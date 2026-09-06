import 'package:reportes/reportes.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

void main() {
  const engine = IncomeBySourceEngine();

  final stage = EnvelopeId('stage');
  final comida = EnvelopeId('comida');
  final ajustes = EnvelopeId('ajustes');
  final apertura = EnvelopeId('apertura');

  final envelopes = [
    EnvelopeView(id: stage, name: 'Stage', role: EnvelopeRoleView.stage),
    EnvelopeView(id: comida, name: 'Comida', role: EnvelopeRoleView.user),
    EnvelopeView(
      id: ajustes,
      name: 'Ajustes',
      role: EnvelopeRoleView.adjustments,
    ),
    EnvelopeView(
      id: apertura,
      name: 'Apertura',
      role: EnvelopeRoleView.opening,
    ),
  ];

  TransactionView incomeTx(
    String id,
    EnvelopeId envelopeId,
    int amountUsdCents, {
    String? source,
  }) => TransactionView(
    id: EventId(id),
    hasAccountPosting: true,
    envelopePostings: [
      PostingView(envelopeId: envelopeId, amountUsdCents: amountUsdCents),
    ],
    source: source,
  );

  test('groups two incomes from the same source and one from another, '
      'landing in Stage as every quick-add Income does', () {
    final result = engine(
      [
        incomeTx('evt-a-300', stage, 30000, source: 'Cliente A'),
        incomeTx('evt-a-200', stage, 20000, source: 'Cliente A'),
        incomeTx('evt-b-150', stage, 15000, source: 'Cliente B'),
      ],
      const [],
      envelopes,
    );

    expect(result, {'Cliente A': 50000, 'Cliente B': 15000});
  });

  test('a null or empty source groups as Sin fuente', () {
    final result = engine(
      [
        incomeTx('evt-null', stage, 10000),
        incomeTx('evt-empty', stage, 5000, source: ''),
      ],
      const [],
      envelopes,
    );

    expect(result, {'Sin fuente': 15000});
  });

  test('an Opening of \$1,000 never appears', () {
    final result = engine(
      [incomeTx('evt-opening', apertura, 100000, source: 'Cliente A')],
      const [],
      envelopes,
    );

    expect(result, isEmpty);
  });

  test('an absorbed Adjustment never appears', () {
    final result = engine(
      [incomeTx('evt-adjustment', ajustes, 60, source: 'Cliente A')],
      const [],
      envelopes,
    );

    expect(result, isEmpty);
  });

  test('a Distribution between two user envelopes has no account posting '
      'and never appears, even though its incoming leg lands in a user '
      'envelope', () {
    final distribution = TransactionView(
      id: EventId('evt-distribution'),
      hasAccountPosting: false,
      envelopePostings: [
        PostingView(envelopeId: stage, amountUsdCents: -5000),
        PostingView(envelopeId: comida, amountUsdCents: 5000),
      ],
      source: 'Cliente A',
    );

    final result = engine([distribution], const [], envelopes);

    expect(result, isEmpty);
  });

  test('an expense (money leaving Stage) is not income', () {
    final expense = incomeTx('evt-expense', stage, -4000, source: 'Cliente A');

    final result = engine([expense], const [], envelopes);

    expect(result, isEmpty);
  });

  test('a Reversal of the \$300 income leaves Cliente A at \$0, so it does '
      'not appear', () {
    final income = incomeTx('evt-a-300', stage, 30000, source: 'Cliente A');
    final reversal = TransactionView(
      id: EventId('evt-reversal'),
      reverses: EventId('evt-a-300'),
      hasAccountPosting: true,
      envelopePostings: [
        PostingView(envelopeId: stage, amountUsdCents: -30000),
      ],
      source: 'Cliente A',
    );

    final result = engine([income], [reversal], envelopes);

    expect(result, isEmpty);
  });

  test('no transactions and no reversals means an empty result', () {
    final result = engine(const [], const [], envelopes);

    expect(result, isEmpty);
  });
}
