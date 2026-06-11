import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:test/test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('Envelope', () {
    test('mergeWith resolves via Last-Write-Wins based on updatedAt but preserves original role', () {
      final olderEnvelope = Envelope(
        id: EnvelopeId('env-1'),
        name: 'Older Name',
        role: EnvelopeRole.ninguno,
        isArchived: false,
        updatedAt: DateTime(2023, 1, 1),
      );

      final newerEnvelope = Envelope(
        id: EnvelopeId('env-1'),
        name: 'Newer Name',
        role: EnvelopeRole.stage, // Role change attempted
        isArchived: true,
        updatedAt: DateTime(2023, 1, 2),
      );

      // older.mergeWith(newer) should pick newer data but KEEP older role
      final merged1 = olderEnvelope.mergeWith(newerEnvelope);
      expect(merged1.name, 'Newer Name');
      expect(merged1.role, EnvelopeRole.ninguno); // Preserved!
      expect(merged1.isArchived, true);
      expect(merged1.updatedAt, DateTime(2023, 1, 2));

      // What if we try to apply older onto newer? 
      // It should still just be newer (since it has higher timestamp), but the role comes from the base instance calling mergeWith.
      // Wait, mergeWith is typically "this" being updated by "other".
      // If "this" is newer, it rejects the older's data. So it keeps its own role (which is stage).
      final merged2 = newerEnvelope.mergeWith(olderEnvelope);
      expect(merged2.name, 'Newer Name');
      expect(merged2.role, EnvelopeRole.stage); 
      expect(merged2.isArchived, true);
      expect(merged2.updatedAt, DateTime(2023, 1, 2));
    });

    test('mergeWith keeps current if timestamps are exactly the same', () {
      final env1 = Envelope(
        id: EnvelopeId('env-1'),
        name: 'Name 1',
        role: EnvelopeRole.stage,
        isArchived: false,
        updatedAt: DateTime(2023, 1, 1),
      );

      final env2 = Envelope(
        id: EnvelopeId('env-1'),
        name: 'Name 2',
        role: EnvelopeRole.diferencial,
        isArchived: true,
        updatedAt: DateTime(2023, 1, 1),
      );

      final merged = env1.mergeWith(env2);
      expect(merged.name, 'Name 1');
      expect(merged.role, EnvelopeRole.stage);
    });

    test('mergeWith throws if IDs are different', () {
      final env1 = Envelope(
        id: EnvelopeId('env-1'),
        name: 'Name 1',
        role: EnvelopeRole.ninguno,
        updatedAt: DateTime(2023, 1, 1),
        isArchived: false,
      );

      final env2 = Envelope(
        id: EnvelopeId('env-2'),
        name: 'Name 2',
        role: EnvelopeRole.ninguno,
        updatedAt: DateTime(2023, 1, 2),
        isArchived: false,
      );

      expect(() => env1.mergeWith(env2), throwsArgumentError);
    });
  });
}
