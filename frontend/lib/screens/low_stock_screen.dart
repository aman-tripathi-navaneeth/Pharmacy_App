import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../data/low_stock_repository.dart';
import '../models/expiry.dart' show formatQty;
import '../models/low_stock.dart';
import '../providers/low_stock_provider.dart';
import '../widgets/message_state.dart';
import '../widgets/summary_card.dart';

extension LowStockStatusStyle on LowStockStatus {
  Color get color => switch (this) {
        LowStockStatus.outOfStock => const Color(0xFFC62828),
        LowStockStatus.low => const Color(0xFFEF6C00),
      };
}

class LowStockScreen extends StatelessWidget {
  const LowStockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => LowStockProvider(ctx.read<LowStockRepository>())..load(),
      child: const _LowStockView(),
    );
  }
}

class _LowStockView extends StatefulWidget {
  const _LowStockView();

  @override
  State<_LowStockView> createState() => _LowStockViewState();
}

class _LowStockViewState extends State<_LowStockView> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
        context.read<LowStockProvider>().loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _editLevel(LowStockItem item) async {
    final level = await showDialog<double>(
      context: context,
      builder: (_) => _ReorderLevelDialog(item: item),
    );
    if (level == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<LowStockProvider>().setReorderLevel(item.productId, level);
      messenger.showSnackBar(SnackBar(
        content: Text(level == 0
            ? '${item.productName} is no longer tracked'
            : 'Reorder level updated to ${formatQty(level)} ${item.baseUnit}'),
      ));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LowStockProvider>();
    final s = p.summary;

    return Scaffold(
      appBar: AppBar(title: const Text('Low stock')),
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

  Widget _header(LowStockProvider p, LowStockSummary? s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            onChanged: p.setQuery,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search medicine',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SummaryCard(
                label: 'Out of stock',
                count: s?.outOfStock,
                color: LowStockStatus.outOfStock.color,
                onTap: () => p.setFilter(LowStockFilter.outOfStock),
              ),
              const SizedBox(width: 8),
              SummaryCard(
                label: 'Low',
                count: s?.low,
                color: LowStockStatus.low.color,
                onTap: () => p.setFilter(LowStockFilter.low),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: p.filter == LowStockFilter.all,
                onSelected: (_) => p.setFilter(LowStockFilter.all),
              ),
              ChoiceChip(
                label: const Text('Out of stock'),
                selected: p.filter == LowStockFilter.outOfStock,
                onSelected: (_) => p.setFilter(LowStockFilter.outOfStock),
              ),
              ChoiceChip(
                label: const Text('Low'),
                selected: p.filter == LowStockFilter.low,
                onSelected: (_) => p.setFilter(LowStockFilter.low),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _body(LowStockProvider p) {
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
            title: 'Could not load low stock',
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
            title: searching ? 'No matching medicines' : 'Nothing is running low',
            message: searching
                ? 'Try a different medicine name.'
                : 'Only medicines with a reorder level are tracked. Pull down to refresh.',
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
            final item = p.items[i];
            return _LowStockCard(
              item: item,
              onEdit: AppConfig.canApprove ? () => _editLevel(item) : null,
            );
          },
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }
}

class _LowStockCard extends StatelessWidget {
  const _LowStockCard({required this.item, this.onEdit});
  final LowStockItem item;
  final VoidCallback? onEdit;

  String _qty(double v, String? pack) =>
      '${formatQty(v)} ${item.baseUnit}${pack == null ? '' : ' ($pack)'}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = item.status.color;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.productName,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    item.status.label,
                    style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('On hand: ${_qty(item.onHandBase, item.onHandPack)}',
                style: theme.textTheme.bodyMedium),
            Text('Reorder level: ${_qty(item.reorderLevelBase, item.reorderLevelPack)}',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Short by ${formatQty(item.shortfallBase)} ${item.baseUnit}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: c, fontWeight: FontWeight.w600),
                  ),
                ),
                if (onEdit != null)
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('Reorder level'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReorderLevelDialog extends StatefulWidget {
  const _ReorderLevelDialog({required this.item});
  final LowStockItem item;

  @override
  State<_ReorderLevelDialog> createState() => _ReorderLevelDialogState();
}

class _ReorderLevelDialogState extends State<_ReorderLevelDialog> {
  late final _ctrl = TextEditingController(text: formatQty(widget.item.reorderLevelBase));
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final n = double.tryParse(_ctrl.text.trim());
    if (n == null || n < 0) {
      setState(() => _error = 'Enter 0 or a positive number');
      return;
    }
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item.productName),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Reorder level',
          suffixText: widget.item.baseUnit,
          helperText: 'Enter 0 to stop tracking this medicine',
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
