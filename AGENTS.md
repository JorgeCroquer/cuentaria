# AGENTS.md — Agent Guidelines

Navigation guide and workflow rules for AI agents in the Cuentaria repo. Read it before touching code.

## What is Cuentaria

Personal finance app for the multi-rate Venezuelan reality. **Client-authoritative, offline-first.** All domain logic lives in **pure Dart packages** on the Flutter client; the "backend" (Supabase + workers) only syncs encrypted blobs and appends observed facts. See [`README.md`](README.md) and [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Canonical Documents (reading order)

1. [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — consolidated view.
2. [`docs/CONTEXT.md`](CONTEXT.md) — **ubiquitous architecture language**. Use these exact terms in code, commits, PRDs, and issues. If you introduce or rename a concept, update CONTEXT.md in the same commit.
3. [`docs/adr/`](docs/adr/README.md) — the 11 decisions with their reasoning. Before proposing something that contradicts an ADR, read it: if it really needs to change, write a **new ADR that supersedes it**, don't rewrite the old one.

## Architecture Rules that CANNOT be broken

- **Dependency Inversion.** `domain/` does not know `infrastructure/` or Flutter. External dependencies (Drift, Supabase, APIs) enter through **ports** defined in the domain and implemented as **adapters**.
- **Context Boundaries.** A package **never** imports another's `domain/`. Communication between contexts is only via **domain events** (in-process EventBus) or the **application API**; cross-references are **by ID** (`AccountId`, etc.). See ADR-0005.
- **Self-balancing Transaction.** Every ledger transaction fulfills `Σ usd[Account] == Σ usd[Envelope]`; the domain **rejects** those that don't. See ADR-0006. Do not add paths that write balances without passing this invariant.
- **Append-only.** No editing or deleting: append only. A correction is a reversal event (Reconciliation/Adjustment), not an `UPDATE`. See ADR-0002.
- **Frozen Real Cost.** `amount_usd` is snapshotted and not recalculated. Market value is a **read-only overlay**, never a posted event. See ADR-0006.
- **Integrations propose, they don't write.** A worker never writes to the ledger; it appends an observed fact and the client offers one-touch reconciliation. See ADR-0008.
- **Dumb Workers.** fetch → normalize → append observed fact. Zero domain logic in workers. See ADR-0003.

## Repo Structure

```
apps/cuentaria_app/   Flutter — UI and app shell (navigation, theme, design system)
packages/<context>/   domain/ · application/ · infrastructure/ (hexagonal)
  shared_kernel/      pure value objects, no context behavior
  event_bus/          in-process EventBus port
workers/              Dart AOT binaries for GitHub Actions
docs/                 CONTEXT.md · ARCHITECTURE.md · adr/
```

## Workflow

- Environment: **WSL2**; repo in `~/projects/cuentaria` (ext4). For **Windows desktop** target builds use the Windows host or CI — do not compile from WSL.
- Commands: `melos bootstrap`, `melos run analyze`, `melos run test`.
- Before considering a task finished: `dart format .` applied, then `melos run analyze` and `melos run test` passing green. CI runs `dart format --output=none --set-exit-if-changed .` — an unformatted file fails the build even when every test is green, so format **before** committing.
- Changes crossing contexts or touching invariants → review relevant ADR and add a new one if needed.

## Planning (pipeline)

`grill-with-docs` (granularity and PRDs list) → `to-prd` (one PRD = GitHub Issue, label `ready-for-agent`) → `to-issues` (vertical tracer bullets) → `improve-codebase-architecture` (continuous deepening informed by CONTEXT/ADRs). We prefer **few thick and deep PRDs** over many thin ones.

MVP Slice (build order): **F1 → F2 → C1 → C2 → S2 → U1.**

## Notes

- The extended conceptual source (vision, domain model, PRD map) lives in the project's Obsidian vault. The vault is located at the absolute path: `/mnt/d/Huella Digital/Obisidian Vaults/Knowledge_Base/🚀 100 - Proyectos/Cuentaria/`. Agents should refer to this vault for product/design context and PRD specs, but this repo remains the source of truth for **architecture and code**. If something is decided here, reflect it in `docs/`, ADRs, and sync it back to the vault using the `/sync-obsidian` skill.

## Agent skills

### Issue tracker

GitHub issues (cuentaria repository). See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout (`CONTEXT.md` and `docs/adr/` at root). See `docs/agents/domain.md`.
