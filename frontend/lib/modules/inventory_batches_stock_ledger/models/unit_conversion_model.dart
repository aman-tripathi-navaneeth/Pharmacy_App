class UnitConversionRequest {
  final String? productId;
  final String fromUnit;
  final String toUnit;
  final double quantity;
  final double? customFactor;

  const UnitConversionRequest({
    this.productId,
    required this.fromUnit,
    this.toUnit = 'TABLET',
    required this.quantity,
    this.customFactor,
  });

  Map<String, dynamic> toJson() {
    return {
      if (productId != null) 'product_id': productId,
      'from_unit': fromUnit.toUpperCase(),
      'to_unit': toUnit.toUpperCase(),
      'quantity': quantity,
      if (customFactor != null) 'custom_factor': customFactor,
    };
  }
}

class UnitConversionResult {
  final String fromUnit;
  final String toUnit;
  final double enteredQuantity;
  final double convertedQuantity;
  final double conversionFactor;
  final String? notes;

  const UnitConversionResult({
    required this.fromUnit,
    required this.toUnit,
    required this.enteredQuantity,
    required this.convertedQuantity,
    required this.conversionFactor,
    this.notes,
  });

  factory UnitConversionResult.fromJson(Map<String, dynamic> json) {
    return UnitConversionResult(
      fromUnit: (json['from_unit'] as String? ?? 'TABLET').toUpperCase(),
      toUnit: (json['to_unit'] as String? ?? 'TABLET').toUpperCase(),
      enteredQuantity: (json['entered_quantity'] as num?)?.toDouble() ?? 0.0,
      convertedQuantity: (json['converted_quantity'] as num?)?.toDouble() ?? 0.0,
      conversionFactor: (json['conversion_factor'] as num?)?.toDouble() ?? 1.0,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'from_unit': fromUnit,
      'to_unit': toUnit,
      'entered_quantity': enteredQuantity,
      'converted_quantity': convertedQuantity,
      'conversion_factor': conversionFactor,
      'notes': notes,
    };
  }
}
