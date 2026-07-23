import 'package:drift/drift.dart';

/// Web has no durable local store in F2 (ADR-0014); the composition root
/// selects the in-memory adapter and never calls this.
Future<QueryExecutor> openTasasDatabase() {
  throw UnsupportedError('No durable local store on web (ADR-0016).');
}
