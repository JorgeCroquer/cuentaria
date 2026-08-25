import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:cuentaria_app/features/patrimonio/ui/screens/patrimonio_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/providers/tasas_providers.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';

void main() {
  testWidgets(
    'shows a single "Deudas" line with the net USD; Pedro and Ana never '
    'appear as their own currency group (#207)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final deviceId = await container.read(deviceIdProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
      final stageEnvelope = catalog.getSystemEnvelope(EnvelopeRole.stage);

      final efectivoId = AccountId('efectivo');
      await catalog.saveAccount(
        Account(
          id: efectivoId,
          name: 'Efectivo',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      projections.apply(
        Transaction.create(
          postings: [
            Posting(
              target: AccountTarget(efectivoId),
              amountNative: Money(
                amount: BigInt.from(50000),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 50000,
            ),
            Posting(
              target: EnvelopeTarget(stageEnvelope),
              amountNative: Money(
                amount: BigInt.from(50000),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 50000,
            ),
          ],
          metadata: TransactionMetadata(
            eventId: EventId('evt-efectivo'),
            type: 'Adjustment',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: deviceId,
            schemaVersion: 1,
          ),
        ),
      );

      final pedroId = AccountId('pedro');
      await catalog.saveAccount(
        Account(
          id: pedroId,
          name: 'Pedro',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
          meta: {'counterpartyName': 'Pedro'},
        ),
      );
      projections.apply(
        Transaction.create(
          postings: [
            Posting(
              target: AccountTarget(pedroId),
              amountNative: Money(
                amount: BigInt.from(20000),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 20000,
            ),
            Posting(
              target: EnvelopeTarget(stageEnvelope),
              amountNative: Money(
                amount: BigInt.from(20000),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 20000,
            ),
          ],
          metadata: TransactionMetadata(
            eventId: EventId('evt-pedro'),
            type: 'Adjustment',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: deviceId,
            schemaVersion: 1,
          ),
        ),
      );

      final anaId = AccountId('ana');
      await catalog.saveAccount(
        Account(
          id: anaId,
          name: 'Ana',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
          meta: {'counterpartyName': 'Ana'},
        ),
      );
      projections.apply(
        Transaction.create(
          postings: [
            Posting(
              target: AccountTarget(anaId),
              amountNative: Money(
                amount: BigInt.from(400000),
                currency: CurrencyCode('VES'),
              ),
              currency: CurrencyCode('VES'),
              amountUsd: 10000,
            ),
            Posting(
              target: EnvelopeTarget(stageEnvelope),
              amountNative: Money(
                amount: BigInt.from(400000),
                currency: CurrencyCode('VES'),
              ),
              currency: CurrencyCode('VES'),
              amountUsd: 10000,
            ),
          ],
          metadata: TransactionMetadata(
            eventId: EventId('evt-ana'),
            type: 'Adjustment',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: deviceId,
            schemaVersion: 1,
          ),
        ),
      );

      final rateSeries = await container.read(rateSeriesProvider.future);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('50'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:paralelo',
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PatrimonioScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('debtsLine')), findsOneWidget);
      expect(find.text('Deudas · \$280.00'), findsOneWidget);
      expect(find.byKey(const Key('accountGroup_VES')), findsNothing);
      expect(find.text('Pedro'), findsNothing);
      expect(find.text('Ana'), findsNothing);
    },
  );
}
