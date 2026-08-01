#!/usr/bin/env bash
#
# self-fix-pr.sh — self-fix-loop.sh's default FIX_CMD. Checks out the PR's
# head branch, runs the agent agentically against the prior review's
# concerns (scripts/lib/self-fix-prompt.md), then commits the fix. Part of
# pre-preview's self-fix pass (#81 / ADR-004 follow-up).
#
# Contract: self-fix-pr.sh <pr-number> <concerns-json-file>
#
# Required environment variables:
#   REPO        owner/repo
#   HEAD_REF    PR head branch name — checked out and pushed to
#   ITERATION   integer, used in the commit message
#
# Optional environment variables:
#   FIX_AGENT_CMD     Override the agent invocation. Contract:
#                       $FIX_AGENT_CMD <prompt-file>
#                     Agent edits files directly in the CWD. Default
#                     resolves to <script-dir>/lib/agent-cmd-claude-fix.sh.
#   MODEL             Model id passed to FIX_AGENT_CMD.
#   PROMPT_TEMPLATE   Override path to lib/self-fix-prompt.md.
#   WORK_DIR          Directory to operate in. Default: mktemp -d.
#   SKIP_CLONE        "1" to skip `gh repo clone` / `git fetch` and operate
#                     directly in WORK_DIR (already a checked-out git repo
#                     on HEAD_REF). Used by Layer-1 tests.
#   SKIP_PUSH         "1" to skip `git push` (Layer-1 tests assert the
#                     local commit instead of a network push).
#
# Exit codes:
#   0  fix committed (and pushed, unless SKIP_PUSH=1)
#   1  checkout / agent / commit / push failure, or agent made no changes
#   2  required env or args missing
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_env() {
  if [[ -z "${!1:-}" ]]; then
    printf 'error: %s must be set\n' "$1" >&2
    exit 2
  fi
}

PR_NUMBER="${1:-}"
CONCERNS_FILE="${2:-}"
if [[ -z "$PR_NUMBER" || -z "$CONCERNS_FILE" ]]; then
  printf 'error: usage: self-fix-pr.sh <pr-number> <concerns-json-file>\n' >&2
  exit 2
fi

require_env REPO
require_env HEAD_REF
require_env ITERATION

if [[ ! -r "$CONCERNS_FILE" ]]; then
  printf 'error: concerns file not readable: %s\n' "$CONCERNS_FILE" >&2
  exit 2
fi

PROMPT_TEMPLATE="${PROMPT_TEMPLATE:-$SCRIPT_DIR/lib/self-fix-prompt.md}"
if [[ ! -r "$PROMPT_TEMPLATE" ]]; then
  printf 'error: prompt template not readable: %s\n' "$PROMPT_TEMPLATE" >&2
  exit 2
fi

WORK_DIR="${WORK_DIR:-$(mktemp -d)}"
PROMPT_FILE="$(mktemp)"

if [[ "${SKIP_CLONE:-0}" != "1" ]]; then
  gh repo clone "$REPO" "$WORK_DIR" -- --quiet
  ( cd "$WORK_DIR" && git fetch --quiet origin "$HEAD_REF" && git checkout --quiet "$HEAD_REF" )
fi

concerns_md="$(jq -r '.concerns[] | "- **\(.severity)**: \(.message)"' "$CONCERNS_FILE" 2>/dev/null || true)"
[[ -z "$concerns_md" ]] && concerns_md="(no concerns listed)"

awk -v repo="$REPO" -v pr="$PR_NUMBER" -v ref="$HEAD_REF" -v concerns="$concerns_md" '
  {
    gsub(/\{\{REPO\}\}/, repo)
    gsub(/\{\{PR_NUMBER\}\}/, pr)
    gsub(/\{\{HEAD_SHA\}\}/, ref)
    if (index($0, "{{CONCERNS}}")) {
      print concerns
    } else {
      print
    }
  }
' "$PROMPT_TEMPLATE" > "$PROMPT_FILE"

if [[ -z "${FIX_AGENT_CMD:-}" ]]; then
  FIX_AGENT_CMD="$SCRIPT_DIR/lib/agent-cmd-claude-fix.sh"
fi

if ! ( cd "$WORK_DIR" && "$FIX_AGENT_CMD" "$PROMPT_FILE" ); then
  printf 'error: fix agent invocation failed\n' >&2
  rm -f "$PROMPT_FILE"
  exit 1
fi
rm -f "$PROMPT_FILE"

if [[ -z "$( cd "$WORK_DIR" && git status --porcelain )" ]]; then
  printf 'error: agent made no changes -- nothing to commit\n' >&2
  exit 1
fi

( cd "$WORK_DIR" && git add -A && git commit --quiet -m "address self-review (iteration $ITERATION)" )

if [[ "${SKIP_PUSH:-0}" != "1" ]]; then
  ( cd "$WORK_DIR" && git push --quiet origin "HEAD:$HEAD_REF" )
fi

printf 'fixed=true\n'
