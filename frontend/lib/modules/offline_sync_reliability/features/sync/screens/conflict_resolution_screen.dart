import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/local/app_database.dart';
import '../../../data/remote/sync_api.dart';
import '../../../l10n/translations.dart';
import '../domain/op_state.dart';
import '../sync_providers.dart';
import '../sync_repository.dart';
import '../sync_strings.dart';
import '../widgets/common.dart';

enum _Choice { server, device }

/// Screen 5 — Conflict Resolution (frames E1 compare, E2 confirm, E3 resolved).
/// Never overwrites silently: every choice is confirmed and recorded.
class ConflictResolutionScreen extends ConsumerStatefulWidget {
  const ConflictResolutionScreen({super.key, required this.operationId});

  final String operationId;

  @override
  ConsumerState<ConflictResolutionScreen> createState() => _ConflictResolutionScreenState();
}

class _ConflictResolutionScreenState extends ConsumerState<ConflictResolutionScreen> {
  bool _busy = false;
  _Choice? _resolvedWith;
  String? _resolutionOpId;

  Future<void> _resolve(OutboxOp op, ConflictInfo conflict, _Choice choice) async {
    final spec = ref.read(offlineCatalogProvider).lookup(op.module, op.operationType);
    final fields = SyncStrings.joinFields([for (final f in conflict.fields) spec?.fieldLabel(f) ?? f]);
    final (title, body) = switch (choice) {
      _Choice.device => (tr('sync.conflict.keepDeviceTitle'), tr('sync.conflict.keepDeviceBody', {'fields': fields})),
      _Choice.server => (tr('sync.conflict.keepServerTitle'), tr('sync.conflict.keepServerBody', {'fields': fields})),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(SyncStrings.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(SyncStrings.confirm)),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final repo = ref.read(syncRepositoryProvider);
    try {
      if (choice == _Choice.device) {
        final next = await repo.resolveKeepDevice(op);
        _resolutionOpId = next.clientOperationId;
      } else {
        await repo.resolveKeepServer(op);
      }
      setState(() => _resolvedWith = choice);
    } on ApiException catch (e) {
      _snack(e is ApiNetworkException ? tr('sync.conflict.unreachable') : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(operationProvider(widget.operationId));
    return Scaffold(
      appBar: AppBar(title: Text(SyncStrings.resolveConflict)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => StateMessage(
          icon: Icons.error_outline_rounded,
          title: tr('sync.conflict.loadError'),
          body: tr('sync.conflict.loadErrorBody'),
        ),
        data: (op) {
          if (op == null) {
            return StateMessage(icon: Icons.search_off_rounded, title: tr('sync.conflict.notFound'), body: '');
          }
          if (_resolvedWith != null || op.state != OpState.conflict) return _resolved(context, op);
          final conflict = conflictOf(op);
          if (conflict == null) {
            return StateMessage(
              icon: Icons.help_outline_rounded,
              title: tr('sync.conflict.noComparison'),
              body: tr('sync.conflict.noComparisonBody'),
            );
          }
          return _compare(context, op, conflict);
        },
      ),
    );
  }

  // E1
  Widget _compare(BuildContext context, OutboxOp op, ConflictInfo conflict) {
    final spec = ref.watch(offlineCatalogProvider).lookup(op.module, op.operationType);
    final online = ref.watch(isOnlineProvider).value ?? true;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final allowDevice = spec?.allowKeepDeviceVersion ?? false;

    String show(Object? v) => v == null || '$v'.isEmpty ? '—' : '$v';
    final rows = [
      for (final f in conflict.fields)
        (spec?.fieldLabel(f) ?? f, show(conflict.serverValues[f]), show(conflict.clientValues[f])),
      (
        SyncStrings.updated,
        [if (conflict.serverUpdatedAt != null) SyncStrings.time(conflict.serverUpdatedAt!), '(v${conflict.serverVersion})'].join(' '),
        '${SyncStrings.time(op.createdAt)} (v${conflict.clientBaseVersion ?? op.baseVersion ?? '?'})',
      ),
    ];

    Widget cell(String s, {bool muted = false, bool differs = false}) => Expanded(
          child: Text(
            s,
            style: t.bodyMedium?.copyWith(
              color: muted ? scheme.onSurfaceVariant : null,
              fontWeight: differs ? FontWeight.w600 : null,
            ),
          ),
        );

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        StatusBanner(
          text: tr('sync.conflict.changedOnDevice', {'label': op.label}),
          tone: BannerTone.warning,
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                cell(SyncStrings.field, muted: true),
                cell(SyncStrings.server, muted: true),
                cell(SyncStrings.thisDevice, muted: true),
              ]),
              const SizedBox(height: 8),
              for (final (label, server, device) in rows)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Semantics(
                    label: tr('sync.conflict.cellA11y', {'field': label, 'server': server, 'device': device}),
                    excludeSemantics: true,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        cell(label, muted: true),
                        cell(server, differs: server != device),
                        cell(device, differs: server != device),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(SyncStrings.chooseVersion, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              if (!online) ...[
                const SizedBox(height: 12),
                StatusBanner(
                  text: tr('sync.conflict.offlineKeepServer'),
                  tone: BannerTone.neutral,
                  icon: Icons.cloud_off_rounded,
                ),
              ],
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _busy || !online ? null : () => _resolve(op, conflict, _Choice.server),
                child: Text(SyncStrings.keepServer),
              ),
              const SizedBox(height: 12),
              if (allowDevice) ...[
                OutlinedButton(
                  onPressed: _busy ? null : () => _resolve(op, conflict, _Choice.device),
                  child: Text(SyncStrings.keepDevice),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () {
                        _snack(tr('sync.conflict.leftForReview'));
                        context.pop();
                      },
                child: Text(SyncStrings.reviewManually),
              ),
              if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
            ],
          ),
        ),
      ],
    );
  }

  // E3
  Widget _resolved(BuildContext context, OutboxOp op) {
    final t = Theme.of(context).textTheme;
    final pending = ref.watch(syncCountsProvider).value?.pending ?? 0;
    final resolution = _resolutionOpId == null ? null : ref.watch(operationProvider(_resolutionOpId!)).value;
    final keptServer = _resolvedWith == _Choice.server || op.resolution == 'KEEP_SERVER';

    final (String headline, String body, BannerTone tone) = switch (resolution?.state) {
      _ when keptServer => (
          tr('sync.conflict.resolvedServer'),
          tr('sync.conflict.resolvedServerBody'),
          BannerTone.success,
        ),
      OpState.synced => (
          tr('sync.conflict.resolvedSynced', {'time': SyncStrings.time(resolution!.syncedAt ?? DateTime.now())}),
          tr('sync.conflict.resolvedSyncedBody', {'version': '${resolution.serverVersion ?? '?'}'}),
          BannerTone.success,
        ),
      OpState.conflict => (
          tr('sync.conflict.changedAgain'),
          tr('sync.conflict.changedAgainBody'),
          BannerTone.warning,
        ),
      OpState.failedPermanent => (
          tr('sync.conflict.couldNotApply'),
          SyncStrings.error(resolution!.lastErrorCode, resolution.lastErrorMessage, 'sync.conflict.couldNotApplyBody'),
          BannerTone.error,
        ),
      _ => (
          tr('sync.conflict.savedLocally'),
          tr('sync.conflict.savedLocallyBody'),
          BannerTone.info,
        ),
    };

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        StatusBanner(text: headline, tone: tone),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(op.label, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(body, style: t.bodyMedium),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(tr('sync.conflict.otherWaiting', {'count': pending}), style: t.bodyMedium),
              const SizedBox(height: 16),
              if (resolution?.state == OpState.conflict)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FilledButton(
                    onPressed: () => context.pushReplacement('/sync/conflicts/${resolution!.clientOperationId}'),
                    child: Text(SyncStrings.review),
                  ),
                ),
              FilledButton(onPressed: () => context.go('/sync'), child: Text(SyncStrings.backToSyncStatus)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.go('/sync/pending'),
                child: Text(SyncStrings.viewPending),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
