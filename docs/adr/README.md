# Architecture Decision Records (ADRs)

Registro de decisiones de arquitectura de Cuentaria. Cada ADR registra **qué** se decidió y
**por qué**, con las alternativas rechazadas cuando la rechazada no es obvia. Son inmutables:
si una decisión cambia, se añade un ADR nuevo que la supersede (no se reescribe el viejo).

| # | Decisión | Estado |
|---|----------|--------|
| [0001](ADR-0001-dominio-cliente-autoritativo.md) | Dominio cliente-autoritativo, offline-first | Aceptada |
| [0002](ADR-0002-append-only.md) | Append-only en todo; dos arquetipos de evento | Aceptada |
| [0003](ADR-0003-dart-en-todo.md) | Dart en todo, incluidos los workers | Aceptada |
| [0004](ADR-0004-hosting-casi-gratis.md) | Hosting casi-gratis (Supabase + GitHub Actions + Cloudflare) | Aceptada |
| [0005](ADR-0005-monolito-modular.md) | Monolito modular: estructura e integración entre módulos | Aceptada |
| [0006](ADR-0006-ledger-cuenta-sobre.md) | Ledger Cuenta × Sobre, transacción auto-balanceada | Aceptada |
| [0007](ADR-0007-servicio-tasas.md) | Servicio de Tasas: Binance P2P canónico, multi-fuente | Aceptada |
| [0008](ADR-0008-integraciones.md) | Integraciones: lo observado propone, nunca escribe al ledger | Aceptada |
| [0009](ADR-0009-seguridad-e2ee.md) | Seguridad: E2EE por sobre, Auth, cifrado local, export | Aceptada |
| [0010](ADR-0010-metas-sobres.md) | Modelo unificado de metas/aportes de Sobres | Aceptada |
| [0011](ADR-0011-conciliacion.md) | Conciliación operativa: tolerancia configurable | Aceptada |

> ADRs 0001–0011 aceptados el 2026-06-09 en la sesión de diseño `grill-with-docs`.
> Reservados (candidatos sin redactar): **0012** Riverpod + go_router (F1-5), **0013** Doctrina B de realización + costo base promedio (C1-5), **0014** F2 persistencia cifrado local, **0015** C2 cascada de distribución.

## Plantilla para nuevos ADRs

```markdown
# ADR-XXXX — <título>

**Estado:** propuesta | aceptada | superseded por ADR-YYYY (fecha)

<contexto y decisión: qué se decide y por qué>

**Alternativas rechazadas:** <opción — por qué se descartó>

**Consecuencia:** <qué implica / qué se asume>
```
