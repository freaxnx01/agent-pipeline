#!/usr/bin/env bash
#
# agent-cmd-opencode-fix.sh — self-fix-pr.sh's OpenCode FIX_AGENT_CMD
# wrapper (AGENT=opencode). Contract: FIX_AGENT_CMD <prompt-file>.
#
# Mirrors the `implement` job's "Run OpenCode" step (agent-implement.yml)
# but operates on the already-checked-out PR branch instead of a fresh
# clone, and lets the agent edit files directly rather than emitting a
# --format json result for adapt-opencode-result.sh to parse — the caller
# (self-fix-pr.sh) commits/pushes afterward, same division of labor as
# agent-cmd-claude-fix.sh (#193).
#
# MODEL is optional; prefixed with openrouter/ unless already prefixed,
# same rule as the implement job's Run OpenCode step.
#
# EXPERIMENTAL (see #58): reuses the same unverified opencode agentic-edit
# surface as the implement job's OpenCode path — not new risk, but not
# independently re-verified end-to-end either.
#
# stdout/stderr are captured to $RUNNER_TEMP/self-fix-agent-output.log
# (falls back to /tmp), same diagnostics precedent as
# agent-cmd-claude-fix.sh.
set -euo pipefail
IFS=$'\n\t'

prompt="$1"

oc_model="${MODEL:-}"
case "$oc_model" in
  ''|openrouter/*) ;;
  *) oc_model="openrouter/${oc_model}" ;;
esac

args=(run --format json --print-logs)
[[ -n "$oc_model" ]] && args+=(--model "$oc_model")

opencode "${args[@]}" -- "$(cat "$prompt")" > "${RUNNER_TEMP:-/tmp}/self-fix-agent-output.log" 2>&1
