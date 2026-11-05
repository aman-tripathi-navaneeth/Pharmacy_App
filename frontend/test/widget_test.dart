import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/main.dart';
import 'package:pharmacy_app/screens/legal_information_screen.dart';
import 'package:pharmacy_app/screens/login_screen.dart';

void main() {
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
