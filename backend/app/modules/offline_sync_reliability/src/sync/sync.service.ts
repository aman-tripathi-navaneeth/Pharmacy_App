import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { and, asc, count, eq, gt } from 'drizzle-orm';
import { StoreAccessService } from '../common/store-access/store-access.service.js';
import { type Db, InjectDb } from '../db/db.module.js';
import { isUniqueViolation } from '../db/pg-errors.js';
import { syncChanges, syncCounters, syncLogs, syncOperations, userDevices } from '../db/schema.js';
import { IdempotencyService } from '../idempotency/idempotency.service.js';
import { CancelOperationDto, DeviceScopeDto, PullQueryDto, PushDto, PushOperationDto, StoreScopeDto } from './dto/sync.dto.js';
import { OperationHandlerRegistry } from './handlers/operation-handler.js';
import { SyncCaller, SyncProcessor } from './sync.processor.js';
import { OperationResult } from './sync.types.js';

const DEFAULT_PULL_LIMIT = 200;

@Injectable()
export class SyncService {
  constructor(
    @InjectDb() private readonly db: Db,
    private readonly access: StoreAccessService,
    private readonly processor: SyncProcessor,
    private readonly idempotency: IdempotencyService,
    private readonly registry: OperationHandlerRegistry,
  ) {}

  /** Membership is re-checked on every call: access may have been revoked while the device was offline. */
  private async caller(userId: string, scope: { storeId: string; deviceId?: string }, requestId?: string): Promise<SyncCaller> {
    await this.access.assertAccess(userId, scope.storeId);
    return { storeId: scope.storeId, userId, deviceId: scope.deviceId ?? 'unknown', requestId };
  }

  private opWhere(storeId: string, clientOperationId: string) {
    return and(eq(syncOperations.storeId, storeId), eq(syncOperations.clientOperationId, clientOperationId));
  }

  async push(userId: string, dto: PushDto, requestId?: string) {
    const caller = await this.caller(userId, dto, requestId);
    await this.touchDevice(caller, { platform: dto.platform, appVersion: dto.appVersion });

    const ids = new Set<string>();
    for (const op of dto.operations) {
      if (ids.has(op.clientOperationId)) {
        throw new BadRequestException({ code: 'DUPLICATE_IN_BATCH', message: `Operation ${op.clientOperationId} appears twice in one batch.` });
      }
      ids.add(op.clientOperationId);
    }

    // Sequential on purpose: preserves the client's dependency order within the batch.
    const results: OperationResult[] = [];
    for (const op of dto.operations) results.push(await this.processor.process(caller, op));
    return { results, serverTime: new Date().toISOString() };
  }

  async pull(userId: string, q: PullQueryDto, requestId?: string) {
    const caller = await this.caller(userId, q, requestId);
    const limit = q.limit ?? DEFAULT_PULL_LIMIT;
    let after = q.cursor ? Number(q.cursor) : 0;

    // A cursor ahead of this store's feed means the device saw a different database
    // (restore from backup, environment reset). Resend everything rather than silently
    // returning nothing; the device ignores versions older than what it already has.
    let resetCursor = false;
    if (after > 0) {
      const [counter] = await this.db.select({ seq: syncCounters.seq }).from(syncCounters).where(eq(syncCounters.storeId, caller.storeId));
      if (after > (counter?.seq ?? 0)) {
        after = 0;
        resetCursor = true;
      }
    }

    const rows = await this.db
      .select()
      .from(syncChanges)
      .where(and(eq(syncChanges.storeId, caller.storeId), gt(syncChanges.seq, after)))
      .orderBy(asc(syncChanges.seq))
      .limit(limit + 1);
    const hasMore = rows.length > limit;
    const page = rows.slice(0, limit);
    const nextCursor = String(page.length ? page[page.length - 1].seq : after);

    // The cursor the device sends is the one it has durably applied → that is the acknowledgement.
    await this.touchDevice(caller, {
      lastSyncCursor: q.cursor ?? '0',
      ...(hasMore ? {} : { lastSuccessfulSyncAt: new Date() }),
    });

    return {
      changes: page.map((c) => ({
        seq: c.seq,
        entity: c.entity,
        entityId: c.entityId,
        version: c.version,
        deleted: c.deleted,
        data: c.deleted ? undefined : c.data,
        changedAt: c.changedAt,
      })),
      nextCursor,
      hasMore,
      resetCursor,
      serverTime: new Date().toISOString(),
    };
  }

  async status(userId: string, q: StoreScopeDto) {
    const caller = await this.caller(userId, q);
    const filter = q.deviceId
      ? and(eq(syncOperations.storeId, caller.storeId), eq(syncOperations.deviceId, q.deviceId))
      : eq(syncOperations.storeId, caller.storeId);

    const [grouped, device, counter] = await Promise.all([
      this.db.select({ status: syncOperations.status, n: count() }).from(syncOperations).where(filter).groupBy(syncOperations.status),
      q.deviceId
        ? this.db
            .select()
            .from(userDevices)
            .where(and(eq(userDevices.userId, userId), eq(userDevices.deviceId, q.deviceId), eq(userDevices.storeId, caller.storeId)))
            .then((r) => r[0])
        : undefined,
      this.db.select({ seq: syncCounters.seq }).from(syncCounters).where(eq(syncCounters.storeId, caller.storeId)).then((r) => r[0]),
    ]);
    const counts = Object.fromEntries(grouped.map((g) => [g.status, Number(g.n)])) as Record<string, number>;
    return {
      counts: {
        synced: counts.SYNCED ?? 0,
        processing: (counts.PROCESSING ?? 0) + (counts.RECEIVED ?? 0),
        retryable: counts.RETRYABLE ?? 0,
        conflict: counts.CONFLICT ?? 0,
        failed: counts.FAILED ?? 0,
        cancelled: counts.CANCELLED ?? 0,
      },
      lastSuccessfulSyncAt: device?.lastSuccessfulSyncAt ?? null,
      acknowledgedCursor: device?.lastSyncCursor ?? null,
      latestCursor: String(counter?.seq ?? 0),
      supportedOperations: this.registry.supported(),
      serverTime: new Date().toISOString(),
    };
  }

