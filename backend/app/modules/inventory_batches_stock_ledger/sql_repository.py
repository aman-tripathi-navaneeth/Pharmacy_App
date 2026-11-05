"""Asynchronous PostgreSQL / SQLAlchemy repository for Module 5: Inventory, Batches & Stock Ledger.

Implements all inventory query and transactional business logic via SQLAlchemy AsyncSession:
- Invariant & store isolation enforcement
- Append-only stock ledger recording
- Atomic FEFO lot allocation and overdraft prevention
- Check constraint and unique idempotency deduplication
- 5-tier expiry tracking & 4-tier low stock alert evaluation
"""

from datetime import date, datetime, timezone
import math
from typing import Any, Optional
import uuid

from fastapi import HTTPException, status
from sqlalchemy import delete, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.inventory_batches_stock_ledger.models import (
    AuditCountBatchCreate,
    AuditCountItemCreate,
    AuditCountItemResponse,
    AuditCountItemTable,
    AuditDiscrepancyReport,
    AuditReconcileRequest,
    AuditReconcileResponse,
    AuditSessionCreate,
    AuditSessionResponse,
    AuditSessionTable,
    AuditStatus,
    AuditType,
    BatchCreate,
    BatchResponse,
    BatchTable,
    ExpiryBatchItem,
    ExpiryBucketResponse,
    ExpiryBucketSummary,
    ExpiryTier,
    FefoAllocationPreviewRequest,
    FefoAllocationPreviewResponse,
    FefoBatchAllocation,
    FefoDispenseRequest,
    FefoDispenseResponse,
    InventoryListResponse,
    InventorySummaryMetrics,
    InventoryThresholdTable,
    LowStockAlertItem,
    LowStockAlertsResponse,
    MovementType,
    ProductInventorySummary,
    ProductThresholdConfig,
    ReturnToSupplierRequest,
    ReversalRequest,
    SegregateExpiredRequest,
    SourceDocumentReference,
    SourceDocumentType,
    StockAlertSeverity,
    StockBalanceTable,
    StockTransactionCreate,
    StockTransactionResponse,
    StockTransactionTable,
    TransactionListResponse,
    UnitConversionRequest,
    UnitConversionResponse,
    UpdateThresholdsRequest,
)

STANDARD_UNIT_CONVERSIONS: dict[tuple[str, str], float] = {
    ("STRIP", "TABLET"): 10.0,
    ("STRIP", "CAPSULE"): 10.0,
    ("BOX", "TABLET"): 100.0,
    ("BOX", "CAPSULE"): 100.0,
    ("BOX", "STRIP"): 10.0,
    ("BOTTLE", "ML"): 100.0,
    ("TABLET", "STRIP"): 0.1,
    ("TABLET", "BOX"): 0.01,
    ("STRIP", "BOX"): 0.1,
    ("ML", "BOTTLE"): 0.01,
}


def resolve_conversion(
    from_unit: str,
    to_unit: str,
    custom_factor: Optional[float] = None,
) -> tuple[float, str]:
    """Calculate conversion multiplier and explanatory notes."""
    clean_from = from_unit.strip().upper()
    clean_to = to_unit.strip().upper()

    if custom_factor is not None and custom_factor > 0:
        return float(custom_factor), f"Applied custom conversion factor: 1 {clean_from} = {custom_factor} {clean_to}"

    if clean_from == clean_to:
        return 1.0, f"Identical units ({clean_from})"

    pair = (clean_from, clean_to)
    if pair in STANDARD_UNIT_CONVERSIONS:
        factor = STANDARD_UNIT_CONVERSIONS[pair]
        return factor, f"Applied standard pharmacy packaging conversion: 1 {clean_from} = {factor} {clean_to}"

    return 1.0, f"Default 1:1 conversion applied between {clean_from} and {clean_to}"


