import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/outbox_dao.dart';
import '../../data/remote/tickets_api.dart';
import '../sync/sync_providers.dart';

/// Overridden in `main()`.
final ticketsApiProvider = Provider<TicketsApi>((ref) => throw UnimplementedError());

// ------------------------------------------------------------------ list (G)

final ticketQueryProvider = NotifierProvider.autoDispose<TicketQueryNotifier, TicketQuery>(TicketQueryNotifier.new);

class TicketQueryNotifier extends Notifier<TicketQuery> {
  @override
  TicketQuery build() => const TicketQuery();

  void set(TicketQuery q) => state = q;
  void clear() => state = const TicketQuery();
}

class TicketListState {
  const TicketListState({required this.tickets, this.nextCursor, this.loadingMore = false});

  final List<TicketSummary> tickets;
  final String? nextCursor;
  final bool loadingMore;
}

final ticketListProvider =
    AsyncNotifierProvider.autoDispose.family<TicketListController, TicketListState, TicketQuery>(TicketListController.new);

class TicketListController extends AsyncNotifier<TicketListState> {
  TicketListController(this.query);

  final TicketQuery query;

  @override
  Future<TicketListState> build() async {
    final page = await ref.read(ticketsApiProvider).list(storeId: ref.read(authSessionProvider).storeId, query: query);
    return TicketListState(tickets: page.tickets, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.nextCursor == null || current.loadingMore) return;
    state = AsyncData(TicketListState(tickets: current.tickets, nextCursor: current.nextCursor, loadingMore: true));
    try {
      final page = await ref
          .read(ticketsApiProvider)
          .list(storeId: ref.read(authSessionProvider).storeId, query: query, cursor: current.nextCursor);
      state = AsyncData(TicketListState(tickets: [...current.tickets, ...page.tickets], nextCursor: page.nextCursor));
    } catch (_) {
      state = AsyncData(TicketListState(tickets: current.tickets, nextCursor: current.nextCursor));
      rethrow;
    }
  }
}

// ---------------------------------------------------------------- detail (I)

final ticketDetailProvider =
    AsyncNotifierProvider.autoDispose.family<TicketDetailController, TicketDetail, String>(TicketDetailController.new);

class TicketDetailController extends AsyncNotifier<TicketDetail> {
  TicketDetailController(this.id);

  final String id;

  String get _storeId => ref.read(authSessionProvider).storeId;

  @override
  Future<TicketDetail> build() => ref.read(ticketsApiProvider).get(storeId: _storeId, id: id);

  /// [clientRequestId] is kept by the caller across retries, so a resend never posts twice.
  Future<void> reply(String body, String clientRequestId) async {
    final t = await ref.read(ticketsApiProvider).reply(storeId: _storeId, id: id, clientRequestId: clientRequestId, body: body);
    state = AsyncData(t);
  }

  Future<void> close() async {
    state = AsyncData(await ref.read(ticketsApiProvider).close(storeId: _storeId, id: id));
  }
}

// ----------------------------------------------------------------- draft (H)

/// The create form survives navigation, app restarts and offline periods
/// ("Drafts you started are kept", G4). The `clientRequestId` lives with the
/// draft, so re-submitting after a timeout can never create a second ticket.
class TicketDraft {
  const TicketDraft({
    required this.clientRequestId,
    this.subject = '',
    this.description = '',
    this.category,
    this.priority = TicketPriority.normal,
    this.relatedOperationId,
    this.relatedModule,
  });

  factory TicketDraft.fresh({String? relatedOperationId, String? relatedModule}) => TicketDraft(
    clientRequestId: const Uuid().v4(),
    relatedOperationId: relatedOperationId,
    relatedModule: relatedModule,
    category: relatedOperationId != null ? TicketCategory.sync : null,
  );

  factory TicketDraft.fromJson(Map<String, dynamic> j) => TicketDraft(
    clientRequestId: j['clientRequestId'] as String,
    subject: j['subject'] as String? ?? '',
    description: j['description'] as String? ?? '',
    category: j['category'] == null ? null : TicketCategory.parse(j['category'] as String),
    priority: TicketPriority.parse(j['priority'] as String? ?? 'NORMAL'),
    relatedOperationId: j['relatedOperationId'] as String?,
    relatedModule: j['relatedModule'] as String?,
  );

  final String clientRequestId;
  final String subject;
  final String description;
  final TicketCategory? category;
  final TicketPriority priority;
  final String? relatedOperationId;
  final String? relatedModule;

  bool get hasContent => subject.trim().isNotEmpty || description.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'clientRequestId': clientRequestId,
    'subject': subject,
    'description': description,
    'category': category?.wire,
    'priority': priority.wire,
    'relatedOperationId': relatedOperationId,
    'relatedModule': relatedModule,
  };
}

class TicketDraftStore {
  TicketDraftStore(this._dao);

  final OutboxDao _dao;
  static const _key = 'ticket_draft';

  Future<TicketDraft?> load() async {
    final raw = await _dao.readMeta(_key);
    if (raw == null || raw.isEmpty) return null;
    return TicketDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(TicketDraft d) => _dao.writeMeta(_key, jsonEncode(d.toJson()));

  Future<void> clear() => _dao.writeMeta(_key, '');
}

final ticketDraftStoreProvider = Provider<TicketDraftStore>((ref) => TicketDraftStore(ref.watch(outboxDaoProvider)));

// ----------------------------------------------------------- file picking

class PickedFile {
  const PickedFile({required this.name, required this.size, required this.bytes});
  final String name;
  final int size;
  final Uint8List bytes;
}

/// Abstracted so widget tests can supply files without a platform picker.
abstract interface class AttachmentPicker {
  Future<PickedFile?> pick();
}

class PlatformAttachmentPicker implements AttachmentPicker {
  const PlatformAttachmentPicker();

  @override
  Future<PickedFile?> pick() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png']);
    if (f == null) return null;
    final bytes = await f.readAsBytes();
    return PickedFile(name: f.name, size: bytes.length, bytes: bytes);
  }
}

final attachmentPickerProvider = Provider<AttachmentPicker>((ref) => const PlatformAttachmentPicker());
