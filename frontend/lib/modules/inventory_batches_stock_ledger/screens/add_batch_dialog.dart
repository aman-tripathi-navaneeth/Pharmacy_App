import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/inventory_service.dart';

class AddBatchDialog extends StatefulWidget {
  final InventoryService service;

  const AddBatchDialog({super.key, required this.service});

  @override
  State<AddBatchDialog> createState() => _AddBatchDialogState();
}

class _AddBatchDialogState extends State<AddBatchDialog> {
  late String _selectedProductId;
  final TextEditingController _batchNumberController = TextEditingController();
  final TextEditingController _initialQtyController = TextEditingController(text: '100');
  final TextEditingController _mrpController = TextEditingController(text: '45.00');
  final TextEditingController _purchaseRateController = TextEditingController(text: '32.00');
  final TextEditingController _invoiceNumController = TextEditingController(text: 'INV-2026-');

  DateTime _selectedExpiryDate = DateTime.now().add(const Duration(days: 365));
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedProductId = widget.service.catalogueProducts.first['id'] as String;
  }

  @override
  void dispose() {
    _batchNumberController.dispose();
    _initialQtyController.dispose();
    _mrpController.dispose();
    _purchaseRateController.dispose();
    _invoiceNumController.dispose();
    super.dispose();
  }

  Future<void> _pickExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedExpiryDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryTeal,
              onPrimary: Colors.white,
              onSurface: AppTheme.slateDark,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedExpiryDate = picked;
      });
    }
  }

  void _submit() {
    setState(() {
      _errorMessage = null;
    });

    final batchNum = _batchNumberController.text.trim();
    if (batchNum.isEmpty) {
      setState(() {
        _errorMessage = 'Batch number cannot be empty';
      });
      return;
    }

    final qty = double.tryParse(_initialQtyController.text.trim());
    if (qty == null || qty < 0) {
      setState(() {
        _errorMessage = 'Initial quantity must be a non-negative number';
      });
      return;
    }

    final mrp = double.tryParse(_mrpController.text.trim()) ?? 0.0;
    final cost = double.tryParse(_purchaseRateController.text.trim()) ?? 0.0;

    final selectedProduct = widget.service.catalogueProducts.firstWhere(
      (p) => p['id'] == _selectedProductId,
    );
    final unit = selectedProduct['unit'] as String;

    final error = widget.service.registerNewBatch(
      productId: _selectedProductId,
      batchNumber: batchNum,
      expiryDate: _selectedExpiryDate,
      mrp: mrp,
      purchaseRate: cost,
      initialQuantity: qty,
      baseUnit: unit,
      invoiceNumber: _invoiceNumController.text.trim(),
    );

    if (error != null) {
      setState(() {
        _errorMessage = error;
      });
    } else {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Batch ${batchNum.toUpperCase()} registered & posted to ledger.'),
          backgroundColor: AppTheme.primaryTeal,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Register New Batch',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    Text(
                      'Inward Lot & Stock Ledger Ingestion',
                      style: TextStyle(fontSize: 11, color: AppTheme.slateMuted),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: AppTheme.slateMuted),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.roseLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.roseDanger, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: AppTheme.roseDanger,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Medicine Selector
            const Text(
              'Select Medicine',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slateHeading),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.slateBorder),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedProductId,
                  isExpanded: true,
                  items: widget.service.catalogueProducts.map((p) {
                    return DropdownMenuItem<String>(
                      value: p['id'] as String,
                      child: Text(
                        '${p['name']} (${p['unit']})',
                        style: const TextStyle(fontSize: 13, color: AppTheme.slateDark),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedProductId = val;
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Batch Number & Expiry Date Row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Batch / Lot Number',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slateHeading),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _batchNumberController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          hintText: 'e.g. DL-25X01',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Expiry Date',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slateHeading),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _pickExpiryDate,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.slateBorder),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 16, color: AppTheme.primaryTeal),
                              const SizedBox(width: 8),
                              Text(
                                '${_selectedExpiryDate.year}-${_selectedExpiryDate.month.toString().padLeft(2, '0')}-${_selectedExpiryDate.day.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.slateDark),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Quantities & Pricing
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Initial Qty (Base Unit)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slateHeading),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _initialQtyController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '100',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MRP (₹)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slateHeading),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _mrpController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          hintText: '35.00',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cost Rate (₹)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slateHeading),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _purchaseRateController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          hintText: '24.00',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Invoice Number reference
            const Text(
              'Supplier Invoice Number',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slateHeading),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _invoiceNumController,
              decoration: const InputDecoration(
                hintText: 'e.g. INV-2026-904',
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Register Batch & Post Inward to Ledger'),
            ),
          ],
        ),
      ),
    );
  }
}
