import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:cuentaria_app/features/debts/application/debts_providers.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/providers/tasas_providers.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';

void main() {
  group('debtsSnapshotProvider', () {
    test(
      'Pedro (USD, \$200) shows a net of \$200 with no rate needed',
      () async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);

        final catalog = await container.read(catalogRepositoryProvider.future);
        final deviceId = await container.read(deviceIdProvider.future);
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

        final projections = container.read(ledgerProjectionsProvider);
        final stageEnvelope = catalog.getSystemEnvelope(EnvelopeRole.stage);
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

        final snapshot = await container.read(debtsSnapshotProvider.future);
        final pedro = snapshot.personas.singleWhere(
          (p) => p.personName == 'Pedro',
        );
        expect(pedro.netoUsdCents, 20000);
        expect(pedro.hasTasa, isTrue);
        expect(snapshot.globalNetoUsdCents, 20000);
      },
    );

    test('Ana (VES, 4000 Bs, frozen \$100) values at today\'s parallel rate '
        'and announces it', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final deviceId = await container.read(deviceIdProvider.future);
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

      final projections = container.read(ledgerProjectionsProvider);
      final stageEnvelope = catalog.getSystemEnvelope(EnvelopeRole.stage);
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

      final withoutRate = await container.read(debtsSnapshotProvider.future);
      final anaWithoutRate = withoutRate.personas.singleWhere(
        (p) => p.personName == 'Ana',
      );
      expect(anaWithoutRate.hasTasa, isFalse);
      expect(anaWithoutRate.netoUsdCents, 10000);

      final rateSeries = await container.read(rateSeriesProvider.future);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('50'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:paralelo',
        ),
      );
      container.invalidate(debtsSnapshotProvider);

      final snapshot = await container.read(debtsSnapshotProvider.future);
      final ana = snapshot.personas.singleWhere((p) => p.personName == 'Ana');
      expect(ana.hasTasa, isTrue);
      expect(ana.netoUsdCents, 8000);
      expect(snapshot.globalNetoUsdCents, 8000);
    });

    test('BCV reference resolves separately from the parallel rate and '
        'folds every debt account, USD and VES alike (#207)', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final deviceId = await container.read(deviceIdProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
      final stageEnvelope = catalog.getSystemEnvelope(EnvelopeRole.stage);

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
            eventId: EventId('evt-pedro-bcv'),
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
            eventId: EventId('evt-ana-bcv'),
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

      final snapshot = await container.read(debtsSnapshotProvider.future);
      // Pedro at par ($200) + Ana at BCV 40 (4000/40 = $100) = $300; the
      // parallel-valued neto stays independent at $200 + $80 (VES @ 50).
      expect(snapshot.bcvReferenceUsdCents, 30000);
      expect(snapshot.globalNetoUsdCents, 28000);
    });

    test('excludes regular (non-debt) accounts from the snapshot', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);
      await catalog.saveAccount(
        Account(
          id: AccountId('binance'),
          name: 'Binance',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final snapshot = await container.read(debtsSnapshotProvider.future);
      expect(snapshot.personas, isEmpty);
      expect(snapshot.globalNetoUsdCents, 0);
    });
  });
}
