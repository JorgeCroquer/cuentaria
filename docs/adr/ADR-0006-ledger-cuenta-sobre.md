# ADR-0006 — Account × Envelope Ledger

Two independent dimensions, self-balancing transaction, real cost + valuation overlay.

**Status:** accepted (2026-06-09)

**Structural model.** Two **independent** dimensions (not a joint `cell[Account][Envelope]` matrix). Two marginal vectors are projected: balance by **Account** and balance by **Envelope**, which share a grand total. We do not track what portion of an account belongs to which envelope (an envelope can live distributed across several accounts; the invariant is only on the totals).

**Golden rule — self-balancing transaction.** Every transaction (domain event) must fulfill by itself:
`Σ postings.usd[Account dimension] == Σ postings.usd[Envelope dimension]`.
The domain **rejects** transactions that do not fulfill this. Because each transaction preserves the invariant separately, **any merge order of transactions preserves it by induction** → offline multi-device merge is safe by construction. This is the piece that makes event sourcing + offline + invariant fit together.

Effect by type: Income (+X,+X) · Expense (−X,−X) · Transfer (−X+X in Accounts, 0 in Envelopes) · Distribution (0 in Accounts, moves between Envelopes) · P2P/FX Conversion (−X USD Account, +X USD valued-Bs Account; 0 in Envelopes) · Reconciliation and realization (δ in Account and δ in an "Adjustments" type Envelope).

**Event shape.** Transaction = immutable event with `type`, metadata (`occurred_at`, `recorded_at`, `device_id`, `source`, `schema_version`) and `postings[]`. Each posting:
`(dimension: Account|Envelope, target_id, amount_native, currency, amount_usd, rate_ref?)`.

**Frozen real cost.** `amount_usd` is **snapshotted** at the time of the transaction (what actually entered/left) and is not recalculated. `rate_ref` points to the rate fact used, for the optional BCV differential field.

**Market valuation = read-only overlay.** The ledger is kept at **real cost**; the invariant is fulfilled at base cost. The **current value** and the **unrealized P&L** are calculated on the fly in Patrimony/Portfolio (`quantity × current rate/price` from the Rates series), **without posting** transactions. Only when **realizing** (Bs→USD at new rate, crypto sale, spending Bs) is the real transaction posted that materializes the difference. Shown net patrimony = ledger balances + overlay; the difference IS the unrealized P&L.

**Rejected alternative:** periodically posted valuation events — they inflate the log and mix unrealized with real movements.

**Source/client tag.** Income transactions carry `source` (client) as a dimension → enables the cash flow projection by client.

**Level 2 Portfolio preparation.** Postings/holdings capture `instrument_id`, `quantity` and append-only acquisition events from the MVP, even if Level 1 only uses current valuation. This way Level 2 (PNL/cost basis per lot) is computed later without rewriting, wherever data exists.

**Projections (read models) derived from the log:** balance by Account · balance by Envelope · patrimony over time · cash flow by source/client · expense by envelope/category · Envelope progress vs target · debt balance per person · captured exchange differential.
