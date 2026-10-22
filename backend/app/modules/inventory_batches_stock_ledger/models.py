"""Pydantic models, schemas, and document definitions for Module 5: Inventory, Batches & Stock Ledger.

Follows docs/data-and-stock-rules.md and docs/api-conventions.md:
- Strictly validates store isolation, quantities, units, and dates.
- Documents are declarative data structures (no unintended stock mutations on model instantiation).
"""

from datetime import date, datetime, timezone
from enum import Enum
from typing import Any, Optional
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


# ==============================================================================
# Enums
# ==============================================================================

class MovementType(str, Enum):
    """Types of stock movements recorded in the authoritative stock ledger."""
    PURCHASE_IN = "PURCHASE_IN"            # Confirmed purchase inward
    SALES_REPORT_OUT = "SALES_REPORT_OUT"  # Confirmed end-of-day sales report deduction
    RETURN_IN = "RETURN_IN"                # Customer return inward
    RETURN_OUT = "RETURN_OUT"              # Supplier return outward
    ADJUSTMENT_ADD = "ADJUSTMENT_ADD"      # Physical count surplus or manual correction (+)
    ADJUSTMENT_SUBTRACT = "ADJUSTMENT_SUBTRACT"  # Damage, loss, count deficit (-)
    REVERSAL = "REVERSAL"                  # Reversal of a prior incorrect movement


class SourceDocumentType(str, Enum):
    """Source documents that can initiate or reference a stock transaction."""
    PURCHASE_INVOICE = "PURCHASE_INVOICE"
    SALES_REPORT = "SALES_REPORT"
    STOCK_AUDIT = "STOCK_AUDIT"
    MANUAL_ADJUSTMENT = "MANUAL_ADJUSTMENT"
    CUSTOMER_RETURN = "CUSTOMER_RETURN"
    SUPPLIER_RETURN = "SUPPLIER_RETURN"


class UnitOfMeasure(str, Enum):
    """Standardized unit measurements used in the pharmacy inventory."""
    TABLET = "TABLET"
    CAPSULE = "CAPSULE"
    STRIP = "STRIP"
    BOX = "BOX"
    BOTTLE = "BOTTLE"
    VIAL = "VIAL"
    AMPOULE = "AMPOULE"
    TUBE = "TUBE"
    SACHET = "SACHET"
    PIECE = "PIECE"
    ML = "ML"
    GM = "GM"


class AuditType(str, Enum):
    """Types of physical inventory audit procedures."""
    FULL_AUDIT = "FULL_AUDIT"
    CYCLE_COUNT = "CYCLE_COUNT"
    CATEGORY_COUNT = "CATEGORY_COUNT"
    HIGH_VALUE_AUDIT = "HIGH_VALUE_AUDIT"


class AuditStatus(str, Enum):
    """Operational lifecycle statuses for an audit session."""
    PLANNED = "PLANNED"
    IN_PROGRESS = "IN_PROGRESS"
    UNDER_REVIEW = "UNDER_REVIEW"
    RECONCILED = "RECONCILED"
    CANCELLED = "CANCELLED"


class DiscrepancyReason(str, Enum):
    """Justification codes for variance between physical count and system ledger."""
    NORMAL_DISCREPANCY = "NORMAL_DISCREPANCY"
    DAMAGE = "DAMAGE"
    EXPIRED_UNRECORDED = "EXPIRED_UNRECORDED"
    THEFT_SHRINKAGE = "THEFT_SHRINKAGE"
    SURPLUS_FOUND = "SURPLUS_FOUND"
    PACKING_MISMATCH = "PACKING_MISMATCH"
    OTHER = "OTHER"


# ==============================================================================
# Helper / Embedded Schemas
# ==============================================================================

class SourceDocumentReference(BaseModel):
    """Reference to the source invoice, report, or workflow causing the movement."""
    model_config = ConfigDict(extra="ignore")

    document_type: SourceDocumentType = Field(..., description="Type of source document")
    document_id: str = Field(..., min_length=1, max_length=128, description="Primary ID of the source document")
    document_number: Optional[str] = Field(None, max_length=128, description="Human-readable invoice/report number")
    line_id: Optional[str] = Field(None, max_length=128, description="Specific line or item ID within document")
    document_date: Optional[date] = Field(None, description="Date on source invoice or sales report")

    @field_validator("document_id", mode="before")
    @classmethod
    def validate_document_id(cls, v: Any) -> str:
        if not isinstance(v, str) or not v.strip():
            raise ValueError("document_id must be a non-empty string")
        return v.strip()


