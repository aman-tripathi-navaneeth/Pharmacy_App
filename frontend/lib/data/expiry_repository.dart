import '../core/api_client.dart';
import '../core/app_config.dart';
import '../models/expiry.dart';

class ExpiryRepository {
  ExpiryRepository(this._api);
  final ApiClient _api;

  String get _base => '/stores/${AppConfig.storeId}/inventory/expiry';

  Future<ExpirySummary> summary() async =>
      ExpirySummary.fromJson(await _api.get('$_base/summary') as Map<String, dynamic>);

  Future<ExpiryPage> list({
    required List<ExpiryStatus> statuses,
    String query = '',
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _api.get(_base, query: {
      if (statuses.isNotEmpty) 'status': statuses.map((s) => s.api).toList(),
      if (query.trim().isNotEmpty) 'q': query.trim(),
      'page': '$page',
      'page_size': '$pageSize',
    });
    return ExpiryPage.fromJson(data as Map<String, dynamic>);
  }

  Future<Disposal> requestDisposal({
    required String batchId,
    required double quantity,
    required DisposalType type,
    String? note,
  }) async {
    final data = await _api.post('$_base/disposals', body: {
      'batch_id': batchId,
      'quantity_base': quantity,
      'disposal_type': type.api,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    return Disposal.fromJson(data as Map<String, dynamic>);
  }

  Future<Disposal> approveDisposal(String disposalId) async => Disposal.fromJson(
        await _api.post('$_base/disposals/$disposalId/approve') as Map<String, dynamic>,
      );
}
