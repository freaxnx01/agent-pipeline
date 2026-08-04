# Self-Fix Generalization Implementation Plan — Phase 2 of 3 (workflow wiring)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the script-level groundwork from Phase 1 into the actual `pre_preview` and `auto_review` jobs: route each job's self-fix pass to the original implementer's agent/model (dropping the hardcoded Claude fallback), and give `auto_review` the same self-fix block `pre_preview` already has.

**Prerequisite (already satisfied):** Phase 1's Task 4 — the `implement` job's `agent`/`model` outputs — is merged on `main`. Verify before starting:

```bash
grep -n "agent:.*classify_agent.outputs.agent\|model:.*triage.outputs.model" .github/workflows/agent-implement.yml
```

Expected: two matches inside the `implement` job's `outputs:` block. If absent, stop — Phase 2 cannot proceed without it.

**Full design reference:** `docs/superpowers/specs/2026-08-04-self-fix-generalization-design.md`. `docs/superpowers/plans/2026-08-04-self-fix-generalization.md` is the original unsplit 9-task plan — Tasks 5–6 below are extracted from it, plus one addition (OpenCode toolchain install) that Phase 1's PR review (#232) flagged as a gap this phase must close, not defer further.

**Architecture:** (of the full feature, for context) Mirror `pre_preview`'s existing embedded self-fix step block into `auto_review` (no new job). Both jobs' self-fix steps source `FIX_AGENT`/`FIX_MODEL` from `needs.implement.outputs.agent`/`.model` (Phase 1) instead of a hardcoded Claude wrapper. Review's own agent identity (`AGENT: claude`, `review-model`) never changes.

## Global Constraints

- No new inline bash step longer than 5 lines inside workflow YAML without extracting to `scripts/`.
- Action references stay pinned by full SHA (no floating tags) — none of this plan's tasks touch action `uses:` lines.
- Layer-1 tests live in `tests/run-script-tests.sh`; run with `bash tests/run-script-tests.sh` (must finish < 5s, exit 0) — this phase only touches workflow YAML, so Layer-1 is a regression check, not new test-writing.
- Lint every changed workflow with `actionlint`.
- **Commit after each task** — if a turn-budgeted pipeline run stops mid-phase, a committed-and-pushed partial PR covering Task 5 alone is still useful.
- **Push workflow-file changes directly, not through the pipeline's own `ai-implement` dispatch.** Phase 1 discovered the pipeline's GitHub App token lacks `workflows` permission and cannot push any commit touching `.github/workflows/*.yml` — confirmed by a direct push with ordinary git credentials succeeding where the pipeline's token was refused. Whoever executes this plan needs `git push` credentials with the standard `workflow` OAuth scope (an interactive `gh auth login`-based session has this by default; the pipeline's constrained App token does not). **Do not dispatch this plan via the `ai-implement` label** — it will fail at the git-push step exactly like Phase 1's Task 4 did.
- Review's own agent identity (`AGENT: claude`, `review-model`) must never change — only the *fix* call's agent/model are dynamic.

---

### Task 5: `pre_preview`'s self-fix step — hardcoded → dynamic agent/model, OpenCode toolchain

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

