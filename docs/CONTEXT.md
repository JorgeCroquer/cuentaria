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

**Catalog**
The user's Accounts and Envelopes as durable configuration — name, native currency, role, appearance, Funding Target. It is **not** event-sourced: it is last-write-wins config merged on `updatedAt`, exactly like the Cascade. Catalog and Cascade together are the part of the user's state the event log does **not** contain, which is why replaying the log alone yields correct balances hanging off anonymous identifiers. See [ADR-0021](adr/ADR-0021-respaldo-portable-en-claro.md).
_Avoid_: calling it a Projection (a Projection is recomputable from the log; the Catalog is not).

**Port / Adapter**
Hexagonal boundary: the core defines ports (interfaces); adapters (Drift, Google Drive, Binance, BCV) implement them. The user's cloud is a storage adapter behind `CloudFolder`, never a backend with logic (ADR-0023).

**Integration Worker**
Minimal program **in Dart** (AOT) that executes sync with external APIs (Binance, rates, on-chain). It lives outside the client for **scheduling** — it must run on days the phone is off — and, when a source needs one, for secrets. It is **dumb**: fetch → normalize → append observed fact; zero domain logic, and in particular it never picks a winner among sources. Its host is whatever is cheapest per worker: a GitHub Actions cron for the rates worker (no secrets, publishes a static file), a scale-to-zero container when a callback demands one. See [ADR-0003](adr/ADR-0003-dart-en-todo.md) and [ADR-0020](adr/ADR-0020-ingesta-de-tasas-sin-servidor.md).

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
Today's value computed on the fly (`quantity × current rate/price`) shown in Patrimony, without posting to the ledger. The difference with real cost is the **unrealized** P&L; it becomes **realized** only when converting/selling/spending. Computed with the **parallel** rate (see Liquidation Value vs BCV Value).

**Rate Observation**
One appended entry in a currency's rate series: `(currency, nativePerUsd, observedAt, source)`. An Observed External Fact — never overwritten, never a domain event. `source` names the provenance, not the role: `binancep2p:ask`, `dolarapi:paralelo`, `dolarapi:oficial`, `manual:paralelo`, `manual:bcv`. Several sources coexist for the same currency and day and **do not agree**; which one values a movement is decided by the Rate Resolution Chain, never by the source's own claim to be "the" rate. See [ADR-0016](adr/ADR-0016-tasas-manuales-valoracion-patrimonio.md) and [ADR-0020](adr/ADR-0020-ingesta-de-tasas-sin-servidor.md).

**Rate Resolution Chain**
The pure, client-side rule that picks **one** Rate Observation to value a movement: `resolve(currency, asOf, observations) → (rate, source, observedAt)`. Priority `manual` (same day only) → `binancep2p:ask` → `dolarapi:paralelo`; freshness wins first, source rank only breaks ties within the same day, so a manually typed rate rules the day it was typed and never hijacks later ones. It lives in the client and never in a worker: choosing the rate **is** deciding what the user's net worth is, and that cannot live in a CI binary without domain tests ([ADR-0003](adr/ADR-0003-dart-en-todo.md)). Whatever it picks, the app announces — source and date. A currency with no automatic source resolves down to the manual rung. See [ADR-0020](adr/ADR-0020-ingesta-de-tasas-sin-servidor.md).
_Avoid_: "fallback in the worker" (rejected — a source change would move net worth with no signal).

**Published Rate Series**
The append-only NDJSON file the ingestion worker publishes as a fixed GitHub Release asset, read by the client over plain HTTPS with no token, server or auth. It is a **transport**, not a source of truth: the client merges it into its local series idempotently and the ledger keeps ruling. Its side effect is that the rate history is the one part of the user's data that already survives losing the phone. See [ADR-0020](adr/ADR-0020-ingesta-de-tasas-sin-servidor.md).
_Avoid_: "rates API", "rates backend" (nothing is served — a static file is published).

**Liquidation Value vs BCV Value ("the parallel values, the BCV informs")**
Two readings of the same native balance. **Liquidation value** = balance at the **parallel** rate: what you would actually obtain by converting today — it is the only rate that enters net worth and unrealized P&L. **BCV value** = balance at the official rate: "sticker" purchasing power against formally-priced goods — shown as a labeled reference, never summed into net worth. The **executed** rate of past operations participates in neither; it lives frozen in the ledger as real cost. See [ADR-0016](adr/ADR-0016-tasas-manuales-valoracion-patrimonio.md).
_Avoid_: averaging or mixing both rates into a single figure.

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

**Reconciliation**
The recurring ritual of declaring an Account's real native balance and bringing the ledger to it. The difference between real and projected is the **Reconciliation Delta**; what happens to it depends on its size, never on its sign alone. See [ADR-0019](adr/ADR-0019-conciliacion-enrutada.md).
_Avoid_: "sync" (nothing is fetched — the user declares the balance), "correction" (a Reversal is the correction of a mistake; a Reconciliation absorbs an unexplained difference).

