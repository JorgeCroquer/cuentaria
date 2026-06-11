import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryCatalogRepository', () {
    late InMemoryCatalogRepository repository;

    setUp(() {
      repository = InMemoryCatalogRepository();
    });

    test('saves and retrieves accounts with LWW', () {
      final acc1 = Account(
        id: AccountId('acc-1'),
        name: 'Initial',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime(2023, 1, 1),
      );

      repository.saveAccount(acc1);
      expect(repository.getAccount(AccountId('acc-1'))?.name, 'Initial');

      final acc2 = Account(
        id: AccountId('acc-1'),
        name: 'Newer',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime(2023, 1, 2),
      );

      repository.saveAccount(acc2);
      expect(repository.getAccount(AccountId('acc-1'))?.name, 'Newer');

      final acc3 = Account(
        id: AccountId('acc-1'),
        name: 'Older',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime(2023, 1, 1), // Older timestamp!
      );

      repository.saveAccount(acc3);
      // LWW means it should stay 'Newer'
      expect(repository.getAccount(AccountId('acc-1'))?.name, 'Newer');
    });

    test('initializes with 4 system envelopes idempotently', () {
      // Upon creation, 4 system envelopes should exist
      expect(repository.getSystemEnvelope(EnvelopeRole.stage), isNotNull);
      expect(repository.getSystemEnvelope(EnvelopeRole.diferencial), isNotNull);
      expect(repository.getSystemEnvelope(EnvelopeRole.ajustes), isNotNull);
      expect(repository.getSystemEnvelope(EnvelopeRole.apertura), isNotNull);

      // Now we rename Stage
      final stageId = repository.getSystemEnvelope(EnvelopeRole.stage);
      final stageEnv = repository.getEnvelope(stageId)!;
      
      final renamedStage = Envelope(
        id: stageEnv.id,
        name: 'Renamed Stage',
        role: stageEnv.role,
        isArchived: stageEnv.isArchived,
        updatedAt: DateTime.now().add(const Duration(days: 1)),
      );
      
      repository.saveEnvelope(renamedStage);
      expect(repository.getEnvelope(stageId)?.name, 'Renamed Stage');
    });

    test('prevents deletion of system envelopes', () {
      final stageId = repository.getSystemEnvelope(EnvelopeRole.stage);
      
      expect(() => repository.deleteEnvelope(stageId), throwsA(isA<SystemEnvelopeDeletion>()));
      
      // But we can delete a regular one
      final regular = Envelope(
        id: EnvelopeId('regular-1'),
        name: 'Regular',
        role: EnvelopeRole.ninguno,
        isArchived: false,
        updatedAt: DateTime(2023, 1, 1),
      );
      repository.saveEnvelope(regular);
      
      expect(repository.getEnvelope(EnvelopeId('regular-1')), isNotNull);
      repository.deleteEnvelope(EnvelopeId('regular-1'));
      expect(repository.getEnvelope(EnvelopeId('regular-1')), isNull);
    });
  });
}
