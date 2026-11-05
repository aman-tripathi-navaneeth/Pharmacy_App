import 'package:flutter/material.dart';

enum AuditTypeEnum {
  fullAudit('FULL_AUDIT', 'Full Store Audit', Icons.storefront),
  cycleCount('CYCLE_COUNT', 'Targeted Cycle Count', Icons.sync),
  categoryCount('CATEGORY_COUNT', 'Category Count', Icons.category),
  highValueAudit('HIGH_VALUE_AUDIT', 'High Value Lot Audit', Icons.diamond);

  final String code;
  final String label;
  final IconData icon;

  const AuditTypeEnum(this.code, this.label, this.icon);

  static AuditTypeEnum fromCode(String? code) {
    if (code == null) return AuditTypeEnum.cycleCount;
    return AuditTypeEnum.values.firstWhere(
      (e) => e.code.toUpperCase() == code.toUpperCase(),
      orElse: () => AuditTypeEnum.cycleCount,
    );
  }
}

enum AuditStatusEnum {
  planned('PLANNED', 'Planned', Colors.blueGrey),
  inProgress('IN_PROGRESS', 'Counting In Progress', Colors.amber),
  underReview('UNDER_REVIEW', 'Under Review', Colors.orange),
  reconciled('RECONCILED', 'Reconciled', Colors.green),
  cancelled('CANCELLED', 'Cancelled', Colors.red);

  final String code;
  final String label;
  final Color color;

  const AuditStatusEnum(this.code, this.label, this.color);

  static AuditStatusEnum fromCode(String? code) {
    if (code == null) return AuditStatusEnum.inProgress;
    return AuditStatusEnum.values.firstWhere(
      (e) => e.code.toUpperCase() == code.toUpperCase(),
      orElse: () => AuditStatusEnum.inProgress,
    );
  }
}

enum DiscrepancyReasonEnum {
  normalDiscrepancy('NORMAL_DISCREPANCY', 'Normal Count Variance'),
  damage('DAMAGE', 'Damaged / Broken Stock'),
  expiredUnrecorded('EXPIRED_UNRECORDED', 'Expired Unrecorded Stock'),
  theftShrinkage('THEFT_SHRINKAGE', 'Shrinkage / Pilferage'),
  surplusFound('SURPLUS_FOUND', 'Surplus Stock Found'),
  packingMismatch('PACKING_MISMATCH', 'Packing Unit Mismatch'),
  other('OTHER', 'Other Variance Reason');

  final String code;
  final String label;

  const DiscrepancyReasonEnum(this.code, this.label);

  static DiscrepancyReasonEnum fromCode(String? code) {
    if (code == null) return DiscrepancyReasonEnum.normalDiscrepancy;
    return DiscrepancyReasonEnum.values.firstWhere(
      (e) => e.code.toUpperCase() == code.toUpperCase(),
      orElse: () => DiscrepancyReasonEnum.normalDiscrepancy,
    );
  }
}

class AuditCountItemModel {
  final String id;
  final String auditId;
  final String storeId;
  final String productId;
  final String? productName;
  final String? batchId;
  final String batchNumber;
  final DateTime? expiryDate;
  final double? systemQuantity;
  final double countedQuantity;
  final double? discrepancyQuantity;
  final double? unitCost;
  final double? discrepancyValue;
  final String? discrepancyReason;
  final bool recountRequired;
  final String? notes;
  final String? countedBy;
  final String status;
  final DateTime createdAt;

  const AuditCountItemModel({
    required this.id,
    required this.auditId,
    required this.storeId,
    required this.productId,
    this.productName,
    this.batchId,
    required this.batchNumber,
    this.expiryDate,
    this.systemQuantity,
    required this.countedQuantity,
    this.discrepancyQuantity,
    this.unitCost,
    this.discrepancyValue,
    this.discrepancyReason,
    this.recountRequired = false,
    this.notes,
    this.countedBy,
    this.status = 'COUNTED',
    required this.createdAt,
  });

