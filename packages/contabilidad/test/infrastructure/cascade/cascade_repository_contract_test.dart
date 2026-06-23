/// Contract/parity suite: same behaviours must hold for every [CascadeRepository]
/// implementation.  Run against [InMemoryCascadeRepository] and
/// [DriftCascadeRepository] (using an in-memory SQLite executor).
library;

import 'package:contabilidad/application/cascade/cascade.dart';
import 'package:contabilidad/application/cascade/cascade_repository.dart';
import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:contabilidad/infrastructure/cascade/drift_cascade_repository.dart';
import 'package:contabilidad/infrastructure/cascade/in_memory_cascade_repository.dart';
import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

import '../catalog/test_helpers.dart';

// ---------------------------------------------------------------------------
// Factories
// ---------------------------------------------------------------------------

CascadeRepository _inMemory() => InMemoryCascadeRepository();

Future<CascadeRepository> _drift() async {
  final db = openTestDb();
  final repo = DriftCascadeRepository(db);
  await repo.hydrate();
  return repo;
}

// ---------------------------------------------------------------------------
// Contract suite
// ---------------------------------------------------------------------------

void _runContractSuite(
  String label,
  Future<CascadeRepository> Function() factory,
) {
  group('CascadeRepository contract — $label', () {
    late CascadeRepository repo;

    setUp(() async {
      repo = await factory();
    });

    test('load returns null before any save', () async {
      expect(await repo.load(), isNull);
    });

    test(
      'save and load round-trip preserves step order and parameters',
      () async {
        final envA = EnvelopeId('env-a');
        final envB = EnvelopeId('env-b');
        final envC = EnvelopeId('env-c');
        final envD = EnvelopeId('env-d');

        final cascade = Cascade(
          steps: [
            CascadeStep.fixed(envelopeId: envA, amountUsd: 30000),
            CascadeStep.fillToCap(envelopeId: envB),
            CascadeStep.percentOfRemainder(
              envelopeId: envC,
              percent: Decimal.parse('0.2'),
              base: PercentBase.remainder,
            ),
            CascadeStep.catchAll(envelopeId: envD),
          ],
          updatedAt: DateTime.utc(2024, 6, 1),
        );

        await repo.save(cascade);
        final loaded = await repo.load();

        expect(loaded, isNotNull);
        expect(loaded!.steps, hasLength(4));
        expect(loaded.steps[0], isA<FixedStep>());
        expect((loaded.steps[0] as FixedStep).amountUsd, 30000);
        expect((loaded.steps[0] as FixedStep).envelopeId, envA);
        expect(loaded.steps[1], isA<FillToCapStep>());
        expect((loaded.steps[1] as FillToCapStep).envelopeId, envB);
        expect(loaded.steps[2], isA<PercentOfRemainderStep>());
        final pct = loaded.steps[2] as PercentOfRemainderStep;
        expect(pct.envelopeId, envC);
        expect(pct.percent, Decimal.parse('0.2'));
        expect(pct.base, PercentBase.remainder);
        expect(loaded.steps[3], isA<CatchAllStep>());
        expect((loaded.steps[3] as CatchAllStep).envelopeId, envD);
      },
    );

    test('percent base gross is preserved', () async {
      final cascade = Cascade(
        steps: [
          CascadeStep.percentOfRemainder(
            envelopeId: EnvelopeId('env-x'),
            percent: Decimal.parse('0.5'),
            base: PercentBase.gross,
          ),
        ],
        updatedAt: DateTime.utc(2024, 6, 1),
      );
      await repo.save(cascade);
      final loaded = await repo.load();
      final step = loaded!.steps[0] as PercentOfRemainderStep;
      expect(step.base, PercentBase.gross);
    });

    test('LWW: newer updatedAt wins', () async {
      final t0 = DateTime.utc(2024, 1, 1);
      final t1 = DateTime.utc(2024, 1, 2);

      await repo.save(
        Cascade(
          steps: [
            CascadeStep.fixed(envelopeId: EnvelopeId('e1'), amountUsd: 100),
          ],
          updatedAt: t0,
        ),
      );
      await repo.save(
        Cascade(
          steps: [
            CascadeStep.fixed(envelopeId: EnvelopeId('e1'), amountUsd: 999),
          ],
          updatedAt: t1,
        ),
      );

      final loaded = await repo.load();
      expect((loaded!.steps[0] as FixedStep).amountUsd, 999);
    });

    test('LWW: older updatedAt does not overwrite', () async {
      final t0 = DateTime.utc(2024, 1, 1);
      final t1 = DateTime.utc(2024, 1, 2);

      await repo.save(
        Cascade(
          steps: [
            CascadeStep.fixed(envelopeId: EnvelopeId('e1'), amountUsd: 999),
          ],
          updatedAt: t1,
        ),
      );
      await repo.save(
        Cascade(
          steps: [
            CascadeStep.fixed(envelopeId: EnvelopeId('e1'), amountUsd: 1),
          ],
          updatedAt: t0,
        ),
      );

      final loaded = await repo.load();
      expect((loaded!.steps[0] as FixedStep).amountUsd, 999);
    });

    test('updatedAt round-trips correctly', () async {
      final ts = DateTime.utc(2025, 3, 15, 12, 30, 0);
      await repo.save(Cascade(steps: [], updatedAt: ts));
      final loaded = await repo.load();
      expect(loaded!.updatedAt, ts);
    });

    test('empty steps list round-trips', () async {
      await repo.save(Cascade(steps: [], updatedAt: DateTime.utc(2024, 1, 1)));
      final loaded = await repo.load();
      expect(loaded!.steps, isEmpty);
    });
  });
}

void main() {
  _runContractSuite('InMemoryCascadeRepository', () async => _inMemory());
  _runContractSuite('DriftCascadeRepository', _drift);
}
