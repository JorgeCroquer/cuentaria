/// Canonical serializer and deserializer for [Transaction] ↔ JSON.
///
/// Design invariants (enforced by tests, F2 PRD, ADR-0002):
///   - Money ALWAYS as string of minor units (BigInt for native, int for USD).
///     Never a JSON number — no `double` in any money path.
///   - Currency as 3-letter ISO-4217 string, separate from the amount.
///   - Timestamps as ISO-8601 UTC strings in the payload.
///   - Keys sorted alphabetically at every nesting level → stable bytes.
///   - No whitespace → canonical, deterministic, byte-identical for equal
///     objects.
///   - Domain types carry no JSON code: the domain is JSON-free.
///   - Deserialization routes through the [upcaster_registry] pipeline before
///     reconstructing domain objects.
library;

import 'dart:convert';

import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'upcaster_registry.dart' as registry;

/// Serializes and deserializes [Transaction] to/from canonical JSON.
class EventCodec {
  const EventCodec();

  // -------------------------------------------------------------------------
  // Encode
  // -------------------------------------------------------------------------

  /// Encodes [tx] to a canonical JSON string.
  ///
  /// Properties:
  ///   - Keys sorted alphabetically at every level.
  ///   - No whitespace.
  ///   - Money fields are strings of minor units.
  ///   - Timestamps are ISO-8601 UTC strings.
  String encode(Transaction tx) {
    final map = _transactionToMap(tx);
    return jsonEncode(map);
  }

  // -------------------------------------------------------------------------
  // Decode
  // -------------------------------------------------------------------------

  /// Decodes [json] back to a [Transaction].
  ///
  /// Routes the raw map through [registry.upcast] before reconstruction.
  /// Throws [UnsupportedSchemaVersion] if the payload's schema_version
  /// exceeds what this codec supports.
  Transaction decode(String json) {
    final raw = jsonDecode(json) as Map<String, dynamic>;
    final upcasted = registry.upcast(raw);
    return _transactionFromMap(upcasted);
  }

  // -------------------------------------------------------------------------
  // Private helpers — to map
  // -------------------------------------------------------------------------

  Map<String, dynamic> _transactionToMap(Transaction tx) {
    final m = <String, dynamic>{};
    final meta = tx.metadata;

    // Metadata fields
    m['device_id'] = meta.deviceId;
    m['event_id'] = meta.eventId.value;
    if (meta.memo != null) m['memo'] = meta.memo;
    m['occurred_at'] = _encodeTimestamp(meta.occurredAt);
    m['postings'] = tx.postings.map(_postingToMap).toList();
    m['recorded_at'] = _encodeTimestamp(meta.recordedAt);
    if (meta.reverses != null) m['reverses'] = meta.reverses!.value;
    m['schema_version'] = meta.schemaVersion;
    if (meta.source != null) m['source'] = meta.source;
    m['type'] = meta.type;

    // Sort keys at top level and return
    return _sortedMap(m);
  }

  Map<String, dynamic> _postingToMap(Posting p) {
    final m = <String, dynamic>{};

    // amount_native: string of BigInt minor units
    m['amount_native'] = p.amountNative.amount.toString();
    // amount_usd: string of int cents
    m['amount_usd'] = p.amountUsd.toString();
    // currency: 3-letter code
    m['currency'] = p.currency.value;
    if (p.rateRef != null) m['rate_ref'] = p.rateRef;
    // target: dimension + id
    m['target'] = _targetToMap(p.target);

    return _sortedMap(m);
  }

  Map<String, dynamic> _targetToMap(PostingTarget target) {
    final m = <String, dynamic>{};
    switch (target) {
      case AccountTarget(:final accountId):
        m['dimension'] = 'account';
        m['id'] = accountId.value;
      case EnvelopeTarget(:final envelopeId):
        m['dimension'] = 'envelope';
        m['id'] = envelopeId.value;
    }
    return _sortedMap(m);
  }

  String _encodeTimestamp(DomainTimestamp ts) {
    // toIso8601String on a UTC DateTime ends with 'Z'
    return ts.value.toUtc().toIso8601String();
  }

  /// Returns a new [Map] whose keys are sorted alphabetically.
  Map<String, dynamic> _sortedMap(Map<String, dynamic> input) {
    final sorted = Map<String, dynamic>.fromEntries(
      (input.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
    );
    return sorted;
  }

  // -------------------------------------------------------------------------
  // Private helpers — from map
  // -------------------------------------------------------------------------

  Transaction _transactionFromMap(Map<String, dynamic> m) {
    final meta = TransactionMetadata(
      eventId: EventId(m['event_id'] as String),
      type: m['type'] as String,
      occurredAt: _decodeTimestamp(m['occurred_at'] as String),
      recordedAt: _decodeTimestamp(m['recorded_at'] as String),
      deviceId: m['device_id'] as String,
      schemaVersion: m['schema_version'] as int,
      source: m['source'] as String?,
      reverses: m['reverses'] != null ? EventId(m['reverses'] as String) : null,
      memo: m['memo'] as String?,
    );

    final postingsList =
        (m['postings'] as List<dynamic>)
            .map((p) => _postingFromMap(p as Map<String, dynamic>))
            .toList();

    return Transaction.create(postings: postingsList, metadata: meta);
  }

  Posting _postingFromMap(Map<String, dynamic> m) {
    final target = _targetFromMap(m['target'] as Map<String, dynamic>);
    final amountNative = BigInt.parse(m['amount_native'] as String);
    final amountUsd = int.parse(m['amount_usd'] as String);
    final currency = CurrencyCode(m['currency'] as String);
    final rateRef = m['rate_ref'] as String?;

    return Posting(
      target: target,
      amountNative: Money(amount: amountNative, currency: currency),
      currency: currency,
      amountUsd: amountUsd,
      rateRef: rateRef,
    );
  }

  PostingTarget _targetFromMap(Map<String, dynamic> m) {
    final dimension = m['dimension'] as String;
    final id = m['id'] as String;
    return switch (dimension) {
      'account' => AccountTarget(AccountId(id)),
      'envelope' => EnvelopeTarget(EnvelopeId(id)),
      _ => throw ArgumentError('Unknown posting dimension: $dimension'),
    };
  }

  DomainTimestamp _decodeTimestamp(String iso) {
    return DomainTimestamp(DateTime.parse(iso).toUtc());
  }
}
