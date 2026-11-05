import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/remote/api_client.dart';
import '../../data/remote/integrations_api.dart';
import '../sync/sync_providers.dart';

/// Overridden in `main()`.
final integrationsApiProvider = Provider<IntegrationsApi>((ref) => throw UnimplementedError());

const healthCacheKey = 'integration_health_cache';

/// What screen 6 shows: the latest report, and whether it is the live one or
/// the last cached check (offline / server unreachable).
class HealthView {
  const HealthView({required this.report, this.stale = false, this.offline = false, this.error});

  final HealthReport report;

  /// Showing a cached report because the live check could not be fetched.
  final bool stale;
  final bool offline;
  final String? error;

  List<ModuleHealth> get problems => report.modules.where((m) => m.hasProblem).toList();
  List<ModuleHealth> get others => report.modules.where((m) => !m.hasProblem).toList();
}

final integrationHealthProvider =
    AsyncNotifierProvider.autoDispose<IntegrationHealthController, HealthView>(IntegrationHealthController.new);

class IntegrationHealthController extends AsyncNotifier<HealthView> {
  Timer? _timer;

  @override
  Future<HealthView> build() async {
    ref.onDispose(() => _timer?.cancel());
    // Rebuilds when connectivity changes, so coming back online refreshes the screen.
    final online = ref.watch(isOnlineProvider).value ?? ref.read(connectivityProvider).isOnline;
    final dao = ref.watch(outboxDaoProvider);

    HealthView view;
    if (!online) {
      view = await _fromCache(offline: true) ?? (throw const ApiNetworkException('OFFLINE', 'You\'re offline.', isTimeout: false));
    } else {
      try {
        final report = await ref.read(integrationsApiProvider).health(storeId: ref.read(authSessionProvider).storeId);
        await dao.writeMeta(healthCacheKey, jsonEncode(report.toJson()));
        view = HealthView(report: report);
      } on ApiException catch (e) {
        view = await _fromCache(error: e.message) ?? (throw e);
      }
    }

    // Auto-refresh (F1: "Auto-refresh every 5 min") while the screen is open.
    _timer?.cancel();
    _timer = Timer(view.report.refreshAfter, ref.invalidateSelf);
    return view;
  }

  Future<HealthView?> _fromCache({bool offline = false, String? error}) async {
    final raw = await ref.read(outboxDaoProvider).readMeta(healthCacheKey);
    if (raw == null) return null;
    final report = HealthReport.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return HealthView(report: report, stale: true, offline: offline, error: error);
  }

  /// "Retry check" for one module. Throws [ApiException] for the UI to report.
  Future<ModuleHealth> recheck(String key) async {
    final module = await ref.read(integrationsApiProvider).recheck(storeId: ref.read(authSessionProvider).storeId, key: key);
    final current = state.value;
    if (current != null) {
      final report = current.report.replace(module);
      await ref.read(outboxDaoProvider).writeMeta(healthCacheKey, jsonEncode(report.toJson()));
      state = AsyncData(HealthView(report: report, stale: current.stale, offline: current.offline, error: current.error));
    }
    return module;
  }
}
