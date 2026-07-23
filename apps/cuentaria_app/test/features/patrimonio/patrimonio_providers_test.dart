import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/funding_target.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:cuentaria_app/features/patrimonio/application/patrimonio_providers.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/providers/ledger_providers.dart';
import 'package:cuentaria_app/providers/tasas_providers.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrimonio/patrimonio.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';

void main() {
  group('patrimonioSnapshotProvider', () {
    test('excludes archived accounts from the totals', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final deviceId = await container.read(deviceIdProvider.future);
      final recordIncome = await container.read(recordIncomeProvider.future);
      final liveAccountId = catalog.accountIds.first;

      final archivedAccount = Account(
        id: AccountId('archived-1'),
        name: 'Old wallet',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: true,
        updatedAt: DateTime.now(),
      );
      await catalog.saveAccount(archivedAccount);

      await recordIncome(
        eventId: EventId('evt-archived'),
        deviceId: deviceId,
        accountId: archivedAccount.id,
        amount: Money(amount: BigInt.from(9900), currency: CurrencyCode('USD')),
        source: 'Manual entry',
      );
      await recordIncome(
        eventId: EventId('evt-live'),
        deviceId: deviceId,
        accountId: liveAccountId,
        amount: Money(amount: BigInt.from(2500), currency: CurrencyCode('USD')),
        source: 'Manual entry',
      );

      final snapshot = await container.read(patrimonioSnapshotProvider.future);
      expect(snapshot.realCostUsdCents, 2500);
      expect(snapshot.todayValueUsdCents, 2500);
      expect(snapshot.bcvReferenceUsdCents, 2500);
    });

    test('invalidates itself when a transaction is recorded', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final initial = await container.read(patrimonioSnapshotProvider.future);
      expect(initial.realCostUsdCents, 0);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final deviceId = await container.read(deviceIdProvider.future);
      final recordIncome = await container.read(recordIncomeProvider.future);

      await recordIncome(
        eventId: EventId('evt-reactive'),
        deviceId: deviceId,
        accountId: catalog.accountIds.first,
        amount: Money(amount: BigInt.from(1500), currency: CurrencyCode('USD')),
        source: 'Manual entry',
      );

      final updated = await container.read(patrimonioSnapshotProvider.future);
      expect(updated.realCostUsdCents, 1500);
    });

    test(
      'values a foreign-currency account at the parallel rate, keeps BCV '
      'as a separate reference, and flags currencies without a rate',
      () async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);

        final catalog = await container.read(catalogRepositoryProvider.future);
        final deviceId = await container.read(deviceIdProvider.future);
        final projections = container.read(ledgerProjectionsProvider);

        final vesAccountId = AccountId('ves-1');
        await catalog.saveAccount(
          Account(
            id: vesAccountId,
            name: 'Cuenta Bs',
            nativeCurrency: CurrencyCode('VES'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        // $100 cost basis at executed 75 Bs/USD => native balance 7500 Bs
        // (750000 in minor units, matching the USD cents scale).
        final stageEnvelope = catalog.getSystemEnvelope(EnvelopeRole.stage);
        projections.apply(
          Transaction.create(
            postings: [
              Posting(
                target: AccountTarget(vesAccountId),
                amountNative: Money(
                  amount: BigInt.from(750000),
                  currency: CurrencyCode('VES'),
                ),
                currency: CurrencyCode('VES'),
                amountUsd: 10000,
              ),
              Posting(
                target: EnvelopeTarget(stageEnvelope),
                amountNative: Money(
                  amount: BigInt.from(750000),
                  currency: CurrencyCode('VES'),
                ),
                currency: CurrencyCode('VES'),
                amountUsd: 10000,
              ),
            ],
            metadata: TransactionMetadata(
              eventId: EventId('evt-ves-acquisition'),
              type: 'Adjustment',
              occurredAt: DomainTimestamp(DateTime.now().toUtc()),
              recordedAt: DomainTimestamp(DateTime.now().toUtc()),
              deviceId: deviceId,
              schemaVersion: 1,
            ),
          ),
        );

        final beforeRates = await container.read(
          patrimonioSnapshotProvider.future,
        );
        final vesGroupBefore = beforeRates.accountGroups.singleWhere(
          (g) => g.currency == CurrencyCode('VES'),
        );
        expect(vesGroupBefore.hasRate, isFalse);
        expect(beforeRates.hasMissingRate, isTrue);
        expect(vesGroupBefore.todayValueUsdCents, 10000);

        final recordRates = await container.read(
          recordRateUseCaseProvider.future,
        );
        final observedAt = DateTime.now().toUtc();
        await recordRates.execute(
          bcv: RateObservation(
            currency: CurrencyCode('VES'),
            nativePerUsd: Decimal.parse('50'),
            observedAt: observedAt,
            source: 'manual:bcv',
          ),
          paralelo: RateObservation(
            currency: CurrencyCode('VES'),
            nativePerUsd: Decimal.parse('100'),
            observedAt: observedAt,
            source: 'manual:paralelo',
          ),
        );
        container.invalidate(patrimonioSnapshotProvider);

        final snapshot = await container.read(
          patrimonioSnapshotProvider.future,
        );
        expect(snapshot.realCostUsdCents, 10000);
        expect(snapshot.todayValueUsdCents, 7500);
        expect(snapshot.unrealizedPnlUsdCents, -2500);
        expect(snapshot.bcvReferenceUsdCents, 15000);
        expect(snapshot.hasMissingRate, isFalse);
      },
    );
  });

  group('patrimonioSnapshotProvider envelopes', () {
    test('maps a user envelope with a GoalLine target into metadata', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final deviceId = await container.read(deviceIdProvider.future);
      final recordIncome = await container.read(recordIncomeProvider.future);

      final vacaciones = EnvelopeId('vacaciones');
      await catalog.saveEnvelope(
        Envelope(
          id: vacaciones,
          name: 'Vacaciones',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ).withTarget(const GoalLine(amountUsd: 10000)),
      );

      await recordIncome(
        eventId: EventId('evt-envelope-goal'),
        deviceId: deviceId,
        accountId: catalog.accountIds.first,
        envelopeId: vacaciones,
        amount: Money(amount: BigInt.from(4000), currency: CurrencyCode('USD')),
        source: 'Manual entry',
      );

      final snapshot = await container.read(patrimonioSnapshotProvider.future);
      final envelope = snapshot.envelopes.singleWhere(
        (e) => e.id == vacaciones,
      );
      expect(envelope.balanceUsd, 4000);
      expect(envelope.role, EnvelopeRoleView.user);
      final metadata = envelope.metadata as GoalLineMetadata;
      expect(metadata.progressPercent, 40);
    });

    test('Stage is surfaced as "Sin asignar" only once it has a balance; '
        'Diferencial/Ajustes never appear', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final before = await container.read(patrimonioSnapshotProvider.future);
      expect(
        before.envelopes.where((e) => e.role == EnvelopeRoleView.stage),
        isEmpty,
      );

      final catalog = await container.read(catalogRepositoryProvider.future);
      final deviceId = await container.read(deviceIdProvider.future);
      final recordIncome = await container.read(recordIncomeProvider.future);

      await recordIncome(
        eventId: EventId('evt-stage'),
        deviceId: deviceId,
        accountId: catalog.accountIds.first,
        amount: Money(amount: BigInt.from(2000), currency: CurrencyCode('USD')),
        source: 'Manual entry',
      );

      final after = await container.read(patrimonioSnapshotProvider.future);
      final stage = after.envelopes.singleWhere(
        (e) => e.role == EnvelopeRoleView.stage,
      );
      expect(stage.balanceUsd, 2000);
      expect(
        after.envelopes.where(
          (e) =>
              e.role == EnvelopeRoleView.differential ||
              e.role == EnvelopeRoleView.adjustments,
        ),
        isEmpty,
      );
    });
  });
}
