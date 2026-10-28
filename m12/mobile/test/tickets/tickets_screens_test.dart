import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_store/app/theme.dart';
import 'package:medical_store/data/local/app_database.dart';
import 'package:medical_store/data/remote/api_client.dart';
import 'package:medical_store/data/remote/tickets_api.dart';
import 'package:medical_store/features/sync/sync_providers.dart';
import 'package:medical_store/features/tickets/screens/create_ticket_screen.dart';
import 'package:medical_store/features/tickets/screens/ticket_detail_screen.dart';
import 'package:medical_store/features/tickets/screens/tickets_list_screen.dart';
import 'package:medical_store/features/tickets/tickets_providers.dart';

import '../support/fakes.dart';
import '../support/l10n.dart';

Map<String, dynamic> _ticketJson({
  String id = 't1',
  String number = 'TKT-1041',
  String subject = 'Sync stuck at 3 of 8',
  String status = 'OPEN',
  String priority = 'HIGH',
  String category = 'SYNC',
  bool canReply = true,
  bool canClose = true,
  List<Map<String, dynamic>> events = const [],
}) => {
  'id': id,
  'ticketNumber': number,
  'subject': subject,
  'category': category,
  'priority': priority,
  'status': status,
  'relatedOperationId': null,
  'lastActivityBy': 'SUPPORT',
  'createdAt': '2026-10-21T03:42:00.000Z',
  'updatedAt': '2026-10-21T04:10:00.000Z',
  'description': 'Sync has been stuck since yesterday evening.',
  'relatedModule': null,
  'resolvedAt': null,
  'canReply': canReply,
  'canClose': canClose,
  'attachments': <dynamic>[],
  'events': events.isEmpty
      ? [
          {'id': 'e1', 'type': 'CREATED', 'authorRole': 'USER', 'byViewer': true, 'createdAt': '2026-10-21T03:42:00.000Z'},
        ]
      : events,
};

class FakeTicketsApi implements TicketsApi {
  List<TicketSummary> tickets = [];
  ApiException? listError;
  final created = <Map<String, Object?>>[];
  ApiException? failNextCreate;
  TicketDetail? detail;
  final replies = <String>[];
  final uploads = <String>[];

  @override
  Future<TicketPage> list({required String storeId, TicketQuery query = const TicketQuery(), String? cursor}) async {
    if (listError != null) throw listError!;
    return TicketPage(tickets: tickets);
  }

  @override
  Future<TicketDetail> get({required String storeId, required String id}) async => detail!;

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
  }) async {
    created.add({
      'clientRequestId': clientRequestId,
      'subject': subject,
      'description': description,
      'category': category,
      'priority': priority,
      'relatedOperationId': relatedOperationId,
      'attachmentIds': attachmentIds,
    });
    if (failNextCreate != null) {
      final e = failNextCreate!;
      failNextCreate = null;
      throw e;
    }
    return TicketDetail.fromJson(_ticketJson(number: 'TKT-1042', priority: priority.wire, category: category.wire));
  }

  @override
  Future<TicketDetail> reply({required String storeId, required String id, required String clientRequestId, required String body}) async {
    replies.add(body);
    return TicketDetail.fromJson(_ticketJson(
      status: 'IN_PROGRESS',
      events: [
        {'id': 'e1', 'type': 'CREATED', 'authorRole': 'USER', 'byViewer': true, 'createdAt': '2026-10-21T03:42:00.000Z'},
        {'id': 'e2', 'type': 'MESSAGE', 'authorRole': 'USER', 'byViewer': true, 'body': body, 'createdAt': '2026-10-21T04:20:00.000Z'},
      ],
    ));
  }

  @override
  Future<TicketDetail> close({required String storeId, required String id}) async =>
      TicketDetail.fromJson(_ticketJson(status: 'CLOSED', canReply: false, canClose: false));

  @override
  Future<TicketAttachment> upload({required String storeId, required List<int> bytes, required String fileName}) async {
    uploads.add(fileName);
    return TicketAttachment.fromJson({'id': 'att1', 'fileName': fileName, 'contentType': 'image/png', 'size': bytes.length});
  }
}

class FakePicker implements AttachmentPicker {
  PickedFile? next;
  @override
  Future<PickedFile?> pick() async => next;
}

