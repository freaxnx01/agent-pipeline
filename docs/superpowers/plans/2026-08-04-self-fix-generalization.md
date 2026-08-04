# Self-Fix Generalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generalize the existing `pre_preview`-only, Claude-only self-fix pass (#81/#221) to also run inside `auto_review`, and to route the fix call to whichever agent (Claude or OpenCode) actually implemented the issue, instead of a hardcoded Claude fallback.

**Architecture:** Mirror `pre_preview`'s existing embedded self-fix step block into `auto_review` (no new job). Add an `AGENT` env to `self-fix-pr.sh` that resolves which fix wrapper to invoke, and `FIX_AGENT`/`FIX_MODEL` env to `self-fix-loop.sh` that forward to the fix call only — kept distinct from the loop's own `AGENT`/`MODEL`, which stays fixed at `claude`/`review-model` for re-review. The `implement` job exposes `agent`/`model` outputs so both jobs' self-fix steps can source `FIX_AGENT`/`FIX_MODEL` from the actual implementer.

**Tech Stack:** Bash scripts (fixture-tested via `tests/run-script-tests.sh`), GitHub Actions reusable workflow (`actionlint` + `shellcheck` lint, `act` layer-2 test).

## Global Constraints

- Bash scripts: `set -euo pipefail` + `IFS=$'\n\t'` at the top of every script (repo convention, `.ai/stacks/ci.md`).
- Quote every variable expansion; `[[ ... ]]` over `[ ... ]`; `$(...)` over backticks.
- Exit codes are part of the API: `0` success, `1` generic error, `2` usage/env error (see each script's own header comment for its specific codes).
- No new inline bash step longer than 5 lines inside workflow YAML without extracting to `scripts/`.
- Action references stay pinned by full SHA (no floating tags) — none of this plan's tasks touch action `uses:` lines.
- Layer-1 tests live in `tests/run-script-tests.sh`; run with `bash tests/run-script-tests.sh` (must finish < 5s, exit 0).
- Lint every changed/new script with `shellcheck -x -e SC1091 <file>.sh`; lint workflow YAML with `actionlint`.
- Commit after each task.
- Review's own agent identity (`AGENT: claude`, `review-model`) must never change — only the *fix* call's agent/model become dynamic.

---

### Task 1: `self-fix-pr.sh` — `AGENT`-based fix-wrapper routing

**Files:**

- Modify: `scripts/self-fix-pr.sh`
- Create: `tests/mocks/self-fix-lib/agent-cmd-claude-fix.sh`
- Create: `tests/mocks/self-fix-lib/agent-cmd-opencode-fix.sh`
- Test: `tests/run-script-tests.sh` (`self-fix-pr` section, after line 1137)

**Interfaces:**

- Produces: `self-fix-pr.sh` gains an `AGENT` env var (`claude` | `opencode`, default `claude`) and a `FIX_LIB_DIR` env var (test seam, default `<script-dir>/lib`). When `FIX_AGENT_CMD` is unset, the default resolves to `$FIX_LIB_DIR/agent-cmd-claude-fix.sh` (AGENT=claude) or `$FIX_LIB_DIR/agent-cmd-opencode-fix.sh` (AGENT=opencode). An explicit `FIX_AGENT_CMD` still overrides both.

- [ ] **Step 1: Write the failing tests**

In `tests/run-script-tests.sh`, immediately after line 1137 (the blank line following the "no ambient git identity" test block, right before `section "self-fix-loop — bounded fix→re-review cycles"` at line 1139), insert:

```bash
# AGENT-based default resolution: claude → agent-cmd-claude-fix.sh (via FIX_LIB_DIR test seam)
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

# Default AGENT (unset) behaves as claude
REPO_DIR="$(make_self_fix_repo)"
out="$(WORK_DIR="$REPO_DIR" SKIP_CLONE=1 SKIP_PUSH=1 \
       REPO=o/r HEAD_REF=fix-branch ITERATION=1 \
       FIX_LIB_DIR="$MOCKS/self-fix-lib" \
       bash "$SELF_FIX_PR" 99 "$CONCERNS")"
edited="$(cat "$REPO_DIR/file.txt")"
assert_contains "$edited" 'fixed-by-claude' "AGENT unset → defaults to claude"
rm -rf "$REPO_DIR"

# Explicit FIX_AGENT_CMD still overrides AGENT-based resolution
REPO_DIR="$(make_self_fix_repo)"
out="$(WORK_DIR="$REPO_DIR" SKIP_CLONE=1 SKIP_PUSH=1 \
       REPO=o/r HEAD_REF=fix-branch ITERATION=1 AGENT=opencode \
       FIX_LIB_DIR="$MOCKS/self-fix-lib" \
       FIX_AGENT_CMD="$MOCKS/self-fix-agent" \
       bash "$SELF_FIX_PR" 99 "$CONCERNS")"
assert_contains "$out" 'fixed=true' "explicit FIX_AGENT_CMD still works"
edited="$(cat "$REPO_DIR/file.txt")"
assert_contains "$edited" 'fixed' "explicit FIX_AGENT_CMD overrides AGENT-based resolution"
rm -rf "$REPO_DIR"

# Invalid AGENT → exit 2
ec="$(run_capture_ec env REPO=o/r HEAD_REF=x ITERATION=1 AGENT=gpt5 bash "$SELF_FIX_PR" 99 "$CONCERNS")"
assert_equals "$ec" "2" "invalid AGENT → exit 2"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-script-tests.sh`
Expected: FAIL — the five new assertions error (`FIX_LIB_DIR`/`AGENT` not yet recognized, `tests/mocks/self-fix-lib/` doesn't exist).

- [ ] **Step 3: Create the mocks**

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
chmod +x tests/mocks/self-fix-lib/agent-cmd-claude-fix.sh tests/mocks/self-fix-lib/agent-cmd-opencode-fix.sh
```

- [ ] **Step 4: Write the implementation**

In `scripts/self-fix-pr.sh`, change the header comment's "Optional environment variables" list (after the `FIX_AGENT_CMD` entry) from:

```text
#   FIX_AGENT_CMD     Override the agent invocation. Contract:
#                       $FIX_AGENT_CMD <prompt-file>
#                     Agent edits files directly in the CWD. Default
#                     resolves to <script-dir>/lib/agent-cmd-claude-fix.sh.
#   MODEL             Model id passed to FIX_AGENT_CMD.
```

to:

```text
#   AGENT             claude | opencode — which agent implemented the
#                     issue (needs.implement.outputs.agent). Default:
#                     claude. Selects the default FIX_AGENT_CMD wrapper
#                     (ignored when FIX_AGENT_CMD is set explicitly).
#   FIX_AGENT_CMD     Override the agent invocation entirely. Contract:
#                       $FIX_AGENT_CMD <prompt-file>
#                     Agent edits files directly in the CWD. Takes
#                     precedence over AGENT-based resolution.
#   FIX_LIB_DIR       Directory the AGENT-based default resolves wrapper
#                     scripts from. Default: <script-dir>/lib. Test seam —
#                     lets Layer-1 tests point AGENT resolution at mock
#                     wrappers without touching the real lib/ scripts.
#   MODEL             Model id passed to FIX_AGENT_CMD.
```

Also change the "Exit codes" comment block from:

```text
# Exit codes:
#   0  fix committed (and pushed, unless SKIP_PUSH=1)
#   1  checkout / agent / commit / push failure, or agent made no changes
#   2  required env or args missing
```

to:

```text
# Exit codes:
#   0  fix committed (and pushed, unless SKIP_PUSH=1)
#   1  checkout / agent / commit / push failure, or agent made no changes
#   2  required env or args missing, or AGENT invalid
```

Then, in the body, change:

```bash
require_env REPO
require_env HEAD_REF
require_env ITERATION

if [[ ! -r "$CONCERNS_FILE" ]]; then
```

to:

```bash
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
```

Then change:

```bash
if [[ -z "${FIX_AGENT_CMD:-}" ]]; then
  FIX_AGENT_CMD="$SCRIPT_DIR/lib/agent-cmd-claude-fix.sh"
fi
```

to:

```bash
if [[ -z "${FIX_AGENT_CMD:-}" ]]; then
  FIX_LIB_DIR="${FIX_LIB_DIR:-$SCRIPT_DIR/lib}"
  case "$AGENT" in
    claude)   FIX_AGENT_CMD="$FIX_LIB_DIR/agent-cmd-claude-fix.sh" ;;
    opencode) FIX_AGENT_CMD="$FIX_LIB_DIR/agent-cmd-opencode-fix.sh" ;;
  esac
