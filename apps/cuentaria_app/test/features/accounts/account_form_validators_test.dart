import 'package:cuentaria_app/features/accounts/ui/account_form_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateAccountName', () {
    test('rejects an empty name', () {
      expect(validateAccountName(''), isNotNull);
      expect(validateAccountName('   '), isNotNull);
    });

    test('accepts a non-empty name', () {
      expect(validateAccountName('Bancamiga'), isNull);
    });

    test('rejects a name longer than 50 characters', () {
      expect(validateAccountName('A' * 51), isNotNull);
      expect(validateAccountName('A' * 50), isNull);
    });
  });

  group('validateOpeningBalance', () {
    test('accepts an empty value — opening balance is optional', () {
      expect(validateOpeningBalance(''), isNull);
      expect(validateOpeningBalance('   '), isNull);
    });

    test('accepts a whole number', () {
      expect(validateOpeningBalance('200'), isNull);
      expect(validateOpeningBalance('0'), isNull);
    });

    test('rejects a decimal amount — money must be an integer', () {
      expect(validateOpeningBalance('100.50'), isNotNull);
    });

    test('rejects a negative amount', () {
      expect(validateOpeningBalance('-5'), isNotNull);
    });

    test('rejects non-numeric text', () {
      expect(validateOpeningBalance('abc'), isNotNull);
    });
  });

  group('validateOpeningBalanceRate', () {
    test('is not required for a USD account', () {
      expect(
        validateOpeningBalanceRate(
          currency: 'USD',
          openingBalanceText: '200',
          rateText: '',
        ),
        isNull,
      );
    });

    test('is not required when there is no opening balance', () {
      expect(
        validateOpeningBalanceRate(
          currency: 'VES',
          openingBalanceText: '',
          rateText: '',
        ),
        isNull,
      );
      expect(
        validateOpeningBalanceRate(
          currency: 'VES',
          openingBalanceText: '0',
          rateText: '',
        ),
        isNull,
      );
    });

    test(
      'is required for a non-USD account with a non-zero opening balance',
      () {
        expect(
          validateOpeningBalanceRate(
            currency: 'VES',
            openingBalanceText: '50000',
            rateText: '',
          ),
          isNotNull,
        );
      },
    );

    test('rejects a non-numeric rate', () {
      expect(
        validateOpeningBalanceRate(
          currency: 'VES',
          openingBalanceText: '50000',
          rateText: 'abc',
        ),
        isNotNull,
      );
    });

    test('rejects a zero or negative rate', () {
      expect(
        validateOpeningBalanceRate(
          currency: 'VES',
          openingBalanceText: '50000',
          rateText: '0',
        ),
        isNotNull,
      );
      expect(
        validateOpeningBalanceRate(
          currency: 'VES',
          openingBalanceText: '50000',
          rateText: '-3.5',
        ),
        isNotNull,
      );
    });

    test('accepts a positive rate', () {
      expect(
        validateOpeningBalanceRate(
          currency: 'VES',
          openingBalanceText: '50000',
          rateText: '3.5',
        ),
        isNull,
      );
    });
  });
}
