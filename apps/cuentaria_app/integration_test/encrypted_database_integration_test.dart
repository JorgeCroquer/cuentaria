/// Native Android integration test for encrypted database (slice #45, F2-6).
///
/// IMPORTANT: this test requires a real Android device or emulator.
/// It CANNOT run in pure Dart CI (no SQLCipher native lib, no path_provider).
///
/// Run with:
///   flutter test integration_test/encrypted_database_integration_test.dart
///
/// What is verified:
///   1. Encryption smoke: opening the DB with the CORRECT key succeeds.
///   2. Encryption smoke: opening the DB with the WRONG key fails.
///   3. device_id stability across re-opens of the same encrypted DB.
///   4. KeyProvisioner key is stable across re-provisions (OS secure storage).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:cuentaria_app/infrastructure/device_id_provisioner.dart';
import 'package:cuentaria_app/infrastructure/encrypted_database_factory.dart';
import 'package:cuentaria_app/infrastructure/key_provisioner.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Encrypted database (native Android)', () {
    late File dbFile;

    // Deterministic test key (32 bytes = 256 bits).
    // Real app uses Random.secure() via KeyProvisioner.
    final correctKey = Uint8List.fromList(List.generate(32, (i) => i + 1));

    setUpAll(() async {
      await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
      open.overrideFor(OperatingSystem.android, openCipherOnAndroid);

      final dir = await getApplicationDocumentsDirectory();
      dbFile = File(p.join(dir.path, 'integration_test_cuentaria.db'));
      if (await dbFile.exists()) await dbFile.delete();
    });

    tearDownAll(() async {
      if (await dbFile.exists()) await dbFile.delete();
    });

    testWidgets('correct key opens encrypted DB and runs migrations', (
      tester,
    ) async {
      final hexKey = toHexKey(correctKey);
      final executor = NativeDatabase(
        dbFile,
        setup: (db) => db.execute("PRAGMA key = \"x'$hexKey'\";"),
      );

      final db = CuentariaDatabase(executor);
      final envelopes = await db.select(db.envelopes).get();
      expect(
        envelopes.length,
        greaterThanOrEqualTo(4),
        reason: 'system envelopes seeded on first open',
      );
      await db.close();
    });

    testWidgets('wrong key fails to open encrypted DB', (tester) async {
      // Seed: write the file with correctKey so the wrong-key attempt has
      // something real to fail against. Isolated — does not depend on prior test.
      final seedHex = toHexKey(correctKey);
      final seedExecutor = NativeDatabase(
        dbFile,
        setup: (db) => db.execute("PRAGMA key = \"x'$seedHex'\";"),
      );
      final seedDb = CuentariaDatabase(seedExecutor);
      await seedDb.select(seedDb.envelopes).get(); // force open + migrate
      await seedDb.close();

      // Now open with wrong key — must throw.
      final wrongKey = Uint8List(32); // all zeros ≠ correctKey
      final hexKey = toHexKey(wrongKey);
      final executor = NativeDatabase(
        dbFile,
        setup: (db) => db.execute("PRAGMA key = \"x'$hexKey'\";"),
      );
      final db = CuentariaDatabase(executor);
      await expectLater(
        db.select(db.envelopes).get(),
        throwsA(anything),
        reason: 'wrong key must not open the encrypted file',
      );
      await db.close().catchError((_) {});
    });

    testWidgets(
      'device_id is stable across re-opens of the same encrypted DB',
      (tester) async {
        final hexKey = toHexKey(correctKey);

        Future<String> openAndGetDeviceId() async {
          final executor = NativeDatabase(
            dbFile,
            setup: (db) => db.execute("PRAGMA key = \"x'$hexKey'\";"),
          );
          final db = CuentariaDatabase(executor);
          final id = await DeviceIdProvisioner(db).provision();
          await db.close();
          return id;
        }

        final id1 = await openAndGetDeviceId();
        final id2 = await openAndGetDeviceId();
        expect(
          id1,
          equals(id2),
          reason: 'device_id must be stable across restarts',
        );
      },
    );

    testWidgets('KeyProvisioner key is stable across re-provisions', (
      tester,
    ) async {
      const secureStorage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      // Clean slate.
      await secureStorage.delete(key: 'cuentaria.db.key');

      final storage = FlutterSecureStorageAdapter(secureStorage);
      final key1 = await KeyProvisioner(storage).provision();
      final key2 = await KeyProvisioner(storage).provision();

      expect(key1, equals(key2), reason: 'key must survive re-provision');
      expect(key1.length, 32, reason: '256-bit key');

      await secureStorage.delete(key: 'cuentaria.db.key');
    });
  });
}
