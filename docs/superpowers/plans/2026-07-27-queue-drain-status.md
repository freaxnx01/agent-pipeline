# Queue drain status — milestone `next` (#177, #173, #178, #174, #175)

**Phase:** executing five enriched issues one at a time via Copilot dispatch.
**Date:** 2026-07-27, 18:05
**Resume artifact for:** `/handoff` → `/clear` → `/pickup`

---

## Where things stand

| # | State | PR | Notes |
|---|---|---|---|
| **177** | ✅ closed | #180 merged `62ca19e` | Conditional implementation contract |
| **173** | ✅ closed | #181 merged `29a5b98` | `roadmap` filter in `/gh:issues` + `/fj:issues` |
| **178** | 🟡 in flight | **#182 — green, awaiting the user's merge** | `/milestone triage` |
| **174** | ⏳ queued | — | `/parked` gains `unpark` / `repark` / `review` |
| **175** | ⏳ queued **last** | — | new `/roadmap` command |
| **179** | ⚪ parked | — | epics — needs its own brainstorm session, not in this queue |

**Immediate next step:** the user merges **PR #182**. Once #178 closes, dispatch
**#174**. Then **#175 last**.

**Why #175 is last:** its Task 4 retires the placeholder sentence *"find them with
`gh issue list --label roadmap`"* that #173 deliberately introduced. That task opens
with a precondition check reporting SKIP if #173 isn't merged. #173 *is* merged now,
so the gate has cleared — but #175 still goes last so its diff doesn't race #174.

## Per-issue specs and plans

Each issue body links its own spec + plan by pinned SHA. On disk:

