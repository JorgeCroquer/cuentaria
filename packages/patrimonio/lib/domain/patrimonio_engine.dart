import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'account_view.dart';
import 'envelope_view.dart';
import 'patrimonio_snapshot.dart';
import 'rate_view.dart';

/// Pure valuation engine (ADR-0016 §5): "the parallel rate values, the BCV
/// informs". Takes only patrimonio-owned views — no Flutter, no other
/// context's domain (ADR-0005); app-layer wiring is responsible for mapping
/// contabilidad/tasas data into [AccountView]/[RateView] beforehand.
class PatrimonioEngine {
  static final _usd = CurrencyCode('USD');

  const PatrimonioEngine();

  PatrimonioSnapshot call(
    List<AccountView> accounts,
    Map<CurrencyCode, RateView> rates,
    List<EnvelopeView> envelopes,
    DateTime now,
  ) {
    final groups = <CurrencyCode, _MutableGroup>{};

    for (final account in accounts) {
      if (account.isArchived) continue;

      final group = groups.putIfAbsent(
        account.currency,
        () => _MutableGroup(account.currency),
      );
      group.nativeMinorAmount += account.nativeMinorAmount;
      group.realCostUsdCents += account.realCostUsdCents;

      if (account.currency == _usd) {
        group.todayValueUsdCents += account.realCostUsdCents;
        group.bcvReferenceUsdCents += account.realCostUsdCents;
        continue;
      }

      final rate = rates[account.currency];
      final parallel = rate?.parallel;
      final bcv = rate?.bcv;

      if (parallel == null) {
        group.todayValueUsdCents += account.realCostUsdCents;
        group.hasRate = false;
      } else {
        group.todayValueUsdCents += _convert(
          account.nativeMinorAmount,
          parallel.nativePerUsd,
        );
        group.observedAt = parallel.observedAt;
      }

      group.bcvReferenceUsdCents +=
          bcv == null
              ? account.realCostUsdCents
              : _convert(account.nativeMinorAmount, bcv.nativePerUsd);
    }

    final accountGroups = groups.values.map((g) => g.toView()).toList();

    var realCost = 0;
    var todayValue = 0;
    var bcvReference = 0;
    var hasMissingRate = false;
    for (final group in accountGroups) {
      realCost += group.realCostUsdCents;
      todayValue += group.todayValueUsdCents;
      bcvReference += group.bcvReferenceUsdCents;
      if (!group.hasRate) hasMissingRate = true;
    }

    return PatrimonioSnapshot(
      realCostUsdCents: realCost,
      todayValueUsdCents: todayValue,
      unrealizedPnlUsdCents: todayValue - realCost,
      bcvReferenceUsdCents: bcvReference,
      hasMissingRate: hasMissingRate,
      accountGroups: accountGroups,
      envelopes: _buildEnvelopes(envelopes, now),
    );
  }

  static int _convert(BigInt nativeMinorAmount, Decimal nativePerUsd) {
    return (Decimal.fromBigInt(nativeMinorAmount) / nativePerUsd)
        .round()
        .toInt();
  }

  /// User Envelopes always appear, with [_metadataFor] computed from their
  /// target. Stage/Apertura appear only with a positive balance (S2:
  /// "highlighted only when balance > 0"); Diferencial/Ajustes never appear
  /// — they are accounting mechanics, not something to fund or track.
  static List<PatrimonioEnvelope> _buildEnvelopes(
    List<EnvelopeView> envelopes,
    DateTime now,
  ) {
    final today = DateTime.utc(now.year, now.month, now.day);
    final result = <PatrimonioEnvelope>[];

    for (final envelope in envelopes) {
      switch (envelope.role) {
        case EnvelopeRoleView.differential:
        case EnvelopeRoleView.adjustments:
          continue;
        case EnvelopeRoleView.stage:
        case EnvelopeRoleView.opening:
          if (envelope.balanceUsd <= 0) continue;
          result.add(
            PatrimonioEnvelope(
              id: envelope.id,
              name: envelope.name,
              role: envelope.role,
              balanceUsd: envelope.balanceUsd,
              target: envelope.target,
              metadata: const NoMetadata(),
            ),
          );
        case EnvelopeRoleView.user:
          result.add(
            PatrimonioEnvelope(
              id: envelope.id,
              name: envelope.name,
              role: envelope.role,
              balanceUsd: envelope.balanceUsd,
              target: envelope.target,
              metadata: _metadataFor(
                envelope.target,
                envelope.balanceUsd,
                today,
              ),
            ),
          );
      }
    }
    return result;
  }

