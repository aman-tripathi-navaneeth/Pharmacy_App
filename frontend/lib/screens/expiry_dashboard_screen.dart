import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/expiry_repository.dart';
import '../models/expiry.dart';
import '../providers/expiry_provider.dart';
import '../widgets/batch_card.dart';
import '../widgets/message_state.dart';
import '../widgets/status_chip.dart';
import '../widgets/summary_card.dart';
import 'batch_disposal_screen.dart';

class ExpiryDashboardScreen extends StatelessWidget {
  const ExpiryDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => ExpiryProvider(ctx.read<ExpiryRepository>())..load(),
      child: const _ExpiryView(),
    );
  }
}

class _ExpiryView extends StatefulWidget {
  const _ExpiryView();

  @override
  State<_ExpiryView> createState() => _ExpiryViewState();
}

class _ExpiryViewState extends State<_ExpiryView> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
        context.read<ExpiryProvider>().loadMore();
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    _tabs.animateTo(index);
    context.read<ExpiryProvider>().setTab(ExpiryTab.values[index]);
  }

  Future<void> _openDisposal(ExpiryBatch batch) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BatchDisposalScreen(batch: batch)),
    );
    if (changed == true && mounted) context.read<ExpiryProvider>().load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ExpiryProvider>();
    final s = p.summary;

    return Scaffold(
      appBar: AppBar(title: const Text('Expiry')),
      body: RefreshIndicator(
        onRefresh: p.load,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header(p, s)),
            ..._body(p),
          ],
        ),
      ),
    );
  }

  Widget _header(ExpiryProvider p, ExpirySummary? s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            onChanged: p.setQuery,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search medicine or batch number',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SummaryCard(
                label: 'Expired',
                count: s?.expired,
                color: ExpiryStatus.expired.color,
                onTap: () => _selectTab(0),
              ),
              const SizedBox(width: 8),
              SummaryCard(
                label: 'Critical',
                count: s?.critical,
                color: ExpiryStatus.critical.color,
                onTap: () => _selectTab(1),
              ),
              const SizedBox(width: 8),
              SummaryCard(
                label: 'Warning',
                count: s?.warning,
                color: ExpiryStatus.warning.color,
                onTap: () => _selectTab(1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabs,
            onTap: (i) => p.setTab(ExpiryTab.values[i]),
            tabs: [
              Tab(text: s == null ? 'Expired' : 'Expired (${s.expired})'),
              Tab(text: s == null ? 'Expiring soon' : 'Expiring soon (${s.critical + s.warning})'),
              const Tab(text: 'All'),
            ],
          ),
          if (p.tab == ExpiryTab.all) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final st in ExpiryStatus.values)
                  FilterChip(
                    label: Text(st.label),
                    selected: p.allTabFilter.contains(st),
                    onSelected: (_) => p.toggleFilter(st),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _body(ExpiryProvider p) {
    const pad = EdgeInsets.symmetric(horizontal: 16);

    if (p.loading && p.items.isEmpty) {
      return [
        SliverPadding(
          padding: pad,
          sliver: SliverList.builder(itemCount: 5, itemBuilder: (_, __) => const SkeletonCard()),
        ),
      ];
    }

    if (p.error != null && p.items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: MessageState(
            icon: Icons.cloud_off,
            title: 'Could not load batches',
            message: p.error!,
            actionLabel: 'Retry',
            onAction: p.load,
          ),
        ),
      ];
    }

    if (p.items.isEmpty) {
      final searching = p.query.trim().isNotEmpty;
      return [
        SliverToBoxAdapter(
          child: MessageState(
            icon: searching ? Icons.search_off : Icons.check_circle_outline,
            title: searching ? 'No matching batches' : _emptyTitle(p.tab),
            message: searching
                ? 'Try a different medicine name or batch number.'
                : 'Pull down to refresh.',
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: pad,
        sliver: SliverList.builder(
          itemCount: p.items.length + (p.loadingMore ? 1 : 0),
          itemBuilder: (_, i) {
            if (i >= p.items.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final batch = p.items[i];
            return BatchCard(batch: batch, onDispose: () => _openDisposal(batch));
          },
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }

  String _emptyTitle(ExpiryTab tab) => switch (tab) {
        ExpiryTab.expired => 'No expired batches',
        ExpiryTab.expiringSoon => 'Nothing expiring soon',
        ExpiryTab.all => 'No batches in stock',
      };
}
