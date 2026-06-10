# ADR-0001 — Client-authoritative, offline-first domain

**Status:** accepted (2026-06-09)

The authoritative domain (the one that guarantees invariants, e.g. `Σ Accounts(USD) == Σ Envelopes(USD)`) runs **in the Flutter client** as pure Dart packages (hexagonal/DDD/CQRS). The local store (SQLite/Drift) is the **source of truth**; Supabase Postgres acts as a destination for **sync + backup**, not as a backend with logic. Integrations (Binance, rates, on-chain) run in **minimal serverless workers**.

**Why:** it's a **single-user** app with a need for **mobile offline capture**. A client-resident domain is the cheapest (no always-on server), makes offline-first natural, and keeps the domain pure and portable.

**Rejected alternatives:**

- **Server-authoritative (own monolith):** More "textbook" DDD and more direct separation to microservices, but demands almost-always-on hosting (not free-forever) and *even then* requires a sync layer for offline. Rejected due to cost and for not adding value to a single-user MVP.
- **Supabase-as-backend (logic in PostgREST/RLS/edge):** Cheaper infra and faster MVP, but disperses the domain in SQL/RLS, making it untestable and hard to split. Rejected for breaking hexagonal/DDD/CQRS.

**Consequence:** "ready for microservices" today means **module hygiene** (bounded contexts as Dart packages with explicit boundaries), not deployed topology. Hoisting a module to a server is enabled future work, not done work.
