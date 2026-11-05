import { Injectable, Logger } from '@nestjs/common';
import { and, eq, inArray, sql } from 'drizzle-orm';
import { sha256 } from '../common/canonical-hash.js';
import { type Db, InjectDb, type Tx } from '../db/db.module.js';
import { isTransientTxError, isUniqueViolation } from '../db/pg-errors.js';
import { type IdempotencyOutcome, type ServerOpStatus, syncChanges, syncCounters, syncLogs, syncOperations } from '../db/schema.js';
import { type IdempotencyRecord, type IdempotencyScope, IdempotencyService } from '../idempotency/idempotency.service.js';
import { MAX_PAYLOAD_BYTES, PushOperationDto } from './dto/sync.dto.js';
import {
  ChangeInput,
  DomainConflictError,
  DomainRejectedError,
  OperationContext,
  OperationHandlerRegistry,
} from './handlers/operation-handler.js';
import { ERR, OperationResult } from './sync.types.js';

export interface SyncCaller {
  storeId: string;
  userId: string;
  deviceId: string;
  requestId?: string;
}

const RETRY_AFTER_MS = 2_000;

/**
 * Processes one offline operation exactly once.
 *
 * The idempotency record, the domain write, the change-feed entry and the operation status
 * commit in ONE Postgres transaction. The idempotency row is inserted first: a concurrent
 * submission of the same key blocks on its unique index and then fails, so the domain write
 * can never run twice (spec §5, test plan "Duplicate prevention").
 */
@Injectable()
export class SyncProcessor {
  private readonly logger = new Logger(SyncProcessor.name);

  constructor(
    @InjectDb() private readonly db: Db,
    private readonly idempotency: IdempotencyService,
    private readonly registry: OperationHandlerRegistry,
  ) {}

  async process(caller: SyncCaller, op: PushOperationDto, action: 'PUSH' | 'RETRY' = 'PUSH'): Promise<OperationResult> {
    const started = Date.now();
    let result: OperationResult;
    try {
      result = await this.processInner(caller, op);
    } catch (err) {
      if (!isTransientTxError(err)) {
        this.logger.error(`[${caller.requestId}] op ${op.clientOperationId} failed: ${(err as Error).stack ?? err}`);
      }
      await this.markStatus(caller.storeId, op.clientOperationId, 'RETRYABLE', ERR.TRANSIENT_ERROR).catch(() => undefined);
      result = this.retryable(op, ERR.TRANSIENT_ERROR, 'The server could not finish this change. It will retry automatically.');
    }
    await this.db
      .insert(syncLogs)
      .values({
        storeId: caller.storeId,
        userId: caller.userId,
        deviceId: caller.deviceId,
        operationId: op.clientOperationId,
        action,
        result: result.status,
        errorCode: result.errorCode,
        durationMs: Date.now() - started,
        requestId: caller.requestId,
      })
      .catch((e) => this.logger.warn(`sync_log write failed: ${e}`));
    return result;
  }

