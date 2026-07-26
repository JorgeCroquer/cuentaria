import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:cuentaria_app/features/distribution/ui/screens/cascade_editor_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('reorderCascadeSteps', () {
    final a = CascadeStep.catchAll(envelopeId: EnvelopeId('a'));
    final b = CascadeStep.catchAll(envelopeId: EnvelopeId('b'));
    final c = CascadeStep.catchAll(envelopeId: EnvelopeId('c'));

    test('moves an item down, adjusting for ReorderableListView semantics', () {
      final result = reorderCascadeSteps([a, b, c], 0, 2);
      expect(result.map((s) => s.envelopeId.value), ['b', 'a', 'c']);
    });

    test('moves an item up', () {
      final result = reorderCascadeSteps([a, b, c], 2, 0);
      expect(result.map((s) => s.envelopeId.value), ['c', 'a', 'b']);
    });

    test('does not mutate the original list', () {
      final original = [a, b, c];
      reorderCascadeSteps(original, 0, 2);
      expect(original.map((s) => s.envelopeId.value), ['a', 'b', 'c']);
    });
  });
}
