import 'package:cuentaria_app/design/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  testWidgets(
    'sits on colorScheme.secondaryContainer and shows title/subline',
    (tester) async {
      await pump(
        tester,
        const ActionCard(
          title: 'Sin asignar · \$10.00',
          subline: '+ \$5.00 de apertura por repartir',
          buttonLabel: 'Repartir',
        ),
      );

      final card = tester.widget<Card>(find.byType(Card));
      final context = tester.element(find.byType(Card));
      expect(card.color, Theme.of(context).colorScheme.secondaryContainer);
      expect(find.text('Sin asignar · \$10.00'), findsOneWidget);
      expect(find.text('+ \$5.00 de apertura por repartir'), findsOneWidget);
    },
  );

  testWidgets('fires onButtonPressed when the FilledButton is tapped', (
    tester,
  ) async {
    var tapped = false;
    await pump(
      tester,
      ActionCard(
        title: 'Sin asignar',
        buttonLabel: 'Repartir',
        buttonKey: const Key('actionButton'),
        onButtonPressed: () => tapped = true,
      ),
    );

    await tester.tap(find.byKey(const Key('actionButton')));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('fires onSublineTap when the subline is tapped', (tester) async {
    var tapped = false;
    await pump(
      tester,
      ActionCard(
        subline: 'de apertura por repartir',
        sublineKey: const Key('subline'),
        onSublineTap: () => tapped = true,
      ),
    );

    await tester.tap(find.byKey(const Key('subline')));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('omits the button when buttonLabel is null', (tester) async {
    await pump(tester, const ActionCard(title: 'Sin asignar'));

    expect(find.byType(FilledButton), findsNothing);
  });
}
