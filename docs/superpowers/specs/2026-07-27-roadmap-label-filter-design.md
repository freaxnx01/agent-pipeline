# Design: exclude `roadmap`-labeled issues from `/issues`

**Issue:** [#173](https://github.com/freaxnx01/agent-workflow/issues/173)
**Date:** 2026-07-27
**Status:** approved — scope (both forges) confirmed by the user at the
brainstorming gate; the acceptance criteria below were authored after that gate and
have not been separately signed off.

---

## Problem

`/gh:issues` and `/fj:issues` answer one question: *what is open, actionable, and
not already being worked on?* They earn that by subtracting two sets from the open
issues — WIP (an open linked PR) and parked (`🧊 parked`).

A third "deliberately not now" state has since appeared in practice: the `roadmap`
label, born ad hoc in `anim-bossinfo-ch/BI-ArchiveUploader` for *planned for future
work, not yet scheduled to a milestone*. Neither command knows about it, so
roadmap-labeled issues still surface as actionable work.

Observed directly: `anim-bossinfo-ch/BI-ArchiveUploader#164` carries
`needs-enrichment | roadmap` and still appears in `/gh:issues` output.

## The label — verified, not assumed

The whole change is a string match, so the exact string is the load-bearing
constraint. Verified against the repo where the label was introduced:

```
$ gh label list --repo anim-bossinfo-ch/BI-ArchiveUploader | grep -i roadmap
roadmap    Planned for future work, not yet scheduled to a milestone    #0e8a16
```

**The label is bare `roadmap`** — lowercase, no emoji, no prefix. It does *not*
follow the `🧊 parked` emoji convention. Any filter written against `📍 roadmap`
or `Roadmap` is a silent no-op that still passes a string-presence check.

The label does **not** exist in `freaxnx01/agent-workflow` itself. That is fine and
must not be treated as a blocker: both filters are label-absence checks, so in a
repo with no `roadmap` label they are inert no-ops. Do not create the label here as
part of this change.

## Scope

**In scope** — the two commands that already do parked-filtering:

| File | Change |
|---|---|
| `commands/gh/issues.md` | jq pipeline + prose + front-matter `description:` |
| `commands/fj/issues.md` | python filter + prose + front-matter `description:` |
| `commands/issues.md` | front-matter `description:` only (router holds no query logic) |
| `CHANGELOG.md` | `[Unreleased] → ### Changed` entry |

Both forges, decided deliberately: #173's body names only `/gh:issues`, but
`/fj:issues` carries the identical parked filter and this repo keeps hard gh/fj
parity. Shipping GitHub-only would leave Forgejo behind and the router's
description half-true, and would need a follow-up issue immediately.

**Out of scope** — captured, not acted on:

- **`/gh:triage`** — #173 explicitly says "not scoping that here", and inspection
  confirms `commands/gh/triage.md` has **no parked filter at all**. Adding roadmap
  awareness there is a larger, differently-shaped change (it would mean introducing
  deferred-state filtering to triage for the first time), not a third filter step.
- **A `/gh:roadmap` listing command** so filtered issues remain visible — that is
  [#175](https://github.com/freaxnx01/agent-workflow/issues/175).
- **Shared parked/roadmap triage UX** — that is
  [#174](https://github.com/freaxnx01/agent-workflow/issues/174) / #175.
- **The `author` column** in the output table. It is arguably noise in a
  single-owner setup, but it does not trace to #173. Leave it.

## Design

### Two independent filter steps, not one merged list

The jq pipeline gains a **third `map(select(...))` step**, mirroring the parked step
character-for-character rather than collapsing both into a single
`["🧊 parked","roadmap"]` membership test.

Rationale:

- #173 asks for exactly this ("add a third filter step … alongside the existing
  `🧊 parked` exclusion").
- The two states are semantically distinct — parked is *paused*, roadmap is
  *future-scheduled* — and #174/#175 may well give them different handling. A
  merged list would have to be un-merged then.
- Mirroring the existing idiom keeps the diff to one added line and makes it
  obvious the new step is the same kind of thing as the one above it.

**GitHub** (`commands/gh/issues.md`, after the existing parked line):

```jq
| map(select([.labels.nodes[].name] | index("roadmap") | not))
```

`labels(first:20)` is already in the GraphQL query — **no query change is needed**,
only the jq post-filter.

**Forgejo** (`commands/fj/issues.md`) has no jq; the equivalent lives in the inline
python `continue` guard, extended in place:

```python
if i["number"] in wip or "🧊 parked" in labels or "roadmap" in labels: continue
```

### Three text surfaces per command file, not one

Easy to change the filter and leave the file lying about what it does. Each of
`commands/gh/issues.md` and `commands/fj/issues.md` has three places that state the
contract:

1. **front-matter `description:`** (line 2) — this is what renders in the `/`
   autocomplete menu
2. **the opening prose** stating what is subtracted, plus the `/gh:parked` /
   `/fj:parked` pointer sentence
3. **the approach paragraph / inline comment** explaining the filter steps

All three must name roadmap. `commands/issues.md` has only surface 1.

### Where do the hidden issues go?

Parked issues have `/gh:parked` as their escape hatch; the prose points at it.
Roadmap issues have **no listing command yet** — that is #175. So the prose must
not promise one. Point at the label instead:

> Roadmap issues are planned for a future milestone, not current work; find them
> with `gh issue list --label roadmap`.

When #175 lands it can replace that sentence with `/gh:roadmap`.

## Acceptance Criteria

1. `commands/gh/issues.md`'s jq pipeline contains a filter step dropping any issue
   whose labels include the exact string `roadmap`, written in the same
   `map(select([.labels.nodes[].name] | index(...) | not))` idiom as the existing
   `🧊 parked` step, and placed after it.
2. `commands/fj/issues.md`'s python `continue` guard drops any issue whose labels
   include the exact string `roadmap`, alongside the existing `🧊 parked` check.
3. The front-matter `description:` in all three of `commands/gh/issues.md`,
   `commands/fj/issues.md`, and `commands/issues.md` states that roadmap issues are
   excluded.
4. The body prose in `commands/gh/issues.md` and `commands/fj/issues.md` states that
   roadmap-labeled issues are excluded and tells the reader how to find them —
   `gh issue list --label roadmap` and
   `tea issues list --login git-home --labels roadmap` (**plural** `--labels`,
   verified against `tea issues list --help`, tea 0.14.1) — without referring to a
   `/gh:roadmap` or `/fj:roadmap` command, which does not exist.
5. The label is matched as bare lowercase `roadmap` — no emoji prefix, in any file.
6. `commands/gh/triage.md`, `commands/gh/parked.md`, `commands/fj/parked.md`, and
   every file under `.github/workflows/` are unmodified.
7. `CHANGELOG.md` has an entry under `[Unreleased] → ### Changed` referencing #173.
8. Both command files still end with their existing self-improving footer, and
   `commands/fj/issues.md`'s Forgejo-access section is unchanged.

## Verification

**Automated (CI-executable).** This repo has **no test framework for command `.md`
files** — `just lint` runs `actionlint` + `shellcheck` over `.github/workflows/`,
`scripts/`, and `tests/` only, and nothing parses command front-matter or executes
the bash inside `commands/**/*.md`. **Do not add a test file, fixture, or `tests/`
entry for this change.** Verification is string-presence checks in the task steps,
following the precedent set by the #172 plan.

**Manual (post-merge, human-run).** Live-forge reads are deliberately excluded from
task steps:

1. Reinstall commands (`setup/link-commands.sh`) and run `/gh:issues` inside
   `anim-bossinfo-ch/BI-ArchiveUploader` — issue **#164** must no longer appear.
2. Run `/gh:issues` in `freaxnx01/agent-workflow`, which has no `roadmap` label —
   output must be unchanged from before (proving the filter is inert, not
   over-matching).
3. Run `/fj:issues` against a Forgejo repo to confirm the python change did not
   break the existing pipeline. (`tea` 0.14.1 was installed locally while writing
   this spec, so unlike #172's `/fj:milestone` work the Forgejo flags here are
   verified rather than read from source — but no live Forgejo call has been made.)

## Risks

- **Over-matching.** `index("roadmap")` on a label *list* is exact-element
  membership, not substring — a label named `roadmap-q3` would **not** match. This
  is the intended behaviour and matches how the parked filter already works.
- **Silent no-op.** If the label string is ever changed to carry an emoji, both
  filters go quiet with no error. Mitigated by manual verification step 1, which
  asserts on a real labeled issue.