class ProductSummary(BaseModel):
    """Minimal catalogue product representation required for inventory management."""
    model_config = ConfigDict(extra="ignore")

    product_id: str = Field(..., min_length=1, max_length=128, description="Catalogue product ID")
    name: str = Field(..., min_length=1, max_length=256, description="Medicine or product name")
    base_unit: str = Field(default="TABLET", description="Canonical base unit for all stock tracking")
    pack_unit: Optional[str] = Field(None, description="Package unit (e.g. STRIP)")
    conversion_factor: float = Field(default=1.0, gt=0, description="Conversion multiplier to base unit")

    @field_validator("product_id", "name", mode="before")
    @classmethod
    def validate_non_empty(cls, v: Any) -> str:
        if not isinstance(v, str) or not v.strip():
            raise ValueError("Field cannot be empty or whitespace")
        return v.strip()

    @field_validator("base_unit", mode="before")
    @classmethod
    def normalize_unit(cls, v: Any) -> str:
        if isinstance(v, str):
            return v.strip().upper()
        return "TABLET"


# ==============================================================================
# Batch Schemas & Document Structure
# ==============================================================================

class BatchBase(BaseModel):
    """Base fields common to batch requests and storage."""
    model_config = ConfigDict(extra="ignore")

    store_id: Optional[str] = Field(None, max_length=128, description="Store identifier for isolation")
    product_id: str = Field(..., min_length=1, max_length=128, description="Catalogue product identifier")
    batch_number: str = Field(..., min_length=1, max_length=64, description="Manufacturer batch or lot number")
    expiry_date: date = Field(..., description="Batch expiry date (YYYY-MM-DD)")
    mrp: Optional[float] = Field(None, ge=0, description="Maximum Retail Price per pack/unit in INR")
    purchase_rate: Optional[float] = Field(None, ge=0, description="Purchase cost rate in INR")
    base_unit: str = Field(default="TABLET", description="Base unit for batch quantities")

    @field_validator("store_id", mode="before")
    @classmethod
    def validate_store_id(cls, v: Any) -> Optional[str]:
        if v is None:
            return None
        if not isinstance(v, str) or not v.strip():
            raise ValueError("Identifier must be a non-empty string")
        return v.strip()

    @field_validator("product_id", mode="before")
    @classmethod
    def validate_product_id(cls, v: Any) -> str:
        if not isinstance(v, str) or not v.strip():
            raise ValueError("Identifier must be a non-empty string")
        return v.strip()

    @field_validator("batch_number", mode="before")
    @classmethod
    def normalize_batch_number(cls, v: Any) -> str:
        if not isinstance(v, str) or not v.strip():
            raise ValueError("batch_number must be a non-empty string")
        return v.strip().upper()

    @field_validator("base_unit", mode="before")
    @classmethod
    def normalize_base_unit(cls, v: Any) -> str:
        if isinstance(v, str) and v.strip():
            return v.strip().upper()
        return "TABLET"


class BatchCreate(BatchBase):
    """Payload for registering a batch (e.g. from Purchase Inward)."""
    initial_quantity: float = Field(default=0.0, ge=0, description="Initial base unit quantity")


class BatchResponse(BatchBase):
    """Batch output returned by API endpoints."""
    id: Optional[str] = Field(None, description="Database ID")
    current_quantity: float = Field(default=0.0, ge=0, description="Current stock in base units")
    is_expired: bool = Field(default=False, description="Computed flag indicating if batch is expired")
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    @model_validator(mode="after")
    def calculate_expired_flag(self) -> "BatchResponse":
        today = datetime.now(timezone.utc).date()
        self.is_expired = self.expiry_date < today
        return self


class BatchDocument(BatchBase):
    """Document structure stored in the 'batches' MongoDB collection."""
    id: Optional[str] = Field(None, alias="_id")
    current_quantity: float = Field(default=0.0, ge=0)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


# ==============================================================================
# Stock Transaction Ledger Models (Authoritative Source of Truth)
# ==============================================================================

