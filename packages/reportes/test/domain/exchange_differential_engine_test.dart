import 'package:reportes/reportes.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

void main() {
  const engine = ExchangeDifferentialEngine();

  final month = ReportMonth(2026, 8);
  final differential = EnvelopeId('sys-differential');
  final comida = EnvelopeId('comida');
  final envelopes = [
    EnvelopeView(
      id: EnvelopeId('sys-differential'),
      name: 'Diferencial',
      role: EnvelopeRoleView.differential,
    ),
    EnvelopeView(
      id: EnvelopeId('comida'),
      name: 'Comida',
      role: EnvelopeRoleView.user,
    ),
  ];

  PatrimonioPoint pointWith({
    int? marketValueUsdCents,
    int realCostUsdCents = 0,
  }) => PatrimonioPoint(
    month: month,
    realCostUsdCents: realCostUsdCents,
    marketValueUsdCents: marketValueUsdCents,
  );

  TransactionView tx({
    required String id,
    EventId? reverses,
    required List<PostingView> postings,
  }) => TransactionView(
    id: EventId(id),
    reverses: reverses,
    hasAccountPosting: true,
    envelopePostings: postings,
  );

  test('realizado sums a +\$12 crypto gain and a -\$3 FX-expense loss into '
      '+\$9', () {
    final result = engine(
      [
        tx(
          id: 'evt-1',
          postings: [
            PostingView(envelopeId: differential, amountUsdCents: 1200),
          ],
        ),
        tx(
          id: 'evt-2',
          postings: [
            PostingView(envelopeId: differential, amountUsdCents: -300),
          ],
        ),
      ],
      const [],
      envelopes,
      pointWith(),
    );

    expect(result.realizadoUsdCents, 900);
  });

  test('realizado is 0 when there are no differential postings this month', () {
    final result = engine([], const [], envelopes, pointWith());

    expect(result.realizadoUsdCents, 0);
  });

  test('a user envelope posting never leaks into realizado', () {
    final result = engine(
      [
        tx(
          id: 'evt-1',
          postings: [PostingView(envelopeId: comida, amountUsdCents: -4000)],
        ),
      ],
      const [],
      envelopes,
      pointWith(),
    );

    expect(result.realizadoUsdCents, 0);
  });

  test('a Reversal of a later month subtracts its original from realizado', () {
    final result = engine(
      [
        tx(
          id: 'evt-1',
          postings: [
            PostingView(envelopeId: differential, amountUsdCents: 1200),
          ],
        ),
      ],
      [
        tx(
          id: 'evt-reversal',
          reverses: EventId('evt-1'),
          postings: [
            PostingView(envelopeId: differential, amountUsdCents: -1200),
          ],
        ),
      ],
      envelopes,
      pointWith(),
    );

    expect(result.realizadoUsdCents, 0);
  });

  test('no realizado is market value minus real cost: \$1080 - \$1000 = '
      '+\$80', () {
    final result = engine(
      const [],
      const [],
      envelopes,
      pointWith(realCostUsdCents: 100000, marketValueUsdCents: 108000),
    );

    expect(result.noRealizadoUsdCents, 8000);
  });

  test('no realizado is null when the point has no market value overlay', () {
    final result = engine(
      const [],
      const [],
      envelopes,
      pointWith(realCostUsdCents: 100000),
    );

    expect(result.noRealizadoUsdCents, isNull);
  });

  test('the result carries the point\'s month', () {
    final result = engine(const [], const [], envelopes, pointWith());

    expect(result.month, month);
  });
}
