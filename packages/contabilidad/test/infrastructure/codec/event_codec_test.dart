// Tests for EventCodec — canonical serializer + upcasting seam (F2 Slice 1).
// Verifies:
//   - round-trip (decode(encode(tx)) == tx) for all C1 transaction shapes
//   - encoding stability: same object → same bytes, keys are sorted
//   - money serialized as strings (BigInt, no double)
//   - timestamps round-trip ISO-8601 UTC ↔ DomainTimestamp
//   - upcaster registry: v1 → identity; future schema_version → typed error
//   - integration seam: codec ↔ upcaster registry

import 'dart:convert';

import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/infrastructure/codec/codec_error.dart';
import 'package:contabilidad/infrastructure/codec/event_codec.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

TransactionMetadata _meta({
  String? eventId,
  String type = 'Income',
  int? schemaVersion,
  EventId? reverses,
  String? memo,
}) {
  return TransactionMetadata(
    eventId: EventId(eventId ?? 'evt-test-001'),
    type: type,
    occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 16, 10, 30)),
    recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 16, 10, 31)),
    deviceId: 'device-abc',
    schemaVersion: schemaVersion ?? 1,
    reverses: reverses,
    memo: memo,
  );
}

Posting _accountPosting({
  String accountId = 'acc-001',
  BigInt? amount,
  String currency = 'USD',
  int amountUsd = 100,
  String? rateRef,
}) {
  return Posting(
    target: AccountTarget(AccountId(accountId)),
    amountNative: Money(
      amount: amount ?? BigInt.from(100),
      currency: CurrencyCode(currency),
    ),
    currency: CurrencyCode(currency),
    amountUsd: amountUsd,
    rateRef: rateRef,
  );
}

Posting _envelopePosting({
  String envelopeId = 'env-001',
  BigInt? amount,
  String currency = 'USD',
  int amountUsd = 100,
}) {
  return Posting(
    target: EnvelopeTarget(EnvelopeId(envelopeId)),
    amountNative: Money(
      amount: amount ?? BigInt.from(100),
      currency: CurrencyCode(currency),
    ),
    currency: CurrencyCode(currency),
    amountUsd: amountUsd,
  );
}

