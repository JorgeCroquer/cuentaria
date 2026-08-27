import 'package:cuentaria_app/features/cloud_copy/application/cloud_copy_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts empty: nothing succeeded, failed or in progress', () {
    const status = CloudCopyStatus();

    expect(status.lastSuccessAt, isNull);
    expect(status.lastAttemptAt, isNull);
    expect(status.lastError, isNull);
    expect(status.inProgress, isFalse);
  });

  test('copyWith overrides only the given fields, keeping the rest', () {
    final base = CloudCopyStatus(
      lastSuccessAt: DateTime.utc(2026, 1, 1),
      lastAttemptAt: DateTime.utc(2026, 1, 2),
      lastError: 'algo falló',
      inProgress: true,
    );

    final updated = base.copyWith(inProgress: false);

    expect(updated.lastSuccessAt, equals(base.lastSuccessAt));
    expect(updated.lastAttemptAt, equals(base.lastAttemptAt));
    expect(updated.lastError, equals(base.lastError));
    expect(updated.inProgress, isFalse);
  });
}
