import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:shared_kernel/shared_kernel.dart';

abstract class CatalogRepository {
  /// Reads are synchronous — served from an in-memory cache hydrated at boot.
  Account? getAccount(AccountId id);
  Envelope? getEnvelope(EnvelopeId id);
  EnvelopeId getSystemEnvelope(EnvelopeRole role);

  /// Writes are async to allow Drift persistence (F2-10).
  Future<void> saveAccount(Account account);
  Future<void> saveEnvelope(Envelope envelope);
  Future<void> deleteEnvelope(EnvelopeId id);
}
