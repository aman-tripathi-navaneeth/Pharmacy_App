import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../data/remote/api_client.dart';
import '../data/remote/tickets_api.dart';
import '../features/sync/widgets/common.dart';
import '../features/tickets/ticket_strings.dart';
import '../features/tickets/tickets_providers.dart' show attachmentPickerProvider;
import 'admin_api.dart';
import 'admin_providers.dart';
import 'admin_shell.dart' show PriorityDot, StatusChip, adminStatusLabel;
import 'save_file.dart';

final _when = DateFormat('d MMM, HH:mm');

/// Full ticket for support staff: conversation, internal notes, properties,
/// shop, related operation and every action needed to resolve it.
class AdminTicketView extends ConsumerWidget {
  const AdminTicketView({super.key, required this.ticketId, this.showBack = false});

  final String ticketId;
  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminTicketProvider(ticketId));
    return async.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => StateMessage(
        icon: Icons.error_outline_rounded,
        title: e is ApiHttpException && e.statusCode == 404 ? 'Ticket not found' : 'Couldn\'t load this ticket',
        body: e is ApiException ? e.message : '$e',
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(adminTicketProvider(ticketId)),
      ),
      data: (t) => LayoutBuilder(builder: (context, c) {
        final twoColumn = c.maxWidth >= 780;
        final side = _SidePanel(ticket: t);
        final main = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _Timeline(ticket: t, extra: twoColumn ? null : side)),
            if (!t.isClosed) _Composer(ticket: t) else const _ClosedNote(),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(ticket: t, showBack: showBack),
            const Divider(height: 1),
            Expanded(
              child: twoColumn
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: main),
                        const VerticalDivider(width: 1),
                        SizedBox(width: 300, child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: side)),
                      ],
                    )
                  : main,
            ),
          ],
        );
      }),
    );
  }
}

/// Floats bottom-left so it never covers the composer's Send button.
void _snack(BuildContext context, String text) {
  final width = MediaQuery.sizeOf(context).width;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(16, 0, width > 600 ? width - 376 : 16, 16),
    ));
}

/// Runs an action and reports API errors; a concurrent change reloads the ticket.
Future<bool> _run(BuildContext context, WidgetRef ref, String ticketId, Future<void> Function() action, {String? done}) async {
  try {
    await action();
    if (done != null && context.mounted) _snack(context, done);
    return true;
  } on ApiException catch (e) {
    if (e is ApiHttpException && e.code == 'TICKET_CHANGED') ref.invalidate(adminTicketProvider(ticketId));
    if (context.mounted) _snack(context, e.message);
    return false;
  }
}

// ───────────────────────────────────────────────────────────────────── header

class _Header extends ConsumerWidget {
  const _Header({required this.ticket, required this.showBack});

  final AdminTicket ticket;
  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ctl = ref.read(adminTicketProvider(ticket.id).notifier);

