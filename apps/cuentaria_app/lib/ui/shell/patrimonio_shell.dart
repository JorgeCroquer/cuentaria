import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/capture/ui/screens/quick_add_expense_sheet.dart';

/// Bottom-navigation shell over the app's two tabs (#79): Patrimonio and
/// Ledger. `StatefulShellRoute.indexedStack` keeps each branch's Navigator
/// (and widget state) alive across switches — tapping a destination only
/// advances [navigationShell], it never rebuilds the other branch.
///
/// The quick-add expense FAB (U1 slice 4, #97) lives here so it floats over
/// both tabs rather than being duplicated in each screen.
class PatrimonioShell extends StatelessWidget {
  const PatrimonioShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      floatingActionButton: FloatingActionButton(
        key: const Key('quickAddExpenseFab'),
        onPressed: () => showQuickAddExpenseSheet(context),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: navigationShell.goBranch,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            label: 'Patrimonio',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            label: 'Ledger',
          ),
        ],
      ),
    );
  }
}
