import 'package:reportes/reportes.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

void main() {
  const engine = FundingPaceEngine();

  final viaje = EnvelopeId('viaje');
  final reportMonth = ReportMonth(2026, 9);
  final dueDateInSixMonths = DateTime(2027, 3, 1);

  FundingEnvelopeView goalEnvelope({
    int balanceUsdCents = 0,
    DateTime? dueDate,
  }) => FundingEnvelopeView(
    id: viaje,
    name: 'Viaje',
    balanceUsdCents: balanceUsdCents,
    target: GoalLineView(amountUsd: 120000, dueDate: dueDate),
  );

  TransactionView inflow(String id, int amountUsdCents) => TransactionView(
    id: EventId(id),
    hasAccountPosting: false,
    envelopePostings: [
      PostingView(envelopeId: viaje, amountUsdCents: amountUsdCents),
    ],
  );

  test('goal \$1,200 due in 6 months, \$0 balance, no aporte this month → '
      'requires \$200/mo and is behind', () {
    final result = engine(const [], const [], [
      goalEnvelope(dueDate: dueDateInSixMonths),
    ], reportMonth);

    expect(result, [
      FundingPaceRow(
        envelopeId: viaje,
        name: 'Viaje',
        contributedThisMonthUsdCents: 0,
        requiredPerMonthUsdCents: 20000,
        status: FundingPaceStatus.behind,
      ),
    ]);
  });

  test('aportado \$250 against a \$200/mo requirement is on pace', () {
    final result = engine(
      [inflow('evt-aporte', 25000)],
      const [],
      [goalEnvelope(dueDate: dueDateInSixMonths)],
      reportMonth,
    );

    expect(result.single.contributedThisMonthUsdCents, 25000);
    expect(result.single.requiredPerMonthUsdCents, 20000);
    expect(result.single.status, FundingPaceStatus.onPace);
  });

  test('aportado \$100 against a \$200/mo requirement is behind', () {
    final result = engine(
      [inflow('evt-aporte', 10000)],
      const [],
      [goalEnvelope(dueDate: dueDateInSixMonths)],
      reportMonth,
    );

    expect(result.single.status, FundingPaceStatus.behind);
  });

  test('a balance that already meets the goal is goalReached regardless of '
      'this month\'s aporte', () {
    final result = engine(
      [inflow('evt-aporte', 10000)],
      const [],
      [goalEnvelope(balanceUsdCents: 120000, dueDate: dueDateInSixMonths)],
      reportMonth,
    );

    expect(result.single.status, FundingPaceStatus.goalReached);
    expect(result.single.requiredPerMonthUsdCents, 0);
  });

  test('no due date means only the aportado is reported, no status', () {
    final result = engine(
      [inflow('evt-aporte', 25000)],
      const [],
      [goalEnvelope(dueDate: null)],
      reportMonth,
    );

    expect(result.single.contributedThisMonthUsdCents, 25000);
    expect(result.single.requiredPerMonthUsdCents, isNull);
    expect(result.single.status, isNull);
  });

  test('a Cap never has a due date, so it only ever reports the aportado', () {
    final envelope = FundingEnvelopeView(
      id: viaje,
      name: 'Viaje',
      balanceUsdCents: 0,
      target: const CapView(amountUsd: 50000),
    );

    final result = engine(
      [inflow('evt-aporte', 10000)],
      const [],
      [envelope],
      reportMonth,
    );

    expect(result.single.contributedThisMonthUsdCents, 10000);
    expect(result.single.requiredPerMonthUsdCents, isNull);
    expect(result.single.status, isNull);
  });

  test(
    'an expense leaving the envelope does not count as a negative aporte',
    () {
      final expense = inflow('evt-gasto', -5000);

      final result = engine(
        [inflow('evt-aporte', 25000), expense],
        const [],
        [goalEnvelope(dueDate: dueDateInSixMonths)],
        reportMonth,
      );

      expect(result.single.contributedThisMonthUsdCents, 25000);
    },
  );

  test('a same-month reversal of an expense does not count as an aporte', () {
    final expense = TransactionView(
      id: EventId('evt-gasto'),
      hasAccountPosting: true,
      envelopePostings: [PostingView(envelopeId: viaje, amountUsdCents: -5000)],
    );
    final reversal = TransactionView(
      id: EventId('evt-reversal'),
      reverses: EventId('evt-gasto'),
      hasAccountPosting: true,
      envelopePostings: [PostingView(envelopeId: viaje, amountUsdCents: 5000)],
    );

    final result = engine(
      [expense, reversal],
      const [],
      [goalEnvelope(dueDate: dueDateInSixMonths)],
      reportMonth,
    );

    expect(result.single.contributedThisMonthUsdCents, 0);
  });

  test('an envelope with no funding target never appears', () {
    final envelope = FundingEnvelopeView(
      id: viaje,
      name: 'Viaje',
      balanceUsdCents: 0,
      target: const NoTargetView(),
    );

    final result = engine([], const [], [envelope], reportMonth);

    expect(result, isEmpty);
  });

  test('no envelopes with a funding target means an empty result', () {
    final result = engine(const [], const [], const [], reportMonth);

    expect(result, isEmpty);
  });

  test('a Reversal subtracts its original aporte from this month\'s total', () {
    final aporte = inflow('evt-aporte', 25000);
    final reversal = TransactionView(
      id: EventId('evt-reversal'),
      reverses: EventId('evt-aporte'),
      hasAccountPosting: false,
      envelopePostings: [
        PostingView(envelopeId: viaje, amountUsdCents: -25000),
      ],
    );

    final result = engine([aporte], [reversal], [
      goalEnvelope(dueDate: dueDateInSixMonths),
    ], reportMonth);

    expect(result.single.contributedThisMonthUsdCents, 0);
  });
}
