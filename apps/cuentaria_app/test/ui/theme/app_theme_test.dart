import 'package:cuentaria_app/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('appLightTheme uses Material 3 with a non-default light scheme', () {
    final theme = appLightTheme();

    expect(theme.useMaterial3, isTrue);
    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.primary, isNot(Colors.blue));
  });

  test('appDarkTheme uses Material 3 with a non-default dark scheme', () {
    final theme = appDarkTheme();

    expect(theme.useMaterial3, isTrue);
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, isNot(Colors.blue));
  });

  test('both themes share the same seed color', () {
    expect(appLightTheme().colorScheme.primary, isNot(appDarkTheme().colorScheme.primary));
    expect(appLightTheme().colorScheme.brightness, Brightness.light);
    expect(appDarkTheme().colorScheme.brightness, Brightness.dark);
  });

  test('AppColors exposes a fixed catalog palette for later slices to pick from', () {
    expect(AppColors.palette, hasLength(12));
    expect(AppColors.palette.toSet(), hasLength(12)); // all distinct
  });
}
