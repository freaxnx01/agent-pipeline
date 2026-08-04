# Auto-Fix Retry Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On a `request_changes` verdict from `auto_review` (ADR-002) or `pre_preview` (ADR-004), optionally dispatch the issue's original implementer agent (Claude or OpenCode, per `classify-agent.sh`) to fix its own findings through bounded fix→re-review cycles, before falling back to the existing `ai:review-blocked` human-review path.

**Architecture:** Generalizes issue #81's Claude-only, pre-preview-only self-fix design (spec/plan merged in #218, never implemented) into a single `fix_retry` job shared by both `auto_review` and `pre_preview`. Two new scripts — `self-fix-loop.sh` (bounded fix→re-review orchestrator) and `self-fix-pr.sh` (checks out the PR branch, runs the resolved agent, commits) — plus two small agent wrappers (`agent-cmd-claude-fix.sh`, `agent-cmd-opencode-fix.sh`). `implement` exposes which agent/model it used; `auto_review`/`pre_preview` expose the first verdict + PR identity + concerns JSON; `fix_retry` consumes all of that, loops, and on the final verdict either promotes (re-checking ADR-002's merge envelope when the source was `auto_review`) or stamps `ai:review-blocked` with distinct "self-fix exhausted" wording. `auto_review`/`pre_preview`'s own block steps gain a guard so they don't prematurely block while `fix_retry` is still working.

**Tech Stack:** Bash scripts (fixture-tested via `tests/run-script-tests.sh`), GitHub Actions reusable workflow (`actionlint` + `shellcheck` lint, `act` layer-2 test).

