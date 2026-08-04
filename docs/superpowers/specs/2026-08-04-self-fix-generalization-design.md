# Self-fix generalization — auto_review + agent routing — design

**Issue:** [#193](https://github.com/freaxnx01/agent-workflow/issues/193)
**Builds on:** [#81](https://github.com/freaxnx01/agent-workflow/issues/81) / PR #221 (merged 2026-08-01), which shipped a `pre_preview`-only, Claude-only self-fix pass
**Supersedes:** `docs/superpowers/specs/2026-08-01-auto-fix-retry-loop-design.md` and its implementation plan — both were authored roughly concurrently with #221's merge and describe a separate `fix_retry` job architecture that does not match what actually shipped. This spec is written against the real, current `pre_preview` self-fix implementation.
**Relates to:** ADR-002 (auto-review/auto-merge envelope), ADR-004 (pre-preview mode, self-fix addendum)
**Date:** 2026-08-04

## Context

Issue #81's self-fix pass merged via PR #221 on 2026-08-01: on a `request_changes`
verdict from `pre_preview`, a self-fix step (embedded directly in the `pre_preview`
job, not a separate job) runs up to `self-fix-max-iterations` fix→re-review cycles
via `scripts/self-fix-loop.sh` / `scripts/self-fix-pr.sh`, before falling back to
`post-auto-review-block.sh`'s block path. It works, is tested (Layer-1 + Layer-2),
and is documented (ADR-004 addendum).

It has two gaps against issue #193's actual ask:

1. **`auto_review` (ADR-002) has no self-fix wiring at all.** Only `pre_preview` got
   it.
2. **The fix agent is hardcoded to Claude.** `pre_preview`'s self-fix step sets
   `AGENT: claude` / `FIX_AGENT_CMD: .../agent-cmd-claude-fix.sh` as literal
   strings — regardless of which agent (Claude or OpenCode) actually implemented
   the issue. #193's original motivation (`game-tschau-sepp#9` / PR #12 — a
   different agent, `@copilot`, did an incomplete fix job because it lacked the
   original implementer's context) applies just as much to a hardcoded Claude
   fallback when OpenCode implemented the issue.

A prior planning pass (2026-08-01) tried to close both gaps by extracting a new
shared `fix_retry` job downstream of both `auto_review`/`pre_preview`. That plan
was written without knowledge that #221 (a different, concurrent PR) had just
merged a *different* shape — self-fix as a step embedded in `pre_preview` itself,
not a job. This spec instead generalizes the shape that actually exists: mirror
the embedded self-fix step into `auto_review`, and make the agent/model routing
dynamic in both.

## Non-goals

Unchanged from the 2026-08-01 spec:

- **No cross-provider review-agent selection.** The review step's own agent choice
  (`AGENT: claude`, `review-model` input) is unaffected — only the *fix* call's
  agent/model become dynamic. Review always runs as Claude, regardless of who
  implemented or who fixes.
- **No change to what `approve` means.** `auto_review`'s merge envelope
  (self-mod guard, allowlist, required checks — ADR-002) is still evaluated
  against the final HEAD before auto-merge, self-fix or not.
- **No new PR.** Fixes land as commits on the existing PR branch.
- **No self-fix on a `block` verdict or a missing PR** — unchanged.
- **No new job.** Self-fix stays an embedded step per job, matching the shape #221
  already shipped and tested, rather than extracting a shared job.

## Design

### 1. `implement` job exposes `agent`/`model`

`steps.classify_agent.outputs.agent` and `steps.triage.outputs.model` are computed
today but only consumed within the `implement` job itself. Add them as job outputs
so `auto_review`/`pre_preview` can read `needs.implement.outputs.agent` /
`needs.implement.outputs.model`.

Both `classify_agent`/`triage` steps are skipped entirely under `stub-claude: true`
(their `if:` conditions require `!inputs.stub-claude`), so the output expressions
fall back to the raw `inputs.agent` / `inputs.default-model` in that mode — this
lets Layer-2 act tests drive the resolved agent through the existing `agent` input
without a new stub, same precedent the 2026-08-01 spec used.

### 2. Fix-agent resolution: `self-fix-pr.sh` gains `AGENT` routing

`scripts/self-fix-pr.sh` today hardcodes its default `FIX_AGENT_CMD` to
`lib/agent-cmd-claude-fix.sh`. Add an `AGENT` env var (`claude` | `opencode`,
default `claude`) that resolves the default:

- `claude` → `lib/agent-cmd-claude-fix.sh` (existing, unchanged)
- `opencode` → `lib/agent-cmd-opencode-fix.sh` (new — see below)

An explicit `FIX_AGENT_CMD` still overrides AGENT-based resolution entirely (test
seam, already used by the workflow steps that reference the wrapper by full path
today — that continues to work, but the workflow steps will switch to `AGENT`-based
resolution instead, see §4).

### 3. `scripts/lib/agent-cmd-opencode-fix.sh` (new)

Mirrors `agent-cmd-claude-fix.sh`'s contract (`FIX_AGENT_CMD <prompt-file>`, edits
files directly in CWD, optional `MODEL` env) but invokes OpenCode instead of
Claude. Matches the `implement` job's own "Run OpenCode" step's invocation shape
(`.github/workflows/agent-implement.yml` lines ~519-585) exactly, adapted for
agentic file-editing instead of `--format json` result-parsing:

- `opencode run --model <model> --format json --print-logs -- "$(cat "$prompt")"`
- Model prefix rule identical to the implement job's: prepend `openrouter/` unless
  the model id already carries a provider slug.
- `OPENROUTER_API_KEY` read from env, never logged.

Unlike the read-only review wrapper precedent, this one lets the agent edit files
directly in the CWD — the caller (`self-fix-pr.sh`) has already checked out the PR
branch and commits/pushes afterward, same division of labor as
`agent-cmd-claude-fix.sh`.

**EXPERIMENTAL** (per #58, same caveat as `implement`'s own OpenCode path): the
OpenRouter auth mechanism and `--format json` event shape are not independently
re-verified here — this reuses the same unverified surface, not new risk.

### 4. `self-fix-loop.sh` gains `FIX_AGENT`/`FIX_MODEL`

`self-fix-loop.sh` has no agent-routing concept today — it invokes `$FIX_CMD`
(`self-fix-pr.sh`) with `ITERATION`/`REPO`/`HEAD_REF` env, and separately invokes
`$REVIEW_SCRIPT` (`review-pr.sh`) reusing its *own* `AGENT`/`AGENT_CMD`/`MODEL` env
unmodified (inherited from the calling job step, which is `claude`/`review-model`
for both today).

Add `FIX_AGENT` (default `claude`) / `FIX_MODEL` (default empty), forwarded to the
`$FIX_CMD` call **only**, as `AGENT`/`MODEL` on that call's env — distinct from the
script's own `AGENT`/`MODEL`, which stay whatever the calling job step set for
re-review. Without this separation, setting the job step's `AGENT: opencode` for
fix-routing would leak into the `$REVIEW_SCRIPT` call too and mislabel which agent
actually reviewed (review must always be Claude — see Non-goals).

### 5. `pre_preview`'s self-fix step: hardcoded → dynamic

Today's step (`.github/workflows/agent-implement.yml`, "Self-fix loop
(pre-preview optional self-fix pass)") sets:

```yaml
AGENT: claude
AGENT_CMD: .../agent-cmd-claude.sh
FIX_AGENT_CMD: .../agent-cmd-claude-fix.sh
MODEL: ${{ inputs.review-model }}
```

Change to:

```yaml
AGENT: claude                          # unchanged — re-review stays Claude
AGENT_CMD: .../agent-cmd-claude.sh     # unchanged
MODEL: ${{ inputs.review-model }}      # unchanged — re-review model
FIX_AGENT: ${{ needs.implement.outputs.agent }}
FIX_MODEL: ${{ needs.implement.outputs.model }}
```

Drop the hardcoded `FIX_AGENT_CMD` — `self-fix-pr.sh`'s new `AGENT`-based
resolution (§2) picks the wrapper. This also changes the fix call's *model* from
`inputs.review-model` to the original implementer's model — matching #193's
explicit intent ("run by the same agent that did the original implementation"),
which today's hardcoded step does not.

### 6. `auto_review` gains the same self-fix block

`auto_review` today goes straight from its verdict-resolution step to
`check-merge-envelope.sh` → promote/merge or block. Insert, between verdict
resolution and the envelope check, the same two steps `pre_preview` has:

- **Self-fix loop** — identical shape to `pre_preview`'s (§5's env block), gated on
  `steps.find_pr.outputs.found == 'true' && steps.verdict.outputs.value ==
  'request_changes' && inputs.self-fix`.
- **Resolve final verdict (post self-fix)** — same pattern: final verdict is the
  self-fix loop's verdict if it ran, else the original verdict; also emits
  `iterations-used`.

Then re-point the existing envelope-check/promote/merge/block steps'
verdict-dependent conditions and `VERDICT` env from `steps.verdict.outputs.value`
to `steps.final.outputs.verdict` — envelope check and promote/merge now evaluate
the **final** (post-self-fix) verdict and HEAD, exactly as `pre_preview` already
does for its own promote/block decision. `check-merge-envelope.sh` itself needs no
change: it re-derives PR/CI state dynamically from the PR at call time, so running
it after self-fix's commits/pushes already reflects the final HEAD.

No block-step guard/race condition is needed here (unlike the 2026-08-01 spec's
Task 8) — self-fix runs synchronously, in-job, before the promote/block decision,
so there's no window where a separate downstream job hasn't run yet.

`post-auto-review-block.sh` already handles `SELF_FIX_ITERATIONS`/`SELF_FIX_MAX`
generically across both `MODE=auto-review` and `MODE=pre-preview` (shipped in
#221) — no script change needed; `auto_review`'s existing block step just needs
`SELF_FIX_ITERATIONS`/`SELF_FIX_MAX` env added, same as `pre_preview`'s already has.

### 7. New workflow output

Add `auto-review-self-fix-iterations-used`, mirroring the existing
`pre-preview-self-fix-iterations-used` (`value: ${{ jobs.auto_review.outputs.self-fix-iterations-used }}`,
sourced from the new `final` step's `iterations-used` output, same as `pre_preview`).

## Data flow summary

```
implement job
  └─ agent, model  (NEW outputs)
       │
       ▼
auto_review / pre_preview job (independent, mutually exclusive)
  find_pr → review → verdict
       │
       ▼ (if self-fix && verdict == request_changes)
  self_fix step:
    FIX_AGENT=needs.implement.outputs.agent   → routes self-fix-pr.sh's wrapper
    FIX_MODEL=needs.implement.outputs.model   → fix call's model
    AGENT=claude, MODEL=review-model          → unchanged, re-review call only
       │
       ▼
  final step: verdict = self_fix.verdict || first verdict
       │
       ▼
  (auto_review only) check-merge-envelope.sh, using final verdict/HEAD
       │
       ▼
  promote/merge (final verdict == approve) or post-auto-review-block.sh (else)
```

## Testing strategy

- **Layer-1 (`tests/run-script-tests.sh`):**
  - `self-fix-pr.sh`: new assertions for `AGENT=opencode` resolving
    `agent-cmd-opencode-fix.sh` specifically (mock-based, mirroring the existing
    `AGENT=claude` coverage that already exists for the Claude path), plus the
    `FIX_AGENT_CMD` override still taking precedence over `AGENT`.
  - `self-fix-loop.sh`: new assertions that `FIX_AGENT`/`FIX_MODEL` reach the
    `FIX_CMD` mock as `AGENT`/`MODEL`, while the loop's own `AGENT`/`MODEL` (used
    for the `REVIEW_SCRIPT` mock call) stay at whatever the test sets them to —
    proving the two never collide.
  - `agent-cmd-opencode-fix.sh`: no independent fixture test, same precedent as
    `agent-cmd-claude-fix.sh` (lint + exercised only via the scripts that call it).
- **Layer-2 (`act`, `.github/workflows/agent-implement.test.yml`):** two new
  scenarios mirroring the existing `pre-preview-self-fix-*` ones, but for
  `auto_review`: fix→approve within cap (asserts merge-attempted after N
  iterations), and cap-exhausted (asserts no merge). Both driven via
  `stub-self-fix-verdict-sequence`, one with `agent: opencode` to prove
  `FIX_AGENT` routing is wired at the workflow level (per-agent wrapper behavior
  itself stays Layer-1-tested).
- **Docs:** update `docs/DECISIONS.md`'s ADR-004 self-fix addendum (or add a new
  ADR-005-equivalent addendum) to note `auto_review` coverage and agent-dynamic
  routing; update `docs/CONSUMER-SETUP.md`'s self-fix description accordingly.
  Close #193's acceptance criteria; #81 is already closed (superseded by #221).

## Open questions

None — the architecture, agent-routing mechanism, and test shape all follow
directly from patterns #221 already shipped and validated in production-shaped
Layer-1/Layer-2 tests. The only genuinely new code is: two script env-var
additions (`AGENT` on `self-fix-pr.sh`, `FIX_AGENT`/`FIX_MODEL` on
`self-fix-loop.sh`), one new wrapper script, two new job outputs, and one
mirrored workflow step block.
