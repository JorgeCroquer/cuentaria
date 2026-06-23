import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/envelope_target.dart';
import 'package:test/test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('Envelope', () {
    test(
      'mergeWith resolves via Last-Write-Wins based on updatedAt but preserves original role',
      () {
        final olderEnvelope = Envelope(
          id: EnvelopeId('env-1'),
          name: 'Older Name',
          role: EnvelopeRole.none,
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
        expect(merged1.role, EnvelopeRole.none); // Preserved!
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
      },
    );

    test('mergeWith resolves meta via Last-Write-Wins', () {
      final olderEnvelope = Envelope(
        id: EnvelopeId('env-1'),
        name: 'Older Name',
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: DateTime(2023, 1, 1),
        meta: {'key': 'old'},
      );

      final newerEnvelope = Envelope(
        id: EnvelopeId('env-1'),
        name: 'Newer Name',
        role: EnvelopeRole.stage,
        isArchived: true,
        updatedAt: DateTime(2023, 1, 2),
        meta: {'key': 'new', 'other': 'value'},
      );

      final merged1 = olderEnvelope.mergeWith(newerEnvelope);
      expect(merged1.meta, {'key': 'new', 'other': 'value'});

      final merged2 = newerEnvelope.mergeWith(olderEnvelope);
      expect(merged2.meta, {'key': 'new', 'other': 'value'});
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
        role: EnvelopeRole.differential,
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
        role: EnvelopeRole.none,
        updatedAt: DateTime(2023, 1, 1),
        isArchived: false,
      );

      final env2 = Envelope(
        id: EnvelopeId('env-2'),
        name: 'Name 2',
        role: EnvelopeRole.none,
        updatedAt: DateTime(2023, 1, 2),
        isArchived: false,
      );

      expect(() => env1.mergeWith(env2), throwsArgumentError);
    });

    // -------------------------------------------------------------------------
    // EnvelopeTarget — typed access
    // -------------------------------------------------------------------------

    group('target', () {
      final t0 = DateTime(2024, 1, 1);

      test('defaults to NoTarget when meta is null', () {
        final env = Envelope(
          id: EnvelopeId('env-t1'),
          name: 'Groceries',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t0,
        );
        expect(env.target, const NoTarget());
      });

      test('defaults to NoTarget when meta has no target key', () {
        final env = Envelope(
          id: EnvelopeId('env-t2'),
          name: 'Groceries',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t0,
          meta: {'other': 'data'},
        );
        expect(env.target, const NoTarget());
      });

      test('returns Cap from meta', () {
        final env = Envelope(
          id: EnvelopeId('env-t3'),
          name: 'Groceries',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t0,
          meta: {
            'target': {'type': 'cap', 'amount_usd': 30000},
          },
        );
        expect(env.target, const Cap(amountUsd: 30000));
      });

      test('returns GoalLine from meta', () {
        final env = Envelope(
          id: EnvelopeId('env-t4'),
          name: 'Emergency',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t0,
          meta: {
            'target': {'type': 'goal_line', 'amount_usd': 100000},
          },
        );
        expect(env.target, const GoalLine(amountUsd: 100000));
      });

      test('withTarget encodes Cap into meta and round-trips', () {
        final env = Envelope(
          id: EnvelopeId('env-t5'),
          name: 'Dining',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t0,
        );
        final updated = env.withTarget(const Cap(amountUsd: 20000));
        expect(updated.target, const Cap(amountUsd: 20000));
        expect(updated.id, env.id);
        expect(updated.name, env.name);
      });

      test('withTarget encodes GoalLine with date into meta', () {
        final due = DateTime.utc(2028, 1, 1);
        final env = Envelope(
          id: EnvelopeId('env-t6'),
          name: 'Emergency',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t0,
        );
        final updated = env.withTarget(GoalLine(amountUsd: 50000, dueDate: due));
        expect(
          updated.target,
          GoalLine(amountUsd: 50000, dueDate: due),
        );
      });

      test('withTarget preserves other meta keys', () {
        final env = Envelope(
          id: EnvelopeId('env-t7'),
          name: 'Food',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t0,
          meta: {'custom': 'value'},
        );
        final updated = env.withTarget(const Cap(amountUsd: 10000));
        expect(updated.meta!['custom'], 'value');
        expect(updated.target, const Cap(amountUsd: 10000));
      });

      test('withTarget NoTarget removes target key from meta', () {
        final env = Envelope(
          id: EnvelopeId('env-t8'),
          name: 'Food',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t0,
          meta: {
            'custom': 'value',
            'target': {'type': 'cap', 'amount_usd': 10000},
          },
        );
        final updated = env.withTarget(const NoTarget());
        expect(updated.target, const NoTarget());
        expect(updated.meta!.containsKey('target'), isFalse);
        expect(updated.meta!['custom'], 'value');
      });

      test('withTarget on system envelope throws', () {
        final env = Envelope(
          id: EnvelopeId('sys-stage'),
          name: 'Stage',
          role: EnvelopeRole.stage,
          isArchived: false,
          updatedAt: t0,
        );
        expect(
          () => env.withTarget(const Cap(amountUsd: 10000)),
          throwsArgumentError,
        );
      });

      test('mergeWith preserves target via LWW (newer wins)', () {
        final older = Envelope(
          id: EnvelopeId('env-merge'),
          name: 'X',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime(2024, 1, 1),
          meta: {
            'target': {'type': 'cap', 'amount_usd': 10000},
          },
        );
        final newer = Envelope(
          id: EnvelopeId('env-merge'),
          name: 'X',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime(2024, 1, 2),
          meta: {
            'target': {'type': 'cap', 'amount_usd': 99000},
          },
        );
        expect(older.mergeWith(newer).target, const Cap(amountUsd: 99000));
        expect(newer.mergeWith(older).target, const Cap(amountUsd: 99000));
      });
    });
  });
}
