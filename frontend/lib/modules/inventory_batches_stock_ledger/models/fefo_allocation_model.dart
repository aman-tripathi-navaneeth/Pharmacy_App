import 'stock_transaction_model.dart';

class FefoBatchAllocation {
  final String batchId;
  final String batchNumber;
  final DateTime expiryDate;
  final double allocatedQuantity;
  final double remainingBatchQuantity;
  final double? mrp;
  final double? purchaseRate;
  final bool isExpired;

  const FefoBatchAllocation({
    required this.batchId,
    required this.batchNumber,
    required this.expiryDate,
    required this.allocatedQuantity,
    required this.remainingBatchQuantity,
    this.mrp,
    this.purchaseRate,
    this.isExpired = false,
  });

  bool get isExpiringSoon {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    final days = exp.difference(today).inDays;
    return !isExpired && days <= 60;
  }

  int get daysUntilExpiry {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    return exp.difference(today).inDays;
  }

  factory FefoBatchAllocation.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    final expRaw = json['expiry_date'];
    if (expRaw is String) {
      parsedDate = DateTime.tryParse(expRaw) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return FefoBatchAllocation(
      batchId: json['batch_id'] as String? ?? '',
      batchNumber: json['batch_number'] as String? ?? 'UNKNOWN',
      expiryDate: parsedDate,
      allocatedQuantity: (json['allocated_quantity'] as num?)?.toDouble() ?? 0.0,
      remainingBatchQuantity: (json['remaining_batch_quantity'] as num?)?.toDouble() ?? 0.0,
      mrp: (json['mrp'] as num?)?.toDouble(),
      purchaseRate: (json['purchase_rate'] as num?)?.toDouble(),
      isExpired: json['is_expired'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'batch_id': batchId,
      'batch_number': batchNumber,
      'expiry_date': expiryDate.toIso8601String().split('T').first,
      'allocated_quantity': allocatedQuantity,
      'remaining_batch_quantity': remainingBatchQuantity,
      if (mrp != null) 'mrp': mrp,
      if (purchaseRate != null) 'purchase_rate': purchaseRate,
      'is_expired': isExpired,
    };
  }
}

class FefoAllocationPreview {
  final String storeId;
  final String productId;
  final double requestedQuantity;
  final String requestedUnit;
  final String baseUnit;
  final double conversionFactor;
  final double baseQuantityRequired;
  final double totalAvailableUnexpired;
  final List<FefoBatchAllocation> allocations;
  final bool isFullyFulfillable;
  final double shortage;

  const FefoAllocationPreview({
    required this.storeId,
    required this.productId,
    required this.requestedQuantity,
    required this.requestedUnit,
    required this.baseUnit,
    required this.conversionFactor,
    required this.baseQuantityRequired,
    required this.totalAvailableUnexpired,
    required this.allocations,
    required this.isFullyFulfillable,
    this.shortage = 0.0,
  });

  factory FefoAllocationPreview.fromJson(Map<String, dynamic> json) {
    final rawAllocs = json['allocations'] as List<dynamic>? ?? [];
    return FefoAllocationPreview(
      storeId: json['store_id'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      requestedQuantity: (json['requested_quantity'] as num?)?.toDouble() ?? 0.0,
      requestedUnit: (json['requested_unit'] as String? ?? 'TABLET').toUpperCase(),
      baseUnit: (json['base_unit'] as String? ?? 'TABLET').toUpperCase(),
      conversionFactor: (json['conversion_factor'] as num?)?.toDouble() ?? 1.0,
      baseQuantityRequired: (json['base_quantity_required'] as num?)?.toDouble() ?? 0.0,
      totalAvailableUnexpired: (json['total_available_unexpired'] as num?)?.toDouble() ?? 0.0,
      allocations: rawAllocs.map((a) => FefoBatchAllocation.fromJson(a as Map<String, dynamic>)).toList(),
      isFullyFulfillable: json['is_fully_fulfillable'] as bool? ?? false,
      shortage: (json['shortage'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'store_id': storeId,
      'product_id': productId,
      'requested_quantity': requestedQuantity,
      'requested_unit': requestedUnit,
      'base_unit': baseUnit,
      'conversion_factor': conversionFactor,
      'base_quantity_required': baseQuantityRequired,
      'total_available_unexpired': totalAvailableUnexpired,
      'allocations': allocations.map((a) => a.toJson()).toList(),
      'is_fully_fulfillable': isFullyFulfillable,
      'shortage': shortage,
    };
  }
}

class FefoDispenseResult {
  final String storeId;
  final String productId;
  final double totalDispensedBaseUnits;
  final String baseUnit;
  final double enteredQuantity;
  final String enteredUnit;
  final double conversionFactor;
  final List<StockTransactionItem> transactions;
  final List<FefoBatchAllocation> allocations;

  const FefoDispenseResult({
    required this.storeId,
    required this.productId,
    required this.totalDispensedBaseUnits,
    required this.baseUnit,
    required this.enteredQuantity,
    required this.enteredUnit,
    required this.conversionFactor,
    required this.transactions,
    required this.allocations,
  });

  factory FefoDispenseResult.fromJson(Map<String, dynamic> json) {
    final rawTxs = json['transactions'] as List<dynamic>? ?? [];
    final rawAllocs = json['allocations'] as List<dynamic>? ?? [];
    return FefoDispenseResult(
      storeId: json['store_id'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      totalDispensedBaseUnits: (json['total_dispensed_base_units'] as num?)?.toDouble() ?? 0.0,
      baseUnit: (json['base_unit'] as String? ?? 'TABLET').toUpperCase(),
      enteredQuantity: (json['entered_quantity'] as num?)?.toDouble() ?? 0.0,
      enteredUnit: (json['entered_unit'] as String? ?? 'TABLET').toUpperCase(),
      conversionFactor: (json['conversion_factor'] as num?)?.toDouble() ?? 1.0,
      transactions: rawTxs.map((t) => StockTransactionItem.fromJson(t as Map<String, dynamic>)).toList(),
      allocations: rawAllocs.map((a) => FefoBatchAllocation.fromJson(a as Map<String, dynamic>)).toList(),
    );
  }
}