  private async processInner(caller: SyncCaller, op: PushOperationDto): Promise<OperationResult> {
    const { storeId } = caller;
    const scope: IdempotencyScope = { storeId, scopeKey: `${op.module}.${op.operationType}`, idempotencyKey: op.idempotencyKey };
    const requestHash = sha256({
      module: op.module,
      operationType: op.operationType,
      payload: op.payload,
      entityId: op.entityId ?? null,
      baseVersion: op.baseVersion ?? null,
      dependsOn: [...(op.dependsOn ?? [])].sort(),
    });

    // A clientOperationId is bound to exactly one key/action for its lifetime.
    const [tracked] = await this.db
      .select({ idempotencyKey: syncOperations.idempotencyKey, module: syncOperations.module, operationType: syncOperations.operationType })
      .from(syncOperations)
      .where(and(eq(syncOperations.storeId, storeId), eq(syncOperations.clientOperationId, op.clientOperationId)))
      .limit(1);
    if (
      tracked &&
      (tracked.idempotencyKey !== op.idempotencyKey || tracked.module !== op.module || tracked.operationType !== op.operationType)
    ) {
      return this.permanent(op, ERR.OPERATION_ID_MISMATCH, 'This operation ID was already used for a different change.');
    }

    const prior = await this.idempotency.find(scope);
    if (prior) return this.replay(op, prior, requestHash);

    await this.track(caller, op, requestHash);

    const handler = this.registry.get(op.module, op.operationType);
    if (!handler) {
      return this.finalize(caller, op, scope, requestHash, 'FAILED_PERMANENT', {
        errorCode: ERR.UNSUPPORTED_OPERATION,
        message: `"${op.module}.${op.operationType}" cannot be synced from offline mode. Repeat it while online.`,
      });
    }
    if (Buffer.byteLength(JSON.stringify(op.payload)) > MAX_PAYLOAD_BYTES) {
      return this.finalize(caller, op, scope, requestHash, 'FAILED_PERMANENT', {
        errorCode: ERR.PAYLOAD_TOO_LARGE,
        message: 'This change is too large to sync. Upload attachments separately.',
      });
    }
    const parsed = await this.registry.parse(handler, op.payload);
    if (parsed.errors.length) {
      return this.finalize(caller, op, scope, requestHash, 'FAILED_PERMANENT', {
        errorCode: ERR.INVALID_PAYLOAD,
        message: `Some details are invalid: ${parsed.errors.slice(0, 3).join('; ')}`,
      });
    }

    const dep = await this.checkDependencies(storeId, op.dependsOn ?? []);
    if (dep === 'pending') {
      await this.markStatus(storeId, op.clientOperationId, 'RETRYABLE', ERR.DEPENDENCY_NOT_SYNCED);
      return this.retryable(op, ERR.DEPENDENCY_NOT_SYNCED, 'Waiting for an earlier change to sync first.');
    }
    if (dep === 'failed') {
      return this.finalize(caller, op, scope, requestHash, 'FAILED_PERMANENT', {
        errorCode: ERR.DEPENDENCY_FAILED,
        message: 'An earlier change this depends on failed or was cancelled. Correct that change first.',
      });
    }

    try {
      const outcome = await this.db.transaction(async (tx) => {
        // Claim the key first so a concurrent duplicate collides before any domain write.
        await this.idempotency.record(
          scope,
          { userId: caller.userId, clientOperationId: op.clientOperationId, requestHash, outcome: 'SYNCED', resultBody: {} },
          tx,
        );
        const ctx: OperationContext = {
          tx,
          storeId,
          userId: caller.userId,
          deviceId: caller.deviceId,
          clientOperationId: op.clientOperationId,
          entityId: op.entityId,
          baseVersion: op.baseVersion,
          emitChange: (c) => this.emitChange(tx, storeId, op.clientOperationId, c),
        };
        const res = await handler.handle(ctx, parsed.value!);
        await this.idempotency.setResult(scope, { serverResourceId: res.resourceId, version: res.version }, res.resourceId, tx);
        await tx
          .update(syncOperations)
          .set({
            status: 'SYNCED',
            serverResourceId: res.resourceId,
            processedAt: new Date(),
            updatedAt: new Date(),
            lastErrorCode: null,
            lastErrorMessage: null,
          })
          .where(and(eq(syncOperations.storeId, storeId), eq(syncOperations.clientOperationId, op.clientOperationId)));
        return res;
      });
      return { clientOperationId: op.clientOperationId, status: 'SYNCED', serverResourceId: outcome.resourceId, version: outcome.version };
    } catch (err) {
      if (err instanceof DomainConflictError) {
        return this.finalize(caller, op, scope, requestHash, 'CONFLICT', { errorCode: err.code, message: err.message, conflict: err.conflict });
      }
      if (err instanceof DomainRejectedError) {
        return this.finalize(caller, op, scope, requestHash, 'FAILED_PERMANENT', { errorCode: err.code, message: err.message });
      }
      if (isUniqueViolation(err)) {
        const winner = await this.idempotency.find(scope);
        if (winner) return this.replay(op, winner, requestHash);
      }
      throw err;
    }
  }

  /** Replays a stored outcome. Never re-executes the domain write. */
  replay(op: Pick<PushOperationDto, 'clientOperationId'>, record: IdempotencyRecord, requestHash: string | null): OperationResult {
    if (requestHash !== null && this.idempotency.decide(record, requestHash).kind === 'key_reused') {
      return this.permanent(op, ERR.IDEMPOTENCY_KEY_REUSED, 'This change was already submitted with different details. Create a new change instead.');
    }
    const body = record.resultBody ?? {};
    switch (record.outcome) {
      case 'SYNCED':
        return {
          clientOperationId: op.clientOperationId,
          status: 'ALREADY_PROCESSED',
          serverResourceId: body.serverResourceId as string | undefined,
          version: body.version as number | undefined,
        };
      case 'CONFLICT':
        return { clientOperationId: op.clientOperationId, status: 'CONFLICT', ...(body as object) };
      case 'CANCELLED':
        return this.permanent(op, ERR.OPERATION_CANCELLED, 'This change was cancelled before it was applied.');
      default:
        return { clientOperationId: op.clientOperationId, status: 'FAILED_PERMANENT', ...(body as object) };
    }
  }

