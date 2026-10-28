import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../data/remote/tickets_api.dart';
import '../features/sync/widgets/common.dart';
import '../features/tickets/ticket_strings.dart';
import 'admin_api.dart';
import 'admin_providers.dart';
import 'admin_ticket_view.dart';

const _wide = 1100.0;
const _medium = 760.0;

/// Support console layout: views sidebar · ticket queue · ticket detail.
/// Wide screens show all three; narrower screens show the queue or the ticket.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, this.selectedId});

  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= _wide;
        final medium = c.maxWidth >= _medium;
        final sidebar = const _Sidebar();
        final queue = _QueuePane(selectedId: selectedId);
        final detail = selectedId == null
            ? const Center(
                child: StateMessage(
                  icon: Icons.inbox_rounded,
                  title: 'Select a ticket',
                  body: 'Pick a ticket from the queue to see the full conversation.',
                ),
              )
            : AdminTicketView(key: ValueKey(selectedId), ticketId: selectedId!, showBack: !wide);

        return Scaffold(
          appBar: _TopBar(compact: !medium),
          drawer: medium ? null : const Drawer(child: _Sidebar()),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (medium) SizedBox(width: 232, child: sidebar),
              if (medium) const VerticalDivider(width: 1),
              if (wide) ...[
                SizedBox(width: 440, child: queue),
                const VerticalDivider(width: 1),
                Expanded(child: detail),
              ] else
                Expanded(child: selectedId == null ? queue : detail),
            ],
          ),
        );
      },
    );
  }
}

class _TopBar extends ConsumerStatefulWidget implements PreferredSizeWidget {
  const _TopBar({required this.compact});

  final bool compact;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  ConsumerState<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends ConsumerState<_TopBar> {
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
      final q = ref.read(queueQueryProvider);
      ref.read(queueQueryProvider.notifier).set(q.copyWith(q: text));
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(adminDisplayNameProvider);
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      toolbarHeight: 64,
      titleSpacing: 16,
      title: Row(
        children: [
          Icon(Icons.support_agent_rounded, color: scheme.primary),
          const SizedBox(width: 10),
          if (!widget.compact) const Text('Support Console'),
          const SizedBox(width: 24),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: TextField(
                controller: _search,
                onChanged: _onSearch,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search ticket number, subject or shop',
                  prefixIcon: Icon(Icons.search_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () {
            ref.invalidate(queueProvider);
            ref.invalidate(statsProvider);
          },
          icon: const Icon(Icons.refresh_rounded),
        ),
        if (!widget.compact)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Chip(avatar: const Icon(Icons.person_rounded, size: 18), label: Text(name)),
          ),
      ],
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  static const _icons = {
    QueueView.needsReply: Icons.mark_chat_unread_rounded,
    QueueView.unassigned: Icons.person_off_rounded,
    QueueView.mine: Icons.assignment_ind_rounded,
    QueueView.open: Icons.inbox_rounded,
    QueueView.waitingUser: Icons.hourglass_top_rounded,
    QueueView.resolved: Icons.task_alt_rounded,
    QueueView.closed: Icons.archive_rounded,
    QueueView.all: Icons.all_inbox_rounded,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(queueQueryProvider);
    final stats = ref.watch(statsProvider).value;
    final t = Theme.of(context).textTheme;
    final c = context.status;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      children: [
        if (stats != null && stats.criticalOpen > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: StatusBanner(
              text: '${stats.criticalOpen} critical ticket${stats.criticalOpen == 1 ? '' : 's'} open',
              tone: BannerTone.error,
              icon: Icons.priority_high_rounded,
            ),
          ),
        for (final v in QueueView.values)
          ListTile(
            dense: true,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
            selected: query.view == v,
            leading: Icon(_icons[v]),
            title: Text(v.label),
            trailing: stats == null
                ? null
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: v == QueueView.needsReply && (stats.counts[v] ?? 0) > 0
                          ? c.warningBg
                          : Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('${stats.counts[v] ?? 0}', style: t.labelMedium),
                  ),
            onTap: () {
              ref.read(queueQueryProvider.notifier).set(query.copyWith(view: v));
              if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) Navigator.of(context).pop();
              context.go('/');
            },
          ),
      ],
    );
  }
}

