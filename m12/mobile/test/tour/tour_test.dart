import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_store/app/theme.dart';
import 'package:medical_store/data/local/app_database.dart';
import 'package:medical_store/data/local/outbox_dao.dart';
import 'package:medical_store/data/remote/api_client.dart';
import 'package:medical_store/data/remote/tour_api.dart';
import 'package:medical_store/features/tour/tour_controller.dart';
import 'package:medical_store/features/tour/tour_models.dart';
import 'package:medical_store/features/tour/tour_repository.dart';
import 'package:medical_store/features/tour/tour_screen.dart';

import '../support/l10n.dart';

class FakeTourApi implements TourApi {
  bool offline = false;
  final saved = <String>[];
  TourDefinition? newer;
  TourProgress? remote;

  ApiException get _down => const ApiNetworkException('NETWORK_UNAVAILABLE', 'offline', isTimeout: false);

  @override
  Future<TourDefinition> latest() async {
    if (offline) throw _down;
    return newer ?? TourDefinition.fromJson(jsonDecode(File('assets/tour/2026.10.1.json').readAsStringSync()) as Map<String, dynamic>);
  }

  @override
  Future<TourProgress?> progress(String version) async {
    if (offline) throw _down;
    return remote;
  }

  @override
  Future<void> save({required String version, required String stepId, required TourStatus status}) async {
    if (offline) throw _down;
    saved.add('$stepId:${status.wire}');
  }
}

void main() {
  late AppDatabase db;
  late FakeTourApi api;
  late TourRepository repo;
  late Map<String, dynamic> tourJson;

  setUpAll(useEnglish);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    api = FakeTourApi();
    repo = TourRepository(dao: db.outboxDao, api: api, bundle: DiskBundle());
    tourJson = jsonDecode(File('assets/tour/2026.10.1.json').readAsStringSync()) as Map<String, dynamic>;
  });
  tearDown(() => db.close());

  test('every tour step uses keys that exist in English', () {
    final en = loadCatalog('en');
    final def = TourDefinition.fromJson(tourJson);
    expect(def.steps, hasLength(6));
    expect(def.steps.last.type, TourStepType.finish);
    for (final s in def.steps) {
      for (final k in [s.titleKey, ?s.bodyKey, for (final i in s.items) ...[i.labelKey, i.descriptionKey]]) {
        expect(en.messages, contains(k), reason: '${s.id}: $k');
      }
    }
  });

  test('auto-launch only for a never-started tour, and not over work needing attention', () {
    final def = TourDefinition.fromJson(tourJson);
    expect(shouldAutoLaunch(TourState(definition: def), const SyncCounts()), isTrue);
    expect(shouldAutoLaunch(TourState(definition: def), const SyncCounts(conflict: 1)), isFalse);
    const skipped = TourProgress(status: TourStatus.skipped, lastStepId: 'welcome');
    expect(shouldAutoLaunch(TourState(definition: def, progress: skipped), const SyncCounts()), isFalse);
    const midway = TourProgress(status: TourStatus.inProgress, lastStepId: 'offline');
    expect(TourState(definition: def, progress: midway).resumeIndex, 2);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  Future<void> pump(WidgetTester tester, {bool restart = false}) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [tourRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TourScreen(restart: restart))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  Future<TourProgress?> stored() async => repo.progress('2026.10.1');

  testWidgets('K1 → K2 → K3: progress, sync states, completion recorded', (tester) async {
    await pump(tester);
    expect(find.text('Welcome to Medical Shop'), findsOneWidget);
    expect(find.text('Step 1 of 6'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Next'));
      await settle(tester);
    }
    // K2
    expect(find.text('Step 5 of 6'), findsOneWidget);
    expect(find.text('Sync status'), findsOneWidget);
    for (final s in ['Pending', 'Syncing', 'Synced', 'Conflict', 'Failed']) {
      expect(find.text(s), findsOneWidget);
    }
    expect(find.text('Needs your review'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await settle(tester);
    expect(find.text('Step 4 of 6'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await settle(tester);
    await tester.tap(find.text('Next'));
    await settle(tester);

    // K3
    expect(find.text('You’re all set'), findsOneWidget);
    expect(find.text('Step 6 of 6 · Tour complete'), findsOneWidget);
    expect((await tester.runAsync(stored))!.status, TourStatus.completed);
    expect(api.saved.last, 'finish:COMPLETED');

    await tester.tap(find.text('Finish'));
    await settle(tester);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('Skip on step 1 records SKIPPED and closes', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Skip'));
    await settle(tester);
    expect(find.text('open'), findsOneWidget);
    expect((await tester.runAsync(stored))!.status, TourStatus.skipped);
    expect(api.saved.last, 'welcome:SKIPPED');
  });

  testWidgets('resumes where the user left off; restart from Help starts at step 1', (tester) async {
    await tester.runAsync(() => repo.record('2026.10.1', 'offline', TourStatus.inProgress));
    await pump(tester);
    expect(find.text('Step 3 of 6'), findsOneWidget);
    expect(find.text('Working offline'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    await tester.runAsync(() => repo.record('2026.10.1', 'finish', TourStatus.completed));
    await pump(tester, restart: true);
    expect(find.text('Step 1 of 6'), findsOneWidget);
    expect((await tester.runAsync(stored))!.status, TourStatus.completed, reason: 'restarting keeps completion');
  });

  test('offline progress is kept on the device and pushed later; server progress restored on a new device', () async {
    api.offline = true;
    final p = await repo.record('2026.10.1', 'dashboard', TourStatus.inProgress);
    expect(p.lastStepId, 'dashboard');
    expect(api.saved, isEmpty);

    api.offline = false;
    await repo.flushPending('2026.10.1');
    expect(api.saved, ['dashboard:IN_PROGRESS']);

    // New device: nothing local, server says completed → not shown again.
    final fresh = AppDatabase(NativeDatabase.memory());
    final repo2 = TourRepository(dao: fresh.outboxDao, bundle: DiskBundle(), api: api..remote = const TourProgress(status: TourStatus.completed, lastStepId: 'finish'));
    await repo2.syncWithServer('2026.10.1');
    expect((await repo2.progress('2026.10.1'))!.status, TourStatus.completed);
    await fresh.close();
  });
}

