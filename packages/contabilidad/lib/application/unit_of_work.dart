/// Runs a group of writes so that either all of them land or none do.
///
/// Restoring a Backup File writes the Catalog, the Cascade and the event log
/// in one go, and ADR-0021 §6 demands all-or-nothing: dying halfway through
/// must leave the device as it was, not half restored. A partial restore is
/// the one failure the ledger cannot detect — balances add up, they are just
/// missing movements, and the user has no way to tell that from a good one.
///
/// Atomicity is a property of the storage engine, but the application layer
/// must not know Drift exists (dependency inversion), so it enters here as a
/// port with a single method.
abstract class UnitOfWork {
  /// Runs [body] as one unit. Its writes are committed only if [body]
  /// completes; if it throws, they are rolled back and the error is rethrown.
  Future<T> run<T>(Future<T> Function() body);
}
