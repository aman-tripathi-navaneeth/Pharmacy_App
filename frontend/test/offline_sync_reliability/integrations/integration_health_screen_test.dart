import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/modules/offline_sync_reliability/app/theme.dart';
import 'package:pharmacy_app/modules/offline_sync_reliability/data/local/app_database.dart';
import 'package:pharmacy_app/modules/offline_sync_reliability/data/remote/api_client.dart';
import 'package:pharmacy_app/modules/offline_sync_reliability/data/remote/integrations_api.dart';
import 'package:pharmacy_app/modules/offline_sync_reliability/features/integrations/integration_health_controller.dart';
import 'package:pharmacy_app/modules/offline_sync_reliability/features/integrations/integration_health_screen.dart';
import 'package:pharmacy_app/modules/offline_sync_reliability/features/sync/sync_providers.dart';

import '../support/fakes.dart';
import '../support/l10n.dart';

final _t0 = DateTime(2026, 10, 21, 10, 30);

ModuleHealth _m(String key, String label, HealthStatus s, {String? message, String? guidance, DateTime? lastOkAt}) =>
    ModuleHealth(
      key: key,
      label: label,
      status: s,
      message: message,
      guidance: guidance,
      lastCheckedAt: _t0,
      lastOkAt: lastOkAt ?? (s == HealthStatus.operational ? _t0 : null),
    );

HealthReport _report(List<ModuleHealth> modules) =>
    HealthReport(overall: HealthStatus.operational, checkedAt: _t0, refreshAfter: const Duration(minutes: 5), modules: modules);

final _healthy = _report([
  _m('inventory', 'Inventory', HealthStatus.operational),
  _m('sales', 'Sales', HealthStatus.notConnected, message: 'Not connected yet. This module has not published a health check.'),
  _m('payments', 'Payments', HealthStatus.operational),
]);

final _problems = _report([
  _m('inventory', 'Inventory', HealthStatus.operational),
  _m(
    'payments',
    'Payments',
    HealthStatus.degraded,
    guidance: 'Confirmations are delayed. Payments stay pending until the provider confirms. Do not take the payment again.',
  ),
  _m(
    'notifications',
    'Notifications / WhatsApp',
    HealthStatus.unavailable,
    message: 'Did not respond in time.',
    guidance: 'Notifications queue on the server and send when restored.',
    lastOkAt: DateTime(2026, 10, 21, 9, 12),
  ),
]);

class FakeIntegrationsApi implements IntegrationsApi {
  HealthReport? report;
  ApiException? error;
  final rechecked = <String>[];
  ModuleHealth Function(String key)? onRecheck;

  @override
  Future<HealthReport> health({required String storeId}) async {
    if (error != null) throw error!;
    return report!;
  }

  @override
  Future<ModuleHealth> recheck({required String storeId, required String key}) async {
    rechecked.add(key);
    return onRecheck!(key);
  }
}

void main() {
  setUpAll(useEnglish);
  late AppDatabase db;
  late FakeIntegrationsApi api;
  late FakeConnectivity net;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    api = FakeIntegrationsApi();
    net = FakeConnectivity();
  });

  tearDown(() => db.close());

  /// Drift and fake-API futures complete outside the test's fake clock.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        connectivityProvider.overrideWithValue(net),
        authSessionProvider.overrideWithValue(FakeSession()),
        integrationsApiProvider.overrideWithValue(api),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: const IntegrationHealthScreen()),
    ));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }

  testWidgets('F1 healthy: every module listed with status, auto-refresh note', (tester) async {
    api.report = _healthy;
    await pumpScreen(tester);

    expect(find.text('Last checked 10:30 · Auto-refresh every 5 min'), findsOneWidget);
    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Operational · Checked 10:30'), findsNWidgets(2));
    expect(find.text('OK'), findsNWidgets(2));
    expect(find.text('Not set up'), findsOneWidget, reason: 'unconnected modules are never shown as OK');
    expect(find.text('Retry check'), findsNothing);
    await unmount(tester);
  });

  testWidgets('F2/F3 problems first with guidance and last-known time', (tester) async {
    api.report = _problems;
    await pumpScreen(tester);

    expect(find.text('Payments · Degraded'), findsOneWidget);
    expect(find.textContaining('Do not take the payment again'), findsOneWidget);
    expect(find.text('Notifications / WhatsApp · Unavailable'), findsOneWidget);
    expect(find.text('Last known: Operational at 09:12.'), findsOneWidget);
    expect(find.text('Retry check'), findsNWidgets(2));
    expect(find.text('Other modules'), findsOneWidget);
    expect(find.text('Last checked 10:30'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Retry check re-runs one module and updates it in place', (tester) async {
    api
      ..report = _problems
      ..onRecheck = (key) => _m(key, 'Payments', HealthStatus.operational);
    await pumpScreen(tester);

    await tester.tap(find.text('Retry check').first);
    await settle(tester);

    expect(api.rechecked, ['payments']);
    expect(find.text('Payments · Degraded'), findsNothing);
    expect(find.text('Payments is operational again.'), findsOneWidget);
    expect(find.text('Retry check'), findsOneWidget, reason: 'notifications still unavailable');
    await unmount(tester);
  });

  testWidgets('server unreachable → last cached check with a banner', (tester) async {
    api.report = _problems;
    await pumpScreen(tester);
    await unmount(tester);

    api.error = const ApiNetworkException('NETWORK_UNAVAILABLE', 'Could not reach the server.', isTimeout: false);
    await pumpScreen(tester);
    expect(find.text('Couldn’t refresh · Showing the last check from 10:30.'), findsOneWidget);
    expect(find.text('Payments · Degraded'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('offline with nothing cached → explains, offers retry', (tester) async {
    net.online = false;
    await pumpScreen(tester);
    expect(find.text('Couldn\'t load integration health'), findsOneWidget);
    expect(find.textContaining('You\'re offline'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('offline with cache → read-only last check, retry disabled', (tester) async {
    api.report = _problems;
    await pumpScreen(tester);
    await unmount(tester);

    net.online = false;
    await pumpScreen(tester);
    expect(find.text('Offline · Showing the last check from 10:30.'), findsOneWidget);
    final buttons = tester.widgetList<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Retry check'));
    expect(buttons.every((b) => b.onPressed == null), isTrue);
    await unmount(tester);
  });
}