  bool get isSurplus => (discrepancyQuantity ?? 0.0) > 0.0;
  bool get isShortage => (discrepancyQuantity ?? 0.0) < 0.0;
  bool get isClean => (discrepancyQuantity ?? 0.0) == 0.0;

  factory AuditCountItemModel.fromJson(Map<String, dynamic> json) {
    return AuditCountItemModel(
      id: json['id'] as String? ?? '',
      auditId: json['audit_id'] as String? ?? '',
      storeId: json['store_id'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      productName: json['product_name'] as String?,
      batchId: json['batch_id'] as String?,
      batchNumber: json['batch_number'] as String? ?? '',
      expiryDate: json['expiry_date'] != null ? DateTime.tryParse(json['expiry_date'].toString()) : null,
      systemQuantity: json['system_quantity'] != null ? (json['system_quantity'] as num).toDouble() : null,
      countedQuantity: (json['counted_quantity'] as num?)?.toDouble() ?? 0.0,
      discrepancyQuantity: json['discrepancy_quantity'] != null ? (json['discrepancy_quantity'] as num).toDouble() : null,
      unitCost: json['unit_cost'] != null ? (json['unit_cost'] as num).toDouble() : null,
      discrepancyValue: json['discrepancy_value'] != null ? (json['discrepancy_value'] as num).toDouble() : null,
      discrepancyReason: json['discrepancy_reason'] as String?,
      recountRequired: json['recount_required'] as bool? ?? false,
      notes: json['notes'] as String?,
      countedBy: json['counted_by'] as String?,
      status: json['status'] as String? ?? 'COUNTED',
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'].toString()) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      if (productName != null) 'product_name': productName,
      if (batchId != null) 'batch_id': batchId,
      'batch_number': batchNumber,
      'counted_quantity': countedQuantity,
      if (discrepancyReason != null) 'discrepancy_reason': discrepancyReason,
      if (notes != null) 'notes': notes,
      if (countedBy != null) 'counted_by': countedBy,
    };
  }
}

class AuditSessionModel {
  final String id;
  final String storeId;
  final String title;
  final AuditTypeEnum auditType;
  final AuditStatusEnum status;
  final List<String>? scopeProductIds;
  final int totalItemsExpected;
  final int totalItemsCounted;
  final int discrepancyCount;
  final int surplusCount;
  final int shortageCount;
  final double netVarianceValue;
  final String? notes;
  final String? assignedTo;
  final String? createdBy;
  final String? approvedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? reconciledAt;
  final List<AuditCountItemModel>? items;

  const AuditSessionModel({
    required this.id,
    required this.storeId,
    required this.title,
    required this.auditType,
    required this.status,
    this.scopeProductIds,
    this.totalItemsExpected = 0,
    this.totalItemsCounted = 0,
    this.discrepancyCount = 0,
    this.surplusCount = 0,
    this.shortageCount = 0,
    this.netVarianceValue = 0.0,
    this.notes,
    this.assignedTo,
    this.createdBy,
    this.approvedBy,
    required this.createdAt,
    required this.updatedAt,
    this.reconciledAt,
    this.items,
  });

