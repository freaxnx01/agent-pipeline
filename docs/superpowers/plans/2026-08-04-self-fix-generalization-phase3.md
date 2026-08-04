# Self-Fix Generalization Implementation Plan — Phase 3 of 3 (Layer-2 tests + docs)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close out issue #193 — Layer-2 `act` scenarios proving `auto_review`'s self-fix pass works end-to-end through the workflow (approve and cap-exhausted paths), and the docs pass (ADR-004 addendum, `CONSUMER-SETUP.md`, `CHANGELOG.md`) documenting the full, now-shipped generalization.

**Prerequisites (already satisfied, verify before starting):**

```bash
grep -n "call-pre-preview-self-fix-exhausted:\|verify-pre-preview-self-fix-exhausted:" .github/workflows/agent-implement.test.yml
grep -n "auto-review-self-fix-iterations-used" .github/workflows/agent-implement.yml
```

Expected: both present (Phase 1's scripts, Phase 2's `auto_review` self-fix block and its `auto-review-self-fix-iterations-used` workflow output — merged via PR #232 and #235). If either is absent, stop.

**Full design reference:** `docs/superpowers/specs/2026-08-04-self-fix-generalization-design.md`. Task 7 below is extracted verbatim from the original unsplit plan (`docs/superpowers/plans/2026-08-04-self-fix-generalization.md`, Task 7); Task 8 is updated to match what actually shipped in Phases 1–2 (the original Task 8's addendum text was written speculatively before implementation — verified accurate against the merged code before inclusion here).

## Global Constraints

- Layer-1 tests live in `tests/run-script-tests.sh`; run with `bash tests/run-script-tests.sh` (must finish < 5s per the stack's own convention, though the current suite already runs ~25-30s — pre-existing, not this phase's regression to fix).
- Lint every changed workflow with `actionlint`.
- Commit after each task.
- **Push directly, not via `ai-implement`.** Task 7 touches `.github/workflows/agent-implement.test.yml` — a file under `.github/workflows/`, which the pipeline's GitHub App token cannot push to (confirmed twice now, Phases 1 and 2). Task 8 (docs only) could in principle go through the pipeline, but keep this phase's execution path consistent with Phases 1–2 rather than splitting a 2-task phase further.
- Review's own agent identity (`AGENT: claude`, `review-model`) is unaffected by this phase — no script or job-body changes, only a new test file section and docs.

---

### Task 7: Layer-2 act scenarios for `auto_review` self-fix

**Files:**

- Modify: `.github/workflows/agent-implement.test.yml`

- [ ] **Step 1: Add the call jobs**

In `.github/workflows/agent-implement.test.yml`, immediately after the `call-pre-preview-self-fix-exhausted:` job block (ends with the `CLAUDE_CODE_OAUTH_TOKEN: not-used-by-stub` line under `secrets:`), add:

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

(`issue-number: 9020`/`9021` — verified unused by any other scenario in this file before adding. `stub-pr-files: src/foo.ts` mirrors `call-auto-review-approve-safe`'s envelope-passing fixture, so the final `approve` scenario's envelope check passes — proving self-fix's `approve` outcome actually reaches merge, not just that it stops early. `stub-self-fix-verdict-sequence` bypasses `self-fix-pr.sh`/`self-fix-loop.sh`'s real `FIX_CMD`/`REVIEW_SCRIPT` invocation entirely — per-agent wrapper routing is already Layer-1-tested (Phase 1); this Layer-2 pass proves the workflow wiring: gating, the final-verdict resolution, and envelope/promote/block reading from it correctly, mirroring the existing `pre_preview` self-fix scenarios' scope exactly.)

- [ ] **Step 2: Add the assertion jobs**

Immediately after `verify-pre-preview-self-fix-exhausted:` (ends with the `echo "self-fix cap-exhausted OK: ..."` line), add:

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

- [ ] **Step 6: Push directly (not via ai-implement — see Global Constraints)**

```bash
git push origin <branch>
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
  See ADR-002's own addendum (2026-08-04) for a known limitation on this
  path: a self-fix-approved PR commonly still lands in `ai:review-blocked`
  today, because the envelope's required-checks gate runs before CI on the
  freshly-pushed fix commit has finished.
+ The fix call now routes to `needs.implement.outputs.agent` (`claude` |
  `opencode`) and `needs.implement.outputs.model` — the agent that actually
  implemented the issue — instead of a hardcoded Claude wrapper and the
  *review* model. The review step's own agent identity (`AGENT: claude`,
  `review-model`) is unchanged; only the fix call's agent/model became
  dynamic. `scripts/self-fix-pr.sh` resolves the wrapper via a new `AGENT`
  env; `scripts/lib/agent-cmd-opencode-fix.sh` mirrors the existing Claude
  wrapper for the OpenCode case.
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

- [ ] **Step 6: Push directly (not via ai-implement — see Global Constraints)**

```bash
git push origin <branch>
```

---

## Phase boundary — this is the final phase

- [ ] **Open the PR referencing `Closes #193`** — unlike Phases 1–2 (which used "Part of #193" to avoid a premature auto-close), this phase completes the feature: Layer-2 tests + docs are the last items. Once this PR merges, issue #193 should close automatically via the `Closes #193` footer.
- [ ] **Confirm CI green**, including the two new `verify-auto-review-self-fix-*` jobs and all pre-existing `verify-pre-preview-*`/`verify-auto-review-*` jobs (no regression).
- [ ] After merge, confirm issue #193 is actually closed (`gh issue view 193 --json state`) — if the `Closes #193` footer didn't take effect for any reason (e.g. PR body edited after creation and the footer got dropped), close it manually with a summary comment referencing all three phases' PRs (#232, #235, and this one).

## Self-Review notes (author)

- **Task 7 unchanged from the original unsplit plan** — verified line-number-free (searches by content, not line numbers) and issue-number-collision-free (9020/9021 confirmed unused) against the current `agent-implement.test.yml` before inclusion here.
- **Task 8 updated, not copied blindly**: the ADR-004 addendum insertion point was re-verified present and unchanged; the addendum text itself was re-checked against what Phases 1–2 actually shipped (not what the original plan assumed before implementation) and gained one added sentence cross-referencing the ADR-002 pending-checks addendum Phase 2's final review produced — so a reader of ADR-004's addendum isn't surprised by the auto-merge caveat living in a different ADR section.
- **No placeholders:** every workflow/doc edit shows full content.
- **This phase closes the issue** — the PR body must say `Closes #193`, distinct from Phases 1–2's `Part of #193` wording.
