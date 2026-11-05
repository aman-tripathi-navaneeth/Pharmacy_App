"""API router for Module 5: Inventory, Batches & Stock Ledger.

Exclusively powered by PostgreSQL / relational SQLAlchemy async sessions.
Provides 100% contract compatibility with Flutter client.
"""

from typing import Any, Optional

from fastapi import APIRouter, HTTPException, Query, Request, status

from app.core.database import get_session_factory
from app.modules.inventory_batches_stock_ledger.models import (
    AuditCountBatchCreate,
    AuditDiscrepancyReport,
    AuditReconcileRequest,
    AuditReconcileResponse,
    AuditSessionCreate,
    AuditSessionResponse,
    AuditStatus,
    AuditType,
    BatchCreate,
    BatchResponse,
    ExpiryBucketResponse,
    ExpiryTier,
    FefoAllocationPreviewRequest,
    FefoAllocationPreviewResponse,
    FefoDispenseRequest,
    FefoDispenseResponse,
    InventoryListResponse,
    InventorySummaryMetrics,
    LowStockAlertsResponse,
    MovementType,
    ProductThresholdConfig,
    ReturnToSupplierRequest,
    ReversalRequest,
    SegregateExpiredRequest,
    SourceDocumentType,
    StockAlertSeverity,
    StockTransactionCreate,
    StockTransactionResponse,
    TransactionListResponse,
    UnitConversionRequest,
    UnitConversionResponse,
    UpdateThresholdsRequest,
)
from app.modules.inventory_batches_stock_ledger.sql_repository import InventorySqlRepository

router = APIRouter(prefix="/stores/{store_id}", tags=["Inventory, Batches & Stock Ledger"])


# ==============================================================================
# Connectivity / Health Verification
# ==============================================================================


@router.get("/inventory/connectivity")
async def inventory_connectivity(store_id: str, request: Request) -> dict[str, Any]:
    """Scaffold and connectivity endpoint confirming inventory route registration and DB readiness."""
    engine = getattr(request.app.state, "db_engine", None)
    if engine is None:
        raise HTTPException(
            status_code=503,
            detail={"code": "DATABASE_NOT_CONFIGURED", "message": "Set DATABASE_URL to enable database access"},
        )
    try:
        session_factory = get_session_factory()
        async with session_factory() as session:
            repo = InventorySqlRepository(session)
            return await repo.connectivity_probe(store_id)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=503,
            detail={
                "code": "DATABASE_UNREACHABLE",
                "message": "Database ping failed; check network connection and credentials",
                "error_type": type(exc).__name__,
            },
        )


# ==============================================================================
# Phase 3 Read Endpoints
# ==============================================================================


@router.get("/inventory", response_model=InventoryListResponse)
async def list_inventory(
    store_id: str,
    request: Request,
    search: Optional[str] = Query(None, description="Search by product name or ID"),
    low_stock_only: bool = Query(False, description="Filter for products below threshold"),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
) -> InventoryListResponse:
    """Fetch product-level inventory balances with search, filtering, and active batch counts."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.get_inventory_balances(
            store_id, search=search, low_stock_only=low_stock_only, limit=limit, skip=skip
        )


@router.get("/products/{product_id}/batches", response_model=list[BatchResponse])
async def list_product_batches(
    store_id: str,
    product_id: str,
    request: Request,
    status_filter: Optional[str] = Query(None, alias="status", description="Filter by status (ACTIVE, DEPLETED, EXPIRED, QUARANTINED)"),
) -> list[BatchResponse]:
    """Fetch all batches for a product, sorted strictly by FEFO (earliest expiry first)."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.get_product_batches(store_id, product_id, status_filter=status_filter)


@router.get("/batches/{batch_id}", response_model=BatchResponse)
async def get_batch(
    store_id: str,
    batch_id: str,
    request: Request,
) -> BatchResponse:
    """Fetch details of a single batch by ID with store isolation."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.get_batch_by_id(store_id, batch_id)


@router.get("/inventory/transactions", response_model=TransactionListResponse)
async def list_transactions(
    store_id: str,
    request: Request,
    product_id: Optional[str] = Query(None, description="Filter by product ID"),
    batch_number: Optional[str] = Query(None, description="Filter by batch number"),
    movement_type: Optional[MovementType] = Query(None, description="Filter by movement type"),
    source_document_type: Optional[SourceDocumentType] = Query(None, description="Filter by document type"),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
) -> TransactionListResponse:
    """Audit ledger endpoint: fetch immutable stock transactions in reverse chronological order."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.get_transactions(
            store_id,
            product_id=product_id,
            batch_number=batch_number,
            movement_type=movement_type.value if movement_type else None,
            source_document_type=source_document_type.value if source_document_type else None,
            limit=limit,
            skip=skip,
        )


