import { Injectable } from '@nestjs/common';
import { sql } from 'drizzle-orm';
import { type Db, InjectDb } from '../../db/db.module.js';
import { OperationHandlerRegistry } from '../../sync/handlers/operation-handler.js';
import type { CheckOutcome, HealthCheck } from '../health-check.js';

/**
 * REFERENCE check for the Inventory owner to adopt or replace: verifies the
 * contract Member 12 depends on (spec §14) — the stock-movement handler is
 * registered and the ledger's unique movement-id index exists.
 */
@Injectable()
export class InventoryHealthCheck implements HealthCheck {
  readonly key = 'inventory';
  readonly scope = 'global' as const;

  constructor(
    @InjectDb() private readonly db: Db,
    private readonly handlers: OperationHandlerRegistry,
  ) {}

  async check(): Promise<CheckOutcome> {
    if (!this.handlers.get('inventory', 'stock_movement')) {
      return { status: 'UNAVAILABLE', message: 'Stock movements are not accepted by the server.' };
    }
    const res = await this.db.execute(
      sql`select 1 from pg_indexes where tablename = 'stock_movements' and indexname = 'stock_movements_store_movement_uq'`,
    );
    return res.rows.length
      ? { status: 'OPERATIONAL' }
      : { status: 'DEGRADED', message: 'Duplicate protection for stock movements is not ready yet.' };
  }
}
