import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_store/data/local/app_database.dart';
import 'package:medical_store/data/remote/sync_api.dart';
import 'package:medical_store/features/sync/domain/op_state.dart';
import 'package:medical_store/features/sync/domain/sync_config.dart';
import 'package:medical_store/features/sync/sync_manager.dart';
import 'package:medical_store/features/sync/sync_repository.dart';

import '../support/fakes.dart';

/// In-memory server that honours idempotency exactly like the NestJS API.
class FakeServer implements SyncApi {
  final executed = <String, int>{}; // idempotencyKey → times the domain write ran
  final ledger = <String, OperationResultDto>{};
  final requests = <List<PushOperation>>[];
  final cancelled = <String>[];
  int pulls = 0;

  /// Decide the outcome for a fresh (never processed) op.
  OperationResultDto Function(PushOperation op)? decide;

  /// Throw instead of answering; `commitFirst` simulates a timeout AFTER the server committed.
  ApiException? failNext;
  bool commitFirst = false;

  @override
  Future<List<OperationResultDto>> push({
    required String storeId,
    required String deviceId,
    required List<PushOperation> operations,
  }) async {
    requests.add(operations);
    if (failNext != null && !commitFirst) throw _take();
    final results = [
      for (final op in operations)
        if (ledger.containsKey(op.idempotencyKey))
          OperationResultDto(
            clientOperationId: op.clientOperationId,
            status: ResultStatus.alreadyProcessed,
            serverResourceId: ledger[op.idempotencyKey]!.serverResourceId,
          )
        else
          _process(op),
    ];
    if (failNext != null) throw _take();
    return results;
  }

  ApiException _take() {
    final e = failNext!;
    failNext = null;
    commitFirst = false;
    return e;
  }

  OperationResultDto _process(PushOperation op) {
    final r = decide?.call(op) ??
        OperationResultDto(
          clientOperationId: op.clientOperationId,
          status: ResultStatus.synced,
          serverResourceId: 'srv_${executed.length + 1}',
        );
    if (r.status == ResultStatus.synced) {
      executed.update(op.idempotencyKey, (n) => n + 1, ifAbsent: () => 1);
      ledger[op.idempotencyKey] = r;
    }
    return r;
  }

  @override
  Future<PullPage> pull({required String storeId, required String deviceId, String? cursor, int? limit}) async {
    pulls++;
    final c = int.parse(cursor ?? '0');
    if (c >= 3) return PullPage(changes: [], nextCursor: '$c', hasMore: false);
    return PullPage(
      changes: [
        PullChangeDto.fromJson({
          'entity': 'stock_balance',
          'entityId': 'p${c + 1}',
          'version': c + 1,
          'data': {'quantity': (c + 1) * 10},
        }),
      ],
      nextCursor: '${c + 1}',
      hasMore: c + 1 < 3,
    );
  }

  @override
  Future<void> cancel({
    required String storeId,
    required String deviceId,
    required String clientOperationId,
    required String idempotencyKey,
    required String module,
    required String operationType,
  }) async {
    if (ledger.containsKey(idempotencyKey)) {
      throw const ApiHttpException(409, 'ALREADY_COMMITTED', 'Already applied');
    }
    cancelled.add(clientOperationId);
  }
}

