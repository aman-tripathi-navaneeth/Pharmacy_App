import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/local/outbox_dao.dart';
import '../domain/op_state.dart';
import '../sync_manager.dart';
import '../sync_providers.dart';
import '../sync_strings.dart';
import '../widgets/common.dart';

/// Screen 2 — Sync Status Dashboard (frames B1–B5).
class SyncStatusScreen extends ConsumerStatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  ConsumerState<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends ConsumerState<SyncStatusScreen> {
  bool _busy = false;

  Future<void> _sync({required bool manual}) async {
    setState(() => _busy = true);
    try {
      final summary = await ref.read(syncManagerProvider).syncNow(manual: manual);
      if (mounted) _showSummary(summary);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSummary(SyncRunSummary s) {
    final text = switch (s) {
      _ when s.offline => SyncStrings.runOffline,
      _ when s.errorCode != null => SyncStrings.error(s.errorCode, s.errorMessage, 'sync.run.stopped'),
      _ when s.isPartial => SyncStrings.runPartial(s.synced, s.attempted - s.synced),
      _ when s.synced > 0 => SyncStrings.runSynced(s.synced),
      _ when s.attempted > 0 => SyncStrings.runAttention(s.attempted),
      _ => SyncStrings.runUpToDate,
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final counts = ref.watch(syncCountsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(SyncStrings.syncStatus)),
      body: counts.when(
        loading: () => const _Loading(),
        error: (_, _) => Center(
          child: StateMessage(
            icon: Icons.sync_problem_rounded,
            title: SyncStrings.loadStatusError,
            body: SyncStrings.loadStatusErrorBody,
            actionLabel: SyncStrings.retry,
            onAction: () => ref.invalidate(syncCountsProvider),
          ),
        ),
        data: (c) => _Body(counts: c, busy: _busy, onSync: _sync),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.counts, required this.busy, required this.onSync});

  final SyncCounts counts;
  final bool busy;
  final Future<void> Function({required bool manual}) onSync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider).value ?? true;
    final progress = ref.watch(syncProgressProvider).value ?? const SyncProgress();
    final last = ref.watch(lastSuccessfulSyncProvider).value;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final t = Theme.of(context).textTheme;
    final syncing = progress.isSyncing || busy;

    final links = [
      LinkRow(label: SyncStrings.viewPending, onTap: () => context.push('/sync/pending')),
      LinkRow(label: SyncStrings.integrationHealth, onTap: () => context.push('/integrations')),
      LinkRow(label: SyncStrings.openHelp, onTap: () => context.push('/support')),
    ];

    final syncNowButton = FilledButton(
      onPressed: online && !syncing ? () => onSync(manual: false) : null,
      child: Text(online ? SyncStrings.syncNow : SyncStrings.syncNowOffline, textAlign: TextAlign.center),
    );

    // B3 — empty
    if (counts.isEmpty && online && !syncing) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(SyncStrings.lastSync(last, now), style: t.bodyMedium),
          StateMessage(
            icon: Icons.cloud_done_rounded,
            title: SyncStrings.allSynced,
            body: SyncStrings.allSyncedBody,
          ),
          syncNowButton,
          const SizedBox(height: 16),
          ...links,
        ],
      );
    }

    // B1 populated / B4 offline
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!online) ...[
          StatusBanner(text: SyncStrings.offlinePaused, tone: BannerTone.neutral, icon: Icons.cloud_off_rounded),
          const SizedBox(height: 12),
        ],
        Text(SyncStrings.lastSync(last, now), style: t.bodyMedium),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.9,
          children: [
            _Tile(label: SyncStrings.pending, value: counts.pending, onTap: () => context.push('/sync/pending')),
            _Tile(label: SyncStrings.synced, value: counts.synced),
            _Tile(
              label: SyncStrings.failed,
              value: counts.failed,
              onTap: () => context.push('/sync/pending?filter=${OpState.failedPermanent.name}'),
            ),
            _Tile(
              label: SyncStrings.conflicts,
              value: counts.conflict,
              onTap: () => context.push('/sync/pending?filter=${OpState.conflict.name}'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: syncNowButton),
            if (online) ...[
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: counts.retryWait > 0 && !syncing ? () => onSync(manual: true) : null,
                  child: Text(SyncStrings.retryEligible),
                ),
              ),
            ],
          ],
        ),
        if (syncing) ...[
          const SizedBox(height: 16),
          Text(SyncStrings.progress(progress.done, progress.total), style: t.bodyMedium),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: progress.total == 0 ? null : progress.done / progress.total,
              semanticsLabel: SyncStrings.progress(progress.done, progress.total),
            ),
          ),
        ],
        const SizedBox(height: 16),
        ...links,
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.onTap});

  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: onTap != null,
      label: '$label: $value',
      excludeSemantics: true,
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                Text('$value', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Semantics(
        label: SyncStrings.loadingStatus,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SkeletonBox(width: 200),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.9,
              children: List.generate(4, (_) => const SkeletonBox(height: 72)),
            ),
            const SizedBox(height: 20),
            const SkeletonBox(height: 48),
          ],
        ),
      );
}