- `docs/superpowers/specs/2026-07-27-conditional-implementation-contract-design.md` · `docs/superpowers/plans/2026-07-27-conditional-implementation-contract.md` (#177, done)
- `docs/superpowers/specs/2026-07-27-roadmap-label-filter-design.md` · `docs/superpowers/plans/2026-07-27-roadmap-label-filter.md` (#173, done)
- `docs/superpowers/specs/2026-07-27-milestone-triage-design.md` · `docs/superpowers/plans/2026-07-27-milestone-triage.md` (#178, in flight)
- `docs/superpowers/specs/2026-07-27-parked-triage-design.md` · `docs/superpowers/plans/2026-07-27-parked-triage.md` (#174, queued)
- `docs/superpowers/specs/2026-07-27-roadmap-command-design.md` · `docs/superpowers/plans/2026-07-27-roadmap-command.md` (#175, queued)

## The loop contract

One issue in flight at a time — **all five edit `CHANGELOG.md` under
`[Unreleased]`**, so parallel dispatch conflicts by construction. Serializing also
enforces the ordering rules for free.

Each tick does exactly one of:

1. **PR open + Copilot finished + not yet reviewed** → review against the issue's
   ACs, then stop at *"ready for your merge"*. **Never merge.**
2. **PR open + already reviewed** → report what it waits on. Don't dispatch.
3. **Nothing in flight** → dispatch the next issue.
4. **All closed** → report drained, stop the loop.

The user chose the *dispatch + review, they merge* boundary deliberately. Do not
switch to autopilot merging unless they explicitly say so.

## How to review (this is what caught the real bugs)

Grep checks alone were **not** sufficient — they passed a PR that shipped a live
command-substitution bug. Do all three:

1. **Run the plan's per-task verification blocks** against the PR head. Fetch with
   `git fetch origin refs/pull/<n>/head` then `git show <sha>:<path>` into a scratch
   dir — don't touch the working tree.
2. **Read the changed sections in full** for the ACs greps can't cover.
3. **Execute the changed logic against real data.** Extract the PR's own jq/python
   and run it.

Behavioural checks already used, and the ones still pending:

- **#173 (done):** the PR's jq excluded roadmap issue #164 in
  `anim-bossinfo-ch/BI-ArchiveUploader`, and left `agent-workflow` at 26 issues
  before == 26 after, proving it's inert where the label doesn't exist.
- **#178 (done):** the gap query returned 25 rows, excluded all four milestoned
  issues and parked #116, rendered `-` for unlabelled #166, newest-first.
- **#174 (pending):** this repo has exactly **one** parked issue, **#116**, with no
  reason comment → `/parked` must list it with an em-dash. Also check the
  reason-extraction jq on multiple matching comments (most recent, first line only)
  and on none.
- **#175 (pending):** `agent-workflow` has **no** `roadmap` label → list must report
  empty **without creating it**. `BI-ArchiveUploader` has the label with **#164**
  carrying it.

## Operational gotchas — hard-won, don't re-derive

- **Writes need the freaxnx01 token.** The ambient `gh` login is
  `anim-bossinfo-ch`, READ-only here; writes fail with a bare **404**, not a
  permission error. Use
  `direnv exec /home/admin/repos/github/freaxnx01 gh …`. For `git push`, git's
  credential helper reads `GITHUB_TOKEN`, not `GH_TOKEN`:
  `direnv exec … bash -c 'GITHUB_TOKEN="$GH_TOKEN" git push'`.
- **Copilot's completion signal is `copilot_work_finished`** in
  `gh api repos/freaxnx01/agent-workflow/issues/<pr>/timeline`. The **draft flag and
  `[WIP]` title both lie** — #182 flipped its title and grew to +130/−11 while still
  having no finish event.
- **Copilot opens PRs as drafts** and they cannot be merged until
  `gh pr ready <n>` (undo: `--undo`). The user authorized this for #180/#181/#182.
- **Copilot-triggered CI sits at `conclusion=action_required`.** The REST
  `/approve` endpoint returns **403 — fork-PRs only**. The fix that works is
  `gh run rerun <run-id>` under the freaxnx01 token. Confirm the PR touches no
  `.github/` or `scripts/` first, since `pull_request` runs the head branch's YAML.
- **Never take a claimed merge at face value.** Verify with
  `gh pr view <n> --json state,mergedAt`. The user reported "merged" twice while
  #180 was still open (it was a draft), and said "merge" once while #182 was an
  empty `+0/-0` WIP draft — declining and explaining was correct.
- **`~/.claude/commands/gh/` holds stale COPIES from Jul 24**, not symlinks, and has
  no `implementation-contract.md`. So `/gh:assign` still posts the **old
  unconditional TDD contract**. Keep posting the docs-only variant **by hand** until
  the user re-runs `setup/link-commands.sh` (manual verification item 1 of #177).
- **Extracting the contract** (do not retype it):
  split `commands/gh/implementation-contract.md` on `## Docs-only variant`, regex out
  the `--body "…"` string, unescape `` \` `` and `\"`, write to a file, post with
  `--body-file`. Then verify the read-back still contains the literal
  `` `git diff --name-only` `` backticks.
- **Monitors are session-scoped** and die on session end. After resuming, re-arm one
  for whatever is in flight.

## Housekeeping done along the way

- Milestone **`next`** was created (#4) and holds all six issues.
- Stale `needs-enrichment` was removed from **#178**; **#179** keeps it deliberately.
- **#170** and **#115** are pre-existing PRs of the user's, untouched by this work.

## Known follow-ups, captured not acted on

- `commands/gh/enrich.md` lines 26 and 107 unconditionally recommend
  `/gh:implement`, but this repo has **no `.github/workflows/claude.yml`**, so that
  path is dead here. Should be conditional on `claude.yml` existing. **User was
  asked and hasn't answered.**
- `commands/gh/parked.md` has **no self-improving footer**, unlike its `fj`
  counterpart. Pre-existing, out of scope for #174.
- #177's open question — whether the conditional contract belongs in other commands
  (`gh/work.md`, `gh/route.md`, the `fj/*` equivalents) — was deliberately left out
  of scope.