    final actions = <Widget>[
      if (ticket.status == TicketStatus.open || ticket.status == TicketStatus.inProgress)
        OutlinedButton.icon(
          icon: const Icon(Icons.help_outline_rounded),
          label: const Text('Ask shop for info'),
          onPressed: () => _run(context, ref, ticket.id, () => ctl.setStatus(TicketStatus.waitingForUser), done: 'Waiting for the shop to reply'),
        ),
      if (ticket.status == TicketStatus.waitingForUser)
        OutlinedButton.icon(
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Mark in progress'),
          onPressed: () => _run(context, ref, ticket.id, () => ctl.setStatus(TicketStatus.inProgress)),
        ),
      if (ticket.status != TicketStatus.resolved && !ticket.isClosed)
        FilledButton.icon(
          icon: const Icon(Icons.task_alt_rounded),
          label: const Text('Resolve'),
          onPressed: () => _resolve(context, ref),
        ),
      if (ticket.status == TicketStatus.resolved)
        OutlinedButton.icon(
          icon: const Icon(Icons.undo_rounded),
          label: const Text('Reopen'),
          onPressed: () => _run(context, ref, ticket.id, () => ctl.setStatus(TicketStatus.inProgress), done: 'Ticket reopened'),
        ),
      if (!ticket.isClosed)
        TextButton.icon(
          icon: const Icon(Icons.archive_outlined),
          label: const Text('Close'),
          onPressed: () => _close(context, ref),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showBack)
                IconButton(tooltip: 'Back to queue', onPressed: () => context.go('/'), icon: const Icon(Icons.arrow_back_rounded)),
              PriorityDot(priority: ticket.priority),
              const SizedBox(width: 8),
              SelectableText(ticket.ticketNumber, style: t.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              StatusChip(status: ticket.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(ticket.subject, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            '${ticket.shopName ?? 'Unknown shop'} · ${ticket.requesterName ?? 'Shop user'} · '
            '${TicketStrings.categoryName(ticket.category)} · opened ${_when.format(ticket.createdAt)}',
            style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }

  Future<void> _resolve(BuildContext context, WidgetRef ref) async {
    final note = await showDialog<String>(context: context, builder: (_) => _ResolveDialog(ticket: ticket));
    if (note == null || !context.mounted) return;
    await _run(
      context,
      ref,
      ticket.id,
      () => ref.read(adminTicketProvider(ticket.id).notifier).setStatus(TicketStatus.resolved, note: note),
      done: '${ticket.ticketNumber} resolved. The shop has been shown your summary.',
    );
  }

  Future<void> _close(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Close ${ticket.ticketNumber}?'),
        content: const Text('Closing is final. The shop can no longer reply and will need a new ticket for further help.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Close ticket')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, ref, ticket.id, () => ref.read(adminTicketProvider(ticket.id).notifier).setStatus(TicketStatus.closed), done: 'Ticket closed');
  }
}

class _ResolveDialog extends StatefulWidget {
  const _ResolveDialog({required this.ticket});

  final AdminTicket ticket;

  @override
  State<_ResolveDialog> createState() => _ResolveDialogState();
}

class _ResolveDialogState extends State<_ResolveDialog> {
  final _note = TextEditingController();
  bool _tried = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String? get _error => _note.text.trim().length < 5 ? 'Write a resolution summary (at least 5 characters).' : null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Resolve ${widget.ticket.ticketNumber}'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Explain what was wrong and what was done. The shop sees this summary on the ticket.'),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'e.g. Fixed the GST rounding; invoices now match the till.',
                border: const OutlineInputBorder(),
                errorText: _tried ? _error : null,
              ),
            ),
            Text(
              'If the shop replies within 14 days, the ticket reopens automatically.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            setState(() => _tried = true);
            if (_error == null) Navigator.pop(context, _note.text.trim());
          },
          child: const Text('Resolve ticket'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────── timeline

class _Timeline extends ConsumerWidget {
  const _Timeline({required this.ticket, this.extra});

  final AdminTicket ticket;

  /// On narrow layouts the side panel is shown above the conversation.
  final Widget? extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agents = {for (final a in ref.watch(agentsProvider).value ?? const <NamedRef>[]) a.id: a.name ?? 'Support'};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (extra != null) ...[extra!, const SizedBox(height: 16)],
        for (final e in ticket.events) _EventItem(event: e, ticket: ticket, agents: agents),
      ],
    );
  }
}

class _EventItem extends ConsumerWidget {
  const _EventItem({required this.event, required this.ticket, required this.agents});

  final AdminEvent event;
  final AdminTicket ticket;
  final Map<String, String> agents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final c = context.status;
    final who = event.authorName ?? (event.bySupport ? 'Support' : 'Shop user');
    final time = _when.format(event.createdAt);

    Widget line(IconData icon, String text, {String? detail}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$text · $time', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    if (detail != null && detail.isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 2), child: Text(detail, style: t.bodyMedium)),
                  ],
                ),
              ),
            ],
          ),
        );

    switch (event.type) {
      case 'STATUS_CHANGE':
        return line(
          Icons.sync_alt_rounded,
          '$who changed status ${event.fromStatus == null ? '' : '${adminStatusLabel(event.fromStatus!)} → '}${adminStatusLabel(event.toStatus!)}',
          detail: event.body,
        );
      case 'ASSIGNMENT':
        final to = event.meta?['to'] as String?;
        return line(Icons.assignment_ind_outlined, to == null ? '$who unassigned the ticket' : '$who assigned it to ${agents[to] ?? 'an agent'}');
      case 'PRIORITY_CHANGE':
        final from = TicketPriority.parse(event.meta?['from'] as String? ?? 'NORMAL');
        final to = TicketPriority.parse(event.meta?['to'] as String? ?? 'NORMAL');
        return line(Icons.flag_outlined, '$who changed priority ${TicketStrings.priorityLabel(from)} → ${TicketStrings.priorityLabel(to)}');
    }

    final note = event.type == 'NOTE';
    final fromShop = !event.bySupport;
    final body = event.type == 'CREATED' ? ticket.description : (event.body ?? '');
    final (bg, border) = note
        ? (c.warningBg, c.warningFg.withValues(alpha: 0.4))
        : fromShop
            ? (scheme.surfaceContainerHigh, Colors.transparent)
            : (scheme.primaryContainer, Colors.transparent);
    final files = ticket.attachments.where((a) => event.attachmentIds.contains(a.id)).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: fromShop ? Alignment.centerLeft : Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (note) ...[Icon(Icons.lock_outline_rounded, size: 14, color: c.warningFg), const SizedBox(width: 4)],
                    Flexible(
                      child: Text(
                        '${note ? 'Internal note · ' : event.type == 'CREATED' ? 'Opened by ' : ''}$who · $time',
                        style: t.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: note ? c.warningFg : null),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SelectableText(body, style: t.bodyMedium),
                if (files.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final f in files) _AttachmentChip(ticketId: ticket.id, file: f)]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentChip extends ConsumerWidget {
  const _AttachmentChip({required this.ticketId, required this.file});

  final String ticketId;
  final TicketAttachment file;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ActionChip(
        avatar: const Icon(Icons.download_rounded, size: 16),
        label: Text('${file.fileName} · ${TicketStrings.fileSize(file.size)}'),
        onPressed: () async {
          try {
            final bytes = await ref.read(adminApiProvider).download(ticketId, file.id);
            final saved = await saveFile(bytes, file.fileName, file.contentType);
            if (!saved && context.mounted) _snack(context, 'Downloads are available in the web console.');
          } on ApiException catch (e) {
            if (context.mounted) _snack(context, e.message);
          }
        },
      );
}

