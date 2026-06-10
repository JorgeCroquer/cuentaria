# CLAUDE.md — Guía para agentes

Guía de navegación y reglas de trabajo para agentes de IA en el repo de Cuentaria. Léela antes
de tocar código.

## Qué es Cuentaria

App personal de finanzas para la realidad venezolana multi-tasa. **Cliente-autoritativa,
offline-first.** Toda la lógica de dominio vive en **paquetes Dart puros** en el cliente
Flutter; el "backend" (Supabase + workers) solo sincroniza blobs cifrados y anexa hechos
observados. Ver [`README.md`](README.md) y [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Documentos canónicos (orden de lectura)

1. [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — la vista consolidada.
2. [`docs/CONTEXT.md`](docs/CONTEXT.md) — **lenguaje ubicuo de arquitectura**. Usa estos
   términos exactos en código, commits, PRDs e issues. Si introduces o renombras un concepto,
   actualiza CONTEXT.md en el mismo cambio.
3. [`docs/adr/`](docs/adr/README.md) — las 11 decisiones con su porqué. Antes de proponer algo
   que contradiga un ADR, léelo: si de verdad hay que cambiarlo, se escribe un **ADR nuevo que
   lo supersede**, no se reescribe el viejo.

## Reglas de arquitectura que NO se rompen

- **Inversión de dependencias.** `domain/` no conoce a `infrastructure/` ni a Flutter. Las
  dependencias externas (Drift, Supabase, APIs) entran por **puertos** definidos en el dominio
  e implementados como **adaptadores**.
- **Fronteras de contexto.** Un paquete **nunca** importa el `domain/` de otro. La comunicación
  entre contextos es solo por **eventos de dominio** (EventBus en proceso) o por la **API de
  aplicación**; las referencias cruzadas son **por ID** (`AccountId`, etc.). Ver ADR-0005.
- **Transacción auto-balanceada.** Toda transacción del ledger cumple
  `Σ usd[Cuenta] == Σ usd[Sobre]`; el dominio **rechaza** las que no. Ver ADR-0006. No añadas
  caminos que escriban saldos sin pasar por este invariante.
- **Append-only.** No se edita ni se borra: se anexa. Una corrección es un evento de reverso
  (Conciliación/Ajuste), no un `UPDATE`. Ver ADR-0002.
- **Costo real congelado.** `amount_usd` se snapshotea y no se recalcula. El valor de mercado es
  un **overlay de solo-lectura**, nunca un evento posteado. Ver ADR-0006.
- **Las integraciones proponen, no escriben.** Un worker nunca escribe al ledger; anexa un hecho
  observado y el cliente ofrece conciliación de un toque. Ver ADR-0008.
- **Workers tontos.** fetch → normaliza → anexa hecho observado. Cero lógica de dominio en los
  workers. Ver ADR-0003.

## Estructura del repo

```
apps/cuentaria_app/   Flutter — UI y marco de la app (navegación, tema, design system)
packages/<contexto>/  domain/ · application/ · infrastructure/ (hexagonal)
  shared_kernel/      value objects puros, sin comportamiento de contexto
  event_bus/          puerto del EventBus en proceso
workers/              binarios Dart AOT para GitHub Actions
docs/                 CONTEXT.md · ARCHITECTURE.md · adr/
```

## Flujo de trabajo

- Entorno: **WSL2**; repo en `~/projects/cuentaria` (ext4). Para builds del target **Windows
  desktop** usar el host Windows o CI — no se compila desde WSL.
- Comandos: `melos bootstrap`, `melos run analyze`, `melos run test`.
- Antes de dar una tarea por terminada: `melos run analyze` y `melos run test` en verde.
- Cambios que cruzan contextos o tocan invariantes → revisa el ADR pertinente y, si hace falta,
  añade uno nuevo.

## Planificación (pipeline)

`grill-with-docs` (granularidad y lista de PRDs) → `to-prd` (un PRD = issue padre en Jira
`QUEN`, label `ready-for-agent`) → `to-issues` (tracer bullets verticales) →
`improve-codebase-architecture` (deepening continuo informado por CONTEXT/ADRs). Preferimos
**pocos PRDs gruesos y profundos** sobre muchos finos.

Slice MVP (orden de construcción): **F1 → F2 → C1 → C2 → S2 → U1.**

## Notas

- La fuente conceptual extendida (visión, modelo de dominio, mapa de PRDs) vive en el Obsidian
  vault del proyecto. Este repo es la fuente de verdad de **arquitectura y código**; si algo se
  decide aquí, refléjalo en `docs/` y en los ADRs.
