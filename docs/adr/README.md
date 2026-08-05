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
| [0007](ADR-0007-servicio-tasas.md) | Servicio de Tasas: Binance P2P canónico, multi-fuente | Superseded por [0020](ADR-0020-ingesta-de-tasas-sin-servidor.md) |
| [0008](ADR-0008-integraciones.md) | Integraciones: lo observado propone, nunca escribe al ledger | Aceptada |
| [0009](ADR-0009-seguridad-e2ee.md) | Seguridad: E2EE por sobre, Auth, cifrado local, export | Aceptada |
| [0010](ADR-0010-metas-sobres.md) | Modelo unificado de metas/aportes de Sobres | Aceptada |
| [0011](ADR-0011-conciliacion.md) | Conciliación operativa: tolerancia configurable | Aceptada |
| [0014](ADR-0014-persistencia-f2-cifrado-local.md) | F2: store cifrado solo-nativo, llave local separada del DEK (refina 0009) | Aceptada |
| [0015](ADR-0015-cascada-distribucion.md) | Cascada de distribución + metas de Sobres (refina 0010) | Aceptada |
| [0016](ADR-0016-tasas-manuales-valoracion-patrimonio.md) | Tasas manuales como hechos observados; el paralelo valora, el BCV informa | Aceptada |
| [0017](ADR-0017-sobregiro-registrable.md) | Sobregiro registrable: el ledger admite saldos negativos, el exceso se valora a tasa de ejecución | Aceptada |
| [0018](ADR-0018-valoracion-sin-contraparte-observada.md) | Valoración sin contraparte observada: el costo congelado sale de la serie paralela | Aceptada |
| [0019](ADR-0019-conciliacion-enrutada.md) | Conciliación enrutada: el tamaño decide, no el signo; el sobrante se registra como Ingreso (refina 0011) | Aceptada |
| [0020](ADR-0020-ingesta-de-tasas-sin-servidor.md) | Ingesta de tasas sin servidor: el worker publica todo, la app elige y lo anuncia (supersede 0007) | Aceptada |

> 0001–0011 aceptadas el 2026-06-09 en la sesión de diseño `grill-with-docs`.
> ADR-0014 (2026-06-15) refina el 0009 para F2. ADR-0015 (2026-06-23) refina el 0010 para C2.
> ADR-0016 (2026-07-23) fija la valoración de S2 y adelanta el almacén de la serie del 0007.
> ADR-0017 (2026-08-04) refina el 0006: el ledger admite saldos negativos en vez de rechazar el disposal.
> ADR-0018 (2026-08-04) completa el 0006 y aclara el 0016: de dónde sale el `amount_usd` congelado cuando no hay contraparte USD observada.
> ADR-0019 (2026-08-04) refina el 0011 y cierra el cabo que 0017/0018 le delegaron: el ritual de conciliación.
> ADR-0020 (2026-08-05) supersede el 0007: su agregador pasó a ser de pago y su premisa de frecuencia ("la serie tolera lag") la invalidó el 0018.
> Los números 0012/0013 quedaron reservados sin redactar (Riverpod+go_router · Doctrina B).

## Plantilla para nuevos ADRs

```markdown
# ADR-XXXX — <título>

**Estado:** propuesta | aceptada | superseded por ADR-YYYY (fecha)

<contexto y decisión: qué se decide y por qué>

**Alternativas rechazadas:** <opción — por qué se descartó>

**Consecuencia:** <qué implica / qué se asume>
```
