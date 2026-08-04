# Design: `/roadmap` — list and promote roadmap-labeled issues

**Issue:** [#175](https://github.com/freaxnx01/agent-workflow/issues/175)
**Date:** 2026-07-27
**Status:** approved — "two separate commands" confirmed by the user; `/roadmap`
mirrors `/parked`'s shape rather than merging with it.

---

## Problem

There is no command for the `roadmap` label at all. The label was introduced ad hoc
in `anim-bossinfo-ch/BI-ArchiveUploader` for *"Planned for future work, not yet
scheduled to a milestone"*, and [#173](https://github.com/freaxnx01/agent-workflow/issues/173)
is about to start **hiding** those issues from `/issues`.

Hiding them without giving them a home makes them invisible. `/roadmap` is the
home.

## Ordering dependency — read this first

**#175 must merge after #173.** #173 adds this sentence to `commands/gh/issues.md`
and `commands/fj/issues.md`:

> Roadmap issues are planned for a future milestone rather than current work; find
> them with `gh issue list --label roadmap`.

That raw-`gh` escape hatch is a **deliberate placeholder**, written that way because
`/gh:roadmap` did not exist yet. This issue replaces it. If #175 somehow lands
first, the sentence won't be there to replace — in that case say so and skip that
task rather than inventing the surrounding prose.

## Shape

`/roadmap` mirrors `/parked`'s structure — same three-file layout, same verb
grammar, same interaction rules:

| Verb | Behaviour |
|---|---|
| *(none)* | **`list`** — open issues carrying `roadmap`, newest first, compact table. |
| `promote <n>` | Move from *someday* to *scheduled*: assign a milestone, remove the `roadmap` label, read back. |
| `defer <n> "<reason>"` | Record why it's still on the roadmap, as a `roadmap:`-prefixed comment. |

It deliberately does **not** share an implementation with `/parked`
([#174](https://github.com/freaxnx01/agent-workflow/issues/174)). Parked means
*paused*; roadmap means *future-scheduled*. Some duplication between the two files
is the accepted cost of keeping the semantics distinct.

Both forges plus the router — `commands/gh/roadmap.md`, `commands/fj/roadmap.md`,
`commands/roadmap.md`.

## Design

### `promote` is the whole point

Promotion is a **two-part write**, and both parts must happen or neither is
meaningful:

1. Assign a milestone — the issue stops being *someday*.
2. Remove the `roadmap` label — otherwise `/issues` (post-#173) keeps hiding it,
   and a scheduled-but-hidden issue is worse than an unscheduled visible one.

Order matters: **assign first, then unlabel.** If the milestone assignment fails,
the issue stays hidden and correctly labelled rather than becoming visible with no
schedule. Read back after each part and report from the read-backs.

If the named milestone doesn't exist: print the open milestones and stop. **No
fuzzy matching, no silent creation** — the same rule `/milestone assign` already
states. Point at `/milestone new`.

After a successful promote, offer `/gh:route <n>` — the issue is now scheduled, so
"how do I implement this" is the natural next question. **Offer**, don't run it
automatically: unlike `/parked unpark`, promotion doesn't imply the work starts now.

### The label may not exist

`roadmap` exists in `anim-bossinfo-ch/BI-ArchiveUploader` but **not** in
`freaxnx01/agent-workflow`. `list` in a repo with no such label must report an empty
roadmap plainly — not an error, and **not** by creating the label. Creating labels
is out of scope; `/gh:new` and the forge UI own that.

### Reason comments

Same mechanism as `/parked repark`, different prefix: a comment starting
`roadmap:`. `list` shows the most recent one truncated to a line, `—` where absent.
Append-only; never edits the issue body (that races with `/enrich`) and never edits
a previous comment.

## Acceptance Criteria

1. `commands/gh/roadmap.md`, `commands/fj/roadmap.md`, and `commands/roadmap.md`
   exist, each with YAML front-matter naming the verbs `list`, `promote`, `defer`.
2. Bare invocation means `list`; an unrecognised first word prints the usage forms
   and stops without guessing.
3. `list` shows open issues carrying `roadmap`, newest first — number, title,
   labels, age, author, and the most recent `roadmap:` reason (`—` if none).
4. `list` in a repo with no `roadmap` label reports an empty roadmap plainly and
   does **not** create the label.
5. `promote <n> to <milestone>` assigns the milestone **first**, then removes the
   `roadmap` label, with a read-back after each; if the assignment fails it stops
   without touching the label.
6. An unknown milestone name prints the open milestones and stops — no fuzzy
   matching, no silent creation.
7. After a successful promote the command **offers** `/gh:route <n>` (`/fj:route` on
   Forgejo) rather than running it automatically.
8. `defer <n> "<reason>"` posts a `roadmap:`-prefixed comment, leaves the label in
   place, and never edits the issue body or a previous comment.
9. The escape-hatch sentence #173 added to `commands/gh/issues.md` and
   `commands/fj/issues.md` is replaced by a pointer to `/gh:roadmap` / `/fj:roadmap`.
10. No command in this change ever adds the `roadmap` label.
11. `CHANGELOG.md` has an entry under `[Unreleased]` → `### Added` referencing #175.

## Out of scope

- **Anything parked-related** — that is #174, deliberately a separate command.
- **Creating the `roadmap` label** in any repo.
- Changing which issues `/issues` excludes — that is #173.
- A shared parked+roadmap triage abstraction. Explicitly rejected in favour of two
  commands.

## Verification

Automated: string-presence checks per task step — this repo has **no test framework
for command `.md` files**, so no test file or fixture may be added.

Manual, after merge: `freaxnx01/agent-workflow` has **no** `roadmap` label, so run
`/roadmap` here and confirm it reports an empty roadmap without creating anything.
Then run it in `anim-bossinfo-ch/BI-ArchiveUploader`, which has the label and
issue **#164** carrying it — confirm #164 lists, then `promote` it to a milestone
and confirm it disappears from `/roadmap` and appears under `/milestone list`.
