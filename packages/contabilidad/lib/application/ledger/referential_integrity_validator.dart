import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:shared_kernel/shared_kernel.dart';

class ReferentialIntegrityValidator {
  final CatalogRepository catalogRepository;

  ReferentialIntegrityValidator(this.catalogRepository);

  void validate(List<Posting> postings) {
    for (final posting in postings) {
      if (posting.target is AccountTarget) {
        final accountId = (posting.target as AccountTarget).accountId;
        final account = catalogRepository.getAccount(accountId);

        if (account == null) {
          throw TargetNotFound(
            'Account ${accountId.value} not found in catalog',
          );
        }

        if (posting.currency != account.nativeCurrency) {
          throw IncompatibleCurrency(
            'Posting currency ${posting.currency.value} does not match account ${accountId.value} native currency ${account.nativeCurrency.value}',
          );
        }
      } else if (posting.target is EnvelopeTarget) {
        final envelopeId = (posting.target as EnvelopeTarget).envelopeId;
        final envelope = catalogRepository.getEnvelope(envelopeId);

        if (envelope == null) {
          throw TargetNotFound(
            'Envelope ${envelopeId.value} not found in catalog',
          );
        }

        if (posting.currency != CurrencyCode('USD')) {
          throw IncompatibleCurrency(
            'Envelope ${envelopeId.value} must always be posted in USD, got ${posting.currency.value}',
          );
        }
      }
    }
  }
}
