import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/integrations_api.dart';
import '../sync/sync_strings.dart';
import '../sync/widgets/common.dart';
import 'health_strings.dart';
import 'integration_health_controller.dart';

/// Screen 6 — Integration Health (frames F1 healthy, F2 degraded, F3 unavailable).
/// Shows only curated status text from the server; never URLs or secrets.
class IntegrationHealthScreen extends ConsumerWidget {
  const IntegrationHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(integrationHealthProvider);
    return Scaffold(
      appBar: AppBar(title: Text(HealthStrings.title)),
      body: async.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const _Loading(),
        error: (e, _) => Center(
          child: StateMessage(
            icon: Icons.cloud_off_rounded,
            title: HealthStrings.loadError,
            body: e is ApiNetworkException && e.code == 'OFFLINE'
                ? HealthStrings.loadErrorOffline
                : HealthStrings.loadErrorBody,
            actionLabel: SyncStrings.retry,
            onAction: () => ref.invalidate(integrationHealthProvider),
          ),
        ),
        data: (view) => RefreshIndicator(
          onRefresh: () => ref.refresh(integrationHealthProvider.future),
          child: _Body(view: view),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.view});

  final HealthView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final problems = view.problems;
    final checked = SyncStrings.time(view.report.checkedAt);
    final refreshMin = view.report.refreshAfter.inMinutes;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        if (view.stale) ...[
          StatusBanner(
            text: view.offline
                ? HealthStrings.offlineStale(checked)
                : HealthStrings.errorStale(checked),
            tone: BannerTone.neutral,
            icon: view.offline ? Icons.cloud_off_rounded : Icons.sync_problem_rounded,
          ),
          const SizedBox(height: 12),
        ],
        Text(
          problems.isEmpty && !view.stale
              ? HealthStrings.lastCheckedAuto(checked, refreshMin)
              : HealthStrings.lastChecked(checked),
          style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        for (final m in problems) ...[
          _ProblemCard(module: m, canRetry: !view.offline),
          const SizedBox(height: 12),
        ],
        if (problems.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(HealthStrings.otherModules, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
        ],
        Card(
          child: Column(
            children: [
              for (final (i, m) in view.others.indexed) ...[
                if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                _ModuleRow(module: m),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProblemCard extends ConsumerStatefulWidget {
  const _ProblemCard({required this.module, required this.canRetry});

  final ModuleHealth module;
  final bool canRetry;

  @override
  ConsumerState<_ProblemCard> createState() => _ProblemCardState();
}

class _ProblemCardState extends ConsumerState<_ProblemCard> {
  bool _checking = false;

  Future<void> _retry() async {
    setState(() => _checking = true);
    String text;
    try {
      final m = await ref.read(integrationHealthProvider.notifier).recheck(widget.module.key);
      final label = HealthStrings.moduleLabel(m);
      text = m.hasProblem ? HealthStrings.stillProblem(label, m.status) : HealthStrings.operationalAgain(label);
    } on ApiException catch (e) {
      text = e.message;
    } finally {
      if (mounted) setState(() => _checking = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.module;
    final t = Theme.of(context).textTheme;
    final c = context.status;
    final unavailable = m.status == HealthStatus.unavailable;
    final (bg, fg) = unavailable ? (c.errorBg, c.errorFg) : (c.warningBg, c.warningFg);

    final details = <String>[
      if (m.message != null) m.message!,
      ?HealthStrings.guidance(m),
      if (unavailable && m.lastOkAt != null) HealthStrings.lastKnown(SyncStrings.time(m.lastOkAt!)),
      HealthStrings.autoChecked,
    ];

    return Semantics(
      container: true,
      label: '${HealthStrings.moduleLabel(m)}: ${_statusWord(m.status)}',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(unavailable ? Icons.cloud_off_rounded : Icons.warning_amber_rounded, color: fg, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${HealthStrings.moduleLabel(m)} · ${_statusWord(m.status)}',
                    style: t.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final d in details)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(d, style: t.bodyMedium?.copyWith(color: fg)),
              ),
            const SizedBox(height: 6),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: fg, side: BorderSide(color: fg.withValues(alpha: 0.6))),
              onPressed: widget.canRetry && !_checking ? _retry : null,
              child: Text(_checking ? HealthStrings.checking : HealthStrings.retryCheck),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({required this.module});

  final ModuleHealth module;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final c = context.status;
    final ok = module.status == HealthStatus.operational;
    final subtitle = ok
        ? (module.lastCheckedAt == null
            ? HealthStrings.operationalOk
            : HealthStrings.operationalChecked(SyncStrings.time(module.lastCheckedAt!)))
        : HealthStrings.notConnected;

    return Semantics(
      label: '${HealthStrings.moduleLabel(module)}: ${_statusWord(module.status)}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(HealthStrings.moduleLabel(module), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: ok ? c.onlineBg : c.offlineBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                ok ? HealthStrings.ok : HealthStrings.notSetUp,
                style: t.labelMedium?.copyWith(color: ok ? c.onlineFg : c.offlineFg, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _statusWord(HealthStatus s) => HealthStrings.status(s);

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Semantics(
        label: HealthStrings.loading,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SkeletonBox(width: 220),
            const SizedBox(height: 16),
            for (var i = 0; i < 6; i++) ...[const SkeletonBox(height: 56), const SizedBox(height: 8)],
          ],
        ),
      );
}
