---
name: to-issues
description: Break a plan, spec, or PRD into independently-grabbable issues on the project issue tracker using tracer-bullet vertical slices. Use when user wants to convert a plan into issues, create implementation tickets, or break down work into issues.
---

# To Issues

Break a plan into independently-grabbable issues using vertical slices (tracer bullets).

The issue tracker and triage label vocabulary should have been provided to you — run `/setup-matt-pocock-skills` if not.

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes an issue reference (issue number, URL, or path) as an argument, fetch it from the issue tracker and read its full body and comments.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Issue titles and descriptions should use the project's domain glossary vocabulary, and respect ADRs in the area you're touching.

### 3. Draft vertical slices

Break the plan into **tracer bullet** issues. Each issue is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

Slices may be 'HITL' or 'AFK'. HITL slices require human interaction, such as an architectural decision or a design review. AFK slices can be implemented and merged without human interaction. Prefer AFK over HITL where possible.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
</vertical-slice-rules>

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories this addresses (if the source material has them)

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are the correct slices marked as HITL and AFK?

Iterate until the user approves the breakdown.

### 5. Publish the issues to the issue tracker

For each approved slice, publish a new issue to the issue tracker. Use the issue body template below. These issues are considered ready for AFK agents, so publish them with the correct triage label and the `sub-issue` type label unless instructed otherwise.

**IMPORTANT**: 
1. You MUST create the issues using the `gh` CLI and link them to the PRD parent issue in the body (e.g. `Parent: #123`).
2. Add both the `ready-for-agent` and `sub-issue` labels.
   `gh issue create --title "Title" --body-file <body-file> --label "ready-for-agent" --label "sub-issue"`

> [!TIP] Obsidian Sync
> After publishing the issues, recommend the user to run `/sync-obsidian` to keep the vault updated.

Publish issues in dependency order (blockers first) so you can reference real issue identifiers in the "Blocked by" field.

### 6. Declare the signals (required — the body starts with frontmatter)

Every issue body MUST open with the frontmatter block in the template. **The orchestrator's RiskGate counts a missing key as `false`**, so an omitted key silently under-prices the slice and sends risky work to an unattended agent. Declare all seven every time; never leave one out because "it obviously doesn't apply".

| Key | `true` when the slice… |
|---|---|
| `risk_touches_multiple_modules` | changes more than 2 modules/packages |
| `risk_modifies_domain_aggregate` | changes a domain aggregate or one of its invariants |
| `risk_changes_public_interface` | changes a public API, DTO or port |
| `risk_involves_money` | touches a money, rate or fee path |
| `risk_touches_external_integration` | talks to an external system |
| `risk_has_unresolved_ambiguity` | leaves decisions **explicitly open** to the implementer (a property of the spec, auditable by reading it) |

Each signal must be declarable by reading only the spec and auditable after the fact against the delivered PR. **3 or more true → `high` → the run refuses to start** and the ticket is relabeled `ready-for-human`. That is the gate working, not a problem to massage away: if the user has deliberately ratified a high-risk slice, add `risk_approved_by_human: true`.

`verify_on_device: true` goes on **every slice a human can see on screen** — it routes the slice to a handoff for human verification instead of auto-merge. A slice that only adds tests does not carry it.

<issue-template>
---
risk_touches_multiple_modules: true|false
risk_modifies_domain_aggregate: true|false
risk_changes_public_interface: true|false
risk_involves_money: true|false
risk_touches_external_integration: true|false
risk_has_unresolved_ambiguity: true|false
verify_on_device: true|false
---

## Parent

A reference to the parent issue on the issue tracker (if the source was an existing issue, otherwise omit this section).

## What to build

A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer implementation.

Avoid specific file paths or code snippets — they go stale fast. Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it here and note briefly that it came from a prototype. Trim to the decision-rich parts — not a working demo, just the important bits.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

When `verify_on_device: true`, every criterion a human can see on screen carries **a concrete example with numbers** — the actual figure typed and the actual text expected on screen, in the user's words. The verification plan is written from these as a *do this → you must see this* table, with chained steps where each one leaves the state the next needs. Copying implementer vocabulary ("absorbs against Adjustments", "lands in Stage") produces a plan the verifier cannot read.

## Blocked by

- A reference to the blocking ticket (if any)

Or "None - can start immediately" if no blockers.

</issue-template>

Do NOT close or modify any parent issue.