class StockTransactionCreate(BaseModel):
    """Payload to post a stock movement to the append-only stock ledger."""
    model_config = ConfigDict(extra="ignore")

    store_id: Optional[str] = Field(None, max_length=128)
    product_id: str = Field(..., min_length=1, max_length=128)
    batch_id: Optional[str] = Field(None, max_length=128, description="Specific batch ID when known")
    batch_number: Optional[str] = Field(None, max_length=64, description="Batch number when known")
    movement_type: MovementType = Field(..., description="Type of stock movement")
    quantity: float = Field(..., description="Signed quantity in base unit (+ for IN, - for OUT)")
    base_unit: str = Field(default="TABLET", description="Canonical base unit")
    entered_quantity: Optional[float] = Field(None, gt=0, description="Quantity entered by user before conversion")
    entered_unit: Optional[str] = Field(None, description="Unit entered by user (e.g. STRIP)")
    conversion_factor: float = Field(default=1.0, gt=0, description="Conversion multiplier applied")
    source_document: SourceDocumentReference = Field(..., description="Source reference for audit traceability")
    idempotency_key: str = Field(..., min_length=1, max_length=128, description="Unique key preventing duplicate processing")
    actor_id: Optional[str] = Field(None, max_length=128, description="User or service performing movement")
    actor_role: Optional[str] = Field(None, max_length=64)
    notes: Optional[str] = Field(None, max_length=512)
    is_inferred: bool = Field(default=False, description="True if batch allocation was inferred via FEFO")

    @field_validator("store_id", mode="before")
    @classmethod
    def validate_store_id(cls, v: Any) -> Optional[str]:
        if v is None:
            return None
        if not isinstance(v, str) or not v.strip():
            raise ValueError("store_id must be a non-empty string")
        return v.strip()

    @field_validator("product_id", "idempotency_key", mode="before")
    @classmethod
    def validate_required_strings(cls, v: Any) -> str:
        if not isinstance(v, str) or not v.strip():
            raise ValueError("Field must be a non-empty string")
        return v.strip()

    @field_validator("batch_number", mode="before")
    @classmethod
    def normalize_batch_num(cls, v: Any) -> Optional[str]:
        if isinstance(v, str) and v.strip():
            return v.strip().upper()
        return None

    @field_validator("base_unit", "entered_unit", mode="before")
    @classmethod
    def normalize_units(cls, v: Any) -> Optional[str]:
        if isinstance(v, str) and v.strip():
            return v.strip().upper()
        return v

    @model_validator(mode="after")
    def validate_movement_sign(self) -> "StockTransactionCreate":
        """Verify that movement type and sign of quantity align."""
        if self.quantity == 0:
            raise ValueError("Stock movement quantity cannot be zero")

        inward_types = {MovementType.PURCHASE_IN, MovementType.RETURN_IN, MovementType.ADJUSTMENT_ADD}
        outward_types = {MovementType.SALES_REPORT_OUT, MovementType.RETURN_OUT, MovementType.ADJUSTMENT_SUBTRACT}

        if self.movement_type in inward_types and self.quantity < 0:
            raise ValueError(f"Quantity for {self.movement_type.value} must be positive")
        if self.movement_type in outward_types and self.quantity > 0:
            raise ValueError(f"Quantity for {self.movement_type.value} must be negative")

        return self


class StockTransactionResponse(BaseModel):
    """Stock ledger transaction representation returned to API consumers."""
    model_config = ConfigDict(extra="ignore")

    id: Optional[str] = Field(None, description="Transaction record ID")
    store_id: str
    product_id: str
    batch_id: Optional[str] = None
    batch_number: Optional[str] = None
    movement_type: MovementType
    quantity: float
    base_unit: str
    entered_quantity: Optional[float] = None
    entered_unit: Optional[str] = None
    conversion_factor: float = 1.0
    source_document: SourceDocumentReference
    idempotency_key: str
    actor_id: Optional[str] = None
    actor_role: Optional[str] = None
    notes: Optional[str] = None
    is_inferred: bool = False
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class StockTransactionDocument(BaseModel):
    """Document structure stored in 'stock_transactions' MongoDB collection."""
    model_config = ConfigDict(extra="ignore")

    id: Optional[str] = Field(None, alias="_id")
    store_id: str
    product_id: str
    batch_id: Optional[str] = None
    batch_number: Optional[str] = None
    movement_type: MovementType
    quantity: float
    base_unit: str
    entered_quantity: Optional[float] = None
    entered_unit: Optional[str] = None
    conversion_factor: float = 1.0
    source_document: SourceDocumentReference
    idempotency_key: str
    actor_id: Optional[str] = None
    actor_role: Optional[str] = None
    notes: Optional[str] = None
    is_inferred: bool = False
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


# ==============================================================================
# Stock Balance Projection Model (Optional derived cache for fast queries)
# ==============================================================================

class StockBalanceResponse(BaseModel):
    """Derived current balance per product and batch for fast read queries."""
    model_config = ConfigDict(extra="ignore")

    store_id: str
    product_id: str
    batch_id: Optional[str] = None
    batch_number: Optional[str] = None
    expiry_date: Optional[date] = None
    current_quantity: float = Field(default=0.0)
    base_unit: str = "TABLET"
    last_transaction_id: Optional[str] = None
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class StockBalanceDocument(BaseModel):
    """Document structure stored in optional 'stock_balances' projection collection."""
    model_config = ConfigDict(extra="ignore")

    id: Optional[str] = Field(None, alias="_id")
    store_id: str
    product_id: str
    batch_id: Optional[str] = None
    batch_number: Optional[str] = None
    expiry_date: Optional[date] = None
    current_quantity: float = Field(default=0.0)
    base_unit: str = "TABLET"
    last_transaction_id: Optional[str] = None
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


# ==============================================================================
# Store Inventory Summary / Aggregates
# ==============================================================================

class ProductInventorySummary(BaseModel):
    """Product-level stock summary aggregating all active batches."""
    model_config = ConfigDict(extra="ignore")

    store_id: str
    product_id: str
    product_name: Optional[str] = None
    total_quantity: float = 0.0
    base_unit: str = "TABLET"
    active_batch_count: int = 0
    earliest_expiry_date: Optional[date] = None
    has_expired_batches: bool = False
    is_low_stock: bool = False


class InventoryListResponse(BaseModel):
    """Paginated list of product stock balances."""
    model_config = ConfigDict(extra="ignore")

    items: list[ProductInventorySummary]
    total: int
    skip: int
    limit: int


class TransactionListResponse(BaseModel):
    """Paginated list of append-only stock ledger transactions."""
    model_config = ConfigDict(extra="ignore")

    items: list[StockTransactionResponse]
    total: int
    skip: int
    limit: int


class InventorySummaryMetrics(BaseModel):
    """Aggregated operational metrics for store inventory overview."""
    model_config = ConfigDict(extra="ignore")

    store_id: str
    total_products: int = 0
    in_stock_units: float = 0.0
    active_batches: int = 0
    expired_batches: int = 0
    low_stock_items: int = 0


class ReversalRequest(BaseModel):
    """Payload to reverse a prior stock transaction."""
    model_config = ConfigDict(extra="ignore")

    original_transaction_id: str = Field(..., min_length=1, max_length=128, description="ID of transaction to reverse")
    idempotency_key: str = Field(..., min_length=1, max_length=128, description="Unique key for reversal transaction")
    reason: str = Field(..., min_length=1, max_length=512, description="Audit reason for reversing transaction")
    actor_id: Optional[str] = Field(None, max_length=128, description="User performing reversal")


# ==============================================================================
# Phase 5: Multi-Unit Conversions & FEFO Allocation Schemas
# ==============================================================================

class UnitConversionRequest(BaseModel):
    """Payload to convert between packaging units and canonical base units."""
    model_config = ConfigDict(extra="ignore")

    product_id: Optional[str] = Field(None, description="Optional catalogue product ID for item-specific conversion")
    from_unit: str = Field(..., min_length=1, description="Source unit (e.g. STRIP, BOX, BOTTLE)")
    to_unit: Optional[str] = Field(default="TABLET", description="Target base unit (default TABLET)")
    quantity: float = Field(..., gt=0, description="Quantity to convert (strictly > 0)")
    custom_factor: Optional[float] = Field(None, gt=0, description="Optional explicit conversion multiplier")

    @field_validator("from_unit", "to_unit", mode="before")
    @classmethod
    def normalize_units(cls, v: Any) -> str:
        if isinstance(v, str) and v.strip():
            return v.strip().upper()
        return "TABLET"


class UnitConversionResponse(BaseModel):
    """Result of unit conversion math."""
    model_config = ConfigDict(extra="ignore")

    from_unit: str
    to_unit: str
    entered_quantity: float
    converted_quantity: float
    conversion_factor: float
    notes: Optional[str] = None


class FefoBatchAllocation(BaseModel):
    """Batch lot slice selected during FEFO auto-allocation."""
    model_config = ConfigDict(extra="ignore")

    batch_id: str = Field(..., description="Database ID of the batch lot")
    batch_number: str = Field(..., description="Lot number")
    expiry_date: date = Field(..., description="Lot expiry date")
    allocated_quantity: float = Field(..., gt=0, description="Base unit quantity allocated from this lot")
    remaining_batch_quantity: float = Field(..., ge=0, description="Quantity remaining in lot after allocation")
    mrp: Optional[float] = None
    purchase_rate: Optional[float] = None
    is_expired: bool = False


class FefoAllocationPreviewRequest(BaseModel):
    """Request payload to simulate/preview FEFO batch allocation for an outward movement."""
    model_config = ConfigDict(extra="ignore")

    product_id: str = Field(..., min_length=1, description="Catalogue product ID")
    quantity: float = Field(..., gt=0, description="Required quantity (positive number)")
    unit: Optional[str] = Field(None, description="Unit of entered quantity (e.g. STRIP, BOX), defaults to product base unit")
    custom_factor: Optional[float] = Field(None, gt=0, description="Custom packaging conversion factor")
    include_expired: bool = Field(default=False, description="Whether expired batches can be allocated (default False)")

    @field_validator("unit", mode="before")
    @classmethod
    def normalize_unit(cls, v: Any) -> Optional[str]:
        if isinstance(v, str) and v.strip():
            return v.strip().upper()
        return None


class FefoAllocationPreviewResponse(BaseModel):
    """Response detailing the simulated FEFO allocation plan."""
    model_config = ConfigDict(extra="ignore")

    store_id: str
    product_id: str
    requested_quantity: float
    requested_unit: str
    base_unit: str
    conversion_factor: float
    base_quantity_required: float
    total_available_unexpired: float
    allocations: list[FefoBatchAllocation]
    is_fully_fulfillable: bool
    shortage: float = 0.0