**Reference spec:** `docs/superpowers/specs/2026-08-01-auto-fix-retry-loop-design.md`
**Supersedes (unimplemented):** `docs/superpowers/specs/2026-07-31-pre-preview-self-fix-design.md` / `docs/superpowers/plans/2026-07-31-pre-preview-self-fix.md` (#81) — no code from that plan exists in the repo yet, so this plan writes the generalized scripts directly rather than modifying #81's output.

## Global Constraints

- Bash scripts: `set -euo pipefail` + `IFS=$'\n\t'` at the top of every script (repo convention, `.ai/stacks/ci.md`).
- Quote every variable expansion; `[[ ... ]]` over `[ ... ]`; `$(...)` over backticks.
- Exit codes are part of the API: `0` success, `1` generic error, `2` usage/env error (see each script's own header comment for its specific codes).
- No new inline bash step longer than 5 lines inside workflow YAML without extracting to `scripts/`.
- Action references stay pinned by full SHA (no floating tags) — none of this plan's tasks touch action `uses:` lines, so no new pins are introduced.
- `contents: write` / `pull-requests: write` / `issues: write` — the new `fix_retry` job needs the same permission set as `auto_review`/`pre_preview` (it pushes commits and comments).
- Layer-1 tests live in `tests/run-script-tests.sh`; run with `bash tests/run-script-tests.sh` (must finish < 5s, exit 0).
- Lint every changed/new script with `shellcheck -x -e SC1091 <file>.sh`; lint workflow YAML with `actionlint`.
- Commit after each task.

---

## Task 1: `find-pipeline-pr.sh` emits `head-ref`

`fix_retry` needs the PR's branch name (not just its head SHA) to check it out directly. Extend the existing PR-discovery script to report it. (Same change #81 specified — `head-ref` is a small, independently useful addition regardless of which spec ships it.)

**Files:**

- Modify: `scripts/find-pipeline-pr.sh`
- Test: `tests/run-script-tests.sh` (`find-pipeline-pr` section)

- [ ] **Step 1: Write the failing test**

In `tests/run-script-tests.sh`, in `section "find-pipeline-pr — discover the draft PR opened for an issue"`, find:

```bash
out="$(find_pr_run env ISSUE_NUMBER=42 REPO=o/r \
        PIPELINE_PRS_JSON='[{"number":17,"isDraft":true,"headRefOid":"deadbeef","author":{"login":"github-actions[bot]"}}]')"
assert_contains "$out" 'found=true'         "single draft PR → found=true"
assert_contains "$out" 'pr-number=17'       "emits pr-number"
assert_contains "$out" 'head-sha=deadbeef'  "emits head-sha"
```

Replace it with:

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

In `scripts/find-pipeline-pr.sh`, change:

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

Finally, update the header comment's `Output:` list from:

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
Expected: PASS — `✓ emits head-ref (branch name)`, and all pre-existing `find-pipeline-pr` assertions still green (their fixtures lack `headRefName`, so `head_ref` resolves to `""` via `// ""` — no regression).

- [ ] **Step 5: Lint**

Run: `shellcheck -x -e SC1091 scripts/find-pipeline-pr.sh`
Expected: no output, exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/find-pipeline-pr.sh tests/run-script-tests.sh
git commit -m "feat(review): find-pipeline-pr.sh emits head-ref (#193)"
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

# MODE=auto-review also gets the distinct wording (this spec covers both
# modes, unlike #81 which was pre-preview-only)
LOG="$(mktemp)"
PATH="$MOCKS:$PATH" GH_MOCK_LOG="$LOG" \
REPO=o/r ISSUE_NUMBER=42 PR_NUMBER=100 FOUND=true \
VERDICT=request_changes MODE=auto-review \
SELF_FIX_ITERATIONS=1 SELF_FIX_MAX=2 \
  bash "$POST_BLOCK" >/dev/null
calls="$(cat "$LOG")"; rm -f "$LOG"
assert_contains "$calls" 'Auto-merge held: self-fix exhausted after 1/2 iteration(s) — last verdict: request_changes' "MODE=auto-review also gets self-fix wording"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-script-tests.sh`
Expected: FAIL — the three new assertions error (script doesn't know about `SELF_FIX_ITERATIONS` yet).

- [ ] **Step 3: Write minimal implementation**

In `scripts/post-auto-review-block.sh`, change:

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

Also extend the header comment's "Optional environment variables" list, immediately after the `MODE` line, adding:

```text
#   SELF_FIX_ITERATIONS  Iterations the self-fix retry loop actually used
#                        (#193). "0" or unset → unchanged wording.
#   SELF_FIX_MAX         The self-fix iteration cap, for the "exhausted"
#                        wording. Only read when SELF_FIX_ITERATIONS != "0".
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-script-tests.sh`
Expected: PASS — all three new assertions green, and all pre-existing `post-auto-review-block` assertions (self-mod, missing-PR, plain verdict, both `MODE` values, envelope-fail) still green.

- [ ] **Step 5: Lint**

Run: `shellcheck -x -e SC1091 scripts/post-auto-review-block.sh`
Expected: no output, exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/post-auto-review-block.sh tests/run-script-tests.sh
git commit -m "feat(review): self-fix-exhausted block wording (#193)"
```

---

## Task 3: Self-fix prompt template + Claude fix-mode wrapper

Two small library files `self-fix-pr.sh` (Task 5) depends on. Neither has an independent Layer-1 fixture test — same precedent as `agent-cmd-claude.sh`, which is only exercised via lint + the scripts that call it.

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
# agent-cmd-claude-fix.sh — self-fix-pr.sh's Claude FIX_AGENT_CMD wrapper.
# Contract: FIX_AGENT_CMD <prompt-file>.
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
git commit -m "feat(self-fix): self-fix prompt template + Claude fix wrapper (#193)"
```

---

## Task 4: OpenCode fix-mode wrapper

Without this, self-fix would silently only work for Claude-implemented issues — undermining the point that the fix must come from the original implementer, not a substitute.

**Files:**

- Create: `scripts/lib/agent-cmd-opencode-fix.sh`

- [ ] **Step 1: Create the OpenCode fix-mode wrapper**

Create `scripts/lib/agent-cmd-opencode-fix.sh`:

```bash
#!/usr/bin/env bash
#
# agent-cmd-opencode-fix.sh — self-fix-pr.sh's OpenCode FIX_AGENT_CMD
# wrapper. Contract: FIX_AGENT_CMD <prompt-file>.
#
# Mirrors the `implement` job's "Run OpenCode" step (agent-implement.yml)
# but operates on the already-checked-out PR branch instead of a fresh
# clone, and lets the agent edit files directly rather than emitting a
# --format json result for adapt-opencode-result.sh to parse — the caller
# (self-fix-pr.sh) commits/pushes afterward, same division of labor as
# agent-cmd-claude-fix.sh.
#
# EXPERIMENTAL: reuses the same unverified opencode agentic-edit surface
# as the implement job's OpenCode path (see #58) — not new risk, but not
# independently verified end-to-end either (per #193's design doc).
#
# MODEL is optional; prefixed with openrouter/ unless already prefixed,
# same rule as the implement job's Run OpenCode step.
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

opencode "${args[@]}" -- "$(cat "$prompt")" > /dev/null
```

- [ ] **Step 2: Make it executable and lint**

```bash
chmod +x scripts/lib/agent-cmd-opencode-fix.sh
shellcheck -x -e SC1091 scripts/lib/agent-cmd-opencode-fix.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add scripts/lib/agent-cmd-opencode-fix.sh
git commit -m "feat(self-fix): OpenCode fix wrapper (#193)"
```

---

## Task 5: `self-fix-pr.sh` — the fix invocation, routed by agent

**Files:**

- Create: `scripts/self-fix-pr.sh`
- Create: `tests/mocks/self-fix-agent` (happy-path FIX_AGENT_CMD mock)
- Create: `tests/mocks/self-fix-agent-noop` (no-op FIX_AGENT_CMD mock)
- Create: `tests/mocks/self-fix-agent-fail` (crashing FIX_AGENT_CMD mock)
- Create: `tests/mocks/self-fix-lib/agent-cmd-claude-fix.sh` (AGENT-resolution mock, "claude" marker)
- Create: `tests/mocks/self-fix-lib/agent-cmd-opencode-fix.sh` (AGENT-resolution mock, "opencode" marker)
- Test: `tests/run-script-tests.sh` (new section)

**Interfaces:**

- Consumes: nothing from earlier tasks (`scripts/lib/self-fix-prompt.md` from Task 3 is its own default template).
- Produces: `self-fix-pr.sh <pr-number> <concerns-json-file>` — env contract `REPO`, `HEAD_REF`, `ITERATION` (required), `AGENT` (`claude`|`opencode`, default `claude`), `FIX_AGENT_CMD` (override), `FIX_LIB_DIR` (test seam, default `<script-dir>/lib`), `MODEL`, `PROMPT_TEMPLATE`, `WORK_DIR`, `SKIP_CLONE`, `SKIP_PUSH`. Prints `fixed=true` on success. Exit `0` success, `1` fix/commit/push failure or no-op agent, `2` bad args/env/AGENT.

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

# AGENT-based default resolution: claude → agent-cmd-claude-fix.sh
REPO_DIR="$(make_self_fix_repo)"
out="$(WORK_DIR="$REPO_DIR" SKIP_CLONE=1 SKIP_PUSH=1 \
       REPO=o/r HEAD_REF=fix-branch ITERATION=1 AGENT=claude \
       FIX_LIB_DIR="$MOCKS/self-fix-lib" \
       bash "$SELF_FIX_PR" 99 "$CONCERNS")"
assert_contains "$out" 'fixed=true' "AGENT=claude resolves a working wrapper"
edited="$(cat "$REPO_DIR/file.txt")"
assert_contains "$edited" 'fixed-by-claude' "AGENT=claude resolves agent-cmd-claude-fix.sh specifically"
rm -rf "$REPO_DIR"

# AGENT-based default resolution: opencode → agent-cmd-opencode-fix.sh
REPO_DIR="$(make_self_fix_repo)"
out="$(WORK_DIR="$REPO_DIR" SKIP_CLONE=1 SKIP_PUSH=1 \
       REPO=o/r HEAD_REF=fix-branch ITERATION=1 AGENT=opencode \
       FIX_LIB_DIR="$MOCKS/self-fix-lib" \
       bash "$SELF_FIX_PR" 99 "$CONCERNS")"
assert_contains "$out" 'fixed=true' "AGENT=opencode resolves a working wrapper"
edited="$(cat "$REPO_DIR/file.txt")"
assert_contains "$edited" 'fixed-by-opencode' "AGENT=opencode resolves agent-cmd-opencode-fix.sh specifically"
rm -rf "$REPO_DIR"

# Invalid AGENT → exit 2
ec="$(run_capture_ec env REPO=o/r HEAD_REF=x ITERATION=1 AGENT=gpt5 bash "$SELF_FIX_PR" 99 "$CONCERNS")"
assert_equals "$ec" "2" "invalid AGENT → exit 2"

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

Create `tests/mocks/self-fix-lib/agent-cmd-claude-fix.sh`:

```bash
#!/usr/bin/env bash
#
# AGENT-resolution mock for self-fix-pr.sh's FIX_LIB_DIR test seam —
# proves AGENT=claude resolves specifically to this file, not the
# opencode sibling.
set -euo pipefail
IFS=$'\n\t'
printf 'fixed-by-claude\n' >> file.txt
```

Create `tests/mocks/self-fix-lib/agent-cmd-opencode-fix.sh`:

```bash
#!/usr/bin/env bash
#
# AGENT-resolution mock for self-fix-pr.sh's FIX_LIB_DIR test seam —
# proves AGENT=opencode resolves specifically to this file, not the
# claude sibling.
set -euo pipefail
IFS=$'\n\t'
printf 'fixed-by-opencode\n' >> file.txt
```

```bash
chmod +x tests/mocks/self-fix-agent tests/mocks/self-fix-agent-noop tests/mocks/self-fix-agent-fail \
  tests/mocks/self-fix-lib/agent-cmd-claude-fix.sh tests/mocks/self-fix-lib/agent-cmd-opencode-fix.sh
```

- [ ] **Step 4: Write the implementation**

Create `scripts/self-fix-pr.sh`:

```bash
#!/usr/bin/env bash
#
# self-fix-pr.sh — self-fix-loop.sh's default FIX_CMD. Checks out the PR's
# head branch, runs the ORIGINAL IMPLEMENTER'S agent (claude | opencode,
# per AGENT) agentically against the prior review's concerns
# (scripts/lib/self-fix-prompt.md), then commits the fix. Part of the
# auto-fix retry loop (#193 — generalizes #81's Claude-only pre-preview
# design to route to whichever agent implemented the issue).
#
# Contract: self-fix-pr.sh <pr-number> <concerns-json-file>
#
# Required environment variables:
#   REPO        owner/repo
#   HEAD_REF    PR head branch name — checked out and pushed to
#   ITERATION   integer, used in the commit message
#
# Optional environment variables:
#   AGENT             claude | opencode — which agent implemented the
#                     issue (needs.implement.outputs.agent). Default:
#                     claude. Selects the default FIX_AGENT_CMD wrapper.
#   FIX_AGENT_CMD     Override the agent invocation entirely. Contract:
#                       $FIX_AGENT_CMD <prompt-file>
#                     Agent edits files directly in the CWD. Takes
#                     precedence over AGENT-based resolution.
#   FIX_LIB_DIR       Directory the AGENT-based default resolves wrapper
#                     scripts from. Default: <script-dir>/lib. Test seam —
#                     lets Layer-1 tests point AGENT resolution at mock
#                     wrappers without touching the real lib/ scripts.
#   MODEL             Model id passed to FIX_AGENT_CMD.
#   PROMPT_TEMPLATE   Override path to lib/self-fix-prompt.md.
#   WORK_DIR          Directory to operate in. Default: mktemp -d.
#   SKIP_CLONE        "1" to skip `gh repo clone` / `git fetch` and operate
#                     directly in WORK_DIR (already a checked-out git repo
#                     on HEAD_REF). Used by Layer-1 tests and by the
#                     fix_retry job (which checks out head-ref itself via
#                     actions/checkout).
#   SKIP_PUSH         "1" to skip `git push` (Layer-1 tests assert the
#                     local commit instead of a network push).
#
# Exit codes:
#   0  fix committed (and pushed, unless SKIP_PUSH=1)
#   1  checkout / agent / commit / push failure, or agent made no changes
#   2  required env or args missing, or AGENT invalid
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

AGENT="${AGENT:-claude}"
case "$AGENT" in
  claude|opencode) ;;
  *)
    printf 'error: AGENT must be one of: claude | opencode (got %q)\n' "$AGENT" >&2
    exit 2
    ;;