void main() {
  late Directory dir;
  late File dbFile;
  late AppDatabase db;
  late FakeServer server;
  late FakeConnectivity net;
  late DateTime now;
  late SyncManager manager;
  late SyncRepository repo;
  const config = SyncConfig(batchSize: 50);

  SyncManager buildManager() => SyncManager(
        dao: db.outboxDao,
        api: server,
        connectivity: net,
        session: FakeSession(),
        deviceId: 'device-1',
        config: config,
        clock: () => now,
        random: Random(1),
      );

  SyncRepository buildRepo() => SyncRepository(
        dao: db.outboxDao,
        api: server,
        session: FakeSession(),
        connectivity: net,
        manager: manager,
        config: config,
        clock: () => now,
      );

  Future<OutboxOp> stock(int delta, {List<String> dependsOn = const []}) => repo.enqueue(
        module: 'inventory',
        operationType: 'stock_movement',
        label: 'Stock movement',
        payload: {'productId': 'p1', 'quantityDelta': delta, 'reason': 'PURCHASE'},
        dependsOn: dependsOn,
        triggerSync: false,
      );

  Future<OutboxOp> reload(OutboxOp op) async => (await db.outboxDao.getOp(op.clientOperationId))!;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sync_test');
    dbFile = File('${dir.path}/app.sqlite');
    db = AppDatabase(NativeDatabase(dbFile));
    server = FakeServer();
    net = FakeConnectivity();
    now = DateTime(2026, 10, 21, 10);
    manager = buildManager();
    repo = buildRepo();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('offline actions are durable across an app restart and keep their order', () async {
    net.online = false;
    final a = await stock(10);
    final b = await stock(-2);
    expect(a.state, OpState.queued);
    expect((await manager.syncNow()).offline, isTrue);
    expect(server.requests, isEmpty);

    await db.close(); // process death
    db = AppDatabase(NativeDatabase(dbFile));
    manager = buildManager();
    net.online = true;
    final summary = await manager.syncNow();

    expect(summary.synced, 2);
    expect(server.requests.single.map((o) => o.clientOperationId), [a.clientOperationId, b.clientOperationId]);
    expect((await reload(a)).state, OpState.synced);
    expect((await reload(a)).serverResourceId, isNotNull);
  });

  test('pull applies all pages and stores the cursor', () async {
    final summary = await manager.syncNow();
    expect(summary.pulled, isTrue);
    expect(server.pulls, 3);
    expect(await db.outboxDao.readMeta(SyncMetaKeys.pullCursor), '3');
    expect((await db.outboxDao.getEntity('stock_balance', 'p3'))!.version, 3);
    expect(await db.outboxDao.readMeta(SyncMetaKeys.lastSuccessfulSyncAt), isNotNull);
  });

  test('timeout after server commit → retry reuses the key → exactly one server write', () async {
    final op = await stock(5);
    server
      ..failNext = const ApiNetworkException('NETWORK_TIMEOUT', 'Network timed out. Safe to retry.', isTimeout: true)
      ..commitFirst = true;

    final first = await manager.syncNow();
    expect(first.errorCode, 'NETWORK_TIMEOUT');
    var row = await reload(op);
    expect(row.state, OpState.retryWait);
    expect(row.attemptCount, 1);
    expect(row.nextAttemptAt, isNotNull);
    expect(row.lastErrorMessage, contains('Safe to retry'));

    now = now.add(const Duration(minutes: 1));
    await manager.syncNow();
    row = await reload(op);
    expect(row.state, OpState.synced);
    expect(server.requests.map((r) => r.single.idempotencyKey).toSet(), {op.idempotencyKey});
    expect(server.executed[op.idempotencyKey], 1);
  });

  test('ops left IN_FLIGHT by a crash are recovered and resent with the same key', () async {
    final op = await stock(3);
    await db.outboxDao.markInFlight([op], now);
    await manager.start();
    await manager.syncNow();
    expect((await reload(op)).state, OpState.synced);
    expect(server.requests.last.single.idempotencyKey, op.idempotencyKey);
    await manager.dispose();
  });

  test('partial batch: each op gets its own outcome', () async {
    final ok = await stock(1);
    final bad = await stock(-999);
    final conflicted = await stock(2);
    final flaky = await stock(3);
    server.decide = (o) => switch (o.clientOperationId) {
          final id when id == bad.clientOperationId => OperationResultDto(
              clientOperationId: id,
              status: ResultStatus.failedPermanent,
              errorCode: 'INSUFFICIENT_STOCK',
              message: 'Stock quantity exceeds available balance.'),
          final id when id == conflicted.clientOperationId => OperationResultDto(
              clientOperationId: id,
              status: ResultStatus.conflict,
              errorCode: 'VERSION_CONFLICT',
              conflict: {
                'entity': 'shop_profile',
                'entityId': 's',
                'serverVersion': 7,
                'serverValues': {'phone': 'a'},
                'clientValues': {'phone': 'b'},
              }),
          final id when id == flaky.clientOperationId => OperationResultDto(
              clientOperationId: id, status: ResultStatus.retryableFailure, errorCode: 'TRANSIENT_ERROR'),
          _ => OperationResultDto(clientOperationId: o.clientOperationId, status: ResultStatus.synced, serverResourceId: 'x'),
        };

    final s = await manager.syncNow();
    expect([s.synced, s.failed, s.conflicts, s.retrying], [1, 1, 1, 1]);
    expect(s.isPartial, isTrue);
    expect((await reload(ok)).state, OpState.synced);
    expect((await reload(bad)).state, OpState.failedPermanent);
    expect((await reload(bad)).lastErrorMessage, contains('exceeds available balance'));
    expect((await reload(conflicted)).state, OpState.conflict);
    expect(conflictOf(await reload(conflicted))!.serverVersion, 7);
    expect((await reload(flaky)).state, OpState.retryWait);

    // A replay of the whole batch must not duplicate the synced op.
    server.decide = null;
    now = now.add(const Duration(minutes: 10));
    await manager.syncNow(manual: true);
    expect(server.executed[ok.idempotencyKey], 1);
    expect(server.requests.last.map((o) => o.clientOperationId), [flaky.clientOperationId]);
  });

  test('backoff grows, stops after 8 attempts, and manual retry still works', () async {
    final op = await stock(1);
    final delays = <Duration>[];
    for (var i = 0; i < config.maxAutoAttempts; i++) {
      server.failNext = const ApiHttpException(503, 'UNAVAILABLE', 'Server busy');
      await manager.syncNow();
      final row = await reload(op);
      if (row.nextAttemptAt != null) {
        delays.add(row.nextAttemptAt!.difference(now));
        now = row.nextAttemptAt!;
      }
    }
    final row = await reload(op);
    expect(row.attemptCount, 8);
    expect(row.state, OpState.retryWait);
    expect(row.nextAttemptAt, isNull, reason: 'exhausted → needs attention');
    expect(delays.first.inMilliseconds, inInclusiveRange(1000, 2000));
    expect(delays.last, lessThanOrEqualTo(config.backoffCap));
    expect(delays[3] > delays[0], isTrue);

    final requestsBefore = server.requests.length;
    now = now.add(const Duration(hours: 1));
    await manager.syncNow();
    expect(server.requests.length, requestsBefore, reason: 'no automatic send after cap');

    await repo.retryNow(op.clientOperationId);
    expect((await reload(op)).state, OpState.synced);
  });

  test('auth rejection holds the queue without consuming attempts', () async {
    final op = await stock(1);
    server.failNext = const ApiHttpException(403, 'STORE_SUSPENDED', 'This shop is suspended.');
    final s = await manager.syncNow();
    expect(s.errorCode, 'STORE_SUSPENDED');
    final row = await reload(op);
    expect(row.state, OpState.retryWait);
    expect(row.attemptCount, 0);
    expect(row.lastErrorCode, 'STORE_SUSPENDED');
  });

  test('batches are bounded and dependencies wait for their parent', () async {
    final ops = [for (var i = 0; i < 120; i++) await stock(1)];
    await manager.syncNow();
    expect(server.requests.map((r) => r.length), [50, 50, 20]);
    expect(ops.length, 120);

    final parent = await stock(1);
    final child = await stock(-1, dependsOn: [parent.clientOperationId]);
    server.decide = (o) => o.clientOperationId == parent.clientOperationId
        ? OperationResultDto(clientOperationId: o.clientOperationId, status: ResultStatus.retryableFailure)
        : OperationResultDto(clientOperationId: o.clientOperationId, status: ResultStatus.synced);
    server.requests.clear();
    await manager.syncNow();
    expect(server.requests.single.map((o) => o.clientOperationId), [parent.clientOperationId, child.clientOperationId],
        reason: 'parent first; child allowed because parent precedes it in the batch');
    expect((await reload(child)).state, OpState.synced);
  });

  test('a dependent op is not sent while its parent is waiting', () async {
    net.online = false;
    final parent = await stock(1);
    await db.outboxDao.markInFlight([parent], now);
    await db.outboxDao.recoverInterrupted(now.add(const Duration(hours: 1))); // parent not due yet
    final child = await stock(-1, dependsOn: [parent.clientOperationId]);
    net.online = true;
    await manager.syncNow();
    expect(server.requests, isEmpty);
    expect((await reload(child)).state, OpState.queued);
  });

  group('cancel', () {
    test('never-sent op is cancelled locally', () async {
      final op = await stock(1);
      expect(await repo.cancel(op.clientOperationId), CancelOutcome.cancelled);
      expect((await reload(op)).state, OpState.cancelled);
      expect(server.cancelled, isEmpty);
      await manager.syncNow();
      expect(server.requests, isEmpty);
    });

    test('previously-sent op needs server confirmation', () async {
      final op = await stock(1);
      server.failNext = const ApiNetworkException('NETWORK_TIMEOUT', 't', isTimeout: true);
      await manager.syncNow();
      expect(await repo.cancel(op.clientOperationId), CancelOutcome.cancelled);
      expect(server.cancelled, [op.clientOperationId]);

      net.online = false;
      final op2 = await stock(1);
      await db.outboxDao.markInFlight([op2], now);
      await db.outboxDao.recoverInterrupted(now);
      expect(await repo.cancel(op2.clientOperationId), CancelOutcome.needsConnection);
      expect((await reload(op2)).state, OpState.retryWait);
    });

    test('op committed on the server cannot be cancelled', () async {
      final op = await stock(1);
      server
        ..failNext = const ApiNetworkException('NETWORK_TIMEOUT', 't', isTimeout: true)
        ..commitFirst = true;
      await manager.syncNow();
      expect(await repo.cancel(op.clientOperationId), CancelOutcome.alreadyCommitted);
      await manager.syncNow();
      expect((await reload(op)).state, OpState.synced);
      expect(server.executed[op.idempotencyKey], 1);
    });

    test('refuses while other queued ops depend on it', () async {
      final parent = await stock(1);
      await stock(-1, dependsOn: [parent.clientOperationId]);
      expect(await repo.cancel(parent.clientOperationId), CancelOutcome.hasDependents);
    });
  });

  group('conflict resolution', () {
    Future<OutboxOp> conflicted() async {
      final op = await repo.enqueue(
        module: 'shop',
        operationType: 'profile_update',
        label: 'Shop profile',
        entityId: 'store-1',
        baseVersion: 6,
        payload: {
          'fields': {'phone': '+91 98000 10243'},
        },
        triggerSync: false,
      );
      server.decide = (o) => OperationResultDto(
            clientOperationId: o.clientOperationId,
            status: ResultStatus.conflict,
            errorCode: 'VERSION_CONFLICT',
            message: 'Shop profile changed on another device.',
            conflict: {
              'entity': 'shop_profile',
              'entityId': 'store-1',
              'serverVersion': 7,
              'clientBaseVersion': 6,
              'serverValues': {'phone': '+91 98000 10234'},
              'clientValues': {'phone': '+91 98000 10243'},
            },
          );
      await manager.syncNow();
      server.decide = null;
      return reload(op);
    }

    test('keep device → NEW op based on the server version; original closed', () async {
      final op = await conflicted();
      expect(op.state, OpState.conflict);
      final next = await repo.resolveKeepDevice(op);
      expect(next.clientOperationId, isNot(op.clientOperationId));
      expect(next.idempotencyKey, isNot(op.idempotencyKey));
      expect(next.baseVersion, 7);
      expect(next.resolutionOf, op.clientOperationId);
      expect(next.state, OpState.synced);
      final original = await reload(op);
      expect(original.state, OpState.cancelled);
      expect(original.resolution, 'KEEP_DEVICE');
      expect(server.cancelled, [op.clientOperationId], reason: 'server audit closes the conflicted op');
    });

    test('keep server → server audit call, local op closed', () async {
      final op = await conflicted();
      await repo.resolveKeepServer(op);
      expect(server.cancelled, [op.clientOperationId]);
      final row = await reload(op);
      expect(row.state, OpState.cancelled);
      expect(row.resolution, 'KEEP_SERVER');
    });

    test('keep device is refused for ledger operations', () async {
      final op = await stock(1);
      await db.outboxDao.updateOp(
        op.clientOperationId,
        const OutboxOperationsCompanion(state: Value(OpState.conflict), conflictJson: Value('{"entity":"x","entityId":"y","serverVersion":1,"serverValues":{},"clientValues":{}}')),
      );
      await expectLater(repo.resolveKeepDevice(await reload(op)), throwsStateError);
    });
  });

  test('unsupported offline actions are refused before anything is stored', () async {
    await expectLater(
      repo.enqueue(module: 'payments', operationType: 'settle', label: 'x', payload: {}),
      throwsA(isA<UnsupportedOfflineAction>()),
    );
    expect(await db.outboxDao.selectSendable(now: now, limit: 10, maxAttempts: 8, manual: true), isEmpty);
  });
}