  static EnvelopeMetadata _metadataFor(
    FundingTargetView target,
    int balanceUsd,
    DateTime today,
  ) {
    switch (target) {
      case NoTargetView():
        return const NoMetadata();

      case CapView(:final amountUsd):
        if (amountUsd <= 0) return const NoMetadata();
        return CapMetadata(
          fillPercent: _percentOf(balanceUsd, amountUsd),
          isOverfilled: balanceUsd > amountUsd,
        );

      case GoalLineView(:final amountUsd, :final dueDate):
        if (amountUsd <= 0) return const NoMetadata();
        return _goalLineMetadata(
          amountUsd: amountUsd,
          balanceUsd: balanceUsd,
          dueDate: dueDate,
          today: today,
        );
    }
  }

  static GoalLineMetadata _goalLineMetadata({
    required int amountUsd,
    required int balanceUsd,
    required DateTime? dueDate,
    required DateTime today,
  }) {
    final progressPercent = _percentOf(balanceUsd, amountUsd);
    final isFulfilled = balanceUsd >= amountUsd;

    if (isFulfilled) {
      return GoalLineMetadata(
        progressPercent: 100,
        quotaPerMonthUsd: 0,
        daysRemaining: dueDate == null ? null : _daysUntil(dueDate, today),
        isOverdue: false,
        isFulfilled: true,
      );
    }

    if (dueDate == null) {
      return GoalLineMetadata(
        progressPercent: progressPercent,
        quotaPerMonthUsd: 0,
        daysRemaining: null,
        isOverdue: false,
        isFulfilled: false,
      );
    }

    final due = DateTime.utc(dueDate.year, dueDate.month, dueDate.day);
    if (due.isBefore(today)) {
      return GoalLineMetadata(
        progressPercent: progressPercent,
        quotaPerMonthUsd: 0,
        daysRemaining: 0,
        isOverdue: true,
        isFulfilled: false,
      );
    }

    final daysLeft = due.difference(today).inDays;
    final monthsLeft = _max(1, _ceilDiv(daysLeft, 30));
    final quota = _ceilDiv(amountUsd - balanceUsd, monthsLeft);

    return GoalLineMetadata(
      progressPercent: progressPercent,
      quotaPerMonthUsd: quota,
      daysRemaining: daysLeft,
      isOverdue: false,
      isFulfilled: false,
    );
  }

  static int _daysUntil(DateTime dueDate, DateTime today) {
    final due = DateTime.utc(dueDate.year, dueDate.month, dueDate.day);
    final diff = due.difference(today).inDays;
    return diff < 0 ? 0 : diff;
  }

  static int _percentOf(int balanceUsd, int targetUsd) {
    if (balanceUsd <= 0) return 0;
    if (balanceUsd >= targetUsd) return 100;
    return ((balanceUsd * 100) ~/ targetUsd).clamp(0, 100);
  }

  static int _ceilDiv(int a, int b) => (a + b - 1) ~/ b;

  static int _max(int a, int b) => a > b ? a : b;
}

class _MutableGroup {
  final CurrencyCode currency;
  BigInt nativeMinorAmount = BigInt.zero;
  int realCostUsdCents = 0;
  int todayValueUsdCents = 0;
  int bcvReferenceUsdCents = 0;
  bool hasRate = true;
  DateTime? observedAt;

  _MutableGroup(this.currency);

  PatrimonioAccountGroup toView() => PatrimonioAccountGroup(
    currency: currency,
    nativeMinorAmount: nativeMinorAmount,
    realCostUsdCents: realCostUsdCents,
    todayValueUsdCents: todayValueUsdCents,
    bcvReferenceUsdCents: bcvReferenceUsdCents,
    hasRate: hasRate,
    observedAt: observedAt,
  );
}
