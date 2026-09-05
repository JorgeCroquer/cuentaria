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
    'recording BCV and parallel rates from the Patrimonio header appends '
    'both observations',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PatrimonioScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recordRatesAction')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('bcvRateField')), '37.5');
      await tester.enterText(find.byKey(const Key('paraleloRateField')), '90');
      await tester.tap(find.byKey(const Key('saveRatesButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bcvRateField')), findsNothing);

      final series = await container.read(rateSeriesProvider.future);
      final latest = await series.latestFor(CurrencyCode('VES'));
      expect(latest, isNotNull);
      expect(latest!.source, 'manual:paralelo');
      expect(latest.nativePerUsd, Decimal.parse('90'));
    },
  );

  testWidgets("recording rates through the dialog immediately refreshes a "
      "foreign-currency account's today's value and clears the missing-rate "
      'flag (#84)', (tester) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);

    final catalog = await container.read(catalogRepositoryProvider.future);
    final projections = container.read(ledgerProjectionsProvider);
    final deviceId = await container.read(deviceIdProvider.future);

    final vesAccountId = AccountId('ves-1');
    await catalog.saveAccount(
      Account(
        id: vesAccountId,
        name: 'Cuenta Bs',
        nativeCurrency: CurrencyCode('VES'),
        isArchived: false,
        updatedAt: DateTime.now(),
      ),
    );

    // $100 cost basis, native balance 7500 Bs (750000 in minor units).
    final stageEnvelope = catalog.getSystemEnvelope(EnvelopeRole.stage);
    projections.apply(
      Transaction.create(
        postings: [
          Posting(
            target: AccountTarget(vesAccountId),
            amountNative: Money(
              amount: BigInt.from(750000),
              currency: CurrencyCode('VES'),
            ),
            currency: CurrencyCode('VES'),
            amountUsd: 10000,
          ),
          Posting(
            target: EnvelopeTarget(stageEnvelope),
            amountNative: Money(
              amount: BigInt.from(750000),
              currency: CurrencyCode('VES'),
            ),
            currency: CurrencyCode('VES'),
            amountUsd: 10000,
          ),
        ],
        metadata: TransactionMetadata(
          eventId: EventId('evt-ves-dialog'),
          type: 'Adjustment',
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
          recordedAt: DomainTimestamp(DateTime.now().toUtc()),
          deviceId: deviceId,
          schemaVersion: 1,
        ),
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PatrimonioScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('missingRateFlag')), findsOneWidget);
    expect(find.textContaining('(sin tasa)'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('todayValueAmount'))).data,
      '\$100.00',
    );

    await tester.tap(find.byKey(const Key('recordRatesAction')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('bcvRateField')), '50');
    await tester.enterText(find.byKey(const Key('paraleloRateField')), '100');
    await tester.tap(find.byKey(const Key('saveRatesButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('missingRateFlag')), findsNothing);
    expect(find.textContaining('(sin tasa)'), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('todayValueAmount'))).data,
      '\$75.00',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('bcvReferenceAmount'))).data,
      'Referencia BCV: \$150.00',
    );
  });

  testWidgets(
    'the rates form pre-fills both fields from the Chain, and typing only '
    'the parallel rate appends just manual:paralelo, leaving the BCV '
    'reference resolving from dolarapi:oficial (#175)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final currency = CurrencyCode('VES');
      final series = await container.read(rateSeriesProvider.future);
      await series.append(
        RateObservation(
          currency: currency,
          nativePerUsd: Decimal.parse('755.90'),
          observedAt: DateTime.now().toUtc(),
          source: 'dolarapi:oficial',
        ),
      );
      await series.append(
        RateObservation(
          currency: currency,
          nativePerUsd: Decimal.parse('846.50'),
          observedAt: DateTime.now().toUtc(),
          source: 'binancep2p:ask',
        ),
      );

      final catalog = await container.read(catalogRepositoryProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
      final deviceId = await container.read(deviceIdProvider.future);

      final vesAccountId = AccountId('ves-1');
      await catalog.saveAccount(
        Account(
          id: vesAccountId,
          name: 'Cuenta Bs',
          nativeCurrency: currency,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      final stageEnvelope = catalog.getSystemEnvelope(EnvelopeRole.stage);
      projections.apply(
        Transaction.create(
          postings: [
            Posting(
              target: AccountTarget(vesAccountId),
              amountNative: Money(
                amount: BigInt.from(800000),
                currency: currency,
              ),
              currency: currency,
              amountUsd: 0,
            ),
            Posting(
              target: EnvelopeTarget(stageEnvelope),
              amountNative: Money(
                amount: BigInt.from(800000),
                currency: currency,
              ),
              currency: currency,
              amountUsd: 0,
            ),
          ],
          metadata: TransactionMetadata(
            eventId: EventId('evt-ves-175'),
            type: 'Adjustment',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: deviceId,
            schemaVersion: 1,
          ),
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PatrimonioScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recordRatesAction')));
      await tester.pumpAndSettle();

      final bcvField = tester.widget<TextField>(
        find.byKey(const Key('bcvRateField')),
      );
      expect(bcvField.controller!.text, '755.9');
      final paraleloField = tester.widget<TextField>(
        find.byKey(const Key('paraleloRateField')),
      );
      expect(paraleloField.controller!.text, '846.5');

      await tester.enterText(find.byKey(const Key('paraleloRateField')), '900');
      await tester.tap(find.byKey(const Key('saveRatesButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bcvRateField')), findsNothing);

      final bcvObservation = await series.latestFor(
        currency,
        source: 'manual:bcv',
      );
      expect(bcvObservation, isNull);
      final paraleloObservation = await series.latestFor(
        currency,
        source: 'manual:paralelo',
      );
      expect(paraleloObservation, isNotNull);
      expect(paraleloObservation!.nativePerUsd, Decimal.parse('900'));

      expect(
        tester.widget<Text>(find.byKey(const Key('todayValueAmount'))).data,
        '\$8.89',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('bcvReferenceAmount'))).data,
        'Referencia BCV: \$10.58',
      );
    },
  );
}
