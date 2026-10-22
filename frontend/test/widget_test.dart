import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/main.dart';

void main() {
  testWidgets('Pharmacy app modular view & Module 5 inventory smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PharmacyApp());
    await tester.pumpAndSettle();

    // Verify Pharmacy Store title and Module 5 scope are present
    expect(find.text('Pharmacy Store'), findsWidgets);
    expect(find.text('• Module 5'), findsOneWidget);

    // Verify Balances, Batches (FEFO), and Ledger tabs are present
    expect(find.text('Balances'), findsOneWidget);
    expect(find.text('Batches (FEFO)'), findsOneWidget);
    expect(find.text('Ledger'), findsOneWidget);

    // Verify KPI metric cards are present
    expect(find.text('In-Stock Units'), findsOneWidget);
    expect(find.text('Active Batches'), findsOneWidget);
  });
}
