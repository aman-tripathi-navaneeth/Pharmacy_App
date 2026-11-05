import '../../data/remote/integrations_api.dart';
import '../../l10n/translations.dart';

/// Copy for screen 6 (Figma row F). Module names and guidance come from the
/// catalogs by module key; the server's English text is used only when the
/// catalog has no entry (e.g. a module added after this app version).
class HealthStrings {
  const HealthStrings._();

  static String get title => tr('health.title');
  static String get loadError => tr('health.loadError');
  static String get loadErrorOffline => tr('health.loadErrorOffline');
  static String get loadErrorBody => tr('health.loadErrorBody');
  static String lastCheckedAuto(String time, int minutes) => tr('health.lastCheckedAuto', {'time': time, 'minutes': minutes});
  static String lastChecked(String time) => tr('health.lastChecked', {'time': time});
  static String offlineStale(String time) => tr('health.offlineStale', {'time': time});
  static String errorStale(String time) => tr('health.errorStale', {'time': time});
  static String get otherModules => tr('health.otherModules');
  static String lastKnown(String time) => tr('health.lastKnown', {'time': time});
  static String get autoChecked => tr('health.autoChecked');
  static String get retryCheck => tr('health.retryCheck');
  static String get checking => tr('health.checking');
  static String stillProblem(String module, HealthStatus s) =>
      tr('health.stillProblem', {'module': module, 'status': status(s).toLowerCase()});
  static String operationalAgain(String module) => tr('health.operationalAgain', {'module': module});
  static String operationalChecked(String time) => tr('health.operationalChecked', {'time': time});
  static String get operationalOk => tr('health.operationalOk');
  static String get notConnected => tr('health.notConnected');
  static String get ok => tr('health.ok');
  static String get notSetUp => tr('health.notSetUp');
  static String get loading => tr('health.loading');

  static String status(HealthStatus s) => tr('health.status.${s.name}');

  static String moduleLabel(ModuleHealth m) => trOrNull('health.module.${m.key}') ?? m.label;

  static String? guidance(ModuleHealth m) {
    if (!m.hasProblem) return null;
    final which = m.status == HealthStatus.degraded ? 'degraded' : 'unavailable';
    return trOrNull('health.guidance.${m.key}.$which') ?? m.guidance ?? tr('health.guidance.default.$which');
  }
}
