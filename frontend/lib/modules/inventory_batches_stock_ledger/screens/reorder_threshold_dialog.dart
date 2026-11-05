import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/stock_balance_model.dart';
import '../services/inventory_service.dart';

class ReorderThresholdDialog extends StatefulWidget {
  final InventoryService service;
  final StockBalanceItem item;

  const ReorderThresholdDialog({
    super.key,
    required this.service,
    required this.item,
  });

  @override
  State<ReorderThresholdDialog> createState() => _ReorderThresholdDialogState();
}

class _ReorderThresholdDialogState extends State<ReorderThresholdDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _reorderPointController;
  late TextEditingController _safetyStockController;
  late TextEditingController _reorderQuantityController;
  late TextEditingController _leadTimeController;
  late TextEditingController _maxStockController;
  late TextEditingController _notesController;

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _reorderPointController = TextEditingController(text: widget.item.reorderThreshold.toStringAsFixed(0));
    _safetyStockController = TextEditingController(text: widget.item.safetyStockLevel.toStringAsFixed(0));
    _reorderQuantityController = TextEditingController(text: '100');
    _leadTimeController = TextEditingController(text: '2');
    _maxStockController = TextEditingController();
    _notesController = TextEditingController();

    _loadExistingThreshold();
  }

  Future<void> _loadExistingThreshold() async {
    try {
      final config = await widget.service.fetchProductThresholdAsync(widget.item.productId);
      if (mounted) {
        setState(() {
          _reorderPointController.text = config.reorderPoint.toStringAsFixed(0);
          _safetyStockController.text = config.safetyStockLevel.toStringAsFixed(0);
          _reorderQuantityController.text = config.reorderQuantity.toStringAsFixed(0);
          _leadTimeController.text = config.leadTimeDays.toString();
          if (config.maxStockLevel != null) {
            _maxStockController.text = config.maxStockLevel!.toStringAsFixed(0);
          }
          if (config.notes != null) {
            _notesController.text = config.notes!;
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _reorderPointController.dispose();
    _safetyStockController.dispose();
    _reorderQuantityController.dispose();
    _leadTimeController.dispose();
    _maxStockController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveThresholds() async {
    if (!_formKey.currentState!.validate()) return;

    final reorder = double.tryParse(_reorderPointController.text.trim()) ?? 0.0;
    final safety = double.tryParse(_safetyStockController.text.trim()) ?? 0.0;
    final reorderQty = double.tryParse(_reorderQuantityController.text.trim()) ?? 0.0;
    final leadDays = int.tryParse(_leadTimeController.text.trim()) ?? 2;
    final maxStock = double.tryParse(_maxStockController.text.trim());

    if (safety > reorder) {
      setState(() => _errorMessage = 'Safety stock level cannot exceed reorder point');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final err = await widget.service.updateProductThresholdsAsync(
      productId: widget.item.productId,
      reorderPoint: reorder,
      safetyStockLevel: safety,
      reorderQuantity: reorderQty,
      leadTimeDays: leadDays,
      maxStockLevel: maxStock,
      notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
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
          content: Text('Thresholds for ${widget.item.productName} updated successfully.'),
          backgroundColor: AppTheme.primaryTealDark,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
      child: _isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(40.0),
                child: CircularProgressIndicator(color: AppTheme.primaryTeal),
              ),
            )
          : Form(
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
                            Icon(Icons.tune, color: AppTheme.primaryTealDark, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Configure Reorder Thresholds',
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

                    // Product Summary Card
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
                          Text(
                            widget.item.productName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.slateDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Available Unexpired Stock: ${widget.item.unexpiredQuantity.toStringAsFixed(0)} ${widget.item.baseUnit}',
                                style: const TextStyle(fontSize: 11, color: AppTheme.slateBody, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'Total: ${widget.item.totalQuantity.toStringAsFixed(0)} ${widget.item.baseUnit}',
                                style: const TextStyle(fontSize: 11, color: AppTheme.slateMuted),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Error banner
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

                    // Row: Reorder Point & Safety Stock Level
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Reorder Point (${widget.item.baseUnit})',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.slateDark),
                              ),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: _reorderPointController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: _inputDecoration('e.g. 50'),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return 'Required';
                                  final num = double.tryParse(val.trim());
                                  if (num == null || num < 0) return 'Must be >= 0';
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Safety Stock Level (${widget.item.baseUnit})',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.slateDark),
                              ),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: _safetyStockController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: _inputDecoration('e.g. 20'),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return 'Required';
                                  final num = double.tryParse(val.trim());
                                  if (num == null || num < 0) return 'Must be >= 0';
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Row: Default Reorder Quantity & Supplier Lead Time
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Reorder Quantity (${widget.item.baseUnit})',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.slateDark),
                              ),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: _reorderQuantityController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: _inputDecoration('e.g. 100'),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return 'Required';
                                  final num = double.tryParse(val.trim());
                                  if (num == null || num <= 0) return 'Must be > 0';
                                  return null;
                                },
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
                                'Supplier Lead Time (Days)',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.slateDark),
                              ),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: _leadTimeController,
                                keyboardType: TextInputType.number,
                                decoration: _inputDecoration('e.g. 2'),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return 'Required';
                                  final num = int.tryParse(val.trim());
                                  if (num == null || num < 0) return 'Must be >= 0';
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Max Stock Level
                    const Text('Max Stock Level (Optional Ceiling)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.slateDark)),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _maxStockController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: _inputDecoration('e.g. 500 (leave blank for unlimited)'),
                    ),

                    const SizedBox(height: 12),

                    // Notes
                    const Text('Procurement Notes (Optional)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.slateDark)),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _notesController,
                      maxLines: 2,
                      decoration: _inputDecoration('e.g. High turnover seasonal demand...'),
                    ),

                    const SizedBox(height: 18),

                    // Action buttons
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
                            onPressed: _isSubmitting ? null : _saveThresholds,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryTealDark,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            child: _isSubmitting
                                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Save Thresholds', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
