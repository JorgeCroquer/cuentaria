import 'backup_header.dart';

/// A fully parsed Backup File (ADR-0021). Catalog lines ([accounts],
/// [envelopes]) and [cascades]/[rates] are decoded JSON objects; [events]
/// stay as opaque payload text — [BackupReader] never decodes them, so a
/// stored event is byte-identical to the one that comes back out.
class BackupFile {
  final BackupHeader header;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> envelopes;
  final List<Map<String, dynamic>> cascades;
  final List<String> events;
  final List<Map<String, dynamic>> rates;

  const BackupFile({
    required this.header,
    required this.accounts,
    required this.envelopes,
    required this.cascades,
    required this.events,
    required this.rates,
  });
}
