import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../data/remote/api_client.dart';
import '../../../data/remote/tickets_api.dart';
import '../../sync/sync_providers.dart';
import '../../sync/widgets/common.dart';
import '../../sync/widgets/op_presentation.dart';
import '../ticket_strings.dart';
import '../tickets_providers.dart';

const _maxBytes = 10 * 1024 * 1024;
const _maxFiles = 3;
const _allowedExt = {'pdf', 'jpg', 'jpeg', 'png'};

class _Attachment {
  _Attachment(this.name, this.size);
  final String name;
  final int size;
  String? id;
  bool failed = false;
  bool get uploading => id == null && !failed;
}

/// Screen 8 — Create Ticket (frames H1 empty, H2 errors, H3 submitting, H4 success, H5 discard).
class CreateTicketScreen extends ConsumerStatefulWidget {
  const CreateTicketScreen({super.key, this.relatedOperationId, this.relatedModule});

  /// Pre-filled when opened from an operation error ("Contact support").
  final String? relatedOperationId;
  final String? relatedModule;

  @override
  ConsumerState<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends ConsumerState<CreateTicketScreen> {
  final _subject = TextEditingController();
  final _description = TextEditingController();
  TicketDraft? _draft;
  TicketCategory? _category;
  TicketPriority _priority = TicketPriority.normal;
  String? _relatedOperationId;
  String? _relatedModule;
  final _files = <_Attachment>[];
  bool _showErrors = false;
  bool _submitting = false;
  TicketDetail? _created;
  Timer? _saveTimer;
  late final TicketDraftStore _drafts;

  @override
  void initState() {
    super.initState();
    _drafts = ref.read(ticketDraftStoreProvider);
    _restore();
  }

  Future<void> _restore() async {
    final saved = await _drafts.load();
    final draft = saved ?? TicketDraft.fresh(relatedOperationId: widget.relatedOperationId, relatedModule: widget.relatedModule);
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _subject.text = draft.subject;
      _description.text = draft.description;
      _category = draft.category ?? (widget.relatedOperationId != null ? TicketCategory.sync : null);
      _priority = draft.priority;
      _relatedOperationId = widget.relatedOperationId ?? draft.relatedOperationId;
      _relatedModule = widget.relatedModule ?? draft.relatedModule;
    });
  }

  @override
  void dispose() {
    // Leaving within the debounce window must not lose the last keystrokes.
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      if (_draft != null && _created == null) _drafts.save(_current());
    }
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  TicketDraft _current() => TicketDraft(
        clientRequestId: _draft!.clientRequestId,
        subject: _subject.text,
        description: _description.text,
        category: _category,
        priority: _priority,
        relatedOperationId: _relatedOperationId,
        relatedModule: _relatedModule,
      );

  void _changed() {
    setState(() {});
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      if (_draft != null && _created == null) _drafts.save(_current());
    });
  }

  bool get _dirty => _subject.text.trim().isNotEmpty || _description.text.trim().isNotEmpty || _files.isNotEmpty;

  String? get _subjectError {
    final s = _subject.text.trim();
    if (s.length < 3) return TicketStrings.subjectError;
    if (s.length > 120) return TicketStrings.subjectTooLong;
    return null;
  }

  String? get _descriptionError {
    final d = _description.text.trim();
    if (d.length < 10) return TicketStrings.descriptionError;
    if (d.length > 5000) return TicketStrings.descriptionTooLong;
    return null;
  }

  String? get _categoryError => _category == null ? TicketStrings.categoryError : null;

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _submit() async {
    setState(() => _showErrors = true);
    if (_subjectError != null || _descriptionError != null || _categoryError != null) return;
    if (_files.any((f) => f.uploading)) return _snack(TicketStrings.waitUpload);
    if (!(ref.read(isOnlineProvider).value ?? true)) {
      await _drafts.save(_current());
      return _snack(TicketStrings.offlineSubmit);
    }

    setState(() => _submitting = true);
    try {
      final ticket = await ref.read(ticketsApiProvider).create(
            storeId: ref.read(authSessionProvider).storeId,
            clientRequestId: _draft!.clientRequestId, // same id on every retry → never a duplicate ticket
            subject: _subject.text.trim(),
            description: _description.text.trim(),
            category: _category!,
            priority: _priority,
            relatedOperationId: _relatedOperationId,
            relatedModule: _relatedModule,
            attachmentIds: [for (final f in _files) ?f.id],
          );
      _saveTimer?.cancel();
      await _drafts.clear();
      ref.invalidate(ticketListProvider);
      if (mounted) setState(() => _created = ticket);
    } on ApiException catch (e) {
      await _drafts.save(_current());
      _snack(e is ApiNetworkException ? TicketStrings.unreachable : e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _addFile() async {
    if (_files.length >= _maxFiles) return _snack(TicketStrings.tooManyFiles);
    final picked = await ref.read(attachmentPickerProvider).pick();
    if (picked == null) return;
    final ext = picked.name.split('.').last.toLowerCase();
    if (!_allowedExt.contains(ext)) return _snack(TicketStrings.fileTypeNotAllowed);
    if (picked.size > _maxBytes) return _snack(TicketStrings.fileTooLarge);

    final a = _Attachment(picked.name, picked.size);
    setState(() => _files.add(a));
    try {
      final uploaded = await ref.read(ticketsApiProvider).upload(
            storeId: ref.read(authSessionProvider).storeId,
            bytes: picked.bytes,
            fileName: picked.name,
          );
      a.id = uploaded.id;
    } on ApiException catch (e) {
      a.failed = true;
      _snack(e.message);
    }
    if (mounted) setState(() {});
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TicketStrings.discardTitle),
        content: Text(TicketStrings.discardBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(TicketStrings.keepEditing)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(TicketStrings.discard),
          ),
        ],
      ),
    );
    if (discard == true) {
      _saveTimer?.cancel();
      await _drafts.clear();
    }
    return discard == true;
  }

  @override
  Widget build(BuildContext context) {
    final guard = _created == null && _dirty && !_submitting;
    return PopScope(
      canPop: !guard,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(TicketStrings.newTicket), automaticallyImplyLeading: _created == null),
        body: _draft == null
            ? const Center(child: CircularProgressIndicator())
            : _created != null
                ? _Success(ticket: _created!)
                : _form(context),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final online = ref.watch(isOnlineProvider).value ?? true;
    const border = OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)));

    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(s, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        );

    return AbsorbPointer(
      absorbing: _submitting,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!online) ...[
            StatusBanner(text: TicketStrings.offlineSubmit, tone: BannerTone.neutral, icon: Icons.cloud_off_rounded),
            const SizedBox(height: 16),
          ],
          label(TicketStrings.subject),
          TextField(
            controller: _subject,
            onChanged: (_) => _changed(),
            maxLength: 120,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              border: border,
              helperText: TicketStrings.subjectHelp,
              errorText: _showErrors ? _subjectError : null,
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          label(TicketStrings.description),
          TextField(
            controller: _description,
            onChanged: (_) => _changed(),
            minLines: 4,
            maxLines: 10,
            maxLength: 5000,
            decoration: InputDecoration(
              border: border,
              hintText: TicketStrings.descriptionHint,
              errorText: _showErrors ? _descriptionError : null,
              counterText: '',
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(child: Text(TicketStrings.secretsWarning, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
            ],
          ),
          const SizedBox(height: 16),
          label(TicketStrings.categoryLabel),
          DropdownButtonFormField<TicketCategory>(
            initialValue: _category,
            isExpanded: true,
            hint: Text(TicketStrings.selectCategory),
            decoration: InputDecoration(border: border, errorText: _showErrors ? _categoryError : null),
            items: [for (final c in TicketCategory.values) DropdownMenuItem(value: c, child: Text(TicketStrings.categoryName(c)))],
            onChanged: (c) {
              _category = c;
              _changed();
            },
          ),
          const SizedBox(height: 16),
          label(TicketStrings.priority),
          SegmentedButton<TicketPriority>(
            showSelectedIcon: false,
            segments: [for (final p in TicketPriority.values) ButtonSegment(value: p, label: Text(TicketStrings.priorityLabel(p)))],
            selected: {_priority},
            onSelectionChanged: (s) {
              _priority = s.first;
              _changed();
            },
          ),
          const SizedBox(height: 16),
          label(TicketStrings.relatedOperation),
          _RelatedOperation(
            operationId: _relatedOperationId,
            onClear: () {
              _relatedOperationId = null;
              _relatedModule = null;
              _changed();
            },
          ),
          const SizedBox(height: 16),
          label(TicketStrings.attachment),
          for (final f in _files)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    f.failed ? Icons.error_outline_rounded : Icons.attach_file_rounded,
                    color: f.failed ? scheme.error : null,
                  ),
                  title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(f.uploading ? TicketStrings.uploading : f.failed ? TicketStrings.uploadFailed : TicketStrings.fileSize(f.size)),
                  trailing: IconButton(
                    tooltip: TicketStrings.removeAttachment,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _files.remove(f)),
                  ),
                ),
              ),
            ),
          if (_files.length < _maxFiles)
            OutlinedButton.icon(
              onPressed: online ? _addFile : null,
              icon: const Icon(Icons.upload_file_rounded),
              label: Text(TicketStrings.addFile),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? TicketStrings.submitting : TicketStrings.submit),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _RelatedOperation extends ConsumerWidget {
  const _RelatedOperation({required this.operationId, required this.onClear});

  final String? operationId;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (operationId == null) {
      return Text(TicketStrings.relatedOperationHelp, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant));
    }
    final op = ref.watch(operationOnceProvider(operationId!)).value;
    final catalog = ref.watch(offlineCatalogProvider);
    final text = [if (op != null) op.title(catalog), shortOperationId(operationId!)].join(' · ');
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: context.status.offlineBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded, size: 18, color: context.status.offlineFg),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: t.bodyMedium?.copyWith(color: context.status.offlineFg))),
          IconButton(tooltip: TicketStrings.removeRelated, onPressed: onClear, icon: const Icon(Icons.close_rounded)),
        ],
      ),
    );
  }
}

String shortOperationId(String id) => id.length <= 12 ? id : 'op_${id.substring(0, 4)}…${id.substring(id.length - 3)}';

// H4
class _Success extends StatelessWidget {
  const _Success({required this.ticket});

  final TicketDetail ticket;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 32),
        Icon(Icons.check_circle_rounded, size: 56, color: context.status.onlineFg),
        const SizedBox(height: 16),
        Text(
          TicketStrings.created(ticket.ticketNumber),
          style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(TicketStrings.createdBody, style: t.bodyLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          TicketStrings.createdMeta(ticket),
          style: t.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => context.pushReplacement('/support/tickets/${ticket.id}'),
          child: Text(TicketStrings.viewTicket),
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: () => context.go('/support'), child: Text(TicketStrings.backToList)),
      ],
    );
  }
}
