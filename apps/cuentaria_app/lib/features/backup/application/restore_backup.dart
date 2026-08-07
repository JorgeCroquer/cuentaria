import 'dart:convert';

import 'package:backup/backup.dart';
import 'package:contabilidad/application/cascade/cascade.dart';
import 'package:contabilidad/application/cascade/cascade_codec.dart';
import 'package:contabilidad/application/cascade/cascade_repository.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/unit_of_work.dart';
import 'package:contabilidad/domain/ports/event_store.dart';
import 'package:contabilidad/domain/ports/ledger_projections.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_error.dart';
import 'package:contabilidad/infrastructure/codec/codec_error.dart';
import 'package:contabilidad/infrastructure/codec/event_codec.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/application/sync_rate_series_use_case.dart';
import 'package:tasas/domain/rate_series.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_feed.dart';

/// Thrown when a Backup File cannot be restored. [message] names the
/// specific line and reason for a broken file, or a distinct message for a
/// file from a newer app version — never a partial write (ADR-0021 §6).
class RestoreBackupError implements Exception {
  final String message;
  const RestoreBackupError(this.message);

  @override
  String toString() => message;
}

class RestoreBackupResult {
  /// Total events the Backup File declared — not the delta actually
  /// inserted, so restoring the same file twice shows the same count both
  /// times (ADR-0021 §7: a duplicate is silently ignored, not reported).
  final int eventsRestored;

  const RestoreBackupResult({required this.eventsRestored});
}

/// Restores a Backup File written by [CreateBackup] (ADR-0021 §6-7).
///
/// Two passes: everything is parsed and decoded into domain objects first —
/// [BackupReader.parse], [EventCodec.decode] (which re-runs
/// [Transaction.create]'s self-balance check, ADR-0006, on data from outside
/// the device) — and only once all of that succeeds does the second pass
/// write anything. Writes reuse each port's existing idempotent merge
/// (`saveAccount`/`saveEnvelope` LWW, `cascade.save` LWW, `eventStore.append`
/// dedup by `event_id`, [SyncRateSeriesUseCase] dedup by
/// `(currency, source, observedAt)`) — restoring onto a device that already
/// has data, or restoring the same file twice, is safe with no new merge
/// code.
///
/// The write pass runs inside a [UnitOfWork] so it is all-or-nothing even if
/// the process dies in the middle of it, not just when the file fails to
/// parse — a half-restored device is the one broken state the ledger cannot
/// detect (ADR-0021 §6).
///
/// App-layer wiring, not a `backup`-package use case, for the same reason as
/// [CreateBackup]: `backup` depends only on `shared_kernel`.
class RestoreBackup {
  final EventStore eventStore;
  final CatalogRepository catalog;
  final CascadeRepository cascade;
  final RateSeries rates;
  final LedgerProjections projections;
  final EventBus eventBus;
  final UnitOfWork unitOfWork;
  final BackupReader _reader;

  RestoreBackup({
    required this.eventStore,
    required this.catalog,
    required this.cascade,
    required this.rates,
    required this.projections,
    required this.eventBus,
    required this.unitOfWork,
    BackupReader reader = const BackupReader(),
  }) : _reader = reader;

