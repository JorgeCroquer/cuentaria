import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/composition_root.dart';

/// Persistent warning shown when running on web (#122): web has no durable,
/// plaintext-free local storage, so all data is lost on reload without
/// notice. See [isWebProvider].
class EphemeralModeBanner extends ConsumerWidget {
  const EphemeralModeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isWebProvider)) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('ephemeralModeWarning'),
      width: double.infinity,
      color: colorScheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        'Modo efímero: en web los datos no se guardan',
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colorScheme.onTertiaryContainer),
      ),
    );
  }
}
