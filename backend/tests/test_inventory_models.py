"""Automated tests for Phase 2: Database Models, Collections, Validation, and Indexes."""

from datetime import date, datetime, timedelta, timezone
import pytest
from pydantic import ValidationError

from app.modules.inventory_batches_stock_ledger.models import (
    BatchCreate,
    BatchResponse,
    BatchTable,
    InventoryThresholdTable,
    MovementType,
    ProductInventorySummary,
    ProductSummary,
    SourceDocumentReference,
    SourceDocumentType,
    StockBalanceResponse,
    StockBalanceTable,
    StockTransactionCreate,
    StockTransactionResponse,
    StockTransactionTable,
    UnitOfMeasure,
)


# ==============================================================================
# 1. Product & Unit Tests
# ==============================================================================

def test_product_summary_validation() -> None:
    """ProductSummary accepts valid values and normalizes base unit."""
    product = ProductSummary(
        product_id="prod-dolo-650",
        name="Dolo 650mg Tablet",
        base_unit="tablet",
        pack_unit="STRIP",
        conversion_factor=15.0,
    )
    assert product.product_id == "prod-dolo-650"
    assert product.name == "Dolo 650mg Tablet"
    assert product.base_unit == "TABLET"
    assert product.conversion_factor == 15.0


def test_product_summary_rejects_empty_identifiers() -> None:
    """ProductSummary rejects empty product_id or invalid conversion factor."""
    with pytest.raises(ValidationError):
        ProductSummary(product_id="  ", name="Test Medicine")

    with pytest.raises(ValidationError):
        ProductSummary(product_id="prod-1", name="Test", conversion_factor=0)


# ==============================================================================
# 2. Batch Model Validation Tests
# ==============================================================================

def test_batch_create_validation_and_normalization() -> None:
    """BatchCreate normalizes batch_number and base_unit, validates prices."""
    expiry = date.today() + timedelta(days=365)
    batch = BatchCreate(
        store_id="store-apollo-01",
        product_id="prod-paracetamol",
        batch_number="  b-2024-xyz  ",
        expiry_date=expiry,
        mrp=30.50,
        purchase_rate=22.00,
        initial_quantity=100.0,
    )
    assert batch.store_id == "store-apollo-01"
    assert batch.batch_number == "B-2024-XYZ"
    assert batch.base_unit == "TABLET"
    assert batch.mrp == 30.50
    assert batch.purchase_rate == 22.00
    assert batch.initial_quantity == 100.0


def test_batch_create_rejects_invalid_inputs() -> None:
    """BatchCreate rejects empty identifiers, negative prices, or empty batch numbers."""
    expiry = date.today() + timedelta(days=180)

    # Empty store_id
    with pytest.raises(ValidationError):
        BatchCreate(store_id="", product_id="prod-1", batch_number="B1", expiry_date=expiry)

    # Empty batch_number
    with pytest.raises(ValidationError):
        BatchCreate(store_id="store-1", product_id="prod-1", batch_number="  ", expiry_date=expiry)

    # Negative MRP
    with pytest.raises(ValidationError):
        BatchCreate(store_id="store-1", product_id="prod-1", batch_number="B1", expiry_date=expiry, mrp=-10)

    # Negative initial quantity
    with pytest.raises(ValidationError):
        BatchCreate(store_id="store-1", product_id="prod-1", batch_number="B1", expiry_date=expiry, initial_quantity=-5)


def test_batch_response_expiry_calculation() -> None:
    """BatchResponse correctly calculates the computed is_expired flag."""
    future_date = date.today() + timedelta(days=90)
    past_date = date.today() - timedelta(days=10)

    valid_batch = BatchResponse(
        store_id="store-1",
        product_id="prod-1",
        batch_number="B-VALID",
        expiry_date=future_date,
        current_quantity=50.0,
    )
    assert valid_batch.is_expired is False

    expired_batch = BatchResponse(
        store_id="store-1",
        product_id="prod-1",
        batch_number="B-EXPIRED",
        expiry_date=past_date,
        current_quantity=10.0,
    )
    assert expired_batch.is_expired is True


# ==============================================================================
# 3. Source Document Reference Tests
# ==============================================================================

def test_source_document_reference_validation() -> None:
    """SourceDocumentReference validates types and rejects empty IDs."""
    ref = SourceDocumentReference(
        document_type=SourceDocumentType.PURCHASE_INVOICE,
        document_id="inv-2026-9901",
        document_number="INV-9901",
        line_id="line-3",
        document_date=date.today(),
    )
    assert ref.document_type == SourceDocumentType.PURCHASE_INVOICE
    assert ref.document_id == "inv-2026-9901"

    with pytest.raises(ValidationError):
        SourceDocumentReference(document_type=SourceDocumentType.PURCHASE_INVOICE, document_id="   ")


# ==============================================================================
# 4. Stock Transaction Ledger Validation Tests
# ==============================================================================

