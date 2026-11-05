import '../data/remote/api_client.dart';
import '../data/remote/tickets_api.dart';

DateTime _date(Object? v) => DateTime.parse(v as String).toLocal();
DateTime? _dateOrNull(Object? v) => v == null ? null : _date(v);

/// Queue views in the console sidebar (server: `/admin/tickets?view=`).
enum QueueView {
  needsReply('needs_reply', 'Needs reply'),
  unassigned('unassigned', 'Unassigned'),
  mine('mine', 'Assigned to me'),
  open('open', 'All open'),
  waitingUser('waiting_user', 'Waiting for shop'),
  resolved('resolved', 'Resolved'),
  closed('closed', 'Closed'),
  all('all', 'All tickets');

  const QueueView(this.wire, this.label);
  final String wire;
  final String label;
}

enum QueueSort {
  priority('priority', 'Priority'),
  oldest('oldest', 'Oldest first'),
  newest('newest', 'Newest first');

  const QueueSort(this.wire, this.label);
  final String wire;
  final String label;
}

class NamedRef {
  const NamedRef({required this.id, this.name});
  final String id;
  final String? name;

  static NamedRef? fromJson(Object? j) {
    if (j is! Map) return null;
    return NamedRef(id: j['id'] as String, name: j['name'] as String?);
  }
}

class QueueRow {
  QueueRow.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        ticketNumber = j['ticketNumber'] as String,
        subject = j['subject'] as String,
        status = TicketStatus.parse(j['status'] as String),
        priority = TicketPriority.parse(j['priority'] as String),
        category = TicketCategory.parse(j['category'] as String),
        shop = NamedRef.fromJson(j['shop'])!,
        requesterName = j['requesterName'] as String?,
        assignee = NamedRef.fromJson(j['assignee']),
        lastActivityAt = _date(j['lastActivityAt']),
        needsReply = j['needsReply'] as bool? ?? false,
        createdAt = _date(j['createdAt']);

  final String id;
  final String ticketNumber;
  final String subject;
  final TicketStatus status;
  final TicketPriority priority;
  final TicketCategory category;
  final NamedRef shop;
  final String? requesterName;
  final NamedRef? assignee;
  final DateTime lastActivityAt;
  final bool needsReply;
  final DateTime createdAt;
}

class QueuePage {
  QueuePage.fromJson(Map<String, dynamic> j)
      : rows = [for (final r in j['tickets'] as List) QueueRow.fromJson(r as Map<String, dynamic>)],
        page = j['page'] as int,
        pageSize = j['pageSize'] as int,
        total = j['total'] as int;

  final List<QueueRow> rows;
  final int page;
  final int pageSize;
  final int total;

  int get pages => total == 0 ? 1 : (total / pageSize).ceil();
}

class QueueStats {
  QueueStats.fromJson(Map<String, dynamic> j)
      : counts = {for (final v in QueueView.values) v: (j[v.wire] as num?)?.toInt() ?? 0},
        criticalOpen = (j['critical_open'] as num?)?.toInt() ?? 0;

  final Map<QueueView, int> counts;
  final int criticalOpen;
}

class AdminEvent {
  AdminEvent.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        type = j['type'] as String,
        internal = j['visibility'] == 'INTERNAL',
        bySupport = j['authorRole'] == 'SUPPORT',
        byViewer = j['byViewer'] as bool? ?? false,
        authorName = j['authorName'] as String?,
        body = j['body'] as String?,
        fromStatus = j['fromStatus'] == null ? null : TicketStatus.parse(j['fromStatus'] as String),
        toStatus = j['toStatus'] == null ? null : TicketStatus.parse(j['toStatus'] as String),
        meta = (j['meta'] as Map?)?.cast<String, dynamic>(),
        attachmentIds = (j['attachmentIds'] as List? ?? const []).cast<String>(),
        createdAt = _date(j['createdAt']);

  final String id;

