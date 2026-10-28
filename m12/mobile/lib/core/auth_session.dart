/// Integration seam with the shared Authentication module (owned by another member).
///
/// Sync only needs a bearer token and the active shop. Replace [DevAuthSession]
/// with the real session provider when auth lands.
abstract interface class AuthSession {
  Future<String?> accessToken();

  /// The shop the user is currently working in; every queued op is scoped to it.
  String get storeId;
}

/// Reads values passed with `--dart-define` for local development.
class DevAuthSession implements AuthSession {
  const DevAuthSession();

  static const _token = String.fromEnvironment('DEV_TOKEN');
  static const _storeId = String.fromEnvironment('STORE_ID', defaultValue: '00000000-0000-4000-9000-000000000001');

  @override
  Future<String?> accessToken() async => _token.isEmpty ? null : _token;

  @override
  String get storeId => _storeId;
}
