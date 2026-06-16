/// Composition root — wires platform deps into domain ports (F2, slice #45).
///
/// Boot sequence (async, Riverpod FutureProvider):
///   1. KeyProvisioner.provision() → 256-bit SQLCipher key from OS keystore.
///   2. openEncryptedDatabase(key) → encrypted QueryExecutor.
///   3. CuentariaDatabase(executor) → Drift DB (runs migrations + system seed).
///   4. DriftCatalogRepository.hydrate() → warms in-memory catalog cache.
///   5. DeviceIdProvisioner.provision() → stable device_id in app_meta.
///
/// [compositionRootProvider] resolves to [CompositionRoot] once boot completes.
/// The splash screen awaits this; the main UI watches it.
library;

import 'package:contabilidad/infrastructure/catalog/drift_catalog_repository.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/drift_event_store.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../infrastructure/device_id_provisioner.dart';
import '../infrastructure/encrypted_database_factory.dart';
import '../infrastructure/key_provisioner.dart';

/// Holds fully-initialised domain adapters for injection into feature providers.
final class CompositionRoot {
  final CuentariaDatabase database;
  final DriftEventStore eventStore;
  final DriftCatalogRepository catalogRepository;
  final String deviceId;

  const CompositionRoot({
    required this.database,
    required this.eventStore,
    required this.catalogRepository,
    required this.deviceId,
  });
}

final eventBusProvider = Provider<EventBus>((ref) {
  final eventBus = SyncEventBus();
  ref.onDispose(eventBus.dispose);
  return eventBus;
});

/// Async boot: provision key → open encrypted DB → hydrate catalog → device_id.
final compositionRootProvider = FutureProvider<CompositionRoot>((ref) async {
  // 1. Key provisioning (OS secure storage).
  const secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final provisioner = KeyProvisioner(
    FlutterSecureStorageAdapter(secureStorage),
  );
  final rawKey = await provisioner.provision();

  // 2. Encrypted executor.
  final executor = await openEncryptedDatabase(rawKey);

  // 3. Drift database (runs migrations + seeds system envelopes on first open).
  final db = CuentariaDatabase(executor);
  ref.onDispose(db.close);

  // 4. Catalog cache hydration.
  final catalog = DriftCatalogRepository(db);
  await catalog.hydrate();

  // 5. Stable device_id.
  final deviceId = await DeviceIdProvisioner(db).provision();

  return CompositionRoot(
    database: db,
    eventStore: DriftEventStore(db),
    catalogRepository: catalog,
    deviceId: deviceId,
  );
});
