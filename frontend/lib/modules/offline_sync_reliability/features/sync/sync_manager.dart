import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../../core/auth_session.dart';
import '../../core/connectivity_monitor.dart';
import '../../data/local/app_database.dart';
import '../../data/local/outbox_dao.dart';
import '../../data/remote/sync_api.dart';
import 'domain/op_state.dart';
import 'domain/sync_config.dart';

enum SyncPhase { idle, pushing, pulling }

class SyncRunSummary {
  const SyncRunSummary({
    this.synced = 0,
    this.conflicts = 0,
    this.failed = 0,
    this.retrying = 0,
    this.offline = false,
    this.errorCode,
    this.errorMessage,
    this.pulled = false,
    required this.finishedAt,
  });

  final int synced;
  final int conflicts;
  final int failed;
  final int retrying;
  final bool offline;

  /// Transport/auth problem that stopped the run (per-op failures are in the counts).
  final String? errorCode;
  final String? errorMessage;
  final bool pulled;
  final DateTime finishedAt;

  int get attempted => synced + conflicts + failed + retrying;
  bool get isPartial => synced > 0 && (conflicts + failed + retrying) > 0;
  bool get isClean => errorCode == null && !offline && conflicts + failed + retrying == 0;
}

class SyncProgress {
  const SyncProgress({this.phase = SyncPhase.idle, this.done = 0, this.total = 0, this.lastRun});

  final SyncPhase phase;
  final int done;
  final int total;
  final SyncRunSummary? lastRun;

  bool get isSyncing => phase != SyncPhase.idle;
}

class SyncMetaKeys {
  static const deviceId = 'device_id';
  static const pullCursor = 'pull_cursor';
  static const lastSuccessfulSyncAt = 'last_successful_sync_at';
  static const lastPullAt = 'last_pull_at';
}

/// Drives the outbox: pushes bounded batches in dependency order, applies the
/// server's per-operation results, retries with capped backoff, then pulls
/// canonical changes (spec §3).
///
/// Invariants:
///  * every state change is persisted before the next network call;
///  * a retried operation always reuses its original idempotency key;
///  * only a server acknowledgement marks an operation synced.
class SyncManager {
  SyncManager({
    required this.dao,
    required this.api,
    required this.connectivity,
    required this.session,
    required this.deviceId,
    this.config = const SyncConfig(),
    DateTime Function()? clock,
    Random? random,
  })  : _now = clock ?? DateTime.now,
        _backoff = Backoff(config, random);

  final OutboxDao dao;
  final SyncApi api;
  final ConnectivityMonitor connectivity;
  final AuthSession session;
  final String deviceId;
  final SyncConfig config;
  final DateTime Function() _now;
  final Backoff _backoff;

  static const pullInterval = Duration(minutes: 5);

  final _progress = StreamController<SyncProgress>.broadcast();
  SyncProgress _current = const SyncProgress();
  Future<SyncRunSummary>? _running;
  bool _rerun = false;
  bool _rerunManual = false;
  StreamSubscription<bool>? _connSub;
  Timer? _timer;

  SyncProgress get progress => _current;
  Stream<SyncProgress> get progressStream => _progress.stream;

  /// Call once at app start: recovers work interrupted by a crash and wires triggers.
  Future<void> start() async {
    await dao.recoverInterrupted(_now());
    _connSub = connectivity.changes.listen((online) {
      if (online) unawaited(syncNow());
    });
    _timer = Timer.periodic(config.periodicCheck, (_) => unawaited(_tick()));
    if (connectivity.isOnline) unawaited(syncNow());
  }

  Future<void> dispose() async {
    await _connSub?.cancel();
    _timer?.cancel();
    await _progress.close();
  }

  /// Runs a sync, or joins the one in progress (and schedules one more pass so
  /// work queued mid-run is not left waiting).
  ///
  /// [manual] also retries ops that exhausted automatic attempts ("Retry Eligible").
  Future<SyncRunSummary> syncNow({bool manual = false}) {
    final running = _running;
    if (running != null) {
      _rerun = true;
      _rerunManual |= manual;
      return running;
    }
    final future = _runLoop(manual);
    _running = future;
    return future;
  }

  Future<SyncRunSummary> _runLoop(bool manual) async {
    try {
      var summary = await _run(manual: manual);
      while (_rerun && summary.errorCode == null && !summary.offline) {
        final m = _rerunManual;
        _rerun = false;
        _rerunManual = false;
        summary = await _run(manual: m);
      }
      return summary;
    } finally {
      _rerun = false;
      _rerunManual = false;
      _running = null;
    }
  }

