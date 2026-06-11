# Cuentaria — CONTEXT (Architecture Language)

> Glossary of the **ubiquitous architecture language** (not implementation). This is the source of truth for the vocabulary we use in code, PRDs, issues, and conversations with agents.
> It complements the **domain** glossary (see `docs/DOMAIN.md` when note 02 is transferred).
> The decisions justifying these terms live in `docs/adr/`.
>
> Updated inline as decisions crystallize. If you introduce a new concept or rename one, edit it here first.

## Language

**Domain Core**
Pure Dart packages (hexagonal/DDD) containing the aggregates, invariants, and logic.
They run in the Flutter client; reusable in a future server.
_Avoid_: "backend", "API" (those are adapters, not the core).

**Client-authoritative**
The device is the source of truth; the local store (SQLite/Drift) rules. The server only synchronizes and backs up.
_Avoid_: "server-authoritative" (rejected, see [ADR-0001](adr/ADR-0001-dominio-cliente-autoritativo.md)).

**Domain Event (command-sourced)**
Immutable fact produced by executing a command that passed an aggregate's invariants (e.g. a ledger posting). It is the unit of true event sourcing.
_Avoid_: "record", "row" (those are projections).

**Observed External Fact**
Immutable observation ingested from the outside (BCV/parallel rate, market price, on-chain balance). Append-only, **without** aggregate or command.
_Avoid_: treating it as a domain event.

**Projection / Read Model**
Materialized view recomputable from the event log (balance by Account, balance by Envelope, cash flow). Disposable and reconstructible.
_Avoid_: "balances table" as if it were a source of truth.

**Port / Adapter**
Hexagonal boundary: the core defines ports (interfaces); adapters (Drift, Supabase, Binance, BCV) implement them. Supabase Postgres is a persistence/sync adapter, never the backend with logic.

**Integration Worker**
Minimal serverless function **in Dart** (AOT, scale-to-zero container) that executes sync with external APIs (Binance, rates, on-chain). It lives outside the client for secrets/scheduling. It is **dumb**: fetch → normalize → append observed fact; zero domain logic. See [ADR-0003](adr/ADR-0003-dart-en-todo.md).

**Scale-to-zero**
Hosting mode where the platform (Cloud Run / Fly.io) maintains zero instances without traffic (≈ free) and spins one up per trigger. Cost: cold start of 1–3 s, irrelevant for background sync.

**Shared Kernel**
Dart package with pure value objects shared by all contexts (`Money`, `CurrencyCode`, `AccountId`, `EnvelopeId`, `EventId`). No context-specific behavior.

**In-process EventBus**
Port that delivers domain events between modules **synchronously** within the client. Contract has a message shape today; easily swappable for a network bus when splitting into microservices. See [ADR-0005](adr/ADR-0005-monolito-modular.md).

**Reference by ID**
A context references entities of another only by their identifier (e.g. Portfolio uses `AccountId`), never importing its `domain/`. Bounded context boundary.

**Read-only Projection (context)**
Context that doesn't own aggregates; derives views from others (Patrimony, Debts in MVP). It can orchestrate by emitting commands to the owner context, but does not keep its own balance.

**Posting**
A line in a transaction affecting a dimension (Account or Envelope):
`(dimension, target_id, amount_native, currency, amount_usd, rate_ref?)`.

**Self-balancing Transaction**
Transaction that by itself fulfills `Σ usd[Account] == Σ usd[Envelope]`. The domain demands it; guarantees the global invariant under any merge order. See [ADR-0006](adr/ADR-0006-ledger-cuenta-sobre.md).

**Real Cost (snapshot)**
`amount_usd` frozen at the moment of the transaction; never recalculated. Accounting truth.
_Avoid_: recomputing the historical USD from the current rate.

**Overlay Valuation / Unrealized P&L**
Today's value computed on the fly (`quantity × current rate/price`) shown in Patrimony, without posting to the ledger. The difference with real cost is the **unrealized** P&L; it becomes **realized** only when converting/selling/spending.

**Ledger Transaction (The Aggregate)**
The only true aggregate in the ledger context. Each transaction is self-contained and self-validated. **Accounts and Envelopes are NOT aggregates**, they are just identifiers and materialized views.

**Transaction Factory (Smart Constructor)**
The application-layer constructor that enforces the specific shape of a transaction type (e.g. Income, Expense, Transfer). The domain only checks the balance invariant; the factories ensure semantic correctness.

**Realization (Doctrina B)**
The act of converting an unrealized P&L into a realized one. Occurs automatically when spending/converting a foreign currency asset. The difference between the current market rate and the historical average base cost is posted to a System Envelope (Exchange Differential).

**Average Base Cost**
The historical cost of an asset (USD / native) derived dynamically from the event log. Used to calculate the realized differential when spending.

**System Envelope**
Auto-provisioned envelopes identified by `rol` (e.g. Stage, Exchange Differential, Adjustments, Opening Balance). The system relies on their roles, not hardcoded IDs.

**Reversal vs Adjustment**
- **Reversal:** Exact negation of a previous transaction's frozen `amount_usd` to correct a mistake.
- **Adjustment:** A conciliation entry posting a delta against the Adjustments system envelope to match reality.

## Relationships

- A **Command** on an **Aggregate** produces one or more **Domain Events**.
- **Projections** are derived from the **Domain Events** log + **Observed External Facts**.
- The **Domain Core** depends on **Ports**; the **Adapters** depend on the core (dependency inversion).

## Resolved Ambiguities

- "Backend" was used for two things: the **domain core** (lives in the client) and the **sync/integration infra** (Supabase + workers). Resolved as distinct concepts.
- "Event sourcing everywhere" was refined: append-only everywhere, but **two archetypes** (domain event vs observed external fact). See [ADR-0002](adr/ADR-0002-append-only.md).
