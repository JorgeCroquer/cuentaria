import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/envelope_appearance.dart';
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
      final liveAccountId = AccountId('live-1');
      await catalog.saveAccount(
        Account(
          id: liveAccountId,
          name: 'Live wallet',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

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
      final accountId = AccountId('test-acc');
      await catalog.saveAccount(
        Account(
          id: accountId,
          name: 'Test Account',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await recordIncome(
        eventId: EventId('evt-reactive'),
        deviceId: deviceId,
        accountId: accountId,
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

    test('the BCV reference resolves from dolarapi:oficial with no manual '
        'entry (#166)', () async {
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

      // 755.16 Bs (75516 minor units) at 755.16 Bs/USD => exactly $1.00.
      final stageEnvelope = catalog.getSystemEnvelope(EnvelopeRole.stage);
      projections.apply(
        Transaction.create(
          postings: [
            Posting(
              target: AccountTarget(vesAccountId),
              amountNative: Money(
                amount: BigInt.from(75516),
                currency: CurrencyCode('VES'),
              ),
              currency: CurrencyCode('VES'),
              amountUsd: 100,
            ),
            Posting(
              target: EnvelopeTarget(stageEnvelope),
              amountNative: Money(
                amount: BigInt.from(75516),
                currency: CurrencyCode('VES'),
              ),
              currency: CurrencyCode('VES'),
              amountUsd: 100,
            ),
          ],
          metadata: TransactionMetadata(
            eventId: EventId('evt-ves-oficial'),
            type: 'Adjustment',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: deviceId,
            schemaVersion: 1,
          ),
        ),
      );

      final rateSeries = await container.read(rateSeriesProvider.future);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('755.16'),
          observedAt: DateTime.now().toUtc(),
          source: 'dolarapi:oficial',
        ),
      );

      final snapshot = await container.read(patrimonioSnapshotProvider.future);
      expect(snapshot.bcvReferenceUsdCents, 100);
    });

    test('the BCV reference falls back to manual:bcv when there is no '
        'dolarapi:oficial observation (#166)', () async {
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

      // 50.00 Bs (5000 minor units) at 50 Bs/USD => exactly $1.00.
      final stageEnvelope = catalog.getSystemEnvelope(EnvelopeRole.stage);
      projections.apply(
        Transaction.create(
          postings: [
            Posting(
              target: AccountTarget(vesAccountId),
              amountNative: Money(
                amount: BigInt.from(5000),
                currency: CurrencyCode('VES'),
              ),
              currency: CurrencyCode('VES'),
              amountUsd: 100,
            ),
            Posting(
              target: EnvelopeTarget(stageEnvelope),
              amountNative: Money(
                amount: BigInt.from(5000),
                currency: CurrencyCode('VES'),
              ),
              currency: CurrencyCode('VES'),
              amountUsd: 100,
            ),
          ],
          metadata: TransactionMetadata(
            eventId: EventId('evt-ves-bcv-fallback'),
            type: 'Adjustment',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: deviceId,
            schemaVersion: 1,
          ),
        ),
      );

      final rateSeries = await container.read(rateSeriesProvider.future);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('50'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:bcv',
        ),
      );

      final snapshot = await container.read(patrimonioSnapshotProvider.future);
      expect(snapshot.bcvReferenceUsdCents, 100);
    });
  });

  group('patrimonioSnapshotProvider debts segregation (#207)', () {
    test('Debt Accounts never appear in a currency group, and the segregation '
        'moves presentation, not numbers: net worth includes their value '
        'today the same as before segregating', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final deviceId = await container.read(deviceIdProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
      final stageEnvelope = catalog.getSystemEnvelope(EnvelopeRole.stage);

      final efectivoId = AccountId('efectivo');
      await catalog.saveAccount(
        Account(
          id: efectivoId,
          name: 'Efectivo',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      projections.apply(
        Transaction.create(
          postings: [
            Posting(
              target: AccountTarget(efectivoId),
              amountNative: Money(
                amount: BigInt.from(50000),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 50000,
            ),
            Posting(
              target: EnvelopeTarget(stageEnvelope),
              amountNative: Money(
                amount: BigInt.from(50000),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 50000,
            ),
          ],
          metadata: TransactionMetadata(
            eventId: EventId('evt-efectivo'),
            type: 'Adjustment',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: deviceId,
            schemaVersion: 1,
          ),
        ),
      );

      final pedroId = AccountId('pedro');
      await catalog.saveAccount(
        Account(
          id: pedroId,
          name: 'Pedro',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
          meta: {'counterpartyName': 'Pedro'},
        ),
      );
      projections.apply(
        Transaction.create(
          postings: [
            Posting(
              target: AccountTarget(pedroId),
              amountNative: Money(
                amount: BigInt.from(20000),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 20000,
            ),
            Posting(
              target: EnvelopeTarget(stageEnvelope),
              amountNative: Money(
                amount: BigInt.from(20000),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 20000,
            ),
          ],
          metadata: TransactionMetadata(
            eventId: EventId('evt-pedro'),
            type: 'Adjustment',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: deviceId,
            schemaVersion: 1,
          ),
        ),
      );

      final anaId = AccountId('ana');
      await catalog.saveAccount(
        Account(
          id: anaId,
          name: 'Ana',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
          meta: {'counterpartyName': 'Ana'},
        ),
      );
      projections.apply(
        Transaction.create(
          postings: [
            Posting(
              target: AccountTarget(anaId),
              amountNative: Money(
                amount: BigInt.from(400000),
                currency: CurrencyCode('VES'),
              ),
              currency: CurrencyCode('VES'),
              amountUsd: 10000,
            ),
            Posting(
              target: EnvelopeTarget(stageEnvelope),
              amountNative: Money(
                amount: BigInt.from(400000),
                currency: CurrencyCode('VES'),
              ),
              currency: CurrencyCode('VES'),
              amountUsd: 10000,
            ),
          ],
          metadata: TransactionMetadata(
            eventId: EventId('evt-ana'),
            type: 'Adjustment',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: deviceId,
            schemaVersion: 1,
          ),
        ),
      );

      final rateSeries = await container.read(rateSeriesProvider.future);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('50'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:paralelo',
        ),
      );

      final snapshot = await container.read(patrimonioSnapshotProvider.future);

      expect(
        snapshot.accountGroups.where((g) => g.currency == CurrencyCode('VES')),
        isEmpty,
      );
      expect(
        snapshot.accountGroups
            .singleWhere((g) => g.currency == CurrencyCode('USD'))
            .realCostUsdCents,
        50000,
      );

      // Pedro ($200) + Ana (4.000 Bs at 50 => $80) = $280 on top of
      // Efectivo's $500 — the same total as if they were never segregated.
      expect(snapshot.realCostUsdCents, 50000 + 20000 + 10000);
      expect(snapshot.todayValueUsdCents, 50000 + 20000 + 8000);
      expect(snapshot.unrealizedPnlUsdCents, 8000 - 10000);
    });

    test('the BCV reference folds Debt Accounts\' valuation too, not just '
        'their parallel-rate today value', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final deviceId = await container.read(deviceIdProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
      final stageEnvelope = catalog.getSystemEnvelope(EnvelopeRole.stage);

      final anaId = AccountId('ana');
      await catalog.saveAccount(
        Account(
          id: anaId,
          name: 'Ana',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
          meta: {'counterpartyName': 'Ana'},
        ),
      );
      projections.apply(
        Transaction.create(
          postings: [
            Posting(
              target: AccountTarget(anaId),
              amountNative: Money(
                amount: BigInt.from(400000),
                currency: CurrencyCode('VES'),
              ),
              currency: CurrencyCode('VES'),
              amountUsd: 10000,
            ),
            Posting(
              target: EnvelopeTarget(stageEnvelope),
              amountNative: Money(
                amount: BigInt.from(400000),
                currency: CurrencyCode('VES'),
              ),
              currency: CurrencyCode('VES'),
              amountUsd: 10000,
            ),
          ],
          metadata: TransactionMetadata(
            eventId: EventId('evt-ana-bcv-fold'),
            type: 'Adjustment',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: deviceId,
            schemaVersion: 1,
          ),
        ),
      );

      final rateSeries = await container.read(rateSeriesProvider.future);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('50'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:paralelo',
        ),
      );
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('40'),
          observedAt: DateTime.now().toUtc(),
          source: 'dolarapi:oficial',
        ),
      );

      final snapshot = await container.read(patrimonioSnapshotProvider.future);

      // No non-debt accounts, so the patrimonio engine alone contributes 0;
      // Ana's Debt Account values at BCV 40 (4000/40 = $100).
      expect(snapshot.bcvReferenceUsdCents, 10000);
    });
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
      final accountId = AccountId('test-acc');
      await catalog.saveAccount(
        Account(
          id: accountId,
          name: 'Test Account',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

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
        accountId: accountId,
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

    test('maps a user envelope\'s icon/color appearance through', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);

      final mercado = EnvelopeId('mercado');
      await catalog.saveEnvelope(
        Envelope(
          id: mercado,
          name: 'Mercado',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ).withAppearance(
          const EnvelopeAppearance(iconId: 'shopping_cart', colorIndex: 1),
        ),
      );

      final snapshot = await container.read(patrimonioSnapshotProvider.future);
      final envelope = snapshot.envelopes.singleWhere((e) => e.id == mercado);
      expect(envelope.iconId, 'shopping_cart');
      expect(envelope.colorIndex, 1);
    });

    test(
      'excludes an archived user envelope from the snapshot and its totals',
      () async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);

        final catalog = await container.read(catalogRepositoryProvider.future);
        final deviceId = await container.read(deviceIdProvider.future);
        final recordIncome = await container.read(recordIncomeProvider.future);

        final accountId = AccountId('test-acc');
        await catalog.saveAccount(
          Account(
            id: accountId,
            name: 'Test Account',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        final mercado = EnvelopeId('mercado');
        await catalog.saveEnvelope(
          Envelope(
            id: mercado,
            name: 'Mercado',
            role: EnvelopeRole.none,
            isArchived: false,
            updatedAt: DateTime.now(),
          ).withTarget(const Cap(amountUsd: 30000)),
        );

        await recordIncome(
          eventId: EventId('evt-mercado'),
          deviceId: deviceId,
          accountId: accountId,
          envelopeId: mercado,
          amount: Money(
            amount: BigInt.from(4000),
            currency: CurrencyCode('USD'),
          ),
          source: 'Manual entry',
        );

        final before = await container.read(patrimonioSnapshotProvider.future);
        expect(before.envelopes.where((e) => e.id == mercado), isNotEmpty);

        final existing = catalog.getEnvelope(mercado)!;
        await catalog.saveEnvelope(
          Envelope(
            id: mercado,
            name: existing.name,
            role: existing.role,
            isArchived: true,
            updatedAt: DateTime.now(),
            meta: existing.meta,
          ),
        );
        container.invalidate(patrimonioSnapshotProvider);

        final after = await container.read(patrimonioSnapshotProvider.future);
        expect(after.envelopes.where((e) => e.id == mercado), isEmpty);
      },
    );

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
      final accountId = AccountId('test-acc');
      await catalog.saveAccount(
        Account(
          id: accountId,
          name: 'Test Account',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await recordIncome(
        eventId: EventId('evt-stage'),
        deviceId: deviceId,
        accountId: accountId,
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
