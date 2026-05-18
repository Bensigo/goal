# Contributing

Thanks for considering a contribution to `goal`.

This project is open source and accepts focused issues, fixes, tests, and documentation improvements. Keep contributions small enough to review in one pass.

## Before You Start

- Read the [README](README.md) so you understand the goal loop, status files, and safety model.
- Search existing issues and pull requests before opening a duplicate.
- For behavior changes, open an issue first unless the fix is obvious and narrow.
- Do not add hidden network calls, silent global installs, or automatic skill installation.

## Development Setup

Clone the repository and make the scripts executable:

```bash
git clone https://github.com/Bensigo/goal.git
cd goal
chmod +x bin/goal goal-hook tests/run-tests.sh
```

Run the local checks:

```bash
bash -n bin/goal goal-hook
./tests/run-tests.sh
```

The test suite uses a fake `codex` binary for control-flow tests, so it should not spend model calls.

## Pull Request Guide

1. Create a branch from `main`.
2. Keep the change scoped to one behavior, bug fix, or documentation improvement.
3. Add or update tests for runtime behavior changes.
4. Update documentation when user-facing commands, statuses, files, or environment variables change.
5. Run the local checks before opening the pull request.

In the pull request description, include:

- What changed.
- Why it changed.
- How you verified it.
- Any risks, limitations, or follow-up work.

## Code Guidelines

- Prefer shell that is explicit, portable, and easy to audit.
- Preserve existing compatibility aliases unless the pull request is explicitly about removing them.
- Keep status names stable unless there is a migration path.
- Fail loudly when a task is unsafe, unclear, or missing required skills.
- Avoid broad refactors mixed into behavior changes.

## Reporting Issues

Useful bug reports include:

- The command you ran.
- Expected behavior.
- Actual behavior.
- Relevant `.goal/status` and `.goal/logs/` excerpts.
- Your shell, operating system, and configured agent command if it is not the default.

Do not paste secrets, private repository contents, or full agent logs that contain sensitive data.
