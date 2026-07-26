import 'dart:math' as math;
import 'package:test/test.dart';
import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:event_bus/event_bus.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/application/ledger/factories/record_realization.dart';

void main() {
  group('RecordRealization', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late SyncEventBus eventBus;
    late InMemoryCatalogRepository catalog;
    late RecordTransaction record;
    late RecordRealization factory;

    setUp(() {
      store = InMemoryEventStore();
      projections = InMemoryLedgerProjections();
      eventBus = SyncEventBus();
      catalog = InMemoryCatalogRepository();

      final validator = ReferentialIntegrityValidator(catalog);
      record = RecordTransaction(
        store: store,
        projections: projections,
        eventBus: eventBus,
        validator: validator,
      );

      factory = RecordRealization(
        record: record,
        catalog: catalog,
        projections: projections,
      );
    });

    test(
      'Overdraw Rejection: throws InsufficientBalance if nativeAmount > balance.native',
      () async {
        final bsAccountId = AccountId('acc-bs');
        final destinationEnvelopeId = EnvelopeId('env-destination');

        catalog.saveAccount(
          Account(
            id: bsAccountId,
            name: 'Bs Bank',
            nativeCurrency: CurrencyCode('VES'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        catalog.saveEnvelope(
          Envelope(
            id: destinationEnvelopeId,
            name: 'Expenses',
            role: EnvelopeRole.none,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        // Add 100 VES balance via a direct event to projections
        final initialEvent = Transaction.create(
          metadata: TransactionMetadata(
            eventId: EventId('evt-init'),
            type: 'Opening',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: 'dev',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: AccountTarget(bsAccountId),
              amountNative: Money(
                amount: BigInt.from(10000),
                currency: CurrencyCode('VES'),
              ), // 100 VES
              currency: CurrencyCode('VES'),
              amountUsd: 250, // $2.50
            ),
            Posting(
              target: EnvelopeTarget(EnvelopeId('env-opening')),
              amountNative: Money(
                amount: BigInt.from(250),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 250,
            ),
          ],
        );
        projections.apply(initialEvent);

        await expectLater(
          () => factory.foreignCurrencyExpense(
            eventId: EventId('evt-expense-1'),
            deviceId: 'dev-1',
            accountId: bsAccountId,
            destinationEnvelopeId: destinationEnvelopeId,
            nativeAmount: Money(
              amount: BigInt.from(15000),
              currency: CurrencyCode('VES'),
            ), // 150 VES > 100 VES
            currentRate: Decimal.parse('40.00'), // VES/USD
          ),
          throwsA(isA<InsufficientBalance>()),
        );
      },
    );

    test(
      'IncompatibleCurrency: foreignCurrencyExpense rejects USD account',
      () async {
        final usdAccountId = AccountId('acc-usd-incompat');
        final destinationEnvelopeId = EnvelopeId('env-incompat');
        catalog.saveAccount(
          Account(
            id: usdAccountId,
            name: 'USD acc',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        catalog.saveEnvelope(
          Envelope(
            id: destinationEnvelopeId,
            name: 'Expenses',
            role: EnvelopeRole.none,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        await expectLater(
          () => factory.foreignCurrencyExpense(
            eventId: EventId('evt-incompat-1'),
            deviceId: 'dev',
            accountId: usdAccountId,
            destinationEnvelopeId: destinationEnvelopeId,
            nativeAmount: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('USD'),
            ),
            currentRate: Decimal.parse('1.00'),
          ),
          throwsA(isA<IncompatibleCurrency>()),
        );
      },
    );

    test(
      'IncompatibleCurrency: disposalConversion rejects USD source account',
      () async {
        final usdAccountId = AccountId('acc-usd-origin');
        final destinationAccountId = AccountId('acc-usd-dest');
        catalog.saveAccount(
          Account(
            id: usdAccountId,
            name: 'USD origin',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        catalog.saveAccount(
          Account(
            id: destinationAccountId,
            name: 'USD dest',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        await expectLater(
          () => factory.disposalConversion(
            eventId: EventId('evt-incompat-2'),
            deviceId: 'dev',
            sourceForeignAccountId: usdAccountId,
            destinationUsdAccountId: destinationAccountId,
            nativeAmount: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('USD'),
            ),
            usdAmountReceived: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('USD'),
            ),
            rateRef: '1.00 USD/USD',
          ),
          throwsA(isA<IncompatibleCurrency>()),
        );
      },
    );

    test('Foreign Currency Expense: generates 3 postings (Loss)', () async {
      final bsAccountId = AccountId('acc-bs-2');
      final destinationEnvelopeId = EnvelopeId('env-destination-2');

      catalog.saveAccount(
        Account(
          id: bsAccountId,
          name: 'Bs Bank 2',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      catalog.saveEnvelope(
        Envelope(
          id: destinationEnvelopeId,
          name: 'Expenses 2',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final differentialId = catalog.getSystemEnvelope(
        EnvelopeRole.differential,
      );

      // Add 100 VES balance with a base cost of $5.00 (avg 20 VES/USD)
      final initialEvent = Transaction.create(
        metadata: TransactionMetadata(
          eventId: EventId('evt-init-2'),
          type: 'Opening',
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
          recordedAt: DomainTimestamp(DateTime.now().toUtc()),
          deviceId: 'dev',
          schemaVersion: 1,
        ),
        postings: [
          Posting(
            target: AccountTarget(bsAccountId),
            amountNative: Money(
              amount: BigInt.from(10000),
              currency: CurrencyCode('VES'),
            ), // 100 VES
            currency: CurrencyCode('VES'),
            amountUsd: 500, // $5.00
          ),
          Posting(
            target: EnvelopeTarget(EnvelopeId('env-opening')),
            amountNative: Money(
              amount: BigInt.from(500),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 500,
          ),
        ],
      );
      projections.apply(initialEvent);

      // Spend 50 VES at current rate of 40 VES/USD.
      // Market value = 50 VES / 40 = $1.25 (125 cents).
      // Base cost = 50% of 500 cents = $2.50 (250 cents).
      // Differential = market_value - base_cost = 125 - 250 = -125 cents (Loss).

      await factory.foreignCurrencyExpense(
        eventId: EventId('evt-expense-2'),
        deviceId: 'dev-2',
        accountId: bsAccountId,
        destinationEnvelopeId: destinationEnvelopeId,
        nativeAmount: Money(
          amount: BigInt.from(5000),
          currency: CurrencyCode('VES'),
        ), // 50 VES
        currentRate: Decimal.parse('40.00'), // VES/USD
      );

      final events = store.events;
      final event = events.last;
      expect(event.metadata.type, 'ForeignCurrencyExpense');
      expect(event.postings.length, 3);

      final pAccount = event.postings.firstWhere(
        (p) => p.target == AccountTarget(bsAccountId),
      );
      expect(pAccount.amountNative.amount, BigInt.from(-5000));
      expect(pAccount.amountUsd, -250);

      final pDestination = event.postings.firstWhere(
        (p) => p.target == EnvelopeTarget(destinationEnvelopeId),
      );
      expect(pDestination.amountUsd, -125);
      expect(pDestination.rateRef, '40.00 VES/USD'); // rate_ref must be stored

      final pDifferential = event.postings.firstWhere(
        (p) => p.target == EnvelopeTarget(differentialId),
      );
      expect(pDifferential.amountUsd, -125);
    });

    test('Foreign Currency Expense: generates 3 postings (Gain)', () async {
      final bsAccountId = AccountId('acc-bs-3');
      final destinationEnvelopeId = EnvelopeId('env-destination-3');
      final differentialId = catalog.getSystemEnvelope(
        EnvelopeRole.differential,
      );

      catalog.saveAccount(
        Account(
          id: bsAccountId,
          name: 'Bs 3',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      catalog.saveEnvelope(
        Envelope(
          id: destinationEnvelopeId,
          name: 'Expenses 3',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final initialEvent = Transaction.create(
        metadata: TransactionMetadata(
          eventId: EventId('evt-init-3'),
          type: 'Opening',
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
          recordedAt: DomainTimestamp(DateTime.now().toUtc()),
          deviceId: 'dev',
          schemaVersion: 1,
        ),
        postings: [
          Posting(
            target: AccountTarget(bsAccountId),
            amountNative: Money(
              amount: BigInt.from(10000),
              currency: CurrencyCode('VES'),
            ),
            currency: CurrencyCode('VES'),
            amountUsd: 200,
          ), // Base cost $2.00
          Posting(
            target: EnvelopeTarget(EnvelopeId('env-opening')),
            amountNative: Money(
              amount: BigInt.from(200),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 200,
          ),
        ],
      );
      projections.apply(initialEvent);

      // Spend 50 VES at current rate of 25 VES/USD.
      // Market value = 50 / 25 = $2.00 (200 cents).
      // Base cost = 50% of 200 cents = $1.00 (100 cents).
      // Differential = 200 - 100 = +100 cents (Gain).

      await factory.foreignCurrencyExpense(
        eventId: EventId('evt-expense-3'),
        deviceId: 'dev-3',
        accountId: bsAccountId,
        destinationEnvelopeId: destinationEnvelopeId,
        nativeAmount: Money(
          amount: BigInt.from(5000),
          currency: CurrencyCode('VES'),
        ), // 50 VES
        currentRate: Decimal.parse('25.00'), // VES/USD
      );

      final event = store.events.last;

      final pAccount = event.postings.firstWhere(
        (p) => p.target == AccountTarget(bsAccountId),
      );
      expect(pAccount.amountUsd, -100);

      final pDestination = event.postings.firstWhere(
        (p) => p.target == EnvelopeTarget(destinationEnvelopeId),
      );
      expect(pDestination.amountUsd, -200);

      final pDifferential = event.postings.firstWhere(
        (p) => p.target == EnvelopeTarget(differentialId),
      );
      expect(pDifferential.amountUsd, 100);
    });

    test('Disposal Conversion: uses observed usdAmountReceived', () async {
      final bsAccountId = AccountId('acc-bs-4');
      final usdAccountId = AccountId('acc-usd-4');
      final differentialId = catalog.getSystemEnvelope(
        EnvelopeRole.differential,
      );

      catalog.saveAccount(
        Account(
          id: bsAccountId,
          name: 'Bs 4',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      catalog.saveAccount(
        Account(
          id: usdAccountId,
          name: 'USD 4',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final initialEvent = Transaction.create(
        metadata: TransactionMetadata(
          eventId: EventId('evt-init-4'),
          type: 'Opening',
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
          recordedAt: DomainTimestamp(DateTime.now().toUtc()),
          deviceId: 'dev',
          schemaVersion: 1,
        ),
        postings: [
          Posting(
            target: AccountTarget(bsAccountId),
            amountNative: Money(
              amount: BigInt.from(10000),
              currency: CurrencyCode('VES'),
            ),
            currency: CurrencyCode('VES'),
            amountUsd: 500,
          ),
          Posting(
            target: EnvelopeTarget(EnvelopeId('env-opening')),
            amountNative: Money(
              amount: BigInt.from(500),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 500,
          ),
        ],
      );
      projections.apply(initialEvent);

      await factory.disposalConversion(
        eventId: EventId('evt-conv-1'),
        deviceId: 'dev-4',
        sourceForeignAccountId: bsAccountId,
        destinationUsdAccountId: usdAccountId,
        nativeAmount: Money(
          amount: BigInt.from(5000),
          currency: CurrencyCode('VES'),
        ), // 50 VES
        usdAmountReceived: Money(
          amount: BigInt.from(300),
          currency: CurrencyCode('USD'),
        ), // $3.00
        rateRef: '16.66 VES/USD',
      );

      final event = store.events.last;
      expect(event.metadata.type, 'DisposalConversion');
      expect(event.postings.length, 3);

      final pForeignAccount = event.postings.firstWhere(
        (p) => p.target == AccountTarget(bsAccountId),
      );
      expect(pForeignAccount.amountUsd, -250); // 50% of 500 = 250

      final pUsdAccount = event.postings.firstWhere(
        (p) => p.target == AccountTarget(usdAccountId),
      );
      expect(pUsdAccount.amountUsd, 300);
      expect(pUsdAccount.rateRef, '16.66 VES/USD');

      final pDifferential = event.postings.firstWhere(
        (p) => p.target == EnvelopeTarget(differentialId),
      );
      expect(pDifferential.amountUsd, 50); // 300 - 250 = 50
    });

    test(
      'Zero-Native: Emptying account sweeps all remaining USD cost',
      () async {
        final bsAccountId = AccountId('acc-bs-zero');
        final destinationEnvelopeId = EnvelopeId('env-destination-zero');

        catalog.saveAccount(
          Account(
            id: bsAccountId,
            name: 'Bs Zero',
            nativeCurrency: CurrencyCode('VES'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        catalog.saveEnvelope(
          Envelope(
            id: destinationEnvelopeId,
            name: 'Destination Zero',
            role: EnvelopeRole.none,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        // Initial: 30 VES with 101 cents base cost ($1.01)
        final initialEvent = Transaction.create(
          metadata: TransactionMetadata(
            eventId: EventId('evt-z-init'),
            type: 'Opening',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: 'dev',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: AccountTarget(bsAccountId),
              amountNative: Money(
                amount: BigInt.from(3000),
                currency: CurrencyCode('VES'),
              ),
              currency: CurrencyCode('VES'),
              amountUsd: 101,
            ),
            Posting(
              target: EnvelopeTarget(EnvelopeId('env-opening')),
              amountNative: Money(
                amount: BigInt.from(101),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 101,
            ),
          ],
        );
        projections.apply(initialEvent);

        // Spend 20 VES.
        // base_cost = (2000 * 101) ~/ 3000 = 67
        await factory.foreignCurrencyExpense(
          eventId: EventId('evt-z-1'),
          deviceId: 'dev-z',
          accountId: bsAccountId,
          destinationEnvelopeId: destinationEnvelopeId,
          nativeAmount: Money(
            amount: BigInt.from(2000),
            currency: CurrencyCode('VES'),
          ),
          currentRate: Decimal.parse('40.00'),
        );

        final event1 = store.events.last;

        final pAccount1 = event1.postings.firstWhere(
          (p) => p.target == AccountTarget(bsAccountId),
        );
        expect(pAccount1.amountUsd, -67);

        // Spend remaining 10 VES.
        // Proportional = (1000 * 101) ~/ 3000 = 33
        // But remaining cost is 101 - 67 = 34.
        await factory.foreignCurrencyExpense(
          eventId: EventId('evt-z-2'),
          deviceId: 'dev-z',
          accountId: bsAccountId,
          destinationEnvelopeId: destinationEnvelopeId,
          nativeAmount: Money(
            amount: BigInt.from(1000),
            currency: CurrencyCode('VES'),
          ),
          currentRate: Decimal.parse('40.00'),
        );

        final event2 = store.events.last;
        final pAccount2 = event2.postings.firstWhere(
          (p) => p.target == AccountTarget(bsAccountId),
        );
        expect(pAccount2.amountUsd, -34); // Sweeps exactly 34

        final finalBalance = projections.accountBalance(bsAccountId);
        expect(finalBalance.native.amount, BigInt.zero);
        expect(finalBalance.usd, 0);
      },
    );

    test('Zero-Native: Property test with random operations', () async {
      final bsAccountId = AccountId('acc-bs-prop');
      final destinationEnvelopeId = EnvelopeId('env-destination-prop');

      catalog.saveAccount(
        Account(
          id: bsAccountId,
          name: 'Bs Prop',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      catalog.saveEnvelope(
        Envelope(
          id: destinationEnvelopeId,
          name: 'Destination Prop',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      // Initial: 10,000 VES with 33,333 cents base cost ($333.33)
      final initialNative = BigInt.from(10000);
      final initialUsd = 33333;

      final initialEvent = Transaction.create(
        metadata: TransactionMetadata(
          eventId: EventId('evt-p-init'),
          type: 'Opening',
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
          recordedAt: DomainTimestamp(DateTime.now().toUtc()),
          deviceId: 'dev',
          schemaVersion: 1,
        ),
        postings: [
          Posting(
            target: AccountTarget(bsAccountId),
            amountNative: Money(
              amount: initialNative,
              currency: CurrencyCode('VES'),
            ),
            currency: CurrencyCode('VES'),
            amountUsd: initialUsd,
          ),
          Posting(
            target: EnvelopeTarget(EnvelopeId('env-opening')),
            amountNative: Money(
              amount: BigInt.from(initialUsd),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: initialUsd,
          ),
        ],
      );
      projections.apply(initialEvent);

      BigInt remainingNative = initialNative;
      int totalUsdWithdrawn = 0;
      final random = math.Random(42);

      int op = 0;
      while (remainingNative > BigInt.zero) {
        op++;
        BigInt spend = BigInt.from(random.nextInt(remainingNative.toInt()) + 1);
        if (spend > remainingNative) spend = remainingNative;

        await factory.foreignCurrencyExpense(
          eventId: EventId('evt-p-$op'),
          deviceId: 'dev-p',
          accountId: bsAccountId,
          destinationEnvelopeId: destinationEnvelopeId,
          nativeAmount: Money(amount: spend, currency: CurrencyCode('VES')),
          currentRate: Decimal.parse('40.00'),
        );

        final event = store.events.last;
        final pAccount = event.postings.firstWhere(
          (p) => p.target == AccountTarget(bsAccountId),
        );
        totalUsdWithdrawn += pAccount.amountUsd.abs();

        remainingNative -= spend;
      }

      expect(remainingNative, BigInt.zero);
      expect(totalUsdWithdrawn, initialUsd);

      final finalBalance = projections.accountBalance(bsAccountId);
      expect(finalBalance.native.amount, BigInt.zero);
      expect(finalBalance.usd, 0);
    });

    // --- cryptoSale ---

    test(
      'Crypto Sale: generates 3 postings (Loss — BTC price dropped)',
      () async {
        // BTC account: 1 BTC acquired at $50,000 (5_000_000 cents)
        // Current price: $40,000 → realizes loss of $10,000
        final btcAccountId = AccountId('acc-btc-1');
        final usdDestAccountId = AccountId('acc-usd-btc-1');
        final differentialId = catalog.getSystemEnvelope(
          EnvelopeRole.differential,
        );

        catalog.saveAccount(
          Account(
            id: btcAccountId,
            name: 'BTC',
            nativeCurrency: CurrencyCode('BTC'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        catalog.saveAccount(
          Account(
            id: usdDestAccountId,
            name: 'USD dest',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        // 1 BTC = 100_000_000 satoshis, base_cost = $50,000 (5_000_000 cents)
        final initialEvent = Transaction.create(
          metadata: TransactionMetadata(
            eventId: EventId('evt-btc-init'),
            type: 'Opening',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: 'dev',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: AccountTarget(btcAccountId),
              amountNative: Money(
                amount: BigInt.from(100000000),
                currency: CurrencyCode('BTC'),
              ),
              currency: CurrencyCode('BTC'),
              amountUsd: 5000000,
            ),
            Posting(
              target: EnvelopeTarget(EnvelopeId('env-opening')),
              amountNative: Money(
                amount: BigInt.from(5000000),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 5000000,
            ),
          ],
        );
        projections.apply(initialEvent);

        // Sell all 1 BTC at current price $40,000 (4_000_000 cents)
        // base_cost = 5_000_000 cents
        // usd_amount_received = 4_000_000 cents
        // delta = 4_000_000 - 5_000_000 = -1_000_000 (Loss)
        await factory.cryptoSale(
          eventId: EventId('evt-btc-sale-1'),
          deviceId: 'dev-btc',
          cryptoAccountId: btcAccountId,
          destinationUsdAccountId: usdDestAccountId,
          quantity: Money(
            amount: BigInt.from(100000000),
            currency: CurrencyCode('BTC'),
          ),
          usdAmountReceived: Money(
            amount: BigInt.from(4000000),
            currency: CurrencyCode('USD'),
          ),
          rateRef: '40000.00 USD/BTC',
        );

        final event = store.events.last;
        expect(event.metadata.type, 'CryptoSale');
        expect(event.postings.length, 3);

        final pBtc = event.postings.firstWhere(
          (p) => p.target == AccountTarget(btcAccountId),
        );
        expect(pBtc.amountUsd, -5000000); // base_cost
        expect(pBtc.amountNative.amount, BigInt.from(-100000000));

        final pUsd = event.postings.firstWhere(
          (p) => p.target == AccountTarget(usdDestAccountId),
        );
        expect(pUsd.amountUsd, 4000000); // USD received
        expect(pUsd.rateRef, '40000.00 USD/BTC');

        final pDifferential = event.postings.firstWhere(
          (p) => p.target == EnvelopeTarget(differentialId),
        );
        expect(pDifferential.amountUsd, -1000000); // 4M - 5M = -1M (loss)
      },
    );

    test('Crypto Sale: generates 3 postings (Gain — BTC price rose)', () async {
      // BTC account: 1 BTC acquired at $30,000 (3_000_000 cents)
      // Current price: $45,000 → realizes gain of $15,000
      final btcAccountId = AccountId('acc-btc-2');
      final usdDestAccountId = AccountId('acc-usd-btc-2');
      final differentialId = catalog.getSystemEnvelope(
        EnvelopeRole.differential,
      );

      catalog.saveAccount(
        Account(
          id: btcAccountId,
          name: 'BTC 2',
          nativeCurrency: CurrencyCode('BTC'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      catalog.saveAccount(
        Account(
          id: usdDestAccountId,
          name: 'USD dest 2',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final initialEvent = Transaction.create(
        metadata: TransactionMetadata(
          eventId: EventId('evt-btc2-init'),
          type: 'Opening',
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
          recordedAt: DomainTimestamp(DateTime.now().toUtc()),
          deviceId: 'dev',
          schemaVersion: 1,
        ),
        postings: [
          Posting(
            target: AccountTarget(btcAccountId),
            amountNative: Money(
              amount: BigInt.from(100000000),
              currency: CurrencyCode('BTC'),
            ),
            currency: CurrencyCode('BTC'),
            amountUsd: 3000000,
          ),
          Posting(
            target: EnvelopeTarget(EnvelopeId('env-opening')),
            amountNative: Money(
              amount: BigInt.from(3000000),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 3000000,
          ),
        ],
      );
      projections.apply(initialEvent);

      // Sell all 1 BTC at $45,000 (4_500_000 cents)
      // delta = 4_500_000 - 3_000_000 = +1_500_000 (Gain)
      await factory.cryptoSale(
        eventId: EventId('evt-btc2-sale-1'),
        deviceId: 'dev-btc2',
        cryptoAccountId: btcAccountId,
        destinationUsdAccountId: usdDestAccountId,
        quantity: Money(
          amount: BigInt.from(100000000),
          currency: CurrencyCode('BTC'),
        ),
        usdAmountReceived: Money(
          amount: BigInt.from(4500000),
          currency: CurrencyCode('USD'),
        ),
        rateRef: '45000.00 USD/BTC',
      );

      final event = store.events.last;

      final pBtc = event.postings.firstWhere(
        (p) => p.target == AccountTarget(btcAccountId),
      );
      expect(pBtc.amountUsd, -3000000); // base_cost

      final pUsd = event.postings.firstWhere(
        (p) => p.target == AccountTarget(usdDestAccountId),
      );
      expect(pUsd.amountUsd, 4500000);

      final pDifferential = event.postings.firstWhere(
        (p) => p.target == EnvelopeTarget(differentialId),
      );
      expect(pDifferential.amountUsd, 1500000); // gain
    });

    test('foreignCurrencyExpense persists the memo when provided', () async {
      final bsAccountId = AccountId('acc-bs-memo');
      final destinationEnvelopeId = EnvelopeId('env-destination-memo');

      catalog.saveAccount(
        Account(
          id: bsAccountId,
          name: 'Bs Memo',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      catalog.saveEnvelope(
        Envelope(
          id: destinationEnvelopeId,
          name: 'Expenses Memo',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final initialEvent = Transaction.create(
        metadata: TransactionMetadata(
          eventId: EventId('evt-init-memo'),
          type: 'Opening',
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
          recordedAt: DomainTimestamp(DateTime.now().toUtc()),
          deviceId: 'dev',
          schemaVersion: 1,
        ),
        postings: [
          Posting(
            target: AccountTarget(bsAccountId),
            amountNative: Money(
              amount: BigInt.from(10000),
              currency: CurrencyCode('VES'),
            ),
            currency: CurrencyCode('VES'),
            amountUsd: 500,
          ),
          Posting(
            target: EnvelopeTarget(EnvelopeId('env-opening')),
            amountNative: Money(
              amount: BigInt.from(500),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 500,
          ),
        ],
      );
      projections.apply(initialEvent);

      await factory.foreignCurrencyExpense(
        eventId: EventId('evt-expense-memo'),
        deviceId: 'dev-memo',
        accountId: bsAccountId,
        destinationEnvelopeId: destinationEnvelopeId,
        nativeAmount: Money(
          amount: BigInt.from(5000),
          currency: CurrencyCode('VES'),
        ),
        currentRate: Decimal.parse('40.00'),
        memo: 'Taxi',
      );

      expect(store.events.last.metadata.memo, 'Taxi');
    });

    test('foreignCurrencyExpense does not persist an empty memo', () async {
      final bsAccountId = AccountId('acc-bs-empty-memo');
      final destinationEnvelopeId = EnvelopeId('env-destination-empty-memo');

      catalog.saveAccount(
        Account(
          id: bsAccountId,
          name: 'Bs Empty Memo',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      catalog.saveEnvelope(
        Envelope(
          id: destinationEnvelopeId,
          name: 'Expenses Empty Memo',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final initialEvent = Transaction.create(
        metadata: TransactionMetadata(
          eventId: EventId('evt-init-empty-memo'),
          type: 'Opening',
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
          recordedAt: DomainTimestamp(DateTime.now().toUtc()),
          deviceId: 'dev',
          schemaVersion: 1,
        ),
        postings: [
          Posting(
            target: AccountTarget(bsAccountId),
            amountNative: Money(
              amount: BigInt.from(10000),
              currency: CurrencyCode('VES'),
            ),
            currency: CurrencyCode('VES'),
            amountUsd: 500,
          ),
          Posting(
            target: EnvelopeTarget(EnvelopeId('env-opening')),
            amountNative: Money(
              amount: BigInt.from(500),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 500,
          ),
        ],
      );
      projections.apply(initialEvent);

      await factory.foreignCurrencyExpense(
        eventId: EventId('evt-expense-empty-memo'),
        deviceId: 'dev-memo',
        accountId: bsAccountId,
        destinationEnvelopeId: destinationEnvelopeId,
        nativeAmount: Money(
          amount: BigInt.from(5000),
          currency: CurrencyCode('VES'),
        ),
        currentRate: Decimal.parse('40.00'),
        memo: '',
      );

      expect(store.events.last.metadata.memo, isNull);
    });
  });
}
