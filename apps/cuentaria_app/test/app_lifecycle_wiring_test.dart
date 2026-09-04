/// Wiring test for `CloudCopyTriggers` (issue #239, ADR-0023 §4): the class
/// itself is unit-tested in `cloud_copy_triggers_test.dart` (#224) — this
/// test only proves the app's composition root actually instantiates it.
/// Before #239, `git grep CloudCopyTriggers` in `lib/` found only the class:
/// nothing built it, so a registered movement never triggered a Drive copy.
/// If `cloudCopyTriggersProvider` stops being watched by [MyApp], both
/// assertions below fail: no app-launch write, no Transaction-triggered
/// write.
library;

import 'package:backup/domain/ports/cloud_folder.dart';
import 'package:backup/infrastructure/in_memory_cloud_folder.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:cuentaria_app/features/cloud_copy/application/cloud_copy_providers.dart';
import 'package:cuentaria_app/main.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'features/cloud_copy/cloud_copy_test_support.dart';

/// Wraps [InMemoryCloudFolder] to count [write] calls — the app-launch sync
/// and the Transaction-triggered sync each contribute one, letting the test
/// tell them apart without depending on file content.
class _CountingCloudFolder implements CloudFolder {
  _CountingCloudFolder(this._inner);

  final CloudFolder _inner;
  int writeCount = 0;

  @override
  Future<List<String>> list() => _inner.list();

  @override
  Future<String?> read(String name) => _inner.read(name);

  @override
  Future<void> write(String name, String content) async {
    writeCount++;
    await _inner.write(name, content);
  }
}

Transaction _transaction() => Transaction.create(
  metadata: TransactionMetadata(
    eventId: EventId('evt-wiring'),
    type: 'Income',
    occurredAt: DomainTimestamp(DateTime.utc(2026, 8, 1)),
    recordedAt: DomainTimestamp(DateTime.utc(2026, 8, 1)),
    deviceId: 'device-test',
    schemaVersion: 1,
  ),
  postings: [
    Posting(
      target: AccountTarget(AccountId('acc-1')),
      amountNative: Money(
        amount: BigInt.from(1000),
        currency: CurrencyCode('USD'),
      ),
      currency: CurrencyCode('USD'),
      amountUsd: 1000,
    ),
    Posting(
      target: EnvelopeTarget(EnvelopeId('env-1')),
      amountNative: Money(
        amount: BigInt.from(1000),
        currency: CurrencyCode('USD'),
      ),
      currency: CurrencyCode('USD'),
      amountUsd: 1000,
    ),
  ],
);

void main() {
  setUpAll(ensureSqlite3ForTests);

  testWidgets(
    'app launch and a registered Transaction both drive CloudCopyTriggers '
    'into the CloudFolder (#239)',
    (tester) async {
      final cloudFolder = _CountingCloudFolder(InMemoryCloudFolder());

      final container = ProviderContainer(
        overrides: [
          isWebProvider.overrideWithValue(true),
          googleDriveSessionProvider.overrideWithValue(
            FakeGoogleDriveSession('token'),
          ),
          cloudCopyUseCaseProvider.overrideWith(
            (ref) async => buildTestCloudCopyUseCase(cloudFolder: cloudFolder),
          ),
          cloudCopyDebounceProvider.overrideWithValue(Duration.zero),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MyApp()),
      );
      await tester.pumpAndSettle();

      expect(
        cloudFolder.writeCount,
        greaterThan(0),
        reason: 'app launch must fire the initial CloudCopyTriggers sync',
      );
      final writesAtLaunch = cloudFolder.writeCount;

      container.read(eventBusProvider).publish(_transaction());
      await tester.pumpAndSettle();

      expect(
        cloudFolder.writeCount,
        greaterThan(writesAtLaunch),
        reason:
            'publishing a Transaction must fire another sync once the '
            '(zeroed) debounce elapses',
      );
    },
  );
}
