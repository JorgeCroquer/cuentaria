import 'dart:convert';

import 'package:backup/backup.dart';
import 'package:contabilidad/application/cascade/cascade.dart';
import 'package:contabilidad/application/cascade/cascade_codec.dart';
import 'package:contabilidad/application/cascade/cascade_repository.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/ports/event_store.dart';
import 'package:contabilidad/domain/ports/ledger_projections.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/infrastructure/codec/event_codec.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/application/sync_rate_series_use_case.dart';
import 'package:tasas/domain/rate_series.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_feed.dart';

/// Thrown when a Backup File cannot be restored. Per-line diagnostics are
/// #194's job; this slice only guarantees the message is generic and that
/// nothing was written (ADR-0021 §6).
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
/// App-layer wiring, not a `backup`-package use case, for the same reason as
/// [CreateBackup]: `backup` depends only on `shared_kernel`.
class RestoreBackup {
  final EventStore eventStore;
  final CatalogRepository catalog;
  final CascadeRepository cascade;
  final RateSeries rates;
  final LedgerProjections projections;
  final EventBus eventBus;
  final BackupReader _reader;

  RestoreBackup({
    required this.eventStore,
    required this.catalog,
    required this.cascade,
    required this.rates,
    required this.projections,
    required this.eventBus,
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
      transactions = file.events.map(codec.decode).toList();
      rateFeed = InMemoryRateFeed(file.rates.map(jsonEncode).join('\n'));
    } catch (e) {
      throw RestoreBackupError('El archivo de respaldo no se pudo leer: $e');
    }

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
      final isNew = await eventStore.append(transaction);
      if (isNew) {
        projections.apply(transaction);
        eventBus.publish(transaction);
      }
    }
    await SyncRateSeriesUseCase(rateFeed, rates).sync();

    return RestoreBackupResult(eventsRestored: transactions.length);
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
