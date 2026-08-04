# Design: `/milestone triage` — surface and fill the milestone gap

**Issue:** [#178](https://github.com/freaxnx01/agent-workflow/issues/178)
**Date:** 2026-07-27
**Status:** approved — interactive, one issue at a time, confirmed by the user.

---

## Problem

Nothing surfaces open issues that have **no milestone**.

`/milestone list` deliberately doesn't: it nests open issues *under* each milestone
and says outright that listing un-milestoned work is `/issues`' job
(`commands/gh/milestone.md:46-48`). But `/issues` has no milestone awareness at
all — it filters on WIP and deferred-state labels and never reads `.milestone`. So
the gap is invisible from both sides, and an issue can sit unscheduled
indefinitely without anything flagging it.

## Shape: a fourth verb, not a new command

`/milestone` already owns the *when does this ship* axis and already carries the
`list` / `new` / `assign` verbs. The gap is a milestone concern, so it becomes
**`/milestone triage`** rather than a new top-level command name.

This deliberately extends #172's "three verbs only — do **not** add `unassign`,
`close`, `reopen`, `delete`, or `edit`" constraint. That constraint was scoping
#172's own delivery and was aimed at *destructive* and *redundant* verbs; `triage`
is neither, and it is what #178 asks for. Note the reasoning here so the next
reader doesn't treat the three-verb rule as permanent.

Per #178: **both forges**, following the existing `/gh:*` + `/fj:*` +
generic-router pattern — `commands/gh/milestone.md`, `commands/fj/milestone.md`,
and `commands/milestone.md`.

## Design

### What counts as "needs a milestone"

Open issues where `.milestone` is null, **minus** the two deliberately-deferred
states:

- `🧊 parked` — paused on purpose; scheduling it would be a lie.
- `roadmap` — explicitly *"planned for future work, not yet scheduled to a
  milestone"*. Its whole meaning is *not milestoned yet*, so nagging about it is
  noise.

This mirrors `/issues`' exclusion set. It is a **semantic** dependency on
[#173](https://github.com/freaxnx01/agent-workflow/issues/173), not a code one —
`/milestone triage` implements its own filter and does not call `/issues`, so the
two can ship in either order.

Pull requests are out: `gh issue list` excludes them, and the Forgejo call uses
`type=issues`.

### The interaction

Two phases, deliberately separated so the operator sees the whole picture before
answering anything:

**Phase 1 — show the gap.** A compact list, newest first (matching `/issues`'
ordering): number, title, labels. Plus the count. If the list is empty, say so and
stop — do not enter the walk.

**Phase 2 — walk it, one issue at a time.** For each issue, newest first:

- show number, title, labels
- offer the **open milestones** (fetched once, before the walk) plus `skip`
- apply the choice, then **read back** and report from the read-back
- move to the next issue

```
Un-milestoned (3):
  #158  feat(commands): manual-test checklist
  #157  feat(commands): TODO.md add command
  #156  feat(gh): DueDate on issue create

#158 → [next] [later] [skip] ? next
  ✓ read-back: #158 → next
#157 → …
```

### Interaction rules

1. **One issue at a time.** No bulk-assign-all, no "apply to the rest". The point
   is per-issue judgment; batching it defeats the purpose.
2. **`skip` is always offered**, and skipping is silent — no nagging, no re-prompt.
3. **Never assign without an answer.** No default milestone, no inferring from
   labels or title. An unanswered issue is a skipped issue.
4. **Never create a milestone.** If the wanted one doesn't exist, say so and point
   at `/milestone new`. No fuzzy matching, no silent creation — the same rule
   `assign` already states.
5. **Stop cleanly** whenever the operator says stop, and report how many were
   assigned and how many remain.
6. **Every write reported from a read-back, never from the exit code.** This is the
   existing rule at `commands/gh/milestone.md:31-35`, and it is not decorative:
   `gh issue create --label needs-enrichment` has been observed exiting `0` while
   silently dropping the label.

### Truncation guard

`list` already carries one and `triage` needs the same discipline: the issue query
is capped, so print the number shown and say plainly when the cap was hit, rather
than implying the list is complete.

## Acceptance Criteria

1. `commands/gh/milestone.md`, `commands/fj/milestone.md`, and
   `commands/milestone.md` all document a fourth verb `triage`, and all three
   front-matter `description:` / `argument-hint:` lines include it.
2. Phase 1 lists **open issues whose milestone is null**, newest first, showing
   number, title, and labels, plus a count.
3. Issues carrying `🧊 parked` or `roadmap` are excluded from that list.
4. Pull requests are excluded.
5. Phase 2 walks the issues **one at a time**, offering the open milestones plus an
   explicit `skip`, and never assigns without an explicit answer.
6. Each assignment is followed by a read-back, and the reported result comes from
   the read-back rather than the write's exit code.
7. The command never creates a milestone — an unknown name prints the open
   milestones and stops.
8. An empty gap list is reported plainly and the walk is not entered.
9. The three existing verbs (`list`, `new`, `assign`) are behaviourally unchanged,
   and the bare-invocation rule (no args → `list`) still holds.
10. `CHANGELOG.md` has an entry under `[Unreleased]` → `### Added` referencing #178.

## Out of scope

- Making `/issues` milestone-aware. #178 asks for the gap to be *surfaced*, not for
  `/issues` to change.
- Due dates, milestone renaming, closing, or any other verb.
- Un-assigning a milestone.

## Verification

Automated: string-presence checks per task step — this repo has **no test framework
for command `.md` files**, so no test file or fixture may be added.

Manual, after merge: run `/milestone triage` in `freaxnx01/agent-workflow`, which
currently has 6 issues in `next` and many with no milestone. Confirm the gap list
excludes any `🧊 parked` issue, that skipping leaves an issue untouched, and that an
assignment is confirmed from a read-back. Then run it again and confirm the
just-assigned issue no longer appears.
