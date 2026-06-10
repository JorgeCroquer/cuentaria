# ADR-0010 — Unified model for Envelope targets/contributions

**Status:** accepted (2026-06-09)

An Envelope can be funded by one or several cascade rules: **recurring fixed contribution that accumulates** (savings, no cap), **fill-to-target with cap** (expense), and/or **% of remainder**. The **target is optional** and polymorphic based on the envelope's role:

- **Expense** envelope → the target is a **cap** (working limit for the period).
- **Savings** envelope → the target is a **goal line** by **amount or date**: measures progress and suggests quota, but **does not limit growth**.

**Why:** an Envelope is sometimes an expense bucket and sometimes a piggy bank; the system supports both instead of imposing one. Reconciles real practice (accumulating contribution) with a capped expense budget. Matches the three cascade step types.

**Shortfall handling (lean month):**

1. *Not enough to contribute:* the **ordered cascade with preview + skip** fills essentials first; savings contributions (lower down) receive less or nothing due to lack of remainder. **It never goes negative**; non-existent money is not forced.
2. *Need to spend more than what came in (pull from savings):* done via a **Distribution** transaction that **retags** from the savings Envelope to the Envelope that needs it — real money doesn't move, only intent; the invariant `Σ Accounts == Σ Envelopes` remains intact. Then the normal Expense is recorded.

**Consequence:** `Envelope.target` is modeled as a value object with discriminator `{none | cap | goal_line(amount|date)}` and `Envelope` references its cascade contribution rules.
