import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../cloud_copy/application/cloud_sync_status_notifier.dart';
import '../../../cloud_copy/ui/widgets/cloud_status_label.dart';
import '../../application/backup_providers.dart';
import '../../application/system_share.dart';
import '../widgets/restore_backup_button.dart';

const _shareWarning =
    'Este archivo lleva tus finanzas en texto legible. '
    'Mándalo solo a donde tú lo controles.';

String _lastBackupLabel(DateTime? lastBackup) {
  if (lastBackup == null) return 'Último respaldo: nunca';

  final diff = DateTime.now().toUtc().difference(lastBackup.toUtc());
  if (diff.inMinutes < 1) return 'Último respaldo: hace un momento';
  if (diff.inHours < 1) {
    return 'Último respaldo: hace ${diff.inMinutes} min';
  }
  if (diff.inDays < 1) return 'Último respaldo: hace ${diff.inHours} h';
  return 'Último respaldo: hace ${diff.inDays} día${diff.inDays == 1 ? '' : 's'}';
}

/// Backup screen (#192/#195, ADR-0021): shows the age of the last share and
/// two separate actions — Respaldar (`.ndjson`) and Exportar a Excel
/// (`.csv`, ADR-0021 §8). Separate on purpose: a single button would attach
/// a redundant CSV to every backup and leave two same-day files to guess
/// between when restoring. The plaintext warning appears only when actually
/// sharing (§3) — not on entry, which would just be noise on every visit.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  final _respaldarButtonKey = GlobalKey();
  final _exportarExcelButtonKey = GlobalKey();
  bool _isSharingBackup = false;
  bool _isSharingCsv = false;
  String? _backupError;
  String? _csvError;

  Future<bool> _confirmShareWarning() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            content: const Text(_shareWarning, key: Key('shareWarningText')),
            actions: [
              TextButton(
                key: const Key('cancelShareWarningAction'),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                key: const Key('proceedShareWarningAction'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Continuar'),
              ),
            ],
          ),
    );
    return proceed ?? false;
  }

  Rect? _originOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _onRespaldar() async {
    if (!await _confirmShareWarning()) return;
    if (!mounted) return;

    setState(() {
      _isSharingBackup = true;
      _backupError = null;
    });

    try {
      final createBackup = await ref.read(createBackupProvider.future);
      final result = await createBackup();

      final SystemShare share = ref.read(systemShareProvider);
      final completed = await share.shareFile(
        filename: result.filename,
        content: result.content,
        sharePositionOrigin: _originOf(_respaldarButtonKey),
      );

      if (completed) {
        await ref
            .read(lastBackupDateProvider.notifier)
            .stamp(DateTime.now().toUtc());
      }
    } catch (e) {
      setState(() => _backupError = e.toString());
    } finally {
      if (mounted) setState(() => _isSharingBackup = false);
    }
  }

  Future<void> _onExportarExcel() async {
    if (!await _confirmShareWarning()) return;
    if (!mounted) return;

    setState(() {
      _isSharingCsv = true;
      _csvError = null;
    });

    try {
      final createExport = await ref.read(
        createSpreadsheetExportProvider.future,
      );
      final result = await createExport();

      final SystemShare share = ref.read(systemShareProvider);
      await share.shareFile(
        filename: result.filename,
        content: result.content,
        sharePositionOrigin: _originOf(_exportarExcelButtonKey),
      );
    } catch (e) {
      setState(() => _csvError = e.toString());
    } finally {
      if (mounted) setState(() => _isSharingCsv = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastBackupAsync = ref.watch(lastBackupDateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Respaldo')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                children: [
                  lastBackupAsync.when(
                    data:
                        (lastBackup) => Text(
                          _lastBackupLabel(lastBackup),
                          key: const Key('lastBackupLabel'),
                        ),
                    loading: () => const CircularProgressIndicator(),
                    error:
                        (error, stackTrace) =>
                            Text('No se pudo cargar: $error'),
                  ),
                  CloudStatusLabel(status: ref.watch(cloudSyncStatusProvider)),
                ],
              ),
              const SizedBox(height: 24),
              if (_backupError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _backupError!,
                    key: const Key('backupErrorText'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_csvError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _csvError!,
                    key: const Key('csvErrorText'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ElevatedButton(
                key: _respaldarButtonKey,
                onPressed: _isSharingBackup ? null : _onRespaldar,
                child: const Text('Respaldar'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                key: _exportarExcelButtonKey,
                onPressed: _isSharingCsv ? null : _onExportarExcel,
                child: const Text('Exportar a Excel'),
              ),
              // The two ways data leaves the phone first, then the one that
              // brings it back — a wider gap so it does not read as a third
              // flavour of export.
              const SizedBox(height: 16),
              const RestoreBackupButton(),
            ],
          ),
        ),
      ),
    );
  }
}
