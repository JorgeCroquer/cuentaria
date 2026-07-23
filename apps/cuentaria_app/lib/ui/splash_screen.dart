import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bootstrap.dart';

/// Gates [child] behind the app bootstrap sequence, showing a loading
/// indicator until startup (open → seed → hydrate → replay) completes.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(bootstrapProvider);

    return bootstrap.when(
      data: (_) => child,
      loading:
          () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
      error:
          (error, stackTrace) =>
              Scaffold(body: Center(child: Text('Error: $error'))),
    );
  }
}
