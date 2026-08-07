import 'package:backup/backup.dart';
import 'package:contabilidad/application/cascade/cascade.dart';
import 'package:contabilidad/application/cascade/cascade_codec.dart';
import 'package:contabilidad/application/cascade/cascade_repository.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/ports/event_store.dart';
import 'package:tasas/domain/rate_series.dart';
import 'package:tasas/infrastructure/ndjson/ndjson_rate_store.dart';

/// A Backup File ready to hand to the system share sheet (ADR-0021).
class CreateBackupResult {
  final String filename;
  final String content;
  final BackupCounts counts;

  const CreateBackupResult({
    required this.filename,
    required this.content,
    required this.counts,
  });
}

/// Reads the four sources a Backup File needs — the event log
/// ([EventStore.queryRawPayloads], byte-identical), the Catalog
/// ([CatalogRepository]), the Cascade plan ([CascadeRepository]) and the
/// Rate Series ([RateSeries]) — and writes them through [BackupWriter].
///
/// App-layer wiring, not a `backup`-package use case: `backup` depends only
/// on `shared_kernel` (ADR-0021 §Critical Architecture Safeguards), so
/// mapping contabilidad/tasas ports into its line shapes has to live where
/// all three packages are already visible together.
class CreateBackup {
  final EventStore eventStore;
  final CatalogRepository catalog;
  final CascadeRepository cascade;
  final RateSeries rates;
  final BackupWriter _writer;
  final DateTime Function() _now;

  CreateBackup({
    required this.eventStore,
    required this.catalog,
    required this.cascade,
    required this.rates,
    BackupWriter writer = const BackupWriter(),
    DateTime Function()? now,
  }) : _writer = writer,
       _now = now ?? DateTime.now;

  Future<CreateBackupResult> call() async {
    final exportedAt = _now().toUtc();

    final eventPayloads = await eventStore.queryRawPayloads();
    final accounts = catalog.accounts.map(_accountToJson).toList();
    final envelopes = catalog.envelopes.map(_envelopeToJson).toList();

    final cascadeDoc = await cascade.load();
    final cascades =
        cascadeDoc == null
            ? const <Map<String, dynamic>>[]
            : [_cascadeToJson(cascadeDoc)];

    final rateObservations =
        (await rates.allObservations()).map(NdjsonRateStore.toJson).toList();

    final content = _writer.write(
      exportedAt: exportedAt,
      accounts: accounts,
      envelopes: envelopes,
      cascades: cascades,
      events: eventPayloads,
      rates: rateObservations,
    );

    return CreateBackupResult(
      filename: _filenameFor(exportedAt),
      content: content,
      counts: BackupCounts(
        event: eventPayloads.length,
        account: accounts.length,
        envelope: envelopes.length,
        cascade: cascades.length,
        rate: rateObservations.length,
      ),
    );
  }

  static String _filenameFor(DateTime exportedAt) {
    final year = exportedAt.year.toString().padLeft(4, '0');
    final month = exportedAt.month.toString().padLeft(2, '0');
    final day = exportedAt.day.toString().padLeft(2, '0');
    return 'cuentaria-$year-$month-$day.ndjson';
  }

  static Map<String, dynamic> _accountToJson(Account account) => {
    'id': account.id.value,
    'name': account.name,
    'nativeCurrency': account.nativeCurrency.value,
    if (account.provider != null) 'provider': account.provider,
    'isArchived': account.isArchived,
    'updatedAt': account.updatedAt.toUtc().toIso8601String(),
    if (account.meta != null) 'meta': account.meta,
  };

  static Map<String, dynamic> _envelopeToJson(Envelope envelope) => {
    'id': envelope.id.value,
    'name': envelope.name,
    'role': envelope.role.name,
    'isArchived': envelope.isArchived,
    'updatedAt': envelope.updatedAt.toUtc().toIso8601String(),
    if (envelope.meta != null) 'meta': envelope.meta,
  };

  static Map<String, dynamic> _cascadeToJson(Cascade cascade) => {
    'steps': CascadeCodec.stepsToJson(cascade.steps),
    'updatedAt': cascade.updatedAt.toUtc().toIso8601String(),
  };
}