class FefoDispenseRequest(BaseModel):
    """Request payload to execute an automated FEFO outward sales dispense across active lots."""
    model_config = ConfigDict(extra="ignore")

    product_id: str = Field(..., min_length=1, description="Catalogue product ID")
    quantity: float = Field(..., gt=0, description="Required quantity to dispense (positive number)")
    unit: Optional[str] = Field(None, description="Unit of entered quantity (e.g. STRIP, BOX)")
    custom_factor: Optional[float] = Field(None, gt=0, description="Custom packaging conversion factor")
    source_document: SourceDocumentReference = Field(..., description="Audit reference (e.g. sales report or prescription)")
    idempotency_key: str = Field(..., min_length=1, max_length=128, description="Unique transaction key")
    actor_id: Optional[str] = Field(None, max_length=128)
    notes: Optional[str] = Field(None, max_length=512)
    include_expired: bool = Field(default=False, description="Whether to include expired lots (default False)")


class FefoDispenseResponse(BaseModel):
    """Response returned upon successful multi-batch FEFO outward dispense."""
    model_config = ConfigDict(extra="ignore")

    store_id: str
    product_id: str
    total_dispensed_base_units: float
    base_unit: str
    entered_quantity: float
    entered_unit: str
    conversion_factor: float
    transactions: list[StockTransactionResponse]
    allocations: list[FefoBatchAllocation]


# ==============================================================================
# Phase 6: Expiry Tracking, Near-Expiry Buckets & Waste Minimization Schemas
# ==============================================================================

class ExpiryTier(str, Enum):
    """Categorized risk tiers based on days remaining until expiry."""
    EXPIRED = "EXPIRED"            # Days < 0 (non-dispensable, quarantine required)
    CRITICAL_30 = "CRITICAL_30"    # 0 <= Days <= 30 (immediate action required)
    NEAR_60 = "NEAR_60"            # 31 <= Days <= 60 (high attention tier)
    ATTENTION_90 = "ATTENTION_90"  # 61 <= Days <= 90 (reorder suppression window)
    SAFE = "SAFE"                  # Days > 90 (healthy inventory)


class ExpiryBucketSummary(BaseModel):
    """Aggregated financial and inventory metrics for a specific expiry tier."""
    model_config = ConfigDict(extra="ignore")

    tier: ExpiryTier
    label: str
    days_min: Optional[int] = None
    days_max: Optional[int] = None
    batch_count: int = 0
    total_units: float = 0.0
    total_purchase_value: float = 0.0
    total_mrp_value: float = 0.0


class ExpiryBatchItem(BaseModel):
    """Batch lot detail item enriched with calculated expiry metrics and valuations."""
    model_config = ConfigDict(extra="ignore")

    batch_id: str
    batch_number: str
    product_id: str
    product_name: Optional[str] = None
    expiry_date: date
    days_until_expiry: int
    tier: ExpiryTier
    current_quantity: float
    base_unit: str = "TABLET"
    mrp: Optional[float] = None
    purchase_rate: Optional[float] = None
    at_risk_purchase_value: float = 0.0
    at_risk_mrp_value: float = 0.0


class ExpiryBucketResponse(BaseModel):
    """Comprehensive store expiry status with tier summaries and detailed batch listings."""
    model_config = ConfigDict(extra="ignore")

    store_id: str
    total_active_batches: int = 0
    total_at_risk_units: float = 0.0
    total_at_risk_purchase_value: float = 0.0
    total_at_risk_mrp_value: float = 0.0
    buckets: list[ExpiryBucketSummary]
    batches: list[ExpiryBatchItem]


class SegregateExpiredRequest(BaseModel):
    """Request payload to segregate / quarantine expired medication from active inventory."""
    model_config = ConfigDict(extra="ignore")

    quantity: Optional[float] = Field(None, gt=0, description="Quantity to segregate. If omitted, full balance is segregated.")
    reason: str = Field(..., min_length=1, max_length=512, description="Audit reason for segregation/disposal")
    idempotency_key: str = Field(..., min_length=1, max_length=128, description="Unique transaction key")
    disposal_method: Optional[str] = Field("QUARANTINE_FOR_DISPOSAL", max_length=128)
    actor_id: Optional[str] = Field(None, max_length=128)


class ReturnToSupplierRequest(BaseModel):
    """Request payload to initiate a supplier return for near-expiry or expired medicine lots."""
    model_config = ConfigDict(extra="ignore")

    quantity: float = Field(..., gt=0, description="Quantity to return to supplier")
    supplier_id: str = Field(..., min_length=1, max_length=128, description="Supplier identifier")
    supplier_name: Optional[str] = Field(None, max_length=256, description="Supplier corporate name")
    reason: str = Field(..., min_length=1, max_length=512, description="Reason for returning stock")
    supplier_invoice_reference: Optional[str] = Field(None, max_length=128, description="Original inward purchase invoice #")
    credit_note_reference: Optional[str] = Field(None, max_length=128, description="Supplier credit note #")
    idempotency_key: str = Field(..., min_length=1, max_length=128, description="Unique transaction key")
    actor_id: Optional[str] = Field(None, max_length=128)


# ==============================================================================
# Phase 7: Low Stock Alerts, Reorder Thresholds & Safety Stock Rules
# ==============================================================================

