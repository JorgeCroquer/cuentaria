---
name: to-prd
description: Turn the current conversation context into a PRD and publish it to the project issue tracker. Use when user wants to create a PRD from the current context.
---

This skill takes the current conversation context and codebase understanding and produces a PRD. Do NOT interview the user — just synthesize what you already know.

The issue tracker and triage label vocabulary should have been provided to you — run `/setup-matt-pocock-skills` if not.

## Process

1. Explore the repo to understand the current state of the codebase, if you haven't already. Use the project's domain glossary vocabulary throughout the PRD, and respect any ADRs in the area you're touching.

2. Sketch out the major modules you will need to build or modify to complete the implementation. Actively look for opportunities to extract deep modules that can be tested in isolation.

A deep module (as opposed to a shallow module) is one which encapsulates a lot of functionality in a simple, testable interface which rarely changes.

Check with the user that these modules match their expectations. Check with the user which modules they want tests written for.

3. Write the PRD using the template below, then publish it to the project issue tracker. Apply the `ready-for-agent` triage label - no need for additional triage.

> [!IMPORTANT] Jira CLI Required Fields
> PRDs MUST be created as a parent issue of type `Incidencia - Mejora - Nuevo Requerimiento`.
> The Jira CLI will reject the creation with a 400 error unless you provide the mandatory custom fields. You MUST use the following `--custom` flags when creating the PRD:
> ```bash
> jira issue create --no-input -t"Incidencia - Mejora - Nuevo Requerimiento" -s"Title" -T <body-file> \
>   --custom customfield_10335='{"id":"10587"}' \
>   --custom customfield_10336='[{"accountId":"712020:f2f0a3c3-5198-47d8-9c05-69c607c690c9"}]' \
>   --custom customfield_10405='{"id":"10736"}' \
>   --custom customfield_10319='{"id":"10479"}' \
>   --custom customfield_10323='{"id":"10533"}' \
>   --custom customfield_10324='{"id":"10568"}' \
>   --custom customfield_10321='{"id":"10484"}' \
>   --custom customfield_10322='{"id":"10508"}' \
>   --custom customfield_10020='[{"id":397}]'
> ```
> After creating the PRD issue, you MUST move it to the DEV - PENDIENTE status:
> `jira issue move QUEN-XXXX "DEV - PENDIENTE (STG)"`

> [!WARNING] Jira CLI Hangs
> The `jira` CLI may hang indefinitely in this environment even after the API has successfully processed the request. To prevent blocking your execution loop, you MUST execute `jira` CLI commands asynchronously (fire-and-forget). If using tools, set `WaitMsBeforeAsync` to a low value like `500`. Do not retry if the command hangs, as it will create duplicates.

<prd-template>

## Problem Statement

The problem that the user is facing, from the user's perspective.

## Solution

The solution to the problem, from the user's perspective.

## User Stories

A LONG, numbered list of user stories. Each user story should be in the format of:

1. As an <actor>, I want a <feature>, so that <benefit>

<user-story-example>
1. As a mobile bank customer, I want to see balance on my accounts, so that I can make better informed decisions about my spending
</user-story-example>

This list of user stories should be extremely extensive and cover all aspects of the feature.

## Implementation Decisions

A list of implementation decisions that were made. This can include:

- The modules that will be built/modified
- The interfaces of those modules that will be modified
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets. They may end up being outdated very quickly.

Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it within the relevant decision and note briefly that it came from a prototype. Trim to the decision-rich parts — not a working demo, just the important bits.

## Testing Decisions

A list of testing decisions that were made. Include:

- A description of what makes a good test (only test external behavior, not implementation details)
- Which modules will be tested
- Prior art for the tests (i.e. similar types of tests in the codebase)

## Out of Scope

A description of the things that are out of scope for this PRD.

## Further Notes

Any further notes about the feature.

</prd-template>
