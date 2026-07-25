import 'package:flutter/material.dart';

/// Seed for Cuentaria's Material 3 color schemes — a deep emerald, distinct
/// from Flutter's default blue, evoking the app's ledger/money domain.
const _seedColor = Color(0xFF00695C);

/// Fixed catalog of swatches Accounts/Envelopes (later slices) pick from to
/// tag their own color. Kept here so there is a single source of truth.
class AppColors {
  const AppColors._();

  static const ruby = Color(0xFFB3261E);
  static const amber = Color(0xFFB58105);
  static const gold = Color(0xFF9C6B00);
  static const emerald = Color(0xFF1E8E5A);
  static const jade = Color(0xFF00897B);
  static const teal = Color(0xFF00695C);
  static const sky = Color(0xFF0277BD);
  static const sapphire = Color(0xFF1A56DB);
  static const indigo = Color(0xFF3F51B5);
  static const violet = Color(0xFF6A1B9A);
  static const rose = Color(0xFFAD1457);
  static const slate = Color(0xFF546E7A);

  static const palette = <Color>[
    ruby,
    amber,
    gold,
    emerald,
    jade,
    teal,
    sky,
    sapphire,
    indigo,
    violet,
    rose,
    slate,
  ];
}

ThemeData _appTheme(Brightness brightness) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: colorScheme,
    brightness: brightness,
    useMaterial3: true,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      centerTitle: true,
    ),
    cardTheme: const CardThemeData(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
  );
}

ThemeData appLightTheme() => _appTheme(Brightness.light);

ThemeData appDarkTheme() => _appTheme(Brightness.dark);
