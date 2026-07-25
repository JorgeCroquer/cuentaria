import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:cuentaria_app/features/distribution/ui/widgets/cascade_step_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

Envelope _envelope(String id) => Envelope(
  id: EnvelopeId(id),
  name: id,
  role: EnvelopeRole.none,
  isArchived: false,
  updatedAt: DateTime.now(),
);

Future<CascadeStep?> _buildStep(
  WidgetTester tester, {
  required Envelope envelope,
  required String fundingType,
  String? amount,
  String? percent,
}) async {
  CascadeStep? built;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder:
            (context) => ElevatedButton(
              onPressed: () async {
                built = await showDialog<CascadeStep>(
                  context: context,
                  builder: (context) => CascadeStepForm(envelopes: [envelope]),
                );
              },
              child: const Text('open'),
            ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('stepFundingTypeDropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(fundingType).last);
  await tester.pumpAndSettle();

  if (amount != null) {
    await tester.enterText(find.byKey(const Key('stepAmountField')), amount);
  }
  if (percent != null) {
    await tester.enterText(find.byKey(const Key('stepPercentField')), percent);
  }

  await tester.tap(find.byKey(const Key('saveStepButton')));
  await tester.pumpAndSettle();
  return built;
}

void main() {
  group('percent field round-trips through Decimal, never double (#96)', () {
    for (final input in [
      '99.99',
      '66.67',
      '33.33',
      '10.1',
      '0.1',
      '12.5',
      '50',
    ]) {
      testWidgets('$input: typed -> stored -> redisplayed unchanged', (
        tester,
      ) async {
        final envelope = _envelope('mercado');

        final step = await _buildStep(
          tester,
          envelope: envelope,
          fundingType: '% of remainder',
          percent: input,
        );

        expect(step, isA<PercentOfRemainderStep>());

        await tester.pumpWidget(
          MaterialApp(
            home: CascadeStepForm(envelopes: [envelope], existing: step),
          ),
        );
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(
          find.byKey(const Key('stepPercentField')),
        );
        expect(field.controller!.text, input);
      });
    }
  });

  testWidgets(
    'fixed amount field round-trips through Decimal, never double (#96)',
    (tester) async {
      final envelope = _envelope('mercado');

      final step = await _buildStep(
        tester,
        envelope: envelope,
        fundingType: 'Fixed amount',
        amount: '99.99',
      );

      expect(step, isA<FixedStep>());
      expect((step as FixedStep).amountUsd, 9999);
    },
  );
}
