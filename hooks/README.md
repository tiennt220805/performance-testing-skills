# hooks/

## `hooks.json` is descriptive, not executable

`hooks.json` is **not** wired into Claude Code's native `SessionStart` hook engine. That engine is configured via a target project's own `settings.json`, and this repo is mounted read-only as a submodule at that project's `.claude/` — it has no ability to register itself into a project it doesn't own. `hooks.json` exists only as a manifest: a human-readable (and future-reference) statement of intent — "the `session-start` event maps to `session-start.sh`" — kept close to Claude Code's native schema so it's easy to actually wire in later if desired, but nothing in this suite depends on that wiring happening.

## The real enforcement mechanism is `AGENTS.md`

Actual enforcement is behavioral, not automated: `AGENTS.md`'s "Environment Hook Check" instructs the Master Agent (`perf-architect`) to run `hooks/session-start.sh` directly via its Bash tool before any `/perf-*` command, and to interpret that script's exit code itself.

## Exit code contract (suite-internal, not a Claude Code contract)

- `exit 0` — environment validated, the agent may proceed.
- `exit 1` — fatal; the agent must STOP and surface the printed `[FATAL]` reason to the user, per `CLAUDE.md` §5 (hooks "must fail loudly, not warn quietly").

This convention is interpreted by the agent reading the script's output/exit status — it is not a contract with Claude Code's own hook engine.
