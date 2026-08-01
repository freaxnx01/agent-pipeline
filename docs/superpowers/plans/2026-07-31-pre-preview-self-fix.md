# Pre-preview Self-Fix Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in self-fix pass to pre-preview mode — on a `request_changes` verdict, the agent attempts bounded fix→re-review cycles before falling back to the human-review block path.

**Architecture:** Two new scripts (`self-fix-loop.sh` orchestrator, `self-fix-pr.sh` agentic fix invocation) plug into the existing `pre_preview` job in `.github/workflows/agent-implement.yml`, between the first review and the promote/block steps. `self-fix-loop.sh` re-uses `review-pr.sh` unmodified for re-review; `self-fix-pr.sh` follows the same agentic-Claude pattern the `implement` job already uses to write PRs. `post-auto-review-block.sh` gains distinct wording for the cap-exhausted case. No merge envelope, no auto-merge — self-fix only changes what a human eventually reviews.

**Tech Stack:** Bash scripts (fixture-tested via `tests/run-script-tests.sh`), GitHub Actions reusable workflow (`actionlint` + `shellcheck` lint, `act` layer-2 test).

**Reference spec:** `docs/superpowers/specs/2026-07-31-pre-preview-self-fix-design.md`

**Conventions for every task below:**

- Layer-1 tests live in `tests/run-script-tests.sh`; run the whole suite with `bash tests/run-script-tests.sh` (must finish < 5s, exit 0).
- Lint with `shellcheck -x -e SC1091 <file>.sh` for scripts and `actionlint` for workflow YAML.
- Commit after each task.

---

## Task 1: `find-pipeline-pr.sh` emits `head-ref`

`self-fix-pr.sh` needs the PR's branch name (not just its head SHA) to check it out and push to it. Extend the existing PR-discovery script to report it.

**Files:**

- Modify: `scripts/find-pipeline-pr.sh`
- Test: `tests/run-script-tests.sh` (`find-pipeline-pr` section)

- [ ] **Step 1: Write the failing test**

In `tests/run-script-tests.sh`, in `section "find-pipeline-pr — discover the draft PR opened for an issue"`, replace this line:

```bash
out="$(find_pr_run env ISSUE_NUMBER=42 REPO=o/r \
        PIPELINE_PRS_JSON='[{"number":17,"isDraft":true,"headRefOid":"deadbeef","author":{"login":"github-actions[bot]"}}]')"
assert_contains "$out" 'found=true'         "single draft PR → found=true"
assert_contains "$out" 'pr-number=17'       "emits pr-number"
assert_contains "$out" 'head-sha=deadbeef'  "emits head-sha"
```

with:

```bash
out="$(find_pr_run env ISSUE_NUMBER=42 REPO=o/r \
        PIPELINE_PRS_JSON='[{"number":17,"isDraft":true,"headRefOid":"deadbeef","headRefName":"feat/fix-thing","author":{"login":"github-actions[bot]"}}]')"
assert_contains "$out" 'found=true'         "single draft PR → found=true"
assert_contains "$out" 'pr-number=17'       "emits pr-number"
assert_contains "$out" 'head-sha=deadbeef'  "emits head-sha"
assert_contains "$out" 'head-ref=feat/fix-thing' "emits head-ref (branch name)"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run-script-tests.sh`
Expected: FAIL — `✗ emits head-ref (branch name)` (script doesn't emit `head-ref` yet).

- [ ] **Step 3: Write minimal implementation**

In `scripts/find-pipeline-pr.sh`, change this line:

```bash
  PIPELINE_PRS_JSON="$(gh pr list \
    --repo "$REPO" \
    --state open \
    --search "closes #${ISSUE_NUMBER} in:body" \
    --json number,isDraft,headRefOid,author \
    --limit 10 2>/dev/null || printf '[]')"
```

to:

```bash
  PIPELINE_PRS_JSON="$(gh pr list \
    --repo "$REPO" \
    --state open \
    --search "closes #${ISSUE_NUMBER} in:body" \
    --json number,isDraft,headRefOid,headRefName,author \
    --limit 10 2>/dev/null || printf '[]')"
```

Then change:

```bash
pr_number="$(printf '%s' "$SELECTED" | jq -r '.number // ""')"
head_sha="$(printf '%s' "$SELECTED" | jq -r '.headRefOid // ""')"
```

to:

```bash
pr_number="$(printf '%s' "$SELECTED" | jq -r '.number // ""')"
head_sha="$(printf '%s' "$SELECTED" | jq -r '.headRefOid // ""')"
head_ref="$(printf '%s' "$SELECTED" | jq -r '.headRefName // ""')"
```

Then change:

```bash
printf 'found=%s pr-number=%s head-sha=%s\n' "$found" "$pr_number" "$head_sha"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'found=%s\n'     "$found"
    printf 'pr-number=%s\n' "$pr_number"
    printf 'head-sha=%s\n'  "$head_sha"
  } >> "$GITHUB_OUTPUT"
fi
```

to:

```bash
printf 'found=%s pr-number=%s head-sha=%s head-ref=%s\n' "$found" "$pr_number" "$head_sha" "$head_ref"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'found=%s\n'     "$found"
    printf 'pr-number=%s\n' "$pr_number"
    printf 'head-sha=%s\n'  "$head_sha"
    printf 'head-ref=%s\n'  "$head_ref"
  } >> "$GITHUB_OUTPUT"
fi
```

Finally, update the script's header comment `Output:` list from:

```text
# Output:
#   pr-number  PR number (empty if none found)
#   head-sha   PR head commit SHA (empty if none found)
#   found      true | false
```

to:

```text
# Output:
#   pr-number  PR number (empty if none found)
#   head-sha   PR head commit SHA (empty if none found)
#   head-ref   PR head branch name (empty if none found)
#   found      true | false
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run-script-tests.sh`
Expected: PASS — `✓ emits head-ref (branch name)`, and all pre-existing `find-pipeline-pr` assertions still green (their fixtures lack `headRefName`, so `head_ref` resolves to `""` via `// ""` — no assertions on it there, so no regression).

- [ ] **Step 5: Lint**

Run: `shellcheck -x -e SC1091 scripts/find-pipeline-pr.sh`
Expected: no output, exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/find-pipeline-pr.sh tests/run-script-tests.sh
git commit -m "feat(pre-preview): find-pipeline-pr.sh emits head-ref (#81)"
```

---

## Task 2: `post-auto-review-block.sh` — self-fix-exhausted wording

**Files:**

- Modify: `scripts/post-auto-review-block.sh`
- Test: `tests/run-script-tests.sh` (`post-auto-review-block` section)

- [ ] **Step 1: Write the failing tests**

In `tests/run-script-tests.sh`, inside `section "post-auto-review-block — reason selection + PR-vs-issue addressing"`, immediately after the `MODE=pre-preview` block (the one asserting `'Pre-review held: agent review verdict: block (gate 4)'`), add:

```bash
# SELF_FIX_ITERATIONS > 0 → distinct "self-fix exhausted" wording
LOG="$(mktemp)"
PATH="$MOCKS:$PATH" GH_MOCK_LOG="$LOG" \
REPO=o/r ISSUE_NUMBER=42 PR_NUMBER=100 FOUND=true \
VERDICT=request_changes MODE=pre-preview \
SELF_FIX_ITERATIONS=2 SELF_FIX_MAX=2 \
  bash "$POST_BLOCK" >/dev/null
calls="$(cat "$LOG")"; rm -f "$LOG"
assert_contains     "$calls" 'self-fix exhausted after 2/2 iteration(s) — last verdict: request_changes' "self-fix exhausted → distinct wording"
assert_not_contains "$calls" 'agent review verdict: request_changes (gate 4)'                              "self-fix wording replaces the plain verdict reason"

# SELF_FIX_ITERATIONS unset/0 → unchanged wording (byte-identical to today)
LOG="$(mktemp)"
PATH="$MOCKS:$PATH" GH_MOCK_LOG="$LOG" \
REPO=o/r ISSUE_NUMBER=42 PR_NUMBER=100 FOUND=true \
VERDICT=block MODE=pre-preview \
  bash "$POST_BLOCK" >/dev/null
calls="$(cat "$LOG")"; rm -f "$LOG"
assert_contains "$calls" 'agent review verdict: block (gate 4)' "SELF_FIX_ITERATIONS unset → plain wording unchanged"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-script-tests.sh`
Expected: FAIL — `✗ self-fix exhausted → distinct wording` (script doesn't know about `SELF_FIX_ITERATIONS` yet).

- [ ] **Step 3: Write minimal implementation**

In `scripts/post-auto-review-block.sh`, change this line:

```bash
FAILED_GATES="${FAILED_GATES:-}"
MODE="${MODE:-auto-review}"
```

to:

```bash
FAILED_GATES="${FAILED_GATES:-}"
SELF_FIX_ITERATIONS="${SELF_FIX_ITERATIONS:-0}"
SELF_FIX_MAX="${SELF_FIX_MAX:-}"
MODE="${MODE:-auto-review}"
```

Then change:

```bash
elif [[ "$VERDICT" != 'approve' ]]; then
  reason="agent review verdict: ${VERDICT:-<none>} (gate 4)"
else
```

to:

```bash
elif [[ "$VERDICT" != 'approve' ]]; then
  if [[ "$SELF_FIX_ITERATIONS" != '0' ]]; then
    reason="self-fix exhausted after ${SELF_FIX_ITERATIONS}/${SELF_FIX_MAX} iteration(s) — last verdict: ${VERDICT:-<none>}"
  else
    reason="agent review verdict: ${VERDICT:-<none>} (gate 4)"
  fi
else
```

Also extend the script's header comment "Optional environment variables" list, immediately after the `MODE` line, adding:

```text
#   SELF_FIX_ITERATIONS  Iterations the pre-preview self-fix loop actually
#                        used (#81). "0" or unset → unchanged wording.
#   SELF_FIX_MAX         The self-fix iteration cap, for the "exhausted"
#                        wording. Only read when SELF_FIX_ITERATIONS != "0".
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-script-tests.sh`
Expected: PASS — both new assertions green, and all pre-existing `post-auto-review-block` assertions (self-mod, missing-PR, plain verdict, MODE=pre-preview, envelope-fail) still green.

- [ ] **Step 5: Lint**

Run: `shellcheck -x -e SC1091 scripts/post-auto-review-block.sh`
Expected: no output, exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/post-auto-review-block.sh tests/run-script-tests.sh
git commit -m "feat(pre-preview): self-fix-exhausted block wording (#81)"
```

---

## Task 3: Self-fix prompt template + Claude fix-mode wrapper

Two small library files `self-fix-pr.sh` (Task 4) depends on: the prompt template (parallel to `scripts/lib/review-prompt.md`) and the agentic Claude CLI wrapper (parallel to `scripts/lib/agent-cmd-claude.sh`, but allowing file edits instead of read-only JSON output). Neither has an independent Layer-1 fixture test — same precedent as `agent-cmd-claude.sh`, which is only exercised via lint + the scripts that call it.

**Files:**

- Create: `scripts/lib/self-fix-prompt.md`
- Create: `scripts/lib/agent-cmd-claude-fix.sh`

- [ ] **Step 1: Create the prompt template**

Create `scripts/lib/self-fix-prompt.md`:

```markdown
# Self-fix prompt (agent-agnostic)

You are fixing your own pull request for the repository `{{REPO}}`, PR
#{{PR_NUMBER}}, branch `{{HEAD_SHA}}`, based on a prior automated review
that returned `request_changes`. Edit the files in the current working
directory directly to resolve every concern below.

Do not modify tests to make them pass instead of fixing the underlying
issue (CLAUDE.md house rules apply). Do not expand scope beyond what the
concerns describe — no unrelated refactors, no speculative changes.

## Concerns to resolve

{{CONCERNS}}

When done, stop. Do not commit or push — the calling script handles that.
```

- [ ] **Step 2: Create the Claude fix-mode wrapper**

Create `scripts/lib/agent-cmd-claude-fix.sh`:

```bash
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
```

- [ ] **Step 3: Make it executable and lint**

```bash
chmod +x scripts/lib/agent-cmd-claude-fix.sh
shellcheck -x -e SC1091 scripts/lib/agent-cmd-claude-fix.sh
```

Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/lib/self-fix-prompt.md scripts/lib/agent-cmd-claude-fix.sh
git commit -m "feat(pre-preview): self-fix prompt template + Claude fix wrapper (#81)"
```

---

## Task 4: `self-fix-pr.sh` — the fix invocation

**Files:**

- Create: `scripts/self-fix-pr.sh`
- Create: `tests/mocks/self-fix-agent` (happy-path FIX_AGENT_CMD mock)
- Create: `tests/mocks/self-fix-agent-noop` (no-op FIX_AGENT_CMD mock)
- Create: `tests/mocks/self-fix-agent-fail` (crashing FIX_AGENT_CMD mock)
- Test: `tests/run-script-tests.sh` (new section)

- [ ] **Step 1: Write the failing tests**

In `tests/run-script-tests.sh`, immediately after the `section "post-auto-review-block — ..."` block (i.e. just before whichever section follows it today), add:

```bash
section "self-fix-pr — checkout, fix, commit (local repo simulation)"

SELF_FIX_PR="$ROOT/scripts/self-fix-pr.sh"

make_self_fix_repo() {
  local dir; dir="$(mktemp -d)"
  git -C "$dir" init --quiet -b main
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  printf 'hello\n' > "$dir/file.txt"
  git -C "$dir" add file.txt
  git -C "$dir" commit --quiet -m init
  printf '%s' "$dir"
}

CONCERNS="$(mktemp --suffix=.json)"
printf '{"verdict":"request_changes","summary":"x","concerns":[{"severity":"high","message":"fix the bug"}]}' > "$CONCERNS"

# Happy path: mock agent edits a file → committed (push skipped in tests)
REPO_DIR="$(make_self_fix_repo)"
out="$(WORK_DIR="$REPO_DIR" SKIP_CLONE=1 SKIP_PUSH=1 \
       REPO=o/r HEAD_REF=fix-branch ITERATION=1 \
       FIX_AGENT_CMD="$MOCKS/self-fix-agent" \
       bash "$SELF_FIX_PR" 99 "$CONCERNS")"
assert_contains "$out" 'fixed=true' "agent edit → fixed=true"
commit_msg="$(git -C "$REPO_DIR" log -1 --format=%s)"
assert_equals "$commit_msg" "address self-review (iteration 1)" "commit message includes iteration number"
rm -rf "$REPO_DIR"

# Agent makes no changes → exit 1, no new commit
REPO_DIR="$(make_self_fix_repo)"
before_sha="$(git -C "$REPO_DIR" rev-parse HEAD)"
ec="$(run_capture_ec env WORK_DIR="$REPO_DIR" SKIP_CLONE=1 SKIP_PUSH=1 \
        REPO=o/r HEAD_REF=fix-branch ITERATION=1 \
        FIX_AGENT_CMD="$MOCKS/self-fix-agent-noop" \
        bash "$SELF_FIX_PR" 99 "$CONCERNS")"
assert_equals "$ec" "1" "agent makes no changes → exit 1"
after_sha="$(git -C "$REPO_DIR" rev-parse HEAD)"
assert_equals "$after_sha" "$before_sha" "no new commit created"
rm -rf "$REPO_DIR"

# Fix agent crashes → exit 1
REPO_DIR="$(make_self_fix_repo)"
ec="$(run_capture_ec env WORK_DIR="$REPO_DIR" SKIP_CLONE=1 SKIP_PUSH=1 \
        REPO=o/r HEAD_REF=fix-branch ITERATION=1 \
        FIX_AGENT_CMD="$MOCKS/self-fix-agent-fail" \
        bash "$SELF_FIX_PR" 99 "$CONCERNS")"
assert_equals "$ec" "1" "fix agent crash → exit 1"
rm -rf "$REPO_DIR"

# Error paths
ec="$(run_capture_ec bash "$SELF_FIX_PR")"
assert_equals "$ec" "2" "missing pr-number/concerns args → exit 2"

ec="$(run_capture_ec env REPO=o/r HEAD_REF=x ITERATION=1 bash "$SELF_FIX_PR" 99 /no/such/file.json)"
assert_equals "$ec" "2" "unreadable concerns file → exit 2"

ec="$(run_capture_ec env HEAD_REF=x ITERATION=1 bash "$SELF_FIX_PR" 99 "$CONCERNS")"
assert_equals "$ec" "2" "missing REPO → exit 2"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-script-tests.sh`
Expected: FAIL — the new `self-fix-pr` assertions error (script and mocks do not exist).

- [ ] **Step 3: Create the mocks**

Create `tests/mocks/self-fix-agent`:

```bash
#!/usr/bin/env bash
#
# self-fix-agent — self-fix-pr.sh FIX_AGENT_CMD mock for Layer-1 tests
# (happy path: makes an edit). Contract: FIX_AGENT_CMD <prompt-file>,
# invoked with CWD set to the checked-out PR branch.
set -euo pipefail
IFS=$'\n\t'
printf 'fixed\n' >> file.txt
```

Create `tests/mocks/self-fix-agent-noop`:

```bash
#!/usr/bin/env bash
#
# self-fix-agent-noop — self-fix-pr.sh FIX_AGENT_CMD mock that makes no
# changes, simulating an agent that judged nothing needed fixing.
set -euo pipefail
exit 0
```

Create `tests/mocks/self-fix-agent-fail`:

```bash
#!/usr/bin/env bash
#
# self-fix-agent-fail — self-fix-pr.sh FIX_AGENT_CMD mock simulating an
# agent-runner crash.
set -euo pipefail
exit 1
```

```bash
chmod +x tests/mocks/self-fix-agent tests/mocks/self-fix-agent-noop tests/mocks/self-fix-agent-fail
```

- [ ] **Step 4: Write the implementation**

Create `scripts/self-fix-pr.sh`:

```bash
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

if ( cd "$WORK_DIR" && git diff --quiet && git diff --cached --quiet ); then
  printf 'error: agent made no changes -- nothing to commit\n' >&2
  exit 1
fi

( cd "$WORK_DIR" && git add -A && git commit --quiet -m "address self-review (iteration $ITERATION)" )

if [[ "${SKIP_PUSH:-0}" != "1" ]]; then
  ( cd "$WORK_DIR" && git push --quiet origin "HEAD:$HEAD_REF" )
fi

printf 'fixed=true\n'
```

- [ ] **Step 5: Make it executable and run tests to verify they pass**

```bash
chmod +x scripts/self-fix-pr.sh
bash tests/run-script-tests.sh
```

Expected: PASS — all new `self-fix-pr` assertions green, suite exits 0.

- [ ] **Step 6: Lint**

Run: `shellcheck -x -e SC1091 scripts/self-fix-pr.sh`
Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add scripts/self-fix-pr.sh tests/mocks/self-fix-agent tests/mocks/self-fix-agent-noop tests/mocks/self-fix-agent-fail tests/run-script-tests.sh
git commit -m "feat(pre-preview): self-fix-pr.sh — the fix invocation (#81)"
```

---

## Task 5: `self-fix-loop.sh` — the bounded fix→re-review orchestrator

**Files:**

- Create: `scripts/self-fix-loop.sh`
- Create: `tests/mocks/self-fix-loop-fix-stub`
- Create: `tests/mocks/self-fix-loop-review-stub`
- Test: `tests/run-script-tests.sh` (new section)

- [ ] **Step 1: Write the failing tests**

In `tests/run-script-tests.sh`, immediately after the `section "self-fix-pr — ..."` block from Task 4, add:

```bash
section "self-fix-loop — bounded fix→re-review cycles"

SELF_FIX_LOOP="$ROOT/scripts/self-fix-loop.sh"
FIX_STUB="$MOCKS/self-fix-loop-fix-stub"
REVIEW_STUB="$MOCKS/self-fix-loop-review-stub"

LOOP_CONCERNS="$(mktemp --suffix=.json)"
printf '{"verdict":"request_changes","summary":"x","concerns":[]}' > "$LOOP_CONCERNS"

loop_run() {
  # args: <fix-log> <review-verdicts-csv> [extra env assignments...]
  local fix_log="$1" verdicts="$2"; shift 2
  local go; go="$(mktemp)"
  GITHUB_OUTPUT="$go" \
  PR_NUMBER=42 REPO=o/r HEAD_SHA=initsha HEAD_REF=fix-branch \
  INITIAL_VERDICT=request_changes CONCERNS_FILE="$LOOP_CONCERNS" \
  MAX_ITERATIONS=3 \
  FIX_CMD="$FIX_STUB" FIX_LOG="$fix_log" \
  REVIEW_SCRIPT="$REVIEW_STUB" REVIEW_VERDICTS="$verdicts" \
  NEW_HEAD_SHA=newsha \
  "$@" \
    bash "$SELF_FIX_LOOP" >/dev/null
  cat "$go"
  rm -f "$go"
}

# Fix succeeds, second re-review approves → stop at iteration 2
LOG="$(mktemp)"
out="$(loop_run "$LOG" 'request_changes,approve')"
assert_contains "$out" 'verdict=approve'   "fix→approve within cap → verdict=approve"
assert_contains "$out" 'iterations-used=2' "stops at iteration 2 (the approving one)"
fix_calls="$(cat "$LOG")"; rm -f "$LOG"
assert_equals "$(printf '%s\n' "$fix_calls" | grep -c .)" "2" "FIX_CMD invoked exactly twice"

# Cap exhausted without approve
LOG="$(mktemp)"
out="$(loop_run "$LOG" 'request_changes,request_changes,request_changes')"
assert_contains "$out" 'verdict=request_changes' "cap exhausted → final verdict still request_changes"
assert_contains "$out" 'iterations-used=3'        "used all 3 iterations"
rm -f "$LOG"

# Fix succeeds but re-review blocks → stop immediately, don't burn remaining iterations
LOG="$(mktemp)"
out="$(loop_run "$LOG" 'block')"
assert_contains "$out" 'verdict=block'      "re-review block → stops with verdict=block"
assert_contains "$out" 'iterations-used=1'  "stops after 1 iteration on block"
rm -f "$LOG"

# FIX_CMD itself fails → loop aborts, keeps last known verdict, 0 completed iterations
LOG="$(mktemp)"
out="$(loop_run "$LOG" 'approve' env FIX_FAIL=1)"
assert_contains "$out" 'verdict=request_changes' "FIX_CMD failure → verdict stays at INITIAL_VERDICT"
assert_contains "$out" 'iterations-used=0'        "FIX_CMD failure on first attempt → 0 completed iterations"
rm -f "$LOG"

# Stub verdict sequence path (Layer-2 test seam) — bypasses FIX_CMD/REVIEW_SCRIPT entirely
go="$(mktemp)"
GITHUB_OUTPUT="$go" \
PR_NUMBER=42 REPO=o/r HEAD_SHA=initsha HEAD_REF=fix-branch \
INITIAL_VERDICT=request_changes MAX_ITERATIONS=3 \
STUB_VERDICT_SEQUENCE='request_changes,approve' \
  bash "$SELF_FIX_LOOP" >/dev/null
out="$(cat "$go")"; rm -f "$go"
assert_contains "$out" 'verdict=approve'   "stub sequence → verdict=approve"
assert_contains "$out" 'iterations-used=2' "stub sequence consumes 2 entries"

# Error paths
ec="$(run_capture_ec env REPO=o/r HEAD_SHA=x HEAD_REF=y INITIAL_VERDICT=request_changes CONCERNS_FILE="$LOOP_CONCERNS" MAX_ITERATIONS=3 bash "$SELF_FIX_LOOP")"
assert_equals "$ec" "2" "missing PR_NUMBER → exit 2"

ec="$(run_capture_ec env PR_NUMBER=1 REPO=o/r HEAD_SHA=x HEAD_REF=y INITIAL_VERDICT=request_changes CONCERNS_FILE="$LOOP_CONCERNS" MAX_ITERATIONS=0 bash "$SELF_FIX_LOOP")"
assert_equals "$ec" "2" "MAX_ITERATIONS=0 → exit 2"

ec="$(run_capture_ec env PR_NUMBER=1 REPO=o/r HEAD_SHA=x HEAD_REF=y INITIAL_VERDICT=request_changes MAX_ITERATIONS=2 bash "$SELF_FIX_LOOP")"
assert_equals "$ec" "2" "missing CONCERNS_FILE (no STUB_VERDICT_SEQUENCE) → exit 2"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-script-tests.sh`
Expected: FAIL — the new `self-fix-loop` assertions error (script and mocks do not exist).

- [ ] **Step 3: Create the mocks**

Create `tests/mocks/self-fix-loop-fix-stub`:

```bash
#!/usr/bin/env bash
#
# self-fix-loop-fix-stub — self-fix-loop.sh FIX_CMD mock for Layer-1
# tests. Contract: FIX_CMD <pr-number> <concerns-json-file>, with
# ITERATION/REPO/HEAD_REF in env. Logs each call to $FIX_LOG. Exits 1 if
# FIX_FAIL=1, simulating a fix-invocation crash.
set -euo pipefail
IFS=$'\n\t'
: "${FIX_LOG:?FIX_LOG must be set}"
if [[ "${FIX_FAIL:-0}" == "1" ]]; then
  printf 'self-fix-loop-fix-stub: simulated failure\n' >&2
  exit 1
fi
printf 'pr=%s iteration=%s\n' "$1" "${ITERATION:-}" >> "$FIX_LOG"
```

Create `tests/mocks/self-fix-loop-review-stub`:

```bash
#!/usr/bin/env bash
#
# self-fix-loop-review-stub — self-fix-loop.sh REVIEW_SCRIPT mock for
# Layer-1 tests. Emits the Nth (1-indexed via $ITERATION) entry of the
# comma-separated $REVIEW_VERDICTS list to $GITHUB_OUTPUT, mirroring
# review-pr.sh's verdict output.
set -euo pipefail
IFS=$'\n\t'
: "${REVIEW_VERDICTS:?REVIEW_VERDICTS must be set}"
: "${ITERATION:?ITERATION must be set}"
IFS=',' read -ra verdicts <<< "$REVIEW_VERDICTS"
idx=$((ITERATION - 1))
verdict="${verdicts[$idx]:-block}"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'verdict=%s\n'      "$verdict" >> "$GITHUB_OUTPUT"
  printf 'summary-file=\n'              >> "$GITHUB_OUTPUT"
fi
```

```bash
chmod +x tests/mocks/self-fix-loop-fix-stub tests/mocks/self-fix-loop-review-stub
```

- [ ] **Step 4: Write the implementation**

Create `scripts/self-fix-loop.sh`:

```bash
#!/usr/bin/env bash
#
# self-fix-loop.sh — pre-preview's self-fix pass (#81 / ADR-004
# follow-up). On a `request_changes` verdict from the first review, runs
# up to MAX_ITERATIONS fix→re-review cycles: FIX_CMD applies and commits
# a fix, then REVIEW_SCRIPT re-reviews the new HEAD. Stops early on
# `approve` or `block`. The caller (the pre_preview job) only invokes this
# script when the first verdict is `request_changes` and self-fix is
# enabled — a `block` or `approve` first verdict never reaches here.
#
# Required environment variables:
#   PR_NUMBER         PR number
#   REPO              owner/repo
#   HEAD_SHA          initial PR head SHA (from the first review)
#   HEAD_REF          PR head branch name (passed through to FIX_CMD)
#   INITIAL_VERDICT   verdict from the first review-pr.sh run
#   MAX_ITERATIONS    self-fix-max-iterations input (positive integer)
#   CONCERNS_FILE     validated review JSON from the first review-pr.sh
#                     run. Not required when STUB_VERDICT_SEQUENCE is set.
#
# Optional environment variables:
#   FIX_CMD        Override for the fix invocation. Contract:
#                    $FIX_CMD <pr-number> <concerns-json-file>
#                  (ITERATION, REPO, HEAD_REF passed via env per call.)
#                  Default: <script-dir>/self-fix-pr.sh.
#   REVIEW_SCRIPT  Override path to review-pr.sh (default: sibling
#                  script). Re-review calls reuse review-pr.sh's own env
#                  contract (AGENT, AGENT_CMD, MODEL, etc.) — those must
#                  already be present in this script's own environment,
#                  since child processes inherit it unmodified.
#   NEW_HEAD_SHA   Skip the `gh pr view --json headRefOid` lookup after
#                  each fix and use this value instead. Used by Layer-1
#                  tests.
#   STUB_VERDICT_SEQUENCE
#                  Test-only. Comma-separated verdicts (e.g.
#                  "request_changes,approve") consumed one per iteration
#                  instead of really invoking FIX_CMD/REVIEW_SCRIPT. Used
#                  by Layer-2 act tests (real fix/review behavior is
#                  covered by Layer-1 tests of self-fix-pr.sh /
#                  review-pr.sh directly).
#
# Output ($GITHUB_OUTPUT):
#   verdict           final verdict (INITIAL_VERDICT unchanged if no
#                     iteration completed)
#   iterations-used   integer, 0 if no iteration completed
#   head-sha          final PR head SHA (unchanged if no iteration ran)
#
# Exit codes:
#   0   always — verdict/iterations-used/head-sha carry the outcome
#   2   required env missing or MAX_ITERATIONS not a positive integer
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_env() {
  if [[ -z "${!1:-}" ]]; then
    printf 'error: %s must be set\n' "$1" >&2
    exit 2
  fi
}

require_env PR_NUMBER
require_env REPO
require_env HEAD_SHA
require_env HEAD_REF
require_env INITIAL_VERDICT
require_env MAX_ITERATIONS

if ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] || (( MAX_ITERATIONS < 1 )); then
  printf 'error: MAX_ITERATIONS must be a positive integer (got %q)\n' "$MAX_ITERATIONS" >&2
  exit 2
fi

if [[ -z "${STUB_VERDICT_SEQUENCE:-}" ]]; then
  require_env CONCERNS_FILE
fi

emit_output() {
  local key="$1" value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
  fi
}

verdict="$INITIAL_VERDICT"
head_sha="$HEAD_SHA"
iterations_used=0

if [[ -n "${STUB_VERDICT_SEQUENCE:-}" ]]; then
  # Layer-2 test seam: bypass FIX_CMD/REVIEW_SCRIPT entirely and just
  # consume the stubbed sequence, one verdict per iteration.
  IFS=',' read -ra stub_verdicts <<< "$STUB_VERDICT_SEQUENCE"
  for (( i = 1; i <= MAX_ITERATIONS && i <= ${#stub_verdicts[@]}; i++ )); do
    verdict="${stub_verdicts[$((i - 1))]}"
    iterations_used=$i
    [[ "$verdict" == "approve" || "$verdict" == "block" ]] && break
  done
else
  FIX_CMD="${FIX_CMD:-$SCRIPT_DIR/self-fix-pr.sh}"
  REVIEW_SCRIPT="${REVIEW_SCRIPT:-$SCRIPT_DIR/review-pr.sh}"
  concerns_file="$CONCERNS_FILE"

  for (( i = 1; i <= MAX_ITERATIONS; i++ )); do
    if ! ITERATION="$i" REPO="$REPO" HEAD_REF="$HEAD_REF" \
         "$FIX_CMD" "$PR_NUMBER" "$concerns_file"; then
      printf 'self-fix-loop: fix attempt %s failed -- stopping\n' "$i" >&2
      break
    fi
    iterations_used=$i

    if [[ -n "${NEW_HEAD_SHA:-}" ]]; then
      head_sha="$NEW_HEAD_SHA"
    else
      head_sha="$(gh pr view "$PR_NUMBER" --repo "$REPO" --json headRefOid --jq '.headRefOid')"
    fi

    review_go="$(mktemp)"
    GITHUB_OUTPUT="$review_go" ITERATION="$i" PR_NUMBER="$PR_NUMBER" REPO="$REPO" HEAD_SHA="$head_sha" \
      bash "$REVIEW_SCRIPT" >/dev/null
    verdict="$(grep '^verdict=' "$review_go" | tail -n1 | cut -d= -f2-)"
    new_concerns="$(grep '^summary-file=' "$review_go" | tail -n1 | cut -d= -f2-)"
    rm -f "$review_go"
    [[ -n "$new_concerns" && -r "$new_concerns" ]] && concerns_file="$new_concerns"

    if [[ "$verdict" == "approve" || "$verdict" == "block" ]]; then
      break
    fi
  done
fi

printf 'verdict=%s\n' "$verdict"
printf 'iterations-used=%s\n' "$iterations_used"
printf 'head-sha=%s\n' "$head_sha"

emit_output verdict "$verdict"
emit_output iterations-used "$iterations_used"
emit_output head-sha "$head_sha"
```

- [ ] **Step 5: Make it executable and run tests to verify they pass**

```bash
chmod +x scripts/self-fix-loop.sh
bash tests/run-script-tests.sh
```

Expected: PASS — all new `self-fix-loop` assertions green, suite exits 0, total runtime still < 5s.

- [ ] **Step 6: Lint**

Run: `shellcheck -x -e SC1091 scripts/self-fix-loop.sh`
Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add scripts/self-fix-loop.sh tests/mocks/self-fix-loop-fix-stub tests/mocks/self-fix-loop-review-stub tests/run-script-tests.sh
git commit -m "feat(pre-preview): self-fix-loop.sh orchestrator (#81)"
```

---

## Task 6: Workflow — wire the self-fix loop into `pre_preview`

**Files:**

- Modify: `.github/workflows/agent-implement.yml`

- [ ] **Step 1: Add the three new inputs**

In the `on.workflow_call.inputs:` block, immediately after the `pre-preview:` input block (the one whose `default: false`, just before `pipeline-author-allowlist:`), add:

```yaml
      self-fix:
        description: |
          Opt-in for pre-preview's self-fix pass (#81 / ADR-004
          follow-up). When true AND the first review's verdict is
          `request_changes`, the agent attempts up to
          `self-fix-max-iterations` fix → re-review cycles before falling
          back to the block path. Ignored when `pre-preview` is false, or
          when the first verdict is `approve` (nothing to fix) or `block`
          (the agent already refused — self-fix never runs after a block).
        type: boolean
        default: false
      self-fix-max-iterations:
        description: |
          Hard cap on self-fix fix → re-review cycles. Only read when
          `self-fix: true`. Never loop unbounded.
        type: number
        default: 2
      stub-self-fix-verdict-sequence:
        description: |
          Test-only. Comma-separated verdicts (e.g.
          "request_changes,approve") consumed one per iteration by
          self-fix-loop.sh instead of really invoking the fix/re-review
          scripts. Required for end-to-end act tests of the self-fix loop
          under `stub-claude: true`.
        type: string
        default: ''
