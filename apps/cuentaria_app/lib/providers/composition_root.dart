import 'dart:io';

import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/domain/ports/event_store.dart';
import 'package:contabilidad/domain/ports/ledger_projections.dart';
import 'package:contabilidad/infrastructure/catalog/drift_catalog_repository.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/drift_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../infrastructure/persistence/encrypted_db_executor.dart';
import '../infrastructure/persistence/encryption_key_provider.dart';
import '../infrastructure/persistence/secure_key_store.dart';

final eventBusProvider = Provider<EventBus>((ref) {
  final eventBus = SyncEventBus();
  ref.onDispose(eventBus.dispose);
  return eventBus;
});

/// True on web, which has no durable, plaintext-free local storage: selects
/// the in-memory (ephemeral) adapters below instead of Drift+SQLCipher.
final isWebProvider = Provider<bool>((ref) => kIsWeb);

final encryptionKeyProvider = FutureProvider<List<int>>((ref) {
  return EncryptionKeyProvider(const FlutterSecureKeyStore()).getOrCreateKey();
});

/// Opens the encrypted local database. Only resolved on native platforms —
/// see [isWebProvider].
final databaseProvider = FutureProvider<CuentariaDatabase>((ref) async {
  final key = await ref.watch(encryptionKeyProvider.future);
  final dir = await getApplicationDocumentsDirectory();
  final dbFile = File('${dir.path}${Platform.pathSeparator}cuentaria.db');
  return CuentariaDatabase(openEncryptedDatabase(dbFile, key));
});

final eventStoreProvider = FutureProvider<EventStore>((ref) async {
  if (ref.watch(isWebProvider)) {
    return InMemoryEventStore();
  }
  final db = await ref.watch(databaseProvider.future);
  return DriftEventStore(db);
});

final catalogRepositoryProvider = FutureProvider<CatalogRepository>((
  ref,
) async {
  if (ref.watch(isWebProvider)) {
    return InMemoryCatalogRepository();
  }
  final db = await ref.watch(databaseProvider.future);
  final repository = DriftCatalogRepository(db);
  await repository.hydrate();
  return repository;
});

final ledgerProjectionsProvider = Provider<LedgerProjections>((ref) {
  return InMemoryLedgerProjections();
});
