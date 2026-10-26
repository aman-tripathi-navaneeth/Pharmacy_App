import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/main.dart';
void main() {
  testWidgets(
    'Pharmacy app displays home screen and navigation',
    (WidgetTester tester) async {
      await tester.pumpWidget(const PharmacyApp());

      expect(find.text('Pharmacy Store'), findsOneWidget);
      expect(find.text('Pharmacy App'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Expiry'), findsOneWidget);
      expect(find.text('Low Stock'), findsOneWidget);
      expect(find.text('Reconcile'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    },
  );
}