import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Maps a catalog picker item's `*Chip_` key prefix to the field that opens
/// it (#316) — every capture-sheet test used to tap an `accountChip_*` /
/// `envelopeChip_*` / etc. key directly; now that row only exists inside the
/// field's search sheet, so [pickCatalogItem] opens the right field first.
const _fieldKeyByItemPrefix = {
  'incomeAccountChip_': 'incomeAccountField',
  'accountChip_': 'accountField',
  'envelopeChip_': 'envelopeField',
  'moverSourceChip_': 'moverSourceField',
  'moverDestinationChip_': 'moverDestinationField',
  'distributionSourceChip_': 'distributionSourceField',
  'distributionDestinationChip_': 'distributionDestinationField',
};

/// Taps the field that owns [itemKeyValue] to open its search sheet, then
/// taps the item — the sheet closes and applies the selection, same end
/// state as the old direct chip tap.
Future<void> pickCatalogItem(WidgetTester tester, String itemKeyValue) async {
  final prefix = _fieldKeyByItemPrefix.keys.firstWhere(itemKeyValue.startsWith);
  final fieldFinder = find.byKey(Key(_fieldKeyByItemPrefix[prefix]!));
  // The field lives in the sheet's scrollable top section — on a short
  // surface (default test window, or any caller that didn't size up like
  // `_openSheet` does) it may start out scrolled past the visible window.
  await tester.ensureVisible(fieldFinder);
  await tester.pumpAndSettle();
  await tester.tap(fieldFinder);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(itemKeyValue)));
  await tester.pumpAndSettle();
}