class StockAlertSeverity(str, Enum):
    """Categorized low stock alert severity levels."""
    OUT_OF_STOCK = "OUT_OF_STOCK"              # Available unexpired stock == 0
    CRITICAL_LOW = "CRITICAL_LOW"              # Available unexpired stock <= safety_stock_level
    REORDER_RECOMMENDED = "REORDER_RECOMMENDED"# safety_stock_level < stock <= reorder_point
    ADEQUATE = "ADEQUATE"                      # Stock > reorder_point (healthy inventory)


class ProductThresholdConfig(BaseModel):
    """Reorder and safety stock threshold configuration for a specific product in a store."""
    model_config = ConfigDict(extra="ignore")

    store_id: str
    product_id: str
    product_name: Optional[str] = None
    reorder_point: float = Field(..., ge=0, description="Threshold quantity that triggers reorder alert")
    safety_stock_level: float = Field(..., ge=0, description="Minimum reserve to absorb demand spikes (<= reorder_point)")
    reorder_quantity: float = Field(..., gt=0, description="Default replenishment order size")
    lead_time_days: int = Field(default=2, ge=0, description="Supplier delivery turnaround window in days")
    max_stock_level: Optional[float] = Field(None, ge=0, description="Maximum holding capacity ceiling")
    notes: Optional[str] = Field(None, max_length=512)
    updated_at: Optional[datetime] = None


class UpdateThresholdsRequest(BaseModel):
    """Request payload to set or update reorder thresholds for a product."""
    model_config = ConfigDict(extra="ignore")

    reorder_point: float = Field(..., ge=0, description="Threshold quantity that triggers reorder alert")
    safety_stock_level: float = Field(..., ge=0, description="Minimum reserve level")
    reorder_quantity: float = Field(..., gt=0, description="Default order replenishment size")
    lead_time_days: int = Field(default=2, ge=0, description="Supplier lead time in days")
    max_stock_level: Optional[float] = Field(None, ge=0, description="Maximum holding capacity")
    notes: Optional[str] = Field(None, max_length=512)

    @field_validator("safety_stock_level")
    @classmethod
    def validate_safety_le_reorder(cls, v: float, info: Any) -> float:
        reorder = info.data.get("reorder_point")
        if reorder is not None and v > reorder:
            raise ValueError("safety_stock_level cannot exceed reorder_point")
        return v


class LowStockAlertItem(BaseModel):
    """Product-level low stock status item with safety threshold and replenishment metrics."""
    model_config = ConfigDict(extra="ignore")

    product_id: str
    product_name: str
    category: Optional[str] = None
    base_unit: str = "TABLET"
    current_unexpired_stock: float
    expired_stock: float = 0.0
    total_stock: float
    safety_stock_level: float
    reorder_point: float
    reorder_quantity: float
    lead_time_days: int = 2
    severity: StockAlertSeverity
    suggested_reorder_quantity: float = 0.0
    estimated_unit_cost: float = 0.0
    estimated_reorder_cost: float = 0.0
    active_batch_count: int = 0
    earliest_expiry_date: Optional[date] = None


class LowStockAlertsResponse(BaseModel):
    """Aggregate store low-stock alerts overview with replenishment valuation."""
    model_config = ConfigDict(extra="ignore")

    store_id: str
    total_monitored_products: int = 0
    out_of_stock_count: int = 0
    critical_low_count: int = 0
    reorder_recommended_count: int = 0
    adequate_count: int = 0
    total_estimated_reorder_cost: float = 0.0
    alerts: list[LowStockAlertItem]


# ==============================================================================
# Phase 8: Physical Stock Audit & Cycle Count Schemas
# ==============================================================================

class AuditCountItemCreate(BaseModel):
    """Payload for submitting a counted batch line during physical audit."""
    model_config = ConfigDict(extra="ignore")

    product_id: str = Field(..., min_length=1, max_length=128)
    product_name: Optional[str] = Field(None, max_length=256)
    batch_id: Optional[str] = Field(None, max_length=64)
    batch_number: str = Field(..., min_length=1, max_length=64)
    counted_quantity: float = Field(..., ge=0, description="Physically counted quantity in base units")
    discrepancy_reason: Optional[DiscrepancyReason] = Field(default=DiscrepancyReason.NORMAL_DISCREPANCY)
    notes: Optional[str] = Field(None, max_length=512)
    counted_by: Optional[str] = Field(None, max_length=64)


class AuditCountBatchCreate(BaseModel):
    """Batch submission of physical inventory count items."""
    model_config = ConfigDict(extra="ignore")

    items: list[AuditCountItemCreate] = Field(..., min_length=1)


class AuditCountItemResponse(BaseModel):
    """Response schema for an audit count record."""
    model_config = ConfigDict(extra="ignore")

    id: str
    audit_id: str
    store_id: str
    product_id: str
    product_name: Optional[str] = None
    batch_id: Optional[str] = None
    batch_number: str
    expiry_date: Optional[date] = None
    system_quantity: Optional[float] = None
    counted_quantity: float
    discrepancy_quantity: Optional[float] = None
    unit_cost: Optional[float] = None
    discrepancy_value: Optional[float] = None
    discrepancy_reason: Optional[str] = None
    recount_required: bool = False
    notes: Optional[str] = None
    counted_by: Optional[str] = None
    status: str = "COUNTED"
    created_at: datetime


