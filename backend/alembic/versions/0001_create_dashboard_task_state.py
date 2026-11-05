"""create dashboard_task_state table

Revision ID: 0001
Revises:
Create Date: 2026-10-22

The first migration is the baseline every future table joins. The dashboard module
owns exactly this table; other modules' tables arrive in their own migrations.
Follows the lead's universal conventions: store_id VARCHAR(32) NOT NULL, an
idempotency_key column with UNIQUE (store_id, idempotency_key), and created_at /
updated_at TIMESTAMPTZ defaulted to now().
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "dashboard_task_state",
        sa.Column("store_id", sa.String(length=32), nullable=False),
        sa.Column("task_key", sa.Text(), nullable=False),
        sa.Column("status", sa.Text(), nullable=False),
        sa.Column("snoozed_until", sa.Date(), nullable=True),
        sa.Column("acted_by", sa.Text(), nullable=False, server_default=""),
        sa.Column("acted_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("idempotency_key", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.UniqueConstraint("store_id", "task_key", name="uq_store_task"),
        sa.UniqueConstraint("store_id", "idempotency_key", name="uq_store_idempotency"),
    )


def downgrade() -> None:
    op.drop_table("dashboard_task_state")