fi
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/run-script-tests.sh`
Expected: PASS — all five new assertions green, and every pre-existing `self-fix-pr` assertion (happy path, newfile, noop, crash, error paths, no-ambient-identity) still green.

- [ ] **Step 6: Lint**

Run: `shellcheck -x -e SC1091 scripts/self-fix-pr.sh`
Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add scripts/self-fix-pr.sh tests/mocks/self-fix-lib tests/run-script-tests.sh
git commit -m "feat(self-fix): AGENT-based fix-wrapper routing in self-fix-pr.sh (#193)"
```

---

### Task 2: `scripts/lib/agent-cmd-opencode-fix.sh` (new)

**Files:**

- Create: `scripts/lib/agent-cmd-opencode-fix.sh`

- [ ] **Step 1: Create the OpenCode fix-mode wrapper**

Create `scripts/lib/agent-cmd-opencode-fix.sh`:

```bash
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
```

- [ ] **Step 2: Make it executable and lint**

```bash
chmod +x scripts/lib/agent-cmd-opencode-fix.sh
shellcheck -x -e SC1091 scripts/lib/agent-cmd-opencode-fix.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Confirm the Layer-1 suite still passes**

Run: `bash tests/run-script-tests.sh`
Expected: PASS (this task only adds a new file; Task 1's tests already exercise it indirectly is false — Task 1's mocks are separate fixtures. This step just confirms no regression.)

- [ ] **Step 4: Commit**

```bash
git add scripts/lib/agent-cmd-opencode-fix.sh
git commit -m "feat(self-fix): OpenCode fix wrapper (#193)"
```

---

### Task 3: `self-fix-loop.sh` — `FIX_AGENT`/`FIX_MODEL` forwarding

**Files:**

- Modify: `scripts/self-fix-loop.sh`
- Modify: `tests/mocks/self-fix-loop-fix-stub`
- Test: `tests/run-script-tests.sh` (`self-fix-loop` section)

**Interfaces:**

- Produces: `self-fix-loop.sh` gains `FIX_AGENT` (default `claude`) / `FIX_MODEL` (default empty) env vars, forwarded to the `$FIX_CMD` call as `AGENT`/`MODEL` — distinct from the script's own `AGENT`/`MODEL`, which remain whatever the caller set for the `$REVIEW_SCRIPT` call (unchanged, inherited as today).

- [ ] **Step 1: Update the fix-stub mock to log AGENT/MODEL**

In `tests/mocks/self-fix-loop-fix-stub`, change:

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

to:

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

Existing test assertions that count log lines (`assert_equals "$(printf '%s\n' "$fix_calls" | grep -c .)" "2" ...`) are unaffected by the extra fields — only their content check strings would need `pr=... iteration=...` prefix matches, which none of today's assertions do (they only count lines). No other test changes needed for this step.

- [ ] **Step 2: Write the failing test**

In `tests/run-script-tests.sh`, immediately after line 1213 (`assert_contains "$out" 'iterations-used=2' "stub sequence consumes 2 entries"`, the last assertion before the `# Error paths` comment at line 1215), insert:

