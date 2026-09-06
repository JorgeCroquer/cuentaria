import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:cuentaria_app/features/reportes/application/patrimonio_en_tiempo_service.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes/reportes.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_series.dart';

const _usd = 'USD';
const _ves = 'VES';
const _stage = 'sys-stage';

Transaction _movement({
  required String eventId,
  required AccountId accountId,
  required String currency,
  required BigInt nativeDelta,
  required int usdCentsDelta,
  required DateTime occurredAt,
}) => Transaction.create(
  postings: [
    Posting(
      target: AccountTarget(accountId),
      amountNative: Money(
        amount: nativeDelta,
        currency: CurrencyCode(currency),
      ),
      currency: CurrencyCode(currency),
      amountUsd: usdCentsDelta,
    ),
    Posting(
      target: EnvelopeTarget(EnvelopeId(_stage)),
      amountNative: Money(
        amount: nativeDelta,
        currency: CurrencyCode(currency),
      ),
      currency: CurrencyCode(currency),
      amountUsd: usdCentsDelta,
    ),
  ],
  metadata: TransactionMetadata(
    eventId: EventId(eventId),
    type: 'Adjustment',
    occurredAt: DomainTimestamp(occurredAt.toUtc()),
    recordedAt: DomainTimestamp(occurredAt.toUtc()),
    deviceId: 'test-device',
    schemaVersion: 1,
  ),
);

Account _account(String id, String currency, {bool isArchived = false}) =>
    Account(
      id: AccountId(id),
      name: id,
      nativeCurrency: CurrencyCode(currency),
      isArchived: isArchived,
      updatedAt: DateTime.now(),
    );

Account _debtAccount(String id, String currency, String counterpartyName) =>
    Account(
      id: AccountId(id),
      name: id,
      nativeCurrency: CurrencyCode(currency),
      isArchived: false,
      updatedAt: DateTime.now(),
      meta: {'counterpartyName': counterpartyName},
    );

