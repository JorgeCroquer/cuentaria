# Cuentaria

**Personal** use app to centralize finances and accounting, adapted to the multi-rate Venezuelan reality. It separates *where* the money is (real **Accounts**) from *what it is for* (**Envelopes**), values everything in **USD**, automates where there is an API, and makes the rest quick to do by hand.

> **Idea in one sentence:** a comprehensive system that separates the *where* (Accounts) from the *what for* (Envelopes), values everything in USD over a multi-rate reality, automates where there is an API, and makes the rest quick to do by hand — robust, cheap, multi-platform, and extensible.

## Stack

- **Flutter** (Android · Web · Windows/macOS/Linux) — client-authoritative, offline-first.
- **Pure Dart** in the domain core (hexagonal · DDD · CQRS · event sourcing) and in the workers.
- **SQLite/Drift + SQLCipher** as the encrypted local source of truth.
- **Supabase free** (Postgres + Auth) as E2EE blob sync/backup — without domain logic.
- **GitHub Actions** (cron) runs the ingestion Dart AOT workers.
- **Cloudflare Pages** serves the static Flutter Web build.

Full details in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Monorepo Structure

**Melos** monorepo, one Dart package per bounded context (hexagonal inside).

```
apps/cuentaria_app/      Flutter (UI, navigation, theme, design system)
packages/
  shared_kernel/         pure value objects (Money, CurrencyCode, AccountId…)
  event_bus/             In-process EventBus (synchronous)
  contabilidad/          C1 — Account × Envelope ledger (write core)
  tasas/                 S1 — observed rates series
  portafolio/            S4 — holdings and valuation
  patrimonio/            S2 — "where the money is" projection
  deudas/                S3 — projection per person
workers/                 Dart AOT (rates ingestion, integrations)
docs/                    CONTEXT.md · ARCHITECTURE.md · adr/
```

## The 9 Model Rules

1. Two dimensions: **Account** (where) × **Envelope** (what for); always reconcile.
2. Base currency **USD**, multi-currency; transactional VES.
3. Money **never leaves the system**, only moves.
4. **Real cost** as truth; optional BCV value.
5. **Polymorphic providers**; sync is an optional capability.
6. **Honest automation**: fewer actions, not zero.
7. **Distributing = moving tags**, automatic and instant.
8. **Reconciliation** as a recurring ritual.
9. **Own data**, exportable, no lock-in.

## Development

Primary environment: **WSL2** (Ubuntu). The repo lives in the Linux filesystem (`~/projects/cuentaria`), **not** in `/mnt/c`, to avoid degrading Flutter file-watching.

```bash
# requirements: Flutter SDK (Linux), Dart, Melos
dart pub global activate melos
melos bootstrap          # resolves dependencies for all packages
melos run analyze        # static analysis
melos run test           # tests
```

Targets that compile from WSL2: **Linux desktop · Web · Android**. The **Windows desktop** target is built on the Windows host or a Windows CI runner (not from WSL).

## Deployment

La versión Web de Cuentaria se despliega automáticamente a **GitHub Pages** al hacer un merge a la rama `main` mediante un workflow de GitHub Actions (`.github/workflows/deploy-web.yaml`). 

Dado que se utiliza el dominio por defecto de GitHub Pages, la aplicación es accesible en `https://jorgecroquer.github.io/cuentaria/`. Por esta razón, el comando de build en el workflow inyecta `--base-href /cuentaria/` para que la navegación de `go_router` funcione correctamente.

> **Nota para dominios personalizados:** Si en el futuro se configura un dominio personalizado (ej. `cuentaria.com`), el parámetro `base-href` deberá cambiarse de vuelta a `/` en el workflow de despliegue.

## Planning

Features (PRDs) and their order live in the tracker (Jira, `QUEN` project) and in the design notes. MVP Slice: **F1 Scaffold → F2 Local persistence → C1 Ledger → C2 Distribution → S2 Patrimony → U1 Fast capture**.

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — consolidated view. **Start here.**
- [`docs/CONTEXT.md`](docs/CONTEXT.md) — ubiquitous architecture language.
- [`docs/adr/`](docs/adr/README.md) — 11 architecture decisions with their why.
- [`AGENTS.md`](AGENTS.md) — guide for AI agents working in the repo (symlinked to `CLAUDE.md`).
