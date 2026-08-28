import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/cloud_copy_providers.dart';
import '../../application/cloud_session_notifier.dart';
import '../../application/cloud_sync_status_notifier.dart';
import '../widgets/account_button.dart';
import '../widgets/cloud_status_label.dart';
import '../widgets/merge_dialog.dart';
import '../widgets/transparency_section.dart';

/// Copia en tu nube (issue #223, ADR-0023): UI-first Cloud Copy screen,
/// wired to the real Google Drive session ([CloudSessionNotifier], issue
/// #225) and the real Cloud Copy use case behind [CloudSyncStatusNotifier]
/// — untouched since #223, only the providers behind it changed.
class CloudCopyScreen extends ConsumerWidget {
  const CloudCopyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(cloudSessionProvider);
    final status = ref.watch(cloudSyncStatusProvider);

    void onDisconnect() {
      ref.read(cloudSessionProvider.notifier).disconnect();
      ref.read(cloudSyncStatusProvider.notifier).reset();
    }

    Future<void> onConnect() async {
      ref.read(cloudSessionProvider.notifier).connect();

      final useCase = await ref.read(cloudCopyUseCaseProvider.future);
      if (await useCase.hasPendingMerge()) {
        if (!context.mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => const MergeDialog(),
        );
        if (proceed != true) {
          onDisconnect();
          return;
        }
      }

      await ref.read(cloudSyncStatusProvider.notifier).sync();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Copia en tu nube')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TransparencySection(),
            const SizedBox(height: 24),
            CloudStatusLabel(
              status: status,
              onRetry: () => ref.read(cloudSyncStatusProvider.notifier).retry(),
            ),
            const SizedBox(height: 16),
            AccountButton(
              isConnected: session.isConnected,
              accountName: session.accountName,
              onConnect: onConnect,
              onDisconnect: onDisconnect,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('copyNowButton'),
              onPressed:
                  session.isConnected
                      ? () => ref.read(cloudSyncStatusProvider.notifier).sync()
                      : null,
              child: const Text('Copiar ahora'),
            ),
          ],
        ),
      ),
    );
  }
}
