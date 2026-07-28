# `/parked` triage salvage — status

**Phase:** PR #190 open, green, awaiting the user's merge. One cleanup decision pending.
**Date:** 2026-07-28
**Resume artifact for:** `/handoff` → `/clear` → `/pickup`

---

## What happened

This session picked up the queue-drain plan
(`docs/superpowers/plans/2026-07-27-queue-drain-status.md`), merged **PR #182**
(issue #178), and then implemented **issue #174** (`/parked` triage verbs)
locally via `/gh:work` — worktree, 4 plan tasks, subagent-driven, per-task
reviews, final Opus whole-branch review, one fix wave.

**At `/wt:finish` time the branch could not be merged: issue #174 had already
shipped.** A parallel session landed **PR #183** (`91206d7`) at 08:09 while this
one was implementing — same four files, same feature. Issue #174 is CLOSED.

The local implementation was therefore a duplicate. But its final review — which
*executed* the embedded jq/python instead of grepping — had found six real
defects, and **every one of them was live in the shipped version**. So the branch
was not merged; the findings were re-applied on top of `main` instead. That
salvage is **PR #190**.

## Current state

| Thing | State |
|---|---|
| **PR #190** — the salvage fix | **OPEN, green, MERGEABLE, awaiting the user's merge** |
| Issue #174 | CLOSED (shipped via #183) |
| Issue #178 | CLOSED (PR #182 merged this session, `5b89ca2`) |
| Branch `issue-174-parked-triage` | **duplicate — pending discard decision** |
| Worktree `.worktrees/fix-parked-review` | keep — PR #190 feedback gets fixed here |
| Worktree `.worktrees/issue-174-parked-triage` | duplicate — remove with the branch |
| Branch `docs/handoff-parked-salvage` | this document |

**Immediate next step:** the user merges **PR #190**, then answers the discard
question below.

## PR #190 — what it fixes

Branch `fix/parked-triage-review-findings`, 3 commits off `817b749`, touching only
`commands/gh/parked.md`, `commands/fj/parked.md`, `commands/parked.md`.

- **Router closing line countermanded the new verbs.** `commands/parked.md` said
  *"produce that command's table — nothing else"* — wording that predates the
  verbs and forbade exactly `unpark`'s required `/gh:route` handoff and `review`'s
  interactive walk. Now mirrors `commands/milestone.md`: *"carry out that command."*
- **`comments(last:20)` manufactured a false `—`.** `—` is documented to mean *no
  reason recorded*; with 20, an issue whose last repark predates its 20 newest
  comments rendered `—` anyway. Now `last:100` (~12k of GitHub's 500k node budget).
- **The gh `repark` read-back confirmed from the blind last comment** — an
  unrelated trailing comment was reported back as the recorded reason. Now selects
  the newest `🧊 parked:`-prefixed body, matching what the Forgejo file already did.
- **That read-back crashed** (`jq` exit 5, *"split input and separator must be
  strings"*) **on zero comments** — precisely the case it exists to catch — and
  printed a literal `null` for an empty-string body.
- **The gh `list` reason extraction crashed the same way** on a `"body": null`
  comment.
- **The fj reason extractor raised `AttributeError`** on a null body:
  `c.get("body","")` returns `None`, and `.startswith` then blows up. Now
  `(c.get("body") or "")`.
- **`unpark` inside `review` was undefined** — both forge files now say the route
  handoff defers until the walk completes, with the tally listing unparked numbers.

## The correction worth not re-deriving

An earlier revision of the salvage branch added `?limit=100` to the Forgejo comment
reads, reasoning that Forgejo pages at 30 and the `repark` read-back could confirm
against a stale comment.

**That premise is false.** `GET /repos/{owner}/{repo}/issues/{index}/comments`
declares only `since`/`before` and never calls `utils.GetListOptions` — it is **not
paginated**. (`ListRepoIssueComments` and `ListIssueCommentsAndTimeline` do
paginate; `ListIssueComments` does not.) The parameter was inert and its prose
would have taught the next maintainer something untrue. Both were removed.

Do not re-add pagination to that endpoint.

## Pending decision

The duplicate branch `issue-174-parked-triage` (5 commits, worktree at
`.worktrees/issue-174-parked-triage`) was never merged anywhere. The feature it
implements shipped as #183; its unique value — the fix set — is now in PR #190.
Deleting it needs a force-delete (`git branch -D`), so it awaits the user typing
**`discard`**.

If they say keep, leave both branch and worktree in place.

## Operational gotchas — hard-won, don't re-derive

- **Grep-only review is not sufficient in this repo.** It previously passed a live
  command-substitution bug, and four of the six defects above were invisible to
  string matching. Extract the jq/`python3 -c` and run it against synthetic input:
  zero parked issues · no reason comment · multiple reasons (newest wins, first
  line only) · multi-line reason · zero-comment payload · `"body": null` ·
  empty-string body · an array whose last element is unrelated while a real reason
  sits earlier.
- **`gh` writes work directly here.** The ambient login is `freaxnx01` with `repo`
  scope. The `direnv exec /home/admin/repos/github/freaxnx01 gh …` wrapper recorded
  in the older queue-drain notes refers to a path that **does not exist on this
  machine** — ignore it.
- **Branch protection requires an up-to-date branch.** PR #182 rejected its merge
  with *"head branch is not up to date"*; `gh pr update-branch <n>` fixes it, then
  CI re-runs and must go green again before merging.
- **Every change needs a PR now** — `AGENT-NOTES.md` (#185, `c7ea4da`): *"Never.
  Every change goes through a PR, including docs-only ones."* The vendored
  `.ai/base-instructions.md` still shows the old trivial-edit exception until
  someone re-runs `/sync-ai-instructions`; follow `AGENT-NOTES.md`, not that
  sentence. This is why this document is on its own branch rather than pushed to
  `main`.
- **`.claude/handoff.md` is gitignored** (`.gitignore:24`) and is meant to stay
  local — it is never part of a handoff commit.
- **`.superpowers/` is NOT gitignored.** Agent scratch reports land there; a
  `git add -A` in any worktree would commit them. Stage explicit paths. Worth a
  one-line `.gitignore` entry.
- **`commands/*.md` have no test framework.** `just lint` covers only
  `.github/workflows/`, `scripts/`, and `tests/`. Do not add a test file, fixture,
  or `tests/` entry for them, and do not write a failing test first — issue #174
  says so explicitly. Verification is string-presence checks plus executing the
  embedded snippets.
- **Verify `tea` flags with `tea <subcommand> --help`** before writing them.
  0.14.1 is installed. `tea issues create` takes `--description` not `--body`;
  `tea issues list` takes `--labels` plural; `tea issues edit --remove-labels`
  exists (so `tea api -X PATCH` is unnecessary); `tea api` has no `--jq` — pipe to
  `python3 -c`; always pass `--login git-home`.
- **Forgejo's `labels=` query param is broken** on this instance — filter labels
  client-side, and don't "optimise" it back.

## Known follow-ups, captured not acted on

- `commands/fj/parked.md`'s `tea comment <n> "🧊 parked: <reason>"` omits
  `--login git-home`, unlike every other `tea` call in the file. Pre-existing on
  `main`, noted in PR #190's body, not fixed there.
- `.superpowers/` should be added to `.gitignore`.
- The plan `docs/superpowers/plans/2026-07-27-parked-triage.md` has a Task 1 check
  that greps the literal `comments(last:20)`, which PR #190 changes to `last:100`.
  Left as a historical record on purpose.
- From the older queue-drain notes, still open: `commands/gh/enrich.md` lines 26
  and 107 unconditionally recommend `/gh:implement`, but this repo has no
  `.github/workflows/claude.yml`, so that path is dead here. **User was asked and
  hasn't answered.**
