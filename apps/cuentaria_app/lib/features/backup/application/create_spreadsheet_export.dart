import 'package:backup/backup.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/ports/event_store.dart';

/// A CSV Export ready to hand to the system share sheet (ADR-0021 §8).
class CreateSpreadsheetExportResult {
  final String filename;
  final String content;
  final int rowCount;

  const CreateSpreadsheetExportResult({
    required this.filename,
    required this.content,
    required this.rowCount,
  });
}

/// Flattens the Ledger to one CSV row per [Posting] and resolves each
/// target's name against the Catalog (#195, ADR-0021 §8).
///
/// App-layer wiring, not a `backup`-package use case: `backup` depends only
/// on `shared_kernel`, so mapping `contabilidad`'s `Transaction`/`Posting`
/// and resolving Catalog names has to live where both packages are visible
/// together — mirrors [CreateBackup].
class CreateSpreadsheetExport {
  final EventStore eventStore;
  final CatalogRepository catalog;
  final CsvWriter _writer;
  final DateTime Function() _now;

  CreateSpreadsheetExport({
    required this.eventStore,
    required this.catalog,
    CsvWriter writer = const CsvWriter(),
    DateTime Function()? now,
  }) : _writer = writer,
       _now = now ?? DateTime.now;

  Future<CreateSpreadsheetExportResult> call() async {
    final exportedAt = _now().toUtc();
    final transactions = await eventStore.queryLog();

    final rows = <CsvRow>[
      for (final tx in transactions)
        for (final posting in tx.postings)
          CsvRow(
            fecha: tx.metadata.occurredAt.value,
            tipo: tx.metadata.type,
            memo: tx.metadata.memo ?? '',
            dimension: _dimensionOf(posting),
            nombre: _nombreOf(posting),
            montoNativo: posting.amountNative,
            montoUsdCents: posting.amountUsd,
            tasa: posting.rateRef ?? '',
            eventId: tx.metadata.eventId.value,
          ),
    ];

    final content = _writer.writeCsv(rows);

    return CreateSpreadsheetExportResult(
      filename: _filenameFor(exportedAt),
      content: content,
      rowCount: rows.length,
    );
  }

  String _dimensionOf(Posting posting) => switch (posting.target) {
    AccountTarget() => 'cuenta',
    EnvelopeTarget() => 'sobre',
  };

  String _nombreOf(Posting posting) => switch (posting.target) {
    AccountTarget(:final accountId) =>
      catalog.getAccount(accountId)?.name ?? accountId.value,
    EnvelopeTarget(:final envelopeId) =>
      catalog.getEnvelope(envelopeId)?.name ?? envelopeId.value,
  };

  static String _filenameFor(DateTime exportedAt) {
    final year = exportedAt.year.toString().padLeft(4, '0');
    final month = exportedAt.month.toString().padLeft(2, '0');
    final day = exportedAt.day.toString().padLeft(2, '0');
    return 'cuentaria-$year-$month-$day.csv';
  }
}
