import 'package:flutter/services.dart';

import '../api_session.dart';

/// Central place for UI sound effects.
/// Respects the "Notification sounds" toggle in Settings.
class AppSounds {
  /// Short alert sound for snackbars, popups and new notifications.
  /// Silent no-op when sounds are disabled in Settings or the platform
  /// does not support SystemSound.
  static void playAlert() {
    if (!ApiSession.notificationSoundsEnabled) return;
    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {
      // Sound unsupported on this platform: never break the UI for audio.
    }
  }
}
