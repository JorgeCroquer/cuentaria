import 'package:reportes/reportes.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

void main() {
  const engine = SpendingByEnvelopeEngine();

  final comida = EnvelopeId('comida');
  final transporte = EnvelopeId('transporte');
  final ajustes = EnvelopeId('ajustes');
  final diferencial = EnvelopeId('diferencial');
  final stage = EnvelopeId('stage');
  final apertura = EnvelopeId('apertura');

  final envelopes = [
    EnvelopeView(id: comida, name: 'Comida', role: EnvelopeRoleView.user),
    EnvelopeView(
      id: transporte,
      name: 'Transporte',
      role: EnvelopeRoleView.user,
    ),
    EnvelopeView(
      id: ajustes,
      name: 'Ajustes',
      role: EnvelopeRoleView.adjustments,
    ),
    EnvelopeView(
      id: diferencial,
      name: 'Diferencial',
      role: EnvelopeRoleView.differential,
    ),
    EnvelopeView(id: stage, name: 'Stage', role: EnvelopeRoleView.stage),
    EnvelopeView(
      id: apertura,
      name: 'Apertura',
      role: EnvelopeRoleView.opening,
    ),
  ];

  TransactionView expenseTx(
    String id,
    EnvelopeId envelopeId,
    int amountUsdCents,
  ) => TransactionView(
    id: EventId(id),
    hasAccountPosting: true,
    envelopePostings: [
      PostingView(envelopeId: envelopeId, amountUsdCents: amountUsdCents),
    ],
  );

  test('sums two expenses in different currencies into the same envelope by '
      'their frozen amount_usd', () {
    final result = engine(
      [
        expenseTx('evt-usd-40', comida, -4000),
        expenseTx('evt-bs-100', comida, -10000),
      ],
      const [],
      envelopes,
    );

    expect(result, {comida: 14000});
  });

  test('a Transfer between accounts has no envelope postings and never '
      'appears', () {
    final transfer = TransactionView(
      id: EventId('evt-transfer'),
      hasAccountPosting: true,
      envelopePostings: const [],
    );

    final result = engine([transfer], const [], envelopes);

    expect(result, isEmpty);
  });

  test('a Distribution between two user envelopes has no account posting and '
      'never appears, even though both legs touch role=user envelopes', () {
    final distribution = TransactionView(
      id: EventId('evt-distribution'),
      hasAccountPosting: false,
      envelopePostings: [
        PostingView(envelopeId: comida, amountUsdCents: -5000),
        PostingView(envelopeId: transporte, amountUsdCents: 5000),
      ],
    );

    final result = engine([distribution], const [], envelopes);

    expect(result, isEmpty);
  });

  test(
    'an Adjustment of -\$0.60 appears in Ajustes, never in a user envelope',
    () {
      final adjustment = expenseTx('evt-adjustment', ajustes, -60);

      final result = engine([adjustment], const [], envelopes);

      expect(result, {ajustes: -60});
    },
  );

  test(
    'a CryptoSale with +\$12 differential appears in Diferencial realizado',
    () {
      final cryptoSale = TransactionView(
        id: EventId('evt-crypto-sale'),
        hasAccountPosting: true,
        envelopePostings: [
          PostingView(envelopeId: diferencial, amountUsdCents: 1200),
        ],
      );

      final result = engine([cryptoSale], const [], envelopes);

      expect(result, {diferencial: 1200});
    },
  );

  test('Stage and Apertura postings never appear — they are not flow', () {
    final result = engine(
      [
        expenseTx('evt-stage', stage, 2000),
        expenseTx('evt-opening', apertura, 5000),
      ],
      const [],
      envelopes,
    );

    expect(result, isEmpty);
  });

  test('a positive (funding) posting into a user envelope is not gasto', () {
    final income = expenseTx('evt-income', comida, 3000);

    final result = engine([income], const [], envelopes);

    expect(result, isEmpty);
  });

  test('a Reversal of the \$40 USD expense leaves Comida at \$100, the '
      'remaining Bs expense — the reversal itself posts no negative gasto', () {
    final usdExpense = expenseTx('evt-usd-40', comida, -4000);
    final bsExpense = expenseTx('evt-bs-100', comida, -10000);
    final reversal = TransactionView(
      id: EventId('evt-reversal'),
      reverses: EventId('evt-usd-40'),
      hasAccountPosting: true,
      envelopePostings: [PostingView(envelopeId: comida, amountUsdCents: 4000)],
    );

    final result = engine([usdExpense, bsExpense], [reversal], envelopes);

    expect(result, {comida: 10000});
  });

  test('an envelope with net-zero spending in the month does not appear', () {
    final expense = expenseTx('evt-usd-40', comida, -4000);
    final reversal = TransactionView(
      id: EventId('evt-reversal'),
      reverses: EventId('evt-usd-40'),
      hasAccountPosting: true,
      envelopePostings: [PostingView(envelopeId: comida, amountUsdCents: 4000)],
    );

    final result = engine([expense], [reversal], envelopes);

    expect(result, isEmpty);
  });

  test('a reversal that does not target a transaction in this month is '
      'ignored', () {
    final expense = expenseTx('evt-usd-40', comida, -4000);
    final unrelatedReversal = TransactionView(
      id: EventId('evt-reversal'),
      reverses: EventId('evt-not-in-month'),
      hasAccountPosting: true,
      envelopePostings: [
        PostingView(envelopeId: transporte, amountUsdCents: 1000),
      ],
    );

    final result = engine([expense], [unrelatedReversal], envelopes);

    expect(result, {comida: 4000});
  });

  test('no transactions and no reversals means an empty result', () {
    final result = engine(const [], const [], envelopes);

    expect(result, isEmpty);
  });
}