esac

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
  FIX_LIB_DIR="${FIX_LIB_DIR:-$SCRIPT_DIR/lib}"
  case "$AGENT" in
    claude)   FIX_AGENT_CMD="$FIX_LIB_DIR/agent-cmd-claude-fix.sh" ;;
    opencode) FIX_AGENT_CMD="$FIX_LIB_DIR/agent-cmd-opencode-fix.sh" ;;
  esac
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
git add scripts/self-fix-pr.sh tests/mocks/self-fix-agent tests/mocks/self-fix-agent-noop \
  tests/mocks/self-fix-agent-fail tests/mocks/self-fix-lib tests/run-script-tests.sh
git commit -m "feat(self-fix): self-fix-pr.sh — agent-routed fix invocation (#193)"
```

---

## Task 6: `self-fix-loop.sh` — the bounded fix→re-review orchestrator

Keeps the fix-agent's routing (`FIX_AGENT`/`FIX_MODEL`) separate from the re-review agent's fixed identity (`AGENT=claude`, review-model) so the two never collide on the same env var when both are set on the calling job step.

**Files:**

- Create: `scripts/self-fix-loop.sh`
- Create: `tests/mocks/self-fix-loop-fix-stub`
- Create: `tests/mocks/self-fix-loop-review-stub`
- Test: `tests/run-script-tests.sh` (new section)

**Interfaces:**

- Consumes: `self-fix-pr.sh <pr-number> <concerns-file>` (Task 5) as the default `FIX_CMD`; `review-pr.sh` (unmodified, existing script) as the default `REVIEW_SCRIPT`.
- Produces: `$GITHUB_OUTPUT` keys `verdict`, `iterations-used`, `head-sha` — consumed by the `fix_retry` job (Task 9).

- [ ] **Step 1: Write the failing tests**

In `tests/run-script-tests.sh`, immediately after the `section "self-fix-pr — ..."` block from Task 5, add:

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

# FIX_AGENT/FIX_MODEL are forwarded to FIX_CMD as AGENT/MODEL, distinct
# from this script's own inherited AGENT (which stays claude for re-review)
LOG="$(mktemp)"
go="$(mktemp)"
GITHUB_OUTPUT="$go" \
PR_NUMBER=42 REPO=o/r HEAD_SHA=initsha HEAD_REF=fix-branch \
INITIAL_VERDICT=request_changes CONCERNS_FILE="$LOOP_CONCERNS" MAX_ITERATIONS=3 \
FIX_CMD="$FIX_STUB" FIX_LOG="$LOG" FIX_AGENT=opencode FIX_MODEL=some-model \
REVIEW_SCRIPT="$REVIEW_STUB" REVIEW_VERDICTS='approve' NEW_HEAD_SHA=newsha \
AGENT=claude \
  bash "$SELF_FIX_LOOP" >/dev/null
rm -f "$go"
fix_calls="$(cat "$LOG")"; rm -f "$LOG"
assert_contains "$fix_calls" 'agent=opencode model=some-model' "FIX_AGENT/FIX_MODEL forwarded to FIX_CMD as AGENT/MODEL"

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
# ITERATION/REPO/HEAD_REF/AGENT/MODEL in env. Logs each call to $FIX_LOG.
# Exits 1 if FIX_FAIL=1, simulating a fix-invocation crash.
set -euo pipefail
IFS=$'\n\t'
: "${FIX_LOG:?FIX_LOG must be set}"
if [[ "${FIX_FAIL:-0}" == "1" ]]; then
  printf 'self-fix-loop-fix-stub: simulated failure\n' >&2
  exit 1
fi
printf 'pr=%s iteration=%s agent=%s model=%s\n' "$1" "${ITERATION:-}" "${AGENT:-}" "${MODEL:-}" >> "$FIX_LOG"
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
# self-fix-loop.sh — the auto-fix retry loop's orchestrator (#193,
# generalizing #81's Claude-only pre-preview design). On a
# `request_changes` verdict from the first review, runs up to
# MAX_ITERATIONS fix→re-review cycles: FIX_CMD applies and commits a fix,
# then REVIEW_SCRIPT re-reviews the new HEAD. Stops early on `approve` or
# `block`. The caller (the fix_retry job) only invokes this script when
# the first verdict is `request_changes` and self-fix is enabled — an
# `approve` or `block` first verdict never reaches here.
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
#                  (ITERATION, REPO, HEAD_REF, AGENT, MODEL passed via env
#                  per call — AGENT/MODEL come from FIX_AGENT/FIX_MODEL
#                  below, not from this script's own inherited AGENT/MODEL,
#                  which the re-review call below needs to stay at the
#                  fixed review-agent identity.) Default:
#                  <script-dir>/self-fix-pr.sh.
#   FIX_AGENT      claude | opencode — forwarded to FIX_CMD as AGENT.
#                  Default: claude.
#   FIX_MODEL      Forwarded to FIX_CMD as MODEL. Default: empty.
#   REVIEW_SCRIPT  Override path to review-pr.sh (default: sibling
#                  script). Re-review calls reuse review-pr.sh's own env
#                  contract (AGENT, AGENT_CMD, MODEL, etc.) inherited
#                  unmodified from this script's own environment — the
#                  caller job sets those to the fixed review-agent
#                  identity (AGENT=claude), which is intentionally
#                  independent of FIX_AGENT.
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
  FIX_AGENT="${FIX_AGENT:-claude}"
  FIX_MODEL="${FIX_MODEL:-}"
  concerns_file="$CONCERNS_FILE"

  for (( i = 1; i <= MAX_ITERATIONS; i++ )); do
    if ! ITERATION="$i" REPO="$REPO" HEAD_REF="$HEAD_REF" AGENT="$FIX_AGENT" MODEL="$FIX_MODEL" \
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
git commit -m "feat(self-fix): self-fix-loop.sh orchestrator (#193)"
```

---

## Task 7: Workflow — `implement` job exposes `agent`/`model`; `auto_review`/`pre_preview` expose review identity

**Files:**

- Modify: `.github/workflows/agent-implement.yml`

**Interfaces:**

- Produces: `needs.implement.outputs.agent` / `.model`, `needs.auto_review.outputs.{verdict,pr-number,head-sha,head-ref,concerns-json}`, `needs.pre_preview.outputs.{verdict,pr-number,head-sha,head-ref,concerns-json}` — all consumed by the new `fix_retry` job (Task 9).

- [ ] **Step 1: Add `agent`/`model` outputs to the `implement` job**

`steps.classify_agent`/`steps.triage` are skipped entirely under `stub-claude: true` (see their `if:` conditions), so fall back to the raw `inputs.agent`/`inputs.default-model` in that mode — this lets Layer-2 act tests (Task 10) drive the resolved agent via the existing `agent` input without a new stub.

