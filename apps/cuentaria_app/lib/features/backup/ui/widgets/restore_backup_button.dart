import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/composition_root.dart';
import '../../application/backup_providers.dart';
import '../../application/restore_backup.dart';

/// Restore Backup button (#193, ADR-0021 §7): opens the system file picker
/// and restores whatever the user selects. Shared by the Backup screen and
/// Patrimonio's empty state — the two places a just-installed user actually
/// needs it.
class RestoreBackupButton extends ConsumerStatefulWidget {
  const RestoreBackupButton({super.key});

  @override
  ConsumerState<RestoreBackupButton> createState() =>
      _RestoreBackupButtonState();
}

class _RestoreBackupButtonState extends ConsumerState<RestoreBackupButton> {
  bool _isRestoring = false;
  String? _error;

  Future<void> _onRestore() async {
    final picker = ref.read(systemFilePickerProvider);
    final content = await picker.pickFile();
    if (content == null) return;
    if (!mounted) return;

    setState(() {
      _isRestoring = true;
      _error = null;
    });

    try {
      final restoreBackup = await ref.read(restoreBackupProvider.future);
      final result = await restoreBackup(content);

      ref.read(catalogRevisionProvider.notifier).bump();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Se restauraron ${result.eventsRestored} movimientos',
            key: const Key('restoreCountMessage'),
          ),
        ),
      );
    } on RestoreBackupError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              key: const Key('restoreErrorText'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        OutlinedButton(
          key: const Key('restoreBackupButton'),
          onPressed: _isRestoring ? null : _onRestore,
          child: const Text('Restaurar desde un archivo'),
        ),
        const SizedBox(height: 4),
        Text(
          'Elige un Archivo de Respaldo (.ndjson) guardado por ti',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