```bash
# FIX_AGENT/FIX_MODEL are forwarded to FIX_CMD as AGENT/MODEL, distinct
# from this script's own inherited AGENT (which must stay claude for the
# re-review call — see self-fix-loop-review-stub, which doesn't read
# AGENT/MODEL at all and so can't observe a collision directly; this
# assertion checks the FIX_CMD side, which does observe it).
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

# Defaults: FIX_AGENT/FIX_MODEL unset → FIX_CMD sees AGENT=claude, MODEL=(empty)
LOG="$(mktemp)"
go="$(mktemp)"
GITHUB_OUTPUT="$go" \
PR_NUMBER=42 REPO=o/r HEAD_SHA=initsha HEAD_REF=fix-branch \
INITIAL_VERDICT=request_changes CONCERNS_FILE="$LOOP_CONCERNS" MAX_ITERATIONS=3 \
FIX_CMD="$FIX_STUB" FIX_LOG="$LOG" \
REVIEW_SCRIPT="$REVIEW_STUB" REVIEW_VERDICTS='approve' NEW_HEAD_SHA=newsha \
  bash "$SELF_FIX_LOOP" >/dev/null
rm -f "$go"
fix_calls="$(cat "$LOG")"; rm -f "$LOG"
assert_contains "$fix_calls" 'agent=claude model=' "FIX_AGENT unset → defaults to claude, forwarded to FIX_CMD"
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bash tests/run-script-tests.sh`
Expected: FAIL — the two new assertions error (`self-fix-loop.sh` doesn't forward `AGENT`/`MODEL` to `$FIX_CMD` at all today, so the stub's log lines lack `agent=.../model=...`).

- [ ] **Step 4: Write the implementation**

In `scripts/self-fix-loop.sh`, change the header comment's "Optional environment variables" list — after the `FIX_CMD` entry:

```text
#   FIX_CMD        Override for the fix invocation. Contract:
#                    $FIX_CMD <pr-number> <concerns-json-file>
#                  (ITERATION, REPO, HEAD_REF passed via env per call.)
#                  Default: <script-dir>/self-fix-pr.sh.
#   REVIEW_SCRIPT  Override path to review-pr.sh (default: sibling
#                  script). Re-review calls reuse review-pr.sh's own env
#                  contract (AGENT, AGENT_CMD, MODEL, etc.) — those must
#                  already be present in this script's own environment,
#                  since child processes inherit it unmodified.
```

to:

```text
#   FIX_CMD        Override for the fix invocation. Contract:
#                    $FIX_CMD <pr-number> <concerns-json-file>
#                  (ITERATION, REPO, HEAD_REF, AGENT, MODEL passed via env
#                  per call — AGENT/MODEL come from FIX_AGENT/FIX_MODEL
#                  below, not from this script's own inherited AGENT/MODEL,
#                  which the REVIEW_SCRIPT call below needs to stay at the
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
```

Then change:

```bash
else
  FIX_CMD="${FIX_CMD:-$SCRIPT_DIR/self-fix-pr.sh}"
  REVIEW_SCRIPT="${REVIEW_SCRIPT:-$SCRIPT_DIR/review-pr.sh}"
  # shellcheck disable=SC2153 # CONCERNS_FILE (env) seeds local concerns_file; not a typo
  concerns_file="$CONCERNS_FILE"
```

