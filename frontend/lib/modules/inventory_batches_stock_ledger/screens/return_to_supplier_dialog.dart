import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/batch_model.dart';
import '../services/inventory_service.dart';

class ReturnToSupplierDialog extends StatefulWidget {
  final InventoryService service;
  final BatchItem batch;

  const ReturnToSupplierDialog({
    super.key,
    required this.service,
    required this.batch,
  });

  @override
  State<ReturnToSupplierDialog> createState() => _ReturnToSupplierDialogState();
}

class _ReturnToSupplierDialogState extends State<ReturnToSupplierDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _supplierIdController;
  late TextEditingController _quantityController;
  late TextEditingController _invoiceRefController;
  late TextEditingController _creditNoteController;
  late TextEditingController _actorIdController;
  late TextEditingController _notesController;
  late TextEditingController _idempotencyKeyController;

  String _selectedReason = 'Near Expiry (Vendor Return Window)';
  bool _isSubmitting = false;
  String? _errorMessage;

  final List<String> _returnReasons = [
    'Near Expiry (Vendor Return Window)',
    'Expired Stock Return',
    'Damaged / Defective Packaging',
    'Manufacturer Batch Recall',
    'Excess Overstock / Slow Moving',
    'Contractual Return Agreement',
  ];

  @override
  void initState() {
    super.initState();
    final defaultQty = widget.batch.currentQuantity > 0
        ? (widget.batch.currentQuantity > 10 ? 10.0 : widget.batch.currentQuantity)
        : 1.0;

    _supplierIdController = TextEditingController(text: 'SUP-DISTRIBUTOR-01');
    _quantityController = TextEditingController(text: defaultQty.toStringAsFixed(0));
    _invoiceRefController = TextEditingController(text: 'INV-ORIG-${widget.batch.batchNumber}');
    _creditNoteController = TextEditingController(text: 'CN-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}');
    _actorIdController = TextEditingController(text: 'PHARMACIST-RETURN');
    _notesController = TextEditingController(text: 'Returned as per vendor return agreement');
    _idempotencyKeyController = TextEditingController(text: _generateIdempotencyKey());
  }

  @override
  void dispose() {
    _supplierIdController.dispose();
    _quantityController.dispose();
    _invoiceRefController.dispose();
    _creditNoteController.dispose();
    _actorIdController.dispose();
    _notesController.dispose();
    _idempotencyKeyController.dispose();
    super.dispose();
  }

  String _generateIdempotencyKey() {
    return 'IDEM-RET-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';
  }

  void _regenerateIdemKey() {
    setState(() {
      _idempotencyKeyController.text = _generateIdempotencyKey();
    });
  }

  double get _returnQuantity => double.tryParse(_quantityController.text.trim()) ?? 0.0;
  double get _returnValue => _returnQuantity * widget.batch.purchaseRate;

  Future<void> _submitReturn() async {
    if (!_formKey.currentState!.validate()) return;

    final qty = _returnQuantity;
    if (qty <= 0) {
      setState(() => _errorMessage = 'Return quantity must be strictly greater than 0');
      return;
    }
    if (qty > widget.batch.currentQuantity) {
      setState(() => _errorMessage = 'Cannot return more than active stock (${widget.batch.currentQuantity.toStringAsFixed(0)})');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final err = await widget.service.returnToSupplierAsync(
        batchId: widget.batch.id,
        supplierId: _supplierIdController.text.trim(),
        quantity: qty,
        returnReason: _selectedReason,
        idempotencyKey: _idempotencyKeyController.text.trim(),
        supplierInvoiceRef: _invoiceRefController.text.trim(),
        creditNoteNumber: _creditNoteController.text.trim(),
        actorId: _actorIdController.text.trim(),
        notes: _notesController.text.trim(),
      );

      if (!mounted) return;

      if (err != null) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = err;
        });
      } else {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Successfully returned ${qty.toStringAsFixed(0)} ${widget.batch.baseUnit} of batch ${widget.batch.batchNumber} to supplier.',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.primaryTealDark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Failed to process return: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.backgroundLight,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.reply_outlined, color: AppTheme.primaryTealDark, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Return Stock to Supplier',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.slateDark,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: AppTheme.slateMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Batch Summary Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.slateBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            widget.batch.productName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.slateDark,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.tealTint,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppTheme.primaryTeal.withOpacity(0.3)),
                          ),
                          child: Text(
                            'Lot: ${widget.batch.batchNumber}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryTealDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Available Stock: ${widget.batch.currentQuantity.toStringAsFixed(0)} ${widget.batch.baseUnit}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.slateBody,
                          ),
                        ),
                        Text(
                          'Purchase Cost: ₹${widget.batch.purchaseRate.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Error banner if any
              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.roseLight,
                    border: Border.all(color: AppTheme.roseDanger.withOpacity(0.4)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 16, color: AppTheme.roseDanger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 11, color: AppTheme.roseDanger, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),

              // Supplier ID field
              const Text('Supplier / Distributor ID', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.slateDark)),
              const SizedBox(height: 4),
              TextFormField(
                controller: _supplierIdController,
                decoration: _inputDecoration('e.g. SUP-MICRO-01 or GSK Distributor'),
                validator: (val) => val == null || val.trim().isEmpty ? 'Supplier ID is required' : null,
              ),

              const SizedBox(height: 12),

              // Return Quantity & Value Card
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Return Quantity (${widget.batch.baseUnit})',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.slateDark),
                        ),
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: _quantityController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: _inputDecoration('Max: ${widget.batch.currentQuantity.toStringAsFixed(0)}'),
                          onChanged: (_) => setState(() {}),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'Required';
                            final parsed = double.tryParse(val.trim());
                            if (parsed == null || parsed <= 0) return 'Must be > 0';
                            if (parsed > widget.batch.currentQuantity) return 'Exceeds stock';
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Container(
                      margin: const EdgeInsets.only(top: 18),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.amberLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.amberWarning.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Return Value', style: TextStyle(fontSize: 10, color: AppTheme.slateMuted)),
                          const SizedBox(height: 2),
                          Text(
                            '₹${_returnValue.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.slateDark),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Return Reason Dropdown
              const Text('Return Reason', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.slateDark)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.slateBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedReason,
                    isExpanded: true,
                    style: const TextStyle(fontSize: 12, color: AppTheme.slateDark),
                    items: _returnReasons.map((r) {
                      return DropdownMenuItem<String>(
                        value: r,
                        child: Text(r),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedReason = val);
                    },
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Supplier Invoice Ref & Credit Note row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Supplier Invoice Ref', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.slateDark)),
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: _invoiceRefController,
                          decoration: _inputDecoration('e.g. INV-9921'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Credit Note No.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.slateDark)),
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: _creditNoteController,
                          decoration: _inputDecoration('e.g. CN-4401'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Idempotency Key with Regenerate
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Idempotency Key (Audit Safe)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.slateDark)),
                  InkWell(
                    onTap: _regenerateIdemKey,
                    child: const Text('Regenerate', style: TextStyle(fontSize: 10, color: AppTheme.primaryTeal, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: _idempotencyKeyController,
                readOnly: true,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.slateMuted),
                decoration: _inputDecoration('IDEM-...'),
              ),

              const SizedBox(height: 12),

              // Notes
              const Text('Audit Notes (Optional)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.slateDark)),
              const SizedBox(height: 4),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: _inputDecoration('Additional context for supplier return...'),
              ),

              const SizedBox(height: 18),

              // Submit & Cancel buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: AppTheme.slateBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Cancel', style: TextStyle(fontSize: 12, color: AppTheme.slateDark, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitReturn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryTealDark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Confirm Return', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 11, color: AppTheme.slateMuted),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      filled: true,
      fillColor: AppTheme.surfaceCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.slateBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.slateBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.primaryTeal, width: 1.5),
      ),
    );
  }
}
