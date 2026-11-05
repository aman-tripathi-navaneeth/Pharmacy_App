/// Override at run time, e.g.
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000/api/v1
///
/// DEV ONLY: user, role and store are passed as headers to match the backend's
/// dev auth. Replace with the app's real session/login data.
class AppConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1', // Android emulator -> host machine
  );
  static const storeId = String.fromEnvironment('STORE_ID', defaultValue: 'store_001');
  static const userId = String.fromEnvironment('USER_ID', defaultValue: 'user_owner');
  static const role = String.fromEnvironment('USER_ROLE', defaultValue: 'OWNER');

  static bool get canApprove => role == 'OWNER' || role == 'MANAGER';
}
