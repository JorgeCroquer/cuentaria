import 'package:cuentaria_app/features/cloud_copy/ui/widgets/account_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('disconnected shows "Conectar mi Google Drive"', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccountButton(
          isConnected: false,
          accountName: null,
          onConnect: () {},
          onDisconnect: () {},
        ),
      ),
    );

    expect(find.text('Conectar mi Google Drive'), findsOneWidget);
    expect(find.text('Desconectar'), findsNothing);
  });

  testWidgets('connected shows "Desconectar" and the account name', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccountButton(
          isConnected: true,
          accountName: 'cuenta de prueba',
          onConnect: () {},
          onDisconnect: () {},
        ),
      ),
    );

    expect(find.text('Desconectar'), findsOneWidget);
    expect(find.text('cuenta de prueba'), findsOneWidget);
    expect(find.text('Conectar mi Google Drive'), findsNothing);
  });

  testWidgets('tapping Conectar mi Google Drive calls onConnect', (
    tester,
  ) async {
    var connected = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountButton(
          isConnected: false,
          accountName: null,
          onConnect: () => connected = true,
          onDisconnect: () {},
        ),
      ),
    );

    await tester.tap(find.text('Conectar mi Google Drive'));

    expect(connected, isTrue);
  });

  testWidgets('tapping Desconectar calls onDisconnect', (tester) async {
    var disconnected = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountButton(
          isConnected: true,
          accountName: 'cuenta de prueba',
          onConnect: () {},
          onDisconnect: () => disconnected = true,
        ),
      ),
    );

    await tester.tap(find.text('Desconectar'));

    expect(disconnected, isTrue);
  });
}
