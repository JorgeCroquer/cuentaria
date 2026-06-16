/// Opens the local Cuentaria database with SQLCipher encryption (F2-6).
///
/// Uses the raw 256-bit key from [KeyProvisioner] as a hex PRAGMA key.
/// The [QueryExecutor] returned here is injected into [CuentariaDatabase],
/// keeping the Drift adapters Flutter-free.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

/// Opens the encrypted SQLCipher database at the app documents path.
///
/// Must be called after [applyWorkaroundToOpenSqlCipherOnOldAndroidVersions]
/// on Android. The returned [QueryExecutor] is injected into
/// [CuentariaDatabase] at the composition root.
Future<QueryExecutor> openEncryptedDatabase(Uint8List rawKey) async {
  await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();

  open.overrideFor(OperatingSystem.android, openCipherOnAndroid);

  final dir = await getApplicationDocumentsDirectory();
  final dbFile = File(p.join(dir.path, 'cuentaria.db'));

  final hexKey = _toHexKey(rawKey);

  return NativeDatabase(
    dbFile,
    setup: (db) {
      db.execute("PRAGMA key = \"x'$hexKey'\";");
    },
  );
}

/// Converts raw key bytes to SQLCipher hex literal (without 0x prefix).
String _toHexKey(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final b in bytes) {
    buffer.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
