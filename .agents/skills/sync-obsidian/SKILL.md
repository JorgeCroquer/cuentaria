---
name: sync-obsidian
description: Sync architecture, planning, and documentation changes between the repo and the Obsidian Knowledge Base vault. Use when user says "sync obsidian", "update knowledge base", or after completing a PRD/ADR.
---

# Sync Obsidian

## Process

1. **Locate the Vault**
   The Obsidian vault for Cuentaria is located at:
   `/mnt/d/Huella Digital/Obisidian Vaults/Knowledge_Base/🚀 100 - Proyectos/Cuentaria/`

2. **Read current state**
   Read the `Cuentaria - MOC.md` (Map of Content) file to understand the current recorded state in Obsidian.
   Check recent repository changes (new ADRs, updated CONTEXT.md, closed issues for PRDs).

3. **Determine Sync Direction**
   The synchronization works unidirectionally per action:
   - **Repo → Obsidian (Progress & Architecture):**
     - If a PRD is completed in GitHub, check off its box in the Obsidian MOC.
     - If an ADR was added to `docs/adr/`, add a brief summary to `04 - Decisiones de Arquitectura (ADRs).md`.
     - If terms were added to `docs/CONTEXT.md`, append them to `05 - CONTEXT - Lenguaje de Arquitectura.md`.
     - If implementation details diverged from the plan, update the PRD's detail note (e.g. `08 - Detalle F1 - Scaffold.md`).
   - **Obsidian → Repo (Design & Decisions):**
     - Handled mostly by `to-prd` and `to-issues`. Do not overwrite code or PRDs in the repo with Obsidian drafts.

4. **Present the Diff**
   Before modifying the vault, tell the user exactly what you are going to update.
   - Example: "I will check off F1 in the MOC and add the term 'Real Cost' to note 05."

5. **Apply Changes**
   Once confirmed, use your file editing tools to update the markdown files in the vault. Do not break Obsidian frontmatter or wikilinks.

## When to use

- After merging a completed PRD.
- After creating a new ADR (`docs/adr/`).
- After updating the ubiquitous language (`docs/CONTEXT.md`).
- When the user explicitly requests a sync with `/sync-obsidian`.
