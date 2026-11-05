enum ExpiryTierEnum {
  expired('EXPIRED', 'Expired (Quarantine)', -1),
  critical30('CRITICAL_30', 'Critical Risk (<30 days)', 30),
  near60('NEAR_60', 'High Attention (31-60 days)', 60),
  attention90('ATTENTION_90', 'Medium Attention (61-90 days)', 90),
  safe('SAFE', 'Safe Stock (>90 days)', 9999);

  final String code;
  final String label;
  final int maxDays;

  const ExpiryTierEnum(this.code, this.label, this.maxDays);

  static ExpiryTierEnum fromCode(String? code) {
    if (code == null) return ExpiryTierEnum.safe;
    return ExpiryTierEnum.values.firstWhere(
      (e) => e.code.toUpperCase() == code.toUpperCase(),
      orElse: () => ExpiryTierEnum.safe,
    );
  }

  static ExpiryTierEnum fromDays(int days) {
    if (days < 0) return ExpiryTierEnum.expired;
    if (days <= 30) return ExpiryTierEnum.critical30;
    if (days <= 60) return ExpiryTierEnum.near60;
    if (days <= 90) return ExpiryTierEnum.attention90;
    return ExpiryTierEnum.safe;
  }
}

class ExpiryBucketItem {
  final ExpiryTierEnum tier;
  final String label;
  final int? daysMin;
  final int? daysMax;
  final int batchCount;
  final double totalUnits;
  final double totalPurchaseValue;
  final double totalMrpValue;

  const ExpiryBucketItem({
    required this.tier,
    required this.label,
    this.daysMin,
    this.daysMax,
    required this.batchCount,
    required this.totalUnits,
    required this.totalPurchaseValue,
    required this.totalMrpValue,
  });

  factory ExpiryBucketItem.fromJson(Map<String, dynamic> json) {
    return ExpiryBucketItem(
      tier: ExpiryTierEnum.fromCode(json['tier'] as String?),
      label: json['label'] as String? ?? '',
      daysMin: json['days_min'] as int?,
      daysMax: json['days_max'] as int?,
      batchCount: (json['batch_count'] as num?)?.toInt() ?? 0,
      totalUnits: (json['total_units'] as num?)?.toDouble() ?? 0.0,
      totalPurchaseValue: (json['total_purchase_value'] as num?)?.toDouble() ?? 0.0,
      totalMrpValue: (json['total_mrp_value'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tier': tier.code,
      'label': label,
      'days_min': daysMin,
      'days_max': daysMax,
      'batch_count': batchCount,
      'total_units': totalUnits,
      'total_purchase_value': totalPurchaseValue,
      'total_mrp_value': totalMrpValue,
    };
  }
}

class ExpiryBatchDetail {
  final String batchId;
  final String batchNumber;
  final String productId;
  final String productName;
  final DateTime expiryDate;
  final int daysUntilExpiry;
  final ExpiryTierEnum tier;
  final double currentQuantity;
  final String baseUnit;
  final double? mrp;
  final double? purchaseRate;
  final double atRiskPurchaseValue;
  final double atRiskMrpValue;

  const ExpiryBatchDetail({
    required this.batchId,
    required this.batchNumber,
    required this.productId,
    required this.productName,
    required this.expiryDate,
    required this.daysUntilExpiry,
    required this.tier,
    required this.currentQuantity,
    this.baseUnit = 'TABLET',
    this.mrp,
    this.purchaseRate,
    required this.atRiskPurchaseValue,
    required this.atRiskMrpValue,
  });

  factory ExpiryBatchDetail.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    final expRaw = json['expiry_date'];
    if (expRaw is String) {
      parsedDate = DateTime.tryParse(expRaw) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return ExpiryBatchDetail(
      batchId: json['batch_id'] as String? ?? '',
      batchNumber: json['batch_number'] as String? ?? 'UNKNOWN',
      productId: json['product_id'] as String? ?? '',
      productName: json['product_name'] as String? ?? json['product_id'] as String? ?? '',
      expiryDate: parsedDate,
      daysUntilExpiry: (json['days_until_expiry'] as num?)?.toInt() ?? 0,
      tier: ExpiryTierEnum.fromCode(json['tier'] as String?),
      currentQuantity: (json['current_quantity'] as num?)?.toDouble() ?? 0.0,
      baseUnit: json['base_unit'] as String? ?? 'TABLET',
      mrp: (json['mrp'] as num?)?.toDouble(),
      purchaseRate: (json['purchase_rate'] as num?)?.toDouble(),
      atRiskPurchaseValue: (json['at_risk_purchase_value'] as num?)?.toDouble() ?? 0.0,
      atRiskMrpValue: (json['at_risk_mrp_value'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'batch_id': batchId,
      'batch_number': batchNumber,
      'product_id': productId,
      'product_name': productName,
      'expiry_date': expiryDate.toIso8601String().split('T').first,
      'days_until_expiry': daysUntilExpiry,
      'tier': tier.code,
      'current_quantity': currentQuantity,
      'base_unit': baseUnit,
      if (mrp != null) 'mrp': mrp,
      if (purchaseRate != null) 'purchase_rate': purchaseRate,
      'at_risk_purchase_value': atRiskPurchaseValue,
      'at_risk_mrp_value': atRiskMrpValue,
    };
  }
}

class ExpiryBucketResponse {
  final String storeId;
  final int totalActiveBatches;
  final double totalAtRiskUnits;
  final double totalAtRiskPurchaseValue;
  final double totalAtRiskMrpValue;
  final List<ExpiryBucketItem> buckets;
  final List<ExpiryBatchDetail> batches;

  const ExpiryBucketResponse({
    required this.storeId,
    required this.totalActiveBatches,
    required this.totalAtRiskUnits,
    required this.totalAtRiskPurchaseValue,
    required this.totalAtRiskMrpValue,
    required this.buckets,
    required this.batches,
  });

  factory ExpiryBucketResponse.fromJson(Map<String, dynamic> json) {
    final rawBuckets = json['buckets'] as List<dynamic>? ?? [];
    final rawBatches = json['batches'] as List<dynamic>? ?? [];

    return ExpiryBucketResponse(
      storeId: json['store_id'] as String? ?? '',
      totalActiveBatches: (json['total_active_batches'] as num?)?.toInt() ?? 0,
      totalAtRiskUnits: (json['total_at_risk_units'] as num?)?.toDouble() ?? 0.0,
      totalAtRiskPurchaseValue: (json['total_at_risk_purchase_value'] as num?)?.toDouble() ?? 0.0,
      totalAtRiskMrpValue: (json['total_at_risk_mrp_value'] as num?)?.toDouble() ?? 0.0,
      buckets: rawBuckets.map((b) => ExpiryBucketItem.fromJson(b as Map<String, dynamic>)).toList(),
      batches: rawBatches.map((b) => ExpiryBatchDetail.fromJson(b as Map<String, dynamic>)).toList(),
    );
  }
}
