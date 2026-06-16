import 'package:shared_kernel/shared_kernel.dart';
import '../transaction.dart';
import 'log_filters.dart';

abstract class EventStore {
  Future<bool> append(Transaction event);
  Future<Transaction?> get(EventId id);
  Future<bool> hasReversal(EventId originalId);
  Future<List<Transaction>> queryLog({LogFilters? filters});
}