to:

```bash
else
  FIX_CMD="${FIX_CMD:-$SCRIPT_DIR/self-fix-pr.sh}"
  REVIEW_SCRIPT="${REVIEW_SCRIPT:-$SCRIPT_DIR/review-pr.sh}"
  FIX_AGENT="${FIX_AGENT:-claude}"
  FIX_MODEL="${FIX_MODEL:-}"
  # shellcheck disable=SC2153 # CONCERNS_FILE (env) seeds local concerns_file; not a typo
  concerns_file="$CONCERNS_FILE"
```

Then change:

```bash
  for (( i = 1; i <= MAX_ITERATIONS; i++ )); do
    if ! ITERATION="$i" REPO="$REPO" HEAD_REF="$HEAD_REF" \
         "$FIX_CMD" "$PR_NUMBER" "$concerns_file"; then
```

to:

```bash
  for (( i = 1; i <= MAX_ITERATIONS; i++ )); do
    if ! ITERATION="$i" REPO="$REPO" HEAD_REF="$HEAD_REF" AGENT="$FIX_AGENT" MODEL="$FIX_MODEL" \
         "$FIX_CMD" "$PR_NUMBER" "$concerns_file"; then
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/run-script-tests.sh`
Expected: PASS — the two new assertions green, and every pre-existing `self-fix-loop` assertion still green (they don't check the fix-stub's `agent=`/`model=` fields, only `pr=`/`iteration=` via line-counting or `verdict=`/`iterations-used=`, so the stub's added output fields don't break them).

- [ ] **Step 6: Lint**

Run: `shellcheck -x -e SC1091 scripts/self-fix-loop.sh tests/mocks/self-fix-loop-fix-stub`
Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add scripts/self-fix-loop.sh tests/mocks/self-fix-loop-fix-stub tests/run-script-tests.sh
git commit -m "feat(self-fix): forward FIX_AGENT/FIX_MODEL to the fix call in self-fix-loop.sh (#193)"
```

---

### Task 4: `implement` job exposes `agent`/`model` outputs

**Files:**

- Modify: `.github/workflows/agent-implement.yml`

**Interfaces:**

- Produces: `needs.implement.outputs.agent` / `needs.implement.outputs.model` — consumed by Tasks 5 and 6.

- [ ] **Step 1: Add the outputs**

In `.github/workflows/agent-implement.yml`, change the `implement` job's `outputs:` block (currently at line 312):

```yaml
    outputs:
      outcome:             ${{ steps.outputs.outputs.outcome }}
      cost-usd:            ${{ steps.outputs.outputs.cost-usd }}
      num-turns:            ${{ steps.outputs.outputs.num-turns }}
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

