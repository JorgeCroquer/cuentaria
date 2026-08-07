import 'package:contabilidad/infrastructure/database/last_backup_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/composition_root.dart';
import '../../../providers/tasas_providers.dart';
import 'create_backup.dart';
import 'restore_backup.dart';
import 'system_file_picker.dart';
import 'system_share.dart';

final createBackupProvider = FutureProvider<CreateBackup>((ref) async {
  final eventStore = await ref.watch(eventStoreProvider.future);
  final catalog = await ref.watch(catalogRepositoryProvider.future);
  final cascade = await ref.watch(cascadeRepositoryProvider.future);
  final rates = await ref.watch(rateSeriesProvider.future);
  return CreateBackup(
    eventStore: eventStore,
    catalog: catalog,
    cascade: cascade,
    rates: rates,
  );
});

final restoreBackupProvider = FutureProvider<RestoreBackup>((ref) async {
  final eventStore = await ref.watch(eventStoreProvider.future);
  final catalog = await ref.watch(catalogRepositoryProvider.future);
  final cascade = await ref.watch(cascadeRepositoryProvider.future);
  final rates = await ref.watch(rateSeriesProvider.future);
  final projections = ref.watch(ledgerProjectionsProvider);
  final eventBus = ref.watch(eventBusProvider);
  final unitOfWork = await ref.watch(unitOfWorkProvider.future);
  return RestoreBackup(
    eventStore: eventStore,
    catalog: catalog,
    cascade: cascade,
    rates: rates,
    projections: projections,
    eventBus: eventBus,
    unitOfWork: unitOfWork,
  );
});

final systemShareProvider = Provider<SystemShare>(
  (ref) => const MethodChannelSystemShare(),
);

final systemFilePickerProvider = Provider<SystemFilePicker>(
  (ref) => const MethodChannelSystemFilePicker(),
);

/// Local-only stamp of the last successful share (ADR-0021 §4/Consequence),
/// re-read from `app_meta` on native and held in memory for the session on
/// web — same ephemeral-persistence tradeoff [isWebProvider] makes
/// everywhere else, rather than pretending a share never happened.
final lastBackupDateProvider =
    AsyncNotifierProvider<LastBackupDateNotifier, DateTime?>(
      LastBackupDateNotifier.new,
    );

class LastBackupDateNotifier extends AsyncNotifier<DateTime?> {
  @override
  Future<DateTime?> build() async {
    if (ref.watch(isWebProvider)) return null;
    final db = await ref.watch(databaseProvider.future);
    return LastBackupProvider(db).getLastBackupDate();
  }

  /// Stamps [date] as the new last-backup date.
  Future<void> stamp(DateTime date) async {
    if (!ref.read(isWebProvider)) {
      final db = await ref.read(databaseProvider.future);
      await LastBackupProvider(db).setLastBackupDate(date);
    }
    state = AsyncData(date);
  }
}
