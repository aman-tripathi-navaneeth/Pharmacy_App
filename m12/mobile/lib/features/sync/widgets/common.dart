import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// Empty / error / no-results message used across sync screens.
class StateMessage extends StatelessWidget {
  const StateMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(body, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 24),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

/// Grey placeholder bar for loading states (B2, C4, G3 in the wireframes).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.height = 16, this.width});

  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
      );
}

enum BannerTone { info, warning, error, success, neutral }

/// Inline status banner (e.g. "RETRY_WAIT · Network timed out. Safe to retry.").
class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.text, this.tone = BannerTone.warning, this.icon});

  final String text;
  final BannerTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.status;
    final (bg, fg) = switch (tone) {
      BannerTone.info => (c.syncingBg, c.syncingFg),
      BannerTone.warning => (c.warningBg, c.warningFg),
      BannerTone.error => (c.errorBg, c.errorFg),
      BannerTone.success => (c.onlineBg, c.onlineFg),
      BannerTone.neutral => (c.offlineBg, c.offlineFg),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg))),
        ],
      ),
    );
  }
}

class LinkRow extends StatelessWidget {
  const LinkRow({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.arrow_forward_rounded),
        minLeadingWidth: 20,
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        onTap: onTap,
      );
}
