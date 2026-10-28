import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../core/auth_session.dart';
import '../../core/connectivity_monitor.dart';
import '../../data/local/app_database.dart';
import '../../data/local/outbox_dao.dart';
import '../../data/remote/sync_api.dart';
import 'domain/offline_catalog.dart';
import 'domain/op_state.dart';
import 'domain/sync_config.dart';
import 'sync_manager.dart';

class UnsupportedOfflineAction implements Exception {
  UnsupportedOfflineAction(this.key);
  final String key;
  @override
  String toString() => '"$key" is not supported offline. Repeat it while connected.';
}

class PayloadTooLarge implements Exception {
  @override
  String toString() => 'This change is too large to save offline. Upload attachments separately.';
}

enum CancelOutcome { cancelled, alreadyCommitted, needsConnection, hasDependents, notCancellable, failed }

/// Conflict values as sent by the server (screen E1).
class ConflictInfo {
  ConflictInfo.fromJson(Map<String, dynamic> j)
      : entity = j['entity'] as String,
        entityId = j['entityId'] as String,
        serverVersion = j['serverVersion'] as int,
        clientBaseVersion = j['clientBaseVersion'] as int?,
        serverUpdatedAt = DateTime.tryParse(j['serverUpdatedAt'] as String? ?? '')?.toLocal(),
        serverValues = (j['serverValues'] as Map).cast<String, dynamic>(),
        clientValues = (j['clientValues'] as Map).cast<String, dynamic>();

  final String entity;
  final String entityId;
  final int serverVersion;
  final int? clientBaseVersion;
  final DateTime? serverUpdatedAt;
  final Map<String, dynamic> serverValues;
  final Map<String, dynamic> clientValues;

  List<String> get fields => {...serverValues.keys, ...clientValues.keys}.toList();
}

ConflictInfo? conflictOf(OutboxOp op) =>
    op.conflictJson == null ? null : ConflictInfo.fromJson(jsonDecode(op.conflictJson!) as Map<String, dynamic>);

/// Entry point other modules use to queue offline work, plus the user actions
/// on the sync screens (cancel, retry, resolve).
class SyncRepository {
  SyncRepository({
    required this.dao,
    required this.api,
    required this.session,
    required this.connectivity,
    required this.manager,
    OfflineCatalog? catalog,
    this.config = const SyncConfig(),
    DateTime Function()? clock,
  })  : catalog = catalog ?? OfflineCatalog.standard,
        _now = clock ?? DateTime.now;

  final OutboxDao dao;
  final SyncApi api;
  final AuthSession session;
  final ConnectivityMonitor connectivity;
  final SyncManager manager;
  final OfflineCatalog catalog;
  final SyncConfig config;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  /// Persists an operation in the outbox and returns once it is durable. Only
  /// then may the UI say the action is "saved on this device".
  ///
  /// The `clientOperationId` and idempotency key are generated ONCE here and
  /// reused for every retry of this logical action.
  Future<OutboxOp> enqueue({
    required String module,
    required String operationType,
    required String label,
    required Map<String, dynamic> payload,
    String? entityId,
    int? baseVersion,
    List<String> dependsOn = const [],
    String? resolutionOf,
    bool triggerSync = true,
  }) async {
    if (!catalog.isSupported(module, operationType)) throw UnsupportedOfflineAction('$module.$operationType');
    final payloadJson = jsonEncode(payload);
    if (utf8.encode(payloadJson).length > config.maxPayloadBytes) throw PayloadTooLarge();

    final id = _uuid.v4();
    final now = _now();
    await dao.insertOp(OutboxOperationsCompanion.insert(
      clientOperationId: id,
      idempotencyKey: 'idem_${_uuid.v4()}',
      storeId: session.storeId,
      module: module,
      operationType: operationType,
      label: label,
      entityId: Value(entityId),
      baseVersion: Value(baseVersion),
      payloadJson: payloadJson,
      dependsOnJson: Value(jsonEncode(dependsOn)),
      state: OpState.queued,
      resolutionOf: Value(resolutionOf),
      createdAt: now,
      updatedAt: now,
    ));
    if (triggerSync && connectivity.isOnline) manager.syncNow();
    return (await dao.getOp(id))!;
  }