```

- [ ] **Step 2: Add the workflow_call output**

In the `on.workflow_call.outputs:` block, immediately after the `pre-preview-ready-attempted:` output block, add:

```yaml
      pre-preview-self-fix-iterations-used:
        description: |
          Iterations actually used by the self-fix loop (0 if it never
          ran). Populated only when `stub-review-verdict` /
          `stub-self-fix-verdict-sequence` is set.
        value: ${{ jobs.pre_preview.outputs.self-fix-iterations-used }}
```

- [ ] **Step 3: Add the job output**

In the `pre_preview` job's `outputs:` block, change:

```yaml
    outputs:
      merge-attempted: ${{ steps.verify_mock.outputs.merge-attempted }}
      ready-attempted: ${{ steps.verify_mock.outputs.ready-attempted }}
```

to:

```yaml
    outputs:
      merge-attempted: ${{ steps.verify_mock.outputs.merge-attempted }}
      ready-attempted: ${{ steps.verify_mock.outputs.ready-attempted }}
      self-fix-iterations-used: ${{ steps.final.outputs.iterations-used }}
```

- [ ] **Step 4: Add the "Self-fix loop" step**

In the `pre_preview` job's steps, immediately after the existing `Resolve review verdict` step (id: `verdict`), add:

```yaml
      - name: Self-fix loop (pre-preview optional self-fix pass)
        if: |
          steps.find_pr.outputs.found == 'true'
          && steps.verdict.outputs.value == 'request_changes'
          && inputs.self-fix
        id: self_fix
        env:
          GH_TOKEN: ${{ github.token }}
          REPO: ${{ github.repository }}
          PR_NUMBER: ${{ steps.find_pr.outputs.pr-number }}
          HEAD_SHA: ${{ steps.find_pr.outputs.head-sha }}
          HEAD_REF: ${{ steps.find_pr.outputs.head-ref }}
          INITIAL_VERDICT: ${{ steps.verdict.outputs.value }}
          CONCERNS_FILE: ${{ steps.review.outputs.summary-file }}
          MAX_ITERATIONS: ${{ inputs.self-fix-max-iterations }}
          AGENT: claude
          AGENT_CMD: ${{ github.workspace }}/.claude-pipeline/scripts/lib/agent-cmd-claude.sh
          FIX_AGENT_CMD: ${{ github.workspace }}/.claude-pipeline/scripts/lib/agent-cmd-claude-fix.sh
          MODEL: ${{ inputs.review-model }}
          CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          STUB_VERDICT_SEQUENCE: ${{ inputs.stub-self-fix-verdict-sequence }}
        run: bash .claude-pipeline/scripts/self-fix-loop.sh
