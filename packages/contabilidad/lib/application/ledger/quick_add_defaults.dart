import 'package:shared_kernel/shared_kernel.dart';

import '../../domain/ports/event_store.dart';
import '../../domain/posting_target.dart';

const _expenseTypes = {'Expense', 'ForeignCurrencyExpense'};

/// Smart defaults for the quick-add expense capture (U1, #97): the last
/// paying Account and the Envelopes ordered by how often they were spent
/// from, both derived on the fly from [EventStore.queryLog] — there is no
/// preferences store.
class QuickAddDefaults {
  final EventStore _store;

  QuickAddDefaults(this._store);

  /// The Account posted against in the most recently recorded expense, or
  /// `null` if none has been recorded yet.
  Future<AccountId?> lastUsedAccount() async {
    final log = await _store.queryLog();
    for (final tx in log.reversed) {
      if (!_expenseTypes.contains(tx.metadata.type)) continue;
      for (final posting in tx.postings) {
        final target = posting.target;
        if (target is AccountTarget) return target.accountId;
      }
    }
    return null;
  }

  /// User Envelopes that have received an expense at least once, ordered by
  /// descending expense count.
  Future<List<EnvelopeId>> envelopesByFrequency() async {
    final log = await _store.queryLog();
    final counts = <EnvelopeId, int>{};

    for (final tx in log) {
      if (!_expenseTypes.contains(tx.metadata.type)) continue;
      for (final target in tx.postings.map((p) => p.target)) {
        if (target is EnvelopeTarget) {
          counts.update(
            target.envelopeId,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
      }
    }

    final envelopeIds =
        counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return envelopeIds;
  }
}
