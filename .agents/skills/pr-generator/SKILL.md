---
name: pr-generator
description: Generate a polished Pull Request and create it on GitHub with `gh`, following Cuentaria's established PR format with GitHub issue linkage. Use when user says "write PR", "PR description", "generate PR", "create PR", or asks for a pull request title and body.
---

# PR Generator

## Workflow

### 1. Gather context

```bash
git branch --show-current
git log --oneline <target>..<current> --reverse
git diff <target>...<current> --stat
git diff <target>...<current>
```

- **Target branch**: Ask the user if not obvious. Common targets: `dev`, `main`, or a parent feature branch (e.g. `feat/QUEN-2434-...`).
- **GitHub issue**: Extract from branch name (e.g. `feat/123-...` → `123`). If a parent issue exists, link both.

### 2. Analyze the diff

Read every changed file and classify changes: domain/business logic, infrastructure/adapters, API surface (DTOs, controllers, routes), tests, and any bug fixes found during implementation.

### 3. Title

Format: `[#XXX] Type: Concise Description of What This PR Does`

- **Type** follows Conventional Commits: `Feat`, `Fix`, `Refactor`, `Chore`, etc.
- Imperative mood, Title Case after the type prefix, under 80 chars.
- Combine multiple concerns with `&` (e.g. a feature + a bug fix).

```
[#24] Feat: Implement isAvailableForSale in Domain & Validate in Sales
[#18] Refactor: Centralize Distributed Repository Error Handling
```

### 4. Description

```markdown
This PR addresses issue #XXX by [one-sentence summary of what
the PR accomplishes and why it matters].

## Changes Included

- **[Category]:** [Change with relevant `class`/`method` names in backticks].
  [Brief explanation of WHY, not just WHAT].

## Testing / Validation

- `[exact test command]` — X/X passed (Y new tests).
- Global linting successfully fixed.

## Related Issues

Closes #[XXX]
```

- **Opening**: one or two sentences — the issue, what the PR does, the business context. Call out any critical bug found and fixed during implementation.
- **Changes Included**: each bullet starts with a bold category label. Focus on the architectural "why"; the reviewer sees the "what" in the diff.
- **Testing / Validation**: exact test commands with pass counts and new-test counts; include linting status.
- **Related Issues**: always link the issue using `Closes #XXX` (or `Fixes #XXX`, `Resolves #XXX`) so GitHub auto-closes it when the PR merges. Link parent issues using "Parent: #YYY" if it's a subtask.

### 5. Create the PR

Present the title and body to the user and confirm before creating.

Push the branch (custom SSH hosts won't auto-push), then create:

```bash
git push -u origin <current>

gh pr create -R <owner>/<repo> --base <target> --head <current> \
  --title "<title>" \
  --body "$(cat <<'EOF'
<description>
EOF
)"
```

Derive `<owner>/<repo>` from `git remote get-url origin` and always pass it via `-R`, because the SSH alias (`git@personal:Org/repo.git`) breaks `gh`'s auto-detection:

- `git@personal:Org/repo.git` → `Org/repo`
- `git@github.com:Org/repo.git` → `Org/repo`
- `https://github.com/Org/repo.git` → `Org/repo`

Return the PR URL that `gh` prints.

## Anti-patterns

- Do NOT write generic descriptions like "Updated files" or "Made changes."
- Do NOT list every changed file — group by logical concern.
- Do NOT include implementation details that belong in code comments.
- Do NOT use past tense ("Added", "Fixed") — use present tense or noun phrases ("Add", "Fix", "Domain Encapsulation").
- Do NOT create the PR before confirming the title and body with the user.
