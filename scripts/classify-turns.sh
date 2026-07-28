#!/usr/bin/env bash
#
# classify-turns.sh — Pick max_turns for an issue. Two-stage decision,
# mirroring classify-task.sh's model triage:
#
#   1. Explicit override via a `turns:<N>` label on the issue (N one of
#      30/60/90/120). This always wins.
#   2. Heuristic over the issue body — counts `### Task` headings under an
#      `## Implementation Plan` section (the shape /gh:enrich writes). More
#      tasks means more file edits + test runs + a regression pass before
#      the agent can commit/push/open a PR, so it needs a bigger budget.
#      An issue with no Implementation Plan section (not enriched, or a
#      trivial one-liner) falls through to DEFAULT_MAX_TURNS.
#
# Required environment variables:
#   ISSUE_NUMBER  GitHub issue number
#   REPO          owner/repo (default: $GITHUB_REPOSITORY)
#   GH_TOKEN      (or ambient gh auth)
#
# Optional environment variables:
#   DEFAULT_MAX_TURNS  Fallback when no override label + no plan found.
#                      Default: 30 (matches agent-implement.yml's own default).
#   ISSUE_LABELS       Newline- or space-separated labels. If set, skips the
#                      `gh issue view --json labels` call. Used by tests.
#   ISSUE_BODY         Free-form issue title+body string. If set, skips the
#                      `gh issue view --json title,body` call. Used by tests.
#
# Output:
#   Writes `turns=<N>` and `reason=<text>` to $GITHUB_OUTPUT when set,
#   and prints a one-line `chosen: <N> (<reason>)` summary to stdout.
#
# Exit codes:
#   0  success
#   2  required env missing
set -euo pipefail
IFS=$'\n\t'

require_env() {
  if [[ -z "${!1:-}" ]]; then
    printf 'error: %s must be set\n' "$1" >&2
    exit 2
  fi
}

require_env ISSUE_NUMBER
REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
if [[ -z "$REPO" ]]; then
  printf 'error: REPO or GITHUB_REPOSITORY must be set\n' >&2
  exit 2
fi

DEFAULT_MAX_TURNS="${DEFAULT_MAX_TURNS:-30}"

# --- 1) explicit override label -------------------------------------------

if [[ -z "${ISSUE_LABELS:-}" ]]; then
  ISSUE_LABELS="$(gh issue view "$ISSUE_NUMBER" --repo "$REPO" --json labels --jq '.labels[].name')"
fi

chosen=''
reason=''
while IFS= read -r label; do
  case "$label" in
    turns:30)  chosen=30;  reason='label turns:30' ;;
    turns:60)  chosen=60;  reason='label turns:60' ;;
    turns:90)  chosen=90;  reason='label turns:90' ;;
    turns:120) chosen=120; reason='label turns:120' ;;
  esac
done <<< "$ISSUE_LABELS"

# --- 2) heuristic over title+body -----------------------------------------

if [[ -z "$chosen" ]]; then
  if [[ -z "${ISSUE_BODY:-}" ]]; then
    ISSUE_BODY="$(gh issue view "$ISSUE_NUMBER" --repo "$REPO" --json title,body --jq '.title + "\n" + .body')"
  fi

  if printf '%s' "$ISSUE_BODY" | grep -qi '^## Implementation Plan'; then
    task_count="$(printf '%s' "$ISSUE_BODY" | grep -cE '^### Task [0-9]+')"
    if   (( task_count >= 6 )); then chosen=120; reason="heuristic: ${task_count} plan tasks"
    elif (( task_count >= 4 )); then chosen=90;  reason="heuristic: ${task_count} plan tasks"
    elif (( task_count >= 2 )); then chosen=60;  reason="heuristic: ${task_count} plan tasks"
    else chosen="$DEFAULT_MAX_TURNS"; reason="heuristic: ${task_count} plan task(s), default budget enough"
    fi
  else
    chosen="$DEFAULT_MAX_TURNS"
    reason='heuristic: no Implementation Plan section found'
  fi
fi

printf 'chosen: %s (%s)\n' "$chosen" "$reason"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'turns=%s\n'  "$chosen" >> "$GITHUB_OUTPUT"
  printf 'reason=%s\n' "$reason" >> "$GITHUB_OUTPUT"
fi
