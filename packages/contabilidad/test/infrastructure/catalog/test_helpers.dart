/// Shared test helpers for catalog infrastructure tests.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/open.dart';

/// On Linux/WSL, `libsqlite3.so` (unversioned symlink) may be absent.
/// Falls back to the versioned `.so.0` shipped by Debian-like systems.
void ensureSqlite3() {
  if (!Platform.isLinux) return;
  open.overrideForAll(() {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } catch (_) {}
    return DynamicLibrary.open('libsqlite3.so.0');
  });
}

/// Opens an in-memory [CuentariaDatabase] for tests.
CuentariaDatabase openTestDb() {
  ensureSqlite3();
  return CuentariaDatabase(NativeDatabase.memory());
}
