import 'package:contabilidad/infrastructure/cascade/in_memory_cascade_repository.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/infrastructure/in_memory_unit_of_work.dart';
import 'package:cuentaria_app/features/backup/application/backup_providers.dart';
import 'package:cuentaria_app/features/backup/application/restore_backup.dart';
import 'package:cuentaria_app/features/backup/application/system_file_picker.dart';
import 'package:cuentaria_app/features/backup/ui/widgets/restore_backup_button.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_series.dart';

class _FakeSystemFilePicker implements SystemFilePicker {
  final String? content;

  _FakeSystemFilePicker({this.content});

  @override
  Future<String?> pickFile() async => content;
}

final _restoreBackupOverride = restoreBackupProvider.overrideWith(
  (ref) async => RestoreBackup(
    eventStore: InMemoryEventStore(),
    catalog: InMemoryCatalogRepository(),
    cascade: InMemoryCascadeRepository(),
    rates: InMemoryRateSeries(),
    projections: InMemoryLedgerProjections(),
    eventBus: SyncEventBus(),
    unitOfWork: const InMemoryUnitOfWork(),
  ),
);

Future<void> _pumpButton(
  WidgetTester tester, {
  required SystemFilePicker picker,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isWebProvider.overrideWithValue(true),
        _restoreBackupOverride,
        systemFilePickerProvider.overrideWithValue(picker),
      ],
      child: const MaterialApp(home: Scaffold(body: RestoreBackupButton())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the restore button is visible', (tester) async {
    await _pumpButton(tester, picker: _FakeSystemFilePicker());

    expect(find.byKey(const Key('restoreBackupButton')), findsOneWidget);
  });

  testWidgets('cancelling the file picker restores nothing', (tester) async {
    await _pumpButton(tester, picker: _FakeSystemFilePicker(content: null));

    await tester.tap(find.byKey(const Key('restoreBackupButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('restoreCountMessage')), findsNothing);
  });

  testWidgets('picking a backup file shows the restored movement count', (
    tester,
  ) async {
    const backupContent =
        '{"kind":"header","format":1,"app":"cuentaria",'
        '"exportedAt":"2026-08-07T00:00:00.000Z",'
        '"counts":{"event":1,"account":0,"envelope":0,"cascade":0,"rate":0}}\n'
        '{"kind":"event","data":{"device_id":"d","event_id":"evt-1",'
        '"occurred_at":"2026-08-01T00:00:00.000Z",'
        '"postings":[{"amount_native":"1000","amount_usd":"1000",'
        '"currency":"USD","target":{"dimension":"account","id":"acc-1"}},'
        '{"amount_native":"1000","amount_usd":"1000","currency":"USD",'
        '"target":{"dimension":"envelope","id":"env-1"}}],'
        '"recorded_at":"2026-08-01T00:01:00.000Z","schema_version":1,'
        '"type":"Income"}}';

    await _pumpButton(
      tester,
      picker: _FakeSystemFilePicker(content: backupContent),
    );

    await tester.tap(find.byKey(const Key('restoreBackupButton')));
    await tester.pumpAndSettle();

    expect(find.text('Se restauraron 1 movimientos'), findsOneWidget);
  });

  testWidgets('an unreadable file shows a generic error, not a crash', (
    tester,
  ) async {
    await _pumpButton(
      tester,
      picker: _FakeSystemFilePicker(content: 'not a backup file'),
    );

    await tester.tap(find.byKey(const Key('restoreBackupButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('restoreErrorText')), findsOneWidget);
    expect(find.byKey(const Key('restoreCountMessage')), findsNothing);
  });
}
