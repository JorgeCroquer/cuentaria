import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../features/accounts/ui/screens/accounts_screen.dart';
import '../features/backup/ui/screens/backup_screen.dart';
import '../features/distribution/ui/screens/cascade_editor_screen.dart';
import '../features/distribution/ui/screens/distribute_screen.dart';
import '../features/envelopes/ui/screens/envelope_edit_screen.dart';
import '../features/envelopes/ui/screens/envelopes_list_screen.dart';
import '../features/patrimonio/ui/screens/patrimonio_screen.dart';
import '../ui/screens/movements/movement_detail_screen.dart';
import '../ui/screens/movements/movements_screen.dart';
import '../ui/shell/patrimonio_shell.dart';
import '../ui/splash_screen.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/distribute',
        builder: (context, state) {
          final source =
              state.uri.queryParameters['source'] == 'apertura'
                  ? EnvelopeRole.opening
                  : EnvelopeRole.stage;
          return DistributeScreen(source: source);
        },
      ),
      GoRoute(
        path: '/distribute/edit',
        builder: (context, state) => const CascadeEditorScreen(),
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
      GoRoute(
        path: '/accounts',
        builder: (context, state) => const AccountsScreen(),
      ),
      GoRoute(
        path: '/backup',
        builder: (context, state) => const BackupScreen(),
      ),
      GoRoute(
        path: '/movements/:id',
        builder:
            (context, state) => MovementDetailScreen(
              eventId: EventId(state.pathParameters['id']!),
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
                path: '/movements',
                builder: (context, state) => const MovementsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
