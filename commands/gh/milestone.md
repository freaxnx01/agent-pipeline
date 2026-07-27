---
description: List, create, assign, or triage GitHub milestones — list | new <name> [due <date>] | assign <issue> to <name> | triage
argument-hint: list | new <name> [due <date>] | assign <issue> to <name> | triage
---

Manage milestones in the current GitHub repo with **`gh`**.

A milestone is the *when does this ship* axis: repo-scoped, no nesting, one due
date, at most one per issue. It is not an epic (*what work, what scope*) and not a
label (*a filter tag*) — see `docs/glossary.md` in agent-workflow.

## Parse the verb

**Four verbs only** — `list`, `new`, `assign`, `triage`.

- No arguments at all → treat it as `list`.
- A first word that isn't one of the four → print the four usage forms below and
  **stop**. Don't guess the intent, don't fuzzy-match.

```text
/milestone list
/milestone new <name> [due <date>]
/milestone assign <issue> to <name>
/milestone triage
```

## Two rules that apply to every verb

> **`gh milestone` does not exist** (`unknown command "milestone" for "gh"`). Only
> assignment has a first-class flag; creation and listing go through `gh api`.
>
> **Report every write from a read-back — never from the exit code.** This is not
> hypothetical: `gh issue create --label needs-enrichment` has been observed printing
> the issue URL and exiting `0` while silently dropping the label, because the token
> lacked label-write permission. After `new` and `assign`, re-read and report what
> the read-back says, not what the write returned.

Resolve the repo once — `gh api` paths need it:

```bash
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

## list

Open milestones, each with its **open issues nested underneath**. Milestones with
zero issues are shown too — that's the point, they're what you want to see right
after `/milestone new`. Issues with *no* milestone are **not** listed; that's what
`/issues` is for.

Two calls, grouped locally — cost is fixed regardless of milestone count, and the
milestone call returns the API's own issue counts to cross-check against:

```bash
gh api "repos/$repo/milestones?state=open&sort=due_on&direction=asc&per_page=100" \
  --jq '.[] | [.title, (.due_on // "-"), .open_issues, .closed_issues] | @tsv'

gh issue list --state open --limit 200 --json number,title,milestone \
  --jq '.[] | [(.milestone.title // "-"), .number, .title] | @tsv'
```

Group the second output by milestone title and render a compact tree — title, due
date, `open/closed` counts, then the issues. No preamble. If there are no open
milestones, just say so.

**Truncation guard.** Print the API's `open_issues` count next to the number of
issues actually shown. When they differ, say so *and* say what it can mean — the
issue query hit its 200 limit, **or** pull requests are assigned to that milestone
(`open_issues` counts issues *and* PRs together, while `gh issue list` excludes
PRs). Don't claim truncation when it might be PRs.

## new

```bash
# with a due date — normalize a bare YYYY-MM-DD to MIDDAY UTC, deliberately:
# midnight would let a viewer timezone offset render the previous day.
gh api "repos/$repo/milestones" \
  -f title="<name>" \
  -f due_on="<YYYY-MM-DD>T12:00:00Z"

# no due date given — omit the field entirely, don't pass an empty value
gh api "repos/$repo/milestones" -f title="<name>"
```

Then **read back** and report from the read-back:

```bash
gh api "repos/$repo/milestones?state=open&per_page=100" \
  --jq '.[] | select(.title == "<name>") | [.number, .title, (.due_on // "-")] | @tsv'
```

Confirm the `due_on` that came back is the date I asked for. A `422` with
`already_exists` means the title is taken — report the existing milestone and
**stop**; don't retry with a variant name.

## assign

```bash
gh issue edit <issue> --milestone "<name>"
```

Then **read back**:

```bash
gh issue view <issue> --json number,milestone --jq '[.number, (.milestone.title // "-")] | @tsv'
```

If the milestone name doesn't exist, `gh` rejects it — print the open milestones
(the `list` call above) and stop. **No fuzzy matching, no silent creation.**

## triage

Open issues with **no milestone** — the gap `list` deliberately doesn't show.
Two phases: show the whole gap first, then walk it one issue at a time.

Excludes `🧊 parked` (paused on purpose) and `roadmap` (*planned for future work,
not yet scheduled to a milestone* — being un-milestoned is its whole meaning, so
nagging about it is noise). Pull requests are excluded by `gh issue list`.

**Phase 1 — show the gap.** Newest first:

```bash
gh issue list --state open --limit 200 --json number,title,labels,milestone,createdAt \
  --jq 'map(select(.milestone == null))
    | map(select([.labels[].name] | index("🧊 parked") | not))
    | map(select([.labels[].name] | index("roadmap") | not))
    | sort_by(.createdAt) | reverse
    | .[] | [.number, .title, (([.labels[].name] | join(",")) | if . == "" then "-" else . end)] | @tsv'
```

Print the count with the list. **Truncation guard:** the query caps at 200 — if that
many came back, say the list may be incomplete rather than implying it's the whole
gap. If nothing came back, say the gap is empty and **stop — do not enter the walk.**

**Phase 2 — walk it.** Fetch the open milestones **once**, before the walk:

```bash
gh api "repos/$repo/milestones?state=open&sort=due_on&direction=asc&per_page=100" \
  --jq '.[] | [.title, (.due_on // "-")] | @tsv'
```

Then, for each issue newest first: show number, title, labels; offer the milestone
titles plus `skip`; on an answer, assign and **read back**:

```bash
gh issue edit <issue> --milestone "<name>"
gh issue view <issue> --json number,milestone --jq '[.number, (.milestone.title // "-")] | @tsv'
```

Report from the read-back, never from the exit code.

Rules for the walk:

- **One issue at a time.** No bulk-assign, no "apply to the rest".
- **`skip` is always offered**, and skipping is silent — don't re-prompt.
- **Never assign without an explicit answer.** No default milestone, no inferring
  from labels or title. Unanswered means skipped.
- **Never create a milestone.** An unknown name → print the open milestones and
  stop; point at `/milestone new`. No fuzzy matching, no silent creation.
- **Stop cleanly** when told to, and report how many were assigned and how many
  remain.

## No forge context

If `gh` isn't on `PATH`, isn't authenticated, or the cwd isn't a GitHub clone, say
which of those it is, point at `gh auth login`, and stop.

My arguments:
$ARGUMENTS

---

If you hit a blocker (a `gh api` field renamed, `due_on` coming back a day off, a
token missing milestone-write permission), find a fix and update this command for
the future.
