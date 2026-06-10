# ADR-0002 — Append-only across the system, with two event archetypes

**Status:** accepted (2026-06-09)

All storage is **append-only** (uniform audit and *time-travel*), but **two archetypes** are distinguished:

1. **Domain event (command-sourced):** Accounting/Cash, Debts and Distribution use **true event sourcing** — aggregate, command, invariant validation and projections. The ledger is a log of immutable events; *Reconciliation/Adjustment* is a reversal event, not an edit.
2. **Observed external fact (ingestion log, no aggregate):** Rates, market prices and on-chain balances (Binance/Ledger) are appended as immutable observations that feed projections, **without** command or invariant.

**Why:** accounting is naturally append-only (it is reversed, not deleted), which provides auditability, time-travel (report "patrimony over time") and unrealized P&L as a projection, and makes **multi-device merge trivial** (two logs merge by event order). However, adding aggregate/command ceremony to data that is only *observed* (rates, prices) would be overhead with no return.

**Sync primitive:** push/pull of the event log to Supabase Postgres; merge by event order. **Mutable config** (Envelope metadata, settings) uses *last-write-wins* per row.

**Read models / projections:** balance by Account, balance by Envelope, cash flow by source/client, Envelope progress vs. target — all recomputable from the log.

**Consequence:** we assume the cost of maintaining projections and versioning the event schema.
