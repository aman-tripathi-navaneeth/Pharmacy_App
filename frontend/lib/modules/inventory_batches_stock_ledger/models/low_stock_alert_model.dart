enum StockAlertSeverityEnum {
  outOfStock('OUT_OF_STOCK', 'Out of Stock', 0),
  criticalLow('CRITICAL_LOW', 'Critical Low', 1),
  reorderRecommended('REORDER_RECOMMENDED', 'Reorder Required', 2),
  adequate('ADEQUATE', 'Adequate Stock', 3);

  final String code;
  final String label;
  final int priority;

  const StockAlertSeverityEnum(this.code, this.label, this.priority);

  static StockAlertSeverityEnum fromCode(String? code) {
    if (code == null) return StockAlertSeverityEnum.adequate;
    return StockAlertSeverityEnum.values.firstWhere(
      (e) => e.code.toUpperCase() == code.toUpperCase(),
      orElse: () => StockAlertSeverityEnum.adequate,
    );
  }
}

class ProductThresholdConfigModel {
  final String storeId;
  final String productId;
  final String? productName;
  final double reorderPoint;
  final double safetyStockLevel;
  final double reorderQuantity;
  final int leadTimeDays;
  final double? maxStockLevel;
  final String? notes;
  final DateTime? updatedAt;

  const ProductThresholdConfigModel({
    required this.storeId,
    required this.productId,
    this.productName,
    required this.reorderPoint,
    required this.safetyStockLevel,
    required this.reorderQuantity,
    this.leadTimeDays = 2,
    this.maxStockLevel,
    this.notes,
    this.updatedAt,
  });

  factory ProductThresholdConfigModel.fromJson(Map<String, dynamic> json) {
    return ProductThresholdConfigModel(
      storeId: json['store_id'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      productName: json['product_name'] as String?,
      reorderPoint: (json['reorder_point'] as num?)?.toDouble() ?? 50.0,
      safetyStockLevel: (json['safety_stock_level'] as num?)?.toDouble() ?? 20.0,
      reorderQuantity: (json['reorder_quantity'] as num?)?.toDouble() ?? 100.0,
      leadTimeDays: (json['lead_time_days'] as num?)?.toInt() ?? 2,
      maxStockLevel: (json['max_stock_level'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'store_id': storeId,
      'product_id': productId,
      if (productName != null) 'product_name': productName,
      'reorder_point': reorderPoint,
      'safety_stock_level': safetyStockLevel,
      'reorder_quantity': reorderQuantity,
      'lead_time_days': leadTimeDays,
      if (maxStockLevel != null) 'max_stock_level': maxStockLevel,
      if (notes != null) 'notes': notes,
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }
}

class LowStockAlertItemModel {
  final String productId;
  final String productName;
  final String? category;
  final String baseUnit;
  final double currentUnexpiredStock;
  final double expiredStock;
  final double totalStock;
  final double safetyStockLevel;
  final double reorderPoint;
  final double reorderQuantity;
  final int leadTimeDays;
  final StockAlertSeverityEnum severity;
  final double suggestedReorderQuantity;
  final double estimatedUnitCost;
  final double estimatedReorderCost;
  final int activeBatchCount;
  final DateTime? earliestExpiryDate;

  const LowStockAlertItemModel({
    required this.productId,
    required this.productName,
    this.category,
    this.baseUnit = 'TABLET',
    required this.currentUnexpiredStock,
    this.expiredStock = 0.0,
    required this.totalStock,
    required this.safetyStockLevel,
    required this.reorderPoint,
    required this.reorderQuantity,
    this.leadTimeDays = 2,
    required this.severity,
    required this.suggestedReorderQuantity,
    this.estimatedUnitCost = 0.0,
    this.estimatedReorderCost = 0.0,
    this.activeBatchCount = 0,
    this.earliestExpiryDate,
  });

  factory LowStockAlertItemModel.fromJson(Map<String, dynamic> json) {
    DateTime? expDate;
    final expRaw = json['earliest_expiry_date'];
    if (expRaw is String) {
      expDate = DateTime.tryParse(expRaw);
    }

    return LowStockAlertItemModel(
      productId: json['product_id'] as String? ?? '',
      productName: json['product_name'] as String? ?? json['product_id'] as String? ?? '',
      category: json['category'] as String?,
      baseUnit: json['base_unit'] as String? ?? 'TABLET',
      currentUnexpiredStock: (json['current_unexpired_stock'] as num?)?.toDouble() ?? 0.0,
      expiredStock: (json['expired_stock'] as num?)?.toDouble() ?? 0.0,
      totalStock: (json['total_stock'] as num?)?.toDouble() ?? 0.0,
      safetyStockLevel: (json['safety_stock_level'] as num?)?.toDouble() ?? 20.0,
      reorderPoint: (json['reorder_point'] as num?)?.toDouble() ?? 50.0,
      reorderQuantity: (json['reorder_quantity'] as num?)?.toDouble() ?? 100.0,
      leadTimeDays: (json['lead_time_days'] as num?)?.toInt() ?? 2,
      severity: StockAlertSeverityEnum.fromCode(json['severity'] as String?),
      suggestedReorderQuantity: (json['suggested_reorder_quantity'] as num?)?.toDouble() ?? 0.0,
      estimatedUnitCost: (json['estimated_unit_cost'] as num?)?.toDouble() ?? 0.0,
      estimatedReorderCost: (json['estimated_reorder_cost'] as num?)?.toDouble() ?? 0.0,
      activeBatchCount: (json['active_batch_count'] as num?)?.toInt() ?? 0,
      earliestExpiryDate: expDate,
    );
  }
}

class LowStockAlertsResponseModel {
  final String storeId;
  final int totalMonitoredProducts;
  final int outOfStockCount;
  final int criticalLowCount;
  final int reorderRecommendedCount;
  final int adequateCount;
  final double totalEstimatedReorderCost;
  final List<LowStockAlertItemModel> alerts;

  const LowStockAlertsResponseModel({
    required this.storeId,
    required this.totalMonitoredProducts,
    required this.outOfStockCount,
    required this.criticalLowCount,
    required this.reorderRecommendedCount,
    required this.adequateCount,
    required this.totalEstimatedReorderCost,
    required this.alerts,
  });

  factory LowStockAlertsResponseModel.fromJson(Map<String, dynamic> json) {
    final rawAlerts = json['alerts'] as List<dynamic>? ?? [];
    return LowStockAlertsResponseModel(
      storeId: json['store_id'] as String? ?? '',
      totalMonitoredProducts: (json['total_monitored_products'] as num?)?.toInt() ?? 0,
      outOfStockCount: (json['out_of_stock_count'] as num?)?.toInt() ?? 0,
      criticalLowCount: (json['critical_low_count'] as num?)?.toInt() ?? 0,
      reorderRecommendedCount: (json['reorder_recommended_count'] as num?)?.toInt() ?? 0,
      adequateCount: (json['adequate_count'] as num?)?.toInt() ?? 0,
      totalEstimatedReorderCost: (json['total_estimated_reorder_cost'] as num?)?.toDouble() ?? 0.0,
      alerts: rawAlerts.map((a) => LowStockAlertItemModel.fromJson(a as Map<String, dynamic>)).toList(),
    );
  }
}