```

- [ ] **Step 5: Add the "Resolve final verdict" step**

Immediately after the `Self-fix loop` step just added, add:

```yaml
      - name: Resolve final verdict (post self-fix)
        if: steps.find_pr.outputs.found == 'true'
        id: final
        env:
          LOOP_VERDICT: ${{ steps.self_fix.outputs.verdict }}
          LOOP_ITERATIONS: ${{ steps.self_fix.outputs.iterations-used }}
          FIRST_VERDICT: ${{ steps.verdict.outputs.value }}
        run: |
          {
            printf 'verdict=%s\n' "${LOOP_VERDICT:-$FIRST_VERDICT}"
            printf 'iterations-used=%s\n' "${LOOP_ITERATIONS:-0}"
          } >> "$GITHUB_OUTPUT"
```

- [ ] **Step 6: Repoint the promote step at the final verdict**

Change the `Promote draft to ready (pre-preview — no auto-merge)` step's `if:` from:

```yaml
        if: |
          steps.find_pr.outputs.found == 'true'
          && steps.verdict.outputs.value == 'approve'
```

to:

```yaml
        if: |
          steps.find_pr.outputs.found == 'true'
          && steps.final.outputs.verdict == 'approve'
```

- [ ] **Step 7: Repoint the block step at the final verdict + pass self-fix env**

Change the `Mark issue blocked when review refuses or PR missing` step from:

```yaml
      - name: Mark issue blocked when review refuses or PR missing
        if: |
          steps.find_pr.outputs.found != 'true'
          || steps.verdict.outputs.value != 'approve'
        env:
          GH_TOKEN: ${{ github.token }}
          REPO: ${{ github.repository }}
          ISSUE_NUMBER: ${{ inputs.issue-number }}
          PR_NUMBER: ${{ steps.find_pr.outputs.pr-number }}
          FOUND: ${{ steps.find_pr.outputs.found }}
          VERDICT: ${{ steps.verdict.outputs.value }}
          MODE: pre-preview
        run: bash .claude-pipeline/scripts/post-auto-review-block.sh
