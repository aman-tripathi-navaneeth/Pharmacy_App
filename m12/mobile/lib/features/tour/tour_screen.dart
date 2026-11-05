import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/translations.dart';
import '../sync/widgets/common.dart';
import 'tour_controller.dart';
import 'tour_models.dart';

const _icons = <String, IconData>{
  'storefront': Icons.storefront_rounded,
  'dashboard': Icons.space_dashboard_rounded,
  'cloud_off': Icons.cloud_off_rounded,
  'support': Icons.support_agent_rounded,
  'sync': Icons.sync_rounded,
  'check': Icons.check_circle_rounded,
  'translate': Icons.translate_rounded,
};

/// Screen 11 — Product Tour / Getting Started (frames K1 welcome, K2 sync status, K3 finish).
/// Skippable on every step, resumable after leaving, restartable from Help.
class TourScreen extends ConsumerStatefulWidget {
  const TourScreen({super.key, this.restart = false});

  /// Opened from Help → Product tour: start again at step 1.
  final bool restart;

  @override
  ConsumerState<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends ConsumerState<TourScreen> {
  int? _index;

  void _go(TourState tour, int index) {
    setState(() => _index = index);
    final last = index == tour.total - 1;
    ref.read(tourProvider.notifier).record(index, last ? TourStatus.completed : TourStatus.inProgress);
  }

  Future<void> _skip(int index) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(tourProvider.notifier).record(index, TourStatus.skipped);
    if (!mounted) return;
    Navigator.of(context).maybePop();
    messenger.showSnackBar(SnackBar(content: Text(tr('tour.skipped'))));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tourProvider);
    return async.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: Text(tr('tour.title'))),
        body: StateMessage(icon: Icons.tour_rounded, title: tr('tour.title'), body: ''),
      ),
      data: (tour) {
        if (_index == null) {
          final start = widget.restart ? 0 : tour.resumeIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _go(tour, start) : null);
          _index = start;
        }
        return _page(context, tour, _index!.clamp(0, tour.total - 1));
      },
    );
  }

  Widget _page(BuildContext context, TourState tour, int index) {
    final step = tour.definition.steps[index];
    final last = step.type == TourStepType.finish;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final stepText = tr(last ? 'tour.stepComplete' : 'tour.step', {'current': index + 1, 'total': tour.total});

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('tour.title')),
        actions: [
          if (!last && index > 0) TextButton(onPressed: () => _skip(index), child: Text(tr('tour.skip'))),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: ListView(
                  key: ValueKey(step.id),
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                  children: [
                    Icon(_icons[step.icon] ?? Icons.info_outline_rounded, size: 56, color: scheme.primary),
                    const SizedBox(height: 20),
                    Semantics(
                      header: true,
                      child: Text(tr(step.titleKey), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 12),
                    if (step.bodyKey != null) Text(tr(step.bodyKey!), style: t.bodyLarge),
                    if (step.type == TourStepType.syncStates) ...[
                      const SizedBox(height: 8),
                      for (final item in step.items) _SyncStateRow(item: item),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                children: [
                  Semantics(
                    label: stepText,
                    excludeSemantics: true,
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < tour.total; i++)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: i == index ? 20 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: i <= index ? scheme.primary : scheme.outlineVariant,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(stepText, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: switch ((index, last)) {
                            (_, true) => () => _go(tour, 0),
                            (0, _) => () => _skip(index),
                            _ => () => _go(tour, index - 1),
                          },
                          child: Text(last ? tr('tour.restart') : index == 0 ? tr('tour.skip') : tr('tour.back'), textAlign: TextAlign.center),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: last ? () => Navigator.of(context).maybePop() : () => _go(tour, index + 1),
                          child: Text(last ? tr('tour.finishButton') : tr('tour.next'), textAlign: TextAlign.center),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncStateRow extends StatelessWidget {
  const _SyncStateRow({required this.item});

  final TourItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.status;
    final (bg, fg) = switch (item.tone) {
      'info' => (c.syncingBg, c.syncingFg),
      'success' => (c.onlineBg, c.onlineFg),
      'warning' => (c.warningBg, c.warningFg),
      'error' => (c.errorBg, c.errorFg),
      _ => (c.offlineBg, c.offlineFg),
    };
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 96),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
            child: Text(tr(item.labelKey), style: t.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr(item.descriptionKey), style: t.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }
}
