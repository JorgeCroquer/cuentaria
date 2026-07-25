import 'package:contabilidad/application/catalog/models/envelope_appearance.dart';
import 'package:test/test.dart';

void main() {
  group('EnvelopeAppearance', () {
    test('none is empty and has no icon/color', () {
      expect(EnvelopeAppearance.none.iconId, isNull);
      expect(EnvelopeAppearance.none.colorIndex, isNull);
      expect(EnvelopeAppearance.none.isEmpty, isTrue);
    });

    test('equality', () {
      expect(
        const EnvelopeAppearance(iconId: 'cart', colorIndex: 2),
        const EnvelopeAppearance(iconId: 'cart', colorIndex: 2),
      );
      expect(
        const EnvelopeAppearance(iconId: 'cart', colorIndex: 2) ==
            const EnvelopeAppearance(iconId: 'cart', colorIndex: 3),
        isFalse,
      );
    });

    test('round-trips through JSON', () {
      const appearance = EnvelopeAppearance(iconId: 'cart', colorIndex: 4);
      expect(EnvelopeAppearance.fromJson(appearance.toJson()), appearance);
    });

    test('round-trips a partial appearance (icon only)', () {
      const appearance = EnvelopeAppearance(iconId: 'home');
      final json = appearance.toJson();
      expect(json.containsKey('color_index'), isFalse);
      expect(EnvelopeAppearance.fromJson(json), appearance);
    });

    test('fromJson with no keys returns none', () {
      expect(EnvelopeAppearance.fromJson(const {}), EnvelopeAppearance.none);
    });
  });
}