**Reconciliation Tolerance**
A single USD-denominated threshold that decides whether a Reconciliation Delta is **absorbed** (posted straight to the Adjustments system envelope, one touch) or **routed** (the app offers to record the real movement the delta implies — an Income above, an Expense below). It governs friction only: declining the routed capture still absorbs. Denominated in USD so it does not rot with bolívar inflation.
_Avoid_: confusing it with the rejected disposal threshold of [ADR-0017](adr/ADR-0017-sobregiro-registrable.md), which would have changed what gets posted.

**Funding Target**
A typed, optional funding target for a user Envelope (`role == none`); sealed class `FundingTarget` with three variants:
- `NoTarget` — no target (default).
- `Cap(amountUsd)` — spending cap in USD cents; the cascade engine's `fill-to-cap` step reads it.
- `GoalLine(amountUsd, dueDate?)` — savings progress marker in USD cents; read by Patrimony (S2), never enforced by the engine.
Serialized inside the existing `meta` JSON column of the Envelope catalog row — zero Drift migration.
_Not to be confused with_ `EnvelopeTarget` in `domain/posting_target.dart`, which is the posting dimension identifying the envelope side of a ledger entry.
See [ADR-0015](adr/ADR-0015-cascada-distribucion.md) §C2-2.

**Cascade**
The user's single, ordered plan for distributing the Stage Envelope's balance into other Envelopes. Stored as last-write-wins config (not event-sourced), edited as one document. Running it produces a Distribution Proposal. See [ADR-0015](adr/ADR-0015-cascada-distribucion.md) §C2-3.

