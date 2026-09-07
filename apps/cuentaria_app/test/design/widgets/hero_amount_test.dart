import 'package:cuentaria_app/design/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  testWidgets('renders the label in bodySmall and the amount in displaySmall', (
    tester,
  ) async {
    await pump(
      tester,
      const HeroAmount(
        label: 'Valor hoy (paralelo)',
        amount: '\$1,234.56',
        amountKey: Key('heroAmount'),
      ),
    );

    final context = tester.element(find.byKey(const Key('heroAmount')));
    final textTheme = Theme.of(context).textTheme;

    final labelText = tester.widget<Text>(find.text('Valor hoy (paralelo)'));
    expect(
      labelText.style?.color,
      Theme.of(context).colorScheme.onSurfaceVariant,
    );
    expect(labelText.style?.fontSize, textTheme.bodySmall?.fontSize);

    final amountText = tester.widget<Text>(find.byKey(const Key('heroAmount')));
    expect(amountText.data, '\$1,234.56');
    expect(amountText.style?.fontSize, textTheme.displaySmall?.fontSize);
  });

  testWidgets('renders no secondary line when none is given', (tester) async {
    await pump(tester, const HeroAmount(label: 'Valor hoy', amount: '\$0.00'));

    expect(find.byKey(const Key('secondaryLine')), findsNothing);
  });

  testWidgets('renders the secondary line when given', (tester) async {
    await pump(
      tester,
      const HeroAmount(
        label: 'Valor hoy',
        amount: '\$0.00',
        secondaryLine: Text('Costo real \$0.00', key: Key('secondaryLine')),
      ),
    );

    expect(find.byKey(const Key('secondaryLine')), findsOneWidget);
    expect(find.text('Costo real \$0.00'), findsOneWidget);
  });
}
