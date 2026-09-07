import 'package:equatable/equatable.dart';

/// Reportes-owned mirror of one counterparty's net debt at a month-end
/// (ADR-0005: reportes never imports deudas' `domain/`, so app-layer wiring
/// maps deudas' `PersonDebts` into this). [netoUsdCents] carries the sign as
/// deudas does — positive means the person owed the user at that
/// month-end, negative the reverse.
class PersonDebtPoint extends Equatable {
  final String personName;
  final int netoUsdCents;

  const PersonDebtPoint({required this.personName, required this.netoUsdCents});

  @override
  List<Object?> get props => [personName, netoUsdCents];
}
