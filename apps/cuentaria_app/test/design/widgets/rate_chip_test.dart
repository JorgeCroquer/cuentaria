import 'package:cuentaria_app/design/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  testWidgets('shows the name and the value (value + age, preformatted)', (
    tester,
  ) async {
    await pump(
      tester,
      const RateChip(
        name: 'Paralelo',
        value: '846.50 VES/USD · hace 3 h',
        valueKey: Key('rateValue'),
      ),
    );

    expect(find.text('Paralelo '), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('rateValue'))).data,
      '846.50 VES/USD · hace 3 h',
    );
  });

  testWidgets('has an outlined border colored outlineVariant', (tester) async {
    await pump(
      tester,
      const RateChip(name: 'BCV', value: '700.00 VES/USD · hoy'),
    );

    final chip = tester.widget<Chip>(find.byType(Chip));
    final context = tester.element(find.byType(Chip));
    final shape = chip.shape as StadiumBorder;
    expect(shape.side.color, Theme.of(context).colorScheme.outlineVariant);
  });

  testWidgets('paints the name in primary when isPrimary is true', (
    tester,
  ) async {
    await pump(
      tester,
      const RateChip(
        name: 'Paralelo',
        value: '846.50 VES/USD · hoy',
        isPrimary: true,
      ),
    );

    final nameText = tester.widget<Text>(find.text('Paralelo '));
    final context = tester.element(find.text('Paralelo '));
    expect(nameText.style?.color, Theme.of(context).colorScheme.primary);
  });
}
