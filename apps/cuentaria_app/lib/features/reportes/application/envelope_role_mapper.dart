import 'package:contabilidad/application/catalog/models/envelope.dart'
    as contabilidad;
import 'package:reportes/reportes.dart';

/// Maps contabilidad's `EnvelopeRole` into reportes' own [EnvelopeRoleView]
/// (ADR-0005 — reportes never imports contabilidad's `domain/`). Shared by
/// every Reportes provider that feeds a flow engine.
EnvelopeRoleView mapEnvelopeRole(contabilidad.EnvelopeRole role) =>
    switch (role) {
      contabilidad.EnvelopeRole.none => EnvelopeRoleView.user,
      contabilidad.EnvelopeRole.stage => EnvelopeRoleView.stage,
      contabilidad.EnvelopeRole.differential => EnvelopeRoleView.differential,
      contabilidad.EnvelopeRole.adjustments => EnvelopeRoleView.adjustments,
      contabilidad.EnvelopeRole.opening => EnvelopeRoleView.opening,
    };
