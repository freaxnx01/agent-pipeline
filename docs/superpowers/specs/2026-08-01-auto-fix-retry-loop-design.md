# Auto-fix retry loop — design

**Issue:** [#193](https://github.com/freaxnx01/agent-workflow/issues/193)
**Supersedes:** [#81](https://github.com/freaxnx01/agent-workflow/issues/81) (spec/plan merged in #218, not yet implemented — close #81 as superseded once this ships)
**Relates to:** ADR-002 (auto-review/auto-merge envelope), ADR-004 (pre-preview mode)
**Date:** 2026-08-01

## Context

`pre_preview` (ADR-004) and `auto_review` (ADR-002) both call `scripts/review-pr.sh`
against a freshly-opened draft PR. On a non-`approve` verdict, both fall through to
`scripts/post-auto-review-block.sh`, which stamps `ai:review-blocked` on the issue
and leaves the PR draft. **Nothing further happens today** — a human has to notice
the label and either fix it themselves or manually relay the PR to `@copilot` from a
CLI session.

That manual relay was tried once for real (`game-tschau-sepp#9` / PR #12) and did an
incomplete job: `@copilot` fixed 2 of 3 findings and missed the actual root-cause
bug. `@copilot` was never the right tool for this — it has no access to the issue's
original context or implementation plan, and it isn't the agent that wrote the code.
This spec closes the gap properly: **dispatch whichever agent/model actually
implemented the issue** (per `classify-agent.sh`/`classify-task.sh`) to fix its own
findings, bounded, before falling back to human review.

Issue #81 designed a narrower version of this (self-fix, `pre_preview` only,
hardcoded to a Claude fix wrapper) as ADR-004's explicitly-deferred follow-up. Its
spec and implementation plan are merged (#218) but **not yet implemented** — no
`self-fix-loop.sh`/`self-fix-pr.sh` exist in the repo yet. This spec generalizes
that design rather than building it twice: same loop mechanics, but routed to the
original implementer's agent (Claude or OpenCode) and covering both `pre_preview`
and `auto_review`. #81 should be closed as superseded once this ships.

## Non-goals

- **No cross-provider review-agent selection.** The review step's agent choice
  (`AGENT: claude`, `review-model` input) is unchanged and unaffected by this spec.
  Running review on a different provider than the implementer is a real idea (raised
  in #193's discussion) but orthogonal to fix-pass routing — tracked as a separate
  follow-up issue, not part of this design.
- **No change to what `approve` means.** `auto_review`'s merge envelope
  (self-mod guard, allowlist, required checks — ADR-002) is still evaluated on
  the final HEAD before auto-merge, self-fix or not. `pre_preview` still never
  auto-merges (ADR-004).
- **No new PR.** Fixes land as commits on the *existing* PR branch — number and
  review history are preserved.
- **No self-fix on a `block` verdict or a missing PR.** Those are unchanged: the
  agent's own review actively refused, or there's nothing to fix — go straight to
  the block path.

## Design

### 1. Inputs & gating

Two new reusable-workflow inputs:

- `self-fix: boolean` (default `false`) — per-repo opt-in. When `false`, both
  `auto_review` and `pre_preview` behave exactly as today.
- `self-fix-max-iterations: number` (default `2`) — hard cap on fix→re-review
  cycles; only read when `self-fix: true`.

A new `fix_retry` job runs only when: `self-fix: true`, exactly one of
`auto_review`/`pre_preview` ran (they're mutually exclusive via the existing
`implement` job gate), and that job's verdict was `request_changes`. `approve`
(nothing to fix) and `block` (the agent already refused) never reach `fix_retry`.

### 2. Persisting "who implemented this" across jobs

`auto_review`/`pre_preview`/`fix_retry` each run on a **separate runner VM** from
`implement` and from each other — nothing on a prior job's local filesystem is
visible to the next. Two new pieces of cross-job state, both passed as ordinary
`$GITHUB_OUTPUT` values (no artifact upload/download — this workflow's existing
pattern for everything except diagnostic dumps):

**`implement` job gains two new outputs:**

- `agent` — `${{ steps.classify_agent.outputs.agent }}` (`claude` | `opencode`)
- `model` — `${{ steps.triage.outputs.model }}`

**`auto_review`/`pre_preview` each gain three new outputs** (alongside their
existing `merge-attempted`/`ready-attempted`):

- `verdict` — `${{ steps.verdict.outputs.value }}`
- `pr-number` — `${{ steps.find_pr.outputs.pr-number }}`
- `head-ref` — `${{ steps.find_pr.outputs.head-ref }}` (new — see below)
- `concerns-json` — the review's validated JSON content itself (verdict + summary +
  concerns array), read from `steps.review.outputs.summary-file` and emitted as a
  job output string. Concerns payloads are small (a handful of findings, not a
  diff), well within `GITHUB_OUTPUT`'s per-line size limits.

**`scripts/find-pipeline-pr.sh` gains a `head-ref` output** (the PR's branch name,
alongside the existing `pr-number`/`head-sha`/`found`) — `fix_retry` needs it to
check out the branch fresh on its own runner. This is exactly #81's Task 1,
unchanged.

### 3. Fix-agent resolution

`fix_retry` resolves which agent to dispatch from `needs.implement.outputs.agent`,
**not** a hardcoded choice:

- `agent == claude` → `scripts/lib/agent-cmd-claude-fix.sh` (from #81's design,
  unchanged): `claude --print --allowedTools 'Edit,Write,Read,Glob,Grep,MultiEdit,Bash'`.
- `agent == opencode` → new `scripts/lib/agent-cmd-opencode-fix.sh`, mirroring the
  `implement` job's `Run OpenCode` step (`opencode run --model <model> --format json`)
  but operating on the already-checked-out branch instead of a fresh clone, and
  allowing file edits directly rather than emitting a result JSON. Without this
  wrapper, self-fix would silently only work for Claude-implemented issues —
  undermining the issue's own point that the fix must come from the original
  implementer, not a substitute.

`needs.implement.outputs.model` is passed through as `MODEL` to whichever wrapper
runs, so the fix uses the same model that did the implementation (consistent with
#81's precedent of reusing the implementation-time configuration rather than adding
a separate `self-fix-model` input).

### 4. Loop mechanics — `scripts/self-fix-loop.sh` / `scripts/self-fix-pr.sh`

Unchanged from #81's design in shape, generalized in one place. `self-fix-loop.sh`'s
contract, env, and outputs are exactly as specified in #81's spec (see
`docs/superpowers/specs/2026-07-31-pre-preview-self-fix-design.md` §2) — loop up to
`MAX_ITERATIONS`: run `FIX_CMD`, commit `address self-review (iteration N)`, push,
re-review the new HEAD with `review-pr.sh` unmodified, stop on `approve`/`block`,
continue on `request_changes`.

The one change is in `self-fix-pr.sh` (§3 of #81's spec): instead of a single
hardcoded `FIX_AGENT_CMD` default, it resolves the wrapper from an `AGENT` env var
(`claude` | `opencode`) the same way `review-pr.sh` already does — `fix_retry`
passes `AGENT="${{ needs.implement.outputs.agent }}"` and `MODEL="${{
needs.implement.outputs.model }}"`.

### 5. `fix_retry` job — orchestration in `agent-implement.yml`

```yaml
fix_retry:
  needs: [implement, auto_review, pre_preview]
  if: |
    inputs.self-fix
    && (
      (needs.auto_review.result == 'success' && needs.auto_review.outputs.verdict == 'request_changes')
      || (needs.pre_preview.result == 'success' && needs.pre_preview.outputs.verdict == 'request_changes')
    )
```

Steps: checkout consumer repo + agent-workflow scripts (same pattern as the other
jobs) → checkout `head-ref` → write `concerns-json` back to a local file → run
`self-fix-loop.sh` with `AGENT`/`MODEL` from `needs.implement.outputs` and
`MAX_ITERATIONS` from `inputs.self-fix-max-iterations` → on final `verdict ==
approve`: promote (`gh pr ready`), and if the triggering job was `auto_review`, also
re-run `check-merge-envelope.sh` against the final HEAD before `gh pr merge --auto
--squash` (self-fix must not bypass ADR-002's gates) → otherwise:
`post-auto-review-block.sh` with the new `SELF_FIX_ITERATIONS`/`SELF_FIX_MAX` env
(§6) and `MODE` set to whichever of `auto-review`/`pre-preview` triggered it.

A `source` field (`auto_review` vs `pre_preview`) is threaded through as a step
output early in the job (`needs.auto_review.result == 'success' && 'auto-review' ||
'pre-preview'`) so the terminal steps don't repeat the `if:` branching twice.

### 6. Terminal handling — `post-auto-review-block.sh`

Same two new optional env vars as #81's spec (`SELF_FIX_ITERATIONS`,
`SELF_FIX_MAX`), same wording, but now reachable from **either** `MODE` — the
script's reason-selection was already `MODE`-agnostic (`pre-preview` only changes
the comment prefix), so this generalizes with no structural change:

- `SELF_FIX_ITERATIONS` unset/`0` → unchanged wording (byte-identical to today for
  self-fix-off runs and direct `block`/missing-PR paths, which never go through
  `fix_retry`).
- `SELF_FIX_ITERATIONS > 0` → `"self-fix exhausted after $SELF_FIX_ITERATIONS/
  $SELF_FIX_MAX iteration(s) — last verdict: $VERDICT"`.

## Testing

**Layer 1** (`tests/fixtures/`, mocked `FIX_CMD`/`REVIEW_SCRIPT`): all six cases
from #81's spec, plus:

- `self-fix-pr.sh` resolves `agent-cmd-claude-fix.sh` when `AGENT=claude` and
  `agent-cmd-opencode-fix.sh` when `AGENT=opencode` (mocked wrapper paths).
- `find-pipeline-pr.sh` emits `head-ref` (unchanged from #81's Task 1).
- `post-auto-review-block.sh` self-fix-exhausted wording under **both**
  `MODE=auto-review` and `MODE=pre-preview`.

**Layer 2** (`agent-implement.test.yml`, `act`): extend both the
`call-pre-preview-*` and `call-auto-review-*` matrices with `self-fix: true`
scenarios, driving a *sequence* of verdicts via a `stub-self-fix-verdict-sequence`
input (mirrors #81's stub design) to assert `ready-attempted`/`merge-attempted`/
`self-fix-iterations-used` end-to-end for both modes, and for both `agent: claude`
and `agent: opencode` triage outcomes.

**Docs:**

- New `docs/adr/ADR-009-auto-fix-retry-loop.md` (or an entry in `docs/DECISIONS.md`
  following existing numbering — next is ADR-009) documenting the decision: fix pass
  is dispatched to the original implementer's agent/model, loops bounded, no
  auto-merge bypass. References and formally supersedes the self-fix portion of
  ADR-004's deferred item.
- `docs/CONSUMER-SETUP.md` gains `self-fix`/`self-fix-max-iterations`.
- Issue #81 gets a closing comment pointing at this issue/PR once shipped.

## Open items for the implementation plan

- Exact `agent-cmd-opencode-fix.sh` invocation shape — needs verification against
  the `opencode` CLI's behavior when editing files in an already-checked-out
  directory rather than emitting `--format json` to stdout (the `implement` job's
  OpenCode path is itself flagged EXPERIMENTAL/not fully verified end-to-end — this
  reuses that same unverified surface, not new risk, but worth calling out).
- Exact GitHub Actions `if:`/`needs.*.result` syntax needs verification against a
  real `act` run — mutually-exclusive-jobs-feeding-a-shared-downstream-job is a
  slightly less common pattern than this workflow's existing single-predecessor
  `needs:` chains.
- Whether `concerns-json` as a raw `$GITHUB_OUTPUT` string needs escaping/encoding
  (e.g. base64) given it's JSON containing arbitrary review prose — GitHub Actions'
  multiline-output delimiter syntax (`<<EOF`) handles embedded newlines, but the
  exact quoting needs confirming against a real review payload during
  implementation.
- Fix-prompt template content (new `scripts/lib/self-fix-prompt.md`, parallel to
  #81's design) — reused unchanged from #81's spec, just confirm during
  implementation that `{{HEAD_SHA}}`/`{{REPO}}`/`{{PR_NUMBER}}`/`{{CONCERNS}}`
  placeholders still fit once `AGENT`-specific wording (if any) is added.
