---
name: review-pr
description: Run a two-axis code review (Standards + Spec) on an open GitHub PR and post findings as inline review comments with suggested changes — like GitHub Copilot Review. Use when the user says "review PR", "review and comment", "leave comments on PR", "copilot-style review", or wants review findings posted directly to GitHub.
---

# Review PR (with GitHub Comments)

Runs `/review` against a GitHub PR, then posts every finding as an inline review comment with severity and suggested changes where applicable.

## Process

### 1. Identify the PR

Accept a PR number, URL, or nothing (defaults to current branch):

```bash
gh pr view --json number,headRefName,baseRefName
```

Resolve `{owner}/{repo}` and `{pr_number}`.

### 2. Fetch PR metadata & diff

```bash
gh pr view {pr_number} --json title,body,baseRefName,headRefName,commits
gh pr diff {pr_number}
```

The `baseRefName` is the fixed point for `/review`. Keep the full diff in context — you need it for line resolution and to generate suggested changes.

### 3. Run the two-axis review

Invoke `/review` with the base branch as fixed point. **Augment the sub-agent prompts** with these additional instructions:

> For each finding, you MUST include:
> 1. **Severity**: `High`, `Medium`, or `Low` (see Severity Criteria below).
> 2. **Exact file path and line range** from the diff.
> 3. **Suggested fix as code** — if the fix is mechanical and unambiguous (renaming, adding a guard clause, fixing an import, correcting a type), write the corrected code verbatim. If the fix requires a design decision or is ambiguous, describe what should change but do NOT write code.

Collect findings from both sub-agents.

### 4. Build review comments

For each finding, construct a comment object:

**With suggested change** (fix is mechanical):

```markdown
**[Standards]** `High`

AircraftSnapshot constructor will throw on missing fields, returning a 500 instead of a controlled 400/422.

> Rule: Error handling must produce controlled HTTP responses (CLAUDE.md §error-handling)

```suggestion
      if (!aircraftData || !aircraftData.capacity || !aircraftData.operator || !aircraftData.cruiseSpeed || !aircraftData.tailNumber) {
        throw new ValidationException(
          `Incomplete aircraft data for id ${aircraftId}. Missing required fields.`,
        );
      }
```
```

**Without suggested change** (requires design decision):

```markdown
**[Spec]** `Medium`

The PRD requires rate limiting on this endpoint, but none is implemented. This likely needs a decorator or middleware — not a simple inline fix.

> Spec: "All public endpoints must enforce rate limiting" (PRD §3.2)

💡 Consider adding `@Throttle()` decorator or a global guard. Check with Jorge on the preferred approach.
```

### 5. Map line numbers to the diff

The GitHub Reviews API requires lines that **exist in the PR diff** (right side).

- For single-line comments: use `line` (the line number in the new file).
- For multi-line comments (needed for `suggestion` blocks): use `start_line` + `line` to define the range the suggestion replaces.
- If a finding references code not in the diff, put it in the review summary body instead.

### 6. Post the review

Build a single `gh api` call. The event depends on findings:

| Findings | Event |
|---|---|
| Any `High` severity | `REQUEST_CHANGES` |
| Only `Medium`/`Low` | `COMMENT` |
| No findings | `APPROVE` |

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews \
  --method POST \
  -f event="{EVENT}" \
  -f body="## Claude Code Review — PR #{pr_number}

{total} findings ({high}H {medium}M {low}L). Worst: {worst_issue_summary}

{general_findings_not_tied_to_lines}" \
  --input comments.json
```

Where `comments.json` is an array:

```json
[
  {
    "path": "src/foo/handler.ts",
    "start_line": 40,
    "line": 52,
    "side": "RIGHT",
    "body": "**[Standards]** `High`\n\n..."
  }
]
```

For single-line comments, omit `start_line`.

### 7. Report back

Output:
- Link to the review on GitHub
- Count: `N inline comments (X with suggestions), M general findings`

## Severity criteria

| Level | Meaning | Examples |
|---|---|---|
| **High** | Bug, security issue, or hard violation of a documented standard | Unhandled exception leaks 500, SQL injection, wrong HTTP class in wrong layer |
| **Medium** | Correctness risk or partial spec implementation | Missing validation, incomplete error message, spec requirement only half done |
| **Low** | Style, naming, minor convention deviation | Inconsistent naming, missing JSDoc, import order |

## Edge cases

- **No open PR**: Offer to run `/review` without posting.
- **Line not in diff**: Move finding to review summary body.
- **No findings**: Post `APPROVE` with body "✅ No issues found on either axis."
- **Draft PR**: Post anyway — GitHub allows review comments on drafts.
- **Suggestion spans lines not in diff**: Fall back to descriptive comment without `suggestion` block.