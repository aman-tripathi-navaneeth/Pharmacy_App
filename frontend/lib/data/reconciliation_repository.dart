import '../core/api_client.dart';
import '../core/app_config.dart';
import '../models/reconciliation.dart';

class ReconciliationRepository {
  ReconciliationRepository(this._api);
  final ApiClient _api;

  String get _base => '/stores/${AppConfig.storeId}/inventory/reconciliations';

  Future<ReconPage> list({int page = 1, int pageSize = 20}) async => ReconPage.fromJson(
        await _api.get(_base, query: {'page': '$page', 'page_size': '$pageSize'})
            as Map<String, dynamic>,
      );

  Future<Reconciliation> start({String? note}) async => Reconciliation.fromJson(
        await _api.post(_base, body: {
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        }) as Map<String, dynamic>,
      );

  /// [view] is one of: all, uncounted, variance.
  Future<ReconDetail> detail(
    String id, {
    String view = 'all',
    String query = '',
    int page = 1,
    int pageSize = 50,
  }) async =>
      ReconDetail.fromJson(
        await _api.get('$_base/$id', query: {
          'view': view,
          if (query.trim().isNotEmpty) 'q': query.trim(),
          'page': '$page',
          'page_size': '$pageSize',
        }) as Map<String, dynamic>,
      );

  /// A null value clears that batch's count. Sent in chunks of 500 (server limit).
  Future<void> saveCounts(String id, Map<String, double?> counts) async {
    final entries = counts.entries.toList();
    for (var i = 0; i < entries.length; i += 500) {
      final chunk = entries.skip(i).take(500);
      await _api.put('$_base/$id/counts', body: {
        'counts': [
          for (final e in chunk) {'batch_id': e.key, 'counted_base': e.value},
        ],
      });
    }
  }

  Future<Reconciliation> submit(String id) async => Reconciliation.fromJson(
        await _api.post('$_base/$id/submit') as Map<String, dynamic>,
      );

  Future<Reconciliation> approve(String id) async => Reconciliation.fromJson(
        await _api.post('$_base/$id/approve') as Map<String, dynamic>,
      );

  Future<Reconciliation> cancel(String id) async => Reconciliation.fromJson(
        await _api.post('$_base/$id/cancel') as Map<String, dynamic>,
      );
}
