import 'package:cuentaria_app/ui/theme/app_icons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exposes a curated, non-empty catalog of distinct icons', () {
    expect(AppIcons.catalog, isNotEmpty);
    expect(AppIcons.catalog.values.toSet(), hasLength(AppIcons.catalog.length));
  });

  test('iconFor resolves a known id', () {
    final id = AppIcons.catalog.keys.first;
    expect(AppIcons.iconFor(id), AppIcons.catalog[id]);
  });

  test('iconFor falls back to the default for an unknown or null id', () {
    final fallback = AppIcons.catalog[AppIcons.defaultIconId];
    expect(AppIcons.iconFor('not-a-real-id'), fallback);
    expect(AppIcons.iconFor(null), fallback);
  });
}
