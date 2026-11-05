// Tests for the Today screen, M1 welcome/legal screens, M5 inventory, and M6 navigation.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:pharmacy_app/data/api_client.dart';
import 'package:pharmacy_app/features/dashboard/screens/purchases_screen.dart';
import 'package:pharmacy_app/features/dashboard/screens/today_screen.dart';
import 'package:pharmacy_app/main.dart';
import 'package:pharmacy_app/screens/legal_information_screen.dart';
import 'package:pharmacy_app/screens/login_screen.dart';

const String sampleTodayJson = '''
{
  "generated_at": "2026-10-19T18:40:00+05:30",
  "counts": {"urgent": 4, "soon": 5, "routine": 4, "snoozed": 0, "done_today": 0},
  "glance": {
    "expiring_30_days_value_paise": 842000,
    "items_below_minimum": 11,
    "credit_to_collect_paise": 2376000
  },
  "tasks": [
    {
      "key": "low_stock:med_telma40",
      "category": "low_stock",
      "urgency": "urgent",
      "score": 160.0,
      "title": "Telma 40 out of stock",
      "detail": "Out of stock. Sold 14 strips last week.",
      "reason": "Out of stock",
      "value_paise": 300000,
      "source": "Inventory",
      "state": "open",
      "action": {"type": "reorder", "label": "Reorder", "target": "app://orders/new?medicine_id=med_telma40"}
    }
  ],
  "source_status": [
    {"source": "inventory", "ok": true},
    {"source": "credit", "ok": false, "error": "timeout"}
  ]
}
''';

http.Client _stubClient({int statusCode = 200, int actionStatusCode = 200}) {
  return http_testing.MockClient((http.Request request) async {
    final String path = request.url.path;
    if (path.endsWith('/dashboard/today')) {
      return http.Response(
        sampleTodayJson,
        statusCode,
        headers: <String, String>{'content-type': 'application/json'},
      );
    }
    if (path.contains('/tasks/')) {
      return http.Response(
        '{"task_key": "low_stock:med_telma40", "status": "snoozed"}',
        actionStatusCode,
        headers: <String, String>{'content-type': 'application/json'},
      );
    }
    return http.Response('{"detail": "Not Found"}', 404);
  });
}

TodayScreen _screen({int todayStatus = 200}) => TodayScreen(
  apiClient: ApiClient(client: _stubClient(statusCode: todayStatus)),
);

