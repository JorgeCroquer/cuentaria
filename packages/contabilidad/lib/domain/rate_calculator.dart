import 'package:decimal/decimal.dart';

/// Pure rate math for the Mover two-sided toggle (U1, #98): rate is always
/// **native-per-USD** (CONTEXT.md Hard Rule 2) and every derivation rounds
/// exactly once. The rate itself is never persisted — only the native
/// amounts it derives are posted to the ledger.
class RateCalculator {
  const RateCalculator._();

  /// rate = native / usd.
  static Decimal deriveRate({
    required BigInt usdCents,
    required BigInt nativeCents,
  }) {
    if (usdCents == BigInt.zero) {
      throw ArgumentError('usdCents must be non-zero to derive a rate.');
    }
    final ratio =
        Decimal.fromBigInt(nativeCents) / Decimal.fromBigInt(usdCents);
    return ratio.toDecimal(scaleOnInfinitePrecision: 6);
  }

  /// native = round(usd * rate).
  static BigInt deriveNativeCents({
    required BigInt usdCents,
    required Decimal rate,
  }) {
    return (Decimal.fromBigInt(usdCents) * rate).round().toBigInt();
  }

  /// usd = round(native / rate).
  static BigInt deriveUsdCents({
    required BigInt nativeCents,
    required Decimal rate,
  }) {
    if (rate == Decimal.zero) {
      throw ArgumentError('rate must be non-zero to derive an amount.');
    }
    return (Decimal.fromBigInt(nativeCents) / rate).round();
  }
}
