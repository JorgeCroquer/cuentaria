# ADR-0008 — Integrations: observed facts propose reconciliation, never write to the ledger

**Status:** accepted (2026-06-09)

**Pattern:** each Provider has an **optional** sync adapter behind a port (polymorphic, principle 5). Workers are dumb (ADR-0003/0004) and everything external enters as an **observed fact** (ADR-0002).

**Interaction with the ledger (key decision):** when an observed balance (e.g. Binance Funding) differs from the ledger balance, the worker **never writes to the ledger**. It appends the fact; the client shows the **diff** and offers a **one-touch reconciliation** that posts the Reconciliation/Adjustment event (Account + "Adjustments" Envelope, self-balanced). The user confirms.

**Why:** respects *client-authoritative* (ADR-0001), *reconciliation as ritual* (principle 8) and *honest automation: fewer actions, not zero* (principio 6). Avoids erroneous adjustments due to partial/temporary API reads.

**Secrets:** **read-only** API keys (Binance read without withdrawal permissions, Splitwise token, PayPal OAuth) in **GitHub Actions encrypted secrets**, never in the client.

**MVP Scope for integrations (roadmap, not architecture):** (1) Binance read + Rates first; (2) on-chain/Ledger (public addresses + explorers + prices) and Splitwise (net balance per person → adjustment to receivable/payable account) next; (3) PayPal manual for now (partial API). Splitwise and PayPal with OAuth callback could motivate adopting Cloud Run (deferred in ADR-0004).
