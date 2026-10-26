enum ReconStatus {
  inProgress('IN_PROGRESS', 'In progress'),
  pendingApproval('PENDING_APPROVAL', 'Waiting for approval'),
  approved('APPROVED', 'Approved'),
  cancelled('CANCELLED', 'Cancelled');

  const ReconStatus(this.api, this.label);
  final String api;
  final String label;

  static ReconStatus parse(String v) =>
      ReconStatus.values.firstWhere((s) => s.api == v, orElse: () => ReconStatus.inProgress);

  bool get isOpen => this == inProgress || this == pendingApproval;
}

class Reconciliation {
  const Reconciliation({
    required this.id,
    required this.status,
    required this.scope,
    required this.createdBy,
    required this.createdAt,
    required this.linesTotal,
    required this.linesCounted,
    required this.linesWithVariance,
    this.note,
    this.approvedBy,
  });

  final String id;
  final ReconStatus status;
  final String scope;
  final String createdBy;
  final DateTime createdAt;
  final int linesTotal;
  final int linesCounted;
  final int linesWithVariance;
  final String? note;
  final String? approvedBy;

  factory Reconciliation.fromJson(Map<String, dynamic> j) => Reconciliation(
        id: j['id'] as String,
        status: ReconStatus.parse(j['status'] as String),
        scope: j['scope'] as String,
        createdBy: j['created_by'] as String,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        linesTotal: j['lines_total'] as int,
        linesCounted: j['lines_counted'] as int,
        linesWithVariance: j['lines_with_variance'] as int,
        note: j['note'] as String?,
        approvedBy: j['approved_by'] as String?,
      );
}

class ReconPage {
  const ReconPage({required this.items, required this.total});
  final List<Reconciliation> items;
  final int total;

  factory ReconPage.fromJson(Map<String, dynamic> j) => ReconPage(
        items: (j['items'] as List)
            .map((e) => Reconciliation.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: j['total'] as int,
      );
}

class ReconLine {
  const ReconLine({
    required this.batchId,
    required this.productName,
    required this.batchNumber,
    required this.expiryDate,
    required this.baseUnit,
    required this.systemBase,
    required this.countedBase,
    this.transactionId,
  });

  final String batchId;
  final String productName;
  final String batchNumber;
  final DateTime? expiryDate;
  final String baseUnit;
  final double systemBase;
  final double? countedBase;
  final String? transactionId;

  ReconLine withCount(double? value) => ReconLine(
        batchId: batchId,
        productName: productName,
        batchNumber: batchNumber,
        expiryDate: expiryDate,
        baseUnit: baseUnit,
        systemBase: systemBase,
        countedBase: value,
        transactionId: transactionId,
      );

  factory ReconLine.fromJson(Map<String, dynamic> j) => ReconLine(
        batchId: j['batch_id'] as String,
        productName: j['product_name'] as String,
        batchNumber: j['batch_number'] as String,
        expiryDate: j['expiry_date'] == null ? null : DateTime.parse(j['expiry_date'] as String),
        baseUnit: j['base_unit'] as String,
        systemBase: (j['system_base'] as num).toDouble(),
        countedBase: (j['counted_base'] as num?)?.toDouble(),
        transactionId: j['transaction_id'] as String?,
      );
}

class ReconDetail {
  const ReconDetail({required this.recon, required this.lines, required this.total});
  final Reconciliation recon;
  final List<ReconLine> lines;
  final int total;

  factory ReconDetail.fromJson(Map<String, dynamic> j) => ReconDetail(
        recon: Reconciliation.fromJson(j['recon'] as Map<String, dynamic>),
        lines: (j['lines'] as List)
            .map((e) => ReconLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: j['total'] as int,
      );
}
