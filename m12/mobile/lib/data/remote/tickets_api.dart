import 'api_client.dart';

enum TicketStatus {
  open('OPEN'),
  inProgress('IN_PROGRESS'),
  waitingForUser('WAITING_FOR_USER'),
  resolved('RESOLVED'),
  closed('CLOSED');

  const TicketStatus(this.wire);
  final String wire;

  static TicketStatus parse(String s) => values.firstWhere((v) => v.wire == s, orElse: () => open);
}

enum TicketPriority {
  low('LOW', 'Low'),
  normal('NORMAL', 'Normal'),
  high('HIGH', 'High'),
  critical('CRITICAL', 'Critical');

  const TicketPriority(this.wire, this.label);
  final String wire;
  final String label;

  static TicketPriority parse(String s) => values.firstWhere((v) => v.wire == s, orElse: () => normal);
}

/// Spec §8.2: Bug, Feature Request, Account, Sync, Data Conflict, Other.
enum TicketCategory {
  bug('BUG', 'Bug'),
  featureRequest('FEATURE_REQUEST', 'Feature Request'),
  account('ACCOUNT', 'Account'),
  sync('SYNC', 'Sync'),
  dataConflict('DATA_CONFLICT', 'Data Conflict'),
  other('OTHER', 'Other');

  const TicketCategory(this.wire, this.label);
  final String wire;
  final String label;

  static TicketCategory parse(String s) => values.firstWhere((v) => v.wire == s, orElse: () => other);
}

DateTime _date(Object? v) => DateTime.parse(v as String).toLocal();
DateTime? _dateOrNull(Object? v) => v == null ? null : _date(v);

class TicketSummary {
  TicketSummary.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        ticketNumber = j['ticketNumber'] as String,
        subject = j['subject'] as String,
        category = TicketCategory.parse(j['category'] as String),
        priority = TicketPriority.parse(j['priority'] as String),
        status = TicketStatus.parse(j['status'] as String),
        relatedOperationId = j['relatedOperationId'] as String?,
        lastActivityBySupport = j['lastActivityBy'] == 'SUPPORT',
        createdAt = _date(j['createdAt']),
        updatedAt = _date(j['updatedAt']);

  final String id;
  final String ticketNumber;
  final String subject;
  final TicketCategory category;
  final TicketPriority priority;
  final TicketStatus status;
  final String? relatedOperationId;
  final bool lastActivityBySupport;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Support asked a question and is waiting on the shop.
  bool get needsReply => status == TicketStatus.waitingForUser;
}

class TicketAttachment {
  TicketAttachment.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        fileName = j['fileName'] as String,
        contentType = j['contentType'] as String,
        size = j['size'] as int;

  final String id;
  final String fileName;
  final String contentType;
  final int size;
}

enum TicketEventType { created, message, statusChange }

class TicketEvent {
  TicketEvent.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        type = switch (j['type']) {
          'CREATED' => TicketEventType.created,
          'STATUS_CHANGE' => TicketEventType.statusChange,
          _ => TicketEventType.message,
        },
        bySupport = j['authorRole'] == 'SUPPORT',
        byViewer = j['byViewer'] as bool? ?? false,
        body = j['body'] as String?,
        fromStatus = j['fromStatus'] == null ? null : TicketStatus.parse(j['fromStatus'] as String),
        toStatus = j['toStatus'] == null ? null : TicketStatus.parse(j['toStatus'] as String),
        attachmentIds = (j['attachmentIds'] as List? ?? const []).cast<String>(),
        createdAt = _date(j['createdAt']);

  final String id;
  final TicketEventType type;
  final bool bySupport;
  final bool byViewer;
  final String? body;
  final TicketStatus? fromStatus;
  final TicketStatus? toStatus;
  final List<String> attachmentIds;
  final DateTime createdAt;
}

class TicketDetail extends TicketSummary {
  TicketDetail.fromJson(super.j)
      : description = j['description'] as String,
        relatedModule = j['relatedModule'] as String?,
        resolvedAt = _dateOrNull(j['resolvedAt']),
        canReply = j['canReply'] as bool? ?? false,
        canClose = j['canClose'] as bool? ?? false,
        attachments = [for (final a in j['attachments'] as List? ?? const []) TicketAttachment.fromJson(a as Map<String, dynamic>)],
        events = [for (final e in j['events'] as List? ?? const []) TicketEvent.fromJson(e as Map<String, dynamic>)],
        super.fromJson();

