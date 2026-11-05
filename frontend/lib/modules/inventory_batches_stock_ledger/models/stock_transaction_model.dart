import 'enums.dart';

class StockTransactionItem {
  final String id;
  final String storeId;
  final String productId;
  final String productName;
  final String? batchId;
  final String? batchNumber;
  final MovementType movementType;
  final double quantity; // Signed: positive for inward, negative for outward
  final String baseUnit;
  final double? enteredQuantity;
  final String? enteredUnit;
  final double conversionFactor;
  final SourceDocumentType sourceDocumentType;
  final String sourceDocumentId;
  final String? documentNumber;
  final String idempotencyKey;
  final String? actorId;
  final String? notes;
  final bool isInferred;
  final DateTime createdAt;

  StockTransactionItem({
    required this.id,
    required this.storeId,
    required this.productId,
    required this.productName,
    this.batchId,
    this.batchNumber,
    required this.movementType,
    required this.quantity,
    this.baseUnit = 'TABLET',
    this.enteredQuantity,
    this.enteredUnit,
    this.conversionFactor = 1.0,
    required this.sourceDocumentType,
    required this.sourceDocumentId,
    this.documentNumber,
    required this.idempotencyKey,
    this.actorId,
    this.notes,
    this.isInferred = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isInward => quantity > 0;
  bool get isOutward => quantity < 0;

  factory StockTransactionItem.fromJson(Map<String, dynamic> json) {
    DateTime? crDate;
    final rawCr = json['created_at'];
    if (rawCr is String) {
      crDate = DateTime.tryParse(rawCr);
    }

    final srcDoc = json['source_document'] is Map<String, dynamic>
        ? json['source_document'] as Map<String, dynamic>
        : null;

    final docTypeStr = srcDoc?['document_type']?.toString() ??
        json['source_document_type']?.toString() ??
        'MANUAL_ADJUSTMENT';
    final docIdStr = srcDoc?['document_id']?.toString() ??
        json['source_document_id']?.toString() ??
        '';
    final docNumStr = srcDoc?['document_number']?.toString() ??
        json['document_number']?.toString();

    return StockTransactionItem(
      id: json['id']?.toString() ?? '',
      storeId: json['store_id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? json['product_id']?.toString() ?? '',
      batchId: json['batch_id']?.toString(),
      batchNumber: json['batch_number']?.toString(),
      movementType: MovementType.fromCode(json['movement_type']?.toString() ?? 'ADJUSTMENT_ADD'),
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      baseUnit: json['base_unit']?.toString() ?? 'TABLET',
      enteredQuantity: (json['entered_quantity'] as num?)?.toDouble(),
      enteredUnit: json['entered_unit']?.toString(),
      conversionFactor: (json['conversion_factor'] as num?)?.toDouble() ?? 1.0,
      sourceDocumentType: SourceDocumentType.fromCode(docTypeStr),
      sourceDocumentId: docIdStr,
      documentNumber: docNumStr,
      idempotencyKey: json['idempotency_key']?.toString() ?? '',
      actorId: json['actor_id']?.toString(),
      notes: json['notes']?.toString(),
      isInferred: json['is_inferred'] as bool? ?? false,
      createdAt: crDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'store_id': storeId,
      'product_id': productId,
      'product_name': productName,
      'batch_id': batchId,
      'batch_number': batchNumber,
      'movement_type': movementType.code,
      'quantity': quantity,
      'base_unit': baseUnit,
      'entered_quantity': enteredQuantity,
      'entered_unit': enteredUnit,
      'conversion_factor': conversionFactor,
      'source_document_type': sourceDocumentType.code,
      'source_document_id': sourceDocumentId,
      'document_number': documentNumber,
      'idempotency_key': idempotencyKey,
      'actor_id': actorId,
      'notes': notes,
      'is_inferred': isInferred,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