In `.github/workflows/agent-implement.yml`, change:

```yaml
    outputs:
      outcome:             ${{ steps.outputs.outputs.outcome }}
      cost-usd:            ${{ steps.outputs.outputs.cost-usd }}
      num-turns:           ${{ steps.outputs.outputs.num-turns }}
      failure-class:       ${{ steps.classify_failure.outputs.class }}
      retry-decision:      ${{ steps.retry.outputs.decision }}
      auto-review-enabled: ${{ steps.auto_review_gate.outputs.enabled || steps.auto_review_gate_stub.outputs.enabled }}
      pre-preview-enabled: ${{ steps.preview_gate.outputs.enabled || steps.preview_gate_stub.outputs.enabled }}
```

to:

```yaml
    outputs:
      outcome:             ${{ steps.outputs.outputs.outcome }}
      cost-usd:            ${{ steps.outputs.outputs.cost-usd }}
      num-turns:           ${{ steps.outputs.outputs.num-turns }}
      failure-class:       ${{ steps.classify_failure.outputs.class }}
      retry-decision:      ${{ steps.retry.outputs.decision }}
      auto-review-enabled: ${{ steps.auto_review_gate.outputs.enabled || steps.auto_review_gate_stub.outputs.enabled }}
      pre-preview-enabled: ${{ steps.preview_gate.outputs.enabled || steps.preview_gate_stub.outputs.enabled }}
      agent:               ${{ steps.classify_agent.outputs.agent || inputs.agent }}
      model:                ${{ steps.triage.outputs.model || inputs.default-model }}
```

- [ ] **Step 2: Add `verdict`/`pr-number`/`head-sha`/`head-ref`/`concerns-json` outputs and the concerns-capture step to `auto_review`**

Change the `auto_review` job's `outputs:` block from:

```yaml
    outputs:
      merge-attempted: ${{ steps.verify_mock.outputs.merge-attempted }}
```

to:

```yaml
    outputs:
      merge-attempted: ${{ steps.verify_mock.outputs.merge-attempted }}
      verdict:         ${{ steps.verdict.outputs.value }}
      pr-number:       ${{ steps.find_pr.outputs.pr-number }}
      head-sha:        ${{ steps.find_pr.outputs.head-sha }}
      head-ref:        ${{ steps.find_pr.outputs.head-ref }}
      concerns-json:   ${{ steps.concerns.outputs.value }}
```

Immediately after the `Resolve review verdict` step (id: `verdict`) in `auto_review`, add a new step:

```yaml
      - name: Capture review concerns JSON
        # fix_retry (#193) needs the validated review JSON to build the
        # fix prompt, but it runs on a separate runner with no access to
        # this job's local files — read it into a job output string here.
        # Concerns payloads are small (a handful of findings, not a diff),
        # well within GITHUB_OUTPUT's per-line limits. Falls back to '{}'
        # when no summary file exists (e.g. stub-review-verdict mode,
        # where review-pr.sh never ran).
        if: |
          steps.self_mod_guard.outputs.blocked != 'true'
          && steps.find_pr.outputs.found == 'true'
        id: concerns
        env:
          SUMMARY_FILE: ${{ steps.review.outputs.summary-file }}
        run: |
          content='{}'
          if [[ -n "$SUMMARY_FILE" && -r "$SUMMARY_FILE" ]]; then
            content="$(cat "$SUMMARY_FILE")"
          fi
          {
            echo "value<<EOF_CONCERNS_JSON"
            printf '%s\n' "$content"
            echo "EOF_CONCERNS_JSON"
          } >> "$GITHUB_OUTPUT"
```

- [ ] **Step 3: Same for `pre_preview`**

Change the `pre_preview` job's `outputs:` block from:

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
      verdict:         ${{ steps.verdict.outputs.value }}
      pr-number:       ${{ steps.find_pr.outputs.pr-number }}
      head-sha:        ${{ steps.find_pr.outputs.head-sha }}
      head-ref:        ${{ steps.find_pr.outputs.head-ref }}
      concerns-json:   ${{ steps.concerns.outputs.value }}
```

Immediately after `pre_preview`'s `Resolve review verdict` step, add:

```yaml
      - name: Capture review concerns JSON
        if: steps.find_pr.outputs.found == 'true'
        id: concerns
        env:
          SUMMARY_FILE: ${{ steps.review.outputs.summary-file }}
        run: |
          content='{}'
          if [[ -n "$SUMMARY_FILE" && -r "$SUMMARY_FILE" ]]; then
            content="$(cat "$SUMMARY_FILE")"
          fi
          {
            echo "value<<EOF_CONCERNS_JSON"
            printf '%s\n' "$content"
            echo "EOF_CONCERNS_JSON"
          } >> "$GITHUB_OUTPUT"
```

- [ ] **Step 4: Lint the workflow**

Run: `actionlint .github/workflows/agent-implement.yml`
Expected: no output, exit 0.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/agent-implement.yml
git commit -m "feat(workflow): expose implementer agent + review identity for self-fix (#193)"
```

---

## Task 8: Workflow — suppress premature blocking when self-fix will run

Without this guard, `auto_review`/`pre_preview`'s own "Mark issue blocked" step fires immediately on `request_changes` — before the new `fix_retry` job (Task 9) even starts — stamping `ai:review-blocked` and commenting on a PR that self-fix hasn't attempted yet.

**Files:**

- Modify: `.github/workflows/agent-implement.yml`

- [ ] **Step 1: Add the three new workflow_call inputs**

In the `on.workflow_call.inputs:` block, immediately after the `pipeline-author-allowlist:` input block (the last one), add:

```yaml
      self-fix:
        description: |
          Opt-in for the auto-fix retry loop (#193, generalizing #81's
          deferred self-fix follow-up to ADR-004). When true AND exactly
          one of auto_review/pre_preview ran with verdict
          `request_changes`, the `fix_retry` job dispatches the issue's
          original implementer agent (per needs.implement.outputs.agent)
          to attempt up to `self-fix-max-iterations` fix → re-review
          cycles before falling back to the block path. Ignored when the
          verdict is `approve` (nothing to fix) or `block` (the agent
          already refused — self-fix never runs after a block).
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

- [ ] **Step 2: Add the `self-fix-iterations-used` workflow_call output**

In the `on.workflow_call.outputs:` block, immediately after the `pre-preview-ready-attempted:` output block, add:

```yaml
      self-fix-iterations-used:
        description: |
          Iterations actually used by the auto-fix retry loop (0 if it
          never ran). Populated only when `stub-review-verdict` /
          `stub-self-fix-verdict-sequence` is set.
        value: ${{ jobs.fix_retry.outputs.iterations-used }}
```

Also update `pre-preview-ready-attempted` and `auto-review-merge-attempted`'s `value:` to account for `fix_retry` performing the terminal promote/merge instead of `auto_review`/`pre_preview`'s own steps when self-fix ran. Change:

```yaml
      auto-review-merge-attempted:
        description: |
          "true" or "false" — whether `gh pr merge --auto --squash` was
          invoked by the auto_review job. Populated only when
          `stub-review-verdict` is set (the test workflow's assertion
          surface for "no real merge call is made under act"). Empty on
          real runs.
        value: ${{ jobs.auto_review.outputs.merge-attempted }}
      pre-preview-merge-attempted:
        description: |
          "true" or "false" — whether `gh pr merge` was invoked by the
          pre_preview job. Always "false" on the pre-preview path (it never
          merges); populated only when `stub-review-verdict` is set, as the
          test workflow's "no merge in pre-preview" assertion surface.
        value: ${{ jobs.pre_preview.outputs.merge-attempted }}
      pre-preview-ready-attempted:
        description: |
          "true" or "false" — whether `gh pr ready` (promote draft→ready)
          was invoked by the pre_preview job. True on the approve path.
          Populated only when `stub-review-verdict` is set.
        value: ${{ jobs.pre_preview.outputs.ready-attempted }}
