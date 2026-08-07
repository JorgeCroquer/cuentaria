import 'package:contabilidad/application/unit_of_work.dart';

/// [UnitOfWork] for the in-memory adapters (tests and web), which have no
/// transaction to open: it just runs the body.
///
/// ponytail: no rollback — the in-memory repositories keep whatever they wrote
/// before the failure. A test that has to prove all-or-nothing must therefore
/// run against Drift; see `drift_unit_of_work_test.dart`.
class InMemoryUnitOfWork implements UnitOfWork {
  const InMemoryUnitOfWork();

  @override
  Future<T> run<T>(Future<T> Function() body) => body();
}
