import { Injectable } from '@nestjs/common';
import { and, count, eq, inArray, lt } from 'drizzle-orm';
import { type Db, InjectDb } from '../../db/db.module.js';
import { syncOperations } from '../../db/schema.js';
import { OperationHandlerRegistry } from '../../sync/handlers/operation-handler.js';
import type { CheckContext, CheckOutcome, HealthCheck } from '../health-check.js';

/** Spec §12 queue warning: work still unprocessed 15 min after the server first saw it. */
export const STUCK_AFTER_MS = 15 * 60_000;

/** This shop's server-side sync pipeline: handlers registered, nothing stuck retrying. */
@Injectable()
export class SyncBacklogHealthCheck implements HealthCheck {
  readonly key = 'sync';
  readonly scope = 'store' as const;

  constructor(
    @InjectDb() private readonly db: Db,
    private readonly handlers: OperationHandlerRegistry,
  ) {}

  async check({ storeId }: CheckContext): Promise<CheckOutcome> {
    if (this.handlers.supported().length === 0) {
      return { status: 'UNAVAILABLE', message: 'No offline operations are accepted by the server.' };
    }
    const [{ n }] = await this.db
      .select({ n: count() })
      .from(syncOperations)
      .where(
        and(
          eq(syncOperations.storeId, storeId),
          inArray(syncOperations.status, ['RETRYABLE', 'PROCESSING', 'RECEIVED']),
          lt(syncOperations.createdAt, new Date(Date.now() - STUCK_AFTER_MS)),
        ),
      );
    const stuck = Number(n);
    return stuck > 0
      ? { status: 'DEGRADED', message: `${stuck} ${stuck === 1 ? 'change has' : 'changes have'} been retrying for over 15 minutes.` }
      : { status: 'OPERATIONAL' };
  }
}
