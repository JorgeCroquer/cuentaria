/// Typed errors produced by [EventCodec].
library;

/// Thrown when [EventCodec.decode] cannot parse or reconstruct a payload
/// because required fields are missing, have wrong types, or the JSON is
/// syntactically invalid.
///
/// Wraps the underlying error as [cause] so callers can log details without
/// depending on opaque [TypeError] / [CastError] internals.
class MalformedPayload implements Exception {
  /// Human-readable description of what was wrong.
  final String message;

  /// The original error (e.g. [TypeError], [FormatException], [ArgumentError]).
  final Object cause;

  const MalformedPayload({required this.message, required this.cause});

  @override
  String toString() => 'MalformedPayload: $message (cause: $cause)';
}

/// Thrown when [EventCodec.decode] encounters a [schema_version] greater than
/// the maximum version the current codec supports.
///
/// Never silently ignored — the caller must handle unknown-future payloads.
class UnsupportedSchemaVersion implements Exception {
  /// The [schema_version] value found in the payload.
  final int version;

  /// The maximum [schema_version] this codec can handle.
  final int maxSupported;

  const UnsupportedSchemaVersion({
    required this.version,
    required this.maxSupported,
  });

  @override
  String toString() =>
      'UnsupportedSchemaVersion: payload has schema_version=$version '
      'but this codec only supports up to $maxSupported. '
      'Upgrade the app to handle this payload.';
}
