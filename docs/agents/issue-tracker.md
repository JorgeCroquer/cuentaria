# Issue Tracker: GitHub

This repo tracks issues in **GitHub Issues** via the `gh` CLI.

## Workflow rules for agents

1. **Reading/searching:** Use `gh issue list` and `gh issue view <n>`.
2. **Creating:** Use `gh issue create`. Always use the templates if they exist in `.github/ISSUE_TEMPLATE/`.
3. **Updating:** Use `gh issue edit` or `gh issue comment`.

When creating issues, ensure you link them properly to any PRDs or parent tracking issues.
