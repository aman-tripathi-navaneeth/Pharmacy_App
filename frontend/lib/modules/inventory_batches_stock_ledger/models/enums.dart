enum MovementType {
  purchaseIn('PURCHASE_IN', 'Purchase Inward', true),
  salesReportOut('SALES_REPORT_OUT', 'Sales Report Out', false),
  returnIn('RETURN_IN', 'Customer Return In', true),
  returnOut('RETURN_OUT', 'Supplier Return Out', false),
  adjustmentAdd('ADJUSTMENT_ADD', 'Manual Adjustment (+)', true),
  adjustmentSubtract('ADJUSTMENT_SUBTRACT', 'Manual Deficit (-)', false),
  reversal('REVERSAL', 'Transaction Reversal', null);

  final String code;
  final String label;
  final bool? isInward;

  const MovementType(this.code, this.label, this.isInward);

  static MovementType fromCode(String code) {
    return MovementType.values.firstWhere(
      (e) => e.code == code.toUpperCase(),
      orElse: () => MovementType.adjustmentAdd,
    );
  }
}

enum SourceDocumentType {
  purchaseInvoice('PURCHASE_INVOICE', 'Purchase Invoice'),
  salesReport('SALES_REPORT', 'Sales Report'),
  stockAudit('STOCK_AUDIT', 'Stock Reconciliation Audit'),
  manualAdjustment('MANUAL_ADJUSTMENT', 'Manual Adjustment'),
  customerReturn('CUSTOMER_RETURN', 'Customer Return Slip'),
  supplierReturn('SUPPLIER_RETURN', 'Supplier Return Memo');

  final String code;
  final String label;

  const SourceDocumentType(this.code, this.label);

  static SourceDocumentType fromCode(String code) {
    return SourceDocumentType.values.firstWhere(
      (e) => e.code == code.toUpperCase(),
      orElse: () => SourceDocumentType.manualAdjustment,
    );
  }
}

enum UnitOfMeasure {
  tablet('TABLET', 'Tablet'),
  capsule('CAPSULE', 'Capsule'),
  strip('STRIP', 'Strip'),
  box('BOX', 'Box'),
  bottle('BOTTLE', 'Bottle'),
  vial('VIAL', 'Vial'),
  ampoule('AMPOULE', 'Ampoule'),
  tube('TUBE', 'Tube'),
  sachet('SACHET', 'Sachet'),
  piece('PIECE', 'Piece'),
  ml('ML', 'ml'),
  gm('GM', 'gm');

  final String code;
  final String label;

  const UnitOfMeasure(this.code, this.label);

  static UnitOfMeasure fromCode(String code) {
    return UnitOfMeasure.values.firstWhere(
      (e) => e.code == code.toUpperCase(),
      orElse: () => UnitOfMeasure.tablet,
    );
  }
}
