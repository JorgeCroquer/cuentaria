import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

void main() {
  group('ReferentialIntegrityValidator', () {
    late InMemoryCatalogRepository catalog;
    late ReferentialIntegrityValidator validator;

    setUp(() {
      catalog = InMemoryCatalogRepository();
      validator = ReferentialIntegrityValidator(catalog);

      catalog.saveAccount(
        Account(
          id: AccountId('acc-usd'),
          name: 'USD Account',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      catalog.saveAccount(
        Account(
          id: AccountId('acc-ves'),
          name: 'VES Account',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      catalog.saveEnvelope(
        Envelope(
          id: EnvelopeId('env-1'),
          name: 'General',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
    });

    test(
      'validates successfully when all targets exist and currencies match',
      () {
        final postings = [
          Posting(
            target: AccountTarget(AccountId('acc-usd')),
            amountNative: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 100,
          ),
          Posting(
            target: EnvelopeTarget(EnvelopeId('env-1')),
            amountNative: Money(
              amount: BigInt.from(-100),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: -100,
          ),
        ];

        expect(() => validator.validate(postings), returnsNormally);
      },
    );

    test('throws TargetNotFound if account does not exist', () {
      final postings = [
        Posting(
          target: AccountTarget(AccountId('acc-missing')),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 100,
        ),
      ];

      expect(
        () => validator.validate(postings),
        throwsA(isA<TargetNotFound>()),
      );
    });

    test('throws TargetNotFound if envelope does not exist', () {
      final postings = [
        Posting(
          target: EnvelopeTarget(EnvelopeId('env-missing')),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 100,
        ),
      ];

      expect(
        () => validator.validate(postings),
        throwsA(isA<TargetNotFound>()),
      );
    });

    test('throws IncompatibleCurrency if account currency mismatches', () {
      final postings = [
        Posting(
          target: AccountTarget(AccountId('acc-usd')),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('VES'),
          ),
          currency: CurrencyCode('VES'),
          amountUsd: 100,
        ),
      ];

      expect(
        () => validator.validate(postings),
        throwsA(isA<IncompatibleCurrency>()),
      );
    });

    test('throws IncompatibleCurrency if envelope currency is not USD', () {
      final postings = [
        Posting(
          target: EnvelopeTarget(EnvelopeId('env-1')),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('VES'),
          ),
          currency: CurrencyCode('VES'),
          amountUsd: 100,
        ),
      ];

      expect(
        () => validator.validate(postings),
        throwsA(isA<IncompatibleCurrency>()),
      );
    });
  });
}
