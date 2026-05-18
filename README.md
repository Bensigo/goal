# goal

`goal` is a quality-first goal loop for autonomous coding agents. It defaults to Codex and can be configured for Claude or another compatible CLI.

It turns a vague task into a clarified execution contract, routes the task through relevant installed skills, then runs a worker, reviewer, and evaluator loop until the goal is complete, blocked, or the iteration limit is reached.

This is an open-source project and contributions are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or pull request.

## What It Does

- Grills unclear tasks before execution.
- Produces a concrete handoff with Definition of Done, acceptance criteria, verification, scope, and skill routing.
- Checks installed skills and missing high-value skill candidates before running the worker.
- Refuses to install missing skills silently.
- Runs a worker, reviewer, and evaluator in sequence.
- Retries stalled workers up to 3 times.
- Stops with explicit statuses such as `needs-clarification`, `needs-skill-approval`, `blocked-stalled-worker`, or `complete`.

## Repository Layout

```text
.
├── bin/goal                 # CLI entrypoint
├── goal-hook                # worker/reviewer/evaluator loop
├── install-goal-hook.mjs    # installer helper
├── skills/
│   ├── goal/SKILL.md        # agent skill instructions
│   └── grill-me/SKILL.md          # bundled grilling helper
└── tests/run-tests.sh             # shell regression suite
```

## Install

Clone the repo somewhere permanent, then symlink it into your agent config.
The examples below use `GOAL_HOME` so you can choose any project directory. The hook installer currently targets Codex hooks; the CLI itself can run Codex, Claude, or a custom executor.

```bash
git clone https://github.com/Bensigo/goal.git /path/to/goal
export GOAL_HOME="/path/to/goal"

mkdir -p ~/.codex/bin ~/.codex/skills

ln -sfn "$GOAL_HOME" ~/.codex/goal
ln -sfn "$GOAL_HOME/bin/goal" ~/.codex/bin/goal
ln -sfn "$GOAL_HOME/bin/codex-goal" ~/.codex/bin/codex-goal # compatibility alias

rm -rf ~/.codex/skills/goal
mkdir -p ~/.codex/skills/goal
ln -sfn "$GOAL_HOME/skills/goal/SKILL.md" ~/.codex/skills/goal/SKILL.md
```

Make sure the scripts are executable:

```bash
chmod +x "$GOAL_HOME/bin/goal"
chmod +x "$GOAL_HOME/goal-hook"
chmod +x "$GOAL_HOME/tests/run-tests.sh"
```

Restart your agent after installing or changing skills.

## Usage

Start with an already-clarified task:

```bash
goal start-ready "Goal: Create a landing page. Definition of Done: responsive page exists. Acceptance Criteria: desktop and mobile checks pass. Verification Plan: inspect in browser. Out of Scope: no deployment."
```

Start with a raw task and let the loop check clarity first:

```bash
goal "build a landing page website"
```

Clarify a raw task through a stateful CLI queue:

```bash
goal clarify "improve the goal loop"
goal answer "Done means vague goals are blocked before workers run."
goal start-clarified
```

Check status:

```bash
goal status
```

Stop the loop:

```bash
goal stop
```

## Goal Contract

A strong handoff should include:

```text
Goal:
Context:
Definition of Done:
Acceptance Criteria:
Verification Plan:
Out of Scope:
Skill Plan:
```

The CLI can append a `Skill Plan` automatically. The worker, reviewer, and evaluator treat it as part of the contract.

For high-skill work, the Skill Plan is a discovery gate, not just routing metadata. If useful specialist skills are missing, `goal` stops with `needs-skill-approval` until you install/search/approve those skills or explicitly approve continuing without them.

`start-ready`, `start-clarified`, and the hook all block autonomous execution unless the handoff includes objective success criteria and a verification plan. At minimum, the goal contract must include `Goal`, `Definition of Done`, `Acceptance Criteria`, `Verification Plan`, and `Out of Scope`.

## Skill Routing

`goal` scans installed local skills from:

- `~/.codex/skills`
- `~/.agents/skills`
- `~/.codex/plugins/cache`
- `~/.codex/vendor_imports`

It routes common task types to relevant skills:

- images -> `imagegen`
- articles -> writing/editing skills
- slides -> presentation skills
- research -> research/documentation skills
- planning -> planning/issue/milestone skills
- frontend prototypes -> frontend/browser verification skills
- coding -> TDD and verification skills
- client acquisition, sales, outreach, or X/Twitter lead research -> research, proposal, scoring, headline, and prompt-engineering skills

If a useful specialist skill candidate is missing, the loop stops with `needs-skill-approval` even when some relevant skills are installed. This prevents the worker from assuming generic competence where a better specialist skill may exist. It does not install from a skill hub, GitHub, or `npx skills` without explicit user approval.

To continue without missing candidates, explicitly add this to the goal contract:

```text
Missing Skill Approval: approved
```

## Runtime Behavior

Default behavior:

- Max iterations: `10`
- Stalled worker retries: `3`
- Worker stall timeout: `600` seconds

Useful environment overrides:

```bash
GOAL_STALL_TIMEOUT_SECONDS=180 goal run
GOAL_STALLED_WORKER_RETRIES=1 goal run
GOAL_SKILL_SCAN_DIRS="/path/to/skills:/another/path" goal start-ready "..."
GOAL_AGENT=claude goal run
GOAL_AGENT_COMMAND='my-agent --project "$GOAL_PROJECT" --output "$GOAL_OUTPUT" "$GOAL_PROMPT"' goal run
```

By default `goal` runs `codex exec`. Set `GOAL_AGENT=claude` to run `claude -p`, or set `GOAL_AGENT_COMMAND` for another executor. Custom commands receive `GOAL_PROJECT`, `GOAL_OUTPUT`, and `GOAL_PROMPT`.

Older `CODEX_GOAL_*` environment variables and the `codex-goal` command remain supported as compatibility aliases.

## Test

Run the regression suite:

```bash
./tests/run-tests.sh
```

Expected output:

```text
All goal tests passed.
```

The suite uses a fake `codex` binary for control-flow tests, so it does not spend model calls.

## Safety Notes

- This project runs the configured agent with full filesystem access for worker/reviewer/evaluator loops.
- Do not run it on untrusted repositories.
- Review the generated `.goal/goal.md`, logs, and status files when debugging.
- Skill installation is intentionally gated. Silent global environment mutation is a bad default.

## Status Files

Each project using the loop gets a `.goal/` directory containing:

- `goal.md`
- `clarify.md`
- `clarify-answers.md`
- `ready-handoff.md`
- `status`
- `iteration`
- `max-iterations`
- `skill-inventory.txt`
- `skill-preflight.md`
- `logs/`

Common statuses:

- `active`
- `clarified`
- `complete`
- `needs-clarification`
- `needs-skill-approval`
- `blocked-stalled-worker`
- `blocked-worker-error`
- `max-iterations-reached`

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution workflow, pull request expectations, and local verification.

Before claiming changes are done:

```bash
bash -n bin/goal goal-hook
./tests/run-tests.sh
```

Keep changes small and behavior-driven. Add a failing shell test before changing runtime behavior.