  async getOperation(userId: string, clientOperationId: string, q: StoreScopeDto) {
    const caller = await this.caller(userId, q);
    const [op] = await this.db.select().from(syncOperations).where(this.opWhere(caller.storeId, clientOperationId)).limit(1);
    if (!op) throw new NotFoundException({ code: 'OPERATION_NOT_FOUND', message: 'The server has not received this operation yet.' });
    return {
      clientOperationId: op.clientOperationId,
      module: op.module,
      operationType: op.operationType,
      status: op.status,
      serverResourceId: op.serverResourceId ?? null,
      attemptCount: op.attemptCount,
      lastErrorCode: op.lastErrorCode ?? null,
      lastErrorMessage: op.lastErrorMessage ?? null,
      createdAt: op.createdAt,
      updatedAt: op.updatedAt,
      processedAt: op.processedAt ?? null,
    };
  }

  /** Re-runs a stored operation with its ORIGINAL key and payload. A synced op only replays. */
  async retry(userId: string, clientOperationId: string, dto: DeviceScopeDto, requestId?: string): Promise<OperationResult> {
    const caller = await this.caller(userId, dto, requestId);
    const [op] = await this.db.select().from(syncOperations).where(this.opWhere(caller.storeId, clientOperationId)).limit(1);
    if (!op || !op.payload) {
      throw new NotFoundException({ code: 'OPERATION_NOT_FOUND', message: 'The server has not received this operation. Push it again from the device.' });
    }
    const replayed: PushOperationDto = {
      clientOperationId: op.clientOperationId,
      idempotencyKey: op.idempotencyKey,
      module: op.module,
      operationType: op.operationType,
      payload: op.payload,
      entityId: op.entityId ?? undefined,
      baseVersion: op.baseVersion ?? undefined,
      dependsOn: op.dependsOn,
    };
    return this.processor.process(caller, replayed, 'RETRY');
  }

  /**
   * Cancels an operation only if the server has not committed it. Recording CANCELLED under the
   * idempotency key guarantees a late-arriving retry of the same operation is never applied.
   */
  async cancel(userId: string, clientOperationId: string, dto: CancelOperationDto, requestId?: string) {
    const caller = await this.caller(userId, dto, requestId);
    const scope = { storeId: caller.storeId, scopeKey: `${dto.module}.${dto.operationType}`, idempotencyKey: dto.idempotencyKey };

    const [tracked] = await this.db
      .select({ idempotencyKey: syncOperations.idempotencyKey })
      .from(syncOperations)
      .where(this.opWhere(caller.storeId, clientOperationId))
      .limit(1);
    if (tracked && tracked.idempotencyKey !== dto.idempotencyKey) {
      throw new BadRequestException({ code: 'OPERATION_ID_MISMATCH', message: 'Operation ID and key do not match.' });
    }

    let record = await this.idempotency.find(scope);
    if (!record) {
      try {
        await this.idempotency.record(scope, {
          userId: caller.userId,
          clientOperationId,
          requestHash: null,
          outcome: 'CANCELLED',
          resultBody: { errorCode: 'OPERATION_CANCELLED' },
        });
      } catch (err) {
        if (!isUniqueViolation(err)) throw err;
      }
      record = await this.idempotency.find(scope);
    }

    if (record!.outcome === 'SYNCED') {
      await this.log(caller, clientOperationId, 'REJECTED', 'ALREADY_COMMITTED');
      throw new ConflictException({
        code: 'ALREADY_COMMITTED',
        message: 'This change was already applied on the server, so it cannot be cancelled here. Use the module’s reversal flow instead.',
      });
    }

    await this.db
      .insert(syncOperations)
      .values({
        storeId: caller.storeId,
        clientOperationId,
        idempotencyKey: dto.idempotencyKey,
        userId: caller.userId,
        deviceId: caller.deviceId,
        module: dto.module,
        operationType: dto.operationType,
        status: 'CANCELLED',
      })
      .onConflictDoUpdate({
        target: [syncOperations.storeId, syncOperations.clientOperationId],
        set: { status: 'CANCELLED', updatedAt: new Date() },
      });
    await this.log(caller, clientOperationId, 'CANCELLED');
    return { clientOperationId, status: 'CANCELLED' as const };
  }

  private async log(caller: SyncCaller, operationId: string, result: string, errorCode?: string) {
    await this.db.insert(syncLogs).values({
      storeId: caller.storeId,
      userId: caller.userId,
      deviceId: caller.deviceId,
      operationId,
      action: 'CANCEL',
      result,
      errorCode,
      requestId: caller.requestId,
    });
  }

  private async touchDevice(
    caller: SyncCaller,
    set: { platform?: string; appVersion?: string; lastSyncCursor?: string; lastSuccessfulSyncAt?: Date },
  ) {
    if (caller.deviceId === 'unknown') return;
    const clean = Object.fromEntries(Object.entries(set).filter(([, v]) => v !== undefined));
    await this.db
      .insert(userDevices)
      .values({ userId: caller.userId, deviceId: caller.deviceId, storeId: caller.storeId, ...clean, lastActiveAt: new Date() })
      .onConflictDoUpdate({
        target: [userDevices.userId, userDevices.deviceId, userDevices.storeId],
        set: { ...clean, lastActiveAt: new Date() },
      });
  }
}