```

to:

```yaml
      auto-review-merge-attempted:
        description: |
          "true" or "false" — whether `gh pr merge --auto --squash` was
          invoked by either the auto_review job's own promote step or
          (when self-fix ran) fix_retry's. Populated only when
          `stub-review-verdict` is set (the test workflow's assertion
          surface for "no real merge call is made under act"). Empty on
          real runs.
        value: ${{ jobs.auto_review.outputs.merge-attempted || jobs.fix_retry.outputs.merge-attempted }}
      pre-preview-merge-attempted:
        description: |
          "true" or "false" — whether `gh pr merge` was invoked by the
          pre_preview job or fix_retry. Always "false" on the pre-preview
          path (it never merges); populated only when `stub-review-verdict`
          is set, as the test workflow's "no merge in pre-preview" assertion
          surface.
        value: ${{ jobs.pre_preview.outputs.merge-attempted || jobs.fix_retry.outputs.merge-attempted }}
      pre-preview-ready-attempted:
        description: |
          "true" or "false" — whether `gh pr ready` (promote draft→ready)
          was invoked by either the pre_preview job's own promote step or
          (when self-fix ran) fix_retry's. True on the approve path.
          Populated only when `stub-review-verdict` is set.
        value: ${{ jobs.pre_preview.outputs.ready-attempted || jobs.fix_retry.outputs.ready-attempted }}
```

- [ ] **Step 3: Guard `auto_review`'s "Mark issue blocked" step**

Change:

```yaml
      - name: Mark issue blocked when review or envelope refuses
        # Fires on every refusal path: self-mod guard, missing PR,
        # non-approve verdict, or envelope failure. post-auto-review-
        # block.sh picks the right reason and either comments on the
        # PR (when known) or falls back to the issue.
        if: |
          steps.self_mod_guard.outputs.blocked == 'true'
          || steps.find_pr.outputs.found != 'true'
          || steps.verdict.outputs.value != 'approve'
          || (steps.verdict.outputs.value == 'approve' && steps.envelope.outputs.envelope != 'pass')
```

to:

```yaml
      - name: Mark issue blocked when review or envelope refuses
        # Fires on every refusal path: self-mod guard, missing PR,
        # non-approve verdict, or envelope failure. post-auto-review-
        # block.sh picks the right reason and either comments on the
        # PR (when known) or falls back to the issue.
        #
        # The added `&& !(...)` clause defers to fix_retry (#193) when
        # self-fix is enabled and the FIRST verdict was request_changes —
        # without it, this step would stamp ai:review-blocked immediately,
        # before fix_retry (a separate downstream job) gets a chance to
        # run. It is a no-op for every other branch of this condition:
        # the self-mod-guard/missing-PR/envelope-fail paths all have
        # steps.verdict.outputs.value equal to '' or 'approve', never
        # 'request_changes'.
        if: |
          (
            steps.self_mod_guard.outputs.blocked == 'true'
            || steps.find_pr.outputs.found != 'true'
            || steps.verdict.outputs.value != 'approve'
            || (steps.verdict.outputs.value == 'approve' && steps.envelope.outputs.envelope != 'pass')
          )
          && !(inputs.self-fix && steps.verdict.outputs.value == 'request_changes')
```

- [ ] **Step 4: Guard `pre_preview`'s "Mark issue blocked" step**

Change:

```yaml
      - name: Mark issue blocked when review refuses or PR missing
        if: |
          steps.find_pr.outputs.found != 'true'
          || steps.verdict.outputs.value != 'approve'
```

to:

```yaml
      - name: Mark issue blocked when review refuses or PR missing
        # See the equivalent guard on auto_review's block step (#193) —
        # same reasoning: defer to fix_retry when self-fix will run.
        if: |
          (
            steps.find_pr.outputs.found != 'true'
            || steps.verdict.outputs.value != 'approve'
          )
          && !(inputs.self-fix && steps.verdict.outputs.value == 'request_changes')
```

- [ ] **Step 5: Lint the workflow**

Run: `actionlint .github/workflows/agent-implement.yml`
Expected: no output, exit 0 (the `fix_retry` job referenced in Step 2's outputs doesn't exist yet — added in Task 9 — so this lint is expected to pass syntactically but the workflow isn't runnable end-to-end until Task 9 lands; commit anyway per the task-per-commit convention, Task 9 completes it).

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/agent-implement.yml
git commit -m "feat(workflow): defer blocking to fix_retry when self-fix is enabled (#193)"
```

---

## Task 9: Workflow — the `fix_retry` job

**Files:**

- Modify: `.github/workflows/agent-implement.yml`

**Interfaces:**

- Consumes: `needs.implement.outputs.{agent,model}` (Task 7), `needs.auto_review.outputs.*` / `needs.pre_preview.outputs.*` (Task 7), `scripts/self-fix-loop.sh` (Task 6), `scripts/check-merge-envelope.sh` / `scripts/post-auto-review-block.sh` (existing, Task 2), `scripts/verify-gh-mock-merge.sh` (existing).
- Produces: job outputs `iterations-used`, `ready-attempted`, `merge-attempted` — consumed by Task 8's workflow_call outputs.

- [ ] **Step 1: Add the job**

At the end of the `jobs:` block in `.github/workflows/agent-implement.yml` (after the `pre_preview` job), add:

