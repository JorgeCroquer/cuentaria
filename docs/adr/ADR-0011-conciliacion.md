# ADR-0011 — Operational reconciliation: configurable tolerance governs friction

**Status:** accepted (2026-06-09)

**"Reconciled":** an Account is reconciled at T if its ledger balance == real balance within a **tolerance**. The real balance is **proposed by integration** in accounts with API (ADR-0008) or **declared by the user** in VE banks/cash.

**Behavior:** reconciling **always brings the ledger to the real balance** via Reconciliation/Adjustment event (Account + "Adjustments" Envelope, self-balanced, ADR-0006), absorbing the buffer from conservative rounding habits. **Tolerance governs friction, not whether it adjusts**:

- difference **within tolerance** → one-touch / auto-accepted reconciliation;
- difference **outside tolerance** → **prompts for review** first (perhaps a real movement was missed instead of absorbing it).

**Configurable tolerance:** per Account, with a **global default overridable** by each Account (e.g. Bs: round to integer / small threshold; USD: ~$0.50).

**Rhythm and reminders:** **cadence per Account** (weekly for heavy use like BdV; monthly for cold/low use) + on-demand; each Account tracks `last_reconciled`. **Gentle** reminder: badge/list of "accounts to reconcile" based on cadence and last reconciliation date; optional notification, no nagging (discipline is the risk).

**Why:** aligns with *honest automation: fewer actions, not zero* (principle 6) and *reconciliation as ritual* (principle 8), without imposing friction on daily rounding.
