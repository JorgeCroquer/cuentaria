import 'package:cuentaria_app/features/cloud_copy/ui/widgets/transparency_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the literal transparency text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TransparencySection())),
    );

    expect(
      find.text(
        'Cuentaria guarda una copia de tus datos en TU Google Drive, en '
        'una carpeta que solo esta app ve. No tenemos servidor: no vemos, '
        'no guardamos y no podemos recuperar tus datos.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows a tappable privacy-policy link', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TransparencySection())),
    );

    expect(find.byKey(const Key('privacyPolicyLink')), findsOneWidget);
    expect(find.text('Política de privacidad'), findsOneWidget);
  });

  testWidgets('tapping the link shows the same text again', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TransparencySection())),
    );

    await tester.tap(find.byKey(const Key('privacyPolicyLink')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Cuentaria guarda una copia de tus datos en TU Google Drive, en '
        'una carpeta que solo esta app ve. No tenemos servidor: no vemos, '
        'no guardamos y no podemos recuperar tus datos.',
      ),
      findsWidgets,
    );
  });
}
