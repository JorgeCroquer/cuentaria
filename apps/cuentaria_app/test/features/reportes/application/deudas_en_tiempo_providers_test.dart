import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:cuentaria_app/features/reportes/application/deudas_en_tiempo_providers.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/providers/ledger_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes/reportes.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('debtsEnTiempoPointsProvider', () {
    test('computes 12 points ending at the current month', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final points = await container.read(debtsEnTiempoPointsProvider.future);

      expect(points, hasLength(12));
      final now = DateTime.now();
      final currentMonth = MonthCalendar.getReportMonth(
        now.toUtc(),
        now.timeZoneOffset,
      );
      expect(points.last.month, currentMonth);
    });

    test('invalidates itself when a transaction is recorded', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final initial = await container.read(debtsEnTiempoPointsProvider.future);
      expect(initial.last.personas, isEmpty);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final deviceId = await container.read(deviceIdProvider.future);
      final recordIncome = await container.read(recordIncomeProvider.future);
      final accountId = AccountId('debt-pedro');
      await catalog.saveAccount(
        Account(
          id: accountId,
          name: 'Pedro',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
          meta: const {'counterpartyName': 'Pedro'},
        ),
      );
      await recordIncome(
        eventId: EventId('evt-1'),
        deviceId: deviceId,
        accountId: accountId,
        amount: Money(amount: BigInt.from(1500), currency: CurrencyCode('USD')),
        source: 'Manual entry',
      );

      final updated = await container.read(debtsEnTiempoPointsProvider.future);
      expect(updated.last.personas.single.personName, 'Pedro');
      expect(updated.last.personas.single.netoUsdCents, 1500);
    });
  });
}