class _ClosedNote extends StatelessWidget {
  const _ClosedNote();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        color: context.status.offlineBg,
        child: Text('This ticket is closed. The conversation is kept for the audit trail.',
            style: TextStyle(color: context.status.offlineFg)),
      );
}

// ─────────────────────────────────────────────────────────────────── composer

class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.ticket});

  final AdminTicket ticket;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _text = TextEditingController();
  bool _internal = false;
  bool _sending = false;
  String _requestId = AdminTicketController.newRequestId();
  final _files = <TicketAttachment>[];
  bool _uploading = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    final picked = await ref.read(attachmentPickerProvider).pick();
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final f = await ref.read(adminTicketProvider(widget.ticket.id).notifier).upload(picked.bytes, picked.name);
      setState(() => _files.add(f));
    } on ApiException catch (e) {
      if (mounted) _snack(context, e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    final ok = await _run(
      context,
      ref,
      widget.ticket.id,
      () => ref.read(adminTicketProvider(widget.ticket.id).notifier).reply(
            body,
            requestId: _requestId,
            internal: _internal,
            attachmentIds: [for (final f in _files) f.id],
          ),
      // No snackbar: the message appears in the timeline, and a snackbar would cover the composer.
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) {
        _text.clear();
        _files.clear();
        _requestId = AdminTicketController.newRequestId(); // keep the id on failure so a retry can't double-post
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = context.status;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter, meta: true): _send, const SingleActivator(LogicalKeyboardKey.enter, control: true): _send},
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: _internal ? c.warningBg.withValues(alpha: 0.5) : scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, icon: Icon(Icons.reply_rounded), label: Text('Reply to shop')),
                    ButtonSegment(value: true, icon: Icon(Icons.lock_outline_rounded), label: Text('Internal note')),
                  ],
                  selected: {_internal},
                  onSelectionChanged: (s) => setState(() => _internal = s.first),
                ),
                if (_internal)
                  Text('Only support staff can see notes', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.warningFg)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _text,
              minLines: 2,
              maxLines: 8,
              maxLength: 5000,
              enabled: !_sending,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _internal ? 'Add a note for the support team…' : 'Write a reply to the shop…',
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: 'Attach file (PDF, JPG, PNG · max 10 MB)',
                  onPressed: _uploading || _files.length >= 3 ? null : _attach,
                  icon: _uploading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.attach_file_rounded),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final f in _files)
                        InputChip(label: Text(f.fileName), onDeleted: () => setState(() => _files.remove(f))),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _sending || _text.text.trim().isEmpty ? null : _send,
                  icon: Icon(_internal ? Icons.note_add_outlined : Icons.send_rounded),
                  label: Text(_sending ? 'Sending…' : _internal ? 'Add note' : 'Send reply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────── side panel

class _SidePanel extends ConsumerWidget {
  const _SidePanel({required this.ticket});

  final AdminTicket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PropertiesCard(ticket: ticket),
        const SizedBox(height: 12),
        _Card(
          title: 'Shop & requester',
          children: [
            _kv(context, 'Shop', ticket.shopName ?? '—'),
            _kv(context, 'Shop status', ticket.shopStatus ?? '—'),
            _kv(context, 'Requester', ticket.requesterName ?? '—'),
            _kv(context, 'Role', ticket.requesterRole ?? '—'),
            _kv(context, 'Opened', _when.format(ticket.createdAt)),
            if (ticket.resolvedAt != null) _kv(context, 'Resolved', _when.format(ticket.resolvedAt!)),
          ],
        ),
        if (ticket.relatedOperation != null) ...[
          const SizedBox(height: 12),
          _OperationCard(op: ticket.relatedOperation!),
        ],
        if (ticket.attachments.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Card(
            title: 'Attachments',
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final a in ticket.attachments) _AttachmentChip(ticketId: ticket.id, file: a)],
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PropertiesCard extends ConsumerWidget {
  const _PropertiesCard({required this.ticket});

  final AdminTicket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agents = ref.watch(agentsProvider).value ?? const <NamedRef>[];
    final me = ref.watch(adminDisplayNameProvider);
    final ctl = ref.read(adminTicketProvider(ticket.id).notifier);
    final myId = agents.where((a) => a.name == me).map((a) => a.id).firstOrNull;
    const border = OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)));

    return _Card(
      title: 'Properties',
      children: [
        _kv(context, 'Status', adminStatusLabel(ticket.status)),
        _kv(context, 'Category', TicketStrings.categoryName(ticket.category)),
        const SizedBox(height: 8),
        DropdownButtonFormField<TicketPriority>(
          // Keyed so a server-side change (or reload) replaces the field's one-shot initial value.
          key: ValueKey('priority-${ticket.priority.wire}'),
          initialValue: ticket.priority,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Priority', border: border, isDense: true),
          items: [for (final p in TicketPriority.values) DropdownMenuItem(value: p, child: Text(TicketStrings.priorityLabel(p)))],
          onChanged: ticket.isClosed
              ? null
              : (p) => p == null ? null : _run(context, ref, ticket.id, () => ctl.setPriority(p), done: 'Priority updated'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          // Agents load after the ticket; rebuild once they arrive so the current assignee shows.
          key: ValueKey('assignee-${ticket.assignee?.id}-${agents.length}'),
          initialValue: ticket.assignee?.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Assignee', border: border, isDense: true),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Unassigned')),
            for (final a in [
              ...agents,
              // An assignee who has since lost the support role still shows.
              if (ticket.assignee != null && !agents.any((a) => a.id == ticket.assignee!.id)) ticket.assignee!,
            ])
              DropdownMenuItem<String?>(value: a.id, child: Text(a.name ?? a.id, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (id) => _run(context, ref, ticket.id, () => ctl.assign(id), done: id == null ? 'Unassigned' : 'Assigned'),
        ),
        if (myId != null && ticket.assignee?.id != myId)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _run(context, ref, ticket.id, () => ctl.assign(myId), done: 'Assigned to you'),
              child: const Text('Assign to me'),
            ),
          ),
      ],
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.op});

  final RelatedOperation op;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final failed = op.status == 'FAILED' || op.status == 'CONFLICT';
    return _Card(
      title: 'Related operation',
      children: [
        _kv(context, 'Operation ID', op.clientOperationId, mono: true),
        _kv(context, 'Type', [op.module, op.operationType].whereType<String>().join(' · ')),
        if (!op.receivedByServer)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: StatusBanner(text: 'The server never received this operation. It is still on the shop\'s device.', tone: BannerTone.warning),
          )
        else ...[
          _kv(context, 'Server status', op.status ?? '—'),
          _kv(context, 'Attempts', '${op.attemptCount ?? 0}'),
          _kv(context, 'Device', op.deviceId ?? '—', mono: true),
          if (op.serverResourceId != null) _kv(context, 'Server record', op.serverResourceId!, mono: true),
          if (op.lastErrorCode != null) ...[
            const SizedBox(height: 8),
            StatusBanner(text: '${op.lastErrorCode}: ${op.lastErrorMessage ?? ''}', tone: failed ? BannerTone.error : BannerTone.warning),
          ],
          if (op.attempts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Attempt history', style: t.labelLarge),
            const SizedBox(height: 4),
            for (final a in op.attempts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${_when.format(a.timestamp)} · ${a.action} · ${a.result}${a.errorCode == null ? '' : ' (${a.errorCode})'}'
                  '${a.durationMs == null ? '' : ' · ${a.durationMs} ms'}',
                  style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );
}

Widget _kv(BuildContext context, String k, String v, {bool mono = false}) {
  final t = Theme.of(context).textTheme;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 104, child: Text(k, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
        Expanded(child: SelectableText(v, style: mono ? t.bodySmall?.copyWith(fontFamily: 'monospace') : t.bodyMedium)),
      ],
    ),
  );
}
