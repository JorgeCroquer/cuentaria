/// Upcaster registry for the [EventCodec] deserialization pipeline.
///
/// An upcaster is a pure function `Map<String,dynamic> → Map<String,dynamic>`
/// that migrates a canonical JSON payload from schema version N to version N+1.
///
/// Today only v1 is defined; the registry applies the identity transform
/// (no-op). When v2 is introduced, add a v1→v2 upcaster here and register it.
///
/// Rule: a payload whose [schema_version] is GREATER than [maxSupportedVersion]
/// is REJECTED with [UnsupportedSchemaVersion] — never guessed or silently
/// dropped.
library;

import 'codec_error.dart';

typedef Upcaster = Map<String, dynamic> Function(Map<String, dynamic> payload);

/// The highest [schema_version] value this registry can handle.
const int maxSupportedVersion = 1;

/// Registered upcasters, keyed by the source version they consume.
///
/// An upcaster at key K transforms a v-K payload into a v-(K+1) payload.
/// There is no upcaster for [maxSupportedVersion] — the payload is already
/// at the latest version.
const Map<int, Upcaster> _upcasters = {
  // v1 → v1 is a no-op (identity); no entry needed: the loop stops when the
  // payload version equals maxSupportedVersion.
};

/// Applies the upcaster chain to [payload] until its [schema_version] equals
/// [maxSupportedVersion].
///
/// Throws [UnsupportedSchemaVersion] if the payload's version exceeds
/// [maxSupportedVersion].
Map<String, dynamic> upcast(Map<String, dynamic> payload) {
  final rawVersion = payload['schema_version'];
  if (rawVersion == null) {
    throw ArgumentError(
      'Payload is missing the required schema_version field.',
    );
  }
  var version = rawVersion as int;

  if (version > maxSupportedVersion) {
    throw UnsupportedSchemaVersion(
      version: version,
      maxSupported: maxSupportedVersion,
    );
  }

  var current = payload;

  while (version < maxSupportedVersion) {
    final upcaster = _upcasters[version];
    if (upcaster == null) {
      // Should never happen if _upcasters is kept in sync with maxSupportedVersion.
      throw StateError(
        'No upcaster registered for schema_version=$version. '
        'Cannot upcast to $maxSupportedVersion.',
      );
    }
    current = upcaster(current);
    version++;
  }

  return current;
}
