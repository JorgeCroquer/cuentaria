import 'package:drift/drift.dart';

/// Web has no durable encrypted store in F2 (ADR-0014); the composition root
/// selects in-memory adapters and never calls this.
Future<QueryExecutor> openAppDatabase(List<int> encryptionKey) {
  throw UnsupportedError('No durable local store on web (ADR-0014).');
}
