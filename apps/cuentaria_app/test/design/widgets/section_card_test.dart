import 'package:cuentaria_app/design/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  testWidgets('renders the header text in labelSmall', (tester) async {
    await pump(
      tester,
      const SectionCard(
        header: 'SOBRES',
        headerKey: Key('sectionHeader'),
        children: [Text('row 1')],
      ),
    );

    final context = tester.element(find.byKey(const Key('sectionHeader')));
    final headerText = tester.widget<Text>(
      find.byKey(const Key('sectionHeader')),
    );
    expect(headerText.data, 'SOBRES');
    expect(
      headerText.style?.fontSize,
      Theme.of(context).textTheme.labelSmall?.fontSize,
    );
  });

  testWidgets('renders every child row', (tester) async {
    await pump(
      tester,
      const SectionCard(
        header: 'CUENTAS',
        children: [Text('row 1'), Text('row 2')],
      ),
    );

    expect(find.text('row 1'), findsOneWidget);
    expect(find.text('row 2'), findsOneWidget);
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('renders dividers between rows when showDividers is true', (
    tester,
  ) async {
    await pump(
      tester,
      const SectionCard(
        header: 'CUENTAS',
        showDividers: true,
        children: [Text('row 1'), Text('row 2'), Text('row 3')],
      ),
    );

    expect(find.byType(Divider), findsNWidgets(2));
  });
}