```

to:

```yaml
      - name: Mark issue blocked when review refuses or PR missing
        if: |
          steps.find_pr.outputs.found != 'true'
          || steps.final.outputs.verdict != 'approve'
        env:
          GH_TOKEN: ${{ github.token }}
          REPO: ${{ github.repository }}
          ISSUE_NUMBER: ${{ inputs.issue-number }}
          PR_NUMBER: ${{ steps.find_pr.outputs.pr-number }}
          FOUND: ${{ steps.find_pr.outputs.found }}
          VERDICT: ${{ steps.final.outputs.verdict }}
          SELF_FIX_ITERATIONS: ${{ steps.final.outputs.iterations-used }}
          SELF_FIX_MAX: ${{ inputs.self-fix-max-iterations }}
          MODE: pre-preview
        run: bash .claude-pipeline/scripts/post-auto-review-block.sh
```

- [ ] **Step 8: Lint the workflow**

Run: `actionlint .github/workflows/agent-implement.yml`
Expected: no output, exit 0.

- [ ] **Step 9: Commit**

```bash
git add .github/workflows/agent-implement.yml
git commit -m "feat(workflow): wire self-fix loop into pre_preview job (#81)"
```

---

## Task 7: Layer-2 act scenarios

**Files:**

- Modify: `.github/workflows/agent-implement.test.yml`

- [ ] **Step 1: Add two call jobs**

At the end of `.github/workflows/agent-implement.test.yml`, immediately after the existing `call-pre-preview-precedence:` job block, add:

```yaml
  # ─── Self-fix pass (#81 / ADR-004 follow-up) ──────────────────────────────
  # self-fix is exercised via stub-self-fix-verdict-sequence, which drives
  # self-fix-loop.sh's stub branch directly (bypassing the fix/re-review
  # scripts themselves — those are covered by Layer-1 tests). This proves
  # the workflow's wiring: gating, the final-verdict resolution, and the
  # promote/block steps reading from it correctly.

  call-pre-preview-self-fix-approve:
    name: Reusable workflow — pre-preview self-fix fixes then approves
    uses: ./.github/workflows/agent-implement.yml
    with:
      issue-number: 9010
      timeout-minutes: 10
      local-scripts: true
      stub-claude: true
      stub-fixture: success
      pre-preview: true
      dry-run: true
      stub-pre-preview-enabled: true
      stub-review-verdict: request_changes
      self-fix: true
      self-fix-max-iterations: 3
      stub-self-fix-verdict-sequence: "request_changes,approve"
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: not-used-by-stub

  call-pre-preview-self-fix-exhausted:
    name: Reusable workflow — pre-preview self-fix cap exhausted
    uses: ./.github/workflows/agent-implement.yml
    with:
      issue-number: 9011
      timeout-minutes: 10
      local-scripts: true
      stub-claude: true
      stub-fixture: success
      pre-preview: true
      dry-run: true
      stub-pre-preview-enabled: true
      stub-review-verdict: request_changes
      self-fix: true
      self-fix-max-iterations: 2
      stub-self-fix-verdict-sequence: "request_changes,request_changes"
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: not-used-by-stub
```

- [ ] **Step 2: Add the two assertion jobs**

After the existing `verify-pre-preview-precedence:` job, add:

```yaml
  verify-pre-preview-self-fix-approve:
    name: Assert self-fix fixes then approves → promoted, no merge
    needs: call-pre-preview-self-fix-approve
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: read
    env:
      READY:      ${{ needs.call-pre-preview-self-fix-approve.outputs.pre-preview-ready-attempted }}
      ATTEMPTED:  ${{ needs.call-pre-preview-self-fix-approve.outputs.pre-preview-merge-attempted }}
      ITERATIONS: ${{ needs.call-pre-preview-self-fix-approve.outputs.pre-preview-self-fix-iterations-used }}
    steps:
      - name: Assert promoted after 2 self-fix iterations, still no merge
        run: |
          fail=0
          [[ "$READY" == "true" ]]      || { echo "::error::ready-attempted=$READY (want true — self-fix approve must promote)"; fail=1; }
          [[ "$ATTEMPTED" == "false" ]] || { echo "::error::merge-attempted=$ATTEMPTED (want false)"; fail=1; }
          [[ "$ITERATIONS" == "2" ]]    || { echo "::error::self-fix-iterations-used=$ITERATIONS (want 2)"; fail=1; }
          (( fail == 0 )) || exit 1
          echo "self-fix approve OK: ready=$READY merge=$ATTEMPTED iterations=$ITERATIONS"

  verify-pre-preview-self-fix-exhausted:
    name: Assert self-fix cap exhausted → draft, no promote, no merge
    needs: call-pre-preview-self-fix-exhausted
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: read
    env:
      READY:      ${{ needs.call-pre-preview-self-fix-exhausted.outputs.pre-preview-ready-attempted }}
      ATTEMPTED:  ${{ needs.call-pre-preview-self-fix-exhausted.outputs.pre-preview-merge-attempted }}
      ITERATIONS: ${{ needs.call-pre-preview-self-fix-exhausted.outputs.pre-preview-self-fix-iterations-used }}
    steps:
      - name: Assert not promoted after cap exhausted, still no merge
        run: |
          fail=0
          [[ "$READY" == "false" ]]     || { echo "::error::ready-attempted=$READY (want false — cap-exhausted must NOT promote)"; fail=1; }
          [[ "$ATTEMPTED" == "false" ]] || { echo "::error::merge-attempted=$ATTEMPTED (want false)"; fail=1; }
          [[ "$ITERATIONS" == "2" ]]    || { echo "::error::self-fix-iterations-used=$ITERATIONS (want 2 — cap reached)"; fail=1; }
          (( fail == 0 )) || exit 1
          echo "self-fix cap-exhausted OK: ready=$READY merge=$ATTEMPTED iterations=$ITERATIONS"