```yaml
  fix_retry:
    # Auto-fix retry loop (#193): on a `request_changes` verdict from
    # whichever of auto_review/pre_preview ran, dispatch the issue's
    # original implementer agent to fix its own findings through bounded
    # fix→re-review cycles (scripts/self-fix-loop.sh), then either
    # promote (re-checking ADR-002's merge envelope when the source was
    # auto_review) or stamp ai:review-blocked with "self-fix exhausted"
    # wording. `approve` and `block` first verdicts never reach this job.
    name: Self-fix retry for issue #${{ inputs.issue-number }}
    needs: [implement, auto_review, pre_preview]
    if: |
      inputs.self-fix
      && (
        (needs.auto_review.result == 'success' && needs.auto_review.outputs.verdict == 'request_changes')
        || (needs.pre_preview.result == 'success' && needs.pre_preview.outputs.verdict == 'request_changes')
      )
    runs-on: ${{ fromJSON(inputs.runner-labels) }}
    timeout-minutes: 15
    permissions:
      contents: write
      pull-requests: write
      issues: write
    outputs:
      iterations-used: ${{ steps.loop.outputs.iterations-used }}
      ready-attempted: ${{ steps.verify_mock.outputs.ready-attempted }}
      merge-attempted: ${{ steps.verify_mock.outputs.merge-attempted }}
    steps:
      - name: Resolve self-fix source
        # Exactly one of auto_review/pre_preview ran (mutually exclusive
        # via the implement job's gate) and matched this job's `if:` —
        # this step just names which one, so later steps don't repeat
        # the branching.
        id: source
        env:
          AUTO_REVIEW_RESULT:  ${{ needs.auto_review.result }}
          AUTO_REVIEW_VERDICT: ${{ needs.auto_review.outputs.verdict }}
        run: |
          if [[ "$AUTO_REVIEW_RESULT" == 'success' && "$AUTO_REVIEW_VERDICT" == 'request_changes' ]]; then
            echo "mode=auto-review" >> "$GITHUB_OUTPUT"
          else
            echo "mode=pre-preview" >> "$GITHUB_OUTPUT"
          fi

      - name: Checkout PR head branch
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
        with:
          ref: ${{ needs.auto_review.outputs.head-ref || needs.pre_preview.outputs.head-ref }}
          fetch-depth: 0

      - name: Checkout agent-workflow scripts
        if: ${{ !inputs.local-scripts }}
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
        with:
          repository: ${{ inputs.pipeline-repo }}
          ref: ${{ inputs.pipeline-ref }}
          path: .claude-pipeline
          sparse-checkout: |
            scripts
            tests/mocks
            tests/fixtures

      - name: Mirror local scripts to .claude-pipeline (self-test mode)
        if: ${{ inputs.local-scripts }}
        run: |
          mkdir -p .claude-pipeline/scripts \
                   .claude-pipeline/tests/mocks \
                   .claude-pipeline/tests/fixtures
          cp -r scripts/. .claude-pipeline/scripts/
          if [[ -d tests/mocks ]]; then
            cp -r tests/mocks/. .claude-pipeline/tests/mocks/
          fi
          if [[ -d tests/fixtures ]]; then
            cp -r tests/fixtures/. .claude-pipeline/tests/fixtures/
          fi

      - name: Wire gh mock (test mode)
        if: inputs.stub-self-fix-verdict-sequence != ''
        env:
          WORKSPACE: ${{ github.workspace }}
        run: |
          log="${RUNNER_TEMP:-/tmp}/gh-mock-fix-retry.log"
          : > "$log"
          {
            printf 'PATH=%s/.claude-pipeline/tests/mocks:%s\n' "$WORKSPACE" "$PATH"
            printf 'GH_MOCK_LOG=%s\n' "$log"
          } >> "$GITHUB_ENV"

      - name: Write concerns JSON to file
        id: concerns
        env:
          CONCERNS_JSON: ${{ needs.auto_review.outputs.concerns-json || needs.pre_preview.outputs.concerns-json }}
        run: |
          f="${RUNNER_TEMP:-/tmp}/concerns.json"
          printf '%s' "$CONCERNS_JSON" > "$f"
          echo "file=$f" >> "$GITHUB_OUTPUT"

      - name: Self-fix loop
        id: loop
        env:
          GH_TOKEN: ${{ github.token }}
          REPO: ${{ github.repository }}
          PR_NUMBER: ${{ needs.auto_review.outputs.pr-number || needs.pre_preview.outputs.pr-number }}
          HEAD_SHA: ${{ needs.auto_review.outputs.head-sha || needs.pre_preview.outputs.head-sha }}
          HEAD_REF: ${{ needs.auto_review.outputs.head-ref || needs.pre_preview.outputs.head-ref }}
          INITIAL_VERDICT: request_changes
          CONCERNS_FILE: ${{ steps.concerns.outputs.file }}
          MAX_ITERATIONS: ${{ inputs.self-fix-max-iterations }}
          FIX_AGENT: ${{ needs.implement.outputs.agent }}
          FIX_MODEL: ${{ needs.implement.outputs.model }}
          AGENT: claude
          AGENT_CMD: ${{ github.workspace }}/.claude-pipeline/scripts/lib/agent-cmd-claude.sh
          MODEL: ${{ inputs.review-model }}
          CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          OPENROUTER_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}
          WORK_DIR: ${{ github.workspace }}
          SKIP_CLONE: '1'
          STUB_VERDICT_SEQUENCE: ${{ inputs.stub-self-fix-verdict-sequence }}
        run: bash .claude-pipeline/scripts/self-fix-loop.sh

      - name: Check merge envelope (auto-review source only)
        # ADR-002's envelope must be re-evaluated against the final HEAD —
        # self-fix must not bypass it. pre-preview source never merges, so
        # it never needs this (ADR-004: no envelope, no auto-merge).
        if: |
          steps.loop.outputs.verdict == 'approve'
          && steps.source.outputs.mode == 'auto-review'
        id: envelope
        env:
          GH_TOKEN: ${{ github.token }}
          REPO: ${{ github.repository }}
          PR_NUMBER: ${{ needs.auto_review.outputs.pr-number }}
          AUTHOR_ALLOWLIST: ${{ inputs.pipeline-author-allowlist }}
          PR_AUTHOR: ${{ inputs.stub-self-fix-verdict-sequence != '' && 'github-actions[bot]' || '' }}
          PR_FILES: ${{ inputs.stub-pr-files }}
          REQUIRED_CHECKS_STATUS: ${{ inputs.stub-self-fix-verdict-sequence != '' && 'pass' || '' }}
          REPO_ALLOWS_SQUASH: ${{ inputs.stub-self-fix-verdict-sequence != '' && 'true' || '' }}
          REPO_ALLOWS_AUTO_MERGE: ${{ inputs.stub-self-fix-verdict-sequence != '' && 'true' || '' }}
        run: bash .claude-pipeline/scripts/check-merge-envelope.sh

      - name: Promote / merge on final approve
        if: steps.loop.outputs.verdict == 'approve'
        env:
          GH_TOKEN: ${{ github.token }}
          REPO: ${{ github.repository }}
          PR_NUMBER: ${{ needs.auto_review.outputs.pr-number || needs.pre_preview.outputs.pr-number }}
          SOURCE: ${{ steps.source.outputs.mode }}
          ENVELOPE: ${{ steps.envelope.outputs.envelope }}
        run: |
          gh pr ready "$PR_NUMBER" --repo "$REPO" || true
          if [[ "$SOURCE" == 'auto-review' && "$ENVELOPE" == 'pass' ]]; then
            gh pr merge "$PR_NUMBER" --repo "$REPO" --auto --squash
          fi

      - name: Mark issue blocked (self-fix exhausted, blocked, or envelope failed)
        if: |
          steps.loop.outputs.verdict != 'approve'
          || (steps.source.outputs.mode == 'auto-review' && steps.envelope.outputs.envelope != 'pass')
        env:
          GH_TOKEN: ${{ github.token }}
          REPO: ${{ github.repository }}
          ISSUE_NUMBER: ${{ inputs.issue-number }}
          PR_NUMBER: ${{ needs.auto_review.outputs.pr-number || needs.pre_preview.outputs.pr-number }}
          FOUND: 'true'
          VERDICT: ${{ steps.loop.outputs.verdict }}
          ENVELOPE: ${{ steps.envelope.outputs.envelope }}
          ENVELOPE_REASON: ${{ steps.envelope.outputs.reason }}
          FAILED_GATES: ${{ steps.envelope.outputs.failed-gates }}
          SELF_FIX_ITERATIONS: ${{ steps.loop.outputs.iterations-used }}
          SELF_FIX_MAX: ${{ inputs.self-fix-max-iterations }}
          MODE: ${{ steps.source.outputs.mode }}
        run: bash .claude-pipeline/scripts/post-auto-review-block.sh

      - name: Verify gh mock log (test mode)
        if: inputs.stub-self-fix-verdict-sequence != '' && always()
        id: verify_mock
        run: bash .claude-pipeline/scripts/verify-gh-mock-merge.sh
```

- [ ] **Step 2: Lint the workflow**

Run: `actionlint .github/workflows/agent-implement.yml`
Expected: no output, exit 0.

- [ ] **Step 3: Confirm Layer-1 suite still passes**

