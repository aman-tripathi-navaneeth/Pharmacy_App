import 'dart:convert';

import 'package:drift/drift.dart';

import '../../features/sync/domain/op_state.dart';
import 'app_database.dart';

part 'outbox_dao.g.dart';

class SyncCounts {
  const SyncCounts({
    this.queued = 0,
    this.inFlight = 0,
    this.retryWait = 0,
    this.synced = 0,
    this.conflict = 0,
    this.failed = 0,
    this.cancelled = 0,
    this.exhausted = 0,
    this.oldestPendingAt,
  });

  final int queued;
  final int inFlight;
  final int retryWait;
  final int synced;
  final int conflict;
  final int failed;
  final int cancelled;

  /// RETRY_WAIT ops that used up their automatic attempts ("Needs attention").
  final int exhausted;
  final DateTime? oldestPendingAt;

  int get pending => queued + inFlight + retryWait;

  /// Items the user must look at: conflicts, permanent failures, exhausted retries.
  int get needsAttention => conflict + failed + exhausted;

  bool get isEmpty => pending == 0 && conflict == 0 && failed == 0;
}

class PulledChange {
  const PulledChange({
    required this.entity,
    required this.entityId,
    required this.version,
    required this.deleted,
    this.data,
  });

  final String entity;
  final String entityId;
  final int version;
  final bool deleted;
  final Map<String, dynamic>? data;
}

