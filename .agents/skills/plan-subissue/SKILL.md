---
name: plan-subissue
description: >
  Bootstrap a git branch and produce a deep implementation plan for a
  technical subissue from the project issue tracker, designed for handoff
  to an executing agent. Use when user says "plan subissue",
  "implement subissue", "pick up XXX-YYYY", or provides a
  subissue + parent PRD pair.
---

# Plan Subissue

Takes a subissue ID and parent PRD ID. Produces a git branch and a detailed `implementation_plan.md` ready for a (potentially different, less capable) agent to execute with `/tdd` and `/caveman`.

> **Hard rule**: Every behavior introduced by this subissue MUST be covered by a test following `/tdd` skill. The plan is the contract — if a behavior isn't in the TDD Sequence, the executing agent won't test it. Plan accordingly.

## Prerequisites

Before starting, read `docs/agents/issue-tracker.md` to learn:

- Which **issue tracker** is configured (Linear, Jira, GitHub Issues, etc.)
- The **CLI tool and commands** to fetch, create, and update issues
- The **issue ID format** used by this project (e.g. `DEV-XXX`, `PROJ-123`)
- The **issue URL pattern** for linking (e.g. `https://linear.app/...`, `https://jira.example.com/browse/...`)

All issue operations below (fetch, link, branch naming) MUST use the tracker, CLI, ID format, and URL pattern from that doc — never hardcode a specific tool or prefix.

## Process

### 1. Fetch issues

Fetch both the subissue and the parent PRD using the CLI commands documented in `docs/agents/issue-tracker.md`.

Read both fully. The PRD contains implementation decisions, user stories, and testing decisions that scope the subissue.

### 2. Detect branch state and create branches

Run `git branch --show-current`.

**On `main` or `dev`** (first subissue of this PRD):

1. Check `git diff` for pending changes in `CONTEXT.md`, `CONTEXT-MAP.md`, `docs/adr/`. If related to this PRD, stage and commit: `chore(docs): update domain context before {parentId}`. If unsure whether related, ask the user. Ignore unrelated changes.
2. Create parent feature branch from current: `git checkout -b {prefix}/{parentId}-{slug}`. Push it.
3. Create sub-branch: `git checkout -b {prefix}/{subissueId}-{slug}`.

**On a branch matching `*/{parentId}-*`** (continuing PRD):

1. Pull latest: `git pull origin {currentBranch}`.
2. Create sub-branch: `git checkout -b {prefix}/{subissueId}-{slug}`.

**On any other branch**: Ask the user which branch to start from.

Branch naming: choose `feat/`, `fix/`, `refactor/`, or `chore/` based on the subissue's nature. Derive a concise, meaningful slug from the issue title. Use the issue ID format from the tracker doc (lowercased) in the branch name.

### 3. Explore the codebase

Focused exploration — don't boil the ocean:

1. Read `CONTEXT.md` and relevant ADRs in `docs/adr/`
2. Identify which module(s) the subissue touches from the PRD's implementation decisions
3. For each affected module, read:
   - Domain layer (aggregates, value objects, domain services)
   - Ports (repository interfaces, external service interfaces)
   - At least one adapter as a pattern reference
   - Existing tests for conventions and style — pay special attention to test structure, naming, and what's being tested (behavior through public interfaces, NOT implementation details)
4. For **new** modules: find the closest existing module as a structural template
5. **Identify test patterns**: Note the test file locations, naming conventions, test helpers, and factories used in existing tests. The executing agent will follow these patterns exactly.

If domain terms in the subissue conflict with `CONTEXT.md`, flag them in the plan's Open Questions — do NOT edit `CONTEXT.md`.

### 4. Produce the implementation plan

Create `implementation_plan.md` as a platform artifact (`RequestFeedback: true`).

<plan-template>

# [Subissue title] ({subissueId})

Parent: [{parentId}]({parentIssueUrl})

[1-2 sentences: what this subissue accomplishes in the context of the parent PRD.]

## Open Questions

Ambiguities, domain term misalignments, or decisions needing user input before implementation starts.

## Scope Boundaries

**In scope:** What this subissue delivers — be specific.
**Out of scope:** What it does NOT touch — prevents executing agent from scope creep.

## Proposed Changes

Group by component. For each file:

### [Component Name]

#### [NEW/MODIFY/DELETE] [filename](file:///absolute/path)

- What changes and why
- Interface shapes as TypeScript snippets
- Pattern to follow: "see [existing-file](file:///path) for reference"

## TDD Sequence

> **This section is mandatory and must be exhaustive.** Every file in Proposed Changes that introduces or modifies behavior MUST have at least one corresponding TDD step below. If a proposed change has no test step, either add one or justify why it's untestable (infrastructure glue, config, etc.).

Dependency-ordered vertical slices. Each step is one RED→GREEN cycle. The executing agent MUST use `/tdd` and follow these steps in order — no skipping, no writing implementation before its test.

1. **[Behavior under test]**
   - **Test**: Describe the assertion in plain language — what the test proves about the system's observable behavior through its public interface.
   - **Implement**: What minimal production code makes this test pass.
   - **Reference**: Link to an existing test file the executing agent should use as a pattern: `see [existing-test](file:///path)`.

2. **[Next behavior]**
   - **Test**: ...
   - **Implement**: ...
   - **Reference**: ...

### TDD Quality Checklist

Before finalizing the plan, verify every TDD step against this checklist:

- [ ] Tests verify **behavior through public interfaces**, not implementation details
- [ ] Tests would **survive an internal refactor** without breaking
- [ ] No test directly queries the database, mocks internal collaborators, or tests private methods
- [ ] Happy path AND relevant error/edge cases are covered
- [ ] Each step is a **vertical slice** (one test → one implementation), not a horizontal batch
- [ ] The sequence follows **dependency order** — earlier steps don't depend on later ones

## Verification Plan

- Exact test commands (`npx jest --testPathPattern=...`)
- Expected pass counts — be specific (e.g., "6 tests in 2 suites")
- **All tests must pass before the PR is created**
- Manual verification steps if applicable (e.g., API smoke tests)

</plan-template>

Note: `{subissueId}`, `{parentId}`, and `{parentIssueUrl}` are placeholders — replace them with real values from the issue tracker using the ID format and URL pattern found in `docs/agents/issue-tracker.md`.

## What happens next

After the user approves the plan:

1. **Implement** — invoke `/tdd` and `/caveman`. The executing agent MUST follow the TDD Sequence strictly: write the test FIRST, see it fail (RED), then write minimal code to pass (GREEN). No production code without a failing test first. No skipping steps.
2. **Commit** — invoke `/commit-generator`
3. **Create PR** — invoke `/pr-generator` targeting the parent feature branch

> [!CAUTION]
> If the executing agent writes production code without a corresponding test, or writes all tests first then all implementation, it is violating this plan. Every behavior must go through RED→GREEN.
