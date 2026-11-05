import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/local/app_database.dart';
import '../../../l10n/translations.dart';
import '../domain/op_state.dart';
import '../sync_providers.dart';
import '../sync_repository.dart';
import '../sync_strings.dart';
import '../widgets/common.dart';
import '../widgets/op_presentation.dart';

const _filters = <OpState?>[
  null,
  OpState.queued,
  OpState.inFlight,
  OpState.retryWait,
  OpState.failedPermanent,
  OpState.conflict,
];

/// Screen 3 — Pending Operations (frames C1–C5).
class PendingOperationsScreen extends ConsumerStatefulWidget {
  const PendingOperationsScreen({super.key, this.initialFilter});

  final OpState? initialFilter;

  @override
  ConsumerState<PendingOperationsScreen> createState() => _PendingOperationsScreenState();
}

class _PendingOperationsScreenState extends ConsumerState<PendingOperationsScreen> {
  late OpState? _filter = widget.initialFilter;

  @override
  Widget build(BuildContext context) {
    final ops = ref.watch(openOpsProvider(_filter));
    return Scaffold(
      appBar: AppBar(title: Text(SyncStrings.pendingOperations)),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _filters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final f = _filters[i];
                return ChoiceChip(
                  label: Text(f == null ? SyncStrings.all : SyncStrings.stateLabel(f)),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                );
              },
            ),
          ),
          Expanded(
            child: ops.when(
              loading: () => ListView(
                padding: const EdgeInsets.all(16),
                children: List.generate(
                  3,
                  (_) => const Padding(padding: EdgeInsets.only(bottom: 12), child: SkeletonBox(height: 88)),
                ),
              ),
              error: (_, _) => StateMessage(
                icon: Icons.error_outline_rounded,
                title: SyncStrings.loadOpsError,
                body: SyncStrings.loadOpsErrorBody,
                actionLabel: SyncStrings.retry,
                onAction: () => ref.invalidate(openOpsProvider(_filter)),
              ),
              data: (list) {
                if (list.isEmpty && _filter == null) {
                  return StateMessage(
                    icon: Icons.inbox_rounded,
                    title: SyncStrings.noPending,
                    body: SyncStrings.noPendingBody,
                  );
                }
                if (list.isEmpty) {
                  return StateMessage(
                    icon: Icons.filter_alt_off_rounded,
                    title: SyncStrings.noMatch(SyncStrings.stateLabel(_filter!)),
                    body: '',
                    actionLabel: SyncStrings.clearFilter,
                    onAction: () => setState(() => _filter = null),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => OperationCard(op: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class OperationCard extends ConsumerWidget {
  const OperationCard({super.key, required this.op});

  final OutboxOp op;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(syncConfigProvider);
    final catalog = ref.watch(offlineCatalogProvider);
    final online = ref.watch(isOnlineProvider).value ?? true;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final actions = <Widget>[
      if (op.state == OpState.retryWait)
        OutlinedButton(
          onPressed: online ? () => ref.read(syncRepositoryProvider).retryNow(op.clientOperationId) : null,
          child: Text(SyncStrings.retry),
        ),
      if (canCancel(op))
        OutlinedButton(
          onPressed: () => confirmCancel(context, ref, op),
          child: Text(SyncStrings.cancel),
        ),
      if (op.state == OpState.conflict)
        OutlinedButton(
          onPressed: () => context.push('/sync/conflicts/${op.clientOperationId}'),
          child: Text(SyncStrings.review),
        ),
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/sync/operations/${op.clientOperationId}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(op.title(catalog), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(op.summary(config), style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// C5 — confirmation dialog, then a safe cancel (local if never sent, else server-confirmed).
Future<void> confirmCancel(BuildContext context, WidgetRef ref, OutboxOp op) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(SyncStrings.cancelTitle),
      content: Text(SyncStrings.cancelBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(SyncStrings.keepIt)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(SyncStrings.cancelOperation),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final outcome = await ref.read(syncRepositoryProvider).cancel(op.clientOperationId);
  if (!context.mounted) return;
  final message = switch (outcome) {
    CancelOutcome.cancelled => tr('sync.cancel.done'),
    CancelOutcome.alreadyCommitted => tr('sync.cancel.alreadyCommitted'),
    CancelOutcome.needsConnection => tr('sync.cancel.needsConnection'),
    CancelOutcome.hasDependents => tr('sync.cancel.hasDependents'),
    CancelOutcome.notCancellable => tr('sync.cancel.notCancellable'),
    CancelOutcome.failed => tr('sync.cancel.failed'),
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
