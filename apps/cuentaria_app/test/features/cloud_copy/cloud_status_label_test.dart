import 'package:cuentaria_app/features/cloud_copy/application/cloud_copy_status.dart';
import 'package:cuentaria_app/features/cloud_copy/ui/widgets/cloud_status_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('never synced shows "Copia en Drive: nunca"', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CloudStatusLabel(status: CloudCopyStatus())),
    );

    expect(find.text('Copia en Drive: nunca'), findsOneWidget);
  });

  testWidgets('success shows "Copia en Drive: hace un momento"', (
    tester,
  ) async {
    final status = CloudCopyStatus(lastSuccessAt: DateTime.now().toUtc());
    await tester.pumpWidget(
      MaterialApp(home: CloudStatusLabel(status: status)),
    );

    expect(find.text('Copia en Drive: hace un momento'), findsOneWidget);
  });

  testWidgets('in progress shows "Copiando…"', (tester) async {
    const status = CloudCopyStatus(inProgress: true);
    await tester.pumpWidget(
      const MaterialApp(home: CloudStatusLabel(status: status)),
    );

    expect(find.text('Copiando…'), findsOneWidget);
  });

  testWidgets(
    'error shows "Falló hace un momento: <causa> — tocá para reintentar"',
    (tester) async {
      final status = CloudCopyStatus(
        lastAttemptAt: DateTime.now().toUtc(),
        lastError: 'sin internet',
      );
      await tester.pumpWidget(
        MaterialApp(home: CloudStatusLabel(status: status)),
      );

      expect(
        find.text('Falló hace un momento: sin internet — tocá para reintentar'),
        findsOneWidget,
      );
    },
  );

  testWidgets('tapping the error label calls onRetry', (tester) async {
    var retried = false;
    final status = CloudCopyStatus(
      lastAttemptAt: DateTime.now().toUtc(),
      lastError: 'sin internet',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudStatusLabel(status: status, onRetry: () => retried = true),
      ),
    );

    await tester.tap(find.byKey(const Key('cloudStatusLabel')));

    expect(retried, isTrue);
  });
}