void main() {
  group('PatrimonioEnTiempoService.calculatePoints', () {
    test('each point\'s real cost matches the sum of amount_usd balances '
        'replayed to that month\'s end', () async {
      final eventStore = InMemoryEventStore();
      final catalog = InMemoryCatalogRepository();
      final rateSeries = InMemoryRateSeries();
      final accountId = AccountId('acc-1');
      await catalog.saveAccount(_account('acc-1', _usd));

      for (var month = 1; month <= 12; month++) {
        await eventStore.append(
          _movement(
            eventId: 'income-$month',
            accountId: accountId,
            currency: _usd,
            nativeDelta: BigInt.from(1000),
            usdCentsDelta: 1000,
            occurredAt: DateTime.utc(2026, month, 15),
          ),
        );
      }

      final service = PatrimonioEnTiempoService(
        eventStore: eventStore,
        catalog: catalog,
        rateSeries: rateSeries,
      );

      final points = await service.calculatePoints(
        latestMonth: ReportMonth(2026, 12),
      );

      expect(points, hasLength(12));
      for (var i = 0; i < 12; i++) {
        expect(points[i].month, ReportMonth(2026, i + 1));
        expect(points[i].realCostUsdCents, 1000 * (i + 1));
      }
    });

    test('a balance zeroed out before an account is archived stops counting '
        'toward real cost in the months after, but still counts in the '
        'months it held it', () async {
      final eventStore = InMemoryEventStore();
      final catalog = InMemoryCatalogRepository();
      final rateSeries = InMemoryRateSeries();
      final accountId = AccountId('archived-1');
      await catalog.saveAccount(_account('archived-1', _usd, isArchived: true));

      await eventStore.append(
        _movement(
          eventId: 'fund',
          accountId: accountId,
          currency: _usd,
          nativeDelta: BigInt.from(5000),
          usdCentsDelta: 5000,
          occurredAt: DateTime.utc(2026, 3, 10),
        ),
      );
      await eventStore.append(
        _movement(
          eventId: 'empty-out',
          accountId: accountId,
          currency: _usd,
          nativeDelta: BigInt.from(-5000),
          usdCentsDelta: -5000,
          occurredAt: DateTime.utc(2026, 6, 5),
        ),
      );

      final service = PatrimonioEnTiempoService(
        eventStore: eventStore,
        catalog: catalog,
        rateSeries: rateSeries,
      );

      final points = await service.calculatePoints(
        latestMonth: ReportMonth(2026, 6),
      );

      final byMonth = {for (final p in points) p.month.month: p};
      expect(byMonth[3]!.realCostUsdCents, 5000); // marzo
      expect(byMonth[4]!.realCostUsdCents, 5000); // abril
      expect(byMonth[5]!.realCostUsdCents, 5000); // mayo
      expect(byMonth[6]!.realCostUsdCents, 0); // junio
    });

    test(
      'a currency with no rate observation on or before the month leaves '
      'the market value overlay null while real cost stays present',
      () async {
        final eventStore = InMemoryEventStore();
        final catalog = InMemoryCatalogRepository();
        final rateSeries = InMemoryRateSeries();
        final accountId = AccountId('ves-1');
        await catalog.saveAccount(_account('ves-1', _ves));

        await eventStore.append(
          _movement(
            eventId: 'fund-ves',
            accountId: accountId,
            currency: _ves,
            nativeDelta: BigInt.from(750000),
            usdCentsDelta: 10000,
            occurredAt: DateTime.utc(2026, 5, 1),
          ),
        );

        final service = PatrimonioEnTiempoService(
          eventStore: eventStore,
          catalog: catalog,
          rateSeries: rateSeries,
        );

        final points = await service.calculatePoints(
          latestMonth: ReportMonth(2026, 5),
          monthsCount: 1,
        );

        expect(points.single.realCostUsdCents, 10000);
        expect(points.single.marketValueUsdCents, isNull);
        expect(points.single.rateSource, isNull);
        expect(points.single.rateObservedAt, isNull);
      },
    );

    test(
      'a month with no rate observation of its own uses the latest older '
      'one and announces its source and date (#260 "tasa del 15/04")',
      () async {
        final eventStore = InMemoryEventStore();
        final catalog = InMemoryCatalogRepository();
        final rateSeries = InMemoryRateSeries();
        final accountId = AccountId('ves-1');
        await catalog.saveAccount(_account('ves-1', _ves));

        await eventStore.append(
          _movement(
            eventId: 'fund-ves',
            accountId: accountId,
            currency: _ves,
            nativeDelta: BigInt.from(750000),
            usdCentsDelta: 10000,
            occurredAt: DateTime.utc(2026, 1, 1),
          ),
        );

        final observedAt = DateTime.utc(2026, 4, 15);
        await rateSeries.append(
          RateObservation(
            currency: CurrencyCode(_ves),
            nativePerUsd: Decimal.parse('100'),
            observedAt: observedAt,
            source: 'manual:paralelo',
          ),
        );

        final service = PatrimonioEnTiempoService(
          eventStore: eventStore,
          catalog: catalog,
          rateSeries: rateSeries,
        );

        final points = await service.calculatePoints(
          latestMonth: ReportMonth(2026, 5),
        );

        final may = points.singleWhere((p) => p.month == ReportMonth(2026, 5));
        expect(may.realCostUsdCents, 10000);
        expect(may.marketValueUsdCents, 7500);
        expect(may.rateSource, 'manual:paralelo');
        expect(may.rateObservedAt, observedAt);
      },
    );

    test(
      'a single month of history renders one point without crashing',
      () async {
        final eventStore = InMemoryEventStore();
        final catalog = InMemoryCatalogRepository();
        final rateSeries = InMemoryRateSeries();
        final accountId = AccountId('acc-1');
        await catalog.saveAccount(_account('acc-1', _usd));
        await eventStore.append(
          _movement(
            eventId: 'income',
            accountId: accountId,
            currency: _usd,
            nativeDelta: BigInt.from(2000),
            usdCentsDelta: 2000,
            occurredAt: DateTime.utc(2026, 9, 1),
          ),
        );

        final service = PatrimonioEnTiempoService(
          eventStore: eventStore,
          catalog: catalog,
          rateSeries: rateSeries,
        );

        final points = await service.calculatePoints(
          latestMonth: ReportMonth(2026, 9),
          monthsCount: 1,
        );

        expect(points, hasLength(1));
        expect(points.single.realCostUsdCents, 2000);
      },
    );

    test('a Debt Account with a balance is folded back into real cost and '
        'market value, at parity with "Patrimonio hoy" (#260 fix)', () async {
      final eventStore = InMemoryEventStore();
      final catalog = InMemoryCatalogRepository();
      final rateSeries = InMemoryRateSeries();
      final accountId = AccountId('acc-1');
      final debtAccountId = AccountId('debt-1');
      await catalog.saveAccount(_account('acc-1', _usd));
      await catalog.saveAccount(_debtAccount('debt-1', _usd, 'Pedro'));

      await eventStore.append(
        _movement(
          eventId: 'fund-acc',
          accountId: accountId,
          currency: _usd,
          nativeDelta: BigInt.from(100000),
          usdCentsDelta: 100000,
          occurredAt: DateTime.utc(2026, 9, 1),
        ),
      );
      await eventStore.append(
        _movement(
          eventId: 'fund-debt',
          accountId: debtAccountId,
          currency: _usd,
          nativeDelta: BigInt.from(50000),
          usdCentsDelta: 50000,
          occurredAt: DateTime.utc(2026, 9, 5),
        ),
      );

      final service = PatrimonioEnTiempoService(
        eventStore: eventStore,
        catalog: catalog,
        rateSeries: rateSeries,
      );

      final points = await service.calculatePoints(
        latestMonth: ReportMonth(2026, 9),
        monthsCount: 1,
      );

      // Parity with patrimonioSnapshotProvider (#207): the account's
      // balance plus the Debt Account's, both real cost and market value
      // (USD has no rate to miss).
      expect(points.single.realCostUsdCents, 150000);
      expect(points.single.marketValueUsdCents, 150000);
    });

    test(
      'twelve replays over 2,000 events complete in under a second',
      () async {
        final eventStore = InMemoryEventStore();
        final catalog = InMemoryCatalogRepository();
        final rateSeries = InMemoryRateSeries();
        final accountId = AccountId('acc-1');
        await catalog.saveAccount(_account('acc-1', _usd));

        for (var i = 0; i < 2000; i++) {
          final month = (i % 12) + 1;
          await eventStore.append(
            _movement(
              eventId: 'evt-$i',
              accountId: accountId,
              currency: _usd,
              nativeDelta: BigInt.from(10),
              usdCentsDelta: 10,
              occurredAt: DateTime.utc(2026, month, 1 + (i ~/ 12) % 27),
            ),
          );
        }

        final service = PatrimonioEnTiempoService(
          eventStore: eventStore,
          catalog: catalog,
          rateSeries: rateSeries,
        );

        final stopwatch = Stopwatch()..start();
        final points = await service.calculatePoints(
          latestMonth: ReportMonth(2026, 12),
        );
        stopwatch.stop();

        expect(points, hasLength(12));
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      },
    );
  });
}
