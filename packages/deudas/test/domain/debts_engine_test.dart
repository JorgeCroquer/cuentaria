import 'package:decimal/decimal.dart';
import 'package:deudas/domain/debt_account_view.dart';
import 'package:deudas/domain/debts_engine.dart';
import 'package:deudas/domain/rate_view.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

void main() {
  const engine = DebtsEngine();
  final ves = CurrencyCode('VES');
  final usd = CurrencyCode('USD');
  final now = DateTime.utc(2026, 8, 25);

  DebtAccountView account({
    String id = 'acc-1',
    String person = 'Ana',
    CurrencyCode? currency,
    required BigInt native,
    required int realCostUsdCents,
    bool isArchived = false,
  }) => DebtAccountView(
    id: AccountId(id),
    counterpartyName: person,
    currency: currency ?? ves,
    nativeMinorAmount: native,
    realCostUsdCents: realCostUsdCents,
    isArchived: isArchived,
  );

  group('DebtsEngine', () {
    test('USD person: neto equals the frozen cost, no rate needed', () {
      final snapshot = engine(
        [
          account(
            person: 'Ana',
            currency: usd,
            native: BigInt.from(20000),
            realCostUsdCents: 20000,
          ),
        ],
        const {},
        now,
      );

      final ana = snapshot.personas.single;
      expect(ana.personName, 'Ana');
      expect(ana.netoUsdCents, 20000);
      expect(ana.hasTasa, isTrue);
      expect(snapshot.globalNetoUsdCents, 20000);
    });

    test('VES person with a parallel rate: revalued at today\'s rate, rate '
        'exposed', () {
      final rates = {
        ves: RateView(
          currency: ves,
          parallel: RateObservationView(
            nativePerUsd: Decimal.parse('50'),
            observedAt: now,
            source: 'binancep2p:ask',
          ),
        ),
      };

      final snapshot = engine(
        [
          account(
            person: 'Ana',
            native: BigInt.from(400000),
            realCostUsdCents: 10000,
          ),
        ],
        rates,
        now,
      );

      final ana = snapshot.personas.single;
      expect(ana.netoUsdCents, 8000);
      expect(ana.hasTasa, isTrue);
      final leg = ana.currencies.single;
      expect(leg.currency, ves);
      expect(leg.todayValueUsdCents, 8000);
      expect(leg.hasRate, isTrue);
      expect(leg.parallelRate?.nativePerUsd, Decimal.parse('50'));
      expect(leg.parallelRate?.source, 'binancep2p:ask');
    });

    test('VES person without an observation: falls back to frozen cost and '
        'flags "sin tasa", never a silent 1:1', () {
      final snapshot = engine(
        [
          account(
            person: 'Ana',
            native: BigInt.from(400000),
            realCostUsdCents: 10000,
          ),
        ],
        const {},
        now,
      );

      final ana = snapshot.personas.single;
      expect(ana.netoUsdCents, 10000);
      expect(ana.hasTasa, isFalse);
      expect(ana.currencies.single.hasRate, isFalse);
      expect(ana.currencies.single.parallelRate, isNull);
    });

    test('exposes the underlying Account id per currency leg (#209: the UI '
        'needs it to launch Conciliar/Archivar)', () {
      final snapshot = engine(
        [
          account(
            id: 'acc-claudia-usd',
            person: 'Claudia',
            currency: usd,
            native: BigInt.from(3700),
            realCostUsdCents: 3700,
          ),
        ],
        const {},
        now,
      );

      final leg = snapshot.personas.single.currencies.single;
      expect(leg.accountId, AccountId('acc-claudia-usd'));
    });

    test('one person, two currencies: grouped under one name, combined '
        'neto', () {
      final rates = {
        ves: RateView(
          currency: ves,
          parallel: RateObservationView(
            nativePerUsd: Decimal.parse('50'),
            observedAt: now,
            source: 'binancep2p:ask',
          ),
        ),
      };

      final snapshot = engine(
        [
          account(
            id: 'acc-usd',
            person: 'Ana',
            currency: usd,
            native: BigInt.from(5000),
            realCostUsdCents: 5000,
          ),
          account(
            id: 'acc-ves',
            person: 'Ana',
            native: BigInt.from(400000),
            realCostUsdCents: 10000,
          ),
        ],
        rates,
        now,
      );

      expect(snapshot.personas, hasLength(1));
      final ana = snapshot.personas.single;
      expect(ana.personName, 'Ana');
      expect(ana.currencies, hasLength(2));
      // 50 (USD) + 80 (VES @ 50) = 130.
      expect(ana.netoUsdCents, 13000);
    });

    test('negative balance: the sign is preserved, never flipped', () {
      final snapshot = engine(
        [
          account(
            person: 'Beto',
            currency: usd,
            native: BigInt.from(-1200),
            realCostUsdCents: -1200,
          ),
        ],
        const {},
        now,
      );

      expect(snapshot.personas.single.netoUsdCents, -1200);
      expect(snapshot.globalNetoUsdCents, -1200);
    });

    test('global neto: signed sum across every persona', () {
      final snapshot = engine(
        [
          account(
            id: 'acc-ana',
            person: 'Ana',
            currency: usd,
            native: BigInt.from(10000),
            realCostUsdCents: 10000,
          ),
          account(
            id: 'acc-beto',
            person: 'Beto',
            currency: usd,
            native: BigInt.from(-5000),
            realCostUsdCents: -5000,
          ),
        ],
        const {},
        now,
      );

      expect(snapshot.globalNetoUsdCents, 5000);
    });

    test('archived accounts are excluded from every total', () {
      final snapshot = engine(
        [
          account(
            id: 'acc-live',
            person: 'Ana',
            currency: usd,
            native: BigInt.from(10000),
            realCostUsdCents: 10000,
          ),
          account(
            id: 'acc-archived',
            person: 'Ana',
            currency: usd,
            native: BigInt.from(99999),
            realCostUsdCents: 99999,
            isArchived: true,
          ),
        ],
        const {},
        now,
      );

      expect(snapshot.personas.single.netoUsdCents, 10000);
    });

    test('empty catalog produces a zeroed snapshot with no personas', () {
      final snapshot = engine(const [], const {}, now);

      expect(snapshot.personas, isEmpty);
      expect(snapshot.globalNetoUsdCents, 0);
      expect(snapshot.calculatedAt, now);
    });

    test('BCV reference: folds every account\'s BCV valuation, USD at par, '
        'VES with a BCV rate, never feeding globalNetoUsdCents', () {
      final rates = {
        ves: RateView(
          currency: ves,
          parallel: RateObservationView(
            nativePerUsd: Decimal.parse('50'),
            observedAt: now,
            source: 'binancep2p:ask',
          ),
          bcv: RateObservationView(
            nativePerUsd: Decimal.parse('40'),
            observedAt: now,
            source: 'dolarapi:oficial',
          ),
        ),
      };

      final snapshot = engine(
        [
          account(
            id: 'acc-usd',
            person: 'Ana',
            currency: usd,
            native: BigInt.from(5000),
            realCostUsdCents: 5000,
          ),
          account(
            id: 'acc-ves',
            person: 'Ana',
            native: BigInt.from(400000),
            realCostUsdCents: 10000,
          ),
        ],
        rates,
        now,
      );

      // USD leg at par ($50) + VES leg at BCV 40 (4000/40 = $100) = $150.
      expect(snapshot.bcvReferenceUsdCents, 15000);
      // Parallel-valued neto stays independent: 50 + 80 (VES @ 50) = 130.
      expect(snapshot.globalNetoUsdCents, 13000);
    });

    test('BCV reference falls back to frozen cost when no BCV observation '
        'exists, never a silent 1:1', () {
      final snapshot = engine(
        [
          account(
            person: 'Ana',
            native: BigInt.from(400000),
            realCostUsdCents: 10000,
          ),
        ],
        const {},
        now,
      );

      expect(snapshot.bcvReferenceUsdCents, 10000);
    });

    test('single rounding per account: native/rate rounds once, half away '
        'from zero', () {
      final rates = {
        ves: RateView(
          currency: ves,
          parallel: RateObservationView(
            nativePerUsd: Decimal.parse('3'),
            observedAt: now,
            source: 'binancep2p:ask',
          ),
        ),
      };

      final snapshot = engine(
        [
          account(
            person: 'Ana',
            native: BigInt.from(100001),
            realCostUsdCents: 1,
          ),
        ],
        rates,
        now,
      );

      // 100001 / 3 = 33333.67 -> rounds to 33334.
      expect(snapshot.personas.single.netoUsdCents, 33334);
    });
  });
}
