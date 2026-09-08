import 'dart:ffi';
import 'dart:io';

import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/merge_consent_provider.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/open.dart';
import 'package:test/test.dart';

void _ensureSqlite3() {
  if (!Platform.isLinux) return;
  open.overrideForAll(() {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } catch (_) {
      // ignore: empty_catches
    }
    return DynamicLibrary.open('libsqlite3.so.0');
  });
}

void main() {
  setUpAll(_ensureSqlite3);

  late CuentariaDatabase db;
  late MergeConsentProvider provider;

  setUp(() {
    db = CuentariaDatabase(NativeDatabase.memory());
    provider = MergeConsentProvider(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('returns false before any consent has ever been set', () async {
    expect(await provider.hasConsent(), isFalse);
  });

  test('returns true after setConsent(true)', () async {
    await provider.setConsent(true);

    expect(await provider.hasConsent(), isTrue);
  });

  test('setConsent(false) after setConsent(true) reverts to false', () async {
    await provider.setConsent(true);
    await provider.setConsent(false);

    expect(await provider.hasConsent(), isFalse);
  });

  test('does not appear among other app_meta keys, e.g. device_id', () async {
    await provider.setConsent(true);

    final rows = await db.select(db.appMeta).get();
    expect(rows, hasLength(1));
    expect(rows.single.key, equals('merge_consented'));
  });
}
