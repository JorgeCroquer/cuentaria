import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:cuentaria_app/bootstrap.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('bootstrapSequence', () {
    test('runs open->seed->hydrate->replay and leaves the app ready', () async {
      final container = ProviderContainer(
        overrides: [
          eventStoreProvider.overrideWith((ref) async => InMemoryEventStore()),
          catalogRepositoryProvider.overrideWith(
            (ref) async => InMemoryCatalogRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(bootstrapProvider.future);

      // "ready": the catalog is seeded and hydrated (system envelopes resolve)...
      final catalog = await container.read(catalogRepositoryProvider.future);
      expect(
        catalog.getSystemEnvelope(EnvelopeRole.stage),
        EnvelopeId('sys-stage'),
      );

      // ...and projections replayed the event log without error.
      final projections = container.read(ledgerProjectionsProvider);
      expect(projections.envelopeUsdBalance(EnvelopeId('sys-stage')), 0);
    });
  });

  group('platform selector', () {
    test('selects in-memory adapters on web', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final eventStore = await container.read(eventStoreProvider.future);
      final catalogRepository = await container.read(
        catalogRepositoryProvider.future,
      );

      expect(eventStore, isA<InMemoryEventStore>());
      expect(catalogRepository, isA<InMemoryCatalogRepository>());
    });
  });

  group('default account seeding', () {
    test(
      'seeds a single default USD account when the catalog is empty',
      () async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);

        final catalogRepository = await container.read(
          catalogRepositoryProvider.future,
        );

        expect(catalogRepository.accountIds, hasLength(1));
        final accountId = catalogRepository.accountIds.first;
        expect(
          catalogRepository.getAccount(accountId)?.nativeCurrency,
          CurrencyCode('USD'),
        );

        // Re-reading (cached future) must not seed a second account.
        final again = await container.read(catalogRepositoryProvider.future);
        expect(again.accountIds, hasLength(1));
      },
    );
  });
}
