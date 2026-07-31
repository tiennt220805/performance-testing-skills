#!/usr/bin/env bash
#
# session-start.sh — Environment validation for the performance-testing-skills suite.
#
# Idempotent and side-effect-free on failure (CLAUDE.md §5): this script only reads the
# environment and reports pass/fail — it never mutates state, so running it repeatedly or in
# immediate succession is always safe.
#
# NOT a Claude Code native hook: Claude Code's own SessionStart hook engine is not wired to this
# script (this repo is a submodule mounted read-only at a target project's .claude/, and cannot
# register itself into that project's settings.json). Enforcement instead happens per AGENTS.md's
# "Environment Hook Check" — the Master Agent (perf-architect) is instructed to run this script
# directly via its Bash tool before any /perf-* command, and to interpret this script's own exit
# code itself. See hooks/README.md for the full explanation.
#
# Exit code contract (a suite-internal convention interpreted by the agent, not a Claude Code
# hook engine contract):
#   0 = environment validated, safe to proceed
#   1 = fatal — a required condition failed, the agent must STOP and surface the error to the user

set -euo pipefail

# Minimum k6 version required by this suite. 0.45.0 is the floor because
# profile-spike-test.md's Open System model depends on the `ramping-arrival-rate`
# executor, which is not available in older k6 releases.
MIN_K6_VERSION="0.45.0"

fatal() {
  echo "[FATAL] Environment check failed: $1" >&2
  exit 1
}

# 1. [FATAL if missing] Confirm the k6 binary is on PATH.
if ! command -v k6 >/dev/null 2>&1; then
  fatal "k6 binary not found on PATH. Install Grafana k6 from: https://k6.io/docs/get-started/installation/"
fi

# 2. [FATAL if below MIN_K6_VERSION] Parse and compare the installed version.
RAW_VERSION_OUTPUT="$(k6 version 2>&1 || true)"
DETECTED_VERSION="$(printf '%s' "$RAW_VERSION_OUTPUT" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | sed 's/^v//')"

if [ -z "$DETECTED_VERSION" ]; then
  fatal "could not parse a version number from 'k6 version' output: ${RAW_VERSION_OUTPUT}"
fi

version_ge() {
  # Pure-bash numeric comparison of X.Y.Z — portable across BSD (macOS) and GNU environments,
  # avoids relying on GNU-only `sort -V` (BSD sort on macOS has no -V flag and would silently
  # mis-evaluate every comparison as false, producing "version too low" false negatives even
  # against a recent k6 install).
  local IFS=.
  local -a v1=($1) v2=($2)
  for i in 0 1 2; do
    local n1="${v1[i]:-0}"
    local n2="${v2[i]:-0}"
    if (( n1 > n2 )); then return 0; fi
    if (( n1 < n2 )); then return 1; fi
  done
  return 0  # equal
}

if ! version_ge "$DETECTED_VERSION" "$MIN_K6_VERSION"; then
  fatal "k6 version ${DETECTED_VERSION} is below the required minimum ${MIN_K6_VERSION} (needed for the ramping-arrival-rate executor used by Spike open-system profiles). Upgrade at https://k6.io/docs/get-started/installation/"
fi

# 3. [WARNING, not fatal] Optional supporting tooling. Nothing in this suite requires these
#    directly — they only help with ad-hoc manual debugging — so their absence is a warning only.
for tool in node curl jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "[WARNING] Optional tool '${tool}' not found on PATH — not required by this suite, but some manual debugging workflows may expect it."
  fi
done

# 4. [FATAL only if the layout is genuinely unresolvable; WARNING if docs/perf-test simply don't
#    exist yet] Confirm this script's own path resolves to a plausible target-project root two
#    directories up (target-project/.claude/hooks/session-start.sh -> target-project/). This does
#    NOT require docs/ or perf-test/ to already contain files: perf-test/ is created lazily on
#    first use (AGENTS.md §1) and docs/ may be empty until the user supplies input artifacts —
#    that is expected on a first run, not an environment error.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd 2>/dev/null || true)"

if [ -z "$PROJECT_ROOT" ]; then
  fatal "could not resolve a target-project root two directories above hooks/session-start.sh — expected layout is target-project/.claude/hooks/session-start.sh."
fi

if [ ! -d "${PROJECT_ROOT}/docs" ] && [ ! -d "${PROJECT_ROOT}/perf-test" ]; then
  echo "[WARNING] Neither '${PROJECT_ROOT}/docs' nor '${PROJECT_ROOT}/perf-test' exists yet at the resolved project root."
  echo "          This is expected before the first /perf-spec run — perf-test/ is created lazily on first use,"
  echo "          and docs/ must be supplied by the user. Not treated as a fatal environment error."
fi

# 5. [INFO, not fatal] Capture host machine spec for report traceability — cross-platform,
#    detected once per session, never manually typed by the agent (Non-Negotiable 1).
#    Supported shells: macOS Terminal, Linux (including WSL), and Windows via Git Bash/MSYS2/
#    Cygwin (which lack /proc but can shell out to powershell.exe for WMI/CIM data). Raw
#    cmd.exe/PowerShell with no bash interpreter cannot run this script at all — that is a
#    pre-existing prerequisite of the whole hook, not something this step can work around.
if [[ "$OSTYPE" == "darwin"* ]]; then
  CPU_MODEL="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
  CPU_CORES="$(sysctl -n hw.ncpu 2>/dev/null || echo unknown)"
  TOTAL_RAM_GB="$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
  # Git Bash / MSYS2 / Cygwin on Windows: no real /proc filesystem, shell out to
  # powershell.exe (present on the system PATH even from within these bash environments).
  CPU_MODEL="$(powershell.exe -NoProfile -Command "(Get-CimInstance Win32_Processor).Name" 2>/dev/null | tr -d '\r' || echo unknown)"
  CPU_CORES="$(powershell.exe -NoProfile -Command "(Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors" 2>/dev/null | tr -d '\r' || echo unknown)"
  TOTAL_RAM_GB="$(powershell.exe -NoProfile -Command "[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)" 2>/dev/null | tr -d '\r' || echo unknown)"
else
  # Linux, and WSL (which reports linux-gnu) — real /proc filesystem available.
  CPU_MODEL="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo unknown)"
  CPU_CORES="$(nproc 2>/dev/null || echo unknown)"
  TOTAL_RAM_GB="$(( $(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0) / 1048576 ))"
fi
OS_INFO="$(uname -s) $(uname -r)"

echo "[INFO] Host machine: ${CPU_MODEL}, ${CPU_CORES} cores, ${TOTAL_RAM_GB}GB RAM, ${OS_INFO}"

echo "[SUCCESS] Session environment validated. Grafana k6 engine ready (version ${DETECTED_VERSION})."
exit 0
