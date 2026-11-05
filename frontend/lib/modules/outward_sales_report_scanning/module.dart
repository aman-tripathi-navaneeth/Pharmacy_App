import 'package:flutter/material.dart';
import '../../core/widgets/module_placeholder.dart';

class OutwardSalesReportScanningScreen extends StatelessWidget {
  const OutwardSalesReportScanningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderScreen(
      moduleNumber: 7,
      title: 'Outward Sales Report Scanning',
      scope: 'End-of-day sales report capture, OCR recognition, review, and confirmed stock-out movements.',
      member: '7',
      integrationWithInventory: 'Confirmed sales line items invoke Module 5 movement service with SALES_REPORT_OUT negative quantities (FEFO inferred if batch unspecified).',
    );
  }
}