class _QueuePane extends ConsumerWidget {
  const _QueuePane({this.selectedId});

  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(queueQueryProvider);
    final page = ref.watch(queueProvider(query));
    final set = ref.read(queueQueryProvider.notifier).set;
    final t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(query.view.label, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: _Dropdown<TicketPriority?>(
                  label: 'Priority',
                  value: query.priority,
                  items: {null: 'Any', for (final p in TicketPriority.values) p: TicketStrings.priorityLabel(p)},
                  onChanged: (v) => set(query.copyWith(priority: () => v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Dropdown<TicketCategory?>(
                  label: 'Category',
                  value: query.category,
                  items: {null: 'Any', for (final c in TicketCategory.values) c: TicketStrings.categoryName(c)},
                  onChanged: (v) => set(query.copyWith(category: () => v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Dropdown<QueueSort>(
                  label: 'Sort',
                  value: query.sort,
                  items: {for (final s in QueueSort.values) s: s.label},
                  onChanged: (v) => set(query.copyWith(sort: v)),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: page.when(
            skipLoadingOnRefresh: true,
            loading: () => ListView(
              padding: const EdgeInsets.all(16),
              children: List.generate(6, (_) => const Padding(padding: EdgeInsets.only(bottom: 10), child: SkeletonBox(height: 76))),
            ),
            error: (e, _) => StateMessage(
              icon: Icons.cloud_off_rounded,
              title: 'Couldn\'t load tickets',
              body: '$e',
              actionLabel: 'Retry',
              onAction: () => ref.invalidate(queueProvider(query)),
            ),
            data: (p) => p.rows.isEmpty
                ? StateMessage(
                    icon: Icons.task_alt_rounded,
                    title: 'Nothing here',
                    body: query.q.isNotEmpty || query.priority != null || query.category != null
                        ? 'No tickets match these filters.'
                        : 'No tickets in "${query.view.label}".',
                  )
                : Column(
                    children: [
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: p.rows.length,
                          separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
                          itemBuilder: (_, i) => _QueueRowTile(row: p.rows[i], selected: p.rows[i].id == selectedId),
                        ),
                      ),
                      const Divider(height: 1),
                      _Pager(
                        page: p,
                        onPage: (n) => set(query.copyWith(page: n)),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({required this.label, required this.value, required this.items, required this.onChanged});

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => DropdownMenu<T>(
    initialSelection: value,
    label: Text(label),
    expandedInsets: EdgeInsets.zero,
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
    ),
    dropdownMenuEntries: [for (final e in items.entries) DropdownMenuEntry<T>(value: e.key, label: e.value)],
    onSelected: (v) => onChanged(v as T),
  );
}

class _Pager extends StatelessWidget {
  const _Pager({required this.page, required this.onPage});

  final QueuePage page;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final from = (page.page - 1) * page.pageSize + 1;
    final to = (from + page.rows.length - 1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text('$from–$to of ${page.total}', style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          IconButton(
            tooltip: 'Previous page',
            onPressed: page.page > 1 ? () => onPage(page.page - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed: page.page < page.pages ? () => onPage(page.page + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _QueueRowTile extends StatelessWidget {
  const _QueueRowTile({required this.row, required this.selected});

  final QueueRow row;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final c = context.status;
    return Material(
      color: selected ? scheme.secondaryContainer.withValues(alpha: 0.6) : Colors.transparent,
      child: InkWell(
        onTap: () => context.go('/tickets/${row.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PriorityDot(priority: row.priority),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(row.ticketNumber, style: t.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                        const SizedBox(width: 8),
                        if (row.needsReply)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: c.warningBg, borderRadius: BorderRadius.circular(999)),
                            child: Text('Needs reply', style: t.labelSmall?.copyWith(color: c.warningFg)),
                          ),
                        const Spacer(),
                        Text(ago(row.lastActivityAt), style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      row.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${row.shop.name ?? 'Unknown shop'} · ${row.requesterName ?? 'Shop user'} · ${TicketStrings.categoryName(row.category)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        StatusChip(status: row.status),
                        const SizedBox(width: 8),
                        Icon(Icons.person_outline_rounded, size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 2),
                        Text(row.assignee?.name ?? 'Unassigned', style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "5m", "3h", "2d", or a date.
String ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return DateFormat('d MMM').format(t);
}

class PriorityDot extends StatelessWidget {
  const PriorityDot({super.key, required this.priority});

  final TicketPriority priority;

  @override
  Widget build(BuildContext context) {
    final c = context.status;
    final color = switch (priority) {
      TicketPriority.critical => c.errorFg,
      TicketPriority.high => c.warningFg,
      TicketPriority.normal => c.syncingFg,
      TicketPriority.low => c.offlineFg.withValues(alpha: 0.5),
    };
    return Tooltip(
      message: TicketStrings.priorityLabel(priority),
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final TicketStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.status;
    final (bg, fg) = switch (status) {
      TicketStatus.open => (c.syncingBg, c.syncingFg),
      TicketStatus.inProgress => (c.syncingBg, c.syncingFg),
      TicketStatus.waitingForUser => (c.warningBg, c.warningFg),
      TicketStatus.resolved => (c.onlineBg, c.onlineFg),
      TicketStatus.closed => (c.offlineBg, c.offlineFg),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        adminStatusLabel(status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Staff-facing status names ("Waiting for shop" instead of the shop's "Waiting for you").
String adminStatusLabel(TicketStatus s) => switch (s) {
  TicketStatus.open => 'Open',
  TicketStatus.inProgress => 'In progress',
  TicketStatus.waitingForUser => 'Waiting for shop',
  TicketStatus.resolved => 'Resolved',
  TicketStatus.closed => 'Closed',
};
