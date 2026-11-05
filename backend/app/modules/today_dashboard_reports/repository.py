"""Storage for snoozed and done tasks (table: dashboard_task_state).

This stores task action state. Daily summaries are stored by reports.py; operational
facts are read from their owning modules.

Row shape:
  { store_id, task_key, status: "snoozed" | "done", snoozed_until: DATE | null,
    acted_by, acted_at (UTC timestamptz), idempotency_key, created_at, updated_at }
Unique constraint: (store_id, task_key). Writing the same state twice is safe (upsert).
The table is created by Alembic migration 0001; never create it in code.
It follows the lead universal conventions: store_id, idempotency_key, created_at, updated_at.
"""

from dataclasses import dataclass
from datetime import date, datetime
from typing import Protocol


@dataclass
class TaskState:
    store_id: str
    task_key: str
    status: str  # "snoozed" or "done"
    acted_by: str
    acted_at: datetime  # timezone-aware
    snoozed_until: date | None = None
    idempotency_key: str | None = None
    created_at: datetime | None = None  # set by the DB (now()) when None
    updated_at: datetime | None = None  # set by the DB (now()) when None


class TaskStateRepo(Protocol):
    async def list_states(self, store_id: str) -> list[TaskState]: ...
    async def set_state(self, state: TaskState) -> None: ...
    async def clear_state(self, store_id: str, task_key: str) -> None: ...


class InMemoryTaskStateRepo:
    """Used when POSTGRES_URL is not configured, and in tests."""

    def __init__(self) -> None:
        self._data: dict[tuple[str, str], TaskState] = {}

    async def list_states(self, store_id: str) -> list[TaskState]:
        return [s for (sid, _), s in self._data.items() if sid == store_id]

    async def set_state(self, state: TaskState) -> None:
        self._data[(state.store_id, state.task_key)] = state

    async def clear_state(self, store_id: str, task_key: str) -> None:
        self._data.pop((store_id, task_key), None)


class PostgresTaskStateRepo:
    """Reads and writes the dashboard_task_state table through the shared asyncpg pool.

    Keep the SQL to simple statements on this one table. Cross-module data arrives from
    service functions, never as joins into other module tables. The table follows the
    lead universal conventions: store_id, idempotency_key, created_at, updated_at.
    created_at survives updates; updated_at is refreshed on every write.
    """

    def __init__(self, pool) -> None:
        self._pool = pool

    async def list_states(self, store_id: str) -> list[TaskState]:
        rows = await self._pool.fetch(
            "SELECT store_id, task_key, status, snoozed_until, acted_by, acted_at, "
            "idempotency_key, created_at, updated_at "
            "FROM dashboard_task_state WHERE store_id = $1",
            store_id,
        )
        return [
            TaskState(
                store_id=r["store_id"],
                task_key=r["task_key"],
                status=r["status"],
                acted_by=r["acted_by"],
                acted_at=r["acted_at"],
                snoozed_until=r["snoozed_until"],
                idempotency_key=r["idempotency_key"],
                created_at=r["created_at"],
                updated_at=r["updated_at"],
            )
            for r in rows
        ]

    async def set_state(self, state: TaskState) -> None:
        await self._pool.execute(
            """
            INSERT INTO dashboard_task_state
                (store_id, task_key, status, snoozed_until, acted_by, acted_at,
                 idempotency_key, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, COALESCE($8, now()), COALESCE($9, now()))
            ON CONFLICT (store_id, task_key) DO UPDATE SET
                status = EXCLUDED.status,
                snoozed_until = EXCLUDED.snoozed_until,
                acted_by = EXCLUDED.acted_by,
                acted_at = EXCLUDED.acted_at,
                idempotency_key = EXCLUDED.idempotency_key,
                created_at = dashboard_task_state.created_at,
                updated_at = now()
            """,
            state.store_id,
            state.task_key,
            state.status,
            state.snoozed_until,
            state.acted_by,
            state.acted_at,
            state.idempotency_key,
            state.created_at,
            state.updated_at,
        )

    async def clear_state(self, store_id: str, task_key: str) -> None:
        await self._pool.execute(
            "DELETE FROM dashboard_task_state WHERE store_id = $1 AND task_key = $2",
            store_id,
            task_key,
        )
