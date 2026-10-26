enum ExpiryStatus {
  expired('EXPIRED', 'Expired'),
  critical('CRITICAL', 'Critical'),
  warning('WARNING', 'Warning'),
  ok('OK', 'OK'),
  noExpiry('NO_EXPIRY', 'No expiry');

  const ExpiryStatus(this.api, this.label);
  final String api;
  final String label;

  static ExpiryStatus parse(String v) =>
      ExpiryStatus.values.firstWhere((s) => s.api == v, orElse: () => ExpiryStatus.noExpiry);

  /// Only these can be disposed of from the app.
  bool get canDispose => this == expired || this == critical || this == warning;
}

enum DisposalType {
  destroyed('DESTROYED', 'Destroyed'),
  supplierReturn('SUPPLIER_RETURN', 'Returned to supplier');

  const DisposalType(this.api, this.label);
  final String api;
  final String label;
}

String formatQty(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

class ExpiryBatch {
  const ExpiryBatch({
    required this.batchId,
    required this.productId,
    required this.productName,
    required this.batchNumber,
    required this.expiryDate,
    required this.daysLeft,
    required this.status,
    required this.quantityBase,
    required this.baseUnit,
    this.packEquivalent,
  });

  final String batchId;
  final String productId;
  final String productName;
  final String batchNumber;
  final DateTime? expiryDate;
  final int? daysLeft;
  final ExpiryStatus status;
  final double quantityBase;
  final String baseUnit;
  final String? packEquivalent;

  String get quantityLabel => '${formatQty(quantityBase)} $baseUnit';

  factory ExpiryBatch.fromJson(Map<String, dynamic> j) => ExpiryBatch(
        batchId: j['batch_id'] as String,
        productId: j['product_id'] as String,
        productName: j['product_name'] as String,
        batchNumber: j['batch_number'] as String,
        expiryDate: j['expiry_date'] == null ? null : DateTime.parse(j['expiry_date'] as String),
        daysLeft: j['days_left'] as int?,
        status: ExpiryStatus.parse(j['status'] as String),
        quantityBase: (j['quantity_base'] as num).toDouble(),
        baseUnit: j['base_unit'] as String,
        packEquivalent: j['pack_equivalent'] as String?,
      );
}

class ExpiryPage {
  const ExpiryPage({required this.items, required this.total});
  final List<ExpiryBatch> items;
  final int total;

  factory ExpiryPage.fromJson(Map<String, dynamic> j) => ExpiryPage(
        items: (j['items'] as List)
            .map((e) => ExpiryBatch.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: j['total'] as int,
      );
}

class ExpirySummary {
  const ExpirySummary({
    this.expired = 0,
    this.critical = 0,
    this.warning = 0,
    this.ok = 0,
    this.noExpiry = 0,
  });
  final int expired, critical, warning, ok, noExpiry;

  factory ExpirySummary.fromJson(Map<String, dynamic> j) => ExpirySummary(
        expired: j['expired'] as int,
        critical: j['critical'] as int,
        warning: j['warning'] as int,
        ok: j['ok'] as int,
        noExpiry: j['no_expiry'] as int,
      );
}

class Disposal {
  const Disposal({
    required this.id,
    required this.status,
    required this.quantityBase,
    this.transactionId,
    this.newBalanceBase,
  });
  final String id;
  final String status;
  final double quantityBase;
  final String? transactionId;
  final double? newBalanceBase;

  /// Only true once the server has confirmed the ledger write.
  bool get isPosted => status == 'APPROVED' && transactionId != null;

  factory Disposal.fromJson(Map<String, dynamic> j) => Disposal(
        id: j['id'] as String,
        status: j['status'] as String,
        quantityBase: (j['quantity_base'] as num).toDouble(),
        transactionId: j['transaction_id'] as String?,
        newBalanceBase: (j['new_balance_base'] as num?)?.toDouble(),
      );
}
