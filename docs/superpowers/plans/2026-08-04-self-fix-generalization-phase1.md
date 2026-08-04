# Self-Fix Generalization Implementation Plan — Phase 1 of 3 (scripts + implement outputs)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lay the script-level and `implement`-job groundwork for routing self-fix to the original implementer's agent: `self-fix-pr.sh` gains `AGENT`-based fix-wrapper routing, a new OpenCode fix wrapper exists, `self-fix-loop.sh` forwards `FIX_AGENT`/`FIX_MODEL` distinct from its own re-review `AGENT`/`MODEL`, and the `implement` job exposes `agent`/`model` as job outputs.

**Why split into phases:** The full generalization (originally one 9-task plan) exceeded a single pipeline dispatch's turn budget (50/50 turns exhausted, no PR opened — see the failed run on issue #193, 2026-08-04). This phase is scoped to exactly the four *additive, independently testable* tasks that touch scripts and one small workflow-outputs diff — no cross-job workflow rewiring yet, which is the highest-risk, most turn-expensive part of the original plan. Phases 2 and 3 (the actual `pre_preview`/`auto_review` workflow wiring, Layer-2 tests, and docs) will be filed as follow-up issues once this phase's PR merges, each scoped the same way.

**Full design reference:** `docs/superpowers/specs/2026-08-04-self-fix-generalization-design.md` — describes the complete feature this phase is part of. `docs/superpowers/plans/2026-08-04-self-fix-generalization.md` is the original unsplit 9-task plan (Tasks 1–4 below are extracted from it verbatim, unchanged) — Tasks 5–9 there become Phases 2–3.

**Architecture:** (of the full feature, for context) Mirror `pre_preview`'s existing embedded self-fix step block into `auto_review` (no new job). Add an `AGENT` env to `self-fix-pr.sh` that resolves which fix wrapper to invoke, and `FIX_AGENT`/`FIX_MODEL` env to `self-fix-loop.sh` that forward to the fix call only — kept distinct from the loop's own `AGENT`/`MODEL`, which stays fixed at `claude`/`review-model` for re-review. The `implement` job exposes `agent`/`model` outputs so both jobs' self-fix steps can source `FIX_AGENT`/`FIX_MODEL` from the actual implementer. **This phase only builds the script/output side of that architecture** — the workflow steps that consume it (pre_preview's rewire, auto_review's new block) are Phase 2.

**Tech Stack:** Bash scripts (fixture-tested via `tests/run-script-tests.sh`), GitHub Actions reusable workflow (`actionlint` + `shellcheck` lint).

## Global Constraints

- Bash scripts: `set -euo pipefail` + `IFS=$'\n\t'` at the top of every script (repo convention, `.ai/stacks/ci.md`).
- Quote every variable expansion; `[[ ... ]]` over `[ ... ]`; `$(...)` over backticks.
- Exit codes are part of the API: `0` success, `1` generic error, `2` usage/env error (see each script's own header comment for its specific codes).
- No new inline bash step longer than 5 lines inside workflow YAML without extracting to `scripts/`.
- Action references stay pinned by full SHA (no floating tags) — none of this plan's tasks touch action `uses:` lines.
- Layer-1 tests live in `tests/run-script-tests.sh`; run with `bash tests/run-script-tests.sh` (must finish < 5s, exit 0).
- Lint every changed/new script with `shellcheck -x -e SC1091 <file>.sh`; lint workflow YAML with `actionlint`.
- **Commit after each task — this matters even more than usual in a turn-budgeted pipeline run: if you run out of turns mid-phase, a committed-and-pushed partial PR covering Tasks 1–N is useful; uncommitted work in the working tree is not.**
- Review's own agent identity (`AGENT: claude`, `review-model`) must never change — only the *fix* call's agent/model become dynamic (this doesn't come up until Phase 2, but keep it in mind if you read ahead in the full design doc).

---

## Task 1: `self-fix-pr.sh` — `AGENT`-based fix-wrapper routing

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

## Task 2: `scripts/lib/agent-cmd-opencode-fix.sh` (new)

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

## Task 3: `self-fix-loop.sh` — `FIX_AGENT`/`FIX_MODEL` forwarding

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

## Task 4: `implement` job exposes `agent`/`model` outputs

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

## Phase boundary

This phase ends here — do **not** attempt Tasks 5–9 from the original unsplit plan
(`docs/superpowers/plans/2026-08-04-self-fix-generalization.md`) in this run. After
Task 4's commit:

- [ ] **Push and open the PR** (the pipeline's own `implement` job step handles this
  automatically at the end of the run — no separate action needed here, unlike a
  manually-run plan).
- [ ] **Do not touch `.github/workflows/agent-implement.yml`'s `pre_preview` or
  `auto_review` job bodies** — only the `implement` job's `outputs:` block (Task 4).
  Phase 2 depends on Task 4's `agent`/`model` outputs existing on `main`, so it must
  land and merge before Phase 2 is dispatched.

## Self-Review notes (author)

- **Scope discipline:** every task below is additive-only (new files, or diffs to
  files not touched by any other task in this phase) — no task in this phase depends
  on another phase's not-yet-existing code. `self-fix-loop.sh` (Task 3) forwards
  `AGENT`/`MODEL` to `$FIX_CMD` regardless of whether any caller sets `FIX_AGENT`/
  `FIX_MODEL` yet (they default to `claude`/empty) — so Phase 1 alone is a no-op
  change in production behavior (nothing new calls these scripts with a different
  `AGENT` until Phase 2 wires the workflow steps), safe to merge standalone.
- **No placeholders:** every script/YAML edit shows full before/after content or
  full new-file content, extracted verbatim from the original 9-task plan's
  self-reviewed Tasks 1–4.
- **Name consistency:** `AGENT` / `FIX_AGENT_CMD` / `FIX_LIB_DIR` (self-fix-pr.sh);
  `FIX_AGENT` / `FIX_MODEL` (self-fix-loop.sh, distinct from its own `AGENT`/`MODEL`);
  `agent-cmd-opencode-fix.sh`; `implement` job outputs `agent`/`model` — all carried
  forward unchanged into Phase 2's plan when it's written.