class AuditSessionCreate(BaseModel):
    """Payload to initiate a new physical audit or cycle count."""
    model_config = ConfigDict(extra="ignore")

    title: str = Field(..., min_length=3, max_length=128, description="Audit session title")
    audit_type: AuditType = Field(default=AuditType.CYCLE_COUNT)
    scope_product_ids: Optional[list[str]] = Field(default=None, description="Optional target product IDs")
    notes: Optional[str] = Field(None, max_length=1024)
    assigned_to: Optional[str] = Field(None, max_length=64)
    created_by: Optional[str] = Field(None, max_length=64)


class AuditSessionResponse(BaseModel):
    """Full detail of an audit session including progress and discrepancy metrics."""
    model_config = ConfigDict(extra="ignore")

    id: str
    store_id: str
    title: str
    audit_type: AuditType
    status: AuditStatus
    scope_product_ids: Optional[list[str]] = None
    total_items_expected: int = 0
    total_items_counted: int = 0
    discrepancy_count: int = 0
    surplus_count: int = 0
    shortage_count: int = 0
    net_variance_value: float = 0.0
    notes: Optional[str] = None
    assigned_to: Optional[str] = None
    created_by: Optional[str] = None
    approved_by: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    reconciled_at: Optional[datetime] = None
    items: Optional[list[AuditCountItemResponse]] = None


class AuditDiscrepancyReport(BaseModel):
    """Variance analysis report prior to final ledger reconciliation."""
    model_config = ConfigDict(extra="ignore")

    audit_id: str
    store_id: str
    title: str
    status: AuditStatus
    total_counted: int = 0
    total_discrepant: int = 0
    total_surplus_value: float = 0.0
    total_shortage_value: float = 0.0
    net_variance_value: float = 0.0
    clean_items_count: int = 0
    discrepant_items: list[AuditCountItemResponse]


class AuditReconcileRequest(BaseModel):
    """Manager approval payload to reconcile physical variances into the stock ledger."""
    model_config = ConfigDict(extra="ignore")

    approved_by: str = Field(..., min_length=1, max_length=64, description="Approving manager/pharmacist ID")
    idempotency_key: str = Field(..., min_length=1, max_length=128, description="Deduplication key")
    notes: Optional[str] = Field(None, max_length=512)


class AuditReconcileResponse(BaseModel):
    """Confirmation of completed variance reconciliation and posted ledger transactions."""
    model_config = ConfigDict(extra="ignore")

    audit_id: str
    status: str
    reconciled_at: datetime
    approved_by: str
    reconciled_items_count: int
    ledger_transactions_posted: int
    total_surplus_qty: float
    total_shortage_qty: float
    net_financial_adjustment: float
    transaction_ids: list[str]


# ==============================================================================
# Relational SQLAlchemy Table Models (PostgreSQL & SQLite)
# ==============================================================================

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Column,
    Date,
    DateTime,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.types import JSON
from app.core.database import Base


class BatchTable(Base):
    """Relational table model for product batch inventory."""
    __tablename__ = "batches"

    id = Column(String(64), primary_key=True)
    store_id = Column(String(32), nullable=False, index=True)
    product_id = Column(String(32), nullable=False, index=True)
    batch_number = Column(String(64), nullable=False)
    expiry_date = Column(Date, nullable=False, index=True)
    mrp = Column(Numeric(10, 2), nullable=False)
    purchase_rate = Column(Numeric(10, 2), nullable=False)
    current_quantity = Column(Numeric(12, 3), nullable=False, default=0.0)
    base_unit = Column(String(32), nullable=False, default="TABLET")
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    __table_args__ = (
        UniqueConstraint("store_id", "product_id", "batch_number", name="uq_batches_store_product_batch"),
        CheckConstraint("current_quantity >= 0", name="chk_batches_current_quantity_non_negative"),
        Index("idx_batches_fefo", "store_id", "product_id", "expiry_date"),
    )


class StockTransactionTable(Base):
    """Relational table model for the authoritative append-only stock movement ledger."""
    __tablename__ = "stock_transactions"

    id = Column(String(64), primary_key=True)
    store_id = Column(String(32), nullable=False, index=True)
    product_id = Column(String(32), nullable=False, index=True)
    batch_id = Column(String(64), nullable=True, index=True)
    batch_number = Column(String(64), nullable=True)
    movement_type = Column(String(32), nullable=False)
    quantity = Column(Numeric(12, 3), nullable=False)
    base_unit = Column(String(32), nullable=False, default="TABLET")
    entered_quantity = Column(Numeric(12, 3), nullable=True)
    entered_unit = Column(String(32), nullable=False)
    conversion_factor = Column(Numeric(10, 4), nullable=False, default=1.0)
    source_document = Column(JSON, nullable=True)
    idempotency_key = Column(String(128), nullable=False)
    is_inferred = Column(Boolean, nullable=False, default=False)
    notes = Column(Text, nullable=True)
    created_by = Column(String(32), nullable=True)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False, index=True)

    __table_args__ = (
        UniqueConstraint("store_id", "idempotency_key", name="uq_stock_transactions_store_idempotency"),
        Index("idx_stock_transactions_audit", "store_id", "product_id", "created_at"),
    )