@router.get("/inventory/summary", response_model=InventorySummaryMetrics)
async def get_inventory_summary(
    store_id: str,
    request: Request,
) -> InventorySummaryMetrics:
    """Aggregate KPI metrics for inventory dashboard."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.get_inventory_summary(store_id)


# ==============================================================================
# Phase 4 Mutation Endpoints
# ==============================================================================


@router.post("/batches", response_model=BatchResponse, status_code=status.HTTP_201_CREATED)
async def register_batch(
    store_id: str,
    payload: BatchCreate,
    request: Request,
) -> BatchResponse:
    """Register a new batch/lot for a product."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.register_batch(store_id, payload)


@router.post("/inventory/movements", response_model=StockTransactionResponse, status_code=status.HTTP_201_CREATED)
async def post_stock_movement(
    store_id: str,
    payload: StockTransactionCreate,
    request: Request,
) -> StockTransactionResponse:
    """Phase 4: Post stock movement."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.post_stock_movement(store_id, payload)


@router.post("/inventory/movements/reversal", response_model=StockTransactionResponse, status_code=status.HTTP_201_CREATED)
async def post_reversal(
    store_id: str,
    payload: ReversalRequest,
    request: Request,
) -> StockTransactionResponse:
    """Phase 4: Post compensating reversal transaction."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.reverse_transaction(store_id, payload)


# ==============================================================================
# Phase 5 FEFO & Unit Conversion Endpoints
# ==============================================================================


STANDARD_CONVERSIONS = {
    ("STRIP", "TABLET"): 10.0,
    ("STRIP", "CAPSULE"): 10.0,
    ("BOX", "TABLET"): 100.0,
    ("BOX", "CAPSULE"): 100.0,
    ("BOX", "STRIP"): 10.0,
    ("BOTTLE", "ML"): 100.0,
    ("VIAL", "ML"): 10.0,
    ("PACK", "PIECE"): 10.0,
}


@router.post("/inventory/conversions", response_model=UnitConversionResponse)
async def convert_units(
    store_id: str,
    payload: UnitConversionRequest,
    request: Request,
) -> UnitConversionResponse:
    """Phase 5: Convert packaging units into primary dispensing base units."""
    from_u = payload.from_unit.upper().strip()
    to_u = payload.to_unit.upper().strip()

    if from_u == to_u:
        factor = 1.0
        note = "Identical units (1:1 conversion)"
    elif payload.custom_factor is not None and float(payload.custom_factor) > 0:
        factor = float(payload.custom_factor)
        note = f"Applied custom conversion factor: {factor}x"
    elif (from_u, to_u) in STANDARD_CONVERSIONS:
        factor = STANDARD_CONVERSIONS[(from_u, to_u)]
        note = "Applied standard pharmacy packaging conversion multiplier"
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "UNSUPPORTED_CONVERSION",
                "message": f"Cannot convert '{from_u}' to '{to_u}' without a custom conversion factor",
            },
        )

    converted_qty = round(payload.quantity * factor, 3)
    return UnitConversionResponse(
        from_unit=from_u,
        to_unit=to_u,
        entered_quantity=payload.quantity,
        conversion_factor=factor,
        converted_quantity=converted_qty,
        notes=note,
    )


@router.post("/inventory/fefo-preview", response_model=FefoAllocationPreviewResponse)
async def preview_fefo_allocation(
    store_id: str,
    payload: FefoAllocationPreviewRequest,
    request: Request,
) -> FefoAllocationPreviewResponse:
    """Phase 5: Dry-run FEFO allocation preview."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.fefo_preview(store_id, payload)


@router.post("/inventory/fefo-dispense", response_model=FefoDispenseResponse, status_code=status.HTTP_201_CREATED)
async def fefo_dispense(
    store_id: str,
    payload: FefoDispenseRequest,
    request: Request,
) -> FefoDispenseResponse:
    """Phase 5: FEFO automated dispense."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.fefo_dispense(store_id, payload)


# ==============================================================================
# Phase 6 Expiry & Returns Endpoints
# ==============================================================================


@router.get("/inventory/expiry-buckets", response_model=ExpiryBucketResponse)
async def get_expiry_buckets(
    store_id: str,
    request: Request,
    tier: Optional[ExpiryTier] = Query(None, description="Optional filter for specific expiry tier"),
) -> ExpiryBucketResponse:
    """Phase 6: Expiry bucket tracking with 5-tier classification."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.get_expiry_buckets(store_id, tier=tier.value if tier else None)


@router.post("/batches/{batch_id}/segregate-expired", response_model=StockTransactionResponse, status_code=status.HTTP_201_CREATED)
async def segregate_expired_batch(
    store_id: str,
    batch_id: str,
    payload: SegregateExpiredRequest,
    request: Request,
) -> StockTransactionResponse:
    """Phase 6: Quarantine and segregate an expired batch."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.segregate_expired(store_id, batch_id, payload)


