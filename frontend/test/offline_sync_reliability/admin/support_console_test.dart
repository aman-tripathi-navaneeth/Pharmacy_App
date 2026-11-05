import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmacy_app/modules/offline_sync_reliability/admin/admin_api.dart';
import 'package:pharmacy_app/modules/offline_sync_reliability/admin/admin_app.dart';
import 'package:pharmacy_app/modules/offline_sync_reliability/admin/admin_providers.dart';
import 'package:pharmacy_app/modules/offline_sync_reliability/app/theme.dart';
import 'package:pharmacy_app/modules/offline_sync_reliability/data/remote/tickets_api.dart';

import '../support/l10n.dart';

const _agentId = 'a1';
final _now = DateTime.now().toUtc();
String _iso(Duration ago) => _now.subtract(ago).toIso8601String();

Map<String, dynamic> _row(String id, String number, {String priority = 'NORMAL', bool needsReply = true, String status = 'OPEN'}) => {
  'id': id,
  'ticketNumber': number,
  'subject': 'Subject $number',
  'status': status,
  'priority': priority,
  'category': 'SYNC',
  'shop': {'id': 's1', 'name': 'Sri Sai Medicals'},
  'requesterName': 'Ravi',
  'assignee': null,
  'lastActivityAt': _iso(const Duration(hours: 2)),
  'needsReply': needsReply,
  'createdAt': _iso(const Duration(hours: 3)),
};

Map<String, dynamic> _ticket({String status = 'OPEN', String? assigneeId, List<Map<String, dynamic>>? extraEvents}) => {
  'id': 't1',
  'ticketNumber': 'TKT-1001',
  'subject': 'Oversell rejected on sync',
  'description': 'A sale recorded offline was rejected.',
  'status': status,
  'priority': 'HIGH',
  'category': 'SYNC',
  'shop': {'id': 's1', 'name': 'Sri Sai Medicals', 'status': 'ACTIVE'},
  'requester': {'id': 'u1', 'name': 'Ravi', 'role': 'OWNER'},
  'assignee': assigneeId == null ? null : {'id': assigneeId, 'name': 'Asha (support)'},
  'relatedOperation': {
    'clientOperationId': '7f3a1234-5678-4abc-8def-1234567890c9',
    'module': 'inventory',
    'operationType': 'stock_movement',
    'receivedByServer': true,
    'status': 'FAILED',
    'attemptCount': 1,
    'lastErrorCode': 'INSUFFICIENT_STOCK',
    'lastErrorMessage': 'Stock quantity exceeds available balance.',
    'deviceId': 'device-7',
    'attempts': [
      {'action': 'PUSH', 'result': 'FAILED_PERMANENT', 'errorCode': 'INSUFFICIENT_STOCK', 'durationMs': 12, 'timestamp': _iso(const Duration(hours: 3))},
    ],
  },
  'attachments': <dynamic>[],
  'events': [
    {'id': 'e1', 'type': 'CREATED', 'visibility': 'PUBLIC', 'authorRole': 'USER', 'authorName': 'Ravi', 'createdAt': _iso(const Duration(hours: 3))},
    {'id': 'e2', 'type': 'NOTE', 'visibility': 'INTERNAL', 'authorRole': 'SUPPORT', 'authorName': 'Asha (support)', 'body': 'Checking stock ledger.', 'createdAt': _iso(const Duration(hours: 1))},
    ...?extraEvents,
  ],
  'createdAt': _iso(const Duration(hours: 3)),
  'updatedAt': _iso(const Duration(hours: 1)),
  'resolvedAt': status == 'RESOLVED' ? _iso(Duration.zero) : null,
};

class FakeAdminApi implements AdminTicketsApi {
  final calls = <String>[];
  QueueQuery? lastQuery;
  String status = 'OPEN';
  String? assignee;
  Duration agentsDelay = Duration.zero;

  @override
  Future<QueuePage> list(QueueQuery query) async {
    lastQuery = query;
    return QueuePage.fromJson({
      'tickets': [_row('t1', 'TKT-1001', priority: 'CRITICAL'), _row('t2', 'TKT-1002', needsReply: false)],
      'page': 1,
      'pageSize': 25,
      'total': 2,
    });
  }

  @override
  Future<QueueStats> stats() async => QueueStats.fromJson({
    'needs_reply': 1, 'unassigned': 2, 'mine': 0, 'open': 2, 'waiting_user': 0, 'resolved': 4, 'closed': 9, 'all': 15, 'critical_open': 1,
  });

  @override
  Future<List<NamedRef>> agents() async => Future.delayed(agentsDelay, () => const [NamedRef(id: _agentId, name: 'Asha (support)'), NamedRef(id: 'a2', name: 'Bala (support)')]);

  @override
  Future<AdminTicket> detail(String id) async => AdminTicket.fromJson(_ticket(status: status, assigneeId: assignee));

  @override
  Future<AdminTicket> reply(String id, {required String clientRequestId, required String body, bool internal = false, List<String> attachmentIds = const []}) async {
    calls.add('reply:${internal ? 'internal' : 'public'}:$body');
    return detail(id);
  }

  @override
  Future<AdminTicket> setStatus(String id, TicketStatus s, {String? note}) async {
    calls.add('status:${s.wire}:${note ?? ''}');
    status = s.wire;
    return detail(id);
  }

