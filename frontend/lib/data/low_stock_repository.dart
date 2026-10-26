import '../core/api_client.dart';
import '../core/app_config.dart';
import '../models/low_stock.dart';

class LowStockRepository {
  LowStockRepository(this._api);
  final ApiClient _api;

  String get _base => '/stores/${AppConfig.storeId}/inventory/low-stock';

  Future<LowStockSummary> summary() async =>
      LowStockSummary.fromJson(await _api.get('$_base/summary') as Map<String, dynamic>);

  Future<LowStockPage> list({
    required List<LowStockStatus> statuses,
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
    return LowStockPage.fromJson(data as Map<String, dynamic>);
  }

  /// level 0 stops tracking the product.
  Future<void> setReorderLevel(String productId, double level) =>
      _api.put('$_base/$productId/reorder-level', body: {'reorder_level_base': level});
}