  Future<void> _tick() async {
    if (!connectivity.isOnline || _running != null) return;
    final due = await dao.selectSendable(
      now: _now(),
      limit: 1,
      maxAttempts: config.maxAutoAttempts,
      manual: false,
    );
    final lastPull = DateTime.tryParse(await dao.readMeta(SyncMetaKeys.lastPullAt) ?? '');
    final pullDue = lastPull == null || _now().difference(lastPull) >= pullInterval;
    if (due.isNotEmpty || pullDue) await syncNow();
  }

  Future<SyncRunSummary> _run({required bool manual}) async {
    if (!connectivity.isOnline) {
      return _finish(SyncRunSummary(offline: true, finishedAt: _now()));
    }

    var synced = 0, conflicts = 0, failed = 0, retrying = 0;
    String? errorCode, errorMessage;

    final total = (await dao.selectSendable(
      now: _now(),
      limit: 1 << 20,
      maxAttempts: config.maxAutoAttempts,
      manual: manual,
    ))
        .length;
    var done = 0;
    _emit(SyncProgress(phase: SyncPhase.pushing, total: total, lastRun: _current.lastRun));

    // ------------------------------------------------------------------ push
    final attempted = <String>{};
    while (true) {
      final batch = await dao.selectSendable(
        now: _now(),
        limit: config.batchSize,
        maxAttempts: config.maxAutoAttempts,
        manual: manual,
        exclude: attempted,
      );
      if (batch.isEmpty) break;
      attempted.addAll(batch.map((o) => o.clientOperationId));

      await dao.markInFlight(batch, _now());

      final List<OperationResultDto> results;
      try {
        results = await api.push(
          storeId: session.storeId,
          deviceId: deviceId,
          operations: [for (final op in batch) _toWire(op)],
        );
      } on ApiNetworkException catch (e) {
        for (final op in batch) {
          await _scheduleRetry(op, e.code, e.message);
        }
        retrying += batch.length;
        errorCode = e.code;
        errorMessage = e.message;
        break;
      } on ApiHttpException catch (e) {
        if (e.isAuthProblem) {
          // Revoked user/shop must not sync (spec §13). Hold the queue; nothing is lost.
          for (final op in batch) {
            await dao.updateOp(
              op.clientOperationId,
              OutboxOperationsCompanion(
                state: const Value(OpState.retryWait),
                attemptCount: Value(op.attemptCount), // auth problems don't consume attempts
                nextAttemptAt: Value(_now().add(config.backoffCap)),
                lastErrorCode: Value(e.code),
                lastErrorMessage: Value(e.message),
                updatedAt: Value(_now()),
              ),
            );
          }
        } else if (e.isRetryable) {
          for (final op in batch) {
            await _scheduleRetry(op, e.code, e.message, retryAfter: e.retryAfter);
          }
        } else {
          // The envelope itself was rejected (client bug or contract drift).
          for (final op in batch) {
            await _markFailed(op, e.code, e.message);
          }
          failed += batch.length;
        }
        if (e.isAuthProblem || e.isRetryable) retrying += batch.length;
        errorCode = e.code;
        errorMessage = e.message;
        break;
      }

      final byId = {for (final r in results) r.clientOperationId: r};
      for (final op in batch) {
        final r = byId[op.clientOperationId];
        if (r == null) {
          await _scheduleRetry(op, 'NO_RESULT', 'The server did not confirm this change. Safe to retry.');
          retrying++;
          continue;
        }
        switch (r.status) {
          case ResultStatus.synced || ResultStatus.alreadyProcessed:
            await dao.updateOp(
              op.clientOperationId,
              OutboxOperationsCompanion(
                state: const Value(OpState.synced),
                serverResourceId: Value(r.serverResourceId),
                serverVersion: Value(r.version),
                syncedAt: Value(_now()),
                updatedAt: Value(_now()),
                lastErrorCode: const Value(null),
                lastErrorMessage: const Value(null),
                nextAttemptAt: const Value(null),
              ),
            );
            synced++;
          case ResultStatus.conflict:
            await dao.updateOp(
              op.clientOperationId,
              OutboxOperationsCompanion(
                state: const Value(OpState.conflict),
                conflictJson: Value(r.conflict == null ? null : jsonEncode(r.conflict)),
                lastErrorCode: Value(r.errorCode),
                lastErrorMessage: Value(r.message),
                updatedAt: Value(_now()),
              ),
            );
            conflicts++;
          case ResultStatus.failedPermanent:
            if (r.errorCode == 'OPERATION_CANCELLED') {
              await dao.updateOp(
                op.clientOperationId,
                OutboxOperationsCompanion(
                  state: const Value(OpState.cancelled),
                  lastErrorCode: Value(r.errorCode),
                  lastErrorMessage: Value(r.message),
                  updatedAt: Value(_now()),
                ),
              );
            } else {
              await _markFailed(op, r.errorCode ?? 'FAILED', r.message ?? 'The server rejected this change.');
              failed++;
            }
          case ResultStatus.retryableFailure:
            await _scheduleRetry(op, r.errorCode ?? 'RETRYABLE', r.message ?? 'Temporary problem. Safe to retry.',
                retryAfter: r.retryAfter);
            retrying++;
        }
      }
      done += batch.length;
      _emit(SyncProgress(phase: SyncPhase.pushing, done: done, total: max(total, done), lastRun: _current.lastRun));
    }

    // ------------------------------------------------------------------ pull
    var pulled = false;
    if (errorCode == null) {
      _emit(SyncProgress(phase: SyncPhase.pulling, done: done, total: max(total, done), lastRun: _current.lastRun));
      try {
        await _pullAll();
        pulled = true;
        await dao.writeMeta(SyncMetaKeys.lastSuccessfulSyncAt, _now().toIso8601String());
      } on ApiException catch (e) {
        errorCode = e.code;
        errorMessage = e.message;
      }
    }

    await dao.pruneSynced(_now().subtract(config.keepSyncedHistory));

    return _finish(SyncRunSummary(
      synced: synced,
      conflicts: conflicts,
      failed: failed,
      retrying: retrying,
      errorCode: errorCode,
      errorMessage: errorMessage,
      pulled: pulled,
      finishedAt: _now(),
    ));
  }

