import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:test/test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('Account', () {
    test('mergeWith resolves via Last-Write-Wins based on updatedAt', () {
      final olderAccount = Account(
        id: AccountId('acc-1'),
        name: 'Older Name',
        nativeCurrency: CurrencyCode('USD'),
        provider: 'Prov A',
        isArchived: false,
        updatedAt: DateTime(2023, 1, 1),
      );

      final newerAccount = Account(
        id: AccountId('acc-1'),
        name: 'Newer Name',
        nativeCurrency: CurrencyCode('VES'),
        provider: 'Prov B',
        isArchived: true,
        updatedAt: DateTime(2023, 1, 2),
      );

      // older.mergeWith(newer) should pick newer
      final merged1 = olderAccount.mergeWith(newerAccount);
      expect(merged1.name, 'Newer Name');
      expect(merged1.nativeCurrency.value, 'VES');
      expect(merged1.provider, 'Prov B');
      expect(merged1.isArchived, true);
      expect(merged1.updatedAt, DateTime(2023, 1, 2));

      // newer.mergeWith(older) should still pick newer
      final merged2 = newerAccount.mergeWith(olderAccount);
      expect(merged2.name, 'Newer Name');
      expect(merged2.nativeCurrency.value, 'VES');
      expect(merged2.provider, 'Prov B');
      expect(merged2.isArchived, true);
      expect(merged2.updatedAt, DateTime(2023, 1, 2));
    });

    test('mergeWith keeps current if timestamps are exactly the same', () {
      final acc1 = Account(
        id: AccountId('acc-1'),
        name: 'Name 1',
        nativeCurrency: CurrencyCode('USD'),
        provider: 'Prov 1',
        isArchived: false,
        updatedAt: DateTime(2023, 1, 1),
      );

      final acc2 = Account(
        id: AccountId('acc-1'),
        name: 'Name 2',
        nativeCurrency: CurrencyCode('VES'),
        provider: 'Prov 2',
        isArchived: true,
        updatedAt: DateTime(2023, 1, 1),
      );

      final merged = acc1.mergeWith(acc2);
      expect(merged.name, 'Name 1'); // Keeps current when equal
    });

    test('mergeWith throws if IDs are different', () {
      final acc1 = Account(
        id: AccountId('acc-1'),
        name: 'Name 1',
        nativeCurrency: CurrencyCode('USD'),
        updatedAt: DateTime(2023, 1, 1),
        isArchived: false,
      );

      final acc2 = Account(
        id: AccountId('acc-2'),
        name: 'Name 2',
        nativeCurrency: CurrencyCode('USD'),
        updatedAt: DateTime(2023, 1, 2),
        isArchived: false,
      );

      expect(() => acc1.mergeWith(acc2), throwsArgumentError);
    });

    test('colorHex reads the "color" key from meta', () {
      final withColor = Account(
        id: AccountId('acc-1'),
        name: 'Name 1',
        nativeCurrency: CurrencyCode('USD'),
        updatedAt: DateTime(2023, 1, 1),
        isArchived: false,
        meta: {'color': '#FF5500'},
      );
      expect(withColor.colorHex, '#FF5500');

      final withoutColor = Account(
        id: AccountId('acc-2'),
        name: 'Name 2',
        nativeCurrency: CurrencyCode('USD'),
        updatedAt: DateTime(2023, 1, 1),
        isArchived: false,
      );
      expect(withoutColor.colorHex, isNull);
    });

    test('lastReconciledAt reads the "lastReconciledAt" key from meta', () {
      final never = Account(
        id: AccountId('acc-1'),
        name: 'Name 1',
        nativeCurrency: CurrencyCode('USD'),
        updatedAt: DateTime(2023, 1, 1),
        isArchived: false,
      );
      expect(never.lastReconciledAt, isNull);

      final reconciled = Account(
        id: AccountId('acc-1'),
        name: 'Name 1',
        nativeCurrency: CurrencyCode('USD'),
        updatedAt: DateTime(2023, 1, 1),
        isArchived: false,
        meta: {'lastReconciledAt': '2024-03-05T12:00:00.000Z'},
      );
      expect(
        reconciled.lastReconciledAt,
        DateTime.parse('2024-03-05T12:00:00.000Z'),
      );
    });

    test('withLastReconciledAt stamps the timestamp and advances updatedAt, '
        'preserving other meta keys', () {
      final account = Account(
        id: AccountId('acc-1'),
        name: 'Name 1',
        nativeCurrency: CurrencyCode('USD'),
        updatedAt: DateTime(2023, 1, 1),
        isArchived: false,
        meta: {'color': '#FF5500'},
      );

      final stamped = account.withLastReconciledAt(DateTime.utc(2024, 3, 5));

      expect(stamped.lastReconciledAt, DateTime.utc(2024, 3, 5));
      expect(stamped.updatedAt, DateTime.utc(2024, 3, 5));
      expect(stamped.colorHex, '#FF5500');
      expect(stamped.id, account.id);
      expect(stamped.name, account.name);
    });

    test('mergeWith carries meta from the winning side', () {
      final older = Account(
        id: AccountId('acc-1'),
        name: 'Older',
        nativeCurrency: CurrencyCode('USD'),
        updatedAt: DateTime(2023, 1, 1),
        isArchived: false,
        meta: {'color': '#OLD'},
      );
      final newer = Account(
        id: AccountId('acc-1'),
        name: 'Newer',
        nativeCurrency: CurrencyCode('USD'),
        updatedAt: DateTime(2023, 1, 2),
        isArchived: false,
        meta: {'color': '#NEW'},
      );

      expect(older.mergeWith(newer).colorHex, '#NEW');
    });
  });
}
