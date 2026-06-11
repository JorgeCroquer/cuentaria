import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:shared_kernel/shared_kernel.dart';

abstract class CatalogRepository {
  void saveAccount(Account account);
  Account? getAccount(AccountId id);
  void saveEnvelope(Envelope envelope);
  Envelope? getEnvelope(EnvelopeId id);
  EnvelopeId getSystemEnvelope(EnvelopeRole role);
  void deleteEnvelope(EnvelopeId id);
}