  Future<RestoreBackupResult> call(String content) async {
    late final List<Account> accounts;
    late final List<Envelope> envelopes;
    late final Cascade? cascadeDoc;
    late final List<Transaction> transactions;
    late final InMemoryRateFeed rateFeed;

    try {
      final file = _reader.parse(content);
      accounts = file.accounts.map(_accountFromJson).toList();
      envelopes = file.envelopes.map(_envelopeFromJson).toList();
      cascadeDoc =
          file.cascades.isEmpty ? null : _cascadeFromJson(file.cascades.single);
      const codec = EventCodec();
      transactions = [
        for (var i = 0; i < file.events.length; i++)
          _decodeEvent(codec, file.events[i], file.eventLineNumbers[i]),
      ];
      rateFeed = InMemoryRateFeed(file.rates.map(jsonEncode).join('\n'));
    } on UnknownFormatVersion {
      throw const RestoreBackupError(
        'Este respaldo es de una versión más nueva de Cuentaria. '
        'Actualizá la app para poder restaurarlo. No se cambió nada.',
      );
    } on BackupReaderError catch (e) {
      throw RestoreBackupError(
        'No se pudo restaurar: ${e.message}. No se cambió nada.',
      );
    } catch (e) {
      throw RestoreBackupError('El archivo de respaldo no se pudo leer: $e');
    }

    // Everything that lives in the local database goes in one unit: Catalog
    // and Cascade first so the UI has names, then the events.
    final applied = <Transaction>[];
    await unitOfWork.run(() async {
      for (final account in accounts) {
        await catalog.saveAccount(account);
      }
      for (final envelope in envelopes) {
        await catalog.saveEnvelope(envelope);
      }
      if (cascadeDoc != null) {
        await cascade.save(cascadeDoc);
      }
      for (final transaction in transactions) {
        if (await eventStore.append(transaction)) applied.add(transaction);
      }
    });

    // Only after the rows are committed. Projections and the EventBus live in
    // memory and cannot be rolled back, so firing them inside the unit would
    // leave balances counting events that no longer exist on disk.
    for (final transaction in applied) {
      projections.apply(transaction);
      eventBus.publish(transaction);
    }

    // ponytail: the Rate Series lives in a separate physical database, so it
    // cannot join the unit above and there is no two-phase commit here. It is
    // written after the commit and the sync dedups by
    // `(currency, source, observedAt)`, so a failure at this point leaves
    // nothing half-done that restoring the same file again won't finish.
    await SyncRateSeriesUseCase(rateFeed, rates).sync();

    return RestoreBackupResult(eventsRestored: transactions.length);
  }

  /// Decodes one event payload, translating `EventCodec`'s errors into an
  /// [InvalidLine] naming [lineNumber] so the caller can report which line
  /// broke — `EventCodec.decode` wraps a self-balance violation (ADR-0006)
  /// as [MalformedPayload] with [MalformedPayload.cause] set to the
  /// original [UnbalancedTransaction], so that case is told apart by
  /// inspecting the cause rather than by a separate catch clause.
  static Transaction _decodeEvent(
    EventCodec codec,
    String payload,
    int lineNumber,
  ) {
    try {
      return codec.decode(payload);
    } on UnsupportedSchemaVersion {
      throw InvalidLine(
        lineNumber: lineNumber,
        reason: 'usa una versión de datos más nueva que esta app',
      );
    } on MalformedPayload catch (e) {
      throw InvalidLine(
        lineNumber: lineNumber,
        reason:
            e.cause is UnbalancedTransaction
                ? 'no cumple el balance contable'
                : 'no se pudo interpretar',
      );
    }
  }

  static Account _accountFromJson(Map<String, dynamic> json) => Account(
    id: AccountId(json['id'] as String),
    name: json['name'] as String,
    nativeCurrency: CurrencyCode(json['nativeCurrency'] as String),
    provider: json['provider'] as String?,
    isArchived: json['isArchived'] as bool,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    meta: json['meta'] as Map<String, dynamic>?,
  );

  static Envelope _envelopeFromJson(Map<String, dynamic> json) => Envelope(
    id: EnvelopeId(json['id'] as String),
    name: json['name'] as String,
    role: EnvelopeRole.values.byName(json['role'] as String),
    isArchived: json['isArchived'] as bool,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    meta: json['meta'] as Map<String, dynamic>?,
  );

  static Cascade _cascadeFromJson(Map<String, dynamic> json) => Cascade(
    steps: CascadeCodec.stepsFromJson(
      (json['steps'] as List).cast<Map<String, dynamic>>(),
    ),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}
