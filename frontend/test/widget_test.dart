import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/main.dart';

void main() {
  testWidgets('Pharmacy app blank mobile view smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PharmacyApp());

    // Verify that the title and welcome messages are present.
    expect(find.text('Pharmacy Store'), findsOneWidget);
    expect(find.text('Pharmacy App Ready'), findsOneWidget);
  });
}
