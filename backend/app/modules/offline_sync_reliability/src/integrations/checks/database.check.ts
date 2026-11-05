import { Injectable } from '@nestjs/common';
import { sql } from 'drizzle-orm';
import { type Db, InjectDb } from '../../db/db.module.js';
import type { CheckOutcome, HealthCheck } from '../health-check.js';

const SLOW_MS = 1_000;

/** Server → Postgres reachability and latency. */
@Injectable()
export class DatabaseHealthCheck implements HealthCheck {
  readonly key = 'database';
  readonly scope = 'global' as const;

  constructor(@InjectDb() private readonly db: Db) {}

  async check(): Promise<CheckOutcome> {
    const started = Date.now();
    await this.db.execute(sql`select 1`);
    const ms = Date.now() - started;
    return ms > SLOW_MS
      ? { status: 'DEGRADED', message: 'The server database is responding slowly.' }
      : { status: 'OPERATIONAL' };
  }
}
