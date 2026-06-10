# ADR-0005 — Modular monolith: structure, integration between modules, and context map

**Status:** accepted (2026-06-09)

**Structure.** **Melos** monorepo, one Dart package per bounded context. Each package is internally hexagonal: `domain/` (aggregates, events, value objects, ports), `application/` (command/query handlers), `infrastructure/` (adapters: Drift, Supabase, external APIs).
A **`shared_kernel`** package with only pure shared value objects (`Money`, `CurrencyCode`, `AccountId`, `EnvelopeId`, `EventId`, timestamps) — no behavior from any context.

**Integration between modules.** Only two ways: **published domain events** and a **thin application API** (commands/queries). Importing another context's `domain/` is forbidden; they are referenced **by ID**. Events use an **in-process `EventBus` with synchronous dispatch**: the contract already has a message shape, but without eventual consistency inside a single-user client. **Splitting into microservices = swapping the in-process bus for a network one, without touching contracts.** Boundary enforcement with package limits + lint rules for imports.

**Rejected integration alternatives:**

- *In-process async bus:* introduces eventual consistency and retries that the client doesn't need yet.
- *Direct synchronous calls between app-services:* simpler today but couples by call and requires rewriting integrations when splitting.

**Context Map (MVP).**

| Context | Role | Owns aggregates |
|----------|-----|-----------------|
| **Accounting / Cash** | Write core: **Account** aggregates (types: liquid, receivable/payable, deferred-asset) and **Envelope**, event log, all transaction types (incl. Reconciliation and P2P/FX) | Yes |
| **Rates** | Transversal: observed facts (BCV, parallel) + time series; publishes `RateObserved` and a queryable read-model series via port | No (observed facts, ADR-0002) |
| **Portfolio** | Own write: holdings, Level 1 valuation, passive income; data ready for Level 2 (PNL/cost basis) | Yes |
| **Patrimony** | **Read-only projection**: "where the money is" and net worth in USD over Accounts + Rates + holdings. Orchestrates the reconciliation ritual by emitting commands to Accounting | No |
| **Debts** | **Read-only projection**: balance per person on Accounting's receivable/payable accounts. Splitwise net balances are imported as adjustments to those accounts | No (MVP) |

**Why Patrimony and Debts as projection:** avoids duplicating the balance concept (root cause of the original "doesn't match" issue) → **a single source of truth for balance: the ledger**. Doesn't break the microservices goal: Debts can be **promoted** to a write context the day native splitting is built to replace Splitwise (deferred).
