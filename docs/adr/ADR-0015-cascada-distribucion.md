# ADR-0015 — Distribution cascade: ordered plan as config, total engine

**Status:** accepted (2026-06-23) — **refines [ADR-0010](ADR-0010-metas-sobres.md)** on where cascade rules live; does not supersede its target/shortfall model.

C2 turns ADR-0010's funding rules into a runnable engine over C1's Distribution transaction. The engine is a **pure function** `(amount, cascade, envelopeStates) → DistributionProposal`; a thin orchestrator applies an accepted proposal via C1's `RecordDistribution`. Four points ADR-0010 left implicit are fixed here.

## 1. The cascade is a single ordered plan, held as LWW config — not per-envelope rules

ADR-0010's consequence line said *"Envelope references its cascade contribution rules."* We refine that: the cascade is a **single ordered list of steps** (list position = priority), owned by its own `CascadeRepository`, stored as **last-write-wins config** (like the catalog, C1-2), **not** event-sourced. Only the *application* of the cascade produces a Distribution (the domain event, C1).

**Why:** a cascade is intrinsically ordered (essentials → savings → catch-all); an ordered list models priority gap-free and reorderable, where per-envelope priority indices scatter one plan across rows and need renumbering and tie-breaking. The catch-all is a single terminal step, with no home as a per-envelope rule. The plan is editable *intent*, not an accounting fact — its history is irrelevant to the ledger invariant, so it is config, not an event. Exactly **one** cascade in the MVP; named templates ("normal month", "bonus") are deferred (Fase 3+) = add a name + id later.

## 2. Funding (step type) is independent of the Envelope Target marker

An Envelope's **funding** — `fixed` (contributes the same each run, so it **accumulates** a buffer when underspent), `fill-to-cap` (tops up to a ceiling, **never** accumulates beyond it), `% of remainder`, `catch-all` — is **orthogonal** to its **Envelope Target** marker (`none | cap | goal_line`). An expense Envelope can be funded by a fixed accumulating contribution (real practice: a $300/month groceries Envelope that builds a cushion drawn on in lean months). ADR-0010's role→rule pairing ("expense→cap, savings→goal_line") is a default, not a constraint. `cap` is a target **balance** with **roll-over** (no period/reset machinery); only the `fill-to-cap` step reads it. `goal_line` is a progress marker read by Patrimony (S2), never by the engine.

## 3. The engine is total; validation is edit-time

The pure engine **never throws**: it processes any cascade, degrading gracefully (missing/archived target → skip the step; `fill-to-cap` without a cap → contributes 0; misplaced catch-all → later steps get 0 from `remaining == 0`). Real validation (at most one catch-all and it must be last; `fixed > 0`; percent in `(0, 1]`; target exists, is a user Envelope, not archived) lives in `application/` at **edit time** — never as a hard domain gate.

**Why:** the cascade is config that syncs LWW; a plan arriving before the Envelope it references must not be rejected by arrival order (same reasoning as C1-2's application-layer referential integrity). This keeps multi-device merge safe and `domain/` untouched — **C2 lives entirely in `application/`** (+ one infra adapter for the repository).

## 4. Lean-month falls out of ordering; the engine is USD-pure

A single `remaining` counter consumed in priority order, with a universal `min(allocated, remaining)` clamp, makes the shortfall case (ADR-0010 #1) **emergent**: the savings steps at the bottom simply receive less or nothing, nothing ever goes negative, no special case. The `% of remainder` base is a **calibration knob** (`base: remainder | gross`, default `remainder`) so the gross-percent variant can be A/B-tried by flipping an enum, without a rewrite. Envelope balances and Distribution postings are USD, so the engine has **no Rates (S1) dependency**.

**Rejected alternatives:**

- **Per-envelope rules + priority index** (ADR-0010's literal wording) — scatters one ordered plan across rows, needs renumbering/tie-breaking, and has no home for the catch-all.
- **Cascade as an event-sourced log** — the plan is mutable intent, not an accounting fact; event-sourcing it inflates the log and buys nothing the ledger invariant needs.
- **Engine validates/rejects malformed cascades** — would let a synced config blow up by arrival order; breaks the merge-safety doctrine (C1-2).
- **Period/reset machinery for caps** — adds a time concept to C2; roll-over + the `fixed` step already deliver both the "ceiling" and the "cushion" disciplines.

## Consequence

- C2 = pure engine + value objects (`Cascade`, `CascadeStep`, `DistributionProposal`, `FundingTarget`) + `CascadeRepository` (Drift + in-memory, contract-tested) + a thin orchestrator, all in `contabilidad/application/`. `domain/` is untouched; no new bounded context.
- `FundingTarget` (sealed: `NoTarget | Cap | GoalLine`) rides in the existing `meta` JSON column — no Drift migration. Not to be confused with `EnvelopeTarget` in `domain/posting_target.dart` (posting dimension).
- The orchestrator runs the engine over the **Stage** balance (explicit `amount`, default = current Stage, guarded `≤ Stage`), previews a `DistributionProposal` (per-application skippable steps), and applies it via C1's `RecordDistribution`; residue without a catch-all stays in Stage.

### Addendum (2026-07-25, slice 3 #96) — Apertura as an alternate source

The orchestrator (`DistributeFromStage`) also accepts Apertura (`EnvelopeRole.opening`) as the source envelope via a `sourceRole` parameter on `preview`/`apply`/`applySkipping` — same cascade, same preview/skip/apply mechanics, just reading and debiting a different system Envelope's balance. This makes opening balances distributable through the same editor and flow, with no new orchestrator, no Adjustment/reconciliation event, and no change to the invariants above: residue without a catch-all still stays in the source envelope (Apertura, in this case) rather than being force-zeroed.

Slice 3 also ships the previously-deferred cascade editor (an ordered, drag-reorderable list of steps against `CascadeRepository`), surfacing `CascadeValidator`'s existing edit-time errors — no new validation rules.
