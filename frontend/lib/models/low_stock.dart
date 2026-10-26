enum LowStockStatus {
  outOfStock('OUT_OF_STOCK', 'Out of stock'),
  low('LOW', 'Low');

  const LowStockStatus(this.api, this.label);
  final String api;
  final String label;

  static LowStockStatus parse(String v) =>
      LowStockStatus.values.firstWhere((s) => s.api == v, orElse: () => LowStockStatus.low);
}

class LowStockItem {
  const LowStockItem({
    required this.productId,
    required this.productName,
    required this.baseUnit,
    required this.onHandBase,
    required this.reorderLevelBase,
    required this.shortfallBase,
    required this.status,
    this.onHandPack,
    this.reorderLevelPack,
  });

  final String productId;
  final String productName;
  final String baseUnit;
  final double onHandBase;
  final double reorderLevelBase;
  final double shortfallBase;
  final LowStockStatus status;
  final String? onHandPack;
  final String? reorderLevelPack;

  factory LowStockItem.fromJson(Map<String, dynamic> j) => LowStockItem(
        productId: j['product_id'] as String,
        productName: j['product_name'] as String,
        baseUnit: j['base_unit'] as String,
        onHandBase: (j['on_hand_base'] as num).toDouble(),
        reorderLevelBase: (j['reorder_level_base'] as num).toDouble(),
        shortfallBase: (j['shortfall_base'] as num).toDouble(),
        status: LowStockStatus.parse(j['status'] as String),
        onHandPack: j['on_hand_pack'] as String?,
        reorderLevelPack: j['reorder_level_pack'] as String?,
      );
}

class LowStockPage {
  const LowStockPage({required this.items, required this.total});
  final List<LowStockItem> items;
  final int total;

  factory LowStockPage.fromJson(Map<String, dynamic> j) => LowStockPage(
        items: (j['items'] as List)
            .map((e) => LowStockItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: j['total'] as int,
      );
}

class LowStockSummary {
  const LowStockSummary({this.outOfStock = 0, this.low = 0});
  final int outOfStock, low;

  factory LowStockSummary.fromJson(Map<String, dynamic> j) =>
      LowStockSummary(outOfStock: j['out_of_stock'] as int, low: j['low'] as int);
}
