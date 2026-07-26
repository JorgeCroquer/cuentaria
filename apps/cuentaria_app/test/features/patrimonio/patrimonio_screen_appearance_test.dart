import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/envelope_appearance.dart';
import 'package:cuentaria_app/features/patrimonio/ui/screens/patrimonio_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/ui/theme/app_icons.dart';
import 'package:cuentaria_app/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  testWidgets('renders a user envelope\'s chosen icon and color (#95)', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);

    final catalog = await container.read(catalogRepositoryProvider.future);
    await catalog.saveAccount(
      Account(
        id: AccountId('test-acc'),
        name: 'Test Account',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime.now(),
      ),
    );
    final mercado = EnvelopeId('mercado');
    await catalog.saveEnvelope(
      Envelope(
        id: mercado,
        name: 'Mercado',
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: DateTime.now(),
      ).withAppearance(
        const EnvelopeAppearance(iconId: 'shopping_cart', colorIndex: 3),
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: appLightTheme(),
          home: const PatrimonioScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final icon = tester.widget<Icon>(
      find.byKey(const Key('envelopeIcon_mercado')),
    );
    expect(icon.icon, AppIcons.catalog['shopping_cart']);
    expect(icon.color, AppColors.palette[3]);
  });
}