  factory AuditSessionModel.fromJson(Map<String, dynamic> json) {
    return AuditSessionModel(
      id: json['id'] as String? ?? '',
      storeId: json['store_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Stock Audit',
      auditType: AuditTypeEnum.fromCode(json['audit_type'] as String?),
      status: AuditStatusEnum.fromCode(json['status'] as String?),
      scopeProductIds: (json['scope_product_ids'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      totalItemsExpected: (json['total_items_expected'] as num?)?.toInt() ?? 0,
      totalItemsCounted: (json['total_items_counted'] as num?)?.toInt() ?? 0,
      discrepancyCount: (json['discrepancy_count'] as num?)?.toInt() ?? 0,
      surplusCount: (json['surplus_count'] as num?)?.toInt() ?? 0,
      shortageCount: (json['shortage_count'] as num?)?.toInt() ?? 0,
      netVarianceValue: (json['net_variance_value'] as num?)?.toDouble() ?? 0.0,
      notes: json['notes'] as String?,
      assignedTo: json['assigned_to'] as String?,
      createdBy: json['created_by'] as String?,
      approvedBy: json['approved_by'] as String?,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'].toString()) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'].toString()) : DateTime.now(),
      reconciledAt: json['reconciled_at'] != null ? DateTime.tryParse(json['reconciled_at'].toString()) : null,
      items: json['items'] != null
          ? (json['items'] as List<dynamic>)
              .map((it) => AuditCountItemModel.fromJson(it as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
}

class AuditDiscrepancyReportModel {
  final String auditId;
  final String storeId;
  final String title;
  final AuditStatusEnum status;
  final int totalCounted;
  final int totalDiscrepant;
  final double totalSurplusValue;
  final double totalShortageValue;
  final double netVarianceValue;
  final int cleanItemsCount;
  final List<AuditCountItemModel> discrepantItems;

  const AuditDiscrepancyReportModel({
    required this.auditId,
    required this.storeId,
    required this.title,
    required this.status,
    required this.totalCounted,
    required this.totalDiscrepant,
    required this.totalSurplusValue,
    required this.totalShortageValue,
    required this.netVarianceValue,
    required this.cleanItemsCount,
    required this.discrepantItems,
  });

  factory AuditDiscrepancyReportModel.fromJson(Map<String, dynamic> json) {
    return AuditDiscrepancyReportModel(
      auditId: json['audit_id'] as String? ?? '',
      storeId: json['store_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      status: AuditStatusEnum.fromCode(json['status'] as String?),
      totalCounted: (json['total_counted'] as num?)?.toInt() ?? 0,
      totalDiscrepant: (json['total_discrepant'] as num?)?.toInt() ?? 0,
      totalSurplusValue: (json['total_surplus_value'] as num?)?.toDouble() ?? 0.0,
      totalShortageValue: (json['total_shortage_value'] as num?)?.toDouble() ?? 0.0,
      netVarianceValue: (json['net_variance_value'] as num?)?.toDouble() ?? 0.0,
      cleanItemsCount: (json['clean_items_count'] as num?)?.toInt() ?? 0,
      discrepantItems: (json['discrepant_items'] as List<dynamic>? ?? [])
          .map((it) => AuditCountItemModel.fromJson(it as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AuditReconcileResponseModel {
  final String auditId;
  final String status;
  final DateTime reconciledAt;
  final String approvedBy;
  final int reconciledItemsCount;
  final int ledgerTransactionsPosted;
  final double totalSurplusQty;
  final double totalShortageQty;
  final double netFinancialAdjustment;
  final List<String> transactionIds;

  const AuditReconcileResponseModel({
    required this.auditId,
    required this.status,
    required this.reconciledAt,
    required this.approvedBy,
    required this.reconciledItemsCount,
    required this.ledgerTransactionsPosted,
    required this.totalSurplusQty,
    required this.totalShortageQty,
    required this.netFinancialAdjustment,
    required this.transactionIds,
  });

  factory AuditReconcileResponseModel.fromJson(Map<String, dynamic> json) {
    return AuditReconcileResponseModel(
      auditId: json['audit_id'] as String? ?? '',
      status: json['status'] as String? ?? 'RECONCILED',
      reconciledAt: json['reconciled_at'] != null ? DateTime.parse(json['reconciled_at'].toString()) : DateTime.now(),
      approvedBy: json['approved_by'] as String? ?? '',
      reconciledItemsCount: (json['reconciled_items_count'] as num?)?.toInt() ?? 0,
      ledgerTransactionsPosted: (json['ledger_transactions_posted'] as num?)?.toInt() ?? 0,
      totalSurplusQty: (json['total_surplus_qty'] as num?)?.toDouble() ?? 0.0,
      totalShortageQty: (json['total_shortage_qty'] as num?)?.toDouble() ?? 0.0,
      netFinancialAdjustment: (json['net_financial_adjustment'] as num?)?.toDouble() ?? 0.0,
      transactionIds: (json['transaction_ids'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
    );
  }
}
