import 'package:contabilidad/application/unit_of_work.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';

/// [UnitOfWork] backed by a Drift transaction on [CuentariaDatabase].
///
/// Every repository writing through that same database instance joins the
/// transaction automatically — Drift propagates it through the zone — so
/// `DriftCatalogRepository`, `DriftCascadeRepository` and `DriftEventStore`
/// commit or roll back together. `DriftEventStore.append` opens its own
/// transaction per event; nesting is fine, Drift turns the inner ones into
/// savepoints.
///
/// Those repositories also keep an **in-memory cache** they update in place on
/// every write (see `DriftCatalogRepository`'s cache and
/// `DriftCascadeRepository._cache`). A rollback undoes the rows but not the
/// cache, which would leave reads serving accounts that never reached disk —
/// so on failure the caches are reloaded. That is what [onRollback] is for,
/// and passing the wrong list is how this silently rots.
class DriftUnitOfWork implements UnitOfWork {
  final CuentariaDatabase _db;
  final List<Future<void> Function()> _onRollback;

  DriftUnitOfWork(
    this._db, {
    List<Future<void> Function()> onRollback = const [],
  }) : _onRollback = onRollback;

  @override
  Future<T> run<T>(Future<T> Function() body) async {
    try {
      return await _db.transaction(body);
    } catch (_) {
      for (final reload in _onRollback) {
        await reload();
      }
      rethrow;
    }
  }
}
