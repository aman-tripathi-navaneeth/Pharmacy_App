import { Injectable } from '@nestjs/common';
import { and, eq } from 'drizzle-orm';
import { type Db, type Executor, InjectDb } from '../db/db.module.js';
import { idempotencyRecords, type IdempotencyOutcome } from '../db/schema.js';

export interface IdempotencyScope {
  storeId: string;
  scopeKey: string;
  idempotencyKey: string;
}

export type IdempotencyRecord = typeof idempotencyRecords.$inferSelect;

export type ReplayDecision = { kind: 'replay'; record: IdempotencyRecord } | { kind: 'key_reused'; record: IdempotencyRecord };

const where = (s: IdempotencyScope) =>
  and(
    eq(idempotencyRecords.storeId, s.storeId),
    eq(idempotencyRecords.scopeKey, s.scopeKey),
    eq(idempotencyRecords.idempotencyKey, s.idempotencyKey),
  );

@Injectable()
export class IdempotencyService {
  constructor(@InjectDb() private readonly db: Db) {}

  async find(scope: IdempotencyScope, tx: Executor = this.db): Promise<IdempotencyRecord | undefined> {
    const [row] = await tx.select().from(idempotencyRecords).where(where(scope)).limit(1);
    return row;
  }

  /**
   * Inserts the final outcome for a key. Inside a transaction, a concurrent insert of
   * the same key blocks on the unique index until the first commits, then fails with
   * a unique violation — so exactly one wins.
   */
  async record(
    scope: IdempotencyScope,
    data: {
      userId: string;
      clientOperationId: string;
      requestHash: string | null;
      outcome: IdempotencyOutcome;
      resultBody: Record<string, unknown>;
      resourceId?: string;
    },
    tx: Executor = this.db,
  ) {
    await tx.insert(idempotencyRecords).values({ ...scope, ...data });
  }

  async setResult(scope: IdempotencyScope, resultBody: Record<string, unknown>, resourceId: string | undefined, tx: Executor) {
    await tx.update(idempotencyRecords).set({ resultBody, resourceId }).where(where(scope));
  }

  /** Same key + same payload → replay. Same key + different payload → reject (spec §5). */
  decide(record: IdempotencyRecord, requestHash: string): ReplayDecision {
    if (record.requestHash !== null && record.requestHash !== requestHash) return { kind: 'key_reused', record };
    return { kind: 'replay', record };
  }
}
