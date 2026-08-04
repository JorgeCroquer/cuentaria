import 'account_balance.dart';

/// Splits a disposed/moved [amount] against a known [balance] (ADR-0017):
/// [covered] keeps its frozen average base cost; [excess] — money the app
/// didn't know it had — gets no historical cost basis. A negative balance
/// covers nothing. Shared by [RecordRealization]'s disposals and
/// [RecordTransfer]'s foreign-currency transfers (ADR-0018 §3).
({BigInt covered, BigInt excess}) splitByBalance(
  AccountBalance balance,
  BigInt amount,
) {
  final available =
      balance.native.amount < BigInt.zero ? BigInt.zero : balance.native.amount;
  final covered = amount < available ? amount : available;
  return (covered: covered, excess: amount - covered);
}
