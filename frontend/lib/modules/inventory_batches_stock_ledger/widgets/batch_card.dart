import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/batch_model.dart';
import '../models/expiry_tier_model.dart';

class BatchCard extends StatelessWidget {
  final BatchItem batch;
  final int fefoRank;
  final VoidCallback onAdjustTap;
  final VoidCallback? onSegregateTap;
  final VoidCallback? onReturnSupplierTap;

  const BatchCard({
    super.key,
    required this.batch,
    required this.fefoRank,
    required this.onAdjustTap,
    this.onSegregateTap,
    this.onReturnSupplierTap,
  });

  @override
  Widget build(BuildContext context) {
    final days = batch.daysUntilExpiry;
    final tier = ExpiryTierEnum.fromDays(days);

    Color expiryBadgeBg;
    Color expiryBadgeFg;
    String expiryText;

    switch (tier) {
      case ExpiryTierEnum.expired:
        expiryBadgeBg = AppTheme.roseLight;
        expiryBadgeFg = AppTheme.roseDanger;
        expiryText = 'EXPIRED (${batch.expiryDate.year}-${batch.expiryDate.month.toString().padLeft(2, '0')}-${batch.expiryDate.day.toString().padLeft(2, '0')})';
        break;
      case ExpiryTierEnum.critical30:
        expiryBadgeBg = AppTheme.amberLight;
        expiryBadgeFg = AppTheme.roseDanger;
        expiryText = 'CRITICAL: $days days left';
        break;
      case ExpiryTierEnum.near60:
        expiryBadgeBg = AppTheme.amberLight;
        expiryBadgeFg = AppTheme.amberWarning;
        expiryText = 'NEAR: $days days left';
        break;
      case ExpiryTierEnum.attention90:
        expiryBadgeBg = AppTheme.blueLight;
        expiryBadgeFg = AppTheme.blueInfo;
        expiryText = 'ATTN: $days days left';
        break;
      case ExpiryTierEnum.safe:
        expiryBadgeBg = AppTheme.emeraldLight;
        expiryBadgeFg = AppTheme.emeraldGreen;
        expiryText = 'SAFE: $days days left';
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: batch.isExpired
              ? AppTheme.roseDanger.withOpacity(0.4)
              : (batch.isExpiringSoon ? AppTheme.amberWarning.withOpacity(0.4) : AppTheme.slateBorder),
          width: (batch.isExpired || batch.isExpiringSoon) ? 1.5 : 1.0,
        ),
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
          // Header Row: Medicine Name & Stock Qty
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // FEFO Priority tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 8, top: 2),
                decoration: BoxDecoration(
                  color: AppTheme.tealTint,
                  border: Border.all(color: AppTheme.primaryTeal.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '#$fefoRank FEFO',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryTealDark,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      batch.productName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Batch: ${batch.batchNumber}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryTealDark,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${batch.currentQuantity.toStringAsFixed(0)} ${batch.baseUnit}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: batch.isExpired
                          ? AppTheme.roseDanger
                          : (batch.currentQuantity <= 0 ? AppTheme.slateMuted : AppTheme.slateDark),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: expiryBadgeBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      expiryText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: expiryBadgeFg,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: AppTheme.slateBorder),
          const SizedBox(height: 10),

          // Pricing & action row
          Row(
            children: [
              Text(
                'MRP: ₹${batch.mrp.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slateHeading,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Cost: ₹${batch.purchaseRate.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.slateMuted,
                ),
              ),
              const Spacer(),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (batch.isExpired && batch.currentQuantity > 0 && onSegregateTap != null)
                    InkWell(
                      onTap: onSegregateTap,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.roseLight,
                          border: Border.all(color: AppTheme.roseDanger.withOpacity(0.5)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shield_outlined, size: 13, color: AppTheme.roseDanger),
                            SizedBox(width: 4),
                            Text(
                              'Quarantine',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.roseDanger,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (batch.currentQuantity > 0 && onReturnSupplierTap != null)
                    InkWell(
                      onTap: onReturnSupplierTap,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.amberLight,
                          border: Border.all(color: AppTheme.amberWarning.withOpacity(0.4)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.reply_outlined, size: 13, color: AppTheme.slateDark),
                            SizedBox(width: 4),
                            Text(
                              'Return',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.slateDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  InkWell(
                    onTap: onAdjustTap,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundLight,
                        border: Border.all(color: AppTheme.slateBorder),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune, size: 13, color: AppTheme.slateHeading),
                          SizedBox(width: 4),
                          Text(
                            'Movement',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.slateHeading,
                            ),
                          ),
                        ],
                      ),
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
}
