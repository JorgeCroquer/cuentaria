import 'package:contabilidad/application/cascade/cascade_repository.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/domain/ports/event_store.dart';
import 'package:contabilidad/domain/ports/ledger_projections.dart';
import 'package:contabilidad/infrastructure/cascade/drift_cascade_repository.dart';
import 'package:contabilidad/infrastructure/cascade/in_memory_cascade_repository.dart';
import 'package:contabilidad/infrastructure/catalog/drift_catalog_repository.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/device_id_provider.dart';
import 'package:contabilidad/infrastructure/database/drift_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../infrastructure/persistence/encryption_key_provider.dart';
import '../infrastructure/persistence/open_app_database_stub.dart'
    if (dart.library.io) '../infrastructure/persistence/open_app_database_native.dart';
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
  return CuentariaDatabase(await openAppDatabase(key));
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
  final driftRepository = DriftCatalogRepository(db);
  await driftRepository.hydrate();
  return driftRepository;
});

final ledgerProjectionsProvider = Provider<LedgerProjections>((ref) {
  return InMemoryLedgerProjections();
});

/// The single saved cascade plan (ADR-0015 §1), read by the distribute flow
/// (C2) reachable from Patrimonio's "Sin asignar" (S2, #83).
final cascadeRepositoryProvider = FutureProvider<CascadeRepository>((
  ref,
) async {
  if (ref.watch(isWebProvider)) {
    return InMemoryCascadeRepository();
  }
  final db = await ref.watch(databaseProvider.future);
  final repository = DriftCascadeRepository(db);
  await repository.hydrate();
  return repository;
});

/// Stable per-install device id (slice #45), consumed to fill
/// [TransactionMetadata.deviceId]. Web has no durable storage for it, so it
/// falls back to a fixed label — consistent with its ephemeral persistence.
final deviceIdProvider = FutureProvider<String>((ref) async {
  if (ref.watch(isWebProvider)) {
    return 'web';
  }
  final db = await ref.watch(databaseProvider.future);
  return DeviceIdProvider(db).getOrCreateDeviceId();
});
