import 'api_client.dart';

enum HealthStatus { operational, degraded, unavailable, notConnected }

HealthStatus _status(String s) => switch (s) {
      'OPERATIONAL' => HealthStatus.operational,
      'DEGRADED' => HealthStatus.degraded,
      'UNAVAILABLE' => HealthStatus.unavailable,
      _ => HealthStatus.notConnected,
    };

String _wire(HealthStatus s) => switch (s) {
      HealthStatus.operational => 'OPERATIONAL',
      HealthStatus.degraded => 'DEGRADED',
      HealthStatus.unavailable => 'UNAVAILABLE',
      HealthStatus.notConnected => 'NOT_CONNECTED',
    };

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();

class ModuleHealth {
  const ModuleHealth({
    required this.key,
    required this.label,
    required this.status,
    this.message,
    this.guidance,
    this.lastCheckedAt,
    this.lastOkAt,
    this.consecutiveFailures = 0,
  });

  factory ModuleHealth.fromJson(Map<String, dynamic> j) => ModuleHealth(
        key: j['key'] as String,
        label: j['label'] as String,
        status: _status(j['status'] as String),
        message: j['message'] as String?,
        guidance: j['guidance'] as String?,
        lastCheckedAt: _date(j['lastCheckedAt']),
        lastOkAt: _date(j['lastOkAt']),
        consecutiveFailures: j['consecutiveFailures'] as int? ?? 0,
      );

  final String key;
  final String label;
  final HealthStatus status;
  final String? message;
  final String? guidance;
  final DateTime? lastCheckedAt;
  final DateTime? lastOkAt;
  final int consecutiveFailures;

  bool get hasProblem => status == HealthStatus.degraded || status == HealthStatus.unavailable;

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'status': _wire(status),
        'message': message,
        'guidance': guidance,
        'lastCheckedAt': lastCheckedAt?.toUtc().toIso8601String(),
        'lastOkAt': lastOkAt?.toUtc().toIso8601String(),
        'consecutiveFailures': consecutiveFailures,
      };
}

class HealthReport {
  const HealthReport({
    required this.overall,
    required this.checkedAt,
    required this.refreshAfter,
    required this.modules,
  });

  factory HealthReport.fromJson(Map<String, dynamic> j) => HealthReport(
        overall: _status(j['overall'] as String),
        checkedAt: _date(j['checkedAt']) ?? DateTime.now(),
        refreshAfter: Duration(seconds: j['refreshAfterSec'] as int? ?? 300),
        modules: [for (final m in j['modules'] as List) ModuleHealth.fromJson(m as Map<String, dynamic>)],
      );

  final HealthStatus overall;
  final DateTime checkedAt;
  final Duration refreshAfter;
  final List<ModuleHealth> modules;

  HealthReport replace(ModuleHealth module) => HealthReport(
        overall: overall,
        checkedAt: checkedAt,
        refreshAfter: refreshAfter,
        modules: [for (final m in modules) m.key == module.key ? module : m],
      );

  Map<String, dynamic> toJson() => {
        'overall': _wire(overall),
        'checkedAt': checkedAt.toUtc().toIso8601String(),
        'refreshAfterSec': refreshAfter.inSeconds,
        'modules': [for (final m in modules) m.toJson()],
      };
}

abstract interface class IntegrationsApi {
  Future<HealthReport> health({required String storeId});
  Future<ModuleHealth> recheck({required String storeId, required String key});
}

class HttpIntegrationsApi implements IntegrationsApi {
  HttpIntegrationsApi(this._client);

  final ApiClient _client;

  @override
  Future<HealthReport> health({required String storeId}) async =>
      HealthReport.fromJson(await _client.get('/integrations/health', queryParameters: {'storeId': storeId}));

  @override
  Future<ModuleHealth> recheck({required String storeId, required String key}) async {
    final body = await _client.post('/integrations/health/$key/check', data: {'storeId': storeId});
    return ModuleHealth.fromJson(body['module'] as Map<String, dynamic>);
  }
}
