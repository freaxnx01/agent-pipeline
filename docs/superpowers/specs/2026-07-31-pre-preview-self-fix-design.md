# Pre-preview self-fix pass — design

**Issue:** [#81](https://github.com/freaxnx01/agent-workflow/issues/81)
**Follow-up to:** ADR-004 (#77, #80, shipped v1.6.0)
**Date:** 2026-07-31

## Context

Pre-preview mode (`pre_preview` job in `.github/workflows/agent-implement.yml`)
reviews a freshly-opened draft PR with `scripts/review-pr.sh` and, on
`approve`, promotes it to ready via `gh pr ready` — no auto-merge, a human
always merges. On any other verdict (`request_changes`, `block`) or a missing
PR, the PR is left draft and `scripts/post-auto-review-block.sh` stamps
`ai:review-blocked` on the originating issue.

ADR-004 explicitly deferred the agent fixing its own findings:

> **Self-fix deferred.** The agent fixing its own findings is out of scope;
> tracked as a follow-up.

This spec covers that follow-up: on a `request_changes` verdict, optionally
let the agent attempt bounded fix→re-review cycles before falling back to the
human-review path.

## Non-goals

- No auto-merge. Self-fix only changes what a human eventually sees (a
  tidier, self-vetted PR); merging is still always manual, consistent with
  ADR-004's no-safety-envelope stance.
- No self-fix on a `block` verdict or a missing PR — those keep today's
  behavior untouched.
- No change to `auto_review` (ADR-002's flow). This is pre-preview only.

## Design

### 1. Inputs & gating

Two new reusable-workflow inputs, siblings of the existing `pre-preview` /
`stub-pre-preview-enabled` pair:

- `self-fix: boolean` (default `false`) — per-repo opt-in.
- `self-fix-max-iterations: number` (default `2`) — hard cap on fix→re-review
  cycles; only read when `self-fix` is `true`.

The self-fix loop runs **only** when the first review's verdict is
`request_changes` and `self-fix: true`. `block` and missing-PR paths are
unchanged — they go straight to the existing block path without attempting a
fix, matching ADR-004's precedent-and-scope tone (fail-safe toward leaving
the PR alone when the agent's own review actively refused it).

### 2. Loop mechanics — `scripts/self-fix-loop.sh` (new)

A new orchestrator script, invoked from a new "Self-fix loop" step in the
`pre_preview` job, positioned between "Run agent review" and "Promote draft
to ready". Contract:

```
Required env:
  PR_NUMBER, REPO, HEAD_SHA        — same as review-pr.sh
  INITIAL_VERDICT                  — verdict from the first review-pr.sh run
  MAX_ITERATIONS                   — self-fix-max-iterations input

Optional env (testability, mirrors review-pr.sh's AGENT_CMD):
  FIX_CMD       — override for the fix invocation. Contract:
                    $FIX_CMD <pr-number> <concerns-json-file>
                  Default resolves to self-fix-pr.sh.
  REVIEW_SCRIPT — override path to review-pr.sh (default: sibling script).
                  Re-review calls reuse review-pr.sh's own env contract
                  unmodified (AGENT, AGENT_CMD, MODEL, ...).

Outputs ($GITHUB_OUTPUT):
  verdict           final verdict after the loop (or INITIAL_VERDICT
                     unchanged if the loop never ran)
  iterations-used    integer, 0 if the loop never ran
  head-sha           final PR head SHA after the loop

Exit code: always 0 — verdict carries the outcome, matching review-pr.sh.
```

Loop body, up to `MAX_ITERATIONS` times:

1. Run `FIX_CMD` — the agent edits the PR branch, commits
   `address self-review (iteration N)`, and pushes. One commit per
   iteration (no squashing) — preserves the audit trail of what the agent
   changed and why, and needs no rebase/reset step.
2. Run `REVIEW_SCRIPT` against the new HEAD — a **full** re-review of the
   current diff (not a narrower "were findings resolved" check), reusing
   `review-pr.sh` unmodified. This also catches new issues the fix itself
   introduced, not just whether the prior findings were addressed.
3. `approve` → stop, loop succeeded.
   `block` → stop, loop gives up (the agent's own re-review actively
   refused; further attempts are not spent).
   `request_changes` → continue to the next iteration (if any remain).

If the cap is reached without `approve`, the loop ends with the last
verdict (`request_changes` or `block`) and `iterations-used == MAX_ITERATIONS`.

### 3. Fix invocation — `scripts/self-fix-pr.sh` (new)

`self-fix-loop.sh`'s default `FIX_CMD`. Unlike `review-pr.sh` (read-only,
headless `--print`, emits JSON), this script needs the agent to edit files
and push a commit — a full agentic session, following the same pattern the
`implement` job already uses to write the PR in the first place:

```
Required env:
  PR_NUMBER, REPO
  CONCERNS_FILE   — the validated review JSON from the prior review-pr.sh
                    run (its concerns[] array becomes the fix prompt)

Steps:
  1. Checkout the PR's head branch (contents: write, already granted to
     the pre_preview job).
  2. Run the agent agentically (Edit, Write, Read, Glob, Grep, Bash allowed
     — same tool allowlist as the implement job) against a fix-prompt
     template built from CONCERNS_FILE.
  3. Commit "address self-review (iteration N)" and push to the PR branch.

Exit code: non-zero on any failure (checkout, agent crash, push rejected).
self-fix-loop.sh treats a non-zero FIX_CMD exit as an immediate loop abort
(verdict stays at the last known value, iterations-used reflects attempts
made) — it does not call REVIEW_SCRIPT for a fix that never landed.
```

Model: reuses the existing `review-model` input — same agent/model
configuration as the review step. No separate `self-fix-model` input.

### 4. Terminal handling

**Promote** (`gh pr ready`): unchanged step, now gated on the *final*
verdict — the loop's output if it ran, the first-pass verdict otherwise —
being `approve`. Uses the final `head-sha`/PR state (post-fix, if fixes
landed).

**Block** (`post-auto-review-block.sh`): two new optional env vars,
`SELF_FIX_ITERATIONS` (iterations actually used, default unset/0) and
`SELF_FIX_MAX` (the configured cap). In the existing
`VERDICT != approve` branch:

- `SELF_FIX_ITERATIONS` unset or `0` → unchanged reason string
  (`"agent review verdict: $VERDICT"`) — byte-identical to today for
  self-fix-off and initial-`block` paths.
- `SELF_FIX_ITERATIONS > 0` → `"self-fix exhausted after
  $SELF_FIX_ITERATIONS/$SELF_FIX_MAX iteration(s) — last verdict: $VERDICT"`
  — tells the human reviewer the agent already tried and failed N times,
  not just that it disagreed once.

All other branches (self-mod guard, PR not found, envelope failure) are
unaffected — pre-preview has no self-mod guard or envelope check to begin
with (ADR-004), so only the `VERDICT != approve` branch is touched.

## Testing

**Layer 1** (`tests/fixtures/`, mocked `REVIEW_SCRIPT` / `FIX_CMD`):

- fix → approve within cap (loop stops early, `iterations-used < max`)
- cap exhausted without approve (`iterations-used == max`, final verdict
  `request_changes`)
- fix → block on re-review (loop stops immediately, doesn't burn remaining
  iterations)
- first verdict already `approve` (loop never invoked)
- first verdict `block` (loop never invoked)
- `FIX_CMD` itself fails/crashes (loop aborts, verdict stays at last known
  value)

**Layer 2** (`.github/workflows/agent-implement.test.yml`, `act`): extend the
existing `call-pre-preview-*` matrix with `self-fix: true` scenarios driving
a *sequence* of `stub-review-verdict` values (`request_changes` then
`approve`, and `request_changes` × N with no eventual approve) to assert
`ready-attempted` / `merge-attempted` end-to-end, mirroring
`verify-pre-preview-approve` / `verify-pre-preview-block`.

**Docs:** `docs/DECISIONS.md` gets an ADR-004 addendum marking self-fix as
delivered (not a new ADR — it's the deferred item ADR-004 already named).
`docs/CONSUMER-SETUP.md` gains the two new inputs.

## Open items for the implementation plan

- Exact fix-prompt template content (new `scripts/lib/self-fix-prompt.md`,
  parallel to `scripts/lib/review-prompt.md`).
- Whether `self-fix-loop.sh` needs its own `MAX_DIFF_BYTES`-style guard, or
  inherits `review-pr.sh`'s per-re-review.
- Exact `stub-*` wiring needed in `agent-implement.yml` for Layer 2 to drive
  a multi-verdict sequence through one workflow run (today's stub is a
  single static `stub-review-verdict` input).
