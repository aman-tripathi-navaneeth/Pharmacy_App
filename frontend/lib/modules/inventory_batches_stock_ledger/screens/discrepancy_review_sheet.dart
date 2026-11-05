import 'package:flutter/material.dart';
import '../models/audit_model.dart';
import '../services/inventory_service.dart';

class DiscrepancyReviewSheet extends StatefulWidget {
  final InventoryService service;
  final AuditSessionModel auditSession;

  const DiscrepancyReviewSheet({super.key, required this.service, required this.auditSession});

  @override
  State<DiscrepancyReviewSheet> createState() => _DiscrepancyReviewSheetState();
}

class _DiscrepancyReviewSheetState extends State<DiscrepancyReviewSheet> {
  AuditDiscrepancyReportModel? _report;
  bool _isLoading = true;
  bool _isReconciling = false;

  final _approverController = TextEditingController(text: 'CHIEF-PHARMACIST-01');
  final _reconNotesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  @override
  void dispose() {
    _approverController.dispose();
    _reconNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    setState(() => _isLoading = true);
    final invService = widget.service;
    final rep = await invService.fetchAuditDiscrepanciesAsync(widget.auditSession.id);
    if (mounted) {
      setState(() {
        _report = rep;
        _isLoading = false;
      });
    }
  }

  Future<void> _showReconcileDialog() async {
    final invService = widget.service;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.gavel, color: Colors.green),
              SizedBox(width: 8),
              Text('Authorize Stock Reconciliation'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This will post permanent, immutable adjustment transactions to the stock ledger to align book inventory with physical count.',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _approverController,
                decoration: const InputDecoration(
                  labelText: 'Approving Pharmacist / Manager ID *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reconNotesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reconciliation Sign-Off Notes',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Monthly variance sign-off',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () {
                if (_approverController.text.trim().isEmpty) return;
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Confirm & Post to Ledger'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      setState(() => _isReconciling = true);
      final idem = 'RECON-${DateTime.now().millisecondsSinceEpoch}';
      final res = await invService.reconcileAuditSessionAsync(
        auditId: widget.auditSession.id,
        approvedBy: _approverController.text.trim(),
        idempotencyKey: idem,
        notes: _reconNotesController.text.trim().isNotEmpty ? _reconNotesController.text.trim() : null,
      );

      if (mounted) {
        setState(() => _isReconciling = false);
        if (res != null) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Audit successfully reconciled! Posted ${res.ledgerTransactionsPosted} adjustment transactions to ledger.',
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to reconcile audit session'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 820),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.analytics_outlined, color: Colors.deepPurple, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Variance & Discrepancy Review',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              Text(
                                '${widget.auditSession.title} | Status: ${widget.auditSession.status.label}',
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
                    const SizedBox(height: 16),

                    // KPI Summary Cards
                    Row(
                      children: [
                        _buildKpiCard('Total Lots', '${_report?.totalCounted ?? 0}', Colors.blueGrey),
                        const SizedBox(width: 8),
                        _buildKpiCard('Discrepant', '${_report?.totalDiscrepant ?? 0}', Colors.orange),
                        const SizedBox(width: 8),
                        _buildKpiCard('Clean Lots', '${_report?.cleanItemsCount ?? 0}', Colors.teal),
                        const SizedBox(width: 8),
                        _buildKpiCard(
                          'Net Financial Impact',
                          '₹${(_report?.netVarianceValue ?? 0.0).toStringAsFixed(2)}',
                          (_report?.netVarianceValue ?? 0.0) >= 0 ? Colors.green : Colors.red,
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    // Table Header
                    Text(
                      'Discrepancy Breakdown (${_report?.discrepantItems.length ?? 0} variances):',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),

                    // Items Table
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: (_report?.discrepantItems.isEmpty ?? true)
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Zero Discrepancies Found!',
                                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.green.shade800),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Physical stock exactly matches the system ledger for all counted lots.',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                itemCount: _report!.discrepantItems.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (ctx, idx) {
                                  final it = _report!.discrepantItems[idx];
                                  final isSurplus = (it.discrepancyQuantity ?? 0) > 0;
                                  final deltaColor = isSurplus ? Colors.green : Colors.red;

                                  return ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: deltaColor.withOpacity(0.12),
                                      child: Icon(
                                        isSurplus ? Icons.arrow_upward : Icons.arrow_downward,
                                        size: 14,
                                        color: deltaColor,
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            it.productName ?? it.productId,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Lot: ${it.batchNumber}',
                                            style: TextStyle(fontSize: 11, color: Colors.grey[800], fontFamily: 'monospace'),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Row(
                                      children: [
                                        Text('System: ${it.systemQuantity ?? 0}  |  Counted: ${it.countedQuantity}'),
                                        const SizedBox(width: 8),
                                        Text('(${it.discrepancyReason ?? 'NORMAL_DISCREPANCY'})', style: TextStyle(color: Colors.grey[600])),
                                      ],
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${isSurplus ? '+' : ''}${it.discrepancyQuantity} units',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: deltaColor,
                                          ),
                                        ),
                                        Text(
                                          '${isSurplus ? '+' : ''}₹${(it.discrepancyValue ?? 0.0).toStringAsFixed(2)}',
                                          style: TextStyle(fontSize: 11, color: deltaColor.shade700),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),

                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          widget.auditSession.status == AuditStatusEnum.reconciled
                              ? 'Status: RECONCILED (Ledger updated)'
                              : 'Ready for Manager Authorization',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Close'),
                            ),
                            const SizedBox(width: 12),
                            if (widget.auditSession.status != AuditStatusEnum.reconciled &&
                                widget.auditSession.status != AuditStatusEnum.cancelled)
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                ),
                                icon: _isReconciling
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : const Icon(Icons.check_circle, size: 18),
                                label: Text(_isReconciling ? 'Posting...' : 'Reconcile & Update Ledger'),
                                onPressed: _isReconciling ? null : _showReconcileDialog,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