```

- [ ] **Step 3: Lint the test workflow**

Run: `actionlint .github/workflows/agent-implement.test.yml`
Expected: no output, exit 0.

- [ ] **Step 4: (Optional) run the act scenarios locally if `act` + Docker are available**

Run: `act pull_request -W .github/workflows/agent-implement.test.yml -j verify-pre-preview-self-fix-approve`
Expected: job passes (`self-fix approve OK: ready=true merge=false iterations=2`).
If `act`/Docker is unavailable, skip — these run in CI on the pushed PR (Task 9).

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/agent-implement.test.yml
git commit -m "test(act): pre-preview self-fix approve/cap-exhausted scenarios (#81)"
```

---

## Task 8: Docs — CONSUMER-SETUP.md + ADR-004 addendum

**Files:**

- Modify: `docs/CONSUMER-SETUP.md`
- Modify: `docs/DECISIONS.md`

- [ ] **Step 1: Update the pre-preview line in CONSUMER-SETUP.md**

In `docs/CONSUMER-SETUP.md`, change:

```text
3. **Pre-preview** — labeled-issue → draft PR → agent reviews its own PR → on approve, promote draft→ready; a human merges. No envelope, no auto-merge. Opt in with `pre-preview: true` + the `ai-pre-preview` label. See ADR-004.
```