@DriftAccessor(tables: [OutboxOperations, SyncMeta, LocalEntities])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db);

  // ---------------------------------------------------------------- reads

  Stream<SyncCounts> watchCounts({required int maxAttempts}) {
    final query = customSelect(
      'SELECT state, (attempt_count >= ?) AS exhausted, COUNT(*) AS n, MIN(created_at) AS oldest '
      'FROM outbox_operations GROUP BY state, exhausted',
      variables: [Variable.withInt(maxAttempts)],
      readsFrom: {outboxOperations},
    );
    return query.watch().map((rows) {
      final by = <OpState, int>{};
      var exhausted = 0;
      DateTime? oldest;
      for (final r in rows) {
        final state = OpState.values.byName(r.read<String>('state'));
        final n = r.read<int>('n');
        by[state] = (by[state] ?? 0) + n;
        if (state == OpState.retryWait && r.read<bool>('exhausted')) exhausted += n;
        if (state.isPending) {
          final o = DateTime.fromMillisecondsSinceEpoch(r.read<int>('oldest') * 1000);
          if (oldest == null || o.isBefore(oldest)) oldest = o;
        }
      }
      return SyncCounts(
        queued: by[OpState.queued] ?? 0,
        inFlight: by[OpState.inFlight] ?? 0,
        retryWait: by[OpState.retryWait] ?? 0,
        synced: by[OpState.synced] ?? 0,
        conflict: by[OpState.conflict] ?? 0,
        failed: by[OpState.failedPermanent] ?? 0,
        cancelled: by[OpState.cancelled] ?? 0,
        exhausted: exhausted,
        oldestPendingAt: oldest,
      );
    });
  }

  /// Operations that still need the user's or the server's attention, oldest first.
  Stream<List<OutboxOp>> watchOpen({Set<OpState>? states}) {
    final wanted = states ??
        {OpState.queued, OpState.inFlight, OpState.retryWait, OpState.conflict, OpState.failedPermanent};
    return (select(outboxOperations)
          ..where((t) => t.state.isIn(wanted.map((s) => s.name)))
          ..orderBy([(t) => OrderingTerm.asc(t.seq)]))
        .watch();
  }

  Stream<OutboxOp?> watchOp(String clientOperationId) =>
      (select(outboxOperations)..where((t) => t.clientOperationId.equals(clientOperationId))).watchSingleOrNull();

  Future<OutboxOp?> getOp(String clientOperationId) =>
      (select(outboxOperations)..where((t) => t.clientOperationId.equals(clientOperationId))).getSingleOrNull();

  Future<List<OutboxOp>> getOps(Iterable<String> ids) =>
      (select(outboxOperations)..where((t) => t.clientOperationId.isIn(ids))).get();

  /// Non-terminal ops that list [clientOperationId] as a dependency.
  Future<int> countOpenDependents(String clientOperationId) async {
    final rows = await (select(outboxOperations)
          ..where((t) =>
              t.dependsOnJson.like('%"$clientOperationId"%') &
              t.state.isIn([OpState.queued.name, OpState.inFlight.name, OpState.retryWait.name])))
        .get();
    return rows.length;
  }

  /// Next batch to push, in submission order. An op is only included when every
  /// dependency is already synced or sits earlier in the same batch.
  Future<List<OutboxOp>> selectSendable({
    required DateTime now,
    required int limit,
    required int maxAttempts,
    required bool manual,
    Set<String> exclude = const {},
  }) async {
    final candidates = await (select(outboxOperations)
          ..where((t) =>
              t.state.equals(OpState.queued.name) |
              (t.state.equals(OpState.retryWait.name) &
                  (manual
                      ? const Constant(true)
                      : (t.attemptCount.isSmallerThanValue(maxAttempts) &
                          (t.nextAttemptAt.isNull() | t.nextAttemptAt.isSmallerOrEqualValue(now))))))
          ..orderBy([(t) => OrderingTerm.asc(t.seq)]))
        .get();

    final pool = candidates.where((o) => !exclude.contains(o.clientOperationId)).toList();
    final deps = {for (final o in pool) ...decodeDeps(o)};
    final depStates = {for (final d in await getOps(deps)) d.clientOperationId: d.state};

    final batch = <OutboxOp>[];
    final inBatch = <String>{};
    for (final op in pool) {
      if (batch.length >= limit) break;
      final ok = decodeDeps(op).every((d) => inBatch.contains(d) || depStates[d] == OpState.synced);
      if (!ok) continue;
      batch.add(op);
      inBatch.add(op.clientOperationId);
    }
    return batch;
  }

  // --------------------------------------------------------------- writes

  Future<void> insertOp(OutboxOperationsCompanion op) => into(outboxOperations).insert(op);

  /// An app kill while a request was in flight leaves rows IN_FLIGHT. The server
  /// may or may not have committed; resending with the same key is safe.
  Future<int> recoverInterrupted(DateTime now) => (update(outboxOperations)
        ..where((t) => t.state.equals(OpState.inFlight.name)))
      .write(OutboxOperationsCompanion(
        state: const Value(OpState.retryWait),
        nextAttemptAt: Value(now),
        lastErrorCode: const Value('INTERRUPTED'),
        lastErrorMessage: const Value('The app closed while syncing. Safe to retry.'),
        updatedAt: Value(now),
      ));

  Future<void> markInFlight(List<OutboxOp> ops, DateTime now) => transaction(() async {
        for (final op in ops) {
          await (update(outboxOperations)..where((t) => t.seq.equals(op.seq))).write(OutboxOperationsCompanion(
            state: const Value(OpState.inFlight),
            attemptCount: Value(op.attemptCount + 1),
            everSent: const Value(true),
            lastAttemptAt: Value(now),
            nextAttemptAt: const Value(null),
            updatedAt: Value(now),
          ));
        }
      });

  Future<void> updateOp(String clientOperationId, OutboxOperationsCompanion patch) =>
      (update(outboxOperations)..where((t) => t.clientOperationId.equals(clientOperationId))).write(patch);

  /// Atomically moves an op from one of [from] to [to]. Returns false if another
  /// actor (e.g. the sync manager) changed it first.
  Future<bool> compareAndSet(
    String clientOperationId, {
    required Set<OpState> from,
    required OutboxOperationsCompanion to,
    bool requireNeverSent = false,
  }) async {
    final n = await (update(outboxOperations)
          ..where((t) {
            var cond = t.clientOperationId.equals(clientOperationId) & t.state.isIn(from.map((s) => s.name));
            if (requireNeverSent) cond = cond & t.everSent.equals(false);
            return cond;
          }))
        .write(to);
    return n == 1;
  }

  Future<int> pruneSynced(DateTime before) => (delete(outboxOperations)
        ..where((t) => t.state.equals(OpState.synced.name) & t.syncedAt.isSmallerThanValue(before)))
      .go();

  // ------------------------------------------------------------ meta/pull

  Future<String?> readMeta(String key) async =>
      (await (select(syncMeta)..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Stream<String?> watchMeta(String key) =>
      (select(syncMeta)..where((t) => t.key.equals(key))).watchSingleOrNull().map((r) => r?.value);

  Future<void> writeMeta(String key, String value) =>
      into(syncMeta).insertOnConflictUpdate(SyncMetaCompanion.insert(key: key, value: value));

  /// Applies a pulled page and advances the cursor in ONE transaction, so a crash
  /// can never store a cursor for changes that were not applied.
  Future<void> applyPulledPage(List<PulledChange> changes, String nextCursor, String cursorKey) =>
      transaction(() async {
        for (final c in changes) {
          final existing = await (select(localEntities)
                ..where((t) => t.entity.equals(c.entity) & t.entityId.equals(c.entityId)))
              .getSingleOrNull();
          if (existing != null && existing.version > c.version) continue; // never regress
          await into(localEntities).insertOnConflictUpdate(LocalEntitiesCompanion.insert(
            entity: c.entity,
            entityId: c.entityId,
            version: c.version,
            dataJson: Value(c.deleted ? null : jsonEncode(c.data)),
            deleted: Value(c.deleted),
            updatedAt: DateTime.now(),
          ));
        }
        await writeMeta(cursorKey, nextCursor);
      });

  Future<LocalEntity?> getEntity(String entity, String entityId) =>
      (select(localEntities)..where((t) => t.entity.equals(entity) & t.entityId.equals(entityId)))
          .getSingleOrNull();

  Stream<LocalEntity?> watchEntity(String entity, String entityId) =>
      (select(localEntities)..where((t) => t.entity.equals(entity) & t.entityId.equals(entityId)))
          .watchSingleOrNull();
}

List<String> decodeDeps(OutboxOp op) => (jsonDecode(op.dependsOnJson) as List).cast<String>();
