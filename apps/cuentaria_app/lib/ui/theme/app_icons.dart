import 'package:flutter/material.dart';

/// Curated subset of Material Icons Envelopes pick from to tag their own
/// icon (U1 slice 2, #95) — kept small and user-recognizable rather than
/// exposing the entire `Icons` class. Keyed by a stable string id so the
/// choice persists in the catalog `meta` JSON independent of any single
/// Flutter version's `IconData.codePoint`.
class AppIcons {
  const AppIcons._();

  static const defaultIconId = 'savings';

  static const catalog = <String, IconData>{
    'savings': Icons.savings,
    'shopping_cart': Icons.shopping_cart,
    'home': Icons.home,
    'directions_car': Icons.directions_car,
    'card_giftcard': Icons.card_giftcard,
    'medical_services': Icons.medical_services,
    'restaurant': Icons.restaurant,
    'flight': Icons.flight,
    'school': Icons.school,
    'sports_esports': Icons.sports_esports,
    'pets': Icons.pets,
    'fitness_center': Icons.fitness_center,
  };

  static IconData iconFor(String? id) => catalog[id] ?? catalog[defaultIconId]!;
}
