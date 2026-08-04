# Fix 2 Pre-existing Layer-1 Test Failures Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `tests/run-script-tests.sh` pass 348/348 by fixing a stale test-data whitespace mismatch and normalizing an inconsistent status message.

**Architecture:** Two independent one-line fixes, each with its own failing-test-first verification: (1) a whitespace typo in a test assertion's marker string, (2) a missing word in one of three sibling status-message branches in `scripts/ensure-toolchain.sh`.

**Tech Stack:** Bash, `tests/run-script-tests.sh` fixture-driven Layer-1 test suite, `shellcheck`.

## Global Constraints

- Use Test-Driven Development for every task: write a failing test first, watch it fail, implement minimally to pass, verify green.
- Do not weaken or remove either assertion — fix the drift at its source (test-data string / script output).
- No change to `agent-*` workflow behavior.
- `shellcheck -x scripts/ensure-toolchain.sh` must stay clean.
- Reference issue #107 in commits.

---

### Task 1: Fix stale `[Fact(Skip = ` marker whitespace

**Files:**
- Modify: `tests/run-script-tests.sh:523`
- Test: `tests/run-script-tests.sh` (the suite's own `rule 2: matcher example ... present` assertion loop, lines ~520-530)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: nothing consumed by later tasks (independent of Task 2).

**Context:** `tests/run-script-tests.sh:523` currently reads:
```bash
for marker in 'xit(' '@pytest.mark.skip' '@Ignore' '[Fact(Skip = ' 't.Skip(' '@Skip('; do
```
The `'[Fact(Skip = '` entry has a trailing space after `=` that doesn't match `scripts/lib/review-prompt.md:41`, which writes `` `[Fact(Skip =` `` (no trailing space). This causes `assert_contains` to never match for that marker.

- [ ] **Step 1: Confirm the failing assertion**

Run: `bash tests/run-script-tests.sh 2>&1 | grep -A1 "Fact(Skip"`
Expected: a line showing `✗ rule 2: matcher example '[Fact(Skip = ' present` (failing).

- [ ] **Step 2: Fix the marker string**

In `tests/run-script-tests.sh:523`, change:
```bash
for marker in 'xit(' '@pytest.mark.skip' '@Ignore' '[Fact(Skip = ' 't.Skip(' '@Skip('; do
```
to:
```bash
for marker in 'xit(' '@pytest.mark.skip' '@Ignore' '[Fact(Skip =' 't.Skip(' '@Skip('; do
```
(remove the trailing space after `=` in the `[Fact(Skip =` entry only — leave the other five markers unchanged.)

- [ ] **Step 3: Run test to verify it passes**

Run: `bash tests/run-script-tests.sh 2>&1 | grep "Fact(Skip"`
Expected: `✓ rule 2: matcher example '[Fact(Skip =' present` (passing, no more trailing-space mismatch).

- [ ] **Step 4: Commit**

```bash
git add tests/run-script-tests.sh
git commit -m "test: fix stale [Fact(Skip = marker whitespace mismatch

Refs #107"
```

---

### Task 2: Normalize the "present but different version" opencode message

**Files:**
- Modify: `scripts/ensure-toolchain.sh:89`
- Test: `tests/run-script-tests.sh:1566-1567` (existing `OPENCODE_VERSION env overrides the pinned default` assertion)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: nothing consumed by later tasks (independent of Task 1).

**Context:** `scripts/ensure-toolchain.sh` has three opencode status messages inside `ensure_opencode()`. Two include the word "version":
```bash
printf 'opencode already at pinned version %s\n' "$OPENCODE_VERSION"
...
printf 'opencode not present; installing pinned version %s\n' "$OPENCODE_VERSION"
```
But the "present at a different version" branch (line 89) omits it:
```bash
printf 'opencode present but at %s; installing pinned %s\n' \
  "${current:-unknown}" "$OPENCODE_VERSION"
```
On a host where `opencode` is already on PATH at a version other than the pinned `OPENCODE_VERSION` (e.g. `9.9.9` in the test), this branch runs and prints `installing pinned 9.9.9` instead of `installing pinned version 9.9.9`, so the test assertion `assert_contains "$out" 'pinned version 9.9.9'` fails. Whether this branch or the "not present" branch runs depends on whether `opencode` happens to be on the test-runner's PATH already, which is why the failure looked intermittent.

- [ ] **Step 1: Confirm the failing assertion (only fails when `opencode` is already on PATH at a different version)**

Run: `command -v opencode >/dev/null 2>&1 && echo "opencode on PATH: repro possible" || echo "opencode not on PATH: branch not exercised on this host"`

If opencode is not on PATH here, skip straight to Step 2 — the fix is still correct and required by the issue regardless of whether this host reproduces the failure; Step 3 will confirm via direct function invocation.

- [ ] **Step 2: Fix the message**

In `scripts/ensure-toolchain.sh:89`, change:
```bash
    printf 'opencode present but at %s; installing pinned %s\n' \
      "${current:-unknown}" "$OPENCODE_VERSION"
```
to:
```bash
    printf 'opencode present but at %s; installing pinned version %s\n' \
      "${current:-unknown}" "$OPENCODE_VERSION"
```

- [ ] **Step 3: Run test to verify it passes**

Run:
```bash
AGENT=opencode TOOLS="bash sh" OPENCODE_DRY_RUN=1 OPENCODE_VERSION=9.9.9 bash scripts/ensure-toolchain.sh | grep "pinned version 9.9.9"
```
Expected: output contains `pinned version 9.9.9` regardless of which of the three branches runs (verifies the fixed wording directly, independent of whatever opencode state this host happens to have).

Then run the full suite:
Run: `bash tests/run-script-tests.sh 2>&1 | grep "OPENCODE_VERSION"`
Expected: `✓ ... OPENCODE_VERSION env overrides the pinned default` (passing).

- [ ] **Step 4: shellcheck**

Run: `shellcheck -x scripts/ensure-toolchain.sh`
Expected: no new warnings introduced.

- [ ] **Step 5: Commit**

```bash
git add scripts/ensure-toolchain.sh
git commit -m "fix(ensure-toolchain): surface pinned version in opencode-present-different-version message

Refs #107"
```

---

### Task 3: Full suite green + final verification

**Files:**
- None modified (verification only).

**Interfaces:**
- Consumes: the fixes from Task 1 and Task 2.
- Produces: nothing (final task).

- [ ] **Step 1: Run the full Layer-1 suite**

Run: `bash tests/run-script-tests.sh`
Expected: `348/348 tests passed` (or the current total — confirm no other failures were introduced), zero `✗` lines.

- [ ] **Step 2: Run shellcheck across the touched scripts**

Run: `shellcheck -x scripts/ensure-toolchain.sh`
Expected: clean.

- [ ] **Step 3: Confirm no `agent-*` workflow YAML was touched**

Run: `git diff --stat main` (or `git diff --stat` against the base branch)
Expected: only `tests/run-script-tests.sh` and `scripts/ensure-toolchain.sh` appear.
