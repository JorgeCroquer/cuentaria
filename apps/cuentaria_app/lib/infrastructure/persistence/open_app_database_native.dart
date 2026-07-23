import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import 'encrypted_db_executor.dart';

/// Opens the encrypted app database file on native platforms.
Future<QueryExecutor> openAppDatabase(List<int> encryptionKey) async {
  final dir = await getApplicationDocumentsDirectory();
  final dbFile = File('${dir.path}${Platform.pathSeparator}cuentaria.db');
  return openEncryptedDatabase(dbFile, encryptionKey);
}