@router.post("/batches/{batch_id}/return-to-supplier", response_model=StockTransactionResponse, status_code=status.HTTP_201_CREATED)
async def return_to_supplier(
    store_id: str,
    batch_id: str,
    payload: ReturnToSupplierRequest,
    request: Request,
) -> StockTransactionResponse:
    """Phase 6: Return expired or excess batch inventory to supplier."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.return_to_supplier(store_id, batch_id, payload)


# ==============================================================================
# Phase 7 Thresholds & Low-Stock Endpoints
# ==============================================================================


@router.get("/inventory/low-stock-alerts", response_model=LowStockAlertsResponse)
async def get_low_stock_alerts(
    store_id: str,
    request: Request,
    severity: Optional[StockAlertSeverity] = Query(None, description="Filter alerts by severity"),
) -> LowStockAlertsResponse:
    """Phase 7: Fetch low stock alerts with replenishment recommendations."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.get_low_stock_alerts(store_id, severity=severity.value if severity else None)


@router.get("/inventory/thresholds/{product_id}", response_model=ProductThresholdConfig)
async def get_product_thresholds(
    store_id: str,
    product_id: str,
    request: Request,
) -> ProductThresholdConfig:
    """Phase 7: Fetch custom or default threshold configurations for a product."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.get_threshold(store_id, product_id)


@router.post("/inventory/thresholds/{product_id}", response_model=ProductThresholdConfig)
async def update_product_thresholds(
    store_id: str,
    product_id: str,
    payload: UpdateThresholdsRequest,
    request: Request,
) -> ProductThresholdConfig:
    """Phase 7: Create or override reorder threshold configuration for a product."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.upsert_threshold(store_id, product_id, payload)


# ==============================================================================
# Phase 8: Physical Stock Audits, Cycle Counts & Discrepancies
# ==============================================================================

@router.post("/inventory/audits", response_model=AuditSessionResponse, status_code=status.HTTP_201_CREATED)
async def create_audit_session(
    store_id: str,
    payload: AuditSessionCreate,
    request: Request,
) -> AuditSessionResponse:
    """Phase 8: Initiate a physical stock audit or cycle count session."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.create_audit_session(store_id, payload)


@router.get("/inventory/audits", response_model=list[AuditSessionResponse])
async def list_audit_sessions(
    store_id: str,
    request: Request,
    status_filter: Optional[AuditStatus] = Query(None, alias="status", description="Filter by audit status"),
    audit_type: Optional[AuditType] = Query(None, description="Filter by audit type"),
    limit: int = Query(50, ge=1, le=100),
    skip: int = Query(0, ge=0),
) -> list[AuditSessionResponse]:
    """Phase 8: Retrieve audit sessions for the store."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.get_audit_sessions(
            store_id,
            status_filter=status_filter.value if status_filter else None,
            audit_type=audit_type.value if audit_type else None,
            limit=limit,
            skip=skip,
        )


@router.get("/inventory/audits/{audit_id}", response_model=AuditSessionResponse)
async def get_audit_session(
    store_id: str,
    audit_id: str,
    request: Request,
    blind: bool = Query(False, description="Whether to mask system expected quantities for blind counting"),
) -> AuditSessionResponse:
    """Phase 8: Get details and count sheet items of a specific audit session."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.get_audit_session(store_id, audit_id, blind=blind)


@router.post("/inventory/audits/{audit_id}/counts", response_model=AuditSessionResponse)
async def record_audit_counts(
    store_id: str,
    audit_id: str,
    payload: AuditCountBatchCreate,
    request: Request,
) -> AuditSessionResponse:
    """Phase 8: Submit batch physical counts for an in-progress audit."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.record_audit_counts(store_id, audit_id, payload)


@router.get("/inventory/audits/{audit_id}/discrepancies", response_model=AuditDiscrepancyReport)
async def get_audit_discrepancies(
    store_id: str,
    audit_id: str,
    request: Request,
) -> AuditDiscrepancyReport:
    """Phase 8: Generate discrepancy and financial variance report for an audit session."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.get_audit_discrepancies(store_id, audit_id)


@router.post("/inventory/audits/{audit_id}/reconcile", response_model=AuditReconcileResponse)
async def reconcile_audit_session(
    store_id: str,
    audit_id: str,
    payload: AuditReconcileRequest,
    request: Request,
) -> AuditReconcileResponse:
    """Phase 8: Manager approval and atomic posting of discrepancy adjustments to stock ledger."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.reconcile_audit_session(store_id, audit_id, payload)


@router.post("/inventory/audits/{audit_id}/cancel", response_model=AuditSessionResponse)
async def cancel_audit_session(
    store_id: str,
    audit_id: str,
    request: Request,
    reason: Optional[str] = Query(None, description="Optional cancellation reason"),
) -> AuditSessionResponse:
    """Phase 8: Cancel an active or pending audit session."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        repo = InventorySqlRepository(session)
        return await repo.cancel_audit_session(store_id, audit_id, reason=reason)