Run: `bash tests/run-script-tests.sh`
Expected: PASS (this task only touches YAML — confirms no regression before the Layer-2 act pass in Task 10).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/agent-implement.yml
git commit -m "feat(workflow): fix_retry job — auto-fix retry loop orchestration (#193)"
```

---

## Task 10: Layer-2 act scenarios

Exercises the `self-fix: true` path end-to-end via `stub-self-fix-verdict-sequence`, for both the `auto_review` and `pre_preview` sources, and for both `agent: claude` and `agent: opencode` triage outcomes (proving `fix_retry`'s `FIX_AGENT` routing is wired correctly at the workflow level — the actual per-agent wrapper behavior is Layer-1-tested in Task 5).

**Files:**

- Modify: `.github/workflows/agent-implement.test.yml`

- [ ] **Step 1: Add the call jobs**

At the end of `.github/workflows/agent-implement.test.yml`, immediately after the existing `call-pre-preview-precedence:` job block, add:

```yaml
  # ─── Auto-fix retry loop (#193) ───────────────────────────────────────────
  # Exercised via stub-self-fix-verdict-sequence, which drives
  # self-fix-loop.sh's stub branch directly (bypassing the fix/re-review
  # scripts themselves — those are covered by Layer-1 tests). This proves
  # the workflow's wiring: gating, fix_retry's promote/block steps, and
  # the deferred-blocking guard on auto_review/pre_preview.

  call-pre-preview-self-fix-approve:
    name: Reusable workflow — pre-preview self-fix fixes then approves (agent claude)
    uses: ./.github/workflows/agent-implement.yml
    with:
      issue-number: 9020
      timeout-minutes: 10
      local-scripts: true
      stub-claude: true
      stub-fixture: success
      agent: claude
      pre-preview: true
      dry-run: true
      stub-pre-preview-enabled: true
      stub-review-verdict: request_changes
      self-fix: true
      self-fix-max-iterations: 3
      stub-self-fix-verdict-sequence: "request_changes,approve"
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: not-used-by-stub

  call-auto-review-self-fix-exhausted:
    name: Reusable workflow — auto-review self-fix cap exhausted (agent opencode)
    uses: ./.github/workflows/agent-implement.yml
    with:
      issue-number: 9021
      timeout-minutes: 10
      local-scripts: true
      stub-claude: true
      stub-fixture: success
      agent: opencode
      auto-review: true
      dry-run: true
      stub-auto-review-enabled: true
      stub-review-verdict: request_changes
      stub-pr-files: docs/README.md
      self-fix: true
      self-fix-max-iterations: 2
      stub-self-fix-verdict-sequence: "request_changes,request_changes"
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: not-used-by-stub
```

- [ ] **Step 2: Add the assertion jobs**

After the existing `verify-pre-preview-precedence:` job, add:

```yaml
  verify-pre-preview-self-fix-approve:
    name: Assert pre-preview self-fix fixes then approves → promoted, no merge, no premature block
    needs: call-pre-preview-self-fix-approve
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: read
    env:
      READY:      ${{ needs.call-pre-preview-self-fix-approve.outputs.pre-preview-ready-attempted }}
      ATTEMPTED:  ${{ needs.call-pre-preview-self-fix-approve.outputs.pre-preview-merge-attempted }}
      ITERATIONS: ${{ needs.call-pre-preview-self-fix-approve.outputs.self-fix-iterations-used }}
    steps:
      - name: Assert promoted after 2 self-fix iterations, still no merge
        run: |
          fail=0
          [[ "$READY" == "true" ]]      || { echo "::error::ready-attempted=$READY (want true — self-fix approve must promote)"; fail=1; }
          [[ "$ATTEMPTED" == "false" ]] || { echo "::error::merge-attempted=$ATTEMPTED (want false — pre-preview never merges)"; fail=1; }
          [[ "$ITERATIONS" == "2" ]]    || { echo "::error::self-fix-iterations-used=$ITERATIONS (want 2)"; fail=1; }
          (( fail == 0 )) || exit 1
          echo "pre-preview self-fix approve OK: ready=$READY merge=$ATTEMPTED iterations=$ITERATIONS"

  verify-auto-review-self-fix-exhausted:
    name: Assert auto-review self-fix cap exhausted → no promote, no merge
    needs: call-auto-review-self-fix-exhausted
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: read
    env:
      ATTEMPTED:  ${{ needs.call-auto-review-self-fix-exhausted.outputs.auto-review-merge-attempted }}
      ITERATIONS: ${{ needs.call-auto-review-self-fix-exhausted.outputs.self-fix-iterations-used }}
    steps:
      - name: Assert no merge after cap exhausted (agent=opencode routed correctly)
        run: |
          fail=0
          [[ "$ATTEMPTED" == "false" ]] || { echo "::error::merge-attempted=$ATTEMPTED (want false — cap-exhausted must NOT merge)"; fail=1; }
          [[ "$ITERATIONS" == "2" ]]    || { echo "::error::self-fix-iterations-used=$ITERATIONS (want 2 — cap reached)"; fail=1; }
          (( fail == 0 )) || exit 1
          echo "auto-review self-fix cap-exhausted OK: merge=$ATTEMPTED iterations=$ITERATIONS"
```

- [ ] **Step 3: Lint the test workflow**

Run: `actionlint .github/workflows/agent-implement.test.yml`
Expected: no output, exit 0.

- [ ] **Step 4: (Optional) run the act scenarios locally if `act` + Docker are available**

Run: `act pull_request -W .github/workflows/agent-implement.test.yml -j verify-pre-preview-self-fix-approve`
Expected: job passes (`pre-preview self-fix approve OK: ready=true merge=false iterations=2`).
If `act`/Docker is unavailable, skip — these run in CI on the pushed PR (Task 11).

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/agent-implement.test.yml
git commit -m "test(act): auto-fix retry loop approve/cap-exhausted scenarios (#193)"
```

---

## Task 11: Docs — ADR-009, CONSUMER-SETUP.md, close #81

**Files:**

- Modify: `docs/DECISIONS.md`
- Modify: `docs/CONSUMER-SETUP.md`

- [ ] **Step 1: Add ADR-009 to DECISIONS.md**

In `docs/DECISIONS.md`, find `## ADR-008 — Advisor Tool not yet wired into ai-implement (2026-07-24)` and locate its end (the next `## ADR-` heading, or end of file if none). Immediately before that boundary (or at end of file), add:

```markdown

## ADR-009 — Auto-fix retry loop (2026-08-01)

**Status:** Accepted
**Tracking:** [#193](https://github.com/freaxnx01/agent-workflow/issues/193)
**Supersedes:** the self-fix portion of ADR-004's deferred item (spec/plan
drafted in #81, never implemented)

### Context

`auto_review` (ADR-002) and `pre_preview` (ADR-004) both leave the PR draft
and stamp `ai:review-blocked` on any non-`approve` verdict — nothing further
happens automatically. A manual relay to `@copilot` was tried once
(`game-tschau-sepp#9` / PR #12) and did an incomplete job: `@copilot` has no
access to the issue's original context or implementation plan, and isn't the
agent that wrote the code.

### Decision

Add a `fix_retry` job that, on a `request_changes` verdict AND
`self-fix: true`, dispatches **the original implementer's agent** (Claude or
OpenCode, resolved from `needs.implement.outputs.agent` — never a hardcoded
choice) to fix its own findings:

+ Bounded fix→re-review cycles (`self-fix-loop.sh` / `self-fix-pr.sh`), up to
  `self-fix-max-iterations` (default 2). Each iteration commits
  `address self-review (iteration N)` and pushes; re-review reuses
  `review-pr.sh` unmodified against the new HEAD.
+ `block` verdicts and missing PRs never reach `fix_retry` — unchanged from
  today, fail-safe toward leaving the PR alone when the agent's own review
  actively refused.
+ On final `approve`: promote (`gh pr ready`); if the source was
  `auto_review`, additionally re-run `check-merge-envelope.sh` against the
  final HEAD before `gh pr merge --auto --squash` — self-fix must not bypass
  ADR-002's safety envelope. `pre_preview`'s source never merges (ADR-004).
+ On cap-exhausted/still-blocked: `post-auto-review-block.sh` gets distinct
  wording ("self-fix exhausted after N/M iterations") via
  `SELF_FIX_ITERATIONS`/`SELF_FIX_MAX`, byte-identical to today's wording
  when self-fix didn't run.