void main() {
  setUpAll(useEnglish);
  late AppDatabase db;
  late FakeTicketsApi api;
  late FakeConnectivity net;
  late FakePicker picker;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    api = FakeTicketsApi();
    net = FakeConnectivity();
    picker = FakePicker();
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        connectivityProvider.overrideWithValue(net),
        authSessionProvider.overrideWithValue(FakeSession()),
        ticketsApiProvider.overrideWithValue(api),
        attachmentPickerProvider.overrideWithValue(picker),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: screen),
    ));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  group('list (G)', () {
    testWidgets('G2 empty → create prompt', (tester) async {
      await pump(tester, const TicketsListScreen());
      expect(find.text('No support tickets yet'), findsOneWidget);
      expect(find.text('Create ticket'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('G1 populated rows, reply-needed badge', (tester) async {
      api.tickets = [
        TicketSummary.fromJson(_ticketJson(number: 'TKT-1041', status: 'IN_PROGRESS')),
        TicketSummary.fromJson(_ticketJson(id: 't2', number: 'TKT-1038', category: 'BUG', priority: 'NORMAL', status: 'WAITING_FOR_USER', subject: 'Login page slow')),
      ];
      await pump(tester, const TicketsListScreen());
      expect(find.text('TKT-1041 · Sync'), findsOneWidget);
      expect(find.text('TKT-1038 · Bug'), findsOneWidget);
      expect(find.textContaining('High · In progress · Updated'), findsOneWidget);
      expect(find.text('Reply needed'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('G4 error → retry', (tester) async {
      api.listError = const ApiNetworkException('NETWORK_UNAVAILABLE', 'x', isTimeout: false);
      await pump(tester, const TicketsListScreen());
      expect(find.text('Couldn\'t load tickets'), findsOneWidget);
      expect(find.textContaining('Drafts you started are kept'), findsOneWidget);
      api.listError = null;
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(find.text('No support tickets yet'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('create (H)', () {
    Finder field(String hintOrIndex) => find.byType(TextField);

    testWidgets('H2 validation errors only after submit', (tester) async {
      await pump(tester, const CreateTicketScreen());
      expect(find.text('Subject must be at least 3 characters.'), findsNothing);
      await tester.enterText(field('').at(0), 'Hi');
      await tester.enterText(field('').at(1), 'Broken');
      await tester.tap(find.text('Submit ticket'));
      await settle(tester);
      expect(find.text('Subject must be at least 3 characters.'), findsOneWidget);
      expect(find.text('Description must be at least 10 characters.'), findsOneWidget);
      expect(find.text('Choose a category.'), findsOneWidget);
      expect(api.created, isEmpty);
      await unmount(tester);
    });

    testWidgets('opened from an error: operation + Sync category prefilled; retry after timeout reuses the request id; H4 success', (tester) async {
      const opId = '7f3a1234-5678-4abc-8def-1234567890c9';
      await pump(tester, const CreateTicketScreen(relatedOperationId: opId, relatedModule: 'inventory'));
      expect(find.textContaining('op_7f3a…0c9'), findsOneWidget);
      expect(find.text('Sync'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), '  Sync stuck at 3 of 8  ');
      await tester.enterText(find.byType(TextField).at(1), 'Outbox has not cleared after reconnect.');
      api.failNextCreate = const ApiNetworkException('NETWORK_TIMEOUT', 'timeout', isTimeout: true);
      await tester.tap(find.text('Submit ticket'));
      await settle(tester);
      expect(find.textContaining('Your draft is saved'), findsOneWidget);

      await tester.tap(find.text('Submit ticket'));
      await settle(tester);
      expect(api.created, hasLength(2));
      expect(api.created[0]['clientRequestId'], api.created[1]['clientRequestId']);
      expect(api.created[1]['subject'], 'Sync stuck at 3 of 8');
      expect(api.created[1]['relatedOperationId'], opId);
      expect(api.created[1]['category'], TicketCategory.sync);

      expect(find.text('Ticket TKT-1042 created'), findsOneWidget);
      expect(find.text('Status: Open · Priority: Normal · Category: Sync'), findsOneWidget);
      expect(await db.outboxDao.readMeta('ticket_draft'), '', reason: 'draft cleared after success');
      await unmount(tester);
    });

    testWidgets('draft survives leaving the screen; discard clears it', (tester) async {
      await pump(tester, const CreateTicketScreen());
      await tester.enterText(find.byType(TextField).at(0), 'Printer offline');
      await settle(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500))); // debounce
      await unmount(tester);

      await pump(tester, const CreateTicketScreen());
      expect(find.text('Printer offline'), findsOneWidget);

      final state = tester.state<NavigatorState>(find.byType(Navigator));
      state.maybePop();
      await settle(tester);
      expect(find.text('Discard this ticket?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await settle(tester);
      expect(await db.outboxDao.readMeta('ticket_draft'), '');
      await unmount(tester);
    });

    testWidgets('offline submit keeps the draft and sends nothing', (tester) async {
      net.online = false;
      await pump(tester, const CreateTicketScreen());
      await tester.enterText(find.byType(TextField).at(0), 'Cannot sync today');
      await tester.enterText(find.byType(TextField).at(1), 'Nothing syncs since the morning.');
      await tester.tap(find.byType(DropdownButtonFormField<TicketCategory>));
      await settle(tester);
      await tester.tap(find.text('Sync').last);
      await settle(tester);
      await tester.ensureVisible(find.text('Submit ticket'));
      await tester.tap(find.text('Submit ticket'));
      await settle(tester);
      expect(api.created, isEmpty);
      expect(find.textContaining('You\'re offline'), findsWidgets);
      expect(await db.outboxDao.readMeta('ticket_draft'), contains('Cannot sync today'));
      await unmount(tester);
    });

    testWidgets('attachments: wrong type rejected locally, PNG uploaded and referenced', (tester) async {
      await pump(tester, const CreateTicketScreen());
      picker.next = PickedFile(name: 'setup.exe', size: 10, bytes: Uint8List(10));
      await tester.ensureVisible(find.textContaining('Add file'));
      await tester.tap(find.textContaining('Add file'));
      await settle(tester);
      expect(find.text('Only PDF, JPG and PNG files can be attached.'), findsOneWidget);
      expect(api.uploads, isEmpty);

      picker.next = PickedFile(name: 'screen.png', size: 2048, bytes: Uint8List(2048));
      await tester.tap(find.textContaining('Add file'));
      await settle(tester);
      expect(api.uploads, ['screen.png']);
      expect(find.text('screen.png'), findsOneWidget);
      expect(find.text('2 KB'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('detail (I)', () {
    testWidgets('I2 waiting for user: banner, reply moves it on', (tester) async {
      api.detail = TicketDetail.fromJson(_ticketJson(
        number: 'TKT-1038',
        status: 'WAITING_FOR_USER',
        events: [
          {'id': 'e1', 'type': 'CREATED', 'authorRole': 'USER', 'byViewer': true, 'createdAt': '2026-10-21T03:42:00.000Z'},
          {'id': 'e2', 'type': 'MESSAGE', 'authorRole': 'SUPPORT', 'byViewer': false, 'body': 'Which screen were you on?', 'createdAt': '2026-10-21T04:02:00.000Z'},
        ],
      ));
      await pump(tester, const TicketDetailScreen(ticketId: 't1'));
      expect(find.text('TKT-1038'), findsOneWidget);
      expect(find.text('Support needs more information. Reply to continue.'), findsOneWidget);
      expect(find.textContaining('Support ·'), findsOneWidget);
      expect(find.text('Which screen were you on?'), findsOneWidget);
      expect(find.text('Sync has been stuck since yesterday evening.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'The sales screen, code E42.');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await settle(tester);
      expect(api.replies, ['The sales screen, code E42.']);
      expect(find.text('Support needs more information. Reply to continue.'), findsNothing);
      expect(find.text('The sales screen, code E42.'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('closed ticket: no composer, offers a new ticket', (tester) async {
      api.detail = TicketDetail.fromJson(_ticketJson(status: 'CLOSED', canReply: false, canClose: false));
      await pump(tester, const TicketDetailScreen(ticketId: 't1'));
      expect(find.text('Write a reply…'), findsNothing);
      expect(find.text('This ticket is closed. Create a new ticket if you need more help.'), findsOneWidget);
      await unmount(tester);
    });
  });
}
