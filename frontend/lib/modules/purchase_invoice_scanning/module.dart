import 'package:flutter/material.dart';
import '../../core/widgets/module_placeholder.dart';

class PurchaseInvoiceScanningScreen extends StatelessWidget {
  const PurchaseInvoiceScanningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderScreen(
      moduleNumber: 4,
      title: 'Purchase Invoice Scanning & Inward',
      scope: 'Invoice capture, OCR extraction, line review, confirmation and inward integration.',
      member: '4',
      integrationWithInventory: 'Confirmed invoices generate PURCHASE_IN inward ledger transactions and register new batches into Module 5.',
    );
  }
}
