import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

/// Opens the tasas rate-observations database file on native platforms —
/// plain SQLite, unencrypted (ADR-0016 §3): market rates are public data, so
/// this store never touches SQLCipher/key plumbing, unlike the ledger's
/// [openAppDatabase].
Future<QueryExecutor> openTasasDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final dbFile = File('${dir.path}${Platform.pathSeparator}tasas.db');
  return NativeDatabase(dbFile);
}