  @override
  Future<AdminTicket> assign(String id, String? agentId) async {
    calls.add('assign:$agentId');
    assignee = agentId;
    return detail(id);
  }

  @override
  Future<AdminTicket> setPriority(String id, TicketPriority priority) async {
    calls.add('priority:${priority.wire}');
    return detail(id);
  }

  @override
  Future<TicketAttachment> upload(String id, {required List<int> bytes, required String fileName}) => throw UnimplementedError();

  @override
  Future<List<int>> download(String id, String attachmentId) async => const [];
}

void main() {
  late FakeAdminApi api;

  setUpAll(useEnglish);
  setUp(() => api = FakeAdminApi());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<GoRouter> pump(WidgetTester tester, {String location = '/'}) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    final router = buildAdminRouter()..go(location);
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [adminApiProvider.overrideWithValue(api), adminDisplayNameProvider.overrideWithValue('Asha (support)')],
      child: MaterialApp.router(theme: buildTheme(Brightness.light), routerConfig: router),
    ));
    await settle(tester);
    return router;
  }

  testWidgets('queue: views with counts, critical banner, rows across shops', (tester) async {
    await pump(tester);
    expect(find.text('Needs reply'), findsWidgets); // sidebar view + row badge
    expect(find.text('1 critical ticket open'), findsOneWidget);
    expect(find.text('Subject TKT-1001'), findsOneWidget);
    expect(find.textContaining('Sri Sai Medicals · Ravi · Sync'), findsNWidgets(2));
    expect(find.text('1–2 of 2'), findsOneWidget);
    expect(find.text('Select a ticket'), findsOneWidget);

    await tester.tap(find.text('Resolved').first);
    await settle(tester);
    expect(api.lastQuery!.view, QueueView.resolved);
  });

  testWidgets('full ticket: shop, requester, related operation history, internal notes', (tester) async {
    await pump(tester, location: '/tickets/t1');
    expect(find.text('Oversell rejected on sync'), findsOneWidget);
    expect(find.text('Shop & requester'), findsOneWidget);
    expect(find.text('OWNER'), findsOneWidget);
    expect(find.text('Related operation'), findsOneWidget);
    expect(find.text('INSUFFICIENT_STOCK: Stock quantity exceeds available balance.'), findsOneWidget);
    expect(find.textContaining('PUSH · FAILED_PERMANENT (INSUFFICIENT_STOCK) · 12 ms'), findsOneWidget);
    expect(find.textContaining('Internal note · Asha (support)'), findsOneWidget);
    expect(find.text('A sale recorded offline was rejected.'), findsOneWidget);
  });

  testWidgets('reply vs internal note from the composer', (tester) async {
    await pump(tester, location: '/tickets/t1');
    await tester.enterText(find.widgetWithText(TextField, 'Write a reply to the shop…'), 'Which invoice was it?');
    await tester.pump();
    await tester.tap(find.text('Send reply'));
    await settle(tester);
    expect(api.calls, ['reply:public:Which invoice was it?']);

    await tester.tap(find.text('Internal note'));
    await tester.pump();
    expect(find.text('Only support staff can see notes'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Add a note for the support team…'), 'Ledger shows 46 units.');
    await tester.pump();
    await tester.tap(find.text('Add note'));
    await settle(tester);
    expect(api.calls.last, 'reply:internal:Ledger shows 46 units.');
  });

  testWidgets('resolve requires a summary the shop will see; reopen afterwards', (tester) async {
    await pump(tester, location: '/tickets/t1');
    await tester.tap(find.widgetWithText(FilledButton, 'Resolve'));
    await settle(tester);
    expect(find.text('Resolve TKT-1001'), findsOneWidget);

    await tester.tap(find.text('Resolve ticket'));
    await tester.pump();
    expect(find.text('Write a resolution summary (at least 5 characters).'), findsOneWidget);
    expect(api.calls, isEmpty);

    await tester.enterText(find.byType(TextField).last, 'Corrected the stock count; please retry the sale.');
    await tester.tap(find.text('Resolve ticket'));
    await settle(tester);
    expect(api.calls, ['status:RESOLVED:Corrected the stock count; please retry the sale.']);
    expect(find.text('Reopen'), findsOneWidget);

    await tester.tap(find.text('Reopen'));
    await settle(tester);
    expect(api.calls.last, 'status:IN_PROGRESS:');
  });

  testWidgets('ask for info, assign to me, close', (tester) async {
    await pump(tester, location: '/tickets/t1');
    await tester.tap(find.text('Ask shop for info'));
    await settle(tester);
    expect(api.calls.last, 'status:WAITING_FOR_USER:');
    expect(find.text('Mark in progress'), findsOneWidget);

    await tester.tap(find.text('Assign to me'));
    await settle(tester);
    expect(api.calls.last, 'assign:$_agentId');

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await settle(tester);
    await tester.tap(find.text('Close ticket'));
    await settle(tester);
    expect(api.calls.last, 'status:CLOSED:');
    expect(find.textContaining('This ticket is closed.'), findsOneWidget);
    expect(find.text('Send reply'), findsNothing);
  });

  testWidgets('assignee shows once agents load after the ticket', (tester) async {
    api
      ..assignee = 'a2'
      ..agentsDelay = const Duration(milliseconds: 200);
    await pump(tester, location: '/tickets/t1');
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(find.text('Bala (support)'), findsOneWidget);
    expect(find.text('Assign to me'), findsOneWidget);
  });
}
