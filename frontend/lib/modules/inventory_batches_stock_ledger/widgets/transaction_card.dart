import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/stock_transaction_model.dart';
import 'movement_badge.dart';

class TransactionCard extends StatelessWidget {
  final StockTransactionItem tx;

  const TransactionCard({super.key, required this.tx});

  @override
  Widget build(BuildContext context) {
    final isPositive = tx.quantity > 0;
    final qtyString = '${isPositive ? "+" : ""}${tx.quantity.toStringAsFixed(0)} ${tx.baseUnit}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slateBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Movement Badge and Signed Quantity
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              MovementBadge(movementType: tx.movementType),
              Text(
                qtyString,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isPositive ? AppTheme.emeraldGreen : AppTheme.roseDanger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Medicine Name & Batch Number
          Text(
            tx.productName,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.slateDark,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (tx.batchNumber != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundLight,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.slateBorder),
                  ),
                  child: Text(
                    'Lot: ${tx.batchNumber}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slateHeading,
                    ),
                  ),
                ),
              if (tx.isInferred) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.amberLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'FEFO Inferred Allocation',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.amberWarning,
                    ),
                  ),
                ),
              ],
            ],
          ),

          if (tx.notes != null && tx.notes!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              tx.notes!,
              style: const TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: AppTheme.slateBody,
              ),
            ),
          ],

          const SizedBox(height: 8),
          const Divider(height: 1, color: AppTheme.slateBorder),
          const SizedBox(height: 8),

          // Audit Metadata: Source Document & Idempotency Key
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Doc: ${tx.sourceDocumentType.label} ${tx.documentNumber != null ? "#" + tx.documentNumber! : ""}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.slateHeading,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Idem: ${tx.idempotencyKey}',
                      style: const TextStyle(
                        fontSize: 9,
                        fontFamily: 'monospace',
                        color: AppTheme.slateMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatTime(tx.createdAt),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                  if (tx.actorId != null)
                    Text(
                      'by ${tx.actorId}',
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}
