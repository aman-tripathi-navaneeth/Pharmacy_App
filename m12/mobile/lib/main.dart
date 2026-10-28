import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/auth_session.dart';
import 'core/connectivity_monitor.dart';
import 'data/local/app_database.dart';
import 'data/remote/api_client.dart';
import 'data/remote/integrations_api.dart';
import 'data/remote/languages_api.dart';
import 'data/remote/tickets_api.dart';
import 'data/remote/tour_api.dart';
import 'data/remote/sync_api.dart';
import 'features/integrations/integration_health_controller.dart';
import 'features/sync/sync_manager.dart';
import 'features/tickets/tickets_providers.dart';
import 'features/tour/tour_controller.dart';
import 'features/tour/tour_repository.dart';
import 'l10n/language_controller.dart';
import 'l10n/language_repository.dart';
import 'features/sync/sync_providers.dart';

const _apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:3000');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase();
  final dao = db.outboxDao;
  var deviceId = await dao.readMeta(SyncMetaKeys.deviceId);
  if (deviceId == null) {
    deviceId = 'dev_${const Uuid().v4()}';
    await dao.writeMeta(SyncMetaKeys.deviceId, deviceId);
  }

  const session = DevAuthSession();
  final connectivity = PlusConnectivityMonitor();
  final client = ApiClient(baseUrl: _apiBaseUrl, session: session);
  final api = HttpSyncApi(client);
  final manager = SyncManager(
    dao: dao,
    api: api,
    connectivity: connectivity,
    session: session,
    deviceId: deviceId,
  );
  await manager.start();

  // Load the user's language before the first frame (spec §8.3).
  final languages = LanguageRepository(dao: dao, api: HttpLanguagesApi(client));
  final translations = await bootstrapLanguage(languages);

  runApp(ProviderScope(
    // Screens offer explicit Retry buttons and sync has its own backoff; Riverpod's
    // automatic retry would hide error states behind an endless loading skeleton.
    retry: (_, _) => null,
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      syncManagerProvider.overrideWithValue(manager),
      connectivityProvider.overrideWithValue(connectivity),
      syncApiProvider.overrideWithValue(api),
      integrationsApiProvider.overrideWithValue(HttpIntegrationsApi(client)),
      ticketsApiProvider.overrideWithValue(HttpTicketsApi(client)),
      authSessionProvider.overrideWithValue(session),
      languageRepositoryProvider.overrideWithValue(languages),
      initialTranslationsProvider.overrideWithValue(translations),
      tourRepositoryProvider.overrideWithValue(TourRepository(dao: dao, api: HttpTourApi(client))),
    ],
    child: const MedicalStoreApp(),
  ));
}

class MedicalStoreApp extends ConsumerStatefulWidget {
  const MedicalStoreApp({super.key});

  @override
  ConsumerState<MedicalStoreApp> createState() => _MedicalStoreAppState();
}

class _MedicalStoreAppState extends ConsumerState<MedicalStoreApp> {
  final _router = buildRouter();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Spec §12: sync on connectivity change (SyncManager) and on app resume (here).
    _lifecycle = AppLifecycleListener(onResume: () => ref.read(syncManagerProvider).syncNow());
    // Restore the profile language on a new device and pick up newer catalogs.
    ref.read(languageProvider.notifier).syncInBackground();
    ref.read(tourProvider.notifier).syncInBackground().ignore();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // All app strings come from tr(); when the language changes, rebuild every
    // screen in place (navigation and form state are kept).
    ref.listen(languageProvider, (prev, next) {
      if (prev?.code != next.code || !identical(prev, next)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) rebuildAllChildren(context);
        });
      }
    });
    final code = ref.watch(languageProvider).code;
    return MaterialApp.router(
      title: 'Medical Store',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: Locale(code),
      supportedLocales: [for (final c in bundledLanguages) Locale(c)],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: _router,
    );
  }
}
