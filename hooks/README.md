# hooks/

## `hooks.json` is descriptive, not executable

`hooks.json` is **not** wired into Claude Code's native `SessionStart` hook engine. That engine is configured via a target project's own `settings.json`, and this repo is mounted read-only as a submodule at that project's `.claude/` — it has no ability to register itself into a project it doesn't own. `hooks.json` exists only as a manifest: a human-readable (and future-reference) statement of intent — "the `session-start` event maps to `session-start.sh`" — kept close to Claude Code's native schema so it's easy to actually wire in later if desired, but nothing in this suite depends on that wiring happening.

## The real enforcement mechanism is `AGENTS.md`

Actual enforcement is behavioral, not automated: `AGENTS.md`'s "Environment Hook Check" instructs the Master Agent (`perf-architect`) to run `hooks/session-start.sh` directly via its Bash tool before any `/perf-*` command, and to interpret that script's exit code itself.

## Exit code contract (suite-internal, not a Claude Code contract)

- `exit 0` — environment validated, the agent may proceed.
- `exit 1` — fatal; the agent must STOP and surface the printed `[FATAL]` reason to the user, per `CLAUDE.md` §5 (hooks "must fail loudly, not warn quietly").

This convention is interpreted by the agent reading the script's output/exit status — it is not a contract with Claude Code's own hook engine.

## `[INFO] Host machine: ...` line

The script also prints a single `[INFO] Host machine: ...` line (CPU model/cores, total RAM, OS) captured automatically once per session — never typed from memory. This is context metadata for report traceability (feeding `PERF_PLAN.md`'s Environment Parity Summary), not a pass/fail condition: it never affects the exit code contract above, even if detection falls back to `unknown` for a field.

## Shell prerequisite

This script requires a POSIX-compatible shell to run at all: macOS Terminal, Linux, WSL, or Git Bash/MSYS2/Cygwin on Windows. **Running it directly under `cmd.exe` or plain PowerShell (with no bash layer) will not work** — there is no bash interpreter there for the `#!/usr/bin/env bash` shebang to invoke. This is a pre-existing limitation of the whole hook, not specific to the host-machine-spec step.
