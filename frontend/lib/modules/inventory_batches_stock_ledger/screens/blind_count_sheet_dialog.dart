import 'package:flutter/material.dart';
import '../models/audit_model.dart';
import '../services/inventory_service.dart';

class BlindCountSheetDialog extends StatefulWidget {
  final InventoryService service;
  final AuditSessionModel auditSession;

  const BlindCountSheetDialog({super.key, required this.service, required this.auditSession});

  @override
  State<BlindCountSheetDialog> createState() => _BlindCountSheetDialogState();
}

class _BlindCountSheetDialogState extends State<BlindCountSheetDialog> {
  final _batchController = TextEditingController();
  final _qtyController = TextEditingController();
  final _notesController = TextEditingController();

  String? _selectedProductId;
  DiscrepancyReasonEnum _selectedReason = DiscrepancyReasonEnum.normalDiscrepancy;

  final List<Map<String, dynamic>> _stagedItems = [];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final prods = widget.service.catalogueProducts;
    if (prods.isNotEmpty) {
      _selectedProductId = prods.first['id'] as String;
    }
  }

  @override
  void dispose() {
    _batchController.dispose();
    _qtyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _addStagedItem() {
    final batchNum = _batchController.text.trim().toUpperCase();
    final qtyText = _qtyController.text.trim();
    final qty = double.tryParse(qtyText);

    if (batchNum.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter batch number'), backgroundColor: Colors.red),
      );
      return;
    }
    if (qty == null || qty < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid count quantity (>= 0)'), backgroundColor: Colors.red),
      );
      return;
    }

    final prods = widget.service.catalogueProducts;
    final prod = prods.firstWhere(
      (p) => p['id'] == _selectedProductId,
      orElse: () => {'id': _selectedProductId, 'name': _selectedProductId},
    );

    setState(() {
      _stagedItems.add({
        'product_id': _selectedProductId,
        'product_name': prod['name'],
        'batch_number': batchNum,
        'counted_quantity': qty,
        'discrepancy_reason': _selectedReason.code,
        'notes': _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
      });

      _batchController.clear();
      _qtyController.clear();
      _notesController.clear();
      _selectedReason = DiscrepancyReasonEnum.normalDiscrepancy;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final invService = widget.service;
    final products = invService.catalogueProducts;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 780),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.qr_code_scanner, color: Colors.amber, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Blind Physical Count Sheet',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          widget.auditSession.title,
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Blind Count Information Alert
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.visibility_off, color: Colors.blue, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Blind Audit Active: Expected book quantities are hidden to eliminate counter bias and ensure compliance.',
                        style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 24),

              // Entry Form
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      value: _selectedProductId,
                      decoration: const InputDecoration(
                        labelText: 'Product *',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      ),
                      items: products.map((p) {
                        return DropdownMenuItem(
                          value: p['id'] as String,
                          child: Text(
                            p['name'] as String,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedProductId = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _batchController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Batch / Lot *',
                        hintText: 'e.g. DL-24A01',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _qtyController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Count Qty *',
                        hintText: 'Units',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<DiscrepancyReasonEnum>(
                      value: _selectedReason,
                      decoration: const InputDecoration(
                        labelText: 'Reason (if variance)',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                      items: DiscrepancyReasonEnum.values.map((r) {
                        return DropdownMenuItem(
                          value: r,
                          child: Text(r.label, style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedReason = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        hintText: 'Damaged packaging, etc.',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                    onPressed: _addStagedItem,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Staged items list
              Text(
                'Staged Physical Counts (${_stagedItems.length}):',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _stagedItems.isEmpty
                      ? Center(
                          child: Text(
                            'No items counted in this batch yet.\nEnter product, lot number, and quantity above.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _stagedItems.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, idx) {
                            final it = _stagedItems[idx];
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 14,
                                backgroundColor: Colors.indigo.shade50,
                                child: Text(
                                  '${idx + 1}',
                                  style: TextStyle(fontSize: 11, color: Colors.indigo.shade800),
                                ),
                              ),
                              title: Text(
                                '${it['product_name']} (${it['batch_number']})',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              subtitle: Text(
                                'Counted: ${it['counted_quantity']} units | Reason: ${it['discrepancy_reason']}',
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                onPressed: () {
                                  setState(() => _stagedItems.removeAt(idx));
                                },
                              ),
                            );
                          },
                        ),
                ),
              ),

              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    icon: _isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.cloud_upload, size: 18),
                    label: Text(_isSubmitting ? 'Submitting...' : 'Submit Physical Counts (${_stagedItems.length})'),
                    onPressed: (_isSubmitting || _stagedItems.isEmpty)
                        ? null
                        : () async {
                            setState(() => _isSubmitting = true);

                            final res = await invService.recordAuditCountsAsync(
                              widget.auditSession.id,
                              _stagedItems,
                            );

                            if (mounted) {
                              setState(() => _isSubmitting = false);
                              if (res != null) {
                                Navigator.of(context).pop(res);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Recorded ${_stagedItems.length} counts. Discrepancies: ${res.discrepancyCount}'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Failed to submit counts'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
