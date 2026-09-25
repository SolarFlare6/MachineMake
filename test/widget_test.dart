import 'package:flutter_test/flutter_test.dart';
import 'package:machmake2/main.dart';

void main() {
  testWidgets('MachineMakeApp renders WelcomeScreen cleanly', (WidgetTester tester) async {
    await tester.pumpWidget(const MachineMakeApp());
    expect(find.text('Scan for devices'), findsOneWidget);
  });
}
