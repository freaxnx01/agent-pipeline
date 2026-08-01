#!/usr/bin/env bash
#
# agent-cmd-claude-fix.sh — self-fix-pr.sh's default FIX_AGENT_CMD wrapper
# for the Claude Code CLI. Contract: FIX_AGENT_CMD <prompt-file>.
#
# Unlike agent-cmd-claude.sh (review-pr.sh's read-only, JSON-only wrapper),
# this one allows the agent to edit files directly in the current working
# directory — the caller (self-fix-pr.sh) has already checked out the PR
# branch, and commits/pushes afterward. Mirrors the tool allowlist the
# `implement` job already grants Claude for writing the PR in the first
# place (see .github/workflows/agent-implement.yml's "Run Claude Code" step).
#
# MODEL is optional; if set it becomes a `--model <value>` flag.
set -euo pipefail
IFS=$'\n\t'

prompt="$1"

args=(--print --allowedTools 'Edit,Write,Read,Glob,Grep,MultiEdit,Bash')
[[ -n "${MODEL:-}" ]] && args+=(--model "$MODEL")

claude "${args[@]}" < "$prompt" > /dev/null
