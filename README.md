# Cuentaria

App de uso **personal** para centralizar finanzas y contabilidad, adaptada a la realidad
venezolana multi-tasa. Separa el *dónde* está el dinero (**Cuentas** reales) del *para qué* es
(**Sobres**), valora todo en **USD**, automatiza donde hay API y hace el resto rápido a mano.

> **Idea en una frase:** un sistema integral que separe el *dónde* (Cuentas) del *para qué*
> (Sobres), valore todo en USD sobre una realidad multi-tasa, automatice donde haya API y haga
> el resto rápido a mano — robusto, barato, multiplataforma y extensible.

## Stack

- **Flutter** (Android · Web · Windows/macOS/Linux) — cliente autoritativo, offline-first.
- **Dart puro** en el core de dominio (hexagonal · DDD · CQRS · event sourcing) y en los workers.
- **SQLite/Drift + SQLCipher** como fuente de verdad local cifrada.
- **Supabase free** (Postgres + Auth) como sync/backup de blobs E2EE — sin lógica de dominio.
- **GitHub Actions** (cron) ejecuta los workers Dart AOT de ingesta.
- **Cloudflare Pages** sirve el build estático de Flutter Web.

Detalle completo en [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Estructura del monorepo

Monorepo **Melos**, un paquete Dart por bounded context (hexagonal por dentro).

```
apps/cuentaria_app/      Flutter (UI, navegación, tema, design system)
packages/
  shared_kernel/         value objects puros (Money, CurrencyCode, AccountId…)
  event_bus/             EventBus en proceso (síncrono)
  contabilidad/          C1 — ledger Cuenta × Sobre (núcleo write)
  tasas/                 S1 — serie de tasas observadas
  portafolio/            S4 — holdings y valoración
  patrimonio/            S2 — proyección "dónde está el dinero"
  deudas/                S3 — proyección por persona
workers/                 Dart AOT (ingesta de tasas, integraciones)
docs/                    CONTEXT.md · ARCHITECTURE.md · adr/
```

## Las 9 reglas del modelo

1. Dos dimensiones: **Cuenta** (dónde) × **Sobre** (para qué); siempre concilian.
2. Moneda base **USD**, multi-moneda; Bs transaccional.
3. El dinero **nunca sale del sistema**, solo se mueve.
4. **Costo real** como verdad; valor BCV opcional.
5. **Proveedores polimórficos**; sync es capacidad opcional.
6. **Automatización honesta**: menos acciones, no cero.
7. **Distribuir = mover etiquetas**, automático e instantáneo.
8. **Conciliación** como ritual recurrente.
9. **Datos propios**, exportables, sin lock-in.

## Desarrollo

Entorno primario: **WSL2** (Ubuntu). El repo vive en el filesystem de Linux
(`~/projects/cuentaria`), **no** en `/mnt/c`, para no degradar el file-watching de Flutter.

```bash
# requisitos: Flutter SDK (Linux), Dart, Melos
dart pub global activate melos
melos bootstrap          # resuelve dependencias de todos los paquetes
melos run analyze        # análisis estático
melos run test           # tests
```

Targets que compilan desde WSL2: **Linux desktop · Web · Android**. El target **Windows
desktop** se construye en el host Windows o en un runner Windows de CI (no desde WSL).

## Planificación

Las features (PRDs) y su orden viven en el tracker (Jira, proyecto `QUEN`) y en las notas de
diseño. Slice MVP: **F1 Scaffold → F2 Persistencia local → C1 Ledger → C2 Distribución →
S2 Patrimonio → U1 Captura rápida**.

## Documentación

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — vista consolidada. **Empezar aquí.**
- [`docs/CONTEXT.md`](docs/CONTEXT.md) — lenguaje ubicuo de arquitectura.
- [`docs/adr/`](docs/adr/README.md) — 11 decisiones de arquitectura con su porqué.
- [`CLAUDE.md`](CLAUDE.md) — guía para agentes de IA que trabajen en el repo.
