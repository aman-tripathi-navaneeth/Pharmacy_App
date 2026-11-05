import 'package:flutter/material.dart';

import '../models/expiry.dart';

extension ExpiryStatusStyle on ExpiryStatus {
  Color get color => switch (this) {
        ExpiryStatus.expired => const Color(0xFFC62828),
        ExpiryStatus.critical => const Color(0xFFEF6C00),
        ExpiryStatus.warning => const Color(0xFFF9A825),
        ExpiryStatus.ok => const Color(0xFF2E7D32),
        ExpiryStatus.noExpiry => const Color(0xFF757575),
      };
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final ExpiryStatus status;

  @override
  Widget build(BuildContext context) {
    final c = status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}
