import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin/admin_api.dart';
import 'admin/admin_app.dart';
import 'admin/admin_providers.dart';
import 'core/auth_session.dart';
import 'data/remote/api_client.dart';
import 'l10n/translations.dart';

const _apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:3000');
const _adminToken = String.fromEnvironment('ADMIN_TOKEN');
const _adminName = String.fromEnvironment('ADMIN_NAME', defaultValue: 'Dev Support');

/// Support staff session. Replace with the Auth module's staff sign-in when available.
class AdminSession implements AuthSession {
  const AdminSession();

  @override
  Future<String?> accessToken() async => _adminToken.isEmpty ? null : _adminToken;

  /// Not used: the console works across all shops.
  @override
  String get storeId => '';
}

/// Entry point of the platform support console:
///   flutter build web -t lib/main_admin.dart -o build/admin_web --dart-define=ADMIN_TOKEN=…
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The console is staff-facing and English-only; shared labels come from the English catalog.
  final en = Catalog.fromJson(jsonDecode(await rootBundle.loadString('assets/l10n/en.json')) as Map<String, dynamic>);
  Translations.current = Translations(english: en);

  final client = ApiClient(baseUrl: _apiBaseUrl, session: const AdminSession());
  runApp(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      adminApiProvider.overrideWithValue(HttpAdminTicketsApi(client)),
      adminDisplayNameProvider.overrideWithValue(_adminName),
    ],
    child: const SupportConsoleApp(),
  ));
}
