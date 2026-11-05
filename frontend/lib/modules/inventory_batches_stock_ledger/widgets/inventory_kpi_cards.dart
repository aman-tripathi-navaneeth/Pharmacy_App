import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/inventory_service.dart';

class InventoryKpiCards extends StatelessWidget {
  final InventoryService service;

  const InventoryKpiCards({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildKpiCard(
            title: 'In-Stock Units',
            value: '${service.totalStockUnits}',
            subtext: 'across active batches',
            icon: Icons.inventory_2_outlined,
            iconBg: AppTheme.tealSurface,
            iconColor: AppTheme.primaryTeal,
          ),
          const SizedBox(width: 12),
          _buildKpiCard(
            title: 'Active Batches',
            value: '${service.activeBatchesCount}',
            subtext: 'FEFO managed',
            icon: Icons.layers_outlined,
            iconBg: AppTheme.blueLight,
            iconColor: AppTheme.blueInfo,
          ),
          const SizedBox(width: 12),
          _buildKpiCard(
            title: 'Expiring Soon',
            value: '${service.expiringSoonCount}',
            subtext: 'within 60 days',
            icon: Icons.notification_important_outlined,
            iconBg: service.expiringSoonCount > 0 ? AppTheme.amberLight : AppTheme.slateBorder.withOpacity(0.4),
            iconColor: service.expiringSoonCount > 0 ? AppTheme.amberWarning : AppTheme.slateMuted,
          ),
          const SizedBox(width: 12),
          _buildKpiCard(
            title: 'Ledger Postings',
            value: '${service.totalTransactionsCount}',
            subtext: 'authoritative movements',
            icon: Icons.receipt_long_outlined,
            iconBg: AppTheme.emeraldLight,
            iconColor: AppTheme.emeraldGreen,
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtext,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
  }) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
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
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.slateDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.slateHeading,
            ),
          ),
          Text(
            subtext,
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.slateMuted,
            ),
          ),
        ],
      ),
    );
  }
}