  Future<void> _pullAll() async {
    var cursor = await dao.readMeta(SyncMetaKeys.pullCursor);
    while (true) {
      final page = await api.pull(
        storeId: session.storeId,
        deviceId: deviceId,
        cursor: cursor,
        limit: config.pullPageSize,
      );
      await dao.applyPulledPage(
        [
          for (final c in page.changes)
            PulledChange(entity: c.entity, entityId: c.entityId, version: c.version, deleted: c.deleted, data: c.data),
        ],
        page.nextCursor,
        SyncMetaKeys.pullCursor,
      );
      cursor = page.nextCursor;
      if (!page.hasMore) break;
    }
    await dao.writeMeta(SyncMetaKeys.lastPullAt, _now().toIso8601String());
  }

  /// [op] is the row as read BEFORE markInFlight, so this attempt is `attemptCount + 1`.
  Future<void> _scheduleRetry(OutboxOp op, String code, String message, {Duration? retryAfter}) async {
    final attempt = op.attemptCount + 1;
    final exhausted = attempt >= config.maxAutoAttempts;
    await dao.updateOp(
      op.clientOperationId,
      OutboxOperationsCompanion(
        state: const Value(OpState.retryWait),
        nextAttemptAt: Value(exhausted ? null : _now().add(_backoff.delayFor(attempt, retryAfter: retryAfter))),
        lastErrorCode: Value(code),
        lastErrorMessage: Value(message),
        updatedAt: Value(_now()),
      ),
    );
  }

  Future<void> _markFailed(OutboxOp op, String code, String message) => dao.updateOp(
        op.clientOperationId,
        OutboxOperationsCompanion(
          state: const Value(OpState.failedPermanent),
          lastErrorCode: Value(code),
          lastErrorMessage: Value(message),
          nextAttemptAt: const Value(null),
          updatedAt: Value(_now()),
        ),
      );

  PushOperation _toWire(OutboxOp op) => PushOperation(
        clientOperationId: op.clientOperationId,
        idempotencyKey: op.idempotencyKey,
        module: op.module,
        operationType: op.operationType,
        payload: jsonDecode(op.payloadJson) as Map<String, dynamic>,
        entityId: op.entityId,
        baseVersion: op.baseVersion,
        dependsOn: decodeDeps(op),
        clientCreatedAt: op.createdAt,
      );

  SyncRunSummary _finish(SyncRunSummary summary) {
    _emit(SyncProgress(lastRun: summary));
    if (summary.errorCode != null) debugPrint('sync: stopped with ${summary.errorCode}');
    return summary;
  }

  void _emit(SyncProgress p) {
    _current = p;
    if (!_progress.isClosed) _progress.add(p);
  }
}
