import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_session.dart';
import '../../core/connectivity_monitor.dart';
import '../../data/local/app_database.dart';
import '../../data/local/outbox_dao.dart';
import '../../data/remote/sync_api.dart';
import 'domain/offline_catalog.dart';
import 'domain/op_state.dart';
import 'domain/sync_config.dart';
import 'sync_manager.dart';
import 'sync_repository.dart';

/// Overridden in `main()` once the database, device id and manager are ready.
final appDatabaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError());
final syncManagerProvider = Provider<SyncManager>((ref) => throw UnimplementedError());
final connectivityProvider = Provider<ConnectivityMonitor>((ref) => throw UnimplementedError());
final syncApiProvider = Provider<SyncApi>((ref) => throw UnimplementedError());
final authSessionProvider = Provider<AuthSession>((ref) => const DevAuthSession());

final syncConfigProvider = Provider<SyncConfig>((ref) => const SyncConfig());
final offlineCatalogProvider = Provider<OfflineCatalog>((ref) => OfflineCatalog.standard);
final outboxDaoProvider = Provider<OutboxDao>((ref) => ref.watch(appDatabaseProvider).outboxDao);

final syncRepositoryProvider = Provider<SyncRepository>((ref) => SyncRepository(
      dao: ref.watch(outboxDaoProvider),
      api: ref.watch(syncApiProvider),
      session: ref.watch(authSessionProvider),
      connectivity: ref.watch(connectivityProvider),
      manager: ref.watch(syncManagerProvider),
      catalog: ref.watch(offlineCatalogProvider),
      config: ref.watch(syncConfigProvider),
    ));

final syncCountsProvider = StreamProvider<SyncCounts>((ref) =>
    ref.watch(outboxDaoProvider).watchCounts(maxAttempts: ref.watch(syncConfigProvider).maxAutoAttempts));

final syncProgressProvider = StreamProvider<SyncProgress>((ref) async* {
  final manager = ref.watch(syncManagerProvider);
  yield manager.progress;
  yield* manager.progressStream;
});

final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final c = ref.watch(connectivityProvider);
  yield c.isOnline;
  yield* c.changes;
});

final lastSuccessfulSyncProvider = StreamProvider<DateTime?>((ref) => ref
    .watch(outboxDaoProvider)
    .watchMeta(SyncMetaKeys.lastSuccessfulSyncAt)
    .map((v) => v == null ? null : DateTime.tryParse(v)));

/// Filters on the Pending Operations screen (C1). `null` = All.
final openOpsProvider = StreamProvider.family<List<OutboxOp>, OpState?>((ref, filter) =>
    ref.watch(outboxDaoProvider).watchOpen(states: filter == null ? null : {filter}));

/// One-shot lookup for labels that don't need live updates (e.g. a ticket's related operation).
final operationOnceProvider =
    FutureProvider.autoDispose.family<OutboxOp?, String>((ref, id) => ref.watch(outboxDaoProvider).getOp(id));

final operationProvider =
    StreamProvider.family<OutboxOp?, String>((ref, id) => ref.watch(outboxDaoProvider).watchOp(id));

/// Ticks every 30s so relative times ("2 min ago") stay fresh.
final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now());
});
