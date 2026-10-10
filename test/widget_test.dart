import 'package:flutter_test/flutter_test.dart';
import 'package:masterdrinks/app.dart';

void main() {
  testWidgets('MasterDrinksApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MasterDrinksApp());
    expect(find.byType(MasterDrinksApp), findsOneWidget);
  });
}
