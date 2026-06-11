# Triage Labels

This repo uses the default triage vocabulary.

When moving an issue through the triage state machine (e.g. using `gh issue edit <n> --add-label <label>`), use exactly these strings:

| Role | Label string | Description |
|------|--------------|-------------|
| Needs evaluation | `needs-triage` | A maintainer needs to look at this to decide if it's a real issue, a duplicate, or out of scope. |
| Waiting on reporter | `needs-info` | We asked the reporter a question and are waiting for their reply. |
| AFK-ready | `ready-for-agent` | Fully specified with all context. An agent can pick this up and implement it without asking humans for more context. |
| Needs human | `ready-for-human` | Requires human implementation or human design decisions. Agents should skip these. |
| Will not action | `wontfix` | We are not going to do this. |

## Type labels

Use these to distinguish issue hierarchy. Every issue should have exactly one type label.

| Type | Label string | Description |
|------|--------------|-------------|
| PRD | `prd` | Product Requirements Document — parent issue for a feature. Filter with `label:prd` to see only top-level features. |
| Sub-issue | `sub-issue` | Vertical slice / tracer bullet of a parent PRD. Filter with `label:sub-issue` to see only implementable work items. |

**Filtering tips (GitHub UI):**
- See only PRDs: `is:issue is:open label:prd`
- See only sub-issues: `is:issue is:open label:sub-issue`
- See sub-issues ready for an agent: `is:issue is:open label:sub-issue label:ready-for-agent`
