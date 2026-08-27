import 'package:flutter/material.dart';

/// The "se van a juntar" warning (issue #226, ADR-0023 §6): shown once,
/// before the first pull, when this device already has events and the cloud
/// folder already has another device's file. Pops `true` for **Juntar**
/// (proceed with the merge) or `false` for **Cancelar** (stay disconnected)
/// — Cuentaria never fuses Accounts (ADR-0002), it only appends both
/// histories.
class MergeDialog extends StatelessWidget {
  const MergeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('mergeDialog'),
      content: const Text(
        'Este aparato ya tiene movimientos. Se van a juntar con los de tu '
        'nube; si creaste las mismas cuentas en los dos, vas a verlas '
        'repetidas.',
      ),
      actions: [
        TextButton(
          key: const Key('cancelMergeButton'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          key: const Key('confirmMergeButton'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Juntar'),
        ),
      ],
    );
  }
}
