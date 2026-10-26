import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/expiry.dart';
import 'status_chip.dart';

class BatchCard extends StatelessWidget {
  const BatchCard({super.key, required this.batch, required this.onDispose});
  final ExpiryBatch batch;
  final VoidCallback onDispose;

  String get _expiryText {
    final d = batch.expiryDate;
    return d == null ? 'No expiry date' : 'Exp ${DateFormat('MM/yyyy').format(d)}';
  }

  String get _daysText {
    final n = batch.daysLeft;
    if (n == null) return 'Missing expiry – needs correction';
    if (n < 0) return 'Expired ${-n} ${-n == 1 ? 'day' : 'days'} ago';
    if (n == 0) return 'Expires today';
    return '$n ${n == 1 ? 'day' : 'days'} left';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qty = batch.packEquivalent == null
        ? batch.quantityLabel
        : '${batch.quantityLabel} (${batch.packEquivalent})';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: batch.status.color.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    batch.productName,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(batch.status),
              ],
            ),
            const SizedBox(height: 4),
            Text('Batch ${batch.batchNumber}   $_expiryText', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text(
              _daysText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: batch.status.color,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Remaining: $qty', style: theme.textTheme.bodyMedium)),
                if (batch.status.canDispose)
                  FilledButton.tonal(onPressed: onDispose, child: const Text('Dispose')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
