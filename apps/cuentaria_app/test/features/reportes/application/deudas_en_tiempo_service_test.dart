import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:cuentaria_app/features/reportes/application/deudas_en_tiempo_service.dart';
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

Account _debtAccount(
  String id,
  String currency,
  String counterpartyName, {
  bool isArchived = false,
}) => Account(
  id: AccountId(id),
  name: id,
  nativeCurrency: CurrencyCode(currency),
  isArchived: isArchived,
  updatedAt: DateTime.now(),
  meta: {'counterpartyName': counterpartyName},
);

void main() {
  group('DebtsEnTiempoService.calculatePoints', () {
    test('a loan in July and a partial repayment in August carry forward '
        'unchanged into September', () async {
      final eventStore = InMemoryEventStore();
      final catalog = InMemoryCatalogRepository();
      final rateSeries = InMemoryRateSeries();
      final debtAccountId = AccountId('debt-pedro');
      await catalog.saveAccount(_debtAccount('debt-pedro', _usd, 'Pedro'));

      await eventStore.append(
        _movement(
          eventId: 'prestamo',
          accountId: debtAccountId,
          currency: _usd,
          nativeDelta: BigInt.from(20000),
          usdCentsDelta: 20000,
          occurredAt: DateTime.utc(2026, 7, 10),
        ),
      );
      await eventStore.append(
        _movement(
          eventId: 'cobro',
          accountId: debtAccountId,
          currency: _usd,
          nativeDelta: BigInt.from(-5000),
          usdCentsDelta: -5000,
          occurredAt: DateTime.utc(2026, 8, 5),
        ),
      );

      final service = DebtsEnTiempoService(
        eventStore: eventStore,
        catalog: catalog,
        rateSeries: rateSeries,
      );

      final points = await service.calculatePoints(
        latestMonth: ReportMonth(2026, 9),
        monthsCount: 3,
      );

      final byMonth = {for (final p in points) p.month.month: p};
      expect(byMonth[7]!.personas.single.personName, 'Pedro');
      expect(byMonth[7]!.personas.single.netoUsdCents, 20000);
      expect(byMonth[8]!.personas.single.netoUsdCents, 15000);
      expect(byMonth[9]!.personas.single.netoUsdCents, 15000);
    });

    test('a person archived once settled to zero appears only in the months '
        'they held a balance', () async {
      final eventStore = InMemoryEventStore();
      final catalog = InMemoryCatalogRepository();
      final rateSeries = InMemoryRateSeries();
      final debtAccountId = AccountId('debt-ana');
      await catalog.saveAccount(
        _debtAccount('debt-ana', _usd, 'Ana', isArchived: true),
      );

      await eventStore.append(
        _movement(
          eventId: 'prestamo-ana',
          accountId: debtAccountId,
          currency: _usd,
          nativeDelta: BigInt.from(10000),
          usdCentsDelta: 10000,
          occurredAt: DateTime.utc(2026, 4, 1),
        ),
      );
      await eventStore.append(
        _movement(
          eventId: 'cobro-ana',
          accountId: debtAccountId,
          currency: _usd,
          nativeDelta: BigInt.from(-10000),
          usdCentsDelta: -10000,
          occurredAt: DateTime.utc(2026, 5, 20),
        ),
      );

      final service = DebtsEnTiempoService(
        eventStore: eventStore,
        catalog: catalog,
        rateSeries: rateSeries,
      );

      final points = await service.calculatePoints(
        latestMonth: ReportMonth(2026, 6),
        monthsCount: 4,
      );

      final byMonth = {for (final p in points) p.month.month: p};
      expect(byMonth[3]!.personas, isEmpty); // marzo: no existía
      expect(byMonth[4]!.personas.single.netoUsdCents, 10000); // abril
      expect(byMonth[5]!.personas, isEmpty); // mayo: saldada
      expect(byMonth[6]!.personas, isEmpty); // junio: sigue ausente
    });

    test('a debt in Bs is valued at each month-end\'s own parallel rate and '
        'announces its source and date', () async {
      final eventStore = InMemoryEventStore();
      final catalog = InMemoryCatalogRepository();
      final rateSeries = InMemoryRateSeries();
      final debtAccountId = AccountId('debt-ves');
      await catalog.saveAccount(_debtAccount('debt-ves', _ves, 'Juan'));

      await eventStore.append(
        _movement(
          eventId: 'prestamo-ves',
          accountId: debtAccountId,
          currency: _ves,
          nativeDelta: BigInt.from(400000),
          usdCentsDelta: 10000,
          occurredAt: DateTime.utc(2026, 3, 1),
        ),
      );

      final marchRate = DateTime.utc(2026, 3, 31);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode(_ves),
          nativePerUsd: Decimal.parse('40'),
          observedAt: marchRate,
          source: 'manual:paralelo',
        ),
      );
      final aprilRate = DateTime.utc(2026, 4, 30);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode(_ves),
          nativePerUsd: Decimal.parse('50'),
          observedAt: aprilRate,
          source: 'dolarapi:paralelo',
        ),
      );

      final service = DebtsEnTiempoService(
        eventStore: eventStore,
        catalog: catalog,
        rateSeries: rateSeries,
      );

      final points = await service.calculatePoints(
        latestMonth: ReportMonth(2026, 4),
        monthsCount: 2,
      );

      final byMonth = {for (final p in points) p.month.month: p};
      final march = byMonth[3]!;
      expect(march.personas.single.netoUsdCents, 10000);
      expect(march.rateSource, 'manual:paralelo');
      expect(march.rateObservedAt, marchRate);

      final april = byMonth[4]!;
      expect(april.personas.single.netoUsdCents, 8000);
      expect(april.rateSource, 'dolarapi:paralelo');
      expect(april.rateObservedAt, aprilRate);
    });

    test(
      'no Debt Accounts at all returns points with empty personas',
      () async {
        final eventStore = InMemoryEventStore();
        final catalog = InMemoryCatalogRepository();
        final rateSeries = InMemoryRateSeries();

        final service = DebtsEnTiempoService(
          eventStore: eventStore,
          catalog: catalog,
          rateSeries: rateSeries,
        );

        final points = await service.calculatePoints(
          latestMonth: ReportMonth(2026, 9),
          monthsCount: 3,
        );

        expect(points, hasLength(3));
        for (final point in points) {
          expect(point.personas, isEmpty);
        }
      },
    );
  });
}
