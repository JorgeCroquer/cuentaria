/// Typed errors produced by [EventCodec].
library;

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
