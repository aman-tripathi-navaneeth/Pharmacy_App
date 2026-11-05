import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/enums.dart';

class MovementBadge extends StatelessWidget {
  final MovementType movementType;

  const MovementBadge({super.key, required this.movementType});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;

    switch (movementType) {
      case MovementType.purchaseIn:
        bg = AppTheme.emeraldLight;
        fg = AppTheme.emeraldGreen;
        icon = Icons.add_circle_outline;
        break;
      case MovementType.salesReportOut:
        bg = AppTheme.roseLight;
        fg = AppTheme.roseDanger;
        icon = Icons.remove_circle_outline;
        break;
      case MovementType.returnIn:
        bg = AppTheme.tealSurface;
        fg = AppTheme.primaryTeal;
        icon = Icons.keyboard_return;
        break;
      case MovementType.returnOut:
        bg = AppTheme.amberLight;
        fg = AppTheme.amberWarning;
        icon = Icons.call_missed_outgoing;
        break;
      case MovementType.adjustmentAdd:
        bg = AppTheme.blueLight;
        fg = AppTheme.blueInfo;
        icon = Icons.tune;
        break;
      case MovementType.adjustmentSubtract:
        bg = AppTheme.roseLight;
        fg = AppTheme.roseDanger;
        icon = Icons.error_outline;
        break;
      case MovementType.reversal:
        bg = const Color(0xFFF1F5F9);
        fg = AppTheme.slateMuted;
        icon = Icons.history;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            movementType.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
