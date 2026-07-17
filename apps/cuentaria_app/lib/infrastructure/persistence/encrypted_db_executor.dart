import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

/// Opens [dbFile] as a Drift [QueryExecutor] encrypted at rest with
/// SQLCipher, using the raw [encryptionKey] bytes (slice #45).
///
/// Not yet wired into the app's composition root — see #47 for bootstrapping
/// this into [DriftEventStore] / [DriftCatalogRepository].
QueryExecutor openEncryptedDatabase(File dbFile, List<int> encryptionKey) {
  return LazyDatabase(() async {
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);

    final pragma = keyToSqlCipherPragma(encryptionKey);
    return NativeDatabase(
      dbFile,
      setup: (rawDb) => rawDb.execute("PRAGMA key = \"$pragma\";"),
    );
  });
}

/// Encodes [key] as a SQLCipher raw-key hex literal (`x'...'`), the format
/// `PRAGMA key` expects for a raw (non-passphrase-derived) 256-bit key.
String keyToSqlCipherPragma(List<int> key) {
  final hex = key
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return "x'$hex'";
}