+ The review step's own agent/model choice (`AGENT: claude`,
  `review-model`) is unchanged — self-fix only affects who fixes, not who
  reviews.

### Consequences

+ `auto_review`/`pre_preview`'s own "Mark issue blocked" steps gain a guard
  (`&& !(inputs.self-fix && verdict == 'request_changes')`) so they defer to
  `fix_retry` instead of blocking prematurely — a no-op for every other
  branch of their existing condition.
+ The reusable workflow gains `self-fix` / `self-fix-max-iterations` /
  `stub-self-fix-verdict-sequence` inputs, `self-fix-iterations-used`
  output, and new `agent`/`model` outputs on the `implement` job plus
  `verdict`/`pr-number`/`head-sha`/`head-ref`/`concerns-json` outputs on
  `auto_review`/`pre_preview`.
+ #81 (the narrower Claude-only, pre-preview-only version of this design)
  is superseded and closed — its spec/plan were never implemented.
```

- [ ] **Step 2: Update CONSUMER-SETUP.md**

In `docs/CONSUMER-SETUP.md`, change:

```text
2. **Auto-review + auto-merge** — labeled-issue → draft PR → agent review → squash-merge, inside ADR-002's safety envelope.
3. **Pre-preview** — labeled-issue → draft PR → agent reviews its own PR → on approve, promote draft→ready; a human merges. No envelope, no auto-merge. Opt in with `pre-preview: true` + the `ai-pre-preview` label. See ADR-004.
```

to:

```text
2. **Auto-review + auto-merge** — labeled-issue → draft PR → agent review → squash-merge, inside ADR-002's safety envelope.
3. **Pre-preview** — labeled-issue → draft PR → agent reviews its own PR → on approve, promote draft→ready; a human merges. No envelope, no auto-merge. Opt in with `pre-preview: true` + the `ai-pre-preview` label. See ADR-004.

On a `request_changes` verdict from either flow above, optionally opt into a bounded auto-fix retry loop with `self-fix: true` (+ `self-fix-max-iterations`, default 2) — the *original implementer's* agent (Claude or OpenCode, whichever wrote the PR) attempts to fix its own findings and re-review before falling back to `ai:review-blocked`. See ADR-009.
```

- [ ] **Step 3: Confirm nothing regressed**

Run: `bash tests/run-script-tests.sh`
Expected: PASS (docs don't affect scripts; this just confirms nothing regressed).

- [ ] **Step 4: Commit**

```bash
git add docs/DECISIONS.md docs/CONSUMER-SETUP.md
git commit -m "docs: ADR-009 auto-fix retry loop + CONSUMER-SETUP (#193)"
```

---

## Task 12: Push, open PR, confirm CI green, close #81

**Files:** none (integration)

- [ ] **Step 1: Run the full local gate once more**

```bash
bash tests/run-script-tests.sh
shellcheck -x -e SC1091 scripts/find-pipeline-pr.sh scripts/post-auto-review-block.sh \
  scripts/self-fix-pr.sh scripts/self-fix-loop.sh \
  scripts/lib/agent-cmd-claude-fix.sh scripts/lib/agent-cmd-opencode-fix.sh
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
  --title "feat(review): auto-fix retry loop (#193)" \
  --body "Implements the auto-fix retry loop per docs/superpowers/specs/2026-08-01-auto-fix-retry-loop-design.md and ADR-009. Generalizes #81's Claude-only pre-preview self-fix design (never implemented) to route to whichever agent implemented the issue, across both auto_review and pre_preview. Closes #193."
```

- [ ] **Step 4: Confirm CI green**

Run: `gh pr checks <PR#> -R freaxnx01/agent-workflow`
Expected: `actionlint`, `shellcheck`, the new `verify-pre-preview-self-fix-approve` / `verify-auto-review-self-fix-exhausted` jobs, and all pre-existing `verify-pre-preview-*` / `verify-auto-review-*` jobs pass (no regression).

- [ ] **Step 5: Close #81 as superseded**

```bash
gh issue comment 81 -R freaxnx01/agent-workflow --body "Superseded by #193 (ADR-009), which generalizes this issue's self-fix design (spec/plan merged in #218, never implemented) to route to whichever agent implemented the issue, across both auto_review and pre_preview. Closing as superseded."
gh issue close 81 -R freaxnx01/agent-workflow
```

- [ ] **Step 6: Update issue #193**

Check off the acceptance-criteria items now satisfied. Do not auto-close — a human merges the PR, which closes #193 via "Closes #193".

---

## Self-Review notes (author)

- **Spec coverage:** §1 inputs/gating (`self-fix`/`self-fix-max-iterations`, Task 8; `fix_retry`'s own `if:` gate, Task 9) · §2 cross-job state (`implement` agent/model outputs, Task 7 Step 1; `auto_review`/`pre_preview` verdict/pr-number/head-ref/concerns-json outputs, Task 7 Steps 2-3; `find-pipeline-pr.sh` head-ref, Task 1) · §3 fix-agent resolution (`self-fix-pr.sh`'s AGENT-based wrapper resolution, Task 5; opencode wrapper, Task 4) · §4 loop mechanics (`self-fix-loop.sh`, Task 6) · §5 `fix_retry` orchestration incl. envelope re-check on the auto-review source only (Task 9) · §6 terminal wording (`post-auto-review-block.sh`, Task 2). All three of the spec's "open items for the implementation plan" are resolved: the opencode fix wrapper's exact invocation shape (Task 4, mirrors the implement job's Run OpenCode step), the `if:`/`needs.*.result` syntax for the shared downstream job (Task 9's `fix_retry.if:`), and the concerns-json GITHUB_OUTPUT encoding (Task 7's heredoc-delimiter capture step, chosen over base64 since the multiline delimiter syntax already handles embedded newlines in JSON prose).
- **Beyond the spec's literal text, but required for correctness:** the spec's §2 says "auto_review/pre_preview each gain three new outputs" but then lists four (verdict, pr-number, head-ref, concerns-json) — Task 7 implements all four, plus a fifth (`head-sha`) the spec's prose omits but `self-fix-loop.sh`'s own required `HEAD_SHA` env demands; and Task 8's guard on `auto_review`/`pre_preview`'s existing "Mark issue blocked" steps isn't spelled out in the spec's §5 at all, but without it those steps fire immediately on `request_changes` (before the downstream `fix_retry` job runs), stamping `ai:review-blocked` before self-fix gets a chance — this would be a functional regression the spec didn't call out.
- **Name collision avoided:** `self-fix-loop.sh` uses distinct `FIX_AGENT`/`FIX_MODEL` env vars (forwarded to `self-fix-pr.sh` as `AGENT`/`MODEL` only on the `FIX_CMD` call line) instead of reusing the job step's `AGENT`/`MODEL`, which are fixed to the review-agent identity (`claude`/`review-model`) for the `REVIEW_SCRIPT` call — without this, a step-level `AGENT: opencode` set for fix routing would leak into `review-pr.sh`'s re-review call and mislabel which agent actually reviewed.
- **No placeholders:** every script/YAML/doc edit shows full content.
- **Name consistency:** `self-fix-loop.sh`, `self-fix-pr.sh`, `agent-cmd-claude-fix.sh`, `agent-cmd-opencode-fix.sh`; inputs `self-fix` / `self-fix-max-iterations` / `stub-self-fix-verdict-sequence`; job `fix_retry`; job outputs `iterations-used`/`ready-attempted`/`merge-attempted` and workflow output `self-fix-iterations-used`; env `SELF_FIX_ITERATIONS` / `SELF_FIX_MAX` / `FIX_AGENT` / `FIX_MODEL` / `STUB_VERDICT_SEQUENCE` / `NEW_HEAD_SHA` / `FIX_LIB_DIR` — used identically across all tasks that reference them.
</content>