(Note: `classify_agent`/`triage` steps are skipped entirely under `stub-claude: true` — their `if:` conditions require `!inputs.stub-claude` — so the `||` fallback to `inputs.agent`/`inputs.default-model` is what lets Task 7's Layer-2 act tests drive the resolved agent through the existing `agent` input without a new stub.)

- [ ] **Step 2: Lint the workflow**

Run: `actionlint .github/workflows/agent-implement.yml`
Expected: no output, exit 0.

- [ ] **Step 3: Confirm the Layer-1 suite still passes**

Run: `bash tests/run-script-tests.sh`
Expected: PASS (this task only touches YAML).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/agent-implement.yml
git commit -m "feat(workflow): implement job exposes agent/model outputs (#193)"
```

---

### Task 5: `pre_preview`'s self-fix step — hardcoded → dynamic agent/model

**Files:**

- Modify: `.github/workflows/agent-implement.yml`

- [ ] **Step 1: Rewire the self-fix step's env**

In `.github/workflows/agent-implement.yml`, in the `pre_preview` job's "Self-fix loop (pre-preview optional self-fix pass)" step, change:

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

to:

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
          MODEL: ${{ inputs.review-model }}
          FIX_AGENT: ${{ needs.implement.outputs.agent }}
          FIX_MODEL: ${{ needs.implement.outputs.model }}
          CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          OPENROUTER_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}
          STUB_VERDICT_SEQUENCE: ${{ inputs.stub-self-fix-verdict-sequence }}
        run: bash .claude-pipeline/scripts/self-fix-loop.sh
```

(`AGENT`/`AGENT_CMD`/`MODEL` stay exactly as before — they govern the re-review call via `REVIEW_SCRIPT`, which must stay Claude. `FIX_AGENT_CMD` is dropped: `self-fix-pr.sh`'s new `AGENT`-based resolution, driven by `FIX_AGENT` forwarded from `self-fix-loop.sh`, now picks the wrapper. `OPENROUTER_API_KEY` is added so an OpenCode fix wrapper invocation has its API key available.)

- [ ] **Step 2: Lint the workflow**

Run: `actionlint .github/workflows/agent-implement.yml`
Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/agent-implement.yml
git commit -m "feat(workflow): pre_preview self-fix routes to the original implementer's agent (#193)"
```

---

### Task 6: `auto_review` gains the self-fix block

**Files:**

- Modify: `.github/workflows/agent-implement.yml`

**Interfaces:**

- Produces: `auto_review` job output `self-fix-iterations-used` (mirroring `pre_preview`'s), consumed by Task 7's new workflow output.

- [ ] **Step 1: Add the `self-fix-iterations-used` job output**

In `.github/workflows/agent-implement.yml`, change the `auto_review` job's `outputs:` block:

```yaml
    outputs:
      merge-attempted: ${{ steps.verify_mock.outputs.merge-attempted }}
```

to:

```yaml
    outputs:
      merge-attempted:         ${{ steps.verify_mock.outputs.merge-attempted }}
      self-fix-iterations-used: ${{ steps.final.outputs.iterations-used }}
```

- [ ] **Step 2: Insert the self-fix + final-verdict steps**

Immediately after the "Resolve review verdict" step (ends with `run: printf 'value=%s\n' "${REAL:-$STUB}" >> "$GITHUB_OUTPUT"`) and immediately before the "Check merge envelope" step, insert:

```yaml
      - name: Self-fix loop (auto-review optional self-fix pass)
        if: |
          steps.self_mod_guard.outputs.blocked != 'true'
          && steps.find_pr.outputs.found == 'true'
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
          MODEL: ${{ inputs.review-model }}
          FIX_AGENT: ${{ needs.implement.outputs.agent }}
          FIX_MODEL: ${{ needs.implement.outputs.model }}
          CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          OPENROUTER_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}
          STUB_VERDICT_SEQUENCE: ${{ inputs.stub-self-fix-verdict-sequence }}
        run: bash .claude-pipeline/scripts/self-fix-loop.sh

      - name: Resolve final verdict (post self-fix)
        if: |
          steps.self_mod_guard.outputs.blocked != 'true'
          && steps.find_pr.outputs.found == 'true'
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

This is byte-for-byte the same pattern as `pre_preview`'s equivalent two steps, with the `self_mod_guard` condition folded in (auto_review-specific — pre_preview has no self-mod guard).

- [ ] **Step 3: Re-point envelope/promote/block to the final verdict**

Change the "Check merge envelope" step's `if:` and `PR_NUMBER` env (unchanged) from checking `steps.verdict.outputs.value`:

```yaml
      - name: Check merge envelope
        if: |
          steps.self_mod_guard.outputs.blocked != 'true'
          && steps.find_pr.outputs.found == 'true'
          && steps.verdict.outputs.value == 'approve'
        id: envelope
```

to:

```yaml
      - name: Check merge envelope
        if: |
          steps.self_mod_guard.outputs.blocked != 'true'
          && steps.find_pr.outputs.found == 'true'
          && steps.final.outputs.verdict == 'approve'
        id: envelope
```

Change "Promote draft to ready + enable auto-merge"'s `if:`:

```yaml
      - name: Promote draft to ready + enable auto-merge
        if: |
          steps.self_mod_guard.outputs.blocked != 'true'
          && steps.find_pr.outputs.found == 'true'
          && steps.verdict.outputs.value == 'approve'
          && steps.envelope.outputs.envelope == 'pass'
```

to:

```yaml
      - name: Promote draft to ready + enable auto-merge
        if: |
          steps.self_mod_guard.outputs.blocked != 'true'
          && steps.find_pr.outputs.found == 'true'
          && steps.final.outputs.verdict == 'approve'
          && steps.envelope.outputs.envelope == 'pass'
```

Change "Mark issue blocked when review or envelope refuses"'s `if:` and env:

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
        env:
          GH_TOKEN: ${{ github.token }}
          REPO: ${{ github.repository }}
          ISSUE_NUMBER: ${{ inputs.issue-number }}
          PR_NUMBER: ${{ steps.find_pr.outputs.pr-number }}
          FOUND: ${{ steps.find_pr.outputs.found }}
          VERDICT: ${{ steps.verdict.outputs.value }}
          ENVELOPE: ${{ steps.envelope.outputs.envelope }}
          ENVELOPE_REASON: ${{ steps.envelope.outputs.reason }}
          FAILED_GATES: ${{ steps.envelope.outputs.failed-gates }}
          SELF_MOD_BLOCKED: ${{ steps.self_mod_guard.outputs.blocked }}
        run: bash .claude-pipeline/scripts/post-auto-review-block.sh
```

to:

```yaml
      - name: Mark issue blocked when review or envelope refuses
        # Fires on every refusal path: self-mod guard, missing PR,
        # non-approve FINAL verdict (post self-fix, if it ran), or
        # envelope failure. post-auto-review-block.sh picks the right
        # reason and either comments on the PR (when known) or falls
        # back to the issue.
        if: |
          steps.self_mod_guard.outputs.blocked == 'true'
          || steps.find_pr.outputs.found != 'true'
          || steps.final.outputs.verdict != 'approve'
          || (steps.final.outputs.verdict == 'approve' && steps.envelope.outputs.envelope != 'pass')
        env:
          GH_TOKEN: ${{ github.token }}
          REPO: ${{ github.repository }}
          ISSUE_NUMBER: ${{ inputs.issue-number }}
          PR_NUMBER: ${{ steps.find_pr.outputs.pr-number }}
          FOUND: ${{ steps.find_pr.outputs.found }}
          VERDICT: ${{ steps.final.outputs.verdict }}
          ENVELOPE: ${{ steps.envelope.outputs.envelope }}
          ENVELOPE_REASON: ${{ steps.envelope.outputs.reason }}
          FAILED_GATES: ${{ steps.envelope.outputs.failed-gates }}
          SELF_MOD_BLOCKED: ${{ steps.self_mod_guard.outputs.blocked }}
          SELF_FIX_ITERATIONS: ${{ steps.final.outputs.iterations-used }}
          SELF_FIX_MAX: ${{ inputs.self-fix-max-iterations }}
        run: bash .claude-pipeline/scripts/post-auto-review-block.sh
```

(`post-auto-review-block.sh` already handles `SELF_FIX_ITERATIONS`/`SELF_FIX_MAX` generically across `MODE=auto-review` (the job's implicit default `MODE`, unset here same as today) and `MODE=pre-preview` — shipped in #221, no script change needed. `MODE` is intentionally left unset here, same as today, defaulting to `auto-review` inside the script.)

- [ ] **Step 4: Add the `auto-review-self-fix-iterations-used` workflow output**

In the `on.workflow_call.outputs:` block, immediately after `pre-preview-self-fix-iterations-used`, add:

```yaml
      auto-review-self-fix-iterations-used:
        description: |
          Iterations actually used by the auto-review self-fix loop (0 if
          it never ran). Populated only when `stub-review-verdict` /
          `stub-self-fix-verdict-sequence` is set.
        value: ${{ jobs.auto_review.outputs.self-fix-iterations-used }}
```

- [ ] **Step 5: Lint the workflow**

Run: `actionlint .github/workflows/agent-implement.yml`
Expected: no output, exit 0.

- [ ] **Step 6: Confirm the Layer-1 suite still passes**

Run: `bash tests/run-script-tests.sh`
Expected: PASS (this task only touches YAML; confirms no regression before Task 7's Layer-2 pass).

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/agent-implement.yml
git commit -m "feat(workflow): auto_review gains the self-fix pass (#193)"
```

---

### Task 7: Layer-2 act scenarios for `auto_review` self-fix

**Files:**

- Modify: `.github/workflows/agent-implement.test.yml`

- [ ] **Step 1: Add the call jobs**

In `.github/workflows/agent-implement.test.yml`, immediately after the `call-pre-preview-self-fix-exhausted:` job block (ends at line 403 with the `CLAUDE_CODE_OAUTH_TOKEN: not-used-by-stub` line under `secrets:`), add:

```yaml

  call-auto-review-self-fix-approve:
    name: Reusable workflow — auto-review self-fix fixes then approves
    uses: ./.github/workflows/agent-implement.yml
    with:
      issue-number: 9020
      timeout-minutes: 10
      local-scripts: true
      stub-claude: true
      stub-fixture: success
      auto-review: true
      dry-run: true
      stub-auto-review-enabled: true
      stub-review-verdict: request_changes
      stub-pr-files: |
        src/foo.ts
      self-fix: true
      self-fix-max-iterations: 3
      stub-self-fix-verdict-sequence: "request_changes,approve"
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: not-used-by-stub

  call-auto-review-self-fix-exhausted:
    name: Reusable workflow — auto-review self-fix cap exhausted
    uses: ./.github/workflows/agent-implement.yml
    with:
      issue-number: 9021
      timeout-minutes: 10
      local-scripts: true
      stub-claude: true
      stub-fixture: success
      auto-review: true
      dry-run: true
      stub-auto-review-enabled: true
      stub-review-verdict: request_changes
      stub-pr-files: |
        src/foo.ts
      self-fix: true
      self-fix-max-iterations: 2
      stub-self-fix-verdict-sequence: "request_changes,request_changes"
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: not-used-by-stub
```

(`stub-pr-files: src/foo.ts` mirrors `call-auto-review-approve-safe`'s envelope-passing fixture, so the final `approve` scenario's envelope check passes — proving self-fix's `approve` outcome actually reaches merge, not just that it stops early. `stub-self-fix-verdict-sequence` bypasses `self-fix-pr.sh`/`self-fix-loop.sh`'s real `FIX_CMD`/`REVIEW_SCRIPT` invocation entirely — per-agent wrapper routing (`FIX_AGENT`/`AGENT`) is Layer-1-tested in Tasks 1 and 3; this Layer-2 pass proves the workflow wiring: gating, the final-verdict resolution, and envelope/promote/block reading from it correctly, mirroring the existing `pre_preview` self-fix scenarios' scope exactly.)

- [ ] **Step 2: Add the assertion jobs**

Immediately after `verify-pre-preview-self-fix-exhausted:` (ends at line 568 with the `echo "self-fix cap-exhausted OK: ..."` line), add:

```yaml

  verify-auto-review-self-fix-approve:
    name: Assert auto-review self-fix fixes then approves → merge attempted
    needs: call-auto-review-self-fix-approve
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: read
    env:
      ATTEMPTED:  ${{ needs.call-auto-review-self-fix-approve.outputs.auto-review-merge-attempted }}
      ITERATIONS: ${{ needs.call-auto-review-self-fix-approve.outputs.auto-review-self-fix-iterations-used }}
    steps:
      - name: Assert merge attempted after 2 self-fix iterations
        run: |
          fail=0
          [[ "$ATTEMPTED" == "true" ]] || { echo "::error::merge-attempted=$ATTEMPTED (want true — self-fix approve + safe envelope must merge)"; fail=1; }
          [[ "$ITERATIONS" == "2" ]]   || { echo "::error::self-fix-iterations-used=$ITERATIONS (want 2)"; fail=1; }
          (( fail == 0 )) || exit 1
          echo "auto-review self-fix approve OK: merge=$ATTEMPTED iterations=$ITERATIONS"

  verify-auto-review-self-fix-exhausted:
    name: Assert auto-review self-fix cap exhausted → no merge
    needs: call-auto-review-self-fix-exhausted
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: read
    env:
      ATTEMPTED:  ${{ needs.call-auto-review-self-fix-exhausted.outputs.auto-review-merge-attempted }}
      ITERATIONS: ${{ needs.call-auto-review-self-fix-exhausted.outputs.auto-review-self-fix-iterations-used }}
    steps:
      - name: Assert no merge after cap exhausted
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

Run: `act pull_request -W .github/workflows/agent-implement.test.yml -j verify-auto-review-self-fix-approve`
Expected: job passes (`auto-review self-fix approve OK: merge=true iterations=2`).
If `act`/Docker is unavailable, skip — these run in CI on the pushed PR (Task 9).

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/agent-implement.test.yml
git commit -m "test(act): auto-review self-fix approve/cap-exhausted scenarios (#193)"
```

---

### Task 8: Docs — ADR-004 addendum, CONSUMER-SETUP.md, CHANGELOG.md

**Files:**

- Modify: `docs/DECISIONS.md`
- Modify: `docs/CONSUMER-SETUP.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add a second addendum to ADR-004**

In `docs/DECISIONS.md`, find the `### Addendum — Self-fix pass delivered (2026-07-31)` block under `## ADR-004`. Immediately after its last paragraph (ending "...byte-identical to the original wording when self-fix didn't run.") and before the next `## ADR-005` heading, add:

```markdown

### Addendum — Self-fix generalized to auto_review + agent routing (2026-08-04)

**Tracking:** [#193](https://github.com/freaxnx01/agent-workflow/issues/193)

The self-fix pass above generalizes further, closing two gaps: it only ran
inside `pre_preview`, and it always dispatched a hardcoded Claude fix
wrapper regardless of which agent actually implemented the issue.

+ `auto_review` (ADR-002) gains the identical embedded self-fix step
  `pre_preview` already had — same shape, not a shared job. On `approve`
  (first-pass or post-self-fix), the merge envelope is (re-)evaluated
  against the final HEAD before auto-merge, same as any other approve path.
+ The fix call now routes to `needs.implement.outputs.agent` (`claude` |
  `opencode`) and `needs.implement.outputs.model` — the agent that actually
  implemented the issue — instead of a hardcoded Claude wrapper and the
  *review* model. The review step's own agent identity (`AGENT: claude`,
  `review-model`) is unchanged; only the fix call's agent/model became
  dynamic. `scripts/self-fix-pr.sh` resolves the wrapper via a new `AGENT`
  env; a new `scripts/lib/agent-cmd-opencode-fix.sh` mirrors the existing
  Claude wrapper for the OpenCode case.
```

- [ ] **Step 2: Update CONSUMER-SETUP.md**

In `docs/CONSUMER-SETUP.md`, change:

```text
3. **Pre-preview** — labeled-issue → draft PR → agent reviews its own PR → on approve, promote draft→ready; a human merges. No envelope, no auto-merge. Opt in with `pre-preview: true` + the `ai-pre-preview` label. On `request_changes`, optionally opt into a bounded self-fix pass with `self-fix: true` (+ `self-fix-max-iterations`, default 2) — the agent attempts to fix its own findings and re-review before falling back to `ai:review-blocked`. See ADR-004.
```

to:

```text
3. **Pre-preview** — labeled-issue → draft PR → agent reviews its own PR → on approve, promote draft→ready; a human merges. No envelope, no auto-merge. Opt in with `pre-preview: true` + the `ai-pre-preview` label. On `request_changes` from either this flow or auto-review above, optionally opt into a bounded self-fix pass with `self-fix: true` (+ `self-fix-max-iterations`, default 2) — the *original implementer's* agent (Claude or OpenCode, whichever wrote the PR) attempts to fix its own findings and re-review before falling back to `ai:review-blocked`. See ADR-004.
```

- [ ] **Step 3: Add a CHANGELOG.md entry**

In `CHANGELOG.md`, under `## [Unreleased]` → `### Added`, immediately after the existing self-fix entry (starting "**pre-preview:** `self-fix` and `self-fix-max-iterations` workflow inputs..."), add:

```markdown
- **self-fix:** generalized to also run inside auto-review (not just
  pre-preview), and to route the fix call to whichever agent (Claude or
  OpenCode) actually implemented the issue instead of a hardcoded Claude
  fallback (#193).
```

- [ ] **Step 4: Confirm nothing regressed**

Run: `bash tests/run-script-tests.sh`
Expected: PASS (docs don't affect scripts; this just confirms nothing regressed).

- [ ] **Step 5: Commit**

```bash
git add docs/DECISIONS.md docs/CONSUMER-SETUP.md CHANGELOG.md
git commit -m "docs: self-fix generalization — ADR-004 addendum, CONSUMER-SETUP, CHANGELOG (#193)"
```

---

### Task 9: Push, open PR, confirm CI green, update issue #193

**Files:** none (integration)

- [ ] **Step 1: Run the full local gate once more**

```bash
bash tests/run-script-tests.sh
shellcheck -x -e SC1091 scripts/self-fix-pr.sh scripts/self-fix-loop.sh \
  scripts/lib/agent-cmd-opencode-fix.sh
actionlint
```

Expected: all green / no output.

- [ ] **Step 2: Push the branch**

```bash
git push -u origin worktree-enrich
```

- [ ] **Step 3: Open the PR**

```bash
gh pr create -R freaxnx01/agent-workflow --base main --head worktree-enrich \
  --title "feat(self-fix): generalize to auto_review + agent routing (#193)" \
  --body "Implements docs/superpowers/specs/2026-08-04-self-fix-generalization-design.md. Generalizes #81/#221's pre-preview-only, Claude-only self-fix pass: auto_review gains the same embedded self-fix step, and the fix call now routes to whichever agent (Claude or OpenCode) actually implemented the issue instead of a hardcoded Claude fallback. Closes #193."
```

- [ ] **Step 4: Confirm CI green**

Run: `gh pr checks <PR#> -R freaxnx01/agent-workflow`
Expected: `actionlint`, `shellcheck`, the new `verify-auto-review-self-fix-approve` / `verify-auto-review-self-fix-exhausted` jobs, and all pre-existing `verify-pre-preview-*` / `verify-auto-review-*` jobs pass (no regression).

- [ ] **Step 5: Update issue #193**

Check off the acceptance-criteria items now satisfied. Do not auto-close — a human merges the PR, which closes #193 via "Closes #193".

---

## Self-Review notes (author)

- **Spec coverage:** §1 `implement` job outputs (Task 4) · §2 fix-agent resolution, `self-fix-pr.sh`'s `AGENT` routing (Task 1) · §3 `agent-cmd-opencode-fix.sh` (Task 2) · §4 `self-fix-loop.sh`'s `FIX_AGENT`/`FIX_MODEL` (Task 3) · §5 `pre_preview` rewire (Task 5) · §6 `auto_review` self-fix block + re-pointed envelope/promote/block (Task 6) · §7 new workflow output (Task 6, Step 4) · Testing strategy's Layer-1/Layer-2/docs items (Tasks 1, 3, 7, 8).
- **All file paths, script contracts, and workflow step names verified against the actual current repo state** (post-rebase onto `main`, which already contains #221) — not against the superseded 2026-08-01 plan's assumptions. `self-fix-loop.sh`'s real structure (graceful degradation on fix/review failure, `MAX_ITERATIONS=0` handling, `abort_iteration` helper) is preserved untouched by Task 3's diff; only the `FIX_CMD` invocation line and header comment change.
- **No placeholders:** every script/YAML/doc edit shows full before/after content or full new-file content.
- **Name consistency:** `AGENT` / `FIX_AGENT_CMD` / `FIX_LIB_DIR` (self-fix-pr.sh); `FIX_AGENT` / `FIX_MODEL` (self-fix-loop.sh, distinct from its own `AGENT`/`MODEL`); `agent-cmd-opencode-fix.sh`; job outputs `self-fix-iterations-used` (both jobs) and workflow output `auto-review-self-fix-iterations-used` — used identically across all tasks that reference them.
- **Test isolation:** Task 3's mock-log format change (`self-fix-loop-fix-stub`) was checked against every existing assertion that reads `$FIX_LOG` — all of them count lines or check `iterations-used`/`verdict` outputs, none pattern-match the stub's exact line content, so the added `agent=.../model=...` suffix doesn't break pre-existing tests.
