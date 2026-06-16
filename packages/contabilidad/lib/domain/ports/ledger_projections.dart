import 'package:shared_kernel/shared_kernel.dart';
import '../transaction.dart';
import '../account_balance.dart';

export '../account_balance.dart';

abstract class LedgerProjections {
  void apply(Transaction event);
  void clear();
  AccountBalance accountBalance(AccountId id);
  int envelopeUsdBalance(EnvelopeId id);
}
