import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme.dart';
import '../../../data/remote/api_client.dart';
import '../../../data/remote/tickets_api.dart';
import '../../sync/sync_providers.dart';
import '../../sync/sync_strings.dart';
import '../../sync/widgets/common.dart';
import '../../sync/widgets/op_presentation.dart';
import '../ticket_strings.dart';
import '../tickets_providers.dart';
import 'create_ticket_screen.dart' show shortOperationId;

/// Screen 9 — View Ticket & History (frames I1 detail, I2 waiting for user / resolved).
class TicketDetailScreen extends ConsumerWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ticketDetailProvider(ticketId));
    final ticket = async.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(ticket?.ticketNumber ?? TicketStrings.fallbackTitle),
        actions: [
          if (ticket != null && ticket.canClose)
            PopupMenuButton<String>(
              onSelected: (_) => _close(context, ref),
              itemBuilder: (_) => [PopupMenuItem(value: 'close', child: Text(TicketStrings.closeTicket))],
            ),
        ],
      ),
      body: async.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => StateMessage(
          icon: Icons.error_outline_rounded,
          title: e is ApiHttpException && e.statusCode == 404 ? TicketStrings.notFound : TicketStrings.detailLoadError,
          body: e is ApiHttpException && e.statusCode == 404
              ? TicketStrings.notFoundBody
              : TicketStrings.detailLoadErrorBody,
          actionLabel: SyncStrings.retry,
          onAction: () => ref.invalidate(ticketDetailProvider(ticketId)),
        ),
        data: (t) => Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.refresh(ticketDetailProvider(ticketId).future),
                child: _Timeline(ticket: t),
              ),
            ),
            _Composer(ticket: t),
          ],
        ),
      ),
    );
  }

  Future<void> _close(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TicketStrings.closeTitle),
        content: Text(TicketStrings.closeBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(SyncStrings.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(TicketStrings.closeTicket)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(ticketDetailProvider(ticketId).notifier).close();
      ref.invalidate(ticketListProvider);
    } on ApiException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _Timeline extends ConsumerWidget {
  const _Timeline({required this.ticket});

  final TicketDetail ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    // Newest first (I1). The CREATED entry shows the original description.
    final entries = ticket.events.reversed.toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        if (ticket.status == TicketStatus.waitingForUser) ...[
          StatusBanner(text: TicketStrings.waitingBanner, tone: BannerTone.warning, icon: Icons.reply_rounded),
          const SizedBox(height: 12),
        ],
        Text(ticket.subject, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          TicketStrings.detailMeta(ticket, DateTime.now()),
          style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        _Steps(current: ticket.status),
        if (ticket.relatedOperationId != null) ...[
          const SizedBox(height: 12),
          _RelatedOperationLink(operationId: ticket.relatedOperationId!, module: ticket.relatedModule),
        ],
        if (ticket.attachments.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in ticket.attachments)
                Chip(
                  avatar: const Icon(Icons.attach_file_rounded, size: 16),
                  label: Text('${a.fileName} · ${TicketStrings.fileSize(a.size)}'),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        for (final e in entries) _EventTile(event: e, description: ticket.description),
      ],
    );
  }
}

/// OPEN · IN_PROGRESS · WAITING · RESOLVED · CLOSED with the current step highlighted (I1).
class _Steps extends StatelessWidget {
  const _Steps({required this.current});

  final TicketStatus current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Semantics(
      label: TicketStrings.statusA11y(current),
      excludeSemantics: true,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final s in TicketStatus.values)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: s == current ? scheme.primary : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                TicketStrings.stepLabel(s),
                style: t.labelSmall?.copyWith(
                  color: s == current ? scheme.onPrimary : scheme.onSurfaceVariant,
                  fontWeight: s == current ? FontWeight.w700 : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RelatedOperationLink extends ConsumerWidget {
  const _RelatedOperationLink({required this.operationId, this.module});

  final String operationId;
  final String? module;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final op = ref.watch(operationOnceProvider(operationId)).value;
    final catalog = ref.watch(offlineCatalogProvider);
    final text = [
      if (op != null) op.title(catalog) else if (module != null) catalog.moduleLabel(module!),
      shortOperationId(operationId),
    ].join(' · ');
    return Material(
      color: context.status.offlineBg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: op == null ? null : () => context.push('/sync/operations/$operationId'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.link_rounded, size: 18, color: context.status.offlineFg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(TicketStrings.related(text), style: TextStyle(color: context.status.offlineFg)),
              ),
              if (op != null) Icon(Icons.chevron_right_rounded, color: context.status.offlineFg),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.description});

  final TicketEvent event;
  final String description;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final time = SyncStrings.time(event.createdAt);

    if (event.type == TicketEventType.statusChange) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.sync_alt_rounded, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${event.toStatus == null ? '' : TicketStrings.statusChanged(event.toStatus!, event.createdAt)}'
                '${event.body == null ? '' : '\n${event.body}'}',
                style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    final author = event.bySupport
        ? TicketStrings.team
        : event.byViewer
            ? TicketStrings.you
            : TicketStrings.teammate;
    final body = event.type == TicketEventType.created ? description : (event.body ?? '');
    final mine = event.byViewer;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: mine ? scheme.primaryContainer : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$author · $time', style: t.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(body, style: t.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.ticket});

  final TicketDetail ticket;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _text = TextEditingController();
  bool _sending = false;

  /// One id per reply text; reused if the send is retried, so a reply is never posted twice.
  String _requestId = const Uuid().v4();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(ticketDetailProvider(widget.ticket.id).notifier).reply(body, _requestId);
      _text.clear();
      _requestId = const Uuid().v4();
      ref.invalidate(ticketListProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is ApiNetworkException ? TicketStrings.sendFailed : e.message),
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final online = ref.watch(isOnlineProvider).value ?? true;

    if (!widget.ticket.canReply) {
      return SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(TicketStrings.closedNote, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => context.push('/support/new'),
                child: Text(TicketStrings.createTicket),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                minLines: 1,
                maxLines: 5,
                maxLength: 5000,
                enabled: !_sending,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: online ? TicketStrings.replyHint : TicketStrings.connectToReply,
                  border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                  isDense: true,
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: online && !_sending && _text.text.trim().isNotEmpty ? _send : null,
              child: Text(_sending ? '…' : TicketStrings.send),
            ),
          ],
        ),
      ),
    );
  }
}
