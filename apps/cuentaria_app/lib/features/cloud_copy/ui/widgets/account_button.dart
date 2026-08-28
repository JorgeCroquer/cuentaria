import 'package:flutter/material.dart';

/// Connects/disconnects the Google Drive session (issue #223, #225,
/// ADR-0023 §5): disconnecting only closes the local session — it never
/// touches local or remote data.
class AccountButton extends StatelessWidget {
  const AccountButton({
    required this.isConnected,
    required this.accountName,
    required this.onConnect,
    required this.onDisconnect,
    super.key,
  });

  final bool isConnected;
  final String? accountName;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    if (!isConnected) {
      return ElevatedButton(
        key: const Key('connectGoogleDriveButton'),
        onPressed: onConnect,
        child: const Text('Conectar mi Google Drive'),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(accountName ?? '', key: const Key('connectedAccountName')),
        const SizedBox(height: 8),
        ElevatedButton(
          key: const Key('disconnectButton'),
          onPressed: onDisconnect,
          child: const Text('Desconectar'),
        ),
      ],
    );
  }
}
