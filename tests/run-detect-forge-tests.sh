#!/usr/bin/env bash
#
# run-detect-forge-tests.sh — Layer-1 fixture tests for scripts/lib/detect-forge.sh
# (no network). Builds a throwaway git repo per case, points PATH at tests/mocks/,
# sources the script, and asserts detect_forge's output.
#
# Usage: tests/run-detect-forge-tests.sh
# Exit codes: 0 all pass; 1 at least one assertion failed.
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/scripts/lib/detect-forge.sh"
MOCKS="$ROOT/tests/mocks"

PASS=0
FAIL=0
FAIL_NAMES=()

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_GREEN=''; C_RED=''; C_DIM=''; C_OFF=''
fi

section() { printf '\n%s── %s ──%s\n' "$C_DIM" "$1" "$C_OFF"; }
pass() { PASS=$((PASS + 1)); printf '  %s✓%s %s\n' "$C_GREEN" "$C_OFF" "$1"; }
fail() {
  FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1")
  printf '  %s✗%s %s\n' "$C_RED" "$C_OFF" "$1"
  [ $# -gt 1 ] && printf '      %s\n' "$2"
  return 0
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "expected: $expected | actual: $actual"
  fi
}

# make_repo <remote-url>  — throwaway git repo with that origin, echoes its path
make_repo() {
  local dir; dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$1"
  echo "$dir"
}

# run_detect_forge <repo-dir> [GH_MOCK_AUTH_HOSTS] [TEA_MOCK_LOGINS]
run_detect_forge() {
  local dir="$1" auth_hosts="${2:-}" tea_logins="${3:-}"
  (
    cd "$dir"
    export PATH="$MOCKS:$PATH"
    export GH_MOCK_AUTH_HOSTS="$auth_hosts"
    export TEA_MOCK_LOGINS="$tea_logins"
    # shellcheck disable=SC1090
    source "$LIB"
    detect_forge
  )
}

# --- cases -------------------------------------------------------------

section "github"

REPO="$(make_repo "https://github.com/freaxnx01/agent-workflow.git")"
assert_eq "https remote, gh authed" "github github.com" \
  "$(run_detect_forge "$REPO" "github.com" "")"
rm -rf "$REPO"

REPO="$(make_repo "git@github.com:freaxnx01/agent-workflow.git")"
assert_eq "scp-style remote, gh authed" "github github.com" \
  "$(run_detect_forge "$REPO" "github.com" "")"
rm -rf "$REPO"

REPO="$(make_repo "https://github.com/freaxnx01/agent-workflow.git")"
assert_eq "github.com fallback when gh not authed" "github github.com" \
  "$(run_detect_forge "$REPO" "" "")"
rm -rf "$REPO"

section "forgejo"

REPO="$(make_repo "ssh://git@git.home.freaxnx01.ch/freax/hello-forgejo.git")"
assert_eq "ssh remote, tea login matches" "forgejo git.home.freaxnx01.ch" \
  "$(run_detect_forge "$REPO" "" "git.home.freaxnx01.ch")"
rm -rf "$REPO"

section "unknown"

REPO="$(make_repo "https://gitlab.example.com/freax/whatever.git")"
assert_eq "unrecognized host, no gh/tea match" "unknown gitlab.example.com" \
  "$(run_detect_forge "$REPO" "" "")"
rm -rf "$REPO"

# --- summary -------------------------------------------------------------

printf '\n%s─────%s\n' "$C_DIM" "$C_OFF"
printf '  %s%d passed%s' "$C_GREEN" "$PASS" "$C_OFF"
if [ "$FAIL" -gt 0 ]; then
  printf ', %s%d failed%s\n' "$C_RED" "$FAIL" "$C_OFF"
  printf '\nFailed:\n'
  for n in "${FAIL_NAMES[@]}"; do printf '  - %s\n' "$n"; done
  exit 1
fi
printf '\n'
exit 0
