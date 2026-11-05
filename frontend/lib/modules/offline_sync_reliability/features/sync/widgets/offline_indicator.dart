import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../data/local/outbox_dao.dart';
import '../sync_manager.dart';
import '../sync_providers.dart';
import '../sync_strings.dart';

enum IndicatorKind { online, offline, syncing, attention, queueWarning }

/// Decides what the global indicator shows. Syncing > offline > attention > backlog > online.
IndicatorKind indicatorKind({
  required bool online,
  required SyncProgress progress,
  required SyncCounts counts,
  required DateTime now,
  int queueWarningCount = 100,
  Duration queueWarningAge = const Duration(minutes: 15),
}) {
  if (progress.isSyncing) return IndicatorKind.syncing;
  if (!online) return IndicatorKind.offline;
  if (counts.needsAttention > 0) return IndicatorKind.attention;
  final oldest = counts.oldestPendingAt;
  if (counts.pending >= queueWarningCount || (oldest != null && now.difference(oldest) > queueWarningAge)) {
    return IndicatorKind.queueWarning;
  }
  return IndicatorKind.online;
}

/// Global Offline/Online indicator (screen 1, frames A1–A4). Tap → Sync Status.
class OfflineIndicator extends ConsumerWidget {
  const OfflineIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider).value ?? true;
    final progress = ref.watch(syncProgressProvider).value ?? const SyncProgress();
    final counts = ref.watch(syncCountsProvider).value ?? const SyncCounts();
    final last = ref.watch(lastSuccessfulSyncProvider).value;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final config = ref.watch(syncConfigProvider);
    final c = context.status;

    final kind = indicatorKind(
      online: online,
      progress: progress,
      counts: counts,
      now: now,
      queueWarningCount: config.queueWarningCount,
      queueWarningAge: config.queueWarningAge,
    );
    final lastText = last == null ? SyncStrings.never : SyncStrings.relative(last, now);

    final (Color bg, Color fg, IconData icon, String text) = switch (kind) {
      IndicatorKind.online => (c.onlineBg, c.onlineFg, Icons.circle, SyncStrings.online(lastText, counts.pending)),
      IndicatorKind.offline => (c.offlineBg, c.offlineFg, Icons.cloud_off_rounded, SyncStrings.offline(counts.pending)),
      IndicatorKind.syncing => (
          c.syncingBg,
          c.syncingFg,
          Icons.sync_rounded,
          SyncStrings.syncing(progress.done, progress.total, last == null ? SyncStrings.neverSynced : SyncStrings.lastSyncAt(last)),
        ),
      IndicatorKind.attention => (c.warningBg, c.warningFg, Icons.error_outline_rounded, SyncStrings.needsAttention(counts.needsAttention)),
      IndicatorKind.queueWarning => (
          c.warningBg,
          c.warningFg,
          Icons.hourglass_bottom_rounded,
          SyncStrings.queueWarning(counts.pending, SyncStrings.relative(counts.oldestPendingAt!, now).replaceAll(' ago', '')),
        ),
    };

    return Semantics(
      button: true,
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: Material(
        color: bg,
        child: InkWell(
          onTap: () => context.push('/sync'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: kind == IndicatorKind.online ? 10 : 18, color: fg),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg)),
                ),
                Icon(Icons.chevron_right_rounded, color: fg, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
