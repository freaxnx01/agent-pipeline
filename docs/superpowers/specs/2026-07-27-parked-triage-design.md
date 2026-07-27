# Design: `/parked` gains triage verbs

**Issue:** [#174](https://github.com/freaxnx01/agent-workflow/issues/174)
**Date:** 2026-07-27
**Status:** approved — "two separate commands, extend `/gh:parked`" confirmed by
the user (the alternative was one shared parked+roadmap command).

---

## Problem

`/gh:parked` and `/fj:parked` are list-only. They show what's parked, newest first,
and stop. Two things are missing:

- **No way to act.** Getting an issue *out* of parked means remembering the exact
  label string, editing it by hand, and then separately deciding how to implement
  it.
- **No "why".** A parked issue carries the `🧊 parked` label and nothing else.
  Months later there's no record of *why* it was paused or *what would unblock it*,
  so re-reviewing means re-deriving the reasoning from scratch.

## Shape

`/parked` gains verbs, mirroring how `/milestone` is structured:

| Verb | Behaviour |
|---|---|
| *(none)* | **`list`** — exactly today's behaviour, unchanged. |
| `unpark <n>` | Remove `🧊 parked`, read back, then hand to `/gh:route <n>` for an implementation recommendation. |
| `repark <n> "<reason>"` | Keep the label, record/refresh the reason. |
| `review` | Walk the parked set one issue at a time: *still valid to stay parked?* → unpark / repark / skip. |

`/gh:roadmap` ([#175](https://github.com/freaxnx01/agent-workflow/issues/175)) is a
**separate** command with its own semantics — parked is *paused*, roadmap is
*future-scheduled*. The two deliberately do not share an implementation. Some
duplication between them is accepted as the cost of keeping the semantics distinct.

Both forges plus the router — `commands/gh/parked.md`, `commands/fj/parked.md`,
`commands/parked.md` — matching the existing three-file layout for this command.

## Design

### Where the "why" lives

**An issue comment**, prefixed `🧊 parked:`.

Considered and rejected: editing the issue body (destructive, races with `/enrich`
which rewrites bodies wholesale) and a second label (labels are tags, not prose —
`docs/glossary.md` is explicit that a label is *"an orthogonal categorization axis
and nothing more"*).

A comment is append-only, timestamped, attributed, and survives body rewrites.
`repark` posts a new one rather than editing the old, so the history of *why this
kept getting deferred* is readable in order.

`list` shows the **most recent** `🧊 parked:` comment per issue, truncated to one
line. Issues with no reason comment show `—`, which is itself useful: it marks the
ones parked before this feature existed.

### `unpark` hands off, it doesn't decide

`unpark` removes the label, reads back to confirm, and then **delegates to
`/gh:route <n>`** rather than recommending a route itself. `route` already owns
that judgment (readiness gate, complexity assessment, model choice) and duplicating
it here would guarantee drift.

If the issue still carries `needs-enrichment`, say so — unparking doesn't make it
implementable, and `route`'s own readiness gate will catch it.

### `review` is a walk, not a batch

One issue at a time, newest first: show number, title, labels, age, and the current
reason. Offer `unpark` / `repark` / `skip`. Never act without an explicit answer;
`skip` is silent and never re-prompts. Report the tally at the end.

This is the same interaction contract as `/milestone triage`
([#178](https://github.com/freaxnx01/agent-workflow/issues/178)) — deliberately, so
the two feel like one tool. They share no code, only the rules.

### Every write reported from a read-back

Not decorative: `gh issue create --label needs-enrichment` has been observed
printing the URL and exiting `0` while silently dropping the label, because the
token lacked label-write. `unpark` and `repark` re-read and report what the
read-back says.

## Acceptance Criteria

1. `commands/gh/parked.md`, `commands/fj/parked.md`, and `commands/parked.md` all
   document the verbs `unpark`, `repark`, and `review`, and their front-matter
   `description:` / `argument-hint:` lines name them.
2. Bare invocation (no arguments) still means `list`, and today's list output is
   behaviourally unchanged apart from the added reason column.
3. An unrecognised first word prints the usage forms and stops without guessing.
4. `unpark <n>` removes only the `🧊 parked` label, confirms from a read-back, and
   then delegates to `/gh:route <n>` (`/fj:route` on Forgejo) rather than
   recommending a route itself.
5. `repark <n> "<reason>"` posts a new issue comment prefixed `🧊 parked:`, leaves
   the label in place, and confirms from a read-back. It never edits the issue body
   and never edits a previous comment.
6. `list` shows the most recent `🧊 parked:` comment per issue truncated to one
   line, and `—` where there is none.
7. `review` walks the parked issues one at a time offering `unpark` / `repark` /
   `skip`, never acts without an explicit answer, and reports a tally at the end.
8. No command in this change ever adds the `🧊 parked` label — parking stays a
   manual act.
9. `CHANGELOG.md` has an entry under `[Unreleased]` → `### Added` referencing #174.

## Out of scope

- **Anything roadmap-related** — that is #175, deliberately a separate command.
- **Parking an issue** (`/parked add`). Nothing asks for it and parking is a
  judgment call made while looking at the issue.
- Changing which issues `/issues` excludes.

## Verification

Automated: string-presence checks per task step — this repo has **no test framework
for command `.md` files**, so no test file or fixture may be added.

Manual, after merge: `freaxnx01/agent-workflow` has exactly **1** parked issue as of
2026-07-27. Run `/parked` and confirm it shows with `—` for the reason; `repark` it
with a reason and confirm the reason appears on the next `/parked`; `unpark` it and
confirm the label is gone and `/gh:route` runs; then re-park it by hand to restore
the repo's state.
