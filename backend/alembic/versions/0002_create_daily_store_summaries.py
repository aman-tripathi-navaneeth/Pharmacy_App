"""create daily_store_summaries table

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-23

The dashboard module's own table for confirmed end-of-day summaries (Summary tab,
design frames 08/09). One row per store per business day, written when the day's
report is confirmed - never updated after the fact. Same universal conventions as
0001: store_id VARCHAR(32), idempotency_key with UNIQUE (store_id, idempotency_key),
created_at / updated_at TIMESTAMPTZ defaulted to now().

Amounts are NUMERIC(12,2) rupees; the module's adapters convert to integer paise.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "daily_store_summaries",
        sa.Column("store_id", sa.String(length=32), nullable=False),
        sa.Column("summary_date", sa.Date(), nullable=False),
        sa.Column("total_sales_amount", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("total_purchases_amount", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("udhaar_collected_amount", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("udhaar_issued_amount", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("expired_stock_value", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("low_stock_sku_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("idempotency_key", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.UniqueConstraint("store_id", "summary_date", name="uq_store_summary_date"),
        sa.UniqueConstraint("store_id", "idempotency_key", name="uq_store_summary_idempotency"),
    )


def downgrade() -> None:
    op.drop_table("daily_store_summaries")
