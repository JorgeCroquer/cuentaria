import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/ui/shell/ephemeral_mode_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpBanner(WidgetTester tester, {required bool isWeb}) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(isWeb)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: EphemeralModeBanner())),
      ),
    );
  }

  testWidgets('shows the ephemeral-mode warning on web (#122)', (tester) async {
    await pumpBanner(tester, isWeb: true);

    expect(find.byKey(const Key('ephemeralModeWarning')), findsOneWidget);
    expect(
      find.text('Modo efímero: en web los datos no se guardan'),
      findsOneWidget,
    );
  });

  testWidgets('stays hidden on native platforms (#122)', (tester) async {
    await pumpBanner(tester, isWeb: false);

    expect(find.byKey(const Key('ephemeralModeWarning')), findsNothing);
  });
}