  /// CREATED, MESSAGE, NOTE, STATUS_CHANGE, ASSIGNMENT, PRIORITY_CHANGE
  final String type;
  final bool internal;
  final bool bySupport;
  final bool byViewer;
  final String? authorName;
  final String? body;
  final TicketStatus? fromStatus;
  final TicketStatus? toStatus;
  final Map<String, dynamic>? meta;
  final List<String> attachmentIds;
  final DateTime createdAt;
}

class OperationAttempt {
  OperationAttempt.fromJson(Map<String, dynamic> j)
      : action = j['action'] as String,
        result = j['result'] as String,
        errorCode = j['errorCode'] as String?,
        durationMs = j['durationMs'] as int?,
        timestamp = _date(j['timestamp']);

  final String action;
  final String result;
  final String? errorCode;
  final int? durationMs;
  final DateTime timestamp;
}

class RelatedOperation {
  RelatedOperation.fromJson(Map<String, dynamic> j)
      : clientOperationId = j['clientOperationId'] as String,
        module = j['module'] as String?,
        operationType = j['operationType'] as String?,
        receivedByServer = j['receivedByServer'] as bool? ?? false,
        status = j['status'] as String?,
        serverResourceId = j['serverResourceId'] as String?,
        attemptCount = j['attemptCount'] as int?,
        lastErrorCode = j['lastErrorCode'] as String?,
        lastErrorMessage = j['lastErrorMessage'] as String?,
        deviceId = j['deviceId'] as String?,
        processedAt = _dateOrNull(j['processedAt']),
        attempts = [for (final a in j['attempts'] as List? ?? const []) OperationAttempt.fromJson(a as Map<String, dynamic>)];

  final String clientOperationId;
  final String? module;
  final String? operationType;
  final bool receivedByServer;
  final String? status;
  final String? serverResourceId;
  final int? attemptCount;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final String? deviceId;
  final DateTime? processedAt;
  final List<OperationAttempt> attempts;
}

class AdminTicket {
  AdminTicket.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        ticketNumber = j['ticketNumber'] as String,
        subject = j['subject'] as String,
        description = j['description'] as String,
        status = TicketStatus.parse(j['status'] as String),
        priority = TicketPriority.parse(j['priority'] as String),
        category = TicketCategory.parse(j['category'] as String),
        shopName = (j['shop'] as Map?)?['name'] as String?,
        shopId = (j['shop'] as Map?)?['id'] as String? ?? '',
        shopStatus = (j['shop'] as Map?)?['status'] as String?,
        requesterName = (j['requester'] as Map?)?['name'] as String?,
        requesterRole = (j['requester'] as Map?)?['role'] as String?,
        assignee = NamedRef.fromJson(j['assignee']),
        relatedOperation =
            j['relatedOperation'] == null ? null : RelatedOperation.fromJson(j['relatedOperation'] as Map<String, dynamic>),
        attachments = [for (final a in j['attachments'] as List? ?? const []) TicketAttachment.fromJson(a as Map<String, dynamic>)],
        events = [for (final e in j['events'] as List? ?? const []) AdminEvent.fromJson(e as Map<String, dynamic>)],
        createdAt = _date(j['createdAt']),
        updatedAt = _date(j['updatedAt']),
        resolvedAt = _dateOrNull(j['resolvedAt']);

  final String id;
  final String ticketNumber;
  final String subject;
  final String description;
  final TicketStatus status;
  final TicketPriority priority;
  final TicketCategory category;
  final String? shopName;
  final String shopId;
  final String? shopStatus;
  final String? requesterName;
  final String? requesterRole;
  final NamedRef? assignee;
  final RelatedOperation? relatedOperation;
  final List<TicketAttachment> attachments;
  final List<AdminEvent> events;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? resolvedAt;

  bool get isClosed => status == TicketStatus.closed;
}

class QueueQuery {
  const QueueQuery({
    this.view = QueueView.needsReply,
    this.priority,
    this.category,
    this.q = '',
    this.sort = QueueSort.priority,
    this.page = 1,
  });

  final QueueView view;
  final TicketPriority? priority;
  final TicketCategory? category;
  final String q;
  final QueueSort sort;
  final int page;

