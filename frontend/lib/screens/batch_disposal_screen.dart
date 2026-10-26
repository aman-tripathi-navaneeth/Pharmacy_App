import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../data/expiry_repository.dart';
import '../models/expiry.dart';
import '../widgets/status_chip.dart';

class BatchDisposalScreen extends StatefulWidget {
  const BatchDisposalScreen({super.key, required this.batch});
  final ExpiryBatch batch;

  @override
  State<BatchDisposalScreen> createState() => _BatchDisposalScreenState();
}

class _BatchDisposalScreenState extends State<BatchDisposalScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _qty = TextEditingController(text: formatQty(widget.batch.quantityBase));
  final _note = TextEditingController();
  DisposalType _type = DisposalType.destroyed;
  bool _busy = false;
  String? _error;

  /// Set when a request was saved but posting failed, so a retry approves it
  /// instead of creating a duplicate request.
  Disposal? _savedRequest;

  ExpiryBatch get _b => widget.batch;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _validateQty(String? v) {
    final n = double.tryParse((v ?? '').trim());
    if (n == null || n <= 0) return 'Enter a quantity greater than 0';
    if (n > _b.quantityBase) return 'Only ${_b.quantityLabel} remaining';
    return null;
  }

  Future<void> _submit({required bool approve}) async {
    if (!_formKey.currentState!.validate()) return;
    if (approve && !await _confirmPost()) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = context.read<ExpiryRepository>();
    try {
      var disposal = _savedRequest ??
          await repo.requestDisposal(
            batchId: _b.batchId,
            quantity: double.parse(_qty.text.trim()),
            type: _type,
            note: _note.text,
          );
      _savedRequest = disposal;

      if (approve) disposal = await repo.approveDisposal(disposal.id);
      if (!mounted) return;
      await _showResult(disposal);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _savedRequest != null && approve
            ? 'The request was saved but not posted. ${e.message}'
            : e.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmPost() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Post this disposal?'),
        content: Text(
          'Stock for ${_b.productName} (batch ${_b.batchNumber}) will drop by '
          '${_qty.text.trim()} ${_b.baseUnit}. This is recorded in the stock ledger '
          'and cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve & post')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _showResult(Disposal d) {
    final posted = d.isPosted;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          posted ? Icons.check_circle : Icons.hourglass_top,
          color: posted ? Colors.green : Colors.orange,
          size: 40,
        ),
        title: Text(posted ? 'Disposal posted' : 'Sent for approval'),
        content: Text(
          posted
              ? 'Remaining stock for this batch: ${formatQty(d.newBalanceBase ?? 0)} ${_b.baseUnit}.\n'
                  'Ledger entry: ${d.transactionId}'
              : 'An owner or manager needs to approve it before stock changes.',
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expiry = _b.expiryDate == null ? '–' : DateFormat('dd MMM yyyy').format(_b.expiryDate!);
    final qtyNow = double.tryParse(_qty.text.trim());

    return Scaffold(
      appBar: AppBar(title: const Text('Dispose batch')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(_b.productName, style: theme.textTheme.titleMedium),
                          ),
                          StatusChip(_b.status),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _row('Batch', _b.batchNumber),
                      _row('Expiry', expiry),
                      _row('Remaining', _b.packEquivalent == null
                          ? _b.quantityLabel
                          : '${_b.quantityLabel} (${_b.packEquivalent})'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('What happened to this stock?', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<DisposalType>(
                segments: [
                  for (final t in DisposalType.values)
                    ButtonSegment(value: t, label: Text(t.label, textAlign: TextAlign.center)),
                ],
                selected: {_type},
                onSelectionChanged: _busy ? null : (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _qty,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: _validateQty,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Quantity to dispose',
                  suffixText: _b.baseUnit,
                  helperText: 'Defaults to everything remaining',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _note,
                enabled: !_busy,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'e.g. Returned to Sun Distributors',
                  border: OutlineInputBorder(),
                ),
              ),
              if (qtyNow != null && qtyNow > 0 && qtyNow <= _b.quantityBase)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Stock will drop by ${formatQty(qtyNow)} ${_b.baseUnit}, '
                    'leaving ${formatQty(_b.quantityBase - qtyNow)} ${_b.baseUnit}.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              if (_error != null)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                ),
              const SizedBox(height: 12),
              if (AppConfig.canApprove) ...[
                FilledButton(
                  onPressed: _busy ? null : () => _submit(approve: true),
                  child: _busy ? const _Spinner() : const Text('Approve & post'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy || _savedRequest != null ? null : () => _submit(approve: false),
                  child: const Text('Send for approval instead'),
                ),
              ] else
                FilledButton(
                  onPressed: _busy ? null : () => _submit(approve: false),
                  child: _busy ? const _Spinner() : const Text('Send for approval'),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 90, child: Text(label)),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}
