import 'low_stock_alert_model.dart';

class StockBalanceItem {
  final String storeId;
  final String productId;
  final String productName;
  final double totalQuantity;
  final double unexpiredQuantity;
  final String baseUnit;
  final int activeBatchCount;
  final DateTime? earliestExpiryDate;
  final bool hasExpiredBatches;
  final bool isLowStock;
  final double reorderThreshold;
  final double safetyStockLevel;
  final StockAlertSeverityEnum severity;

  StockBalanceItem({
    required this.storeId,
    required this.productId,
    required this.productName,
    required this.totalQuantity,
    this.unexpiredQuantity = 0.0,
    this.baseUnit = 'TABLET',
    required this.activeBatchCount,
    this.earliestExpiryDate,
    this.hasExpiredBatches = false,
    this.isLowStock = false,
    this.reorderThreshold = 50.0,
    this.safetyStockLevel = 20.0,
    this.severity = StockAlertSeverityEnum.adequate,
  });

  factory StockBalanceItem.fromJson(Map<String, dynamic> json) {
    DateTime? expDate;
    final rawExp = json['earliest_expiry_date'];
    if (rawExp is String) {
      expDate = DateTime.tryParse(rawExp);
    }

    final total = (json['total_quantity'] as num?)?.toDouble() ?? 0.0;
    final unexp = (json['unexpired_quantity'] as num?)?.toDouble() ?? total;
    final threshold = (json['reorder_threshold'] as num?)?.toDouble() ?? 50.0;
    final safety = (json['safety_stock_level'] as num?)?.toDouble() ?? 20.0;
    final sev = json['severity'] != null
        ? StockAlertSeverityEnum.fromCode(json['severity'].toString())
        : (unexp <= 0
            ? StockAlertSeverityEnum.outOfStock
            : (unexp <= safety
                ? StockAlertSeverityEnum.criticalLow
                : (unexp <= threshold
                    ? StockAlertSeverityEnum.reorderRecommended
                    : StockAlertSeverityEnum.adequate)));

    return StockBalanceItem(
      storeId: json['store_id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? json['product_id']?.toString() ?? '',
      totalQuantity: total,
      unexpiredQuantity: unexp,
      baseUnit: json['base_unit']?.toString() ?? 'TABLET',
      activeBatchCount: (json['active_batch_count'] as num?)?.toInt() ?? 0,
      earliestExpiryDate: expDate,
      hasExpiredBatches: json['has_expired_batches'] as bool? ?? false,
      isLowStock: json['is_low_stock'] as bool? ?? (unexp <= threshold),
      reorderThreshold: threshold,
      safetyStockLevel: safety,
      severity: sev,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'store_id': storeId,
      'product_id': productId,
      'product_name': productName,
      'total_quantity': totalQuantity,
      'unexpired_quantity': unexpiredQuantity,
      'base_unit': baseUnit,
      'active_batch_count': activeBatchCount,
      'earliest_expiry_date': earliestExpiryDate?.toIso8601String().split('T').first,
      'has_expired_batches': hasExpiredBatches,
      'is_low_stock': isLowStock,
      'reorder_threshold': reorderThreshold,
      'safety_stock_level': safetyStockLevel,
      'severity': severity.code,
    };
  }
}

