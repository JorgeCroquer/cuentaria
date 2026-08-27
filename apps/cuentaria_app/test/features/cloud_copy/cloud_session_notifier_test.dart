import 'package:cuentaria_app/features/cloud_copy/application/cloud_session_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initial state is disconnected', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final session = container.read(cloudSessionProvider);

    expect(session.isConnected, isFalse);
    expect(session.accountName, isNull);
  });

  test('connect() marks the session connected as "cuenta de prueba"', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(cloudSessionProvider.notifier).connect();

    final session = container.read(cloudSessionProvider);
    expect(session.isConnected, isTrue);
    expect(session.accountName, equals('cuenta de prueba'));
  });

  test('disconnect() clears the session', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(cloudSessionProvider.notifier).connect();
    container.read(cloudSessionProvider.notifier).disconnect();

    final session = container.read(cloudSessionProvider);
    expect(session.isConnected, isFalse);
    expect(session.accountName, isNull);
  });
}
