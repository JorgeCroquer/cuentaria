import 'package:contabilidad/application/cascade/cascade_codec.dart';
import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

void main() {
  group('CascadeCodec', () {
    test(
      'round-trips a cascade mixing the 4 old variants and fixedUntilCap',
      () {
        final steps = [
          CascadeStep.fixed(envelopeId: EnvelopeId('e1'), amountUsd: 30000),
          CascadeStep.fillToCap(envelopeId: EnvelopeId('e2')),
          CascadeStep.fixedUntilCap(
            envelopeId: EnvelopeId('e3'),
            amountUsd: 5000,
          ),
          CascadeStep.percentOfRemainder(
            envelopeId: EnvelopeId('e4'),
            percent: Decimal.parse('0.2'),
            base: PercentBase.remainder,
          ),
          CascadeStep.catchAll(envelopeId: EnvelopeId('e5')),
        ];

        final json = CascadeCodec.stepsToJson(steps);
        final decoded = CascadeCodec.stepsFromJson(json);

        expect(decoded, hasLength(5));
        expect(decoded[0], isA<FixedStep>());
        expect((decoded[0] as FixedStep).amountUsd, 30000);
        expect(decoded[1], isA<FillToCapStep>());
        expect(decoded[2], isA<FixedUntilCapStep>());
        expect((decoded[2] as FixedUntilCapStep).amountUsd, 5000);
        expect((decoded[2] as FixedUntilCapStep).envelopeId, EnvelopeId('e3'));
        expect(decoded[3], isA<PercentOfRemainderStep>());
        expect(decoded[4], isA<CatchAllStep>());
      },
    );

    test('serializes fixedUntilCap with its own JSON type', () {
      final json = CascadeCodec.stepsToJson([
        CascadeStep.fixedUntilCap(
          envelopeId: EnvelopeId('e1'),
          amountUsd: 4200,
        ),
      ]);
      expect(json.single['type'], 'fixed_until_cap');
      expect(json.single['amount_usd'], 4200);
      expect(json.single['envelope_id'], 'e1');
    });

    test('unknown step type still throws (unchanged behaviour)', () {
      expect(
        () => CascadeCodec.stepsFromJson([
          {'type': 'nonexistent', 'envelope_id': 'e1'},
        ]),
        throwsFormatException,
      );
    });
  });
}
