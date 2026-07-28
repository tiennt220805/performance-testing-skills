# AGENTS.md

Instruction routing map for AI Agents operating in the `performance-testing-skills` repository.

<!-- Placeholder for 1-2 sentence overview -->

## Agent Personas

<!-- Placeholder: perf-architect, bottleneck-auditor -->

## Command Routing Map

<!-- Placeholder: /perf-spec -> /perf-plan -> /perf-script -> /perf-verify -> /perf-audit -> /perf-gate -->

Command trigger files live in the root `commands/` directory (e.g. `commands/perf-spec.md`), NOT under `.claude/commands/`. This repository is consumed as a `git submodule` inside a target project's `.claude/` directory, so no nested `.claude/` directory may exist here.

## Skill Index

<!-- Placeholder: table linking commands to skills/*/SKILL.md -->

## Non-Negotiable Rules

<!-- Placeholder for the 6 Non-Negotiable Performance Engineering Rules -->
