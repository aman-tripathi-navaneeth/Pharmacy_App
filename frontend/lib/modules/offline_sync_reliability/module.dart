import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'core/auth_session.dart';
import 'core/connectivity_monitor.dart';
import 'data/local/app_database.dart';
import 'data/remote/api_client.dart';
import 'data/remote/integrations_api.dart';
import 'data/remote/languages_api.dart';
import 'data/remote/sync_api.dart';
import 'data/remote/tickets_api.dart';
import 'data/remote/tour_api.dart';
import 'features/integrations/integration_health_controller.dart';
import 'features/sync/sync_manager.dart';
import 'features/sync/sync_providers.dart';
import 'features/tickets/tickets_providers.dart';
import 'features/tour/tour_controller.dart';
import 'features/tour/tour_repository.dart';
import 'l10n/language_controller.dart';
import 'l10n/language_repository.dart';
import 'l10n/translations.dart';
import 'main.dart';

const _defaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000/api',
);

class OfflineSyncReliabilityScreen extends StatefulWidget {
  const OfflineSyncReliabilityScreen({super.key});

  @override
  State<OfflineSyncReliabilityScreen> createState() =>
      _OfflineSyncReliabilityScreenState();
}

class _OfflineSyncReliabilityScreenState
    extends State<OfflineSyncReliabilityScreen> {
  Future<_M12Bootstrap>? _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _initM12();
  }

  Future<_M12Bootstrap> _initM12() async {
    final db = AppDatabase();
    final dao = db.outboxDao;
    var deviceId = await dao.readMeta(SyncMetaKeys.deviceId);
    if (deviceId == null) {
      deviceId = 'dev_${const Uuid().v4()}';
      await dao.writeMeta(SyncMetaKeys.deviceId, deviceId);
    }

    const session = DevAuthSession();
    final connectivity = PlusConnectivityMonitor();
    final client = ApiClient(baseUrl: _defaultApiBaseUrl, session: session);
    final api = HttpSyncApi(client);
    final manager = SyncManager(
      dao: dao,
      api: api,
      connectivity: connectivity,
      session: session,
      deviceId: deviceId,
    );
    await manager.start();

    final languages = LanguageRepository(
      dao: dao,
      api: HttpLanguagesApi(client),
    );
    final translations = await bootstrapLanguage(languages);

    return _M12Bootstrap(
      db: db,
      manager: manager,
      connectivity: connectivity,
      api: api,
      client: client,
      session: session,
      languages: languages,
      translations: translations,
      tourRepo: TourRepository(dao: dao, api: HttpTourApi(client)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_M12Bootstrap>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Offline Sync, Integration & Reliability'),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not initialize Offline Sync: ${snapshot.error}'),
              ),
            ),
          );
        }
        final b = snapshot.data;
        if (b == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return ProviderScope(
          retry: (_, _) => null,
          overrides: [
            appDatabaseProvider.overrideWithValue(b.db),
            syncManagerProvider.overrideWithValue(b.manager),
            connectivityProvider.overrideWithValue(b.connectivity),
            syncApiProvider.overrideWithValue(b.api),
            integrationsApiProvider.overrideWithValue(
              HttpIntegrationsApi(b.client),
            ),
            ticketsApiProvider.overrideWithValue(HttpTicketsApi(b.client)),
            authSessionProvider.overrideWithValue(b.session),
            languageRepositoryProvider.overrideWithValue(b.languages),
            initialTranslationsProvider.overrideWithValue(b.translations),
            tourRepositoryProvider.overrideWithValue(b.tourRepo),
          ],
          child: const MedicalStoreApp(),
        );
      },
    );
  }
}

class _M12Bootstrap {
  const _M12Bootstrap({
    required this.db,
    required this.manager,
    required this.connectivity,
    required this.api,
    required this.client,
    required this.session,
    required this.languages,
    required this.translations,
    required this.tourRepo,
  });

  final AppDatabase db;
  final SyncManager manager;
  final PlusConnectivityMonitor connectivity;
  final HttpSyncApi api;
  final ApiClient client;
  final AuthSession session;
  final LanguageRepository languages;
  final Translations translations;
  final TourRepository tourRepo;
}
