class ApiSession {
  static String? accessToken;
  static String? refreshToken;
  static Map<String, dynamic> user = {};
  static Map<String, dynamic> onboarding = {};
  static bool notificationsEnabled = true;
  static bool notificationSoundsEnabled = true;
  static String? userLanguage;
  static String? plan;

  static Map<String, String> get headers => {
    'Content-Type': 'application/json',
    if (accessToken != null) 'Authorization': 'Bearer $accessToken',
  };

  static void updateFromResponse(Map<String, dynamic> response) {
    accessToken = response['accessToken'] as String?;
    refreshToken = response['refreshToken'] as String?;
    user = response['user'] as Map<String, dynamic>? ?? {};
    onboarding = response['onboarding'] as Map<String, dynamic>? ?? {};
    userLanguage = user['language'] as String?;
    plan = user['plan'] as String?;
  }

  static void clear() {
    accessToken = null;
    refreshToken = null;
    user = {};
    onboarding = {};
    notificationsEnabled = true;
    notificationSoundsEnabled = true;
    userLanguage = null;
    plan = null;
  }
}
