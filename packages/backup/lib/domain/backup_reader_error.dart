/// Typed errors produced by [BackupReader.parse] (ADR-0021 §6).
///
/// Every rejection is all-or-nothing: [BackupReader.parse] either returns a
/// fully-parsed [BackupFile] or throws one of these before returning
/// anything, so a caller never sees a partially-parsed file. [InvalidLine]
/// and [TruncatedFile] name the specific problem so the caller can tell the
/// user *why*, not just *that* the file was rejected.
library;

/// Base type for every rejection [BackupReader.parse] can throw.
sealed class BackupReaderError implements Exception {
  const BackupReaderError();

  /// Human-readable reason, without any leading "el archivo"/"el respaldo"
  /// framing — callers compose it into their own sentence.
  String get message;

  @override
  String toString() => message;
}

/// The header's `format` is not [backupFormatVersion]. Not a broken file —
/// it is from a different (usually newer) version of the app, so callers
/// must show a distinct message that does not mention a line number.
class UnknownFormatVersion extends BackupReaderError {
  final int formatVersion;

  const UnknownFormatVersion(this.formatVersion);

  @override
  String get message =>
      'el formato del respaldo ($formatVersion) no es compatible con esta '
      'versión de la app';

  @override
  bool operator ==(Object other) =>
      other is UnknownFormatVersion && other.formatVersion == formatVersion;

  @override
  int get hashCode => formatVersion.hashCode;
}

/// The file has no readable header: it is empty, its first line is not
/// valid JSON, is missing required fields, or its `kind` is not `"header"`.
class InvalidHeader extends BackupReaderError {
  final String reason;

  const InvalidHeader(this.reason);

  @override
  String get message => 'el archivo no tiene un encabezado válido: $reason';

  @override
  bool operator ==(Object other) =>
      other is InvalidHeader && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

/// The header's [BackupCounts] do not match the lines actually present —
/// the file was cut off partway through.
class TruncatedFile extends BackupReaderError {
  final String expected;
  final String actual;

  const TruncatedFile({required this.expected, required this.actual});

  @override
  String get message =>
      'el archivo está incompleto: el encabezado declara $expected pero el '
      'archivo trae $actual';

  @override
  bool operator ==(Object other) =>
      other is TruncatedFile &&
      other.expected == expected &&
      other.actual == actual;

  @override
  int get hashCode => Object.hash(expected, actual);
}

/// A single data line (1-indexed, matching what a text editor shows)
/// cannot be understood: invalid JSON, unknown `kind`, missing/malformed
/// `data`, or (for event lines decoded downstream by `EventCodec`) a
/// payload that fails to decode, targets an unsupported schema version, or
/// violates the self-balance invariant (ADR-0006).
class InvalidLine extends BackupReaderError {
  final int lineNumber;
  final String reason;

  const InvalidLine({required this.lineNumber, required this.reason});

  @override
  String get message => 'el renglón $lineNumber $reason';

  @override
  bool operator ==(Object other) =>
      other is InvalidLine &&
      other.lineNumber == lineNumber &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(lineNumber, reason);
}