Transaction _simple({
  String type = 'Income',
  List<Posting>? postings,
  int? schemaVersion,
}) {
  final ps = postings ?? [_accountPosting(), _envelopePosting()];
  return Transaction.create(
    postings: ps,
    metadata: _meta(type: type, schemaVersion: schemaVersion),
  );
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  final codec = EventCodec();

  // -------------------------------------------------------------------------
  // 1. Round-trip per transaction shape
  // -------------------------------------------------------------------------

  group('EventCodec round-trip', () {
    test('Income: decode(encode(tx)) == tx', () {
      final tx = _simple(type: 'Income');
      expect(codec.decode(codec.encode(tx)), equals(tx));
    });

    test('UsdExpense: decode(encode(tx)) == tx', () {
      final tx = _simple(type: 'UsdExpense');
      expect(codec.decode(codec.encode(tx)), equals(tx));
    });

    test('ForeignCurrencyExpense with Bs (large minor units)', () {
      final bsAmount = BigInt.parse('123456789012345678');
      final tx = Transaction.create(
        postings: [
          _accountPosting(currency: 'VES', amount: bsAmount, amountUsd: 100),
          _envelopePosting(currency: 'VES', amount: bsAmount, amountUsd: 100),
        ],
        metadata: _meta(type: 'ForeignCurrencyExpense'),
      );
      expect(codec.decode(codec.encode(tx)), equals(tx));
    });

    test('Realization: decode(encode(tx)) == tx', () {
      final tx = Transaction.create(
        postings: [
          _accountPosting(
            accountId: 'acc-ves',
            currency: 'VES',
            amount: BigInt.from(3600000),
            amountUsd: 100,
          ),
          _envelopePosting(
            envelopeId: 'env-stage',
            currency: 'VES',
            amount: BigInt.from(3600000),
            amountUsd: 100,
          ),
        ],
        metadata: _meta(type: 'Realization'),
      );
      expect(codec.decode(codec.encode(tx)), equals(tx));
    });

    test('Transfer: zero-sum account+envelope postings', () {
      final tx = Transaction.create(
        postings: [
          Posting(
            target: AccountTarget(AccountId('acc-1')),
            amountNative: Money(
              amount: BigInt.from(-50),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: -50,
          ),
          Posting(
            target: AccountTarget(AccountId('acc-2')),
            amountNative: Money(
              amount: BigInt.from(50),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 50,
          ),
          Posting(
            target: EnvelopeTarget(EnvelopeId('env-1')),
            amountNative: Money(
              amount: BigInt.from(-50),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: -50,
          ),
          Posting(
            target: EnvelopeTarget(EnvelopeId('env-2')),
            amountNative: Money(
              amount: BigInt.from(50),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 50,
          ),
        ],
        metadata: _meta(type: 'Transfer'),
      );
      expect(codec.decode(codec.encode(tx)), equals(tx));
    });

    test('AcquisitionConversion: decode(encode(tx)) == tx', () {
      final tx = _simple(type: 'AcquisitionConversion');
      expect(codec.decode(codec.encode(tx)), equals(tx));
    });

    test('DispositionConversion: decode(encode(tx)) == tx', () {
      final tx = _simple(type: 'DispositionConversion');
      expect(codec.decode(codec.encode(tx)), equals(tx));
    });

    test('Distribution: decode(encode(tx)) == tx', () {
      final tx = _simple(type: 'Distribution');
      expect(codec.decode(codec.encode(tx)), equals(tx));
    });

    test('Adjustment: with memo, decode(encode(tx)) == tx', () {
      final tx = Transaction.create(
        postings: [_accountPosting(), _envelopePosting()],
        metadata: _meta(type: 'Adjustment', memo: 'Corrección manual'),
      );
      expect(codec.decode(codec.encode(tx)), equals(tx));
    });

    test('Opening: decode(encode(tx)) == tx', () {
      final tx = _simple(type: 'Opening');
      expect(codec.decode(codec.encode(tx)), equals(tx));
    });

    test('Reversal: with reverses field set', () {
      final reversedId = EventId('evt-original-001');
      final tx = Transaction.create(
        postings: [
          _accountPosting(amountUsd: -100, amount: BigInt.from(-100)),
          _envelopePosting(amountUsd: -100, amount: BigInt.from(-100)),
        ],
        metadata: _meta(
          eventId: 'evt-reversal-001',
          type: 'Reversal',
          reverses: reversedId,
        ),
      );
      expect(codec.decode(codec.encode(tx)), equals(tx));
    });

    test('optional fields (source, memo, rateRef) preserved', () {
      final tx = Transaction.create(
        postings: [
          Posting(
            target: AccountTarget(AccountId('acc-1')),
            amountNative: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 100,
            rateRef: 'rate-ref-xyz',
          ),
          _envelopePosting(),
        ],
        metadata: TransactionMetadata(
          eventId: EventId('evt-src-001'),
          type: 'Income',
          occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 16, 10, 30)),
          recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 16, 10, 31)),
          deviceId: 'device-abc',
          schemaVersion: 1,
          source: 'bank-import',
          memo: 'salary deposit',
        ),
      );
      expect(codec.decode(codec.encode(tx)), equals(tx));
    });
  });

  // -------------------------------------------------------------------------
  // 2. Encoding stability
  // -------------------------------------------------------------------------

  group('EventCodec stability', () {
    test('same object encodes to identical bytes', () {
      final tx = _simple();
      expect(codec.encode(tx), equals(codec.encode(tx)));
    });

    test('equal Transaction objects produce identical JSON', () {
      final tx1 = _simple();
      final tx2 = _simple();
      expect(tx1, equals(tx2));
      expect(codec.encode(tx1), equals(codec.encode(tx2)));
    });

    test('JSON keys are sorted (alphabetical order) at top level', () {
      final tx = _simple();
      final json = jsonDecode(codec.encode(tx)) as Map<String, dynamic>;
      final keys = json.keys.toList();
      final sorted = [...keys]..sort();
      expect(keys, equals(sorted), reason: 'Top-level keys must be sorted');
    });

    test('posting keys are sorted', () {
      final tx = _simple();
      final json = jsonDecode(codec.encode(tx)) as Map<String, dynamic>;
      final postings = json['postings'] as List<dynamic>;
      for (final p in postings) {
        final pm = p as Map<String, dynamic>;
        final keys = pm.keys.toList();
        final sorted = [...keys]..sort();
        expect(keys, equals(sorted), reason: 'Posting keys must be sorted');
      }
    });

    test('no incidental whitespace in canonical output', () {
      final encoded = codec.encode(_simple());
      expect(encoded, isNot(contains(' ')), reason: 'No spaces');
      expect(encoded, isNot(contains('\n')), reason: 'No newlines');
      expect(encoded, isNot(contains('\t')), reason: 'No tabs');
    });
  });

  // -------------------------------------------------------------------------
  // 3. Money as string — no double
  // -------------------------------------------------------------------------

  group('EventCodec money serialization', () {
    test('amount_native serialized as string, not number', () {
      final tx = _simple();
      final raw = jsonDecode(codec.encode(tx)) as Map<String, dynamic>;
      final postings = raw['postings'] as List<dynamic>;
      for (final p in postings) {
        final pm = p as Map<String, dynamic>;
        expect(
          pm['amount_native'],
          isA<String>(),
          reason: 'amount_native must be a string',
        );
      }
    });

    test('amount_usd serialized as string, not number', () {
      final tx = _simple();
      final raw = jsonDecode(codec.encode(tx)) as Map<String, dynamic>;
      final postings = raw['postings'] as List<dynamic>;
      for (final p in postings) {
        final pm = p as Map<String, dynamic>;
        expect(
          pm['amount_usd'],
          isA<String>(),
          reason: 'amount_usd must be a string',
        );
      }
    });

    test('large BigInt (crypto amount) preserved without precision loss', () {
      // 21 million BTC in satoshis: 2_100_000_000_000_000
      final bigAmount = BigInt.parse('2100000000000000');
      final tx = Transaction.create(
        postings: [
          Posting(
            target: AccountTarget(AccountId('acc-btc')),
            amountNative: Money(
              amount: bigAmount,
              currency: CurrencyCode('BTC'),
            ),
            currency: CurrencyCode('BTC'),
            amountUsd: 2100000000000000,
          ),
          Posting(
            target: EnvelopeTarget(EnvelopeId('env-btc')),
            amountNative: Money(
              amount: bigAmount,
              currency: CurrencyCode('BTC'),
            ),
            currency: CurrencyCode('BTC'),
            amountUsd: 2100000000000000,
          ),
        ],
        metadata: _meta(type: 'Opening'),
      );
      final decoded = codec.decode(codec.encode(tx));
      expect(decoded.postings.first.amountNative.amount, equals(bigAmount));
    });

    test('high Bs minor-unit amount preserved without precision loss', () {
      final bsAmount = BigInt.parse('999999999999999999');
      final tx = Transaction.create(
        postings: [
          _accountPosting(currency: 'VES', amount: bsAmount, amountUsd: 100),
          _envelopePosting(currency: 'VES', amount: bsAmount, amountUsd: 100),
        ],
        metadata: _meta(type: 'ForeignCurrencyExpense'),
      );
      final decoded = codec.decode(codec.encode(tx));
      expect(decoded.postings.first.amountNative.amount, equals(bsAmount));
    });

    test('negative amounts serialize and deserialize correctly', () {
      final tx = Transaction.create(
        postings: [
          _accountPosting(amountUsd: -50, amount: BigInt.from(-50)),
          _envelopePosting(amountUsd: -50, amount: BigInt.from(-50)),
        ],
        metadata: _meta(type: 'Adjustment'),
      );
      final decoded = codec.decode(codec.encode(tx));
      expect(
        decoded.postings.first.amountNative.amount,
        equals(BigInt.from(-50)),
      );
      expect(decoded.postings.first.amountUsd, equals(-50));
    });
  });

  // -------------------------------------------------------------------------
  // 4. Timestamp round-trip ISO-8601 UTC
  // -------------------------------------------------------------------------

  group('EventCodec timestamp serialization', () {
    test('occurred_at serializes as ISO-8601 UTC string ending with Z', () {
      final tx = _simple();
      final raw = jsonDecode(codec.encode(tx)) as Map<String, dynamic>;
      final occurredAt = raw['occurred_at'] as String;
      expect(occurredAt, endsWith('Z'), reason: 'ISO-8601 UTC must end with Z');
      final parsed = DateTime.parse(occurredAt);
      expect(parsed.isUtc, isTrue);
    });

    test('recorded_at serializes as ISO-8601 UTC string ending with Z', () {
      final tx = _simple();
      final raw = jsonDecode(codec.encode(tx)) as Map<String, dynamic>;
      final recordedAt = raw['recorded_at'] as String;
      expect(recordedAt, endsWith('Z'));
    });

    test('timestamps round-trip: value preserved exactly', () {
      final occurred = DateTime.utc(2026, 1, 15, 8, 0, 0, 500);
      final recorded = DateTime.utc(2026, 1, 15, 8, 0, 1, 0);
      final tx = Transaction.create(
        postings: [_accountPosting(), _envelopePosting()],
        metadata: TransactionMetadata(
          eventId: EventId('evt-ts-001'),
          type: 'Income',
          occurredAt: DomainTimestamp(occurred),
          recordedAt: DomainTimestamp(recorded),
          deviceId: 'device-x',
          schemaVersion: 1,
        ),
      );
      final decoded = codec.decode(codec.encode(tx));
      expect(decoded.metadata.occurredAt.value, equals(occurred));
      expect(decoded.metadata.recordedAt.value, equals(recorded));
    });
  });

  // -------------------------------------------------------------------------
  // 5. Upcaster registry
  // -------------------------------------------------------------------------

  group('EventCodec upcaster registry', () {
    test('v1 payload is accepted (identity upcaster)', () {
      final tx = _simple(schemaVersion: 1);
      expect(() => codec.decode(codec.encode(tx)), returnsNormally);
    });

    test('future schema_version throws UnsupportedSchemaVersion', () {
      final tx = _simple(schemaVersion: 999);
      final encoded = codec.encode(tx);
      expect(
        () => codec.decode(encoded),
        throwsA(isA<UnsupportedSchemaVersion>()),
      );
    });

    test('UnsupportedSchemaVersion carries the version number', () {
      final tx = _simple(schemaVersion: 2);
      final encoded = codec.encode(tx);
      try {
        codec.decode(encoded);
        fail('should have thrown');
      } on UnsupportedSchemaVersion catch (e) {
        expect(e.version, equals(2));
      }
    });
  });

  // -------------------------------------------------------------------------
  // 6. Integration seam: codec ↔ upcaster registry
  // -------------------------------------------------------------------------

  group('EventCodec ↔ upcaster registry integration', () {
    test(
      'v1 payload flows through identity upcaster and reconstructs exact Transaction',
      () {
        final tx = Transaction.create(
          postings: [
            _accountPosting(amountUsd: 250),
            _envelopePosting(amountUsd: 250),
          ],
          metadata: _meta(
            eventId: 'evt-integration-001',
            type: 'Income',
            schemaVersion: 1,
            memo: 'integration test',
          ),
        );
        final encoded = codec.encode(tx);
        final decoded = codec.decode(encoded);
        expect(decoded, equals(tx));
        expect(decoded.metadata.schemaVersion, equals(1));
        expect(decoded.metadata.memo, equals('integration test'));
      },
    );

    test('all fields survive the full codec pipeline', () {
      final reversedId = EventId('evt-original-xyz');
      final tx = Transaction.create(
        postings: [
          Posting(
            target: AccountTarget(AccountId('acc-full')),
            amountNative: Money(
              amount: BigInt.from(500),
              currency: CurrencyCode('VES'),
            ),
            currency: CurrencyCode('VES'),
            amountUsd: 50,
            rateRef: 'rate-001',
          ),
          Posting(
            target: EnvelopeTarget(EnvelopeId('env-full')),
            amountNative: Money(
              amount: BigInt.from(500),
              currency: CurrencyCode('VES'),
            ),
            currency: CurrencyCode('VES'),
            amountUsd: 50,
          ),
        ],
        metadata: TransactionMetadata(
          eventId: EventId('evt-full-001'),
          type: 'Realization',
          occurredAt: DomainTimestamp(DateTime.utc(2026, 3, 10, 14, 0)),
          recordedAt: DomainTimestamp(DateTime.utc(2026, 3, 10, 14, 1)),
          deviceId: 'device-full',
          schemaVersion: 1,
          source: 'manual',
          reverses: reversedId,
          memo: 'P2P exchange',
        ),
      );
      final decoded = codec.decode(codec.encode(tx));
      expect(decoded, equals(tx));
      expect(decoded.metadata.reverses?.value, equals('evt-original-xyz'));
      expect(decoded.metadata.source, equals('manual'));
    });
  });
}
