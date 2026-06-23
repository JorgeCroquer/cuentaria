import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

import 'package:contabilidad/application/cascade/cascade.dart';
import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:contabilidad/application/cascade/distribute_from_stage.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/funding_target.dart';
import 'package:contabilidad/application/ledger/factories/record_distribution.dart';
import 'package:contabilidad/application/ledger/factories/record_income.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/infrastructure/cascade/in_memory_cascade_repository.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';

// Helpers ---------------------------------------------------------------

InMemoryCatalogRepository _catalog() => InMemoryCatalogRepository();

AccountId _addUsdAccount(InMemoryCatalogRepository catalog, String id) {
  final accountId = AccountId(id);
  catalog.saveAccount(
    Account(
      id: accountId,
      name: id,
      nativeCurrency: CurrencyCode('USD'),
      isArchived: false,
      updatedAt: DateTime.now(),
    ),
  );
  return accountId;
}

EnvelopeId _addEnvelope(
  InMemoryCatalogRepository catalog,
  String id, {
  FundingTarget? target,
}) {
  final envId = EnvelopeId(id);
  final now = DateTime.now();
  catalog.saveEnvelope(
    Envelope(
      id: envId,
      name: id,
      role: EnvelopeRole.none,
      isArchived: false,
      updatedAt: now,
      meta:
          target != null && target is! NoTarget
              ? {'target': target.toJson()}
              : null,
    ),
  );
  return envId;
}

({
  DistributeFromStage distributor,
  RecordIncome recordIncome,
  InMemoryLedgerProjections projections,
  InMemoryCatalogRepository catalog,
  InMemoryCascadeRepository cascadeRepo,
})
_wire() {
  final store = InMemoryEventStore();
  final projections = InMemoryLedgerProjections();
  final catalog = _catalog();
  final cascadeRepo = InMemoryCascadeRepository();
  final eventBus = SyncEventBus();
  final validator = ReferentialIntegrityValidator(catalog);

  final recordTx = RecordTransaction(
    store: store,
    projections: projections,
    eventBus: eventBus,
    validator: validator,
  );
  final recordDist = RecordDistribution(record: recordTx, catalog: catalog);
  final recordIncome = RecordIncome(record: recordTx, catalog: catalog);
  final distributor = DistributeFromStage(
    projections: projections,
    catalog: catalog,
    cascadeRepo: cascadeRepo,
    recordDistribution: recordDist,
  );

  return (
    distributor: distributor,
    recordIncome: recordIncome,
    projections: projections,
    catalog: catalog,
    cascadeRepo: cascadeRepo,
  );
}

// -----------------------------------------------------------------------

