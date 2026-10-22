import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/enums.dart';
import '../models/fefo_allocation_model.dart';
import '../models/unit_conversion_model.dart';
import '../services/inventory_service.dart';

class PostMovementDialog extends StatefulWidget {
  final InventoryService service;
  final String? initialProductId;
  final String? initialBatchId;

  const PostMovementDialog({
    super.key,
    required this.service,
    this.initialProductId,
    this.initialBatchId,
  });

  @override
  State<PostMovementDialog> createState() => _PostMovementDialogState();
}

class _PostMovementDialogState extends State<PostMovementDialog> {
  late String _selectedProductId;
  String? _selectedBatchId;
  MovementType _selectedMovementType = MovementType.salesReportOut;
  SourceDocumentType _selectedSourceDoc = SourceDocumentType.salesReport;

  final TextEditingController _quantityController = TextEditingController(text: '10');
  final TextEditingController _customFactorController = TextEditingController();
  final TextEditingController _docNumberController = TextEditingController(text: 'EOD-SALES-');
  final TextEditingController _notesController = TextEditingController(text: 'Counter sales dispense');
  late TextEditingController _idempotencyKeyController;

  String _selectedUnit = 'TABLET';
  bool _isSimulatingFefo = false;
  FefoAllocationPreview? _fefoPreview;
  String? _errorMessage;

  final List<String> _availablePackagingUnits = [
    'TABLET',
    'STRIP',
    'BOX',
    'CAPSULE',
    'BOTTLE',
    'ML',
  ];

  @override
  void initState() {
    super.initState();
    _selectedProductId = widget.initialProductId ?? widget.service.catalogueProducts.first['id'] as String;
    _selectedBatchId = widget.initialBatchId;
    _idempotencyKeyController = TextEditingController(text: _generateIdempotencyKey());
    _syncUnitWithSelectedProduct();
  }

  void _syncUnitWithSelectedProduct() {
    final prod = widget.service.catalogueProducts.firstWhere(
      (p) => p['id'] == _selectedProductId,
      orElse: () => {'unit': 'TABLET'},
    );
    _selectedUnit = (prod['unit'] as String? ?? 'TABLET').toUpperCase();
    _fefoPreview = null;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _customFactorController.dispose();
    _docNumberController.dispose();
    _notesController.dispose();
    _idempotencyKeyController.dispose();
    super.dispose();
  }

  String _generateIdempotencyKey() {
    return 'IDEM-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';
  }

  void _regenerateIdemKey() {
    setState(() {
      _idempotencyKeyController.text = _generateIdempotencyKey();
    });
  }

  String _getProductBaseUnit() {
    final prod = widget.service.catalogueProducts.firstWhere(
      (p) => p['id'] == _selectedProductId,
      orElse: () => {'unit': 'TABLET'},
    );
    return (prod['unit'] as String? ?? 'TABLET').toUpperCase();
  }

  UnitConversionResult _calculateConversion() {
    final qty = double.tryParse(_quantityController.text.trim()) ?? 0.0;
    final baseUnit = _getProductBaseUnit();
    final customFactor = double.tryParse(_customFactorController.text.trim());

    return widget.service.convertUnits(
      fromUnit: _selectedUnit,
      toUnit: baseUnit,
      quantity: qty,
      customFactor: customFactor,
      productId: _selectedProductId,
    );
  }

