import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/local/app_database.dart';
import '../domain/op_state.dart';
import '../sync_providers.dart';
import '../sync_repository.dart';
import '../sync_strings.dart';
import '../widgets/common.dart';
import '../widgets/op_presentation.dart';
import 'pending_operations_screen.dart' show confirmCancel;

/// Screen 4 — Operation Details (frames D1–D2).
class OperationDetailsScreen extends ConsumerStatefulWidget {
  const OperationDetailsScreen({super.key, required this.operationId});

  final String operationId;

  @override
  ConsumerState<OperationDetailsScreen> createState() => _OperationDetailsScreenState();
}

class _OperationDetailsScreenState extends ConsumerState<OperationDetailsScreen> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await ref.read(syncRepositoryProvider).retryNow(widget.operationId);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(operationProvider(widget.operationId));
    return Scaffold(
      appBar: AppBar(title: Text(SyncStrings.operationDetails)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => StateMessage(
          icon: Icons.error_outline_rounded,
          title: SyncStrings.loadOpsError,
          body: SyncStrings.loadOpsErrorBody,
          actionLabel: SyncStrings.retry,
          onAction: () => ref.invalidate(operationProvider(widget.operationId)),
        ),
        data: (op) => op == null
            ? StateMessage(
                icon: Icons.search_off_rounded,
                title: SyncStrings.opNotFound,
                body: SyncStrings.opNotFoundBody,
              )
            : _details(context, op),
      ),
    );
  }

  Widget _details(BuildContext context, OutboxOp op) {
    final config = ref.watch(syncConfigProvider);
    final catalog = ref.watch(offlineCatalogProvider);
    final online = ref.watch(isOnlineProvider).value ?? true;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final failed = op.state == OpState.failedPermanent;

    final rows = <(String, String)>[
      (SyncStrings.operationId, _shortId(op.clientOperationId)),
      if (!failed) (SyncStrings.serverId, op.serverResourceId ?? SyncStrings.notConfirmed),
      (SyncStrings.attempts, op.attemptsText(config)),
      (SyncStrings.created, SyncStrings.time(op.createdAt)),
      if (op.lastAttemptAt != null)
        (
          SyncStrings.lastAttempt,
          [SyncStrings.time(op.lastAttemptAt!), if (op.lastErrorCode != null) _errorWord(op.lastErrorCode!)].join(' · '),
        ),
      if (op.state == OpState.retryWait)
        (
          SyncStrings.nextRetry,
          op.exhausted(config)
              ? SyncStrings.manualRetryNeeded
              : op.nextAttemptAt == null
                  ? SyncStrings.soon
                  : SyncStrings.backoff(op.nextAttemptAt!),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(op.title(catalog), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        StatusBanner(text: op.bannerText(config), tone: op.tone),
        const SizedBox(height: 12),
        for (final (label, value) in rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
            child: Row(
              children: [
                Expanded(child: Text(label, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
                Expanded(child: Text(value, style: t.bodyMedium)),
              ],
            ),
          ),
        const SizedBox(height: 20),
        Text(failed ? SyncStrings.whatYouCanDo : SyncStrings.nextAction,
            style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(op.nextActionText(config, catalog), style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 20),
        ..._actions(context, op, online),
      ],
    );
  }

  List<Widget> _actions(BuildContext context, OutboxOp op, bool online) {
    Widget gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w);
    final viewCanonical = OutlinedButton(
      onPressed: op.serverResourceId == null ? null : () => _showCanonical(context, op),
      child: Text(SyncStrings.viewCanonical),
    );
    final copyId = OutlinedButton(
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: op.clientOperationId));
        _snack(SyncStrings.copied);
      },
      child: Text(SyncStrings.copyOperationId),
    );
    final support = OutlinedButton(
      onPressed: () => context.push(Uri(path: '/support/new', queryParameters: {
        'operationId': op.clientOperationId,
        'module': op.module,
      }).toString()),
      child: Text(SyncStrings.contactSupport),
    );

    return switch (op.state) {
      OpState.retryWait => [
          gap(FilledButton(
            onPressed: online && !_retrying ? _retry : null,
            child: Text(_retrying ? SyncStrings.retrying : SyncStrings.retryNow),
          )),
          if (canCancel(op)) gap(OutlinedButton(onPressed: () => confirmCancel(context, ref, op), child: Text(SyncStrings.cancel))),
          gap(viewCanonical),
        ],
      OpState.queued => [
          gap(OutlinedButton(onPressed: () => confirmCancel(context, ref, op), child: Text(SyncStrings.cancel))),
          gap(copyId),
        ],
      OpState.failedPermanent => [
          gap(FilledButton(
            onPressed: () => _snack(SyncStrings.correctDataHint(ref.read(offlineCatalogProvider).moduleLabel(op.module))),
            child: Text(SyncStrings.correctData),
          )),
          gap(support),
          gap(copyId),
        ],
      OpState.conflict => [
          gap(FilledButton(
            onPressed: () => context.push('/sync/conflicts/${op.clientOperationId}'),
            child: Text(SyncStrings.review),
          )),
          gap(copyId),
        ],
      OpState.inFlight => [gap(copyId)],
      OpState.synced || OpState.cancelled => [gap(viewCanonical), gap(copyId)],
    };
  }

  void _showCanonical(BuildContext context, OutboxOp op) {
    final catalog = ref.read(offlineCatalogProvider);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(SyncStrings.canonicalTitle, style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(SyncStrings.canonicalModule(catalog.moduleLabel(op.module))),
            Text(SyncStrings.canonicalServerId(op.serverResourceId ?? '')),
            if (op.serverVersion != null) Text(SyncStrings.canonicalVersion(op.serverVersion!)),
            const SizedBox(height: 12),
            Text(
              SyncStrings.canonicalNote(catalog.moduleLabel(op.module)),
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

String _shortId(String id) => id.length <= 12 ? id : 'op_${id.substring(0, 4)}…${id.substring(id.length - 3)}';

String _errorWord(String code) => SyncStrings.errorWord(code);
