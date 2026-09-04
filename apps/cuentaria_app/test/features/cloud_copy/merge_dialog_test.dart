import 'package:cuentaria_app/features/cloud_copy/ui/widgets/merge_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A holder so the test can read the [showDialog] result after settling —
/// the `await` inside the button's callback resolves asynchronously.
class _ResultHolder {
  bool? value;
}

Future<void> _pumpAndOpen(WidgetTester tester, _ResultHolder holder) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder:
            (context) => ElevatedButton(
              onPressed: () async {
                holder.value = await showDialog<bool>(
                  context: context,
                  builder: (context) => const MergeDialog(),
                );
              },
              child: const Text('open'),
            ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the literal merge warning text', (tester) async {
    await _pumpAndOpen(tester, _ResultHolder());

    expect(
      find.text(
        'Este aparato ya tiene movimientos. Se van a juntar con los de tu '
        'nube; si creaste las mismas cuentas en los dos, vas a verlas '
        'repetidas.',
      ),
      findsOneWidget,
    );
    expect(find.text('Juntar'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
  });

  testWidgets('Juntar pops true', (tester) async {
    final holder = _ResultHolder();
    await _pumpAndOpen(tester, holder);

    await tester.tap(find.byKey(const Key('confirmMergeButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mergeDialog')), findsNothing);
    expect(holder.value, isTrue);
  });

  testWidgets('Cancelar pops false', (tester) async {
    final holder = _ResultHolder();
    await _pumpAndOpen(tester, holder);

    await tester.tap(find.byKey(const Key('cancelMergeButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mergeDialog')), findsNothing);
    expect(holder.value, isFalse);
  });
}