to:

```text
3. **Pre-preview** — labeled-issue → draft PR → agent reviews its own PR → on approve, promote draft→ready; a human merges. No envelope, no auto-merge. Opt in with `pre-preview: true` + the `ai-pre-preview` label. On `request_changes`, optionally opt into a bounded self-fix pass with `self-fix: true` (+ `self-fix-max-iterations`, default 2) — the agent attempts to fix its own findings and re-review before falling back to `ai:review-blocked`. See ADR-004.
```

- [ ] **Step 2: Add the ADR-004 addendum to DECISIONS.md**

In `docs/DECISIONS.md`, find the `## ADR-004 — Pre-preview mode (agent self-review → human merge) (2026-06-04)` section. Immediately after its `### Consequences` bullet list (the one ending with `...pre-preview` / `stub-pre-preview-enabled` inputs and `pre-preview-{merge,ready}-attempted` outputs.`), and before the next `## ADR-005` heading, add:

```markdown

### Addendum — Self-fix pass delivered (2026-07-31)

**Tracking:** [#81](https://github.com/freaxnx01/agent-workflow/issues/81)

The self-fix pass deferred above is delivered. On a `request_changes`
verdict, opt-in `self-fix: true` runs up to `self-fix-max-iterations`
(default 2) fix → re-review cycles via `scripts/self-fix-loop.sh` /
`scripts/self-fix-pr.sh` before falling back to the block path. `block` and
missing-PR verdicts are unaffected — self-fix only ever runs after
`request_changes`. Still no merge envelope and no auto-merge; self-fix
only changes what the human reviewer eventually sees. Cap-exhausted blocks
get distinct wording in `post-auto-review-block.sh` ("self-fix exhausted
after N/M iterations") via new `SELF_FIX_ITERATIONS` / `SELF_FIX_MAX` env,
byte-identical to the original wording when self-fix didn't run.
```

- [ ] **Step 3: Confirm nothing regressed**

Run: `bash tests/run-script-tests.sh`
Expected: PASS (docs don't affect scripts; this just confirms nothing regressed).

- [ ] **Step 4: Commit**

```bash
git add docs/CONSUMER-SETUP.md docs/DECISIONS.md
git commit -m "docs: self-fix pass — CONSUMER-SETUP + ADR-004 addendum (#81)"
```

---

## Task 9: Push, open PR, confirm CI green, update #81

**Files:** none (integration)

- [ ] **Step 1: Run the full local gate once more**

```bash
bash tests/run-script-tests.sh
shellcheck -x -e SC1091 scripts/find-pipeline-pr.sh scripts/post-auto-review-block.sh \
  scripts/self-fix-pr.sh scripts/self-fix-loop.sh scripts/lib/agent-cmd-claude-fix.sh
actionlint
```

Expected: all green / no output.

- [ ] **Step 2: Push the branch**

```bash
git push -u origin <branch-name>
```

- [ ] **Step 3: Open the PR**

```bash
gh pr create -R freaxnx01/agent-workflow --base main --head <branch-name> \
  --title "feat(pre-preview): optional self-fix pass (#81)" \
  --body "Implements the self-fix pass per docs/superpowers/specs/2026-07-31-pre-preview-self-fix-design.md and the ADR-004 addendum. Closes #81."
```

- [ ] **Step 4: Confirm CI green**

Run: `gh pr checks <PR#> -R freaxnx01/agent-workflow`
Expected: `actionlint`, `shellcheck`, the new `verify-pre-preview-self-fix-*` jobs, and all pre-existing `verify-pre-preview-*` / `verify-auto-review-*` jobs pass (no regression).

- [ ] **Step 5: Update issue #81**

Check off the acceptance-criteria items now satisfied. Do not auto-close — a human merges this PR, which closes #81 via "Closes #81".

---

## Self-Review notes (author)

- **Spec coverage:** opt-in inputs `self-fix` / `self-fix-max-iterations` (Task 6) · gating only on `request_changes`, never on `block`/missing (Task 6 step 4, `self-fix-loop.sh`'s own doc comment) · bounded iteration loop with one-commit-per-iteration hygiene (Task 5, Task 4) · full re-review reusing `review-pr.sh` unmodified (Task 5) · promote gated on final verdict (Task 6 step 6) · cap-exhausted distinct block wording via `SELF_FIX_ITERATIONS`/`SELF_FIX_MAX` (Task 2) · Layer-1 tests for every new/modified script (Tasks 1,2,4,5) · Layer-2 act scenarios (Task 7) · docs + ADR-004 addendum (Task 8). All spec sections map to a task; the spec's three open items (fix-prompt template, diff-size guard, stub wiring) are resolved in Tasks 3, 4 (`self-fix-pr.sh` inherits `review-pr.sh`'s own `MAX_DIFF_BYTES` guard on the re-review call — no separate guard needed since it never diffs independently), and Task 6/7 (`STUB_VERDICT_SEQUENCE` + `stub-self-fix-verdict-sequence` input) respectively.
- **No placeholders:** every script/YAML/edit shows full content.
- **Name consistency:** `self-fix-loop.sh`, `self-fix-pr.sh`, inputs `self-fix` / `self-fix-max-iterations` / `stub-self-fix-verdict-sequence`, job step ids `self_fix` / `final`, outputs `self-fix-iterations-used` / `pre-preview-self-fix-iterations-used`, env `SELF_FIX_ITERATIONS` / `SELF_FIX_MAX` / `STUB_VERDICT_SEQUENCE` / `NEW_HEAD_SHA` — used identically across all tasks.
