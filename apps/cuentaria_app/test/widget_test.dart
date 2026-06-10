import 'package:flutter_test/flutter_test.dart';

import 'package:cuentaria_app/main.dart';

void main() {
  testWidgets('App boots and shows placeholder screen', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that our placeholder text is present.
    expect(find.text('Cuentaria MVP'), findsWidgets);
  });
}
