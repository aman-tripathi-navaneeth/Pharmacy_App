import '../../../api_session.dart';

/// Integration seam with the shared Authentication module (owned by another member).
///
/// Sync only needs a bearer token and the active shop. Replace [DevAuthSession]
/// with the real session provider when auth lands.
abstract interface class AuthSession {
  Future<String?> accessToken();

  /// The shop the user is currently working in; every queued op is scoped to it.
  String get storeId;
}

/// Reads values passed with `--dart-define` for local development, falling back
/// to the active [ApiSession] when running inside the unified Pharmacy app.
class DevAuthSession implements AuthSession {
  const DevAuthSession();

  static const _token = String.fromEnvironment('DEV_TOKEN');
  static const _storeId = String.fromEnvironment('STORE_ID', defaultValue: '00000000-0000-4000-9000-000000000001');

  @override
  Future<String?> accessToken() async {
    if (_token.isNotEmpty) return _token;
    return ApiSession.accessToken;
  }

  @override
  String get storeId {
    final activeStore = ApiSession.user['ownerStoreId']?.toString() ??
        ApiSession.user['storeId']?.toString() ??
        '';
    if (activeStore.isNotEmpty) return activeStore;
    return _storeId;
  }
}
