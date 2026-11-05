import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/connectivity_monitor.dart';
import '../sync/sync_providers.dart';
import '../tour/tour_controller.dart';
import '../tour/tour_models.dart';
import '../../l10n/translations.dart';
import '../sync/widgets/common.dart';
import '../sync/widgets/offline_indicator.dart';

/// Shows the developer tools in non-debug dev builds (`--dart-define=DEV_TOOLS=true`).
const _devTools = bool.fromEnvironment('DEV_TOOLS');

final _paracetamolProvider = StreamProvider<int?>((ref) => ref
    .watch(outboxDaoProvider)
    .watchEntity('stock_balance', 'paracetamol-500')
    .map((e) => e?.dataJson == null ? null : (jsonDecode(e!.dataJson!) as Map)['quantity'] as int?));

/// Placeholder home (frame A1). Domain modules replace the grey cards; the
/// global indicator stays at the top of every primary screen.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _maybeAutoLaunchTour(context, ref);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('home.title')),
        actions: [
          IconButton(
            tooltip: tr('language.title'),
            icon: const Icon(Icons.translate_rounded),
            onPressed: () => context.push('/language'),
          ),
          IconButton(
            tooltip: tr('home.help'),
            icon: const Icon(Icons.support_agent_rounded),
            onPressed: () => context.push('/support'),
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _ResumeTourCard(),
                const SkeletonBox(height: 110),
                const SizedBox(height: 12),
                const Row(children: [
                  Expanded(child: SkeletonBox(height: 80)),
                  SizedBox(width: 12),
                  Expanded(child: SkeletonBox(height: 80)),
                ]),
                const SizedBox(height: 12),
                const SkeletonBox(height: 80),
                if (kDebugMode || _devTools) ...[const SizedBox(height: 24), const _DevTools()],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// First launch of a tour version: open it once, unless sync items need attention.
void _maybeAutoLaunchTour(BuildContext context, WidgetRef ref) {
  if (ref.read(tourAutoLaunchedProvider)) return;
  final tour = ref.watch(tourProvider).value;
  final counts = ref.watch(syncCountsProvider).value;
  if (tour == null || counts == null) return;
  ref.read(tourAutoLaunchedProvider.notifier).set();
  if (shouldAutoLaunch(tour, counts)) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.push('/tour');
    });
  }
}

/// Shown when the user left the tour part-way ("resumable", spec §8.4).
class _ResumeTourCard extends ConsumerWidget {
  const _ResumeTourCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tour = ref.watch(tourProvider).value;
    if (tour == null || !tour.resumable) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tour_rounded),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tr('tour.continueTitle'), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                ],
              ),
              const SizedBox(height: 4),
              Text(tr('tour.continueBody', {'current': tour.resumeIndex + 1, 'total': tour.total})),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(onPressed: () => context.push('/tour'), child: Text(tr('tour.continue'))),
                  OutlinedButton(
                    onPressed: () => ref.read(tourProvider.notifier).record(tour.resumeIndex, TourStatus.skipped),
                    child: Text(tr('tour.dismiss')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Debug-only controls to exercise offline sync before domain modules exist.
class _DevTools extends ConsumerStatefulWidget {
  const _DevTools();

  @override
  ConsumerState<_DevTools> createState() => _DevToolsState();
}

class _DevToolsState extends ConsumerState<_DevTools> {
  final _rand = Random();

  Future<void> _queue(Future<void> Function() action, String message) async {
    try {
      await action();
      if (!mounted) return;
      final online = ref.read(isOnlineProvider).value ?? true;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(online ? message : '$message · saved on this device')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _stock(int delta, String reason, String label) => ref.read(syncRepositoryProvider).enqueue(
        module: 'inventory',
        operationType: 'stock_movement',
        label: label,
        payload: {'productId': 'paracetamol-500', 'quantityDelta': delta, 'reason': reason},
      );

  Future<void> _profile({required bool stale}) async {
    final session = ref.read(authSessionProvider);
    final cached = await ref.read(outboxDaoProvider).getEntity('shop_profile', session.storeId);
    await ref.read(syncRepositoryProvider).enqueue(
      module: 'shop',
      operationType: 'profile_update',
      label: 'Profile edit',
      entityId: session.storeId,
      baseVersion: stale ? 0 : (cached?.version ?? 0),
      payload: {
        'fields': {'phone': '+91 98${_rand.nextInt(900) + 100} ${_rand.nextInt(90000) + 10000}'},
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = ref.watch(connectivityProvider);
    final online = ref.watch(isOnlineProvider).value ?? true;
    final stock = ref.watch(_paracetamolProvider).value;
    final t = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Developer tools', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            Text('Paracetamol 500 · server stock: ${stock ?? '—'}', style: t.bodySmall),
            if (connectivity is PlusConnectivityMonitor)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Simulate offline'),
                value: connectivity.forceOffline,
                onChanged: (v) => setState(() => connectivity.setForceOffline(v)),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _queue(() => _stock(10, 'PURCHASE', 'Stock inward'), 'Stock inward +10 queued'),
                  child: const Text('Stock +10'),
                ),
                OutlinedButton(
                  onPressed: () => _queue(
                    () => _stock(-2, 'SALE', 'Sale S-${1000 + _rand.nextInt(9000)}'),
                    'Sale −2 queued',
                  ),
                  child: const Text('Sale −2'),
                ),
                OutlinedButton(
                  onPressed: () => _queue(() => _stock(-9999, 'SALE', 'Stock movement'), 'Oversell queued'),
                  child: const Text('Oversell (fails)'),
                ),
                OutlinedButton(
                  onPressed: () => _queue(() => _profile(stale: false), 'Profile edit queued'),
                  child: const Text('Edit phone'),
                ),
                OutlinedButton(
                  onPressed: () => _queue(() => _profile(stale: true), 'Stale profile edit queued'),
                  child: const Text('Stale edit (conflict)'),
                ),
              ],
            ),
            if (!online) Text('Offline: actions are saved locally.', style: t.bodySmall),
          ],
        ),
      ),
    );
  }
}