(`AGENT`/`AGENT_CMD`/`MODEL` stay exactly as before — they govern the re-review call via `REVIEW_SCRIPT`, which must stay Claude. `FIX_AGENT_CMD` is dropped: `self-fix-pr.sh`'s `AGENT`-based resolution, driven by `FIX_AGENT` forwarded from `self-fix-loop.sh`, now picks the wrapper. `OPENROUTER_API_KEY` is added so an OpenCode fix wrapper invocation has its API key available.)

- [ ] **Step 2: Install the OpenCode CLI when the fix agent is OpenCode**

PR #232's review (Phase 1) flagged: `pre_preview` only installs the Claude CLI (`npm install -g @anthropic-ai/claude-code`); if `FIX_AGENT` resolves to `opencode`, `agent-cmd-opencode-fix.sh` fails with exit 127 (`opencode` not found) instead of `check-opencode-auth.sh`'s actionable `AuthError`. Mirror the `implement` job's own conditional install (`.github/workflows/agent-implement.yml`, step "Ensure OpenCode toolchain", lines ~417–425).

Immediately before the "Self-fix loop (pre-preview optional self-fix pass)" step (from Step 1, now with the rewired env), insert:

```yaml
      - name: Ensure OpenCode toolchain (self-fix)
        # Mirrors the implement job's own conditional OpenCode install
        # (#62) — the base toolchain step doesn't know the fix agent
        # ahead of time, so install opencode here once FIX_AGENT is
        # known, only when it's actually opencode.
        if: |
          steps.find_pr.outputs.found == 'true'
          && steps.verdict.outputs.value == 'request_changes'
          && inputs.self-fix
          && needs.implement.outputs.agent == 'opencode'
        env:
          AGENT: opencode
        run: bash .claude-pipeline/scripts/ensure-toolchain.sh

      - name: Self-fix loop (pre-preview optional self-fix pass)
```

(Only the `- name: Self-fix loop...` line is shown again as an anchor — the rest of that step's body is unchanged from Step 1.)

- [ ] **Step 3: Lint the workflow**

Run: `actionlint .github/workflows/agent-implement.yml`
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/agent-implement.yml
git commit -m "feat(workflow): pre_preview self-fix routes to the original implementer's agent (#193)"
```

- [ ] **Step 5: Push directly (not via ai-implement — see Global Constraints)**

```bash
git push origin <branch>
```

---

### Task 6: `auto_review` gains the self-fix block, OpenCode toolchain

**Files:**

- Modify: `.github/workflows/agent-implement.yml`

**Interfaces:**

- Produces: `auto_review` job output `self-fix-iterations-used` (mirroring `pre_preview`'s), consumed by Phase 3's new workflow output.

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

- [ ] **Step 2: Insert the OpenCode-toolchain + self-fix + final-verdict steps**

Immediately after the "Resolve review verdict" step (ends with `run: printf 'value=%s\n' "${REAL:-$STUB}" >> "$GITHUB_OUTPUT"`) and immediately before the "Check merge envelope" step, insert:

```yaml
      - name: Ensure OpenCode toolchain (self-fix)
        # See the equivalent step in pre_preview (#193) — same reasoning.
        if: |
          steps.self_mod_guard.outputs.blocked != 'true'
          && steps.find_pr.outputs.found == 'true'
          && steps.verdict.outputs.value == 'request_changes'
          && inputs.self-fix
          && needs.implement.outputs.agent == 'opencode'
        env:
          AGENT: opencode
        run: bash .claude-pipeline/scripts/ensure-toolchain.sh

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

This is the same pattern as `pre_preview`'s equivalent steps (Task 5), with the `self_mod_guard` condition folded in — `auto_review`-specific, `pre_preview` has no self-mod guard.

- [ ] **Step 3: Re-point envelope/promote/block to the final verdict**

Change the "Check merge envelope" step's `if:` from checking `steps.verdict.outputs.value`:

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

(`post-auto-review-block.sh` already handles `SELF_FIX_ITERATIONS`/`SELF_FIX_MAX` generically across `MODE=auto-review` (this job's implicit default, unset here same as today) and `MODE=pre-preview` — shipped in #221, no script change needed.)

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
Expected: PASS (this task only touches YAML; confirms no regression before Phase 3's Layer-2 pass).

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/agent-implement.yml
git commit -m "feat(workflow): auto_review gains the self-fix pass (#193)"
```

- [ ] **Step 8: Push directly (not via ai-implement — see Global Constraints)**

```bash
git push origin <branch>
```

---

## Phase boundary

This phase ends here — do **not** attempt Layer-2 act tests or docs (Phase 3) in
this run; open a PR for Tasks 5–6 and stop.

## Self-Review notes (author)

- **Prerequisite verified against real `main`:** Task 4's `agent`/`model` outputs
  were confirmed present in `.github/workflows/agent-implement.yml`'s `implement`
  job before this plan was finalized — Phase 2 is not blocked on anything further.
- **New since the original unsplit plan:** the OpenCode-toolchain-install step
  (both jobs) — not in the original 9-task plan, added because PR #232's review
  correctly flagged it as a real gap (opencode fix agent would fail with exit 127
  without it). Mirrors the `implement` job's own existing conditional install
  step exactly, same trigger shape (`AGENT: opencode` env, `ensure-toolchain.sh`).
- **Execution path constraint carried into Global Constraints:** this phase
  edits `.github/workflows/agent-implement.yml` extensively — dispatching it via
  `ai-implement` will fail identically to Phase 1's Task 4 (pipeline token lacks
  `workflows` permission). Push with ordinary git credentials instead; confirmed
  working during Phase 1's Task 4 resolution.
- **No placeholders:** every workflow edit shows full before/after content.
- **Name consistency:** `FIX_AGENT`/`FIX_MODEL` (both jobs, forwarded from
  `needs.implement.outputs.agent`/`.model`); `self-fix-iterations-used` (job
  output, both jobs) and `auto-review-self-fix-iterations-used` (workflow
  output) — matches Phase 1's naming exactly.