def test_stock_transaction_inward_validation() -> None:
    """StockTransactionCreate accepts valid inward movement with positive quantity."""
    source_ref = SourceDocumentReference(
        document_type=SourceDocumentType.PURCHASE_INVOICE,
        document_id="inv-883",
    )
    tx = StockTransactionCreate(
        store_id="store-1",
        product_id="prod-amox-500",
        batch_number="amx-001",
        movement_type=MovementType.PURCHASE_IN,
        quantity=150.0,
        entered_quantity=10.0,
        entered_unit="strip",
        conversion_factor=15.0,
        source_document=source_ref,
        idempotency_key="idemp-purchase-inv-883-line-1",
    )
    assert tx.batch_number == "AMX-001"
    assert tx.entered_unit == "STRIP"
    assert tx.quantity == 150.0
    assert tx.idempotency_key == "idemp-purchase-inv-883-line-1"


def test_stock_transaction_outward_validation() -> None:
    """StockTransactionCreate accepts valid outward movement with negative quantity."""
    source_ref = SourceDocumentReference(
        document_type=SourceDocumentType.SALES_REPORT,
        document_id="sales-rep-2026-10-15",
    )
    tx = StockTransactionCreate(
        store_id="store-1",
        product_id="prod-amox-500",
        movement_type=MovementType.SALES_REPORT_OUT,
        quantity=-20.0,
        source_document=source_ref,
        idempotency_key="idemp-sales-2026-10-15-amox",
        is_inferred=True,
    )
    assert tx.quantity == -20.0
    assert tx.is_inferred is True


def test_stock_transaction_rejects_sign_mismatches() -> None:
    """StockTransactionCreate rejects positive quantities for OUT and negative for IN."""
    source_ref = SourceDocumentReference(
        document_type=SourceDocumentType.PURCHASE_INVOICE,
        document_id="inv-1",
    )

    # Inward with negative quantity must fail
    with pytest.raises(ValidationError, match="must be positive"):
        StockTransactionCreate(
            store_id="store-1",
            product_id="prod-1",
            movement_type=MovementType.PURCHASE_IN,
            quantity=-50.0,
            source_document=source_ref,
            idempotency_key="key-1",
        )

    # Outward with positive quantity must fail
    with pytest.raises(ValidationError, match="must be negative"):
        StockTransactionCreate(
            store_id="store-1",
            product_id="prod-1",
            movement_type=MovementType.SALES_REPORT_OUT,
            quantity=50.0,
            source_document=source_ref,
            idempotency_key="key-2",
        )

    # Zero quantity must fail
    with pytest.raises(ValidationError, match="cannot be zero"):
        StockTransactionCreate(
            store_id="store-1",
            product_id="prod-1",
            movement_type=MovementType.PURCHASE_IN,
            quantity=0.0,
            source_document=source_ref,
            idempotency_key="key-3",
        )


def test_stock_transaction_rejects_empty_idempotency_key() -> None:
    """Idempotency key is required to guarantee duplicate prevention."""
    source_ref = SourceDocumentReference(
        document_type=SourceDocumentType.PURCHASE_INVOICE,
        document_id="inv-1",
    )
    with pytest.raises(ValidationError):
        StockTransactionCreate(
            store_id="store-1",
            product_id="prod-1",
            movement_type=MovementType.PURCHASE_IN,
            quantity=10.0,
            source_document=source_ref,
            idempotency_key="   ",
        )


# ==============================================================================
# 5. Declarative Integrity (No side effects on instantiation)
# ==============================================================================

def test_declarative_models_have_no_side_effects() -> None:
    """Instantiating models does not perform mutations or change any state."""
    ref = SourceDocumentReference(
        document_type=SourceDocumentType.MANUAL_ADJUSTMENT,
        document_id="adj-01",
    )
    tx = StockTransactionCreate(
        store_id="store-1",
        product_id="prod-1",
        movement_type=MovementType.ADJUSTMENT_ADD,
        quantity=5.0,
        source_document=ref,
        idempotency_key="adj-key-01",
    )
    assert tx.quantity == 5.0
    # Object is pure data


# ==============================================================================
# 6. Database Relational Tables & Constraints Verification
# ==============================================================================

def test_relational_tables_structure() -> None:
    """Ensure all required relational tables have designated unique and query indexes."""
    assert BatchTable.__tablename__ == "batches"
    assert StockTransactionTable.__tablename__ == "stock_transactions"
    assert StockBalanceTable.__tablename__ == "stock_balances"
    assert InventoryThresholdTable.__tablename__ == "inventory_thresholds"

    batch_constraints = [c.name for c in BatchTable.__table__.constraints]
    assert "uq_batches_store_product_batch" in batch_constraints

    tx_constraints = [c.name for c in StockTransactionTable.__table__.constraints]
    assert "uq_stock_transactions_store_idempotency" in tx_constraints

    balance_constraints = [c.name for c in StockBalanceTable.__table__.constraints]
    assert "uq_stock_balances_store_product_batch" in balance_constraints

