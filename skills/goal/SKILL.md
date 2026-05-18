---
name: goal
description: Start or manage the global Goal loop. Use when the user says goal, /goal, codex goal, Ralph loop, RLAPH loop, keep working until done, or asks an agent to grill unclear tasks before running autonomous worker/reviewer instances.
---

# Goal

Use a hybrid flow: run the grill session inside the current chat, then hand the clarified goal to the global goal-loop CLI.

## Trigger

When the user asks for a goal loop, Ralph/RLAPH loop, `/goal`, autonomous completion loop, or says to keep running until done:

1. Start a real `grill-with-docs` session in chat.

Ask one question at a time and wait for the user's answer. Use existing project docs/code before asking questions. Optimize for quality, not speed: keep grilling until the worker can be judged by concrete outcomes, not vibes.

Each question must resolve one missing quality gate. Prefer questions in this order:

1. Definition of Done: what observable result proves the task is complete?
2. Acceptance Criteria: what specific pass/fail checks must be true?
3. Verification Plan: what commands, screenshots, tests, manual checks, or review steps prove it?
4. Scope Boundaries: what must the worker avoid changing?
5. Runtime Constraints: max iterations, timeout sensitivity, credentials, external services, or cost limits.

Do not ask vague preference questions such as "what style do you want?" unless the answer changes acceptance criteria. For every question, include your recommended answer or default assumption.

2. When the task is clear, produce a concise execution handoff with:

- `Goal`: the task in one concrete sentence
- `Context`: only the facts the worker needs
- `Definition of Done`: observable outcomes that must be true
- `Acceptance Criteria`: specific pass/fail requirements
- `Verification Plan`: exact commands, tests, screenshots, manual checks, or review steps the worker/evaluator should run
- `Out of Scope`: what the worker must not do
- `Skill Plan`: task type, required installed skills, missing skill candidates, skill hub policy, and worker/reviewer/evaluator skill checks

The CLI appends a `Skill Plan` automatically when it starts. The plan checks installed skills first and does not install missing skills silently.

3. Start the loop with the ready path so the CLI does not re-grill:

```bash
goal start-ready "<execution handoff including Definition of Done and Verification Plan>"
```

The CLI rejects incomplete `start-ready` handoffs. Autonomous execution must not start unless the handoff includes `Goal`, `Definition of Done`, `Acceptance Criteria`, `Verification Plan`, and `Out of Scope`. The CLI appends `Skill Plan` automatically.

4. If they ask for status, run:

```bash
goal status
```

5. If they ask to stop it, run:

```bash
goal stop
```

## Behavior

The hybrid flow:

- uses `grill-with-docs` interactively in chat
- starts the CLI with `start-ready` after clarification, using a handoff that includes Definition of Done and Verification Plan
- routes the goal through installed skills before worker execution
- runs fresh worker, reviewer, and evaluator instances if clear
- defaults to 10 goal-loop iterations for quality-first completion
- retries a stalled worker 3 times, then marks the goal `blocked-stalled-worker`
- stops with `needs-skill-approval` if the task type needs a specialized skill but no matching installed skill is found
- continues from the global Stop hook while the workspace status is active

Skill routing rules:

- Check local installed skills before execution.
- Require matching installed skills for high-skill task types such as images, articles, slides, research, plans, prototypes, and coding/debugging.
- Never install from the skill hub, GitHub, or `npx skills` silently.
- If a useful skill is missing, write the missing candidates to `.goal/clarify.md`, set status to `needs-skill-approval`, and wait for explicit user approval or manual installation.
- Worker, reviewer, and evaluator prompts must treat the `Skill Plan` as part of the contract.

The grill session must not create docs just to store questions. It should only update
`CONTEXT.md` or ADRs when it has learned a durable domain decision from existing docs/code
or from a later clarified task.

If the user explicitly wants a non-interactive mode, run:

```bash
goal "<task>"
```

That mode may stop at `.goal/clarify.md` because hooks cannot hold a live conversation.

For a stateful CLI clarification queue, use:

```bash
goal clarify "<task>"
goal answer "<answer to the blocking question>"
goal start-clarified
```

## Install Dependency Skills

`goal install-hook` installs these skills into the configured agent skill directory:

- `grill-me`
- `grill-with-docs`

These are bundled under `~/.codex/goal/skills` so the hook installer can restore them.

## Important Constraint

Codex does not currently expose user-defined slash commands equivalent to Claude Code `/goal`.
Treat `/goal ...` in chat as natural language: grill first, then run `goal start-ready`.
