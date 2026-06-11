# Domain Docs: Single-context

This repo uses a **single-context layout**.

There is one global domain that applies to the entire repository.

## Where to look

- **Domain Language:** [`CONTEXT.md`](../../CONTEXT.md) at the repo root.
- **Architectural Decisions:** [`docs/adr/`](../adr/) at the repo root.

## Rules for reading

When an agent needs to understand the domain (e.g. for `tdd`, `diagnose`, `improve-codebase-architecture`):

1. **Read `CONTEXT.md` first.** This is the ubiquitous language. If the user's prompt uses a term that contradicts this file, assume the file is right and the user is being sloppy, or ask them.
2. **Read `docs/adr/` second.** If you are about to propose an architectural change, check if an ADR already prohibits it. If you want to change an ADR, propose a *new* ADR that supersedes the old one; don't overwrite history.
