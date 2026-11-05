import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/low_stock_alert_model.dart';
import '../models/stock_balance_model.dart';

class StockBalanceCard extends StatelessWidget {
  final StockBalanceItem item;
  final VoidCallback onAdjustTap;
  final VoidCallback? onConfigureThresholdTap;

  const StockBalanceCard({
    super.key,
    required this.item,
    required this.onAdjustTap,
    this.onConfigureThresholdTap,
  });

  @override
  Widget build(BuildContext context) {
    Color severityBg;
    Color severityFg;
    String severityLabel;

    switch (item.severity) {
      case StockAlertSeverityEnum.outOfStock:
        severityBg = AppTheme.roseLight;
        severityFg = AppTheme.roseDanger;
        severityLabel = 'OUT OF STOCK';
        break;
      case StockAlertSeverityEnum.criticalLow:
        severityBg = AppTheme.roseLight;
        severityFg = AppTheme.roseDanger;
        severityLabel = 'CRITICAL (<=${item.safetyStockLevel.toStringAsFixed(0)})';
        break;
      case StockAlertSeverityEnum.reorderRecommended:
        severityBg = AppTheme.amberLight;
        severityFg = AppTheme.amberWarning;
        severityLabel = 'REORDER (<=${item.reorderThreshold.toStringAsFixed(0)})';
        break;
      case StockAlertSeverityEnum.adequate:
        severityBg = AppTheme.tealSurface;
        severityFg = AppTheme.primaryTealDark;
        severityLabel = 'IN STOCK';
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (item.severity == StockAlertSeverityEnum.outOfStock || item.severity == StockAlertSeverityEnum.criticalLow)
              ? AppTheme.roseDanger.withOpacity(0.4)
              : (item.severity == StockAlertSeverityEnum.reorderRecommended ? AppTheme.amberWarning.withOpacity(0.4) : AppTheme.slateBorder),
          width: (item.severity != StockAlertSeverityEnum.adequate) ? 1.5 : 1.0,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID: ${item.productId} • Base: ${item.baseUnit}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // Stock quantity badge
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${item.totalQuantity.toStringAsFixed(0)} ${item.baseUnit}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: item.severity == StockAlertSeverityEnum.outOfStock
                          ? AppTheme.roseDanger
                          : (item.severity == StockAlertSeverityEnum.criticalLow
                              ? AppTheme.roseDanger
                              : (item.severity == StockAlertSeverityEnum.reorderRecommended
                                  ? AppTheme.amberWarning
                                  : AppTheme.primaryTealDark)),
                    ),
                  ),
                  Text(
                    'Reorder Point: ${item.reorderThreshold.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppTheme.slateBorder),
          const SizedBox(height: 10),
          Row(
            children: [
              // Active batches count chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundLight,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.slateBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.layers, size: 12, color: AppTheme.slateMuted),
                    const SizedBox(width: 4),
                    Text(
                      '${item.activeBatchCount} batches',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.slateHeading,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Severity badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: severityBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  severityLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: severityFg,
                  ),
                ),
              ),

              if (item.hasExpiredBatches) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.roseLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Expired Lot',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.roseDanger,
                    ),
                  ),
                ),
              ],

              const Spacer(),

              // Threshold settings action button
              if (onConfigureThresholdTap != null) ...[
                InkWell(
                  onTap: onConfigureThresholdTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.slateBorder),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune, size: 12, color: AppTheme.slateHeading),
                        SizedBox(width: 4),
                        Text(
                          'Threshold',
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
                const SizedBox(width: 6),
              ],

              // Quick Movement action button
              InkWell(
                onTap: onAdjustTap,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.tealSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.swap_horiz, size: 13, color: AppTheme.primaryTealDark),
                      SizedBox(width: 4),
                      Text(
                        'Movement',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryTealDark,
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
    );
  }
}

