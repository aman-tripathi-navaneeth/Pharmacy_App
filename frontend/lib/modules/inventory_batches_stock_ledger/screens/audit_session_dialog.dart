import 'package:flutter/material.dart';
import '../models/audit_model.dart';
import '../services/inventory_service.dart';

class AuditSessionDialog extends StatefulWidget {
  final InventoryService service;

  const AuditSessionDialog({super.key, required this.service});

  @override
  State<AuditSessionDialog> createState() => _AuditSessionDialogState();
}

class _AuditSessionDialogState extends State<AuditSessionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  final _assignedController = TextEditingController();

  AuditTypeEnum _selectedType = AuditTypeEnum.cycleCount;
  final Set<String> _selectedProductIds = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _titleController.text = 'Cycle Count ${now.day}/${now.month}/${now.year}';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _assignedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final invService = widget.service;
    final products = invService.catalogueProducts;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.fact_check, color: Colors.indigo, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Initiate Physical Stock Audit',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            'Freeze stock snapshot and begin blind physical counts',
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
                const Divider(height: 24),

                Expanded(
                  child: ListView(
                    children: [
                      // Audit Title
                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'Audit Session Title *',
                          hintText: 'e.g. Q4 Antibiotics Cycle Count',
                          prefixIcon: Icon(Icons.edit_note),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Title is required';
                          if (v.trim().length < 3) return 'Title must be at least 3 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Audit Type Selector
                      DropdownButtonFormField<AuditTypeEnum>(
                        value: _selectedType,
                        decoration: const InputDecoration(
                          labelText: 'Audit Procedure Type *',
                          prefixIcon: Icon(Icons.tune),
                          border: OutlineInputBorder(),
                        ),
                        items: AuditTypeEnum.values.map((t) {
                          return DropdownMenuItem(
                            value: t,
                            child: Row(
                              children: [
                                Icon(t.icon, size: 18, color: Colors.indigo),
                                const SizedBox(width: 8),
                                Text(t.label),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedType = val);
                        },
                      ),
                      const SizedBox(height: 16),

                      // Scope Product Filter (If targeted)
                      if (_selectedType != AuditTypeEnum.fullAudit) ...[
                        Text(
                          'Select Products in Scope (${_selectedProductIds.length} selected):',
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 140,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.builder(
                            itemCount: products.length,
                            itemBuilder: (ctx, idx) {
                              final p = products[idx];
                              final pid = p['id'] as String;
                              final pname = p['name'] as String;
                              final isSelected = _selectedProductIds.contains(pid);

                              return CheckboxListTile(
                                dense: true,
                                title: Text(pname, style: const TextStyle(fontSize: 13)),
                                subtitle: Text('ID: $pid', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                value: isSelected,
                                onChanged: (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      _selectedProductIds.add(pid);
                                    } else {
                                      _selectedProductIds.remove(pid);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Auditor Assignment
                      TextFormField(
                        controller: _assignedController,
                        decoration: const InputDecoration(
                          labelText: 'Assigned Auditor / Pharmacist',
                          hintText: 'e.g. Pharmacist Rahul or AUDITOR-01',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Notes
                      TextFormField(
                        controller: _notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Instructions / Notes',
                          hintText: 'e.g. Count all top shelf lots first',
                          prefixIcon: Icon(Icons.notes),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
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
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      icon: _isSubmitting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.play_arrow, size: 18),
                      label: Text(_isSubmitting ? 'Starting...' : 'Start Audit Session'),
                      onPressed: _isSubmitting
                          ? null
                          : () async {
                              if (!_formKey.currentState!.validate()) return;
                              setState(() => _isSubmitting = true);

                              final res = await invService.createAuditSessionAsync(
                                title: _titleController.text.trim(),
                                auditType: _selectedType,
                                scopeProductIds: _selectedType == AuditTypeEnum.fullAudit
                                    ? null
                                    : _selectedProductIds.isNotEmpty
                                        ? _selectedProductIds.toList()
                                        : null,
                                notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
                                assignedTo: _assignedController.text.trim().isNotEmpty ? _assignedController.text.trim() : null,
                              );

                              if (mounted) {
                                setState(() => _isSubmitting = false);
                                if (res != null) {
                                  Navigator.of(context).pop(res);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Audit session "${res.title}" started successfully!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Failed to initiate audit session'),
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
      ),
    );
  }
}