class InventorySqlRepository:
    """Encapsulates all relational database operations for Module 5."""

    def __init__(self, session: AsyncSession):
        self.session = session

    # --------------------------------------------------------------------------
    # Connectivity Probe
    # --------------------------------------------------------------------------
    async def connectivity_probe(self, store_id: str) -> dict[str, Any]:
        result = await self.session.execute(select(1))
        val = result.scalar()
        bind = self.session.bind
        dialect_name = bind.dialect.name if bind else "postgresql"
        return {
            "status": "route-ready" if val == 1 else "unhealthy",
            "database_status": "connected",
            "database": f"{dialect_name} - active",
            "store_id": store_id,
            "note": "Inventory module SQL database connectivity verified",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    # --------------------------------------------------------------------------
    # Inventory Balances (Read)
    # --------------------------------------------------------------------------
    async def get_inventory_balances(
        self,
        store_id: str,
        search: Optional[str] = None,
        low_stock_only: bool = False,
        limit: int = 50,
        skip: int = 0,
    ) -> InventoryListResponse:
        stmt = (
            select(BatchTable)
            .where(BatchTable.store_id == store_id)
            .order_by(BatchTable.expiry_date.asc())
        )
        res = await self.session.scalars(stmt)
        batches = list(res.all())

        grouped: dict[str, list[BatchTable]] = {}
        for b in batches:
            grouped.setdefault(b.product_id, []).append(b)

        today = datetime.now(timezone.utc).date()
        items: list[ProductInventorySummary] = []
        for pid, prod_batches in grouped.items():
            total_qty = sum(float(b.current_quantity) for b in prod_batches)
            earliest = None
            has_expired = False
            active_count = 0
            base_unit = "TABLET"

            for b in prod_batches:
                base_unit = b.base_unit
                if b.expiry_date < today:
                    has_expired = True
                if float(b.current_quantity) > 0:
                    active_count += 1
                    if earliest is None or b.expiry_date < earliest:
                        earliest = b.expiry_date

            prod_name = pid.replace("PROD-", "").replace("prod-", "").replace("-", " ").title()
            is_low = total_qty <= 20.0

            if search and search.strip():
                st = search.strip().lower()
                matches_batch = any(st in b.batch_number.lower() for b in prod_batches)
                if st not in pid.lower() and st not in prod_name.lower() and not matches_batch:
                    continue

            if low_stock_only and not is_low:
                continue

            items.append(
                ProductInventorySummary(
                    product_id=pid,
                    product_name=prod_name,
                    store_id=store_id,
                    total_quantity=total_qty,
                    base_unit=base_unit,
                    active_batch_count=active_count,
                    earliest_expiry_date=earliest,
                    has_expired_batches=has_expired,
                    is_low_stock=is_low,
                )
            )

        items.sort(key=lambda x: x.total_quantity, reverse=True)
        items_page = items[skip : skip + limit]
        return InventoryListResponse(
            items=items_page,
            total=len(items),
            limit=limit,
            skip=skip,
        )

    # --------------------------------------------------------------------------
    # Product Batches (FEFO Sorted)
    # --------------------------------------------------------------------------
    async def get_product_batches(
        self,
        store_id: str,
        product_id: str,
        include_zero_stock: bool = True,
        status_filter: Optional[str] = None,
    ) -> list[BatchResponse]:
        stmt = (
            select(BatchTable)
            .where(
                BatchTable.store_id == store_id,
                BatchTable.product_id == product_id,
            )
            .order_by(BatchTable.expiry_date.asc())
        )
        if not include_zero_stock:
            stmt = stmt.where(BatchTable.current_quantity > 0)
        res = await self.session.scalars(stmt)
        batches = res.all()
        return [self._map_batch_to_response(b) for b in batches]

    async def get_batch_by_id(self, store_id: str, batch_id: str) -> BatchResponse:
        clean = batch_id.strip()
        stmt = select(BatchTable).where(
            BatchTable.store_id == store_id,
            (BatchTable.id == clean) | (BatchTable.batch_number == clean.upper()),
        )
        batch = await self.session.scalar(stmt)
        if not batch:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"code": "BATCH_NOT_FOUND", "message": f"Batch '{batch_id}' not found in store '{store_id}'"},
            )
        return self._map_batch_to_response(batch)

    # --------------------------------------------------------------------------
    # Stock Ledger Transactions (Read)
    # --------------------------------------------------------------------------
    async def get_transactions(
        self,
        store_id: str,
        product_id: Optional[str] = None,
        batch_number: Optional[str] = None,
        movement_type: Optional[Any] = None,
        source_document_type: Optional[str] = None,
        limit: int = 50,
        skip: int = 0,
    ) -> TransactionListResponse:
        stmt = select(StockTransactionTable).where(StockTransactionTable.store_id == store_id)
        if product_id and product_id.strip():
            stmt = stmt.where(StockTransactionTable.product_id == product_id.strip())
        if batch_number and batch_number.strip():
            stmt = stmt.where(StockTransactionTable.batch_number == batch_number.strip())
        if movement_type:
            m_val = movement_type.value if hasattr(movement_type, "value") else str(movement_type)
            stmt = stmt.where(StockTransactionTable.movement_type == m_val)

        count_stmt = select(func.count()).select_from(stmt.subquery())
        total_count = await self.session.scalar(count_stmt) or 0

        stmt = stmt.order_by(StockTransactionTable.created_at.desc()).offset(skip).limit(limit)
        res = await self.session.scalars(stmt)
        txs = res.all()

        return TransactionListResponse(
            items=[self._map_tx_to_response(tx) for tx in txs],
            total=total_count,
            limit=limit,
            skip=skip,
        )

    # --------------------------------------------------------------------------
    # Inventory Summary Metrics
    # --------------------------------------------------------------------------
    async def get_inventory_summary(self, store_id: str) -> InventorySummaryMetrics:
        stmt = select(BatchTable).where(BatchTable.store_id == store_id)
        res = await self.session.scalars(stmt)
        batches = list(res.all())

        today = datetime.now(timezone.utc).date()
        distinct_products: set[str] = set()
        in_stock_units = 0.0
        active_batches = 0
        expired_batches = 0
        product_quantities: dict[str, float] = {}

        for b in batches:
            pid = b.product_id
            distinct_products.add(pid)
            qty = float(b.current_quantity)
            in_stock_units += qty
            product_quantities[pid] = product_quantities.get(pid, 0.0) + qty

            if b.expiry_date < today:
                expired_batches += 1
            elif qty > 0:
                active_batches += 1

        low_stock_items = sum(1 for qty in product_quantities.values() if qty <= 20.0)

        return InventorySummaryMetrics(
            store_id=store_id,
            total_products=len(distinct_products),
            in_stock_units=round(in_stock_units, 2),
            active_batches=active_batches,
            expired_batches=expired_batches,
            low_stock_items=low_stock_items,
        )

    # --------------------------------------------------------------------------
    # Register Batch (Write)
    # --------------------------------------------------------------------------
    async def register_batch(self, store_id: str, payload: BatchCreate) -> BatchResponse:
        clean_batch_number = payload.batch_number.strip().upper()

        dup_stmt = select(BatchTable).where(
            BatchTable.store_id == store_id,
            BatchTable.product_id == payload.product_id,
            BatchTable.batch_number == clean_batch_number,
        )
        if await self.session.scalar(dup_stmt):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "code": "BATCH_ALREADY_EXISTS",
                    "message": f"Batch '{clean_batch_number}' already exists for product '{payload.product_id}' in store '{store_id}'",
                },
            )

        batch_id = f"BAT-{uuid.uuid4().hex[:12].upper()}"
        expiry = payload.expiry_date if isinstance(payload.expiry_date, date) else payload.expiry_date.date()

        init_qty = float(payload.initial_quantity)
        new_batch = BatchTable(
            id=batch_id,
            store_id=store_id,
            product_id=payload.product_id,
            batch_number=clean_batch_number,
            expiry_date=expiry,
            mrp=payload.mrp or 0.0,
            purchase_rate=payload.purchase_rate or 0.0,
            current_quantity=init_qty,
            base_unit=payload.base_unit.value if hasattr(payload.base_unit, "value") else str(payload.base_unit),
            is_active=True,
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc),
        )
        self.session.add(new_batch)

        # Log initial inward transaction if initial_quantity > 0
        if init_qty > 0:
            tx_id = f"TXN-{uuid.uuid4().hex[:12].upper()}"
            init_tx = StockTransactionTable(
                id=tx_id,
                store_id=store_id,
                product_id=payload.product_id,
                batch_id=batch_id,
                batch_number=clean_batch_number,
                movement_type=MovementType.PURCHASE_IN.value,
                quantity=init_qty,
                base_unit=new_batch.base_unit,
                entered_quantity=init_qty,
                entered_unit=new_batch.base_unit,
                conversion_factor=1.0,
                source_document={
                    "document_type": SourceDocumentType.PURCHASE_INVOICE.value,
                    "document_id": f"INWARD-{clean_batch_number}",
                    "document_number": f"INWARD-{clean_batch_number}",
                },
                idempotency_key=f"IDEM-INIT-{batch_id}",
                is_inferred=False,
                notes=f"Initial registration for batch {clean_batch_number}",
                created_at=datetime.now(timezone.utc),
            )
            self.session.add(init_tx)

        # Upsert stock_balances
        bal_stmt = select(StockBalanceTable).where(
            StockBalanceTable.store_id == store_id,
            StockBalanceTable.product_id == payload.product_id,
            StockBalanceTable.batch_number == clean_batch_number,
        )
        bal = await self.session.scalar(bal_stmt)
        if not bal:
            bal = StockBalanceTable(
                id=f"BAL-{uuid.uuid4().hex[:12].upper()}",
                store_id=store_id,
                product_id=payload.product_id,
                batch_number=clean_batch_number,
                current_quantity=init_qty,
                base_unit=new_batch.base_unit,
                updated_at=datetime.now(timezone.utc),
            )
            self.session.add(bal)
        else:
            bal.current_quantity = float(bal.current_quantity) + init_qty
            bal.updated_at = datetime.now(timezone.utc)

        await self.session.commit()
        await self.session.refresh(new_batch)
        return self._map_batch_to_response(new_batch)

    # --------------------------------------------------------------------------
    # Stock Movement (Write)
    # --------------------------------------------------------------------------
    async def post_stock_movement(
        self, store_id: str, payload: StockTransactionCreate
    ) -> StockTransactionResponse:
        # Check idempotency duplicate
        idem_stmt = select(StockTransactionTable).where(
            StockTransactionTable.store_id == store_id,
            StockTransactionTable.idempotency_key == payload.idempotency_key,
        )
        existing_tx = await self.session.scalar(idem_stmt)
        if existing_tx:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "code": "DUPLICATE_IDEMPOTENCY_KEY",
                    "message": f"Stock movement with idempotency key '{payload.idempotency_key}' already posted",
                    "existing_transaction_id": existing_tx.id,
                },
            )

        qty = float(payload.quantity)
        m_type = payload.movement_type.value if hasattr(payload.movement_type, "value") else str(payload.movement_type)

        # Validate sign rules
        if m_type in [MovementType.PURCHASE_IN.value, MovementType.RETURN_IN.value, MovementType.ADJUSTMENT_ADD.value]:
            if qty <= 0:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail={"code": "INVALID_SIGN", "message": f"{m_type} requires positive quantity"},
                )
        elif m_type in [MovementType.SALES_REPORT_OUT.value, MovementType.RETURN_OUT.value, MovementType.ADJUSTMENT_SUBTRACT.value]:
            if qty >= 0:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail={"code": "INVALID_SIGN", "message": f"{m_type} requires negative quantity"},
                )

        target_batch: Optional[BatchTable] = None
        allocated_slices: list[dict[str, Any]] = []
        is_inferred = payload.is_inferred

        batch_ident = payload.batch_id or payload.batch_number
        if batch_ident:
            clean_b = batch_ident.strip()
            b_stmt = select(BatchTable).where(
                BatchTable.store_id == store_id,
                BatchTable.product_id == payload.product_id,
                (BatchTable.id == clean_b) | (BatchTable.batch_number == clean_b.upper()),
            )
            target_batch = await self.session.scalar(b_stmt)
            if not target_batch:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail={
                        "code": "BATCH_NOT_FOUND",
                        "message": f"Batch '{batch_ident}' not found in store '{store_id}' for product '{payload.product_id}'",
                    },
                )

            # Prevent negative batch stock on outward movements
            if qty < 0:
                curr_stock = float(target_batch.current_quantity)
                if curr_stock + qty < 0:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail={
                            "code": "INSUFFICIENT_STOCK",
                            "message": f"Insufficient stock in batch '{target_batch.batch_number}'. Available: {curr_stock} {target_batch.base_unit}, requested deduction: {abs(qty)}",
                            "available_quantity": curr_stock,
                            "requested_quantity": abs(qty),
                        },
                    )
        elif qty < 0:
            # Outward without specified batch -> FEFO auto-allocation
            fefo_stmt = (
                select(BatchTable)
                .where(
                    BatchTable.store_id == store_id,
                    BatchTable.product_id == payload.product_id,
                    BatchTable.current_quantity > 0,
                )
                .order_by(BatchTable.expiry_date.asc())
            )
            res = await self.session.scalars(fefo_stmt)
            active_batches = list(res.all())
            today = datetime.now(timezone.utc).date()

            rem_needed = abs(qty)
            for b in active_batches:
                if rem_needed <= 0:
                    break
                if b.expiry_date < today:
                    continue
                avail = float(b.current_quantity)
                take = min(avail, rem_needed)
                allocated_slices.append({
                    "batch": b,
                    "allocated_quantity": take,
                })
                rem_needed -= take

            if rem_needed > 0.0001 or not allocated_slices:
                total_avail = sum(float(b.current_quantity) for b in active_batches if b.expiry_date >= today)
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail={
                        "code": "INSUFFICIENT_STOCK",
                        "message": f"Insufficient unexpired stock for product '{payload.product_id}'. Available: {total_avail}, requested: {abs(qty)}",
                        "available_quantity": total_avail,
                        "requested_quantity": abs(qty),
                        "shortage": rem_needed,
                    },
                )
            is_inferred = True

        now = datetime.now(timezone.utc)

        if allocated_slices:
            primary_tx = None
            for idx, alloc in enumerate(allocated_slices):
                b = alloc["batch"]
                alloc_qty = float(alloc["allocated_quantity"])
                slice_idem = payload.idempotency_key if idx == 0 else f"{payload.idempotency_key}-fefo-{idx}"

                b.current_quantity = float(b.current_quantity) - alloc_qty
                b.updated_at = now

                bal_stmt = select(StockBalanceTable).where(
                    StockBalanceTable.store_id == store_id,
                    StockBalanceTable.product_id == payload.product_id,
                    StockBalanceTable.batch_number == b.batch_number,
                )
                bal = await self.session.scalar(bal_stmt)
                if bal:
                    bal.current_quantity = float(bal.current_quantity) - alloc_qty
                    bal.updated_at = now

                tx_id = f"TXN-{uuid.uuid4().hex[:12].upper()}"
                src_doc = payload.source_document.model_dump() if payload.source_document else {
                    "document_type": SourceDocumentType.SALES_REPORT.value,
                    "document_id": "FEFO-OUT",
                }

                tx = StockTransactionTable(
                    id=tx_id,
                    store_id=store_id,
                    product_id=payload.product_id,
                    batch_id=b.id,
                    batch_number=b.batch_number,
                    movement_type=payload.movement_type.value,
                    quantity=-alloc_qty,
                    base_unit=payload.base_unit.upper(),
                    entered_quantity=float(payload.entered_quantity) if (idx == 0 and payload.entered_quantity is not None) else alloc_qty,
                    entered_unit=payload.entered_unit or payload.base_unit,
                    conversion_factor=float(payload.conversion_factor),
                    source_document=src_doc,
                    idempotency_key=slice_idem,
                    is_inferred=True,
                    notes=f"{payload.notes or ''} [FEFO lot: {b.batch_number}]".strip(),
                    created_by=payload.actor_id,
                    created_at=now,
                )
                self.session.add(tx)
                if idx == 0:
                    primary_tx = tx

            await self.session.commit()
            await self.session.refresh(primary_tx)
            return self._map_tx_to_response(primary_tx)
        else:
            if target_batch:
                target_batch.current_quantity = float(target_batch.current_quantity) + qty
                target_batch.updated_at = now

                bal_stmt = select(StockBalanceTable).where(
                    StockBalanceTable.store_id == store_id,
                    StockBalanceTable.product_id == payload.product_id,
                    StockBalanceTable.batch_number == target_batch.batch_number,
                )
                bal = await self.session.scalar(bal_stmt)
                if bal:
                    bal.current_quantity = float(bal.current_quantity) + qty
                    bal.updated_at = now
                else:
                    bal = StockBalanceTable(
                        id=f"BAL-{uuid.uuid4().hex[:12].upper()}",
                        store_id=store_id,
                        product_id=payload.product_id,
                        batch_number=target_batch.batch_number,
                        current_quantity=float(target_batch.current_quantity),
                        base_unit=target_batch.base_unit,
                        updated_at=now,
                    )
                    self.session.add(bal)

            tx_id = f"TXN-{uuid.uuid4().hex[:12].upper()}"
            src_doc = payload.source_document.model_dump() if payload.source_document else {
                "document_type": SourceDocumentType.MANUAL_ADJUSTMENT.value,
                "document_id": "MANUAL",
            }

            new_tx = StockTransactionTable(
                id=tx_id,
                store_id=store_id,
                product_id=payload.product_id,
                batch_id=target_batch.id if target_batch else payload.batch_id,
                batch_number=target_batch.batch_number if target_batch else payload.batch_number,
                movement_type=m_type,
                quantity=qty,
                base_unit=payload.base_unit.upper(),
                entered_quantity=payload.entered_quantity or abs(qty),
                entered_unit=payload.entered_unit or payload.base_unit,
                conversion_factor=float(payload.conversion_factor),
                source_document=src_doc,
                idempotency_key=payload.idempotency_key,
                is_inferred=is_inferred,
                notes=payload.notes,
                created_by=payload.actor_id,
                created_at=now,
            )
            self.session.add(new_tx)

            await self.session.commit()
            await self.session.refresh(new_tx)
            return self._map_tx_to_response(new_tx)

    # --------------------------------------------------------------------------
    # Reversal (Write)
    # --------------------------------------------------------------------------
    async def reverse_transaction(
        self, store_id: str, payload: ReversalRequest
    ) -> StockTransactionResponse:
        # Check idempotency duplicate
        idem_stmt = select(StockTransactionTable).where(
            StockTransactionTable.store_id == store_id,
            StockTransactionTable.idempotency_key == payload.idempotency_key,
        )
        if await self.session.scalar(idem_stmt):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={"code": "DUPLICATE_IDEMPOTENCY_KEY", "message": "Reversal idempotency key already used"},
            )

        orig_stmt = select(StockTransactionTable).where(
            StockTransactionTable.store_id == store_id,
            StockTransactionTable.id == payload.original_transaction_id.strip(),
        )
        orig_tx = await self.session.scalar(orig_stmt)
        if not orig_tx:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={
                    "code": "TRANSACTION_NOT_FOUND",
                    "message": f"Original transaction '{payload.original_transaction_id}' not found in store '{store_id}'",
                },
            )

        if orig_tx.movement_type == MovementType.REVERSAL.value:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={"code": "CANNOT_REVERSE_REVERSAL", "message": "Cannot reverse an existing reversal"},
            )

        # Check if already reversed
        rev_check = select(StockTransactionTable).where(
            StockTransactionTable.store_id == store_id,
            StockTransactionTable.movement_type == MovementType.REVERSAL.value,
            StockTransactionTable.notes.like(f"%{orig_tx.id}%"),
        )
        if await self.session.scalar(rev_check):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={"code": "ALREADY_REVERSED", "message": "Transaction has already been reversed"},
            )

        rev_qty = -float(orig_tx.quantity)
        target_batch = None
        if orig_tx.batch_id or orig_tx.batch_number:
            b_stmt = select(BatchTable).where(
                BatchTable.store_id == store_id,
                (BatchTable.id == orig_tx.batch_id) | (BatchTable.batch_number == orig_tx.batch_number),
            )
            target_batch = await self.session.scalar(b_stmt)

        if rev_qty < 0 and target_batch:
            avail = float(target_batch.current_quantity)
            if avail + rev_qty < 0:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail={
                        "code": "INSUFFICIENT_STOCK",
                        "message": f"Cannot reverse inward transaction: batch '{target_batch.batch_number}' has insufficient stock. Current: {avail}, required: {abs(rev_qty)}",
                    },
                )

        now = datetime.now(timezone.utc)
        if target_batch:
            target_batch.current_quantity = float(target_batch.current_quantity) + rev_qty
            target_batch.updated_at = now

            bal_stmt = select(StockBalanceTable).where(
                StockBalanceTable.store_id == store_id,
                StockBalanceTable.product_id == orig_tx.product_id,
                StockBalanceTable.batch_number == target_batch.batch_number,
            )
            bal = await self.session.scalar(bal_stmt)
            if bal:
                bal.current_quantity = float(bal.current_quantity) + rev_qty
                bal.updated_at = now

        tx_id = f"TXN-{uuid.uuid4().hex[:12].upper()}"
        reversal_tx = StockTransactionTable(
            id=tx_id,
            store_id=store_id,
            product_id=orig_tx.product_id,
            batch_id=orig_tx.batch_id,
            batch_number=orig_tx.batch_number,
            movement_type=MovementType.REVERSAL.value,
            quantity=rev_qty,
            base_unit=orig_tx.base_unit,
            entered_quantity=abs(rev_qty),
            entered_unit=orig_tx.entered_unit,
            conversion_factor=orig_tx.conversion_factor,
            source_document={
                "document_type": SourceDocumentType.MANUAL_ADJUSTMENT.value,
                "document_id": orig_tx.id,
                "document_number": f"REV-{orig_tx.idempotency_key}",
            },
            idempotency_key=payload.idempotency_key,
            is_inferred=False,
            notes=f"Reversal of transaction {orig_tx.id}: {payload.reason}",
            created_by=payload.actor_id or "PHARMACIST-AUDITOR",
            created_at=now,
        )
        self.session.add(reversal_tx)

        await self.session.commit()
        await self.session.refresh(reversal_tx)
        return self._map_tx_to_response(reversal_tx)

    # --------------------------------------------------------------------------
    # FEFO Preview & Dispense
    # --------------------------------------------------------------------------
    async def fefo_preview(
        self, store_id: str, payload: FefoAllocationPreviewRequest
    ) -> FefoAllocationPreviewResponse:
        today = datetime.now(timezone.utc).date()

        stmt = (
            select(BatchTable)
            .where(
                BatchTable.store_id == store_id,
                BatchTable.product_id == payload.product_id,
                BatchTable.current_quantity > 0,
            )
            .order_by(BatchTable.expiry_date.asc())
        )
        res = await self.session.scalars(stmt)
        batches = list(res.all())

        base_unit = batches[0].base_unit if batches else "TABLET"
        entered_unit = payload.unit or base_unit
        factor, _ = resolve_conversion(entered_unit, base_unit, payload.custom_factor)
        required_base_qty = round(payload.quantity * factor, 4)

        allocations: list[FefoBatchAllocation] = []
        remaining_needed = required_base_qty
        total_allocated = 0.0
        total_unexpired = sum(float(b.current_quantity) for b in batches if b.expiry_date >= today or payload.include_expired)

        for b in batches:
            if remaining_needed <= 0:
                break
            is_exp = b.expiry_date < today
            if is_exp and not payload.include_expired:
                continue

            avail = float(b.current_quantity)
            if avail <= 0:
                continue

            take = min(avail, remaining_needed)
            rem = avail - take
            allocations.append(
                FefoBatchAllocation(
                    batch_id=b.id,
                    batch_number=b.batch_number,
                    expiry_date=b.expiry_date,
                    allocated_quantity=round(take, 3),
                    remaining_batch_quantity=round(rem, 3),
                    mrp=float(b.mrp) if b.mrp is not None else None,
                    purchase_rate=float(b.purchase_rate) if b.purchase_rate is not None else None,
                    is_expired=is_exp,
                )
            )
            remaining_needed -= take
            total_allocated += take

        shortage = max(0.0, round(required_base_qty - total_allocated, 4))
        return FefoAllocationPreviewResponse(
            store_id=store_id,
            product_id=payload.product_id,
            requested_quantity=payload.quantity,
            requested_unit=entered_unit,
            base_unit=base_unit,
            conversion_factor=factor,
            base_quantity_required=required_base_qty,
            total_available_unexpired=round(total_unexpired, 4),
            allocations=allocations,
            is_fully_fulfillable=(shortage == 0.0),
            shortage=shortage,
        )

    async def fefo_dispense(
        self, store_id: str, payload: FefoDispenseRequest
    ) -> FefoDispenseResponse:
        # Check idempotency duplicate
        idem_stmt = select(StockTransactionTable).where(
            StockTransactionTable.store_id == store_id,
            StockTransactionTable.idempotency_key == payload.idempotency_key,
        )
        if await self.session.scalar(idem_stmt):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={"code": "DUPLICATE_IDEMPOTENCY_KEY", "message": f"FEFO dispense with idempotency key '{payload.idempotency_key}' already executed"},
            )

        today = datetime.now(timezone.utc).date()

        stmt = (
            select(BatchTable)
            .where(
                BatchTable.store_id == store_id,
                BatchTable.product_id == payload.product_id,
                BatchTable.current_quantity > 0,
            )
            .order_by(BatchTable.expiry_date.asc())
        )
        res = await self.session.scalars(stmt)
        batches = list(res.all())

        base_unit = batches[0].base_unit if batches else "TABLET"
        entered_unit = payload.unit or base_unit
        factor, _ = resolve_conversion(entered_unit, base_unit, payload.custom_factor)
        required_base_qty = round(payload.quantity * factor, 4)

        # Check total unexpired stock
        unexpired_stock = sum(float(b.current_quantity) for b in batches if b.expiry_date >= today or payload.include_expired)
        if unexpired_stock < required_base_qty:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={
                    "code": "INSUFFICIENT_STOCK",
                    "message": f"Insufficient stock for product '{payload.product_id}'. Available: {unexpired_stock}, required: {required_base_qty} {base_unit}",
                    "available_quantity": unexpired_stock,
                    "requested_quantity": required_base_qty,
                    "shortage": round(required_base_qty - unexpired_stock, 4),
                },
            )

        allocations: list[FefoBatchAllocation] = []
        created_txs: list[StockTransactionResponse] = []
        remaining_needed = required_base_qty
        now = datetime.now(timezone.utc)

        for idx, b in enumerate(batches):
            if remaining_needed <= 0:
                break
            is_exp = b.expiry_date < today
            if is_exp and not payload.include_expired:
                continue

            avail = float(b.current_quantity)
            if avail <= 0:
                continue

            take = min(avail, remaining_needed)
            rem = avail - take
            b.current_quantity = rem
            b.updated_at = now

            # Update stock balance
            bal_stmt = select(StockBalanceTable).where(
                StockBalanceTable.store_id == store_id,
                StockBalanceTable.product_id == payload.product_id,
                StockBalanceTable.batch_number == b.batch_number,
            )
            bal = await self.session.scalar(bal_stmt)
            if bal:
                bal.current_quantity = float(bal.current_quantity) - take
                bal.updated_at = now

            allocations.append(
                FefoBatchAllocation(
                    batch_id=b.id,
                    batch_number=b.batch_number,
                    expiry_date=b.expiry_date,
                    allocated_quantity=round(take, 3),
                    remaining_batch_quantity=round(rem, 3),
                    mrp=float(b.mrp) if b.mrp is not None else None,
                    purchase_rate=float(b.purchase_rate) if b.purchase_rate is not None else None,
                    is_expired=is_exp,
                )
            )

            # Insert outward transaction
            tx_id = f"TXN-{uuid.uuid4().hex[:12].upper()}"
            sub_idem = payload.idempotency_key if len(allocations) == 1 else f"{payload.idempotency_key}-fefo-{len(allocations) - 1}"
            src_doc = payload.source_document.model_dump()

            tx = StockTransactionTable(
                id=tx_id,
                store_id=store_id,
                product_id=payload.product_id,
                batch_id=b.id,
                batch_number=b.batch_number,
                movement_type=MovementType.SALES_REPORT_OUT.value,
                quantity=-take,
                base_unit=base_unit,
                entered_quantity=take / factor,
                entered_unit=entered_unit,
                conversion_factor=factor,
                source_document=src_doc,
                idempotency_key=sub_idem,
                is_inferred=True,
                notes=payload.notes or f"Auto FEFO outward sale allocation from batch {b.batch_number}",
                created_by=payload.actor_id or "PHARMACIST-FEFO",
                created_at=now,
            )
            self.session.add(tx)
            created_txs.append(self._map_tx_to_response(tx))
            remaining_needed -= take

        await self.session.commit()

        total_dispensed = sum(a.allocated_quantity for a in allocations)
        return FefoDispenseResponse(
            store_id=store_id,
            product_id=payload.product_id,
            total_dispensed_base_units=round(total_dispensed, 3),
            base_unit=base_unit,
            entered_quantity=payload.quantity,
            entered_unit=entered_unit,
            conversion_factor=factor,
            transactions=created_txs,
            allocations=allocations,
        )

    # --------------------------------------------------------------------------
    # Expiry Buckets (5-Tier Classification & Valuation)
    # --------------------------------------------------------------------------
    async def get_expiry_buckets(
        self,
        store_id: str,
        tier: Optional[Any] = None,
        product_id: Optional[str] = None,
    ) -> ExpiryBucketResponse:
        today = datetime.now(timezone.utc).date()
        stmt = (
            select(BatchTable)
            .where(BatchTable.store_id == store_id, BatchTable.current_quantity > 0)
            .order_by(BatchTable.expiry_date.asc())
        )
        if product_id and product_id.strip():
            stmt = stmt.where(BatchTable.product_id == product_id.strip())

        res = await self.session.scalars(stmt)
        batches = list(res.all())

        tier_defs = [
            {"tier": ExpiryTier.EXPIRED, "label": "Expired Stock (Quarantine)", "days_min": None, "days_max": -1},
            {"tier": ExpiryTier.CRITICAL_30, "label": "Critical Risk (0-30 days)", "days_min": 0, "days_max": 30},
            {"tier": ExpiryTier.NEAR_60, "label": "High Attention (31-60 days)", "days_min": 31, "days_max": 60},
            {"tier": ExpiryTier.ATTENTION_90, "label": "Medium Attention (61-90 days)", "days_min": 61, "days_max": 90},
            {"tier": ExpiryTier.SAFE, "label": "Healthy Stock (> 90 days)", "days_min": 91, "days_max": None},
        ]

        tier_stats = {
            td["tier"]: {
                "tier": td["tier"],
                "label": td["label"],
                "days_min": td["days_min"],
                "days_max": td["days_max"],
                "batch_count": 0,
                "total_units": 0.0,
                "total_purchase_value": 0.0,
                "total_mrp_value": 0.0,
            }
            for td in tier_defs
        }

        detailed_items: list[ExpiryBatchItem] = []
        total_at_risk_units = 0.0
        total_at_risk_purchase_val = 0.0
        total_at_risk_mrp_val = 0.0

        target_tier = tier.value if hasattr(tier, "value") else (str(tier) if tier else None)

        for b in batches:
            days_remaining = (b.expiry_date - today).days

            if days_remaining < 0:
                item_tier = ExpiryTier.EXPIRED
            elif days_remaining <= 30:
                item_tier = ExpiryTier.CRITICAL_30
            elif days_remaining <= 60:
                item_tier = ExpiryTier.NEAR_60
            elif days_remaining <= 90:
                item_tier = ExpiryTier.ATTENTION_90
            else:
                item_tier = ExpiryTier.SAFE

            qty = float(b.current_quantity)
            mrp = float(b.mrp) if b.mrp is not None else None
            prate = float(b.purchase_rate) if b.purchase_rate is not None else None

            item_purchase_val = round(qty * prate, 2) if prate else 0.0
            item_mrp_val = round(qty * mrp, 2) if mrp else 0.0

            tier_stats[item_tier]["batch_count"] += 1
            tier_stats[item_tier]["total_units"] += qty
            tier_stats[item_tier]["total_purchase_value"] += item_purchase_val
            tier_stats[item_tier]["total_mrp_value"] += item_mrp_val

            if item_tier != ExpiryTier.SAFE:
                total_at_risk_units += qty
                total_at_risk_purchase_val += item_purchase_val
                total_at_risk_mrp_val += item_mrp_val

            if target_tier and item_tier.value != target_tier:
                continue

            detailed_items.append(
                ExpiryBatchItem(
                    batch_id=b.id,
                    batch_number=b.batch_number,
                    product_id=b.product_id,
                    product_name=b.product_id.replace("PROD-", "").replace("prod-", "").replace("-", " ").title(),
                    expiry_date=b.expiry_date,
                    days_until_expiry=days_remaining,
                    tier=item_tier,
                    current_quantity=qty,
                    base_unit=b.base_unit,
                    mrp=mrp,
                    purchase_rate=prate,
                    at_risk_purchase_value=item_purchase_val,
                    at_risk_mrp_value=item_mrp_val,
                )
            )

        detailed_items.sort(key=lambda x: x.days_until_expiry)

        bucket_summaries = [
            ExpiryBucketSummary(
                tier=s["tier"],
                label=s["label"],
                days_min=s["days_min"],
                days_max=s["days_max"],
                batch_count=s["batch_count"],
                total_units=round(s["total_units"], 2),
                total_purchase_value=round(s["total_purchase_value"], 2),
                total_mrp_value=round(s["total_mrp_value"], 2),
            )
            for s in tier_stats.values()
        ]

        return ExpiryBucketResponse(
            store_id=store_id,
            total_active_batches=len(batches),
            total_at_risk_units=round(total_at_risk_units, 2),
            total_at_risk_purchase_value=round(total_at_risk_purchase_val, 2),
            total_at_risk_mrp_value=round(total_at_risk_mrp_val, 2),
            buckets=bucket_summaries,
            batches=detailed_items,
        )

    # --------------------------------------------------------------------------
    # Segregate Expired Stock
    # --------------------------------------------------------------------------
    async def segregate_expired(
        self, store_id: str, batch_id: str, payload: SegregateExpiredRequest
    ) -> StockTransactionResponse:
        # Check idempotency duplicate
        idem_stmt = select(StockTransactionTable).where(
            StockTransactionTable.store_id == store_id,
            StockTransactionTable.idempotency_key == payload.idempotency_key,
        )
        if await self.session.scalar(idem_stmt):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={"code": "DUPLICATE_IDEMPOTENCY_KEY", "message": f"Transaction with idempotency key '{payload.idempotency_key}' already posted"},
            )

        clean = batch_id.strip()
        b_stmt = select(BatchTable).where(
            BatchTable.store_id == store_id,
            (BatchTable.id == clean) | (BatchTable.batch_number == clean.upper()),
        )
        batch = await self.session.scalar(b_stmt)
        if not batch:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"code": "BATCH_NOT_FOUND", "message": f"Batch '{batch_id}' not found in store '{store_id}'"},
            )

        today = datetime.now(timezone.utc).date()
        if batch.expiry_date >= today:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={
                    "code": "BATCH_NOT_EXPIRED",
                    "message": f"Batch '{batch.batch_number}' has not expired yet (Expiry: {batch.expiry_date}, Today: {today}). Use return-to-supplier or standard adjustment instead.",
                },
            )

        avail = float(batch.current_quantity)
        if avail <= 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={"code": "ZERO_STOCK", "message": f"Batch '{batch.batch_number}' already has zero stock"},
            )

        seg_qty = float(payload.quantity) if payload.quantity is not None else avail
        if seg_qty > avail:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={
                    "code": "INSUFFICIENT_STOCK",
                    "message": f"Cannot segregate {seg_qty} units; only {avail} units available in lot '{batch.batch_number}'",
                },
            )

        now = datetime.now(timezone.utc)
        batch.current_quantity = avail - seg_qty
        batch.updated_at = now

        bal_stmt = select(StockBalanceTable).where(
            StockBalanceTable.store_id == store_id,
            StockBalanceTable.product_id == batch.product_id,
            StockBalanceTable.batch_number == batch.batch_number,
        )
        bal = await self.session.scalar(bal_stmt)
        if bal:
            bal.current_quantity = float(bal.current_quantity) - seg_qty
            bal.updated_at = now

        tx_id = f"TXN-{uuid.uuid4().hex[:12].upper()}"
        tx = StockTransactionTable(
            id=tx_id,
            store_id=store_id,
            product_id=batch.product_id,
            batch_id=batch.id,
            batch_number=batch.batch_number,
            movement_type=MovementType.ADJUSTMENT_SUBTRACT.value,
            quantity=-seg_qty,
            base_unit=batch.base_unit,
            entered_quantity=seg_qty,
            entered_unit=batch.base_unit,
            conversion_factor=1.0,
            source_document={
                "document_type": SourceDocumentType.STOCK_AUDIT.value,
                "document_id": f"QUARANTINE-{batch.batch_number}",
                "document_number": f"DISPOSAL-{batch.batch_number}",
            },
            idempotency_key=payload.idempotency_key,
            is_inferred=False,
            notes=f"Expired stock segregation ({payload.disposal_method}): {payload.reason}",
            created_by=payload.actor_id or "PHARMACIST-DISPOSAL",
            created_at=now,
        )
        self.session.add(tx)

        await self.session.commit()
        await self.session.refresh(tx)
        return self._map_tx_to_response(tx)

    # --------------------------------------------------------------------------
    # Return to Supplier
    # --------------------------------------------------------------------------
    async def return_to_supplier(
        self, store_id: str, batch_id: str, payload: ReturnToSupplierRequest
    ) -> StockTransactionResponse:
        # Check idempotency duplicate
        idem_stmt = select(StockTransactionTable).where(
            StockTransactionTable.store_id == store_id,
            StockTransactionTable.idempotency_key == payload.idempotency_key,
        )
        if await self.session.scalar(idem_stmt):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={"code": "DUPLICATE_IDEMPOTENCY_KEY", "message": f"Transaction with idempotency key '{payload.idempotency_key}' already posted"},
            )

        clean = batch_id.strip()
        b_stmt = select(BatchTable).where(
            BatchTable.store_id == store_id,
            (BatchTable.id == clean) | (BatchTable.batch_number == clean.upper()),
        )
        batch = await self.session.scalar(b_stmt)
        if not batch:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"code": "BATCH_NOT_FOUND", "message": f"Batch '{batch_id}' not found in store '{store_id}'"},
            )

        avail = float(batch.current_quantity)
        ret_qty = float(payload.quantity)
        if ret_qty > avail:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={
                    "code": "INSUFFICIENT_STOCK",
                    "message": f"Cannot return {ret_qty} units to supplier; only {avail} units available in lot '{batch.batch_number}'",
                },
            )

        now = datetime.now(timezone.utc)
        batch.current_quantity = avail - ret_qty
        batch.updated_at = now

        bal_stmt = select(StockBalanceTable).where(
            StockBalanceTable.store_id == store_id,
            StockBalanceTable.product_id == batch.product_id,
            StockBalanceTable.batch_number == batch.batch_number,
        )
        bal = await self.session.scalar(bal_stmt)
        if bal:
            bal.current_quantity = float(bal.current_quantity) - ret_qty
            bal.updated_at = now

        tx_id = f"TXN-{uuid.uuid4().hex[:12].upper()}"
        doc_num = payload.credit_note_reference or payload.supplier_invoice_reference or f"RET-{payload.supplier_id}"

        tx = StockTransactionTable(
            id=tx_id,
            store_id=store_id,
            product_id=batch.product_id,
            batch_id=batch.id,
            batch_number=batch.batch_number,
            movement_type=MovementType.RETURN_OUT.value,
            quantity=-ret_qty,
            base_unit=batch.base_unit,
            entered_quantity=ret_qty,
            entered_unit=batch.base_unit,
            conversion_factor=1.0,
            source_document={
                "document_type": SourceDocumentType.SUPPLIER_RETURN.value,
                "document_id": f"SUPPLIER-{payload.supplier_id}",
                "document_number": doc_num.strip().upper(),
            },
            idempotency_key=payload.idempotency_key,
            is_inferred=False,
            notes=f"Supplier return ({payload.supplier_name or payload.supplier_id}): {payload.reason}",
            created_by=payload.actor_id or "PHARMACIST-RETURNS",
            created_at=now,
        )
        self.session.add(tx)

        await self.session.commit()
        await self.session.refresh(tx)
        return self._map_tx_to_response(tx)

    # --------------------------------------------------------------------------
    # Low Stock Alerts & Thresholds
    # --------------------------------------------------------------------------
    async def get_low_stock_alerts(
        self,
        store_id: str,
        severity: Optional[str] = None,
        search: Optional[str] = None,
    ) -> LowStockAlertsResponse:
        today = datetime.now(timezone.utc).date()

        # Fetch all batches for store
        b_stmt = select(BatchTable).where(BatchTable.store_id == store_id)
        res = await self.session.scalars(b_stmt)
        all_batches = list(res.all())

        # Group by product
        grouped: dict[str, list[BatchTable]] = {}
        for b in all_batches:
            grouped.setdefault(b.product_id, []).append(b)

        # Fetch custom thresholds
        t_stmt = select(InventoryThresholdTable).where(
            InventoryThresholdTable.store_id == store_id
        )
        t_res = await self.session.scalars(t_stmt)
        custom_thresholds = {t.product_id: t for t in t_res.all()}

        all_pids = set(grouped.keys()).union(custom_thresholds.keys())

        alerts: list[LowStockAlertItem] = []
        out_of_stock_c = 0
        critical_low_c = 0
        reorder_rec_c = 0
        adequate_c = 0
        total_est_cost = 0.0

        for pid in sorted(all_pids):
            prod_batches = grouped.get(pid, [])
            custom = custom_thresholds.get(pid)

            reorder_point = float(custom.reorder_point) if custom else 50.0
            safety_stock = float(custom.safety_stock_level) if custom else 20.0
            reorder_qty = float(custom.reorder_quantity) if custom else 100.0
            lead_time = custom.lead_time_days if custom else 2

            unexp_stock = 0.0
            exp_stock = 0.0
            total_stock = 0.0
            recent_cost = 0.0
            earliest_exp: Optional[date] = None
            active_count = 0
            base_u = "TABLET"
            prod_name = pid.replace("PROD-", "").replace("prod-", "").replace("-", " ").title()

            for b in prod_batches:
                qty = float(b.current_quantity)
                if qty <= 0:
                    continue

                active_count += 1
                total_stock += qty
                base_u = b.base_unit
                if float(b.purchase_rate or 0) > 0:
                    recent_cost = float(b.purchase_rate)

                if b.expiry_date < today:
                    exp_stock += qty
                else:
                    unexp_stock += qty
                    if earliest_exp is None or b.expiry_date < earliest_exp:
                        earliest_exp = b.expiry_date

            # Evaluate severity
            if unexp_stock <= 0.0001:
                sev = StockAlertSeverity.OUT_OF_STOCK
                out_of_stock_c += 1
            elif unexp_stock <= safety_stock + 0.0001:
                sev = StockAlertSeverity.CRITICAL_LOW
                critical_low_c += 1
            elif unexp_stock <= reorder_point + 0.0001:
                sev = StockAlertSeverity.REORDER_RECOMMENDED
                reorder_rec_c += 1
            else:
                sev = StockAlertSeverity.ADEQUATE
                adequate_c += 1

            suggested = 0.0
            est_cost = 0.0
            if sev != StockAlertSeverity.ADEQUATE:
                suggested = max(reorder_qty, round((reorder_point * 2.0) - unexp_stock, 2))
                est_cost = round(suggested * recent_cost, 2)
                total_est_cost += est_cost

            if severity and severity.strip():
                if sev.value.upper() != severity.strip().upper():
                    continue

            if search and search.strip():
                sq = search.strip().lower()
                if sq not in pid.lower() and sq not in prod_name.lower():
                    continue

            alerts.append(
                LowStockAlertItem(
                    product_id=pid,
                    product_name=prod_name,
                    base_unit=base_u,
                    current_unexpired_stock=round(unexp_stock, 2),
                    expired_stock=round(exp_stock, 2),
                    total_stock=round(total_stock, 2),
                    safety_stock_level=safety_stock,
                    reorder_point=reorder_point,
                    reorder_quantity=reorder_qty,
                    lead_time_days=lead_time,
                    severity=sev,
                    suggested_reorder_quantity=suggested,
                    estimated_unit_cost=recent_cost,
                    estimated_reorder_cost=est_cost,
                    active_batch_count=active_count,
                    earliest_expiry_date=earliest_exp,
                )
            )

        severity_order = {
            StockAlertSeverity.OUT_OF_STOCK: 0,
            StockAlertSeverity.CRITICAL_LOW: 1,
            StockAlertSeverity.REORDER_RECOMMENDED: 2,
            StockAlertSeverity.ADEQUATE: 3,
        }
        alerts.sort(key=lambda a: (severity_order[a.severity], -a.suggested_reorder_quantity))

        return LowStockAlertsResponse(
            store_id=store_id,
            total_monitored_products=len(all_pids),
            out_of_stock_count=out_of_stock_c,
            critical_low_count=critical_low_c,
            reorder_recommended_count=reorder_rec_c,
            adequate_count=adequate_c,
            total_estimated_reorder_cost=round(total_est_cost, 2),
            alerts=alerts,
        )

    async def upsert_threshold(
        self, store_id: str, product_id: str, payload: UpdateThresholdsRequest
    ) -> ProductThresholdConfig:
        if payload.safety_stock_level > payload.reorder_point:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={
                    "code": "INVALID_THRESHOLDS",
                    "message": f"safety_stock_level ({payload.safety_stock_level}) cannot exceed reorder_point ({payload.reorder_point})",
                },
            )

        stmt = select(InventoryThresholdTable).where(
            InventoryThresholdTable.store_id == store_id,
            InventoryThresholdTable.product_id == product_id,
        )
        record = await self.session.scalar(stmt)
        prod_name = product_id.replace("PROD-", "").replace("prod-", "").replace("-", " ").title()

        if not record:
            record = InventoryThresholdTable(
                id=f"{store_id}-{product_id}",
                store_id=store_id,
                product_id=product_id,
                reorder_point=payload.reorder_point,
                safety_stock_level=payload.safety_stock_level,
                reorder_quantity=payload.reorder_quantity,
                lead_time_days=payload.lead_time_days,
                max_stock_level=payload.max_stock_level,
                notes=payload.notes,
                created_at=datetime.now(timezone.utc),
                updated_at=datetime.now(timezone.utc),
            )
            self.session.add(record)
        else:
            record.reorder_point = payload.reorder_point
            record.safety_stock_level = payload.safety_stock_level
            record.reorder_quantity = payload.reorder_quantity
            record.lead_time_days = payload.lead_time_days
            record.max_stock_level = payload.max_stock_level
            record.notes = payload.notes
            record.updated_at = datetime.now(timezone.utc)

        await self.session.commit()
        await self.session.refresh(record)

        return ProductThresholdConfig(
            store_id=record.store_id,
            product_id=record.product_id,
            product_name=prod_name,
            reorder_point=float(record.reorder_point),
            safety_stock_level=float(record.safety_stock_level),
            reorder_quantity=float(record.reorder_quantity),
            lead_time_days=record.lead_time_days,
            max_stock_level=float(record.max_stock_level) if record.max_stock_level is not None else None,
            notes=record.notes,
        )

    async def get_threshold(
        self, store_id: str, product_id: str
    ) -> ProductThresholdConfig:
        stmt = select(InventoryThresholdTable).where(
            InventoryThresholdTable.store_id == store_id,
            InventoryThresholdTable.product_id == product_id,
        )
        record = await self.session.scalar(stmt)
        prod_name = product_id.replace("PROD-", "").replace("prod-", "").replace("-", " ").title()

        if record:
            return ProductThresholdConfig(
                store_id=record.store_id,
                product_id=record.product_id,
                product_name=prod_name,
                reorder_point=float(record.reorder_point),
                safety_stock_level=float(record.safety_stock_level),
                reorder_quantity=float(record.reorder_quantity),
                lead_time_days=record.lead_time_days,
                max_stock_level=float(record.max_stock_level) if record.max_stock_level is not None else None,
                notes=record.notes,
            )

        return ProductThresholdConfig(
            store_id=store_id,
            product_id=product_id,
            product_name=prod_name,
            reorder_point=50.0,
            safety_stock_level=20.0,
            reorder_quantity=100.0,
            lead_time_days=2,
            notes="Standard store default thresholds",
        )

    # --------------------------------------------------------------------------
    # Mapping Helpers
    # --------------------------------------------------------------------------
    def _map_batch_to_response(self, b: BatchTable) -> BatchResponse:
        today = datetime.now(timezone.utc).date()
        return BatchResponse(
            id=b.id,
            store_id=b.store_id,
            product_id=b.product_id,
            batch_number=b.batch_number,
            expiry_date=b.expiry_date,
            mrp=float(b.mrp) if b.mrp is not None else None,
            purchase_rate=float(b.purchase_rate) if b.purchase_rate is not None else None,
            current_quantity=float(b.current_quantity),
            base_unit=b.base_unit,
            is_expired=(b.expiry_date < today),
            created_at=b.created_at,
            updated_at=b.updated_at,
        )

    def _map_tx_to_response(self, tx: StockTransactionTable) -> StockTransactionResponse:
        src_raw = tx.source_document
        if isinstance(src_raw, dict) and src_raw:
            doc_type_val = src_raw.get("document_type", SourceDocumentType.MANUAL_ADJUSTMENT.value)
            try:
                doc_type = SourceDocumentType(doc_type_val)
            except ValueError:
                doc_type = SourceDocumentType.MANUAL_ADJUSTMENT
            src_doc = SourceDocumentReference(
                document_type=doc_type,
                document_id=str(src_raw.get("document_id") or "UNKNOWN"),
                document_number=src_raw.get("document_number"),
                line_id=src_raw.get("line_id"),
                document_date=src_raw.get("document_date"),
            )
        else:
            src_doc = SourceDocumentReference(
                document_type=SourceDocumentType.MANUAL_ADJUSTMENT,
                document_id="UNKNOWN",
            )

        return StockTransactionResponse(
            id=tx.id,
            store_id=tx.store_id,
            product_id=tx.product_id,
            batch_id=tx.batch_id,
            batch_number=tx.batch_number,
            movement_type=MovementType(tx.movement_type),
            quantity=float(tx.quantity),
            base_unit=tx.base_unit,
            entered_quantity=float(tx.entered_quantity) if tx.entered_quantity is not None else None,
            entered_unit=tx.entered_unit,
            conversion_factor=float(tx.conversion_factor),
            source_document=src_doc,
            idempotency_key=tx.idempotency_key,
            actor_id=tx.created_by,
            is_inferred=tx.is_inferred,
            notes=tx.notes,
            created_at=tx.created_at,
        )

    # --------------------------------------------------------------------------
    # Phase 8: Physical Stock Audits & Cycle Counts
    # --------------------------------------------------------------------------
    async def create_audit_session(self, store_id: str, payload: AuditSessionCreate) -> AuditSessionResponse:
        audit_id = f"AUD-{datetime.now(timezone.utc).strftime('%Y%m%d')}-{uuid.uuid4().hex[:6].upper()}"

        expected_stmt = select(func.count(BatchTable.id)).where(
            BatchTable.store_id == store_id,
            BatchTable.is_active == True,
            BatchTable.current_quantity > 0,
        )
        if payload.scope_product_ids:
            expected_stmt = expected_stmt.where(BatchTable.product_id.in_(payload.scope_product_ids))
        total_items_expected = await self.session.scalar(expected_stmt) or 0

        audit_type_str = payload.audit_type.value if hasattr(payload.audit_type, "value") else str(payload.audit_type)
        new_audit = AuditSessionTable(
            id=audit_id,
            store_id=store_id,
            title=payload.title,
            audit_type=audit_type_str,
            status=AuditStatus.IN_PROGRESS.value,
            scope_product_ids=payload.scope_product_ids,
            total_items_expected=int(total_items_expected),
            total_items_counted=0,
            discrepancy_count=0,
            surplus_count=0,
            shortage_count=0,
            net_variance_value=0.0,
            notes=payload.notes,
            assigned_to=payload.assigned_to,
            created_by=payload.created_by,
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc),
        )
        self.session.add(new_audit)
        await self.session.commit()
        await self.session.refresh(new_audit)
        return self._map_audit_session_to_response(new_audit)

    async def get_audit_sessions(
        self,
        store_id: str,
        status_filter: Optional[str] = None,
        audit_type: Optional[str] = None,
        limit: int = 50,
        skip: int = 0,
    ) -> list[AuditSessionResponse]:
        stmt = select(AuditSessionTable).where(AuditSessionTable.store_id == store_id)
        if status_filter:
            stmt = stmt.where(AuditSessionTable.status == status_filter.upper())
        if audit_type:
            stmt = stmt.where(AuditSessionTable.audit_type == audit_type.upper())
        stmt = stmt.order_by(AuditSessionTable.created_at.desc()).offset(skip).limit(limit)
        results = await self.session.scalars(stmt)
        return [self._map_audit_session_to_response(s) for s in results.all()]

    async def get_audit_session(self, store_id: str, audit_id: str, blind: bool = False) -> AuditSessionResponse:
        stmt = select(AuditSessionTable).where(
            AuditSessionTable.id == audit_id,
            AuditSessionTable.store_id == store_id,
        )
        audit = await self.session.scalar(stmt)
        if not audit:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"code": "AUDIT_NOT_FOUND", "message": f"Audit session '{audit_id}' not found in store '{store_id}'"},
            )

        items_stmt = (
            select(AuditCountItemTable)
            .where(AuditCountItemTable.audit_id == audit_id)
            .order_by(AuditCountItemTable.created_at.asc())
        )
        items = (await self.session.scalars(items_stmt)).all()

        is_blind_mode = blind and audit.status != AuditStatus.RECONCILED.value
        mapped_items = [self._map_audit_item_to_response(it, blind=is_blind_mode) for it in items]

        return self._map_audit_session_to_response(audit, items=mapped_items)

    async def record_audit_counts(
        self, store_id: str, audit_id: str, payload: AuditCountBatchCreate
    ) -> AuditSessionResponse:
        audit = await self.session.scalar(
            select(AuditSessionTable).where(
                AuditSessionTable.id == audit_id,
                AuditSessionTable.store_id == store_id,
            )
        )
        if not audit:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"code": "AUDIT_NOT_FOUND", "message": f"Audit session '{audit_id}' not found in store '{store_id}'"},
            )
        if audit.status in [AuditStatus.RECONCILED.value, AuditStatus.CANCELLED.value]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={"code": "AUDIT_CLOSED", "message": f"Cannot submit counts to audit session in '{audit.status}' status"},
            )

        now = datetime.now(timezone.utc)
        for item_data in payload.items:
            clean_b = item_data.batch_number.strip().upper()

            b_stmt = select(BatchTable).where(
                BatchTable.store_id == store_id,
                BatchTable.product_id == item_data.product_id,
                BatchTable.batch_number == clean_b,
            )
            existing_b = await self.session.scalar(b_stmt)
            if existing_b:
                sys_qty = float(existing_b.current_quantity)
                exp_date = existing_b.expiry_date
                unit_cost = float(existing_b.purchase_rate or 0.0)
                batch_id = existing_b.id
            else:
                sys_qty = 0.0
                exp_date = None
                unit_cost = 0.0
                batch_id = item_data.batch_id

            counted_qty = float(item_data.counted_quantity)
            disc_qty = round(counted_qty - sys_qty, 3)
            disc_val = round(disc_qty * unit_cost, 2)
            reason_str = (
                item_data.discrepancy_reason.value
                if hasattr(item_data.discrepancy_reason, "value")
                else str(item_data.discrepancy_reason)
            )

            it_stmt = select(AuditCountItemTable).where(
                AuditCountItemTable.audit_id == audit_id,
                AuditCountItemTable.product_id == item_data.product_id,
                AuditCountItemTable.batch_number == clean_b,
            )
            existing_it = await self.session.scalar(it_stmt)
            if existing_it:
                existing_it.counted_quantity = counted_qty
                existing_it.system_quantity = sys_qty
                existing_it.discrepancy_quantity = disc_qty
                existing_it.unit_cost = unit_cost
                existing_it.discrepancy_value = disc_val
                existing_it.discrepancy_reason = reason_str
                if item_data.notes:
                    existing_it.notes = item_data.notes
                if item_data.counted_by:
                    existing_it.counted_by = item_data.counted_by
                existing_it.updated_at = now
            else:
                new_it = AuditCountItemTable(
                    id=f"CNT-{uuid.uuid4().hex[:12].upper()}",
                    audit_id=audit_id,
                    store_id=store_id,
                    product_id=item_data.product_id,
                    product_name=item_data.product_name,
                    batch_id=batch_id,
                    batch_number=clean_b,
                    expiry_date=exp_date,
                    system_quantity=sys_qty,
                    counted_quantity=counted_qty,
                    discrepancy_quantity=disc_qty,
                    unit_cost=unit_cost,
                    discrepancy_value=disc_val,
                    discrepancy_reason=reason_str,
                    recount_required=False,
                    notes=item_data.notes,
                    counted_by=item_data.counted_by,
                    status="COUNTED",
                    created_at=now,
                    updated_at=now,
                )
                self.session.add(new_it)

        await self.session.flush()

        all_items = (
            await self.session.scalars(
                select(AuditCountItemTable).where(AuditCountItemTable.audit_id == audit_id)
            )
        ).all()

        surplus_c = sum(1 for it in all_items if float(it.discrepancy_quantity) > 0)
        shortage_c = sum(1 for it in all_items if float(it.discrepancy_quantity) < 0)
        net_val = round(sum(float(it.discrepancy_value) for it in all_items), 2)

        audit.total_items_counted = len(all_items)
        audit.surplus_count = surplus_c
        audit.shortage_count = shortage_c
        audit.discrepancy_count = surplus_c + shortage_c
        audit.net_variance_value = net_val
        audit.status = AuditStatus.UNDER_REVIEW.value
        audit.updated_at = now

        await self.session.commit()
        await self.session.refresh(audit)
        return await self.get_audit_session(store_id, audit_id, blind=False)

    async def get_audit_discrepancies(self, store_id: str, audit_id: str) -> AuditDiscrepancyReport:
        audit = await self.session.scalar(
            select(AuditSessionTable).where(
                AuditSessionTable.id == audit_id,
                AuditSessionTable.store_id == store_id,
            )
        )
        if not audit:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"code": "AUDIT_NOT_FOUND", "message": f"Audit session '{audit_id}' not found in store '{store_id}'"},
            )

        all_items = (
            await self.session.scalars(
                select(AuditCountItemTable)
                .where(AuditCountItemTable.audit_id == audit_id)
                .order_by(AuditCountItemTable.created_at.asc())
            )
        ).all()

        disc_items = [it for it in all_items if float(it.discrepancy_quantity) != 0]
        surplus_val = sum(float(it.discrepancy_value) for it in disc_items if float(it.discrepancy_quantity) > 0)
        shortage_val = sum(abs(float(it.discrepancy_value)) for it in disc_items if float(it.discrepancy_quantity) < 0)
        net_val = round(surplus_val - shortage_val, 2)
        clean_count = len(all_items) - len(disc_items)

        mapped_disc = [self._map_audit_item_to_response(it, blind=False) for it in disc_items]

        return AuditDiscrepancyReport(
            audit_id=audit.id,
            store_id=audit.store_id,
            title=audit.title,
            status=AuditStatus(audit.status),
            total_counted=len(all_items),
            total_discrepant=len(disc_items),
            total_surplus_value=round(surplus_val, 2),
            total_shortage_value=round(shortage_val, 2),
            net_variance_value=net_val,
            clean_items_count=clean_count,
            discrepant_items=mapped_disc,
        )

    async def reconcile_audit_session(
        self, store_id: str, audit_id: str, payload: AuditReconcileRequest
    ) -> AuditReconcileResponse:
        audit = await self.session.scalar(
            select(AuditSessionTable).where(
                AuditSessionTable.id == audit_id,
                AuditSessionTable.store_id == store_id,
            )
        )
        if not audit:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"code": "AUDIT_NOT_FOUND", "message": f"Audit session '{audit_id}' not found in store '{store_id}'"},
            )
        if audit.status == AuditStatus.RECONCILED.value:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={"code": "ALREADY_RECONCILED", "message": f"Audit session '{audit_id}' has already been reconciled"},
            )
        if audit.status == AuditStatus.CANCELLED.value:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={"code": "AUDIT_CANCELLED", "message": "Cannot reconcile a cancelled audit session"},
            )

        # Idempotency check
        idem_stmt = select(StockTransactionTable).where(
            StockTransactionTable.store_id == store_id,
            StockTransactionTable.idempotency_key == payload.idempotency_key,
        )
        if await self.session.scalar(idem_stmt):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "code": "DUPLICATE_IDEMPOTENCY_KEY",
                    "message": f"Reconciliation with idempotency key '{payload.idempotency_key}' already completed",
                },
            )

        all_items = (
            await self.session.scalars(
                select(AuditCountItemTable).where(AuditCountItemTable.audit_id == audit_id)
            )
        ).all()

        disc_items = [it for it in all_items if float(it.discrepancy_quantity) != 0]

        now = datetime.now(timezone.utc)
        transaction_ids: list[str] = []
        total_surplus_qty = 0.0
        total_shortage_qty = 0.0
        net_financial = 0.0

        for it in disc_items:
            delta = float(it.discrepancy_quantity)
            tx_id = f"TXN-{uuid.uuid4().hex[:12].upper()}"
            transaction_ids.append(tx_id)

            if delta > 0:
                total_surplus_qty += delta
                net_financial += float(it.discrepancy_value)
                m_type = MovementType.ADJUSTMENT_ADD.value
                tx_qty = delta
            else:
                total_shortage_qty += abs(delta)
                net_financial += float(it.discrepancy_value)
                m_type = MovementType.ADJUSTMENT_SUBTRACT.value
                tx_qty = delta

            tx = StockTransactionTable(
                id=tx_id,
                store_id=store_id,
                product_id=it.product_id,
                batch_id=it.batch_id,
                batch_number=it.batch_number,
                movement_type=m_type,
                quantity=tx_qty,
                base_unit="TABLET",
                entered_quantity=abs(delta),
                entered_unit="TABLET",
                conversion_factor=1.0,
                source_document={
                    "document_type": SourceDocumentType.STOCK_AUDIT.value,
                    "document_id": audit_id,
                    "line_id": it.id,
                    "document_number": audit.title,
                },
                idempotency_key=f"{payload.idempotency_key}-{it.id}",
                is_inferred=False,
                notes=f"Audit discrepancy reconciliation ({it.discrepancy_reason or 'NORMAL_DISCREPANCY'}). Approved by {payload.approved_by}",
                created_by=payload.approved_by,
                created_at=now,
            )
            self.session.add(tx)

            if it.batch_id:
                b = await self.session.scalar(select(BatchTable).where(BatchTable.id == it.batch_id))
                if b:
                    new_b_qty = float(b.current_quantity) + delta
                    b.current_quantity = max(0.0, new_b_qty)
                    b.updated_at = now
            elif delta > 0:
                b_check = await self.session.scalar(
                    select(BatchTable).where(
                        BatchTable.store_id == store_id,
                        BatchTable.product_id == it.product_id,
                        BatchTable.batch_number == it.batch_number,
                    )
                )
                if not b_check:
                    new_b = BatchTable(
                        id=f"BAT-{uuid.uuid4().hex[:12].upper()}",
                        store_id=store_id,
                        product_id=it.product_id,
                        batch_number=it.batch_number,
                        expiry_date=it.expiry_date or now.date(),
                        mrp=0.0,
                        purchase_rate=float(it.unit_cost),
                        current_quantity=delta,
                        base_unit="TABLET",
                        is_active=True,
                        created_at=now,
                        updated_at=now,
                    )
                    self.session.add(new_b)

            bal = await self.session.scalar(
                select(StockBalanceTable).where(
                    StockBalanceTable.store_id == store_id,
                    StockBalanceTable.product_id == it.product_id,
                    StockBalanceTable.batch_number == it.batch_number,
                )
            )
            if bal:
                bal.current_quantity = max(0.0, float(bal.current_quantity) + delta)
                bal.last_transaction_id = tx_id
                bal.updated_at = now
            else:
                new_bal = StockBalanceTable(
                    id=f"BAL-{uuid.uuid4().hex[:12].upper()}",
                    store_id=store_id,
                    product_id=it.product_id,
                    batch_number=it.batch_number,
                    current_quantity=max(0.0, delta),
                    base_unit="TABLET",
                    last_transaction_id=tx_id,
                    updated_at=now,
                )
                self.session.add(new_bal)

            it.status = "RECONCILED"
            it.updated_at = now

        audit.status = AuditStatus.RECONCILED.value
        audit.approved_by = payload.approved_by
        audit.reconciled_at = now
        audit.updated_at = now
        if payload.notes:
            audit.notes = (audit.notes or "") + f" | Reconciliation notes: {payload.notes}"

        await self.session.commit()

        return AuditReconcileResponse(
            audit_id=audit_id,
            status=AuditStatus.RECONCILED.value,
            reconciled_at=now,
            approved_by=payload.approved_by,
            reconciled_items_count=len(disc_items),
            ledger_transactions_posted=len(transaction_ids),
            total_surplus_qty=round(total_surplus_qty, 3),
            total_shortage_qty=round(total_shortage_qty, 3),
            net_financial_adjustment=round(net_financial, 2),
            transaction_ids=transaction_ids,
        )

    async def cancel_audit_session(
        self, store_id: str, audit_id: str, reason: Optional[str] = None
    ) -> AuditSessionResponse:
        audit = await self.session.scalar(
            select(AuditSessionTable).where(
                AuditSessionTable.id == audit_id,
                AuditSessionTable.store_id == store_id,
            )
        )
        if not audit:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"code": "AUDIT_NOT_FOUND", "message": f"Audit session '{audit_id}' not found in store '{store_id}'"},
            )
        if audit.status == AuditStatus.RECONCILED.value:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={"code": "CANNOT_CANCEL_RECONCILED", "message": "Cannot cancel a reconciled audit session"},
            )

        audit.status = AuditStatus.CANCELLED.value
        audit.updated_at = datetime.now(timezone.utc)
        if reason:
            audit.notes = (audit.notes or "") + f" | Cancelled: {reason}"

        await self.session.commit()
        await self.session.refresh(audit)
        return self._map_audit_session_to_response(audit)

    def _map_audit_session_to_response(
        self, s: AuditSessionTable, items: Optional[list[AuditCountItemResponse]] = None
    ) -> AuditSessionResponse:
        return AuditSessionResponse(
            id=s.id,
            store_id=s.store_id,
            title=s.title,
            audit_type=AuditType(s.audit_type),
            status=AuditStatus(s.status),
            scope_product_ids=s.scope_product_ids,
            total_items_expected=int(s.total_items_expected or 0),
            total_items_counted=int(s.total_items_counted or 0),
            discrepancy_count=int(s.discrepancy_count or 0),
            surplus_count=int(s.surplus_count or 0),
            shortage_count=int(s.shortage_count or 0),
            net_variance_value=float(s.net_variance_value or 0.0),
            notes=s.notes,
            assigned_to=s.assigned_to,
            created_by=s.created_by,
            approved_by=s.approved_by,
            created_at=s.created_at,
            updated_at=s.updated_at,
            reconciled_at=s.reconciled_at,
            items=items,
        )

    def _map_audit_item_to_response(
        self, it: AuditCountItemTable, blind: bool = False
    ) -> AuditCountItemResponse:
        return AuditCountItemResponse(
            id=it.id,
            audit_id=it.audit_id,
            store_id=it.store_id,
            product_id=it.product_id,
            product_name=it.product_name,
            batch_id=it.batch_id,
            batch_number=it.batch_number,
            expiry_date=it.expiry_date,
            system_quantity=None if blind else float(it.system_quantity or 0.0),
            counted_quantity=float(it.counted_quantity or 0.0),
            discrepancy_quantity=None if blind else float(it.discrepancy_quantity or 0.0),
            unit_cost=None if blind else float(it.unit_cost or 0.0),
            discrepancy_value=None if blind else float(it.discrepancy_value or 0.0),
            discrepancy_reason=it.discrepancy_reason,
            recount_required=it.recount_required,
            notes=it.notes,
            counted_by=it.counted_by,
            status=it.status,
            created_at=it.created_at,
        )
