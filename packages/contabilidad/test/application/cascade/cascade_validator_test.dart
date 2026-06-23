/// Unit tests for [CascadeValidator] — edit-time validation rules (ADR-0015 §3).
library;

import 'package:contabilidad/application/cascade/cascade.dart';
import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:contabilidad/application/cascade/cascade_validator.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/funding_target.dart';
import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _t0 = DateTime.utc(2024, 1, 1);

Envelope _userEnv(String id, {bool archived = false, FundingTarget? target}) {
  var e = Envelope(
    id: EnvelopeId(id),
    name: id,
    role: EnvelopeRole.none,
    isArchived: archived,
    updatedAt: _t0,
  );
  if (target != null) e = e.withTarget(target);
  return e;
}

Envelope _systemEnv(String id) => Envelope(
  id: EnvelopeId(id),
  name: id,
  role: EnvelopeRole.stage,
  isArchived: false,
  updatedAt: _t0,
);

Map<EnvelopeId, Envelope> _catalog(List<Envelope> envs) => {
  for (final e in envs) e.id: e,
};

Cascade _cascade(List<CascadeStep> steps) =>
    Cascade(steps: steps, updatedAt: _t0);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('CascadeValidator', () {
    group('valid cascade — no errors', () {
      test('single fixed step', () {
        final catalog = _catalog([_userEnv('e1')]);
        final result = CascadeValidator.validate(
          cascade: _cascade([
            CascadeStep.fixed(envelopeId: EnvelopeId('e1'), amountUsd: 100),
          ]),
          catalog: catalog,
        );
        expect(result.errors, isEmpty);
        expect(result.warnings, isEmpty);
      });

      test('all step types valid', () {
        final catalog = _catalog([
          _userEnv('e1'),
          _userEnv('e2', target: const Cap(amountUsd: 20000)),
          _userEnv('e3'),
          _userEnv('e4'),
        ]);
        final result = CascadeValidator.validate(
          cascade: _cascade([
            CascadeStep.fixed(envelopeId: EnvelopeId('e1'), amountUsd: 5000),
            CascadeStep.fillToCap(envelopeId: EnvelopeId('e2')),
            CascadeStep.percentOfRemainder(
              envelopeId: EnvelopeId('e3'),
              percent: Decimal.parse('0.2'),
              base: PercentBase.remainder,
            ),
            CascadeStep.catchAll(envelopeId: EnvelopeId('e4')),
          ]),
          catalog: catalog,
        );
        expect(result.errors, isEmpty);
        expect(result.warnings, isEmpty);
      });
    });

    group('catchAll position rules', () {
      test('two catchAll steps → error', () {
        final catalog = _catalog([_userEnv('e1'), _userEnv('e2')]);
        final result = CascadeValidator.validate(
          cascade: _cascade([
            CascadeStep.catchAll(envelopeId: EnvelopeId('e1')),
            CascadeStep.catchAll(envelopeId: EnvelopeId('e2')),
          ]),
          catalog: catalog,
        );
        expect(result.errors, isNotEmpty);
        expect(
          result.errors.any(
            (e) => e.contains('catch-all') || e.contains('catchAll'),
          ),
          isTrue,
        );
      });

      test('catchAll not last → error', () {
        final catalog = _catalog([_userEnv('e1'), _userEnv('e2')]);
        final result = CascadeValidator.validate(
          cascade: _cascade([
            CascadeStep.catchAll(envelopeId: EnvelopeId('e1')),
            CascadeStep.fixed(envelopeId: EnvelopeId('e2'), amountUsd: 100),
          ]),
          catalog: catalog,
        );
        expect(result.errors, isNotEmpty);
      });
    });

    group('fixed amount rules', () {
      test('fixed amount == 0 → error', () {
        final catalog = _catalog([_userEnv('e1')]);
        final result = CascadeValidator.validate(
          cascade: _cascade([
            CascadeStep.fixed(envelopeId: EnvelopeId('e1'), amountUsd: 0),
          ]),
          catalog: catalog,
        );
        expect(result.errors, isNotEmpty);
      });

      test('fixed amount negative → error', () {
        final catalog = _catalog([_userEnv('e1')]);
        final result = CascadeValidator.validate(
          cascade: _cascade([
            CascadeStep.fixed(envelopeId: EnvelopeId('e1'), amountUsd: -50),
          ]),
          catalog: catalog,
        );
        expect(result.errors, isNotEmpty);
      });
    });

    group('percent rules', () {
      test('percent == 0 → error', () {
        final catalog = _catalog([_userEnv('e1')]);
        final result = CascadeValidator.validate(
          cascade: _cascade([
            CascadeStep.percentOfRemainder(
              envelopeId: EnvelopeId('e1'),
              percent: Decimal.zero,
              base: PercentBase.remainder,
            ),
          ]),
          catalog: catalog,
        );
        expect(result.errors, isNotEmpty);
      });

      test('percent > 1 → error', () {
        final catalog = _catalog([_userEnv('e1')]);
        final result = CascadeValidator.validate(
          cascade: _cascade([
            CascadeStep.percentOfRemainder(
              envelopeId: EnvelopeId('e1'),
              percent: Decimal.parse('1.1'),
              base: PercentBase.remainder,
            ),
          ]),
          catalog: catalog,
        );
        expect(result.errors, isNotEmpty);
      });

      test('percent == 1 → valid', () {
        final catalog = _catalog([_userEnv('e1')]);
        final result = CascadeValidator.validate(
          cascade: _cascade([
            CascadeStep.percentOfRemainder(
              envelopeId: EnvelopeId('e1'),
              percent: Decimal.one,
              base: PercentBase.remainder,
            ),
          ]),
          catalog: catalog,
        );
        expect(result.errors, isEmpty);
      });
    });

    group('envelope existence + usability rules', () {
      test('step targets unknown envelope → error', () {
        final catalog = _catalog([]);
        final result = CascadeValidator.validate(
          cascade: _cascade([
            CascadeStep.fixed(
              envelopeId: EnvelopeId('missing'),
              amountUsd: 100,
            ),
          ]),
          catalog: catalog,
        );
        expect(result.errors, isNotEmpty);
      });

      test('step targets system envelope → error', () {
        final catalog = _catalog([_systemEnv('sys-stage')]);
        final result = CascadeValidator.validate(
          cascade: _cascade([
            CascadeStep.fixed(
              envelopeId: EnvelopeId('sys-stage'),
              amountUsd: 100,
            ),
          ]),
          catalog: catalog,
        );
        expect(result.errors, isNotEmpty);
      });

      test('step targets archived envelope → error', () {
        final catalog = _catalog([_userEnv('e1', archived: true)]);
        final result = CascadeValidator.validate(
          cascade: _cascade([
            CascadeStep.fixed(envelopeId: EnvelopeId('e1'), amountUsd: 100),
          ]),
          catalog: catalog,
        );
        expect(result.errors, isNotEmpty);
      });
    });

    group('fillToCap without cap → warning (not error)', () {
      test('fillToCap envelope has no cap → warning', () {
        final catalog = _catalog([_userEnv('e1')]); // NoTarget
        final result = CascadeValidator.validate(
          cascade: _cascade([
            CascadeStep.fillToCap(envelopeId: EnvelopeId('e1')),
          ]),
          catalog: catalog,
        );
        expect(result.errors, isEmpty);
        expect(result.warnings, isNotEmpty);
      });

      test('fillToCap envelope has cap → no warning', () {
        final catalog = _catalog([
          _userEnv('e1', target: const Cap(amountUsd: 10000)),
        ]);
        final result = CascadeValidator.validate(
          cascade: _cascade([
            CascadeStep.fillToCap(envelopeId: EnvelopeId('e1')),
          ]),
          catalog: catalog,
        );
        expect(result.errors, isEmpty);
        expect(result.warnings, isEmpty);
      });
    });

    group('empty cascade → valid', () {
      test('no steps → no errors', () {
        final result = CascadeValidator.validate(
          cascade: _cascade([]),
          catalog: {},
        );
        expect(result.errors, isEmpty);
        expect(result.warnings, isEmpty);
      });
    });
  });
}