  private async finalize(
    caller: SyncCaller,
    op: PushOperationDto,
    scope: IdempotencyScope,
    requestHash: string,
    outcome: Exclude<IdempotencyOutcome, 'SYNCED' | 'CANCELLED'>,
    body: Record<string, unknown>,
  ): Promise<OperationResult> {
    try {
      await this.idempotency.record(scope, {
        userId: caller.userId,
        clientOperationId: op.clientOperationId,
        requestHash,
        outcome,
        resultBody: body,
      });
    } catch (err) {
      if (!isUniqueViolation(err)) throw err;
      const winner = await this.idempotency.find(scope);
      if (winner) return this.replay(op, winner, requestHash);
    }
    await this.markStatus(caller.storeId, op.clientOperationId, outcome === 'CONFLICT' ? 'CONFLICT' : 'FAILED', body.errorCode as string, body.message as string);
    return { clientOperationId: op.clientOperationId, status: outcome, ...body } as OperationResult;
  }

  /** Upsert the server-side record of this operation and count the attempt. */
  private async track(caller: SyncCaller, op: PushOperationDto, payloadHash: string) {
    await this.db
      .insert(syncOperations)
      .values({
        storeId: caller.storeId,
        clientOperationId: op.clientOperationId,
        idempotencyKey: op.idempotencyKey,
        userId: caller.userId,
        deviceId: caller.deviceId,
        module: op.module,
        operationType: op.operationType,
        entityId: op.entityId,
        baseVersion: op.baseVersion,
        dependsOn: op.dependsOn ?? [],
        clientCreatedAt: op.clientCreatedAt ? new Date(op.clientCreatedAt) : undefined,
        status: 'PROCESSING',
        payload: op.payload,
        payloadHash,
        attemptCount: 1,
      })
      .onConflictDoUpdate({
        target: [syncOperations.storeId, syncOperations.clientOperationId],
        set: {
          status: 'PROCESSING',
          payload: op.payload,
          payloadHash,
          attemptCount: sql`${syncOperations.attemptCount} + 1`,
          updatedAt: new Date(),
        },
      });
  }

  private async checkDependencies(storeId: string, deps: string[]): Promise<'ok' | 'pending' | 'failed'> {
    if (!deps.length) return 'ok';
    const found = await this.db
      .select({ status: syncOperations.status })
      .from(syncOperations)
      .where(and(eq(syncOperations.storeId, storeId), inArray(syncOperations.clientOperationId, deps)));
    if (found.some((d) => ['FAILED', 'CONFLICT', 'CANCELLED'].includes(d.status))) return 'failed';
    if (found.length < deps.length || found.some((d) => d.status !== 'SYNCED')) return 'pending';
    return 'ok';
  }

  private async emitChange(tx: Tx, storeId: string, sourceOperationId: string, c: ChangeInput) {
    // Row lock on the store's counter serialises change-feed writers → commit order == seq order.
    const [counter] = await tx
      .insert(syncCounters)
      .values({ storeId, seq: 1 })
      .onConflictDoUpdate({ target: syncCounters.storeId, set: { seq: sql`${syncCounters.seq} + 1` } })
      .returning({ seq: syncCounters.seq });
    await tx.insert(syncChanges).values({
      storeId,
      seq: counter.seq,
      entity: c.entity,
      entityId: c.entityId,
      version: c.version,
      deleted: c.deleted ?? false,
      data: c.data,
      sourceOperationId,
    });
  }

  async markStatus(storeId: string, clientOperationId: string, status: ServerOpStatus, code?: string, message?: string) {
    await this.db
      .update(syncOperations)
      .set({ status, lastErrorCode: code ?? null, lastErrorMessage: message ?? null, updatedAt: new Date() })
      .where(and(eq(syncOperations.storeId, storeId), eq(syncOperations.clientOperationId, clientOperationId)));
  }

  private permanent(op: Pick<PushOperationDto, 'clientOperationId'>, errorCode: string, message: string): OperationResult {
    return { clientOperationId: op.clientOperationId, status: 'FAILED_PERMANENT', errorCode, message };
  }

  private retryable(op: Pick<PushOperationDto, 'clientOperationId'>, errorCode: string, message: string): OperationResult {
    return { clientOperationId: op.clientOperationId, status: 'RETRYABLE_FAILURE', errorCode, message, retryAfterMs: RETRY_AFTER_MS };
  }
}