  QueueQuery copyWith({
    QueueView? view,
    TicketPriority? Function()? priority,
    TicketCategory? Function()? category,
    String? q,
    QueueSort? sort,
    int? page,
  }) => QueueQuery(
    view: view ?? this.view,
    priority: priority == null ? this.priority : priority(),
    category: category == null ? this.category : category(),
    q: q ?? this.q,
    sort: sort ?? this.sort,
    page: page ?? (view != null || priority != null || category != null || q != null || sort != null ? 1 : this.page),
  );

  @override
  bool operator ==(Object other) =>
      other is QueueQuery &&
      other.view == view &&
      other.priority == priority &&
      other.category == category &&
      other.q == q &&
      other.sort == sort &&
      other.page == page;

  @override
  int get hashCode => Object.hash(view, priority, category, q, sort, page);
}

abstract interface class AdminTicketsApi {
  Future<QueuePage> list(QueueQuery query);
  Future<QueueStats> stats();
  Future<List<NamedRef>> agents();
  Future<AdminTicket> detail(String id);
  Future<AdminTicket> reply(String id, {required String clientRequestId, required String body, bool internal = false, List<String> attachmentIds = const []});
  Future<AdminTicket> setStatus(String id, TicketStatus status, {String? note});
  Future<AdminTicket> assign(String id, String? agentId);
  Future<AdminTicket> setPriority(String id, TicketPriority priority);
  Future<TicketAttachment> upload(String id, {required List<int> bytes, required String fileName});
  Future<List<int>> download(String id, String attachmentId);
}

class HttpAdminTicketsApi implements AdminTicketsApi {
  HttpAdminTicketsApi(this._client);

  final ApiClient _client;

  @override
  Future<QueuePage> list(QueueQuery q) async => QueuePage.fromJson(await _client.get('/admin/tickets', queryParameters: {
    'view': q.view.wire,
    'priority': ?q.priority?.wire,
    'category': ?q.category?.wire,
    if (q.q.trim().isNotEmpty) 'q': q.q.trim(),
    'sort': q.sort.wire,
    'page': q.page,
    'pageSize': 25,
  }));

  @override
  Future<QueueStats> stats() async => QueueStats.fromJson(await _client.get('/admin/tickets/stats'));

  @override
  Future<List<NamedRef>> agents() async =>
      [for (final a in (await _client.get('/admin/agents'))['agents'] as List) NamedRef.fromJson(a)!];

  @override
  Future<AdminTicket> detail(String id) async => AdminTicket.fromJson(await _client.get('/admin/tickets/$id'));

  @override
  Future<AdminTicket> reply(String id, {required String clientRequestId, required String body, bool internal = false, List<String> attachmentIds = const []}) async =>
      AdminTicket.fromJson(await _client.post('/admin/tickets/$id/messages', data: {
        'clientRequestId': clientRequestId,
        'body': body,
        'internal': internal,
        if (attachmentIds.isNotEmpty) 'attachmentIds': attachmentIds,
      }));

  @override
  Future<AdminTicket> setStatus(String id, TicketStatus status, {String? note}) async =>
      AdminTicket.fromJson(await _client.patch('/admin/tickets/$id/status', data: {'status': status.wire, 'note': ?note}));

  @override
  Future<AdminTicket> assign(String id, String? agentId) async =>
      AdminTicket.fromJson(await _client.patch('/admin/tickets/$id/assignee', data: {'assigneeUserId': agentId}));

  @override
  Future<AdminTicket> setPriority(String id, TicketPriority priority) async =>
      AdminTicket.fromJson(await _client.patch('/admin/tickets/$id/priority', data: {'priority': priority.wire}));

  @override
  Future<TicketAttachment> upload(String id, {required List<int> bytes, required String fileName}) async =>
      TicketAttachment.fromJson(await _client.upload('/admin/tickets/$id/attachments', bytes: bytes, fileName: fileName));

  @override
  Future<List<int>> download(String id, String attachmentId) => _client.getBytes('/admin/tickets/$id/attachments/$attachmentId');
}
