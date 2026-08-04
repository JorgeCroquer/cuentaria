import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/ledger/factories/record_acquisition_conversion.dart';
import 'package:contabilidad/application/ledger/factories/record_realization.dart';
import 'package:contabilidad/application/ledger/factories/record_transfer.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:cuentaria_app/features/capture/application/quick_add_mover_use_case.dart';

void main() {
  group('QuickAddMoverUseCase', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late InMemoryCatalogRepository catalog;
    late QuickAddMoverUseCase useCase;

    AccountId usdAccountId(String id) => AccountId(id);

    void addAccount(String id, String currency) {
      catalog.saveAccount(
        Account(
          id: AccountId(id),
          name: id,
          nativeCurrency: CurrencyCode(currency),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
    }

    setUp(() {
      store = InMemoryEventStore();
      projections = InMemoryLedgerProjections();
      catalog = InMemoryCatalogRepository();
      final eventBus = SyncEventBus();
      final validator = ReferentialIntegrityValidator(catalog);
      final record = RecordTransaction(
        store: store,
        projections: projections,
        eventBus: eventBus,
        validator: validator,
      );

      useCase = QuickAddMoverUseCase(
        recordTransfer: RecordTransfer(record: record, catalog: catalog),
        recordAcquisitionConversion: RecordAcquisitionConversion(
          record: record,
          catalog: catalog,
        ),
        recordRealization: RecordRealization(
          record: record,
          catalog: catalog,
          projections: projections,
        ),
        catalog: catalog,
      );
    });

    test('same currency dispatches a Transfer', () async {
      addAccount('facebank', 'USD');
      addAccount('zinli', 'USD');

      await useCase(
        eventId: EventId('evt-1'),
        deviceId: 'dev-1',
        sourceAccountId: usdAccountId('facebank'),
        destinationAccountId: usdAccountId('zinli'),
        givenAmount: Money(
          amount: BigInt.from(5000),
          currency: CurrencyCode('USD'),
        ),
      );

      final log = await store.queryLog();
      expect(log.single.metadata.type, 'Transfer');
      expect(projections.accountBalance(AccountId('facebank')).usd, -5000);
      expect(projections.accountBalance(AccountId('zinli')).usd, 5000);
    });

    test(
      'different currency with an explicit received amount dispatches an '
      'AcquisitionConversion carrying a rateRef, not a stored rate field',
      () async {
        addAccount('binance', 'USD');
        addAccount('bdv', 'VES');

        await useCase(
          eventId: EventId('evt-2'),
          deviceId: 'dev-1',
          sourceAccountId: usdAccountId('binance'),
          destinationAccountId: usdAccountId('bdv'),
          givenAmount: Money(
            amount: BigInt.from(10000),
            currency: CurrencyCode('USD'),
          ), // $100.00
          receivedAmount: Money(
            amount: BigInt.from(400000),
            currency: CurrencyCode('VES'),
          ), // 4000.00 Bs
        );

        final log = await store.queryLog();
        final tx = log.single;
        expect(tx.metadata.type, 'AcquisitionConversion');
        expect(tx.postings.length, 2);
        final bsPosting = tx.postings.last;
        expect(bsPosting.amountUsd, 10000);
        expect(bsPosting.rateRef, '40.00 VES/USD');
        expect(
          projections.accountBalance(AccountId('bdv')).native.amount,
          BigInt.from(400000),
        );
      },
    );

    test('different currency with only a rate derives the received amount '
        '(single rounding, native-per-USD)', () async {
      addAccount('binance', 'USD');
      addAccount('bdv', 'VES');

      await useCase(
        eventId: EventId('evt-3'),
        deviceId: 'dev-1',
        sourceAccountId: usdAccountId('binance'),
        destinationAccountId: usdAccountId('bdv'),
        givenAmount: Money(
          amount: BigInt.from(250),
          currency: CurrencyCode('USD'),
        ), // $2.50
        rate: Decimal.parse('20'),
      );

      final log = await store.queryLog();
      final tx = log.single;
      expect(tx.metadata.type, 'AcquisitionConversion');
      expect(
        projections.accountBalance(AccountId('bdv')).native.amount,
        BigInt.from(5000), // 50.00 Bs
      );
    });

    test(
      'different currency without a received amount or rate throws',
      () async {
        addAccount('binance', 'USD');
        addAccount('bdv', 'VES');

        await expectLater(
          () => useCase(
            eventId: EventId('evt-4'),
            deviceId: 'dev-1',
            sourceAccountId: usdAccountId('binance'),
            destinationAccountId: usdAccountId('bdv'),
            givenAmount: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('USD'),
            ),
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'reuses RecordAcquisitionConversion validation for a non-USD source',
      () async {
        addAccount('binance-eur', 'EUR');
        addAccount('bdv', 'VES');

        await expectLater(
          () => useCase(
            eventId: EventId('evt-5'),
            deviceId: 'dev-1',
            sourceAccountId: usdAccountId('binance-eur'),
            destinationAccountId: usdAccountId('bdv'),
            givenAmount: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('EUR'),
            ),
            rate: Decimal.parse('40'),
          ),
          throwsA(isA<UsdOnlyOperation>()),
        );
      },
    );

    group('the five rows of the Mover matrix (#116, ADR-0018)', () {
      setUp(() {
        addAccount('facebank', 'USD');
        addAccount('zinli', 'USD');
        addAccount('binance', 'USD');
        addAccount('bdv', 'VES');
        addAccount('binance-eur', 'EUR');
      });

      test('row 1: USD -> USD (Facebank -> Zinli) posts a Transfer', () async {
        await useCase(
          eventId: EventId('evt-usd-usd'),
          deviceId: 'dev-1',
          sourceAccountId: usdAccountId('facebank'),
          destinationAccountId: usdAccountId('zinli'),
          givenAmount: Money(
            amount: BigInt.from(10000),
            currency: CurrencyCode('USD'),
          ),
        );

        final log = await store.queryLog();
        expect(log.single.metadata.type, 'Transfer');
        expect(projections.accountBalance(AccountId('facebank')).usd, -10000);
        expect(projections.accountBalance(AccountId('zinli')).usd, 10000);
      });

      test('row 2: USD -> non-USD (Binance -> BdV) posts an '
          'AcquisitionConversion, rateRef labeled VES/USD', () async {
        await useCase(
          eventId: EventId('evt-usd-ves'),
          deviceId: 'dev-1',
          sourceAccountId: usdAccountId('binance'),
          destinationAccountId: usdAccountId('bdv'),
          givenAmount: Money(
            amount: BigInt.from(10000),
            currency: CurrencyCode('USD'),
          ),
          rate: Decimal.parse('40'),
        );

        final log = await store.queryLog();
        final tx = log.single;
        expect(tx.metadata.type, 'AcquisitionConversion');
        expect(tx.postings.last.rateRef, '40.00 VES/USD');
        expect(projections.accountBalance(AccountId('binance')).usd, -10000);
        expect(
          projections.accountBalance(AccountId('bdv')).native.amount,
          BigInt.from(400000),
        );
      });

      test('row 3: non-USD -> USD (BdV -> Binance) with an explicit received '
          'USD amount posts a DisposalConversion, rateRef labeled VES/USD, '
          'not USD/USD', () async {
        await useCase(
          eventId: EventId('evt-ves-usd-received'),
          deviceId: 'dev-1',
          sourceAccountId: usdAccountId('bdv'),
          destinationAccountId: usdAccountId('binance'),
          givenAmount: Money(
            amount: BigInt.from(400000), // 4000.00 Bs given
            currency: CurrencyCode('VES'),
          ),
          receivedAmount: Money(
            amount: BigInt.from(10000), // $100.00 received
            currency: CurrencyCode('USD'),
          ),
        );

        final log = await store.queryLog();
        final tx = log.single;
        expect(tx.metadata.type, 'DisposalConversion');
        final destinationPosting = tx.postings.firstWhere(
          (p) => p.target == AccountTarget(AccountId('binance')),
        );
        expect(destinationPosting.amountUsd, 10000);
        expect(destinationPosting.rateRef, '40.00 VES/USD');
        expect(projections.accountBalance(AccountId('binance')).usd, 10000);
      });

      test(
        'row 3: non-USD -> USD (BdV -> Binance) with only an applied rate '
        'derives the received USD via deriveUsdCents, not deriveNativeCents',
        () async {
          await useCase(
            eventId: EventId('evt-ves-usd-rate'),
            deviceId: 'dev-1',
            sourceAccountId: usdAccountId('bdv'),
            destinationAccountId: usdAccountId('binance'),
            givenAmount: Money(
              amount: BigInt.from(400000), // 4000.00 Bs given
              currency: CurrencyCode('VES'),
            ),
            rate: Decimal.parse('40'),
          );

          final log = await store.queryLog();
          final tx = log.single;
          expect(tx.metadata.type, 'DisposalConversion');
          // 4000.00 Bs / 40 VES per USD = $100.00
          expect(projections.accountBalance(AccountId('binance')).usd, 10000);
        },
      );

      test(
        'row 4: non-USD -> different non-USD (BdV -> Binance EUR) is not '
        'modeled by any factory (ADR-0018 §5) — throws UsdOnlyOperation, '
        'posts nothing; the UI chips prevent this pair from being reachable',
        () async {
          await expectLater(
            () => useCase(
              eventId: EventId('evt-ves-eur'),
              deviceId: 'dev-1',
              sourceAccountId: usdAccountId('bdv'),
              destinationAccountId: usdAccountId('binance-eur'),
              givenAmount: Money(
                amount: BigInt.from(400000),
                currency: CurrencyCode('VES'),
              ),
              rate: Decimal.parse('40'),
            ),
            throwsA(isA<UsdOnlyOperation>()),
          );

          expect(await store.queryLog(), isEmpty);
        },
      );

      test('every account pair reachable from the UI selectors either posts '
          'or throws a typed exception the capture sheet already catches and '
          'displays — never an unhandled crash', () async {
        final accountIds = [
          'facebank',
          'zinli',
          'binance',
          'bdv',
          'binance-eur',
        ];

        for (final sourceId in accountIds) {
          for (final destinationId in accountIds) {
            if (sourceId == destinationId) continue;

            final source = catalog.getAccount(AccountId(sourceId))!;

            try {
              await useCase(
                eventId: EventId('evt-$sourceId-$destinationId'),
                deviceId: 'dev-1',
                sourceAccountId: usdAccountId(sourceId),
                destinationAccountId: usdAccountId(destinationId),
                givenAmount: Money(
                  amount: BigInt.from(100),
                  currency: source.nativeCurrency,
                ),
                rate: Decimal.parse('40'),
              );
            } catch (e) {
              expect(
                e,
                isA<UsdOnlyOperation>(),
                reason:
                    '$sourceId -> $destinationId threw an unexpected, '
                    'unexplained exception: $e',
              );
            }
          }
        }
      });
    });

    group('P2P weekly real: BdV (Bs) -> Binance (USD), differential vs. '
        'frozen cost (re-drain criterion 11)', () {
      setUp(() {
        addAccount('bdv', 'VES');
        addAccount('binance', 'USD');
      });

      Future<void> fundBdvViaIncome({
        required BigInt nativeAmount,
        required int usdAmount,
      }) async {
        final differentialId = catalog.getSystemEnvelope(
          EnvelopeRole.differential,
        );
        await store.append(
          Transaction.create(
            metadata: TransactionMetadata(
              eventId: EventId('evt-fund'),
              type: 'Opening',
              occurredAt: DomainTimestamp(DateTime.now().toUtc()),
              recordedAt: DomainTimestamp(DateTime.now().toUtc()),
              deviceId: 'dev-1',
              schemaVersion: 1,
            ),
            postings: [
              Posting(
                target: AccountTarget(AccountId('bdv')),
                amountNative: Money(
                  amount: nativeAmount,
                  currency: CurrencyCode('VES'),
                ),
                currency: CurrencyCode('VES'),
                amountUsd: usdAmount,
              ),
              Posting(
                target: EnvelopeTarget(differentialId),
                amountNative: Money(
                  amount: BigInt.from(usdAmount),
                  currency: CurrencyCode('USD'),
                ),
                currency: CurrencyCode('USD'),
                amountUsd: usdAmount,
              ),
            ],
          ),
        );
        projections.apply((await store.get(EventId('evt-fund')))!);
      }

      test('a real proceeds rate different from the frozen cost basis posts a '
          'non-zero Differential, and the ledger stays balanced', () async {
        // 10,000.00 Bs funded at a frozen cost of 100 VES/USD => $100.00
        // cost basis.
        await fundBdvViaIncome(
          nativeAmount: BigInt.from(1000000),
          usdAmount: 10000,
        );

        // Sell all 10,000.00 Bs for proceeds at 150 VES/USD => $66.67
        // observed value.
        await useCase(
          eventId: EventId('evt-p2p'),
          deviceId: 'dev-1',
          sourceAccountId: usdAccountId('bdv'),
          destinationAccountId: usdAccountId('binance'),
          givenAmount: Money(
            amount: BigInt.from(1000000),
            currency: CurrencyCode('VES'),
          ),
          rate: Decimal.parse('150'),
        );

        final log = await store.queryLog();
        final tx = log.last;
        expect(tx.metadata.type, 'DisposalConversion');

        final differentialId = catalog.getSystemEnvelope(
          EnvelopeRole.differential,
        );
        final differentialPosting = tx.postings.firstWhere(
          (p) => p.target == EnvelopeTarget(differentialId),
        );
        // observed $66.67 - cost $100.00 = -$33.33 loss. Transaction.create
        // already enforces sumAccounts == sumEnvelopes (AGENTS.md
        // self-balancing rule); reaching this line without an
        // UnbalancedTransaction proves the ledger stayed balanced.
        expect(differentialPosting.amountUsd, -3333);

        expect(
          projections.accountBalance(AccountId('bdv')).native.amount,
          BigInt.zero,
        );
        expect(projections.accountBalance(AccountId('binance')).usd, 6667);
      });

      test(
        'selling more Bs than the known balance (sobregiro, ADR-0017): the '
        'covered portion keeps the frozen cost, the excess is valued at the '
        'observed rate, and only the covered portion hits Differential',
        () async {
          // 5,000.00 Bs funded at a frozen cost of 100 VES/USD => $50.00
          // cost basis.
          await fundBdvViaIncome(
            nativeAmount: BigInt.from(500000),
            usdAmount: 5000,
          );

          // Sell 9,000.00 Bs (nearly double the known balance) at 150
          // VES/USD.
          await useCase(
            eventId: EventId('evt-overdraft'),
            deviceId: 'dev-1',
            sourceAccountId: usdAccountId('bdv'),
            destinationAccountId: usdAccountId('binance'),
            givenAmount: Money(
              amount: BigInt.from(900000),
              currency: CurrencyCode('VES'),
            ),
            rate: Decimal.parse('150'),
          );

          final log = await store.queryLog();
          final tx = log.last;
          expect(tx.metadata.type, 'DisposalConversion');

          // Balance goes negative by the excess (9,000 sold - 5,000 held).
          expect(
            projections.accountBalance(AccountId('bdv')).native.amount,
            BigInt.from(-400000),
          );
          // Full observed proceeds: 9,000.00 / 150 = $60.00.
          expect(projections.accountBalance(AccountId('binance')).usd, 6000);

          final differentialId = catalog.getSystemEnvelope(
            EnvelopeRole.differential,
          );
          final differentialPosting = tx.postings.firstWhere(
            (p) => p.target == EnvelopeTarget(differentialId),
          );
          // costBasis = frozen $50.00 (covered 5,000.00 Bs) + excess cost
          // (4,000.00 Bs valued at the observed rate: 4,000/9,000 * $60.00
          // = $26.67) = $76.67. delta = observed $60.00 - $76.67 = -$16.67.
          // The excess's cost equals its own observed value by
          // construction, so only the covered portion moves Differential.
          expect(differentialPosting.amountUsd, -1667);
        },
      );
    });
  });
}