  /// Cancel is only offered when it is safe (spec §4):
  ///  * never sent → cancelled locally;
  ///  * sent before (it may have committed) → the server must confirm it was not applied.
  Future<CancelOutcome> cancel(String clientOperationId) async {
    final op = await dao.getOp(clientOperationId);
    if (op == null || !canCancel(op)) return CancelOutcome.notCancellable;
    if (await dao.countOpenDependents(clientOperationId) > 0) return CancelOutcome.hasDependents;

    final cancelled = OutboxOperationsCompanion(
      state: const Value(OpState.cancelled),
      resolution: const Value('USER_CANCELLED'),
      nextAttemptAt: const Value(null),
      updatedAt: Value(_now()),
    );

    if (!op.everSent) {
      final ok = await dao.compareAndSet(clientOperationId,
          from: {OpState.queued}, to: cancelled, requireNeverSent: true);
      if (ok) return CancelOutcome.cancelled;
    }

    if (!connectivity.isOnline) return CancelOutcome.needsConnection;
    // Claim the op so the sync manager cannot send it while we ask the server.
    final claimed = await dao.compareAndSet(clientOperationId,
        from: {OpState.queued, OpState.retryWait}, to: const OutboxOperationsCompanion(state: Value(OpState.inFlight)));
    if (!claimed) return CancelOutcome.notCancellable;

    try {
      await api.cancel(
        storeId: op.storeId,
        deviceId: manager.deviceId,
        clientOperationId: op.clientOperationId,
        idempotencyKey: op.idempotencyKey,
        module: op.module,
        operationType: op.operationType,
      );
      await dao.updateOp(clientOperationId, cancelled);
      return CancelOutcome.cancelled;
    } on ApiHttpException catch (e) {
      await _release(op);
      if (e.code == 'ALREADY_COMMITTED') {
        manager.syncNow(); // a resend with the same key returns ALREADY_PROCESSED → synced
        return CancelOutcome.alreadyCommitted;
      }
      return CancelOutcome.failed;
    } on ApiNetworkException {
      await _release(op);
      return CancelOutcome.needsConnection;
    }
  }

  Future<void> _release(OutboxOp op) => dao.updateOp(
        op.clientOperationId,
        OutboxOperationsCompanion(state: Value(op.state), nextAttemptAt: Value(_now()), updatedAt: Value(_now())),
      );

  /// Retries now with the SAME key; includes ops that used up automatic attempts.
  Future<SyncRunSummary> retryNow(String clientOperationId) async {
    await dao.compareAndSet(
      clientOperationId,
      from: {OpState.retryWait},
      to: OutboxOperationsCompanion(nextAttemptAt: Value(_now()), updatedAt: Value(_now())),
    );
    return manager.syncNow(manual: true);
  }

  /// "Keep server version": the device change is dropped and the server records
  /// the decision in its audit trail. Canonical values arrive through pull.
  Future<void> resolveKeepServer(OutboxOp op) async {
    await api.cancel(
      storeId: op.storeId,
      deviceId: manager.deviceId,
      clientOperationId: op.clientOperationId,
      idempotencyKey: op.idempotencyKey,
      module: op.module,
      operationType: op.operationType,
    );
    await dao.updateOp(
      op.clientOperationId,
      OutboxOperationsCompanion(
        state: const Value(OpState.cancelled),
        resolution: const Value('KEEP_SERVER'),
        updatedAt: Value(_now()),
      ),
    );
    await manager.syncNow();
  }

  /// "Keep this device version": submits the device values as a NEW operation
  /// based on the server's current version. The original op is closed, so its
  /// key is never reused with a different payload.
  Future<OutboxOp> resolveKeepDevice(OutboxOp op) async {
    final conflict = conflictOf(op);
    final spec = catalog.lookup(op.module, op.operationType);
    if (conflict == null || spec == null || !spec.allowKeepDeviceVersion) {
      throw StateError('Keeping the device version is not permitted for ${op.module}.${op.operationType}');
    }
    final resolution = await enqueue(
      module: op.module,
      operationType: op.operationType,
      label: op.label,
      payload: jsonDecode(op.payloadJson) as Map<String, dynamic>,
      entityId: op.entityId,
      baseVersion: conflict.serverVersion,
      resolutionOf: op.clientOperationId,
      triggerSync: false,
    );
    await dao.updateOp(
      op.clientOperationId,
      OutboxOperationsCompanion(
        state: const Value(OpState.cancelled),
        resolution: const Value('KEEP_DEVICE'),
        updatedAt: Value(_now()),
      ),
    );
    if (connectivity.isOnline) {
      // Best effort: closes the conflicted op in the server's audit trail. The
      // resolution itself does not depend on it (the new op carries the change).
      try {
        await api.cancel(
          storeId: op.storeId,
          deviceId: manager.deviceId,
          clientOperationId: op.clientOperationId,
          idempotencyKey: op.idempotencyKey,
          module: op.module,
          operationType: op.operationType,
        );
      } on ApiException {
        // Left as CONFLICT on the server; harmless because its key is never reused.
      }
      await manager.syncNow();
    }
    return (await dao.getOp(resolution.clientOperationId))!;
  }
}

/// Cancel is allowed for unsent work, and for retrying work the server can still refuse.
bool canCancel(OutboxOp op) => op.state == OpState.queued || op.state == OpState.retryWait;