void main() {
  testWidgets(
    'shows ranked tasks, counts and partial-failure banner from the API',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: _screen()));
      await tester.pumpAndSettle();

      expect(find.text('Telma 40 out of stock'), findsOneWidget);
      expect(
        find.text('Out of stock. Sold 14 strips last week.'),
        findsOneWidget,
      );
      expect(find.text('Out of stock'), findsOneWidget);
      expect(find.text('4 Urgent'), findsOneWidget);
      expect(find.text('5 Soon'), findsOneWidget);
      expect(find.text('4 Routine'), findsOneWidget);
      expect(
        find.textContaining('credit could not load'),
        findsNothing,
      );
      expect(find.textContaining('Credit could not load'), findsOneWidget);
      expect(find.text('₹8,420'), findsOneWidget);
      expect(find.text('₹23,760'), findsOneWidget);
      expect(find.text('All 13'), findsOneWidget);
      expect(find.text('Low stock 1'), findsOneWidget);
    },
  );

  testWidgets('shows the error state with try-again when the API fails', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: _screen(todayStatus: 500)));
    await tester.pumpAndSettle();

    expect(find.text("Could not load today's tasks"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('retry reloads today tasks without a setState callback error', (
    WidgetTester tester,
  ) async {
    int requests = 0;
    final http.Client client = http_testing.MockClient((
      http.Request request,
    ) async {
      requests++;
      return http.Response(
        sampleTodayJson,
        requests == 1 ? 500 : 200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: TodayScreen(apiClient: ApiClient(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Could not load today's tasks"), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(requests, 2);
    expect(find.text('Telma 40 out of stock'), findsOneWidget);
  });

  testWidgets('shows an error when a task action fails', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: TodayScreen(
          apiClient: ApiClient(client: _stubClient(actionStatusCode: 500)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark done'));
    await tester.pumpAndSettle();

    expect(find.text('Mark done failed'), findsOneWidget);
  });

  test('formats paise without rounding them away', () {
    expect(formatRupees(425050), '₹4,250.50');
    expect(formatRupees(-125), '-₹1.25');
    expect(formatRupees(425000), '₹4,250');
  });

  test('purchase search query is URL encoded and pagination is sent', () async {
    Uri? requestedUri;
    final ApiClient client = ApiClient(
      client: http_testing.MockClient((http.Request request) async {
        requestedUri = request.url;
        return http.Response(
          '{"available":true,"rows":[],"total_count":123,"total_paise":0}',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final PurchaseRegisterResponse response = await client
        .fetchPurchaseRegister(
          'demo-store',
          q: 'ACME & Sons',
          limit: 25,
          offset: 50,
        );

    expect(requestedUri!.queryParameters['q'], 'ACME & Sons');
    expect(requestedUri!.queryParameters['limit'], '25');
    expect(requestedUri!.queryParameters['offset'], '50');
    expect(response.totalCount, 123);
  });

  testWidgets('purchase CSV escapes commas, quotes, and line breaks', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final ApiClient client = ApiClient(
      client: http_testing.MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'available': true,
            'rows': <dynamic>[
              <String, dynamic>{
                'invoice_id': '1',
                'invoice_no': 'INV-1',
                'invoice_date': '2026-10-10',
                'supplier': 'Supplier, "Prime"\nWest',
                'total_paise': 1234,
                'item_count': 0,
              },
            ],
            'total_paise': 1234,
            'total_count': 1,
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(home: PurchasesScreen(apiClient: client)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Copy page as CSV'));
    await tester.tap(find.text('Copy page as CSV'));
    await tester.pumpAndSettle();

    expect(
      copiedText,
      contains('"2026-10-10","INV-1","Supplier, ""Prime""\nWest","12.34"'),
    );
  });

  test('trend API error is surfaced instead of rendered as an empty trend', () {
    final ApiClient client = ApiClient(
      client: http_testing.MockClient((http.Request request) async {
        return http.Response(
          '{"points":[],"error":"Could not read trend data"}',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    expect(client.fetchTrend('demo-store'), throwsA(isA<ApiException>()));
  });

  testWidgets('urgency buttons filter tasks to the matching urgency', (
    WidgetTester tester,
  ) async {
    final http.Client multiClient = http_testing.MockClient((
      http.Request request,
    ) async {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'generated_at': '2026-10-19T18:40:00+05:30',
          'counts': <String, int>{
            'urgent': 1,
            'soon': 1,
            'routine': 0,
            'snoozed': 0,
            'done_today': 0,
          },
          'glance': <String, dynamic>{},
          'tasks': <dynamic>[
            <String, dynamic>{
              'key': 'low_stock:med_telma40',
              'category': 'low_stock',
              'urgency': 'urgent',
              'score': 160.0,
              'title': 'Telma 40 out of stock',
              'detail': 'Out of stock.',
              'reason': 'Out of stock',
              'value_paise': 300000,
              'source': 'Inventory',
              'state': 'open',
              'action': <String, String>{
                'type': 'reorder',
                'label': 'Reorder',
                'target': 'app://orders/new',
              },
            },
            <String, dynamic>{
              'key': 'refill:c1',
              'category': 'refill',
              'urgency': 'soon',
              'score': 60.0,
              'title': 'Refill due for Lakshmi',
              'detail': 'Due in 2 days.',
              'reason': 'Due soon',
              'value_paise': 0,
              'source': 'Refills',
              'state': 'open',
              'action': <String, String>{
                'type': 'remind',
                'label': 'Remind',
                'target': 'app://refills/c1',
              },
            },
          ],
          'source_status': <dynamic>[],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TodayScreen(apiClient: ApiClient(client: multiClient)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Telma 40 out of stock'), findsOneWidget);
    expect(find.text('Refill due for Lakshmi'), findsOneWidget);

    await tester.tap(find.text('1 Urgent'));
    await tester.pumpAndSettle();
    expect(find.text('Telma 40 out of stock'), findsOneWidget);
    expect(find.text('Refill due for Lakshmi'), findsNothing);

    await tester.tap(find.text('1 Soon'));
    await tester.pumpAndSettle();
    expect(find.text('Telma 40 out of stock'), findsNothing);
    expect(find.text('Refill due for Lakshmi'), findsOneWidget);

    await tester.tap(find.text('0 Routine'));
    await tester.pumpAndSettle();
    expect(find.text('Telma 40 out of stock'), findsNothing);
    expect(find.text('Refill due for Lakshmi'), findsNothing);
    expect(find.text('No tasks in this filter.'), findsOneWidget);

    await tester.tap(find.text('0 Routine'));
    await tester.pumpAndSettle();
    expect(find.text('Telma 40 out of stock'), findsOneWidget);
    expect(find.text('Refill due for Lakshmi'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no tasks', (
    WidgetTester tester,
  ) async {
    final http.Client emptyClient = http_testing.MockClient((
      http.Request request,
    ) async {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'generated_at': '2026-10-19T18:40:00+05:30',
          'counts': <String, int>{
            'urgent': 0,
            'soon': 0,
            'routine': 0,
            'snoozed': 0,
            'done_today': 0,
          },
          'glance': <String, dynamic>{},
          'tasks': <dynamic>[],
          'source_status': <dynamic>[],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TodayScreen(apiClient: ApiClient(client: emptyClient)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All clear for today'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('Pharmacy app displays home screen and navigation',
      (WidgetTester tester) async {
    await tester.pumpWidget(const PharmacyApp(home: PharmacyHome()));
    await tester.pumpAndSettle();

    expect(find.text('Pharmacy Store'), findsWidgets);
    expect(find.text('Pharmacy App'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Expiry'), findsOneWidget);
    expect(find.text('Low Stock'), findsOneWidget);
    expect(find.text('Reconcile'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('M1 welcome screen opens sign in', (WidgetTester tester) async {
    await tester.pumpWidget(const PharmacyApp());
    await tester.pumpAndSettle();

    expect(find.text('MediManage'), findsOneWidget);
    expect(find.text('Your pharmacy, in one place'), findsOneWidget);

    await tester.ensureVisible(find.text('Get Started'));
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('welcome screen opens both legal documents', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const PharmacyApp());

    await tester.ensureVisible(find.text('Terms of Use'));
    await tester.tap(find.text('Terms of Use'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is LegalInformationScreen &&
            widget.document == LegalDocument.terms,
      ),
      findsOneWidget,
    );
    expect(find.text('Rules for using MediManage'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Records and regulated work'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Records and regulated work'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Privacy Policy'));
    await tester.tap(find.text('Privacy Policy'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is LegalInformationScreen &&
            widget.document == LegalDocument.privacy,
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Business, customer, and prescription records'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Business, customer, and prescription records'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('privacy policy remains usable on a narrow viewport', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: LegalInformationScreen(document: LegalDocument.privacy),
      ),
    );

    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Information the application handles'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Business, customer, and prescription records'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Business, customer, and prescription records'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pharmacy app modular view & Module 5 inventory smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PharmacyApp(home: Module5InventoryScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Pharmacy Store'), findsWidgets);
    expect(find.text('• Module 5'), findsOneWidget);

    expect(find.text('Balances'), findsOneWidget);
    expect(find.text('Batches (FEFO)'), findsOneWidget);
    expect(find.text('Ledger'), findsOneWidget);

    expect(find.text('In-Stock Units'), findsOneWidget);
    expect(find.text('Active Batches'), findsOneWidget);
  });
}
