class BatchItem {
  final String id;
  final String storeId;
  final String productId;
  final String productName;
  final String batchNumber;
  final DateTime expiryDate;
  final double mrp;
  final double purchaseRate;
  double currentQuantity;
  final String baseUnit;
  final DateTime createdAt;

  BatchItem({
    required this.id,
    required this.storeId,
    required this.productId,
    required this.productName,
    required this.batchNumber,
    required this.expiryDate,
    required this.mrp,
    required this.purchaseRate,
    required this.currentQuantity,
    this.baseUnit = 'TABLET',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isExpired {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    return exp.isBefore(today);
  }

  int get daysUntilExpiry {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    return exp.difference(today).inDays;
  }

  bool get isExpiringSoon {
    final days = daysUntilExpiry;
    return !isExpired && days <= 60;
  }

  BatchItem copyWith({
    String? id,
    String? storeId,
    String? productId,
    String? productName,
    String? batchNumber,
    DateTime? expiryDate,
    double? mrp,
    double? purchaseRate,
    double? currentQuantity,
    String? baseUnit,
  }) {
    return BatchItem(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      batchNumber: batchNumber ?? this.batchNumber,
      expiryDate: expiryDate ?? this.expiryDate,
      mrp: mrp ?? this.mrp,
      purchaseRate: purchaseRate ?? this.purchaseRate,
      currentQuantity: currentQuantity ?? this.currentQuantity,
      baseUnit: baseUnit ?? this.baseUnit,
      createdAt: createdAt,
    );
  }

  factory BatchItem.fromJson(Map<String, dynamic> json) {
    DateTime expDate;
    final rawExp = json['expiry_date'];
    if (rawExp is String) {
      expDate = DateTime.tryParse(rawExp) ?? DateTime.now();
    } else {
      expDate = DateTime.now();
    }

    DateTime? crDate;
    final rawCr = json['created_at'];
    if (rawCr is String) {
      crDate = DateTime.tryParse(rawCr);
    }

    return BatchItem(
      id: json['id']?.toString() ?? '',
      storeId: json['store_id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? json['product_id']?.toString() ?? '',
      batchNumber: json['batch_number']?.toString() ?? '',
      expiryDate: expDate,
      mrp: (json['mrp'] as num?)?.toDouble() ?? 0.0,
      purchaseRate: (json['purchase_rate'] as num?)?.toDouble() ?? 0.0,
      currentQuantity: (json['current_quantity'] as num?)?.toDouble() ?? 0.0,
      baseUnit: json['base_unit']?.toString() ?? 'TABLET',
      createdAt: crDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'store_id': storeId,
      'product_id': productId,
      'product_name': productName,
      'batch_number': batchNumber,
      'expiry_date': expiryDate.toIso8601String().split('T').first,
      'mrp': mrp,
      'purchase_rate': purchaseRate,
      'current_quantity': currentQuantity,
      'base_unit': baseUnit,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
