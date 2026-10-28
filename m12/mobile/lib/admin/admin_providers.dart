import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/remote/tickets_api.dart';
import 'admin_api.dart';

/// Overridden in `main_admin.dart` (and tests).
final adminApiProvider = Provider<AdminTicketsApi>((ref) => throw UnimplementedError());

/// Name shown in the top bar, e.g. "Asha (support)".
final adminDisplayNameProvider = Provider<String>((ref) => 'Support');

final queueQueryProvider = NotifierProvider<QueueQueryNotifier, QueueQuery>(QueueQueryNotifier.new);

class QueueQueryNotifier extends Notifier<QueueQuery> {
  @override
  QueueQuery build() => const QueueQuery();

  void set(QueueQuery q) => state = q;
}

final queueProvider = FutureProvider.autoDispose.family<QueuePage, QueueQuery>((ref, q) => ref.read(adminApiProvider).list(q));

final statsProvider = FutureProvider.autoDispose<QueueStats>((ref) => ref.read(adminApiProvider).stats());

final agentsProvider = FutureProvider<List<NamedRef>>((ref) => ref.read(adminApiProvider).agents());

final adminTicketProvider =
    AsyncNotifierProvider.autoDispose.family<AdminTicketController, AdminTicket, String>(AdminTicketController.new);

class AdminTicketController extends AsyncNotifier<AdminTicket> {
  AdminTicketController(this.id);

  final String id;

  AdminTicketsApi get _api => ref.read(adminApiProvider);

  @override
  Future<AdminTicket> build() => _api.detail(id);

  /// Applies a change, then refreshes the queue list and sidebar counters.
  Future<void> _apply(Future<AdminTicket> Function() call) async {
    state = AsyncData(await call());
    ref.invalidate(queueProvider);
    ref.invalidate(statsProvider);
  }

  /// [requestId] stays the same across retries of one message, so it is never posted twice.
  Future<void> reply(String body, {required String requestId, bool internal = false, List<String> attachmentIds = const []}) =>
      _apply(() => _api.reply(id, clientRequestId: requestId, body: body, internal: internal, attachmentIds: attachmentIds));

  Future<void> setStatus(TicketStatus status, {String? note}) => _apply(() => _api.setStatus(id, status, note: note));

  Future<void> assign(String? agentId) => _apply(() => _api.assign(id, agentId));

  Future<void> setPriority(TicketPriority p) => _apply(() => _api.setPriority(id, p));

  Future<TicketAttachment> upload(List<int> bytes, String fileName) => _api.upload(id, bytes: bytes, fileName: fileName);

  static String newRequestId() => const Uuid().v4();
}
