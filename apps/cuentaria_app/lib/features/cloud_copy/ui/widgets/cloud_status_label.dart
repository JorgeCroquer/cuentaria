import 'package:flutter/material.dart';

import '../../application/cloud_copy_status.dart';

String _relativeTime(DateTime at) {
  final diff = DateTime.now().toUtc().difference(at.toUtc());
  if (diff.inMinutes < 1) return 'un momento';
  if (diff.inHours < 1) return '${diff.inMinutes} min';
  if (diff.inDays < 1) return '${diff.inHours} h';
  return '${diff.inDays} día${diff.inDays == 1 ? '' : 's'}';
}

/// The permanent Cloud Copy status label (issue #223, ADR-0023 §4): four
/// shapes driven by [CloudCopyStatus] — waiting on the merge gate (issue
/// #297), in progress, failed (tap to [onRetry]), or the age of the last
/// success. Reused as-is, compact, next to "Último respaldo" on the Backup
/// screen (issue #223 AC #6).
class CloudStatusLabel extends StatelessWidget {
  const CloudStatusLabel({required this.status, this.onRetry, super.key});

  final CloudCopyStatus status;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (status.waitingForMergeConsent) {
      return const Text(
        'Esperando tu decisión de juntar',
        key: Key('cloudStatusLabel'),
      );
    }
    if (status.inProgress) {
      return const Text('Copiando…', key: Key('cloudStatusLabel'));
    }
    if (status.lastError != null) {
      return GestureDetector(
        key: const Key('cloudStatusLabel'),
        onTap: onRetry,
        child: Text(
          'Falló hace ${_relativeTime(status.lastAttemptAt!)}: '
          '${status.lastError} — toca para reintentar',
        ),
      );
    }
    if (status.lastSuccessAt != null) {
      return Text(
        'Copia en Drive: hace ${_relativeTime(status.lastSuccessAt!)}',
        key: const Key('cloudStatusLabel'),
      );
    }
    return const Text('Copia en Drive: nunca', key: Key('cloudStatusLabel'));
  }
}
