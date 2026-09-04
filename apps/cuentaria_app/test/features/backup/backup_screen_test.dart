import 'package:contabilidad/infrastructure/cascade/in_memory_cascade_repository.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:cuentaria_app/features/backup/application/backup_providers.dart';
import 'package:cuentaria_app/features/backup/application/create_backup.dart';
import 'package:cuentaria_app/features/backup/application/create_spreadsheet_export.dart';
import 'package:cuentaria_app/features/backup/application/system_share.dart';
import 'package:cuentaria_app/features/backup/ui/screens/backup_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_series.dart';

class _FakeSystemShare implements SystemShare {
  bool called = false;
  String? sharedFilename;
  bool result;

  _FakeSystemShare({this.result = true});

  @override
  Future<bool> shareFile({
    required String filename,
    required String content,
    Rect? sharePositionOrigin,
  }) async {
    called = true;
    sharedFilename = filename;
    return result;
  }
}

final _createBackupOverride = createBackupProvider.overrideWith(
  (ref) async => CreateBackup(
    eventStore: InMemoryEventStore(),
    catalog: InMemoryCatalogRepository(),
    cascade: InMemoryCascadeRepository(),
    rates: InMemoryRateSeries(),
    now: () => DateTime.utc(2026, 8, 7),
  ),
);

final _createSpreadsheetExportOverride = createSpreadsheetExportProvider
    .overrideWith(
      (ref) async => CreateSpreadsheetExport(
        eventStore: InMemoryEventStore(),
        catalog: InMemoryCatalogRepository(),
        now: () => DateTime.utc(2026, 8, 7),
      ),
    );

Future<void> _pumpBackupScreen(
  WidgetTester tester, {
  required SystemShare share,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isWebProvider.overrideWithValue(true),
        _createBackupOverride,
        _createSpreadsheetExportOverride,
        systemShareProvider.overrideWithValue(share),
      ],
      child: const MaterialApp(home: BackupScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows "Último respaldo: nunca" with no prior backup', (
    tester,
  ) async {
    await _pumpBackupScreen(tester, share: _FakeSystemShare());

    expect(find.text('Último respaldo: nunca'), findsOneWidget);
  });

  testWidgets('tapping Respaldar shows the plaintext warning first', (
    tester,
  ) async {
    await _pumpBackupScreen(tester, share: _FakeSystemShare());

    await tester.tap(find.widgetWithText(ElevatedButton, 'Respaldar'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Este archivo lleva tus finanzas en texto legible. '
        'Mándalo solo a donde tú lo controles.',
      ),
      findsOneWidget,
    );

    // The share sheet has not been invoked yet — only the warning has.
    final share = tester.widget<ElevatedButton>(
      find.byKey(const Key('proceedShareWarningAction')),
    );
    expect(share, isNotNull);
  });

  testWidgets('proceeding past the warning calls the share plugin', (
    tester,
  ) async {
    final share = _FakeSystemShare();
    await _pumpBackupScreen(tester, share: share);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Respaldar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proceedShareWarningAction')));
    await tester.pumpAndSettle();

    expect(share.called, isTrue);
    expect(share.sharedFilename, equals('cuentaria-2026-08-07.ndjson'));
  });

  testWidgets('cancelling the warning never calls the share plugin', (
    tester,
  ) async {
    final share = _FakeSystemShare();
    await _pumpBackupScreen(tester, share: share);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Respaldar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancelShareWarningAction')));
    await tester.pumpAndSettle();

    expect(share.called, isFalse);
    expect(find.text('Último respaldo: nunca'), findsOneWidget);
  });

  testWidgets('after a completed share, shows "hace un momento"', (
    tester,
  ) async {
    final share = _FakeSystemShare(result: true);
    await _pumpBackupScreen(tester, share: share);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Respaldar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proceedShareWarningAction')));
    await tester.pumpAndSettle();

    expect(find.text('Último respaldo: hace un momento'), findsOneWidget);
  });

  testWidgets('when the user does not complete the share, stays "nunca"', (
    tester,
  ) async {
    final share = _FakeSystemShare(result: false);
    await _pumpBackupScreen(tester, share: share);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Respaldar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proceedShareWarningAction')));
    await tester.pumpAndSettle();

    expect(share.called, isTrue);
    expect(find.text('Último respaldo: nunca'), findsOneWidget);
  });

  testWidgets('Respaldar and Exportar a Excel are two separate buttons', (
    tester,
  ) async {
    await _pumpBackupScreen(tester, share: _FakeSystemShare());

    expect(find.widgetWithText(ElevatedButton, 'Respaldar'), findsOneWidget);
    expect(
      find.widgetWithText(ElevatedButton, 'Exportar a Excel'),
      findsOneWidget,
    );
  });

  testWidgets('tapping Exportar a Excel shows the plaintext warning first', (
    tester,
  ) async {
    await _pumpBackupScreen(tester, share: _FakeSystemShare());

    await tester.tap(find.widgetWithText(ElevatedButton, 'Exportar a Excel'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Este archivo lleva tus finanzas en texto legible. '
        'Mándalo solo a donde tú lo controles.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('proceeding past the warning shares the .csv file', (
    tester,
  ) async {
    final share = _FakeSystemShare();
    await _pumpBackupScreen(tester, share: share);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Exportar a Excel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proceedShareWarningAction')));
    await tester.pumpAndSettle();

    expect(share.called, isTrue);
    expect(share.sharedFilename, equals('cuentaria-2026-08-07.csv'));
  });

  testWidgets('Respaldar shares only the .ndjson file, never the .csv', (
    tester,
  ) async {
    final share = _FakeSystemShare();
    await _pumpBackupScreen(tester, share: share);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Respaldar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proceedShareWarningAction')));
    await tester.pumpAndSettle();

    expect(share.sharedFilename, equals('cuentaria-2026-08-07.ndjson'));
  });

  testWidgets(
    'shows the compact Cloud Copy status label next to Último respaldo',
    (tester) async {
      await _pumpBackupScreen(tester, share: _FakeSystemShare());

      expect(find.text('Copia en Drive: nunca'), findsOneWidget);
    },
  );
}
