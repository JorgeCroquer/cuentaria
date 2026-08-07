import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/backup_providers.dart';
import '../../application/system_share.dart';

const _shareWarning =
    'Este archivo lleva tus finanzas en texto legible. '
    'Mandalo solo a donde vos controles.';

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

/// Backup screen (#192, ADR-0021): shows the age of the last share and a
/// single Respaldar action. The plaintext warning appears only when actually
/// sharing (§3) — not on entry, which would just be noise on every visit.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  final _respaldarButtonKey = GlobalKey();
  bool _isSharing = false;
  String? _error;

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

  Rect? _shareOrigin() {
    final box =
        _respaldarButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _onRespaldar() async {
    if (!await _confirmShareWarning()) return;
    if (!mounted) return;

    setState(() {
      _isSharing = true;
      _error = null;
    });

    try {
      final createBackup = await ref.read(createBackupProvider.future);
      final result = await createBackup();

      final SystemShare share = ref.read(systemShareProvider);
      final completed = await share.shareFile(
        filename: result.filename,
        content: result.content,
        sharePositionOrigin: _shareOrigin(),
      );

      if (completed) {
        await ref
            .read(lastBackupDateProvider.notifier)
            .stamp(DateTime.now().toUtc());
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSharing = false);
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
              lastBackupAsync.when(
                data:
                    (lastBackup) => Text(
                      _lastBackupLabel(lastBackup),
                      key: const Key('lastBackupLabel'),
                    ),
                loading: () => const CircularProgressIndicator(),
                error: (error, stackTrace) => Text('Error: $error'),
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    key: const Key('backupErrorText'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ElevatedButton(
                key: _respaldarButtonKey,
                onPressed: _isSharing ? null : _onRespaldar,
                child: const Text('Respaldar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
