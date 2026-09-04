import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/cloud_copy/application/cloud_copy_providers.dart';
import 'providers/rate_sync_providers.dart';
import 'router/app_router.dart';
import 'ui/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(rateSyncTriggerProvider);
    ref.watch(cloudCopyTriggersProvider);
    final goRouter = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'Cuentaria MVP',
      theme: appLightTheme(),
      darkTheme: appDarkTheme(),
      themeMode: ThemeMode.system,
      routerConfig: goRouter,
    );
  }
}
