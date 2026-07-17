/// Native/Android-only smoke tests for slice #45 (encrypted database + key
/// provisioning). `sqlcipher_flutter_libs` and `flutter_secure_storage` only
/// ship real implementations for Android/iOS/macOS — there is no host build
/// for the Linux sandbox, so this suite cannot run under `flutter test` or
/// CI. Run it on a real Android device/emulator:
///
///   flutter test integration_test/encryption_smoke_test.dart
library;

import 'dart:io';

import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/device_id_provider.dart';
import 'package:cuentaria_app/infrastructure/persistence/encrypted_db_executor.dart';
import 'package:cuentaria_app/infrastructure/persistence/encryption_key_provider.dart';
import 'package:cuentaria_app/infrastructure/persistence/secure_key_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final correctKey = List<int>.generate(32, (i) => i);
  final wrongKey = List<int>.generate(32, (i) => 255 - i);

  group('encryption smoke', () {
    testWidgets('correct key opens the encrypted database', (tester) async {
      final dir = await getTemporaryDirectory();
      final dbFile = File('${dir.path}/encryption_smoke_correct.db');
      if (dbFile.existsSync()) dbFile.deleteSync();

      final db = CuentariaDatabase(openEncryptedDatabase(dbFile, correctKey));
      final deviceId = await DeviceIdProvider(db).getOrCreateDeviceId();
      await db.close();

      expect(deviceId, isNotEmpty);
      expect(dbFile.existsSync(), isTrue);
    });

    testWidgets('wrong key fails to open the encrypted database', (
      tester,
    ) async {
      final dir = await getTemporaryDirectory();
      final dbFile = File('${dir.path}/encryption_smoke_wrong.db');
      if (dbFile.existsSync()) dbFile.deleteSync();

      // Create the DB with the correct key first.
      final writer = CuentariaDatabase(
        openEncryptedDatabase(dbFile, correctKey),
      );
      await DeviceIdProvider(writer).getOrCreateDeviceId();
      await writer.close();

      // Reopening with the wrong key must fail: SQLCipher rejects the file
      // as "not a database" rather than silently returning garbage.
      final reader = CuentariaDatabase(
        openEncryptedDatabase(dbFile, wrongKey),
      );
      await expectLater(
        DeviceIdProvider(reader).getOrCreateDeviceId(),
        throwsException,
      );
    });
  });

  testWidgets(
    'key is generated once and persists across provider instances '
    '(simulates app restart)',
    (tester) async {
      const store = FlutterSecureKeyStore();
      final first = await EncryptionKeyProvider(store).getOrCreateKey();
      final second = await EncryptionKeyProvider(store).getOrCreateKey();

      expect(second, first);
    },
  );
}