  final String description;
  final String? relatedModule;
  final DateTime? resolvedAt;
  final bool canReply;
  final bool canClose;
  final List<TicketAttachment> attachments;
  final List<TicketEvent> events;
}

class TicketPage {
  TicketPage({required this.tickets, this.nextCursor});
  final List<TicketSummary> tickets;
  final String? nextCursor;
}

class TicketQuery {
  const TicketQuery({this.status, this.category, this.priority, this.q = ''});

  final TicketStatus? status;
  final TicketCategory? category;
  final TicketPriority? priority;
  final String q;

  bool get isFiltered => status != null || category != null || priority != null || q.trim().isNotEmpty;

  TicketQuery copyWith({
    TicketStatus? Function()? status,
    TicketCategory? Function()? category,
    TicketPriority? Function()? priority,
    String? q,
  }) => TicketQuery(
    status: status == null ? this.status : status(),
    category: category == null ? this.category : category(),
    priority: priority == null ? this.priority : priority(),
    q: q ?? this.q,
  );

  @override
  bool operator ==(Object other) =>
      other is TicketQuery &&
      other.status == status &&
      other.category == category &&
      other.priority == priority &&
      other.q == q;

  @override
  int get hashCode => Object.hash(status, category, priority, q);
}

abstract interface class TicketsApi {
  Future<TicketPage> list({required String storeId, TicketQuery query = const TicketQuery(), String? cursor});
  Future<TicketDetail> get({required String storeId, required String id});
  Future<TicketDetail> create({
    required String storeId,
    required String clientRequestId,
    required String subject,
    required String description,
    required TicketCategory category,
    required TicketPriority priority,
    String? relatedOperationId,
    String? relatedModule,
    List<String> attachmentIds = const [],
  });
  Future<TicketDetail> reply({
    required String storeId,
    required String id,
    required String clientRequestId,
    required String body,
  });
  Future<TicketDetail> close({required String storeId, required String id});
  Future<TicketAttachment> upload({required String storeId, required List<int> bytes, required String fileName});
}

class HttpTicketsApi implements TicketsApi {
  HttpTicketsApi(this._client);

  final ApiClient _client;

  @override
  Future<TicketPage> list({required String storeId, TicketQuery query = const TicketQuery(), String? cursor}) async {
    final q = query.q.trim();
    final body = await _client.get('/tickets', queryParameters: {
      'storeId': storeId,
      'status': ?query.status?.wire,
      'category': ?query.category?.wire,
      'priority': ?query.priority?.wire,
      if (q.isNotEmpty) 'q': q,
      'cursor': ?cursor,
    });
    return TicketPage(
      tickets: [for (final t in body['tickets'] as List) TicketSummary.fromJson(t as Map<String, dynamic>)],
      nextCursor: body['nextCursor'] as String?,
    );
  }

  @override
  Future<TicketDetail> get({required String storeId, required String id}) async =>
      TicketDetail.fromJson(await _client.get('/tickets/$id', queryParameters: {'storeId': storeId}));

  @override
  Future<TicketDetail> create({
    required String storeId,
    required String clientRequestId,
    required String subject,
    required String description,
    required TicketCategory category,
    required TicketPriority priority,
    String? relatedOperationId,
    String? relatedModule,
    List<String> attachmentIds = const [],
  }) async => TicketDetail.fromJson(await _client.post('/tickets', data: {
    'storeId': storeId,
    'clientRequestId': clientRequestId,
    'subject': subject,
    'description': description,
    'category': category.wire,
    'priority': priority.wire,
    'relatedOperationId': ?relatedOperationId,
    'relatedModule': ?relatedModule,
    if (attachmentIds.isNotEmpty) 'attachmentIds': attachmentIds,
  }));

  @override
  Future<TicketDetail> reply({
    required String storeId,
    required String id,
    required String clientRequestId,
    required String body,
  }) async => TicketDetail.fromJson(
    await _client.post('/tickets/$id/messages', data: {'storeId': storeId, 'clientRequestId': clientRequestId, 'body': body}),
  );

  @override
  Future<TicketDetail> close({required String storeId, required String id}) async =>
      TicketDetail.fromJson(await _client.patch('/tickets/$id/status', data: {'storeId': storeId, 'status': 'CLOSED'}));

  @override
  Future<TicketAttachment> upload({required String storeId, required List<int> bytes, required String fileName}) async =>
      TicketAttachment.fromJson(
        await _client.upload('/tickets/attachments', bytes: bytes, fileName: fileName, fields: {'storeId': storeId}),
      );
}
