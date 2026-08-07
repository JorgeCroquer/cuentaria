/// The Backup File format version (ADR-0021 §1). A file whose header
/// declares a different [backupFormatVersion] is rejected outright rather
/// than guessed at — the format is a compatibility contract once a real
/// backup exists in someone's Drive.
const int backupFormatVersion = 1;

/// The `app` field stamped on every Backup File header.
const String backupAppName = 'cuentaria';
