import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../data/remote/tickets_api.dart';
import '../../../l10n/translations.dart';
import '../../sync/sync_strings.dart';
import '../../sync/widgets/common.dart';
import '../ticket_strings.dart';
import '../tickets_providers.dart';

/// Screen 7 — Support Ticket List (frames G1–G4).
class TicketsListScreen extends ConsumerStatefulWidget {
  const TicketsListScreen({super.key});

  @override
  ConsumerState<TicketsListScreen> createState() => _TicketsListScreenState();
}

class _TicketsListScreenState extends ConsumerState<TicketsListScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = ref.read(ticketQueryProvider);
      ref.read(ticketQueryProvider.notifier).set(q.copyWith(q: text));
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(ticketQueryProvider);
    final list = ref.watch(ticketListProvider(query));

    return Scaffold(
      appBar: AppBar(
        title: Text(TicketStrings.supportTickets),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/support/new'),
            icon: const Icon(Icons.add_rounded),
            label: Text(TicketStrings.newTicketAction),
          ),
          PopupMenuButton<String>(
            onSelected: (_) => context.push('/tour?restart=1'),
            itemBuilder: (_) => [PopupMenuItem(value: 'tour', child: Text(tr('tour.menu')))],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: TicketStrings.searchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: TicketStrings.clearSearch,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          _onSearch('');
                        },
                      ),
              ),
            ),
          ),
          _Filters(query: query),
          Expanded(
            child: list.when(
              skipLoadingOnRefresh: true,
              loading: () => ListView(
                padding: const EdgeInsets.all(16),
                children: List.generate(
                  4,
                  (_) => const Padding(padding: EdgeInsets.only(bottom: 12), child: SkeletonBox(height: 84)),
                ),
              ),
              error: (_, _) => StateMessage(
                icon: Icons.cloud_off_rounded,
                title: TicketStrings.loadError,
                body: TicketStrings.loadErrorBody,
                actionLabel: SyncStrings.retry,
                onAction: () => ref.invalidate(ticketListProvider(query)),
              ),
              data: (state) {
                if (state.tickets.isEmpty && !query.isFiltered) {
                  return StateMessage(
                    icon: Icons.support_agent_rounded,
                    title: TicketStrings.emptyTitle,
                    body: TicketStrings.emptyBody,
                    actionLabel: TicketStrings.createTicket,
                    onAction: () => context.push('/support/new'),
                  );
                }
                if (state.tickets.isEmpty) {
                  return StateMessage(
                    icon: Icons.filter_alt_off_rounded,
                    title: TicketStrings.noMatchTitle,
                    body: TicketStrings.noMatchBody,
                    actionLabel: TicketStrings.clearFilters,
                    onAction: () {
                      _search.clear();
                      ref.read(ticketQueryProvider.notifier).clear();
                    },
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(ticketListProvider(query).future),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: state.tickets.length + (state.nextCursor != null ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      if (i == state.tickets.length) {
                        return Center(
                          child: OutlinedButton(
                            onPressed: state.loadingMore
                                ? null
                                : () => ref.read(ticketListProvider(query).notifier).loadMore().catchError((_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(TicketStrings.loadError)),
                                      );
                                    }
                                  }),
                            child: Text(state.loadingMore ? TicketStrings.loading : TicketStrings.loadMore),
                          ),
                        );
                      }
                      return TicketCard(ticket: state.tickets[i]);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({required this.query});

  final TicketQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final set = ref.read(ticketQueryProvider.notifier).set;
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _FilterChip<TicketStatus>(
            label: TicketStrings.status,
            value: query.status,
            options: TicketStatus.values,
            optionLabel: TicketStrings.statusLabel,
            onChanged: (v) => set(query.copyWith(status: () => v)),
          ),
          const SizedBox(width: 8),
          _FilterChip<TicketCategory>(
            label: TicketStrings.category,
            value: query.category,
            options: TicketCategory.values,
            optionLabel: TicketStrings.categoryName,
            onChanged: (v) => set(query.copyWith(category: () => v)),
          ),
          const SizedBox(width: 8),
          _FilterChip<TicketPriority>(
            label: TicketStrings.priority,
            value: query.priority,
            options: TicketPriority.values,
            optionLabel: TicketStrings.priorityLabel,
            onChanged: (v) => set(query.copyWith(priority: () => v)),
          ),
        ],
      ),
    );
  }
}

class _FilterChip<T> extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.value,
    required this.options,
    required this.optionLabel,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<T> options;
  final String Function(T) optionLabel;
  final ValueChanged<T?> onChanged;

  Future<void> _pick(BuildContext context) async {
    final picked = await showModalBottomSheet<(T?,)>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(label, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            RadioGroup<T?>(
              groupValue: value,
              onChanged: (v) => Navigator.pop(ctx, (v,)),
              child: Column(
                children: [
                  RadioListTile<T?>(value: null, title: Text(TicketStrings.any)),
                  for (final o in options) RadioListTile<T?>(value: o, title: Text(optionLabel(o))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) onChanged(picked.$1);
  }

  @override
  Widget build(BuildContext context) => FilterChip(
        label: Text(value == null ? label : TicketStrings.filterValue(label, optionLabel(value as T))),
        selected: value != null,
        showCheckmark: false,
        avatar: const Icon(Icons.arrow_drop_down_rounded, size: 18),
        onSelected: (_) => _pick(context),
      );
}

class TicketCard extends StatelessWidget {
  const TicketCard({super.key, required this.ticket});

  final TicketSummary ticket;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final c = context.status;
    final now = DateTime.now();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/support/tickets/${ticket.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${ticket.ticketNumber} · ${TicketStrings.categoryName(ticket.category)}',
                      style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (ticket.needsReply)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: c.warningBg, borderRadius: BorderRadius.circular(999)),
                      child: Text(TicketStrings.replyNeeded, style: t.labelSmall?.copyWith(color: c.warningFg)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(ticket.subject, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyLarge),
              const SizedBox(height: 4),
              Text(
                TicketStrings.listMeta(ticket, now),
                style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
