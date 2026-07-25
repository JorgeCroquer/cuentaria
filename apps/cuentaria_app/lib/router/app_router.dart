import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../features/distribution/ui/screens/distribute_screen.dart';
import '../features/envelopes/ui/screens/envelope_edit_screen.dart';
import '../features/envelopes/ui/screens/envelopes_list_screen.dart';
import '../features/patrimonio/ui/screens/patrimonio_screen.dart';
import '../ui/ledger_screen.dart';
import '../ui/shell/patrimonio_shell.dart';
import '../ui/splash_screen.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/distribute',
        builder: (context, state) => const DistributeScreen(),
      ),
      GoRoute(
        path: '/envelopes',
        builder: (context, state) => const EnvelopesListScreen(),
      ),
      GoRoute(
        path: '/envelopes/new',
        builder: (context, state) => const EnvelopeEditScreen(),
      ),
      GoRoute(
        path: '/envelopes/:id/edit',
        builder:
            (context, state) => EnvelopeEditScreen(
              envelopeId: EnvelopeId(state.pathParameters['id']!),
            ),
      ),
      StatefulShellRoute.indexedStack(
        builder:
            (context, state, navigationShell) => SplashScreen(
              child: PatrimonioShell(navigationShell: navigationShell),
            ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const PatrimonioScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ledger',
                builder: (context, state) => const LedgerScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