  Future<void> _simulateFefo() async {
    setState(() {
      _errorMessage = null;
      _isSimulatingFefo = true;
    });

    final qty = double.tryParse(_quantityController.text.trim());
    if (qty == null || qty <= 0) {
      setState(() {
        _isSimulatingFefo = false;
        _errorMessage = 'Enter a valid positive quantity to preview FEFO allocation';
      });
      return;
    }

    final customFactor = double.tryParse(_customFactorController.text.trim());

    try {
      final preview = await widget.service.previewFefoAllocationAsync(
        productId: _selectedProductId,
        quantity: qty,
        unit: _selectedUnit,
        customFactor: customFactor,
        includeExpired: false,
      );

      setState(() {
        _fefoPreview = preview;
        _isSimulatingFefo = false;
      });
    } catch (e) {
      setState(() {
        _isSimulatingFefo = false;
        _errorMessage = 'FEFO simulation failed: $e';
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _errorMessage = null;
    });

    final qty = double.tryParse(_quantityController.text.trim());
    if (qty == null || qty <= 0) {
      setState(() {
        _errorMessage = 'Quantity must be a positive number greater than zero';
      });
      return;
    }

    final docNum = _docNumberController.text.trim();
    if (docNum.isEmpty) {
      setState(() {
        _errorMessage = 'Source document number is required for audit traceability';
      });
      return;
    }

    final customFactor = double.tryParse(_customFactorController.text.trim());
    final isOutward = _selectedMovementType.isInward == false;

    // If outward sales movement with automatic FEFO allocation
    if (isOutward && _selectedBatchId == null && _selectedMovementType == MovementType.salesReportOut) {
      final err = await widget.service.fefoDispenseAsync(
        productId: _selectedProductId,
        quantity: qty,
        unit: _selectedUnit,
        customFactor: customFactor,
        sourceDocumentType: _selectedSourceDoc,
        documentNumber: docNum,
        idempotencyKey: _idempotencyKeyController.text.trim(),
        notes: _notesController.text.trim(),
      );

      if (err != null) {
        setState(() {
          _errorMessage = err;
        });
        return;
      }
    } else {
      // Direct lot or non-FEFO movement
      final conversion = _calculateConversion();
      final error = widget.service.postStockMovement(
        productId: _selectedProductId,
        batchId: _selectedBatchId,
        movementType: _selectedMovementType,
        quantity: conversion.convertedQuantity,
        sourceDocumentType: _selectedSourceDoc,
        documentNumber: docNum,
        notes: _notesController.text.trim(),
        idempotencyKey: _idempotencyKeyController.text.trim(),
      );

      if (error != null) {
        setState(() {
          _errorMessage = error;
        });
        return;
      }
    }

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Posted ${_selectedMovementType.label} to stock ledger successfully.',
          ),
          backgroundColor: AppTheme.primaryTeal,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final productBatches = widget.service.currentStoreBatches
        .where((b) => b.productId == _selectedProductId)
        .toList();

    final isInward = _selectedMovementType.isInward == true;
    final isOutward = _selectedMovementType.isInward == false;
    final baseUnit = _getProductBaseUnit();
    final conversion = _calculateConversion();
    final isConverted = _selectedUnit.toUpperCase() != baseUnit;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceCard,
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
                      'Post Stock Movement',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    Text(
                      'Multi-Unit Conversions & FEFO Auto-Allocation',
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

            // Movement Type Selector
            const Text(
              'Movement Type',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slateHeading),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppTheme.slateBorder),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<MovementType>(
                  value: _selectedMovementType,
                  isExpanded: true,
                  items: MovementType.values.map((m) {
                    return DropdownMenuItem<MovementType>(
                      value: m,
                      child: Text(
                        '${m.label} (${m.isInward == true ? "+" : (m.isInward == false ? "-" : "+/-")})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: m.isInward == true
                              ? AppTheme.emeraldGreen
                              : (m.isInward == false ? AppTheme.roseDanger : AppTheme.blueInfo),
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedMovementType = val;
                        _fefoPreview = null;
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Medicine Selector
            const Text(
              'Medicine',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slateHeading),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
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
                        '${p['name']} [Base: ${p['unit']}]',
                        style: const TextStyle(fontSize: 13, color: AppTheme.slateDark),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedProductId = val;
                        _selectedBatchId = null;
                        _syncUnitWithSelectedProduct();
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Batch Selector (or FEFO Inferred)
            const Text(
              'Target Batch Lot',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slateHeading),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppTheme.slateBorder),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedBatchId,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome, size: 14, color: AppTheme.amberWarning),
                          SizedBox(width: 6),
                          Text(
                            'Automatic / FEFO Allocation Engine',
                            style: TextStyle(fontSize: 13, color: AppTheme.amberWarning, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    ...productBatches.map((b) {
                      return DropdownMenuItem<String?>(
                        value: b.id,
                        child: Text(
                          'Lot ${b.batchNumber} (Stock: ${b.currentQuantity.toStringAsFixed(0)} ${b.baseUnit})',
                          style: const TextStyle(fontSize: 13, color: AppTheme.slateDark),
                        ),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedBatchId = val;
                      _fefoPreview = null;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Quantity & Packaging Unit Selector
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Quantity',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slateHeading),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _quantityController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() => _fefoPreview = null),
                        decoration: InputDecoration(
                          hintText: '10',
                          prefixIcon: Icon(
                            isInward ? Icons.add : (isOutward ? Icons.remove : Icons.swap_horiz),
                            color: isInward ? AppTheme.emeraldGreen : AppTheme.roseDanger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Packaging Unit',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slateHeading),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: AppTheme.slateBorder),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _availablePackagingUnits.contains(_selectedUnit) ? _selectedUnit : _availablePackagingUnits.first,
                            isExpanded: true,
                            items: _availablePackagingUnits.map((u) {
                              return DropdownMenuItem<String>(
                                value: u,
                                child: Text(u, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedUnit = val;
                                  _fefoPreview = null;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Real-time Conversion Feedback Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isConverted ? AppTheme.amberLight : AppTheme.emeraldLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isConverted ? AppTheme.amberWarning.withOpacity(0.3) : AppTheme.emeraldGreen.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isConverted ? Icons.transform : Icons.check_circle_outline,
                    size: 14,
                    color: isConverted ? AppTheme.amberWarning : AppTheme.emeraldGreen,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isConverted
                          ? 'Converted: ${_quantityController.text} $_selectedUnit = ${conversion.convertedQuantity.toStringAsFixed(1)} $baseUnit (${conversion.notes})'
                          : 'Canonical Base Units: ${conversion.convertedQuantity.toStringAsFixed(1)} $baseUnit (1:1 direct ratio)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isConverted ? AppTheme.slateDark : AppTheme.emeraldGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // FEFO Preview Trigger Button (When Outward & Auto Allocation)
            if (isOutward && _selectedBatchId == null) ...[
              OutlinedButton.icon(
                onPressed: _isSimulatingFefo ? null : _simulateFefo,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.primaryTeal),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isSimulatingFefo
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.analytics_outlined, size: 16, color: AppTheme.primaryTeal),
                label: Text(
                  _isSimulatingFefo ? 'Simulating Allocation...' : 'Preview FEFO Allocation Plan',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryTeal),
                ),
              ),
              const SizedBox(height: 8),

              // Render FEFO Preview Card if available
              if (_fefoPreview != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: _fefoPreview!.isFullyFulfillable ? AppTheme.slateBorder : AppTheme.roseDanger,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'FEFO Allocation Plan (${_fefoPreview!.allocations.length} lots)',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.slateDark),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _fefoPreview!.isFullyFulfillable ? AppTheme.emeraldLight : AppTheme.roseLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _fefoPreview!.isFullyFulfillable ? 'Fully Fulfillable' : 'Shortage: ${_fefoPreview!.shortage} $baseUnit',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _fefoPreview!.isFullyFulfillable ? AppTheme.emeraldGreen : AppTheme.roseDanger,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Unexpired stock available: ${_fefoPreview!.totalAvailableUnexpired} $baseUnit | Required: ${_fefoPreview!.baseQuantityRequired} $baseUnit',
                        style: const TextStyle(fontSize: 11, color: AppTheme.slateMuted),
                      ),
                      const Divider(height: 16, color: AppTheme.slateBorder),
                      ..._fefoPreview!.allocations.map((a) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              const Icon(Icons.circle, size: 6, color: AppTheme.primaryTeal),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Lot ${a.batchNumber} (Exp: ${a.expiryDate.toIso8601String().split('T').first})',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.slateDark),
                                ),
                              ),
                              Text(
                                '-${a.allocatedQuantity.toStringAsFixed(0)} $baseUnit',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.roseDanger),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '(Rem: ${a.remainingBatchQuantity.toStringAsFixed(0)})',
                                style: const TextStyle(fontSize: 10, color: AppTheme.slateMuted),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],

            // Document Reference & Number
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Source Document',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slateHeading),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: AppTheme.slateBorder),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<SourceDocumentType>(
                            value: _selectedSourceDoc,
                            isExpanded: true,
                            items: SourceDocumentType.values.map((d) {
                              return DropdownMenuItem<SourceDocumentType>(
                                value: d,
                                child: Text(
                                  d.label,
                                  style: const TextStyle(fontSize: 12, color: AppTheme.slateDark),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedSourceDoc = val;
                                });
                              }
                            },
                          ),
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
                        'Document #',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slateHeading),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _docNumberController,
                        decoration: const InputDecoration(
                          hintText: 'EOD-SALES-01',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Reason / Audit Notes
            const Text(
              'Audit Reason / Notes',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slateHeading),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                hintText: 'e.g. Counter sales dispense / audit variance',
              ),
            ),
            const SizedBox(height: 12),

            // Idempotency Key Row
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Idempotency Key (Deduplication)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.slateHeading),
                    ),
                    InkWell(
                      onTap: _regenerateIdemKey,
                      child: const Row(
                        children: [
                          Icon(Icons.refresh, size: 12, color: AppTheme.primaryTeal),
                          SizedBox(width: 2),
                          Text('Refresh Key', style: TextStyle(fontSize: 11, color: AppTheme.primaryTeal)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _idempotencyKeyController,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    hintText: 'IDEM-...',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Post to Authoritative Stock Ledger'),
            ),
          ],
        ),
      ),
    );
  }
}