class StockBalanceTable(Base):
    """Relational table model for stock balance projections."""
    __tablename__ = "stock_balances"

    id = Column(String(64), primary_key=True)
    store_id = Column(String(32), nullable=False, index=True)
    product_id = Column(String(32), nullable=False, index=True)
    batch_number = Column(String(64), nullable=False)
    current_quantity = Column(Numeric(12, 3), nullable=False, default=0.0)
    base_unit = Column(String(32), nullable=False, default="TABLET")
    last_transaction_id = Column(String(64), nullable=True)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    __table_args__ = (
        UniqueConstraint("store_id", "product_id", "batch_number", name="uq_stock_balances_store_product_batch"),
    )


class InventoryThresholdTable(Base):
    """Relational table model for store-specific product reorder and safety stock rules."""
    __tablename__ = "inventory_thresholds"

    id = Column(String(64), primary_key=True)
    store_id = Column(String(32), nullable=False, index=True)
    product_id = Column(String(32), nullable=False, index=True)
    reorder_point = Column(Numeric(10, 2), nullable=False, default=50.0)
    safety_stock_level = Column(Numeric(10, 2), nullable=False, default=20.0)
    reorder_quantity = Column(Numeric(10, 2), nullable=False, default=100.0)
    lead_time_days = Column(Integer, nullable=False, default=2)
    max_stock_level = Column(Numeric(10, 2), nullable=True)
    notes = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    __table_args__ = (
        UniqueConstraint("store_id", "product_id", name="uq_inventory_thresholds_store_product"),
        CheckConstraint("safety_stock_level <= reorder_point", name="chk_inventory_thresholds_safety_le_reorder"),
    )


class AuditSessionTable(Base):
    """Relational table model for physical stock audits and cycle counts."""
    __tablename__ = "audit_sessions"

    id = Column(String(64), primary_key=True)
    store_id = Column(String(32), nullable=False, index=True)
    title = Column(String(128), nullable=False)
    audit_type = Column(String(32), nullable=False, default="CYCLE_COUNT")
    status = Column(String(32), nullable=False, default="PLANNED", index=True)
    scope_product_ids = Column(JSON, nullable=True)
    total_items_expected = Column(Integer, nullable=False, default=0)
    total_items_counted = Column(Integer, nullable=False, default=0)
    discrepancy_count = Column(Integer, nullable=False, default=0)
    surplus_count = Column(Integer, nullable=False, default=0)
    shortage_count = Column(Integer, nullable=False, default=0)
    net_variance_value = Column(Numeric(12, 2), nullable=False, default=0.0)
    notes = Column(Text, nullable=True)
    assigned_to = Column(String(64), nullable=True)
    created_by = Column(String(64), nullable=True)
    approved_by = Column(String(64), nullable=True)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    reconciled_at = Column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        Index("idx_audit_sessions_store_status", "store_id", "status"),
    )


class AuditCountItemTable(Base):
    """Relational table model for individual counted batch lots within an audit session."""
    __tablename__ = "audit_count_items"

    id = Column(String(64), primary_key=True)
    audit_id = Column(String(64), nullable=False, index=True)
    store_id = Column(String(32), nullable=False, index=True)
    product_id = Column(String(32), nullable=False, index=True)
    product_name = Column(String(256), nullable=True)
    batch_id = Column(String(64), nullable=True, index=True)
    batch_number = Column(String(64), nullable=False)
    expiry_date = Column(Date, nullable=True)
    system_quantity = Column(Numeric(12, 3), nullable=False, default=0.0)
    counted_quantity = Column(Numeric(12, 3), nullable=False, default=0.0)
    discrepancy_quantity = Column(Numeric(12, 3), nullable=False, default=0.0)
    unit_cost = Column(Numeric(10, 2), nullable=False, default=0.0)
    discrepancy_value = Column(Numeric(12, 2), nullable=False, default=0.0)
    discrepancy_reason = Column(String(64), nullable=True, default="NORMAL_DISCREPANCY")
    recount_required = Column(Boolean, nullable=False, default=False)
    notes = Column(Text, nullable=True)
    counted_by = Column(String(64), nullable=True)
    status = Column(String(32), nullable=False, default="COUNTED")
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    __table_args__ = (
        UniqueConstraint("audit_id", "product_id", "batch_number", name="uq_audit_count_items_audit_product_batch"),
        Index("idx_audit_count_items_audit_discrepancy", "audit_id", "discrepancy_quantity"),
    )