**Cascade Step**
One ordered entry in a Cascade, targeting a user Envelope with a funding type: `fixed` (a fixed USD amount, **accumulates** month over month), `fill-to-cap` (tops up only to the Envelope's `Cap`, does **not** accumulate), `percentOfRemainder` (a percentage of the remaining — or gross — amount), or `catchAll` (everything left; at most one, must be last). The funding type is **independent** of the Envelope's Funding Target marker. See [ADR-0015](adr/ADR-0015-cascada-distribucion.md) §C2-4/§C2-7.

**Distribution Proposal**
The Cascade engine's output: a previewable, per-Envelope list of allocations for a given amount, before anything is posted. Applying it becomes a single self-balancing Distribution transaction (`Σ = 0`); steps can be skipped before applying. See [ADR-0015](adr/ADR-0015-cascada-distribucion.md) §C2-6.

**Sobregiro (overdraft)**
The legal ledger state in which an Account's native balance goes negative after a disposal exceeds what the app knew it had. Not an error — the domain never rejects a real disposal. It signals a missing income entry, surfaced in the UI (Patrimony, Accounts) rather than hidden. The excess portion (beyond the known balance) gets no frozen Average Base Cost; it is valued at the disposal's own execution rate, posting **zero differential** on that portion — the ledger declares ignorance instead of inventing a gain or loss. Reconciliation (C3) is what later reconstructs the history once the missing income appears. See [ADR-0017](adr/ADR-0017-sobregiro-registrable.md).

**Observed Counterparty**
The USD side of an operation that actually happened and was seen: the USD received in a P2P sale, the USD handed over in a purchase of Bs, the proceeds of a crypto sale. When it exists, it **is** the frozen `amount_usd` — no rate is consulted and none is divided. Its absence (spending Bs, receiving Bs as income, the excess of a same-currency transfer) is what triggers Valuation from the Series. See [ADR-0018](adr/ADR-0018-valoracion-sin-contraparte-observada.md).

**Valuation from the Series**
The rule for freezing real cost when there is no Observed Counterparty: `amount_usd` comes from the latest **parallel** Rate Observation of that currency. It does not contradict "the parallel values, the BCV informs" — when no rate was ever executed, the liquidation rate *is* the real cost; any other figure would be invented. The app always announces which rate it froze and its date, and warns when the observation is not from today. See [ADR-0018](adr/ADR-0018-valoracion-sin-contraparte-observada.md).
_Avoid_: treating it as an overlay valuation — this one **is posted** and frozen forever.

**Debt Account**
A Catalog Account whose balance is what one person owes the user. **One type, sign tells the story**: positive = they owe you (asset), negative = you owe them (liability) — a debt can cross zero freely (Splitwise-style back and forth); "receivable/payable" are readings of the sign, never two account types. To the ledger and the engine it is an Account like any other — same postings, same invariant, signed net-worth participation. The **person exists only as the account's counterparty label**, never as a domain entity. The debt is denominated in the **agreed currency** — the account's native currency, chosen per debt: "you owe me the dollars" → USD account; "you owe me the bolívares" → VES account, revalued by the overlay and realizing its differential on collection like any VES account. One person owing in two currencies = two Debt Accounts; the UI groups them under the person. The UI segregates Debt Accounts from liquid accounts (own section, own screen); they never appear mixed with cash/bank listings. See ADR-0005 (Debts = read-only projection).
_Avoid_: "Persona/Contact" as an entity (does not exist); confusing with the income `source` tag (free-text client label, a different concept).

**Backup File**
The single portable file that carries everything needed to rebuild the user's state on a clean device: the Domain Event log, the Catalog, the Cascade and the Rate Observations. Plaintext and open by design (principle 9, no lock-in) — it is the one artifact that deliberately leaves the device unencrypted, so the app warns at the moment of sharing. See [ADR-0021](adr/ADR-0021-respaldo-portable-en-claro.md).
_Avoid_: "export" unqualified (it collides with the Spreadsheet Export, which restores nothing).

**Restore**
Reading a Backup File into a device. Idempotent by `EventId` and last-write-wins on config, so restoring onto a device that already holds data adds only what is missing — it never duplicates and never overwrites something newer. All-or-nothing: a file with one unreadable line is rejected whole, naming the line.
_Avoid_: "sync" (nothing negotiates with a server — a file is read), "merge" (no conflict is resolved by the user).

**Cloud Copy**
The user's Backup File kept, one per device, in a folder of the user's **own** cloud storage (Google Drive's app-private folder first). Cuentaria runs no server and holds no account: the app writes its device's file there and reads the other devices' files with a Restore. A device that never connects a cloud works exactly as before — the Cloud Copy is optional, and the manual Backup File remains the lock-in-free exit. See [ADR-0023](adr/ADR-0023-copia-en-la-nube-del-usuario.md).
_Avoid_: "sync engine", "push/pull" (no deltas, no cursors — whole files), "our server", "login" (the user signs in to their cloud, not to us).

**User Flow**
A movement that changes what the user owns or owes against the outside world: an Expense, an Income, or their Reversal. A movement whose every leg touches only the user's own pockets (Transfer, Distribution, Conversion, Opening) or a System Envelope (Adjustment, Exchange Differential) is **not** flow. The rule reads the **role of the envelope touched**, never the event type, so future event types inherit it. Reports of flow are always stated in frozen Real Cost (USD), never in native currency and never revalued. See [ADR-0024](adr/ADR-0024-reportes-en-costo-real.md).
_Avoid_: "expense" for a reconciliation Adjustment (an absorbed delta is not something the user bought); "income" for a realized Exchange Differential.

**Report Month**
The single time unit of every report: one calendar month, cut at the device's local midnight, compared against the previous whole month. Monthly series (Net Worth, Exchange Differential, Funding Target contributions, Debt balances) carry one point per month, the last twelve. A Reversal counts in the month of the movement it reverses, so history does not move when a mistake is fixed later.
_Avoid_: "last 30 days", "custom range" (rejected — see ADR-0024).

**Net Worth Point**
The value of a Report Month's end in a monthly series: the ledger replayed up to that instant (a Projection, never a stored snapshot) valued by the Rate Resolution Chain **as of** that date. Real Cost always exists; the Overlay is blank for a currency with no Rate Observation at or before that date — the gap is shown, never interpolated. A stale rate is used and announced, as in Valuation from the Series.
_Avoid_: "snapshot" (nothing is persisted), "backfill".

**Spreadsheet Export**
The disposable CSV for humans: one row per **Posting**, never read back by the app. Regenerable from a Backup File at any time. Its unit is the Posting and not the transaction because a single Ledger Transaction can touch one Account and several Envelopes at once.
_Avoid_: treating it as a backup — it cannot restore.

## Relationships

- A **Command** on an **Aggregate** produces one or more **Domain Events**.
- **Projections** are derived from the **Domain Events** log + **Observed External Facts**.
- The **Domain Core** depends on **Ports**; the **Adapters** depend on the core (dependency inversion).

## Resolved Ambiguities

- "Backend" was used for two things: the **domain core** (lives in the client) and the **sync/integration infra** (Supabase + workers). Resolved as distinct concepts.
- "Event sourcing everywhere" was refined: append-only everywhere, but **two archetypes** (domain event vs observed external fact). See [ADR-0002](adr/ADR-0002-append-only.md).

## Hard Rules (Money & Rates)

1. **Dinero y tasas:** Enteros o `Decimal`, jamás `double` — ni en firmas, proyecciones, ni tests.
2. **Convención de Tasa:** La tasa es siempre **native-por-USD** (como se cotiza el dólar en Bs); valor USD = `round(native / tasa)` con un único redondeo. Conversiones observan montos, no dividen.
3. **Qué es "native" en un par:** el lado **no-USD** del par, sea origen o destino. La etiqueta de una tasa se deriva del rol de cada cuenta, jamás de su posición en la operación (entregado/recibido). Ver [ADR-0018](adr/ADR-0018-valoracion-sin-contraparte-observada.md).
