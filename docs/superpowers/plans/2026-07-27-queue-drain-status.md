# Queue drain status — milestone `next` (#177, #173, #178, #174, #175)

**Phase:** ✅ **COMPLETE.** All five issues are merged and closed; the loop is stopped.
**Started:** 2026-07-27 · **Finished:** 2026-07-28 09:43
**Resume artifact for:** `/handoff` → `/clear` → `/pickup`

> Nothing here is in flight. This document is now a record plus a short list of
> parked follow-ups. Read "What's left" and stop — do not restart the drain loop.

---

## Final state

| # | State | PR | Merge commit |
|---|---|---|---|
| **177** | ✅ closed | #180 | `62ca19e` — conditional implementation contract |
| **173** | ✅ closed | #181 | `29a5b98` — `roadmap` filter in `/gh:issues` + `/fj:issues` |
| **178** | ✅ closed | #182 | `5b89ca2` — `/milestone triage` |
| **174** | ✅ closed | #183 | `91206d7` — `/parked` gains `unpark` / `repark` / `review` |
| **175** | ✅ closed | #184 | `b93340c` — new `/roadmap` command |
| **179** | ⚪ still parked | — | epics — needs its own brainstorm session, never part of this queue |

Follow-on work merged in the same session:

| Commit | What |
|---|---|
| `0b81dfd` | Corrected the parked-triage plan's broken `tea api -X PATCH` label edit |
| `afc2d40` | Fixed a false-passing verification check in the roadmap plan (Task 4) |
| `c7ea4da` | #185 — `AGENT-NOTES.md`: never direct-push, always PR |
| `279cc7f` | #186 — synced AI instructions from `ai-instructions@218874d` |
| `218874d` | `freaxnx01/ai-instructions` #22 — removed the direct-push exception at source |

## What's left

Nothing blocking. Three observations were raised during the run and deliberately
**not** acted on — each needs its own decision, none is urgent:

1. **`CHANGELOG.md` `[Unreleased]` duplicates the #172 entries** that also appear in
   the `[1.11.0]` section — a git-cliff release-cut artifact on `main`. Two `#172`
   refs currently sit inside `[Unreleased]`. Also note `[Unreleased]` now carries
   #174, #175 and #178 with no release cut for them yet.

2. **The `sync-ai-instructions` plugin fetches four `ui-*` skill files that 404.**
   Upstream `.ai/skills/` holds only `commit.md` and `push.md`; the UI commands ship
   from the global operator console and are deliberately not synced per-project. The
   plugin's Step 2 file list is stale. It lives in the plugin cache
   (`freax-agent-skills/sync-ai-instructions/0.2.0`), so it must be fixed at its
   source — editing the cached copy would be overwritten on update.

3. **A new PowerShell 5.1 "Scripting" section** arrived via #186 and is now in every
   agent's context here. Inert for a bash/Actions repo, but it costs context budget;
   worth deciding whether to trim it upstream or leave it.

Pre-existing and untouched all session: open PRs **#170** and **#115**, plus stale
local branches `chore/rename-to-agent-workflow`, `enrich/114-qwen3-27b-benchmark`,
`worktree-div`.

## Per-issue specs and plans

Each issue body links its own spec + plan by pinned SHA. On disk:

- `docs/superpowers/specs/2026-07-27-conditional-implementation-contract-design.md` · `docs/superpowers/plans/2026-07-27-conditional-implementation-contract.md` (#177)
- `docs/superpowers/specs/2026-07-27-roadmap-label-filter-design.md` · `docs/superpowers/plans/2026-07-27-roadmap-label-filter.md` (#173)
- `docs/superpowers/specs/2026-07-27-milestone-triage-design.md` · `docs/superpowers/plans/2026-07-27-milestone-triage.md` (#178)
- `docs/superpowers/specs/2026-07-27-parked-triage-design.md` · `docs/superpowers/plans/2026-07-27-parked-triage.md` (#174) — **corrected** by `0b81dfd`
- `docs/superpowers/specs/2026-07-27-roadmap-command-design.md` · `docs/superpowers/plans/2026-07-27-roadmap-command.md` (#175) — **corrected** by `afc2d40`

---

## Lessons worth keeping

These cost real time to learn and generalise beyond this queue.

### Plan verification blocks are greps, and greps pass on broken logic

Every per-task "verification" in these plans is a `grep -Fq` string-presence check.
It proves a string was written, never that the command works. **Two defects reached
a fully green verification block:**

- **PR #183** — `commands/fj/parked.md` justified a hand-rolled `tea api -X PATCH`
  of the labels array with *"`tea` has no remove-label flag"*. False: `tea issues
  edit` has `--remove-labels`. The PATCH would also have silently no-opped, because
  Forgejo's `PATCH /repos/{owner}/{repo}/issues/{index}` has no `labels` field —
  label replacement lives on `PUT .../issues/{index}/labels`.
- **PR #184** — `commands/fj/roadmap.md` used `split("\\n")` inside a
  single-quoted shell string, so Python received the two-character string `\n` and
  never truncated multi-line comments. The identical grep passed.

Both were Forgejo/`tea` shell one-liners — the least-exercised path, because
`tea logins list` is empty on this machine so nothing can be run end-to-end.

**So, on top of the plan's own blocks:** verify CLI flags against `--help` on the
installed binary (including flag order vs the declared USAGE line); check the API
endpoint actually accepts the field being sent; and execute embedded python/jq
one-liners on realistic input — multi-line bodies, zero matches, several matches.
Diffing a new file against its already-reviewed sibling (`fj/roadmap.md` vs
`fj/parked.md`) is the cheapest tell: divergence in a shared idiom is the bug.

### A verification that cannot fail is not a verification

The roadmap plan's Task 4 checked **both** `issues.md` files against the gh-worded
placeholder, but `commands/fj/issues.md` never contained that string — so it
reported "retired OK" for Forgejo before any edit existed. Fixed in `afc2d40` by
giving each file its own expected string plus a wording-independent backstop. When
writing a check, run it against the **pre-change** tree and confirm it fails.

### Copilot's completion signal

Only a `copilot_work_finished` timeline event means done — the draft flag and
`[WIP]` title both lie, in both directions. When a PR has had several cycles,
compare the **count**, not mere presence. A head move alone is not new agent work:
an "Update branch" merge of `main` moves the head with no Copilot cycle, so check
the merge commit's parents and diff the PR's own files between heads — byte-identical
means the earlier review still holds. Copilot-triggered CI sits at
`conclusion=action_required` and needs `gh run rerun <run-id>`; the REST `/approve`
endpoint 403s (it is fork-only).

### Never push to `main`

Established this session and now enforced in the instructions themselves
(`ai-instructions` #22, `AGENT-NOTES.md` via #185, synced via #186). Because
`enforce_admins` is false, a direct push **lands first** and the required check
reports afterwards — a postmortem, not a gate. It also leaves open PRs' branches
stale: `0b81dfd` did exactly that to PR #184, costing a `gh pr update-branch` plus a
full CI re-run. One correction worth recording: CI *does* run on bypassed commits
(both went green) — the problem is the ordering, not that checks are skipped.

### Operational

All GitHub writes need `direnv exec /home/admin/repos/github/freaxnx01 gh …` — the
ambient login is read-only and fails writes with a bare 404. Monitors do not survive
`/loop` re-invocations; `TaskList` first and re-arm if empty. Never take a claimed
merge at face value — verify with `gh pr view <n> --json state,mergedAt,mergeCommit`.