void main() {
  group('DistributeFromStage — orchestrator integration', () {
    test('preview returns proposal without applying it', () async {
      final ctx = _wire();
      final accountId = _addUsdAccount(ctx.catalog, 'acc');
      final envA = _addEnvelope(ctx.catalog, 'env-a');
      final envB = _addEnvelope(ctx.catalog, 'env-b');

      await ctx.recordIncome(
        eventId: EventId('inc-1'),
        deviceId: 'dev',
        accountId: accountId,
        amount: Money(amount: BigInt.from(1000), currency: CurrencyCode('USD')),
        source: 'client',
      );

      await ctx.cascadeRepo.save(
        Cascade(
          steps: [
            CascadeStep.fixed(envelopeId: envA, amountUsd: 300),
            CascadeStep.catchAll(envelopeId: envB),
          ],
          updatedAt: DateTime.now(),
        ),
      );

      final stageId = ctx.catalog.getSystemEnvelope(EnvelopeRole.stage);

      final proposal = await ctx.distributor.preview();

      // proposal is non-null with 2 lines; Stage balance unchanged
      expect(proposal, isNotNull);
      expect(proposal!.allocations.length, equals(2));
      expect(
        ctx.projections.envelopeUsdBalance(stageId),
        equals(1000),
      ); // not yet applied
    });

    test(
      'apply: income→Stage→distribute; envelopes get correct amounts; Stage drained',
      () async {
        final ctx = _wire();
        final accountId = _addUsdAccount(ctx.catalog, 'acc');
        final envA = _addEnvelope(ctx.catalog, 'env-a'); // fixed 300
        final envB = _addEnvelope(ctx.catalog, 'env-b'); // catch-all

        await ctx.recordIncome(
          eventId: EventId('inc-1'),
          deviceId: 'dev',
          accountId: accountId,
          amount: Money(
            amount: BigInt.from(1000),
            currency: CurrencyCode('USD'),
          ),
          source: 'client',
        );

        await ctx.cascadeRepo.save(
          Cascade(
            steps: [
              CascadeStep.fixed(envelopeId: envA, amountUsd: 300),
              CascadeStep.catchAll(envelopeId: envB),
            ],
            updatedAt: DateTime.now(),
          ),
        );

        await ctx.distributor.apply(
          eventId: EventId('dist-1'),
          deviceId: 'dev',
        );

        final stageId = ctx.catalog.getSystemEnvelope(EnvelopeRole.stage);
        expect(ctx.projections.envelopeUsdBalance(stageId), equals(0));
        expect(ctx.projections.envelopeUsdBalance(envA), equals(300));
        expect(ctx.projections.envelopeUsdBalance(envB), equals(700));
      },
    );

    test('residue stays in Stage when no catchAll', () async {
      final ctx = _wire();
      final accountId = _addUsdAccount(ctx.catalog, 'acc');
      final envA = _addEnvelope(ctx.catalog, 'env-a'); // fixed 300

      await ctx.recordIncome(
        eventId: EventId('inc-1'),
        deviceId: 'dev',
        accountId: accountId,
        amount: Money(amount: BigInt.from(1000), currency: CurrencyCode('USD')),
        source: 'client',
      );

      await ctx.cascadeRepo.save(
        Cascade(
          steps: [CascadeStep.fixed(envelopeId: envA, amountUsd: 300)],
          updatedAt: DateTime.now(),
        ),
      );

      await ctx.distributor.apply(eventId: EventId('dist-1'), deviceId: 'dev');

      final stageId = ctx.catalog.getSystemEnvelope(EnvelopeRole.stage);
      expect(
        ctx.projections.envelopeUsdBalance(stageId),
        equals(700),
      ); // residue
      expect(ctx.projections.envelopeUsdBalance(envA), equals(300));
    });

    test('guard: amount > Stage balance throws', () async {
      final ctx = _wire();
      final accountId = _addUsdAccount(ctx.catalog, 'acc');
      final envA = _addEnvelope(ctx.catalog, 'env-a');

      await ctx.recordIncome(
        eventId: EventId('inc-1'),
        deviceId: 'dev',
        accountId: accountId,
        amount: Money(amount: BigInt.from(500), currency: CurrencyCode('USD')),
        source: 'client',
      );

      await ctx.cascadeRepo.save(
        Cascade(
          steps: [CascadeStep.fixed(envelopeId: envA, amountUsd: 300)],
          updatedAt: DateTime.now(),
        ),
      );

      await expectLater(
        () => ctx.distributor.apply(
          eventId: EventId('dist-1'),
          deviceId: 'dev',
          amount: 9999, // more than Stage
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('skip step: skipped step excluded; redistribution correct', () async {
      final ctx = _wire();
      final accountId = _addUsdAccount(ctx.catalog, 'acc');
      final envA = _addEnvelope(ctx.catalog, 'env-a'); // fixed 300 (skipped)
      final envB = _addEnvelope(ctx.catalog, 'env-b'); // catch-all

      await ctx.recordIncome(
        eventId: EventId('inc-1'),
        deviceId: 'dev',
        accountId: accountId,
        amount: Money(amount: BigInt.from(1000), currency: CurrencyCode('USD')),
        source: 'client',
      );

      await ctx.cascadeRepo.save(
        Cascade(
          steps: [
            CascadeStep.fixed(envelopeId: envA, amountUsd: 300),
            CascadeStep.catchAll(envelopeId: envB),
          ],
          updatedAt: DateTime.now(),
        ),
      );

      // Skip envA step — re-run engine without it
      await ctx.distributor.applySkipping(
        skipEnvelopeIds: {envA},
        eventId: EventId('dist-1'),
        deviceId: 'dev',
      );

      final stageId = ctx.catalog.getSystemEnvelope(EnvelopeRole.stage);
      expect(ctx.projections.envelopeUsdBalance(stageId), equals(0));
      expect(ctx.projections.envelopeUsdBalance(envA), equals(0)); // skipped
      expect(ctx.projections.envelopeUsdBalance(envB), equals(1000));
    });

    test('fillToCap uses FundingTarget.Cap from catalog envelope', () async {
      final ctx = _wire();
      final accountId = _addUsdAccount(ctx.catalog, 'acc');
      // envA has a cap of 400; already has 100 → needs 300 more
      final envA = _addEnvelope(
        ctx.catalog,
        'env-a',
        target: Cap(amountUsd: 400),
      );
      final envB = _addEnvelope(ctx.catalog, 'env-b'); // catch-all

      // Seed envA with 100 first
      await ctx.cascadeRepo.save(
        Cascade(
          steps: [
            CascadeStep.fixed(envelopeId: envA, amountUsd: 100),
            CascadeStep.catchAll(envelopeId: envB),
          ],
          updatedAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      );

      final accountId2 = _addUsdAccount(ctx.catalog, 'acc2');
      await ctx.recordIncome(
        eventId: EventId('inc-seed'),
        deviceId: 'dev',
        accountId: accountId2,
        amount: Money(amount: BigInt.from(100), currency: CurrencyCode('USD')),
        source: 'seed',
      );
      await ctx.distributor.apply(
        eventId: EventId('dist-seed'),
        deviceId: 'dev',
      );
      // Now envA=100, envB=0

      // Main test: income 1000, fillToCap envA (cap=400, balance=100 → needs 300)
      await ctx.recordIncome(
        eventId: EventId('inc-1'),
        deviceId: 'dev',
        accountId: accountId,
        amount: Money(amount: BigInt.from(1000), currency: CurrencyCode('USD')),
        source: 'client',
      );

      await ctx.cascadeRepo.save(
        Cascade(
          steps: [
            CascadeStep.fillToCap(envelopeId: envA),
            CascadeStep.catchAll(envelopeId: envB),
          ],
          updatedAt: DateTime.now(),
        ),
      );

      await ctx.distributor.apply(eventId: EventId('dist-1'), deviceId: 'dev');

      expect(ctx.projections.envelopeUsdBalance(envA), equals(400)); // 100+300
      expect(ctx.projections.envelopeUsdBalance(envB), equals(700)); // 1000-300
    });

    test(
      'applying twice: second run sees drained Stage; invariant holds',
      () async {
        final ctx = _wire();
        final accountId = _addUsdAccount(ctx.catalog, 'acc');
        final envA = _addEnvelope(ctx.catalog, 'env-a');
        final envB = _addEnvelope(ctx.catalog, 'env-b');

        await ctx.recordIncome(
          eventId: EventId('inc-1'),
          deviceId: 'dev',
          accountId: accountId,
          amount: Money(
            amount: BigInt.from(1000),
            currency: CurrencyCode('USD'),
          ),
          source: 'client',
        );

        await ctx.cascadeRepo.save(
          Cascade(
            steps: [
              CascadeStep.fixed(envelopeId: envA, amountUsd: 300),
              CascadeStep.catchAll(envelopeId: envB),
            ],
            updatedAt: DateTime.now(),
          ),
        );

        await ctx.distributor.apply(
          eventId: EventId('dist-1'),
          deviceId: 'dev',
        );

        // Second apply: Stage is 0, amount defaults to 0 → no-op (nothing to distribute)
        // No exception; guard amount <= stage (0 <= 0 passes).
        await ctx.distributor.apply(
          eventId: EventId('dist-2'),
          deviceId: 'dev',
        );

        final stageId = ctx.catalog.getSystemEnvelope(EnvelopeRole.stage);
        // Stage=0, envA=300, envB=700 → sum = 1000 = account balance
        expect(ctx.projections.envelopeUsdBalance(stageId), equals(0));
        expect(ctx.projections.envelopeUsdBalance(envA), equals(300));
        expect(ctx.projections.envelopeUsdBalance(envB), equals(700));
        expect(ctx.projections.accountBalance(accountId).usd, equals(1000));
      },
    );

    test('preview with no cascade returns null', () async {
      final ctx = _wire();
      final proposal = await ctx.distributor.preview();
      expect(proposal, isNull);
    });
  });

  group('DistributeFromStage — lean-month scenario', () {
    test(
      'lean month: Stage only covers top steps; bottom gets nothing',
      () async {
        final ctx = _wire();
        final accountId = _addUsdAccount(ctx.catalog, 'acc');
        final envRent = _addEnvelope(ctx.catalog, 'env-rent'); // fixed 800
        final envSavings = _addEnvelope(
          ctx.catalog,
          'env-savings',
        ); // fixed 500

        // Lean month: only 900 available, rent (800) gets full; savings gets 100
        await ctx.recordIncome(
          eventId: EventId('inc-1'),
          deviceId: 'dev',
          accountId: accountId,
          amount: Money(
            amount: BigInt.from(900),
            currency: CurrencyCode('USD'),
          ),
          source: 'client',
        );

        await ctx.cascadeRepo.save(
          Cascade(
            steps: [
              CascadeStep.fixed(envelopeId: envRent, amountUsd: 800),
              CascadeStep.fixed(envelopeId: envSavings, amountUsd: 500),
            ],
            updatedAt: DateTime.now(),
          ),
        );

        await ctx.distributor.apply(
          eventId: EventId('dist-1'),
          deviceId: 'dev',
        );

        final stageId = ctx.catalog.getSystemEnvelope(EnvelopeRole.stage);
        expect(ctx.projections.envelopeUsdBalance(envRent), equals(800));
        expect(
          ctx.projections.envelopeUsdBalance(envSavings),
          equals(100),
        ); // clamped
        expect(ctx.projections.envelopeUsdBalance(stageId), equals(0));
      },
    );
  });

  group('DistributeFromStage — accumulative grocery buffer (2-month)', () {
    test('fixed step accumulates buffer over two months', () async {
      final ctx = _wire();
      final accId1 = _addUsdAccount(ctx.catalog, 'acc-1');
      final accId2 = _addUsdAccount(ctx.catalog, 'acc-2');
      final groceries = _addEnvelope(
        ctx.catalog,
        'env-groceries',
      ); // fixed 300/mo
      final catchAll = _addEnvelope(ctx.catalog, 'env-catch');

      await ctx.cascadeRepo.save(
        Cascade(
          steps: [
            CascadeStep.fixed(envelopeId: groceries, amountUsd: 300),
            CascadeStep.catchAll(envelopeId: catchAll),
          ],
          updatedAt: DateTime.now(),
        ),
      );

      // Month 1: income 1000
      await ctx.recordIncome(
        eventId: EventId('inc-m1'),
        deviceId: 'dev',
        accountId: accId1,
        amount: Money(amount: BigInt.from(1000), currency: CurrencyCode('USD')),
        source: 'month1',
      );
      await ctx.distributor.apply(eventId: EventId('dist-m1'), deviceId: 'dev');

      // Month 2: income 1000 again
      await ctx.recordIncome(
        eventId: EventId('inc-m2'),
        deviceId: 'dev',
        accountId: accId2,
        amount: Money(amount: BigInt.from(1000), currency: CurrencyCode('USD')),
        source: 'month2',
      );
      await ctx.distributor.apply(eventId: EventId('dist-m2'), deviceId: 'dev');

      // Groceries accumulated 300+300=600
      expect(ctx.projections.envelopeUsdBalance(groceries), equals(600));
      // Catch-all got 700+700=1400
      expect(ctx.projections.envelopeUsdBalance(catchAll), equals(1400));
    });
  });
}
