# Glossary

## Epic

An epic is **not a native GitHub object** — it's a convention layered on top of
issues, and there are two common ways to express it:

1. **A tracking issue with a checklist** of links to the sub-issues. Works
   everywhere, but the bookkeeping is manual — nothing keeps the checklist in
   sync with the issues it points at.
2. **Native sub-issues** — GitHub's parent/child relationship between issues,
   shown in the issue sidebar. Unlike milestones, this *does* nest: a parent
   issue can have children, and those children can have children of their own,
   so an "epic" issue can sit inside another "epic" issue. It's supported in
   the UI and via the REST/GraphQL API; the `gh` CLI has no first-class
   sub-issue command yet (verified against `gh` 2.92.0 — no `gh issue
   sub-issue`, no `--parent` flag on `gh issue edit`), so scripting it means
   going through `gh api`.

An epic answers **"what work, and what scope"**. See [Milestone](#milestone)
and [Label](#label) for the other two axes, and
[Milestones vs epics vs labels](#milestones-vs-epics-vs-labels) for how they
combine.

## Label

A label is an **orthogonal categorization axis** — `bug`, `epic`,
`needs-enrichment`, `🧊 parked` — and nothing more. It is a tag, not a
grouping or containment mechanism: labelling ten issues `epic` doesn't relate
them to each other or to anything else. An issue can carry any number of
labels at once.

In this repo, labels drive routing rather than structure: `needs-enrichment`
marks an issue for `/enrich`, `ai-implement` hands it to the agent-workflow,
`🧊 parked` keeps it out of `/issues`. A label named `epic` just marks an
issue as being an epic-tracker so it can be filtered for — it doesn't make
anything belong to it.

## Milestone

A milestone is a **native GitHub object** scoped to a single repository (a
repo can have many, but a milestone can't span repos), holding a due date and
a flat list of issues and PRs. Create one via repo → Issues → Milestones → New
Milestone, or:

```bash
gh api repos/{owner}/{repo}/milestones -f title=... -f due_on=...
```

Assign issues to it from the issue sidebar or with
`gh issue edit <n> --milestone <name>`.

Milestones are **date- or release-scoped**, they do **not nest**, and an issue
belongs to **at most one milestone at a time**. A milestone answers **"when
does this ship"** — not what the work is. See
[Milestones vs epics vs labels](#milestones-vs-epics-vs-labels).

## Milestones vs epics vs labels

GitHub gives three separate, non-overlapping mechanisms here, and it's worth
keeping them distinct rather than picking one to stand in for all of it — a
milestone is not an epic, and an epic is not a label:

- **[Epic](#epic)** — a parent tracking issue (optionally using native
  sub-issues for nesting). Answers *what work, what scope*.

- **[Milestone](#milestone)** — a date/release bucket. Answers *when does this
  ship*. One milestone can hold issues from several epics, and one epic's
  issues can spread across several milestones.

- **[Label](#label)** — a flat tag (e.g. `epic`) used to filter. Answers
  *nothing about structure*; it only marks.

## Scope creep

Scope creep is when work quietly expands beyond what was originally asked for —
a bug fix that grows into a refactor, a small feature that pulls in unrelated
cleanup, or a discovery made mid-task ("found a flaky test", "this dependency
is vulnerable") that gets fixed on the spot instead of being written down for
later. It happens one small, reasonable-looking step at a time, which is what
makes it hard to notice from the inside — each hop seems justified, but three
or four hops away from the original request you're effectively doing a
different project without ever deciding to. This repo's convention is to treat
anything outside the stated scope as a **discovery**, not automatically a
**task**: capture it (`/capture-idea`, `docs/TODO.md`, `/gh:new`, `/fj:new`)
and keep going on the original ask, only expanding scope when that expansion
is a deliberate decision rather than a drift. See
[`partials/scope-boundary.md`](../partials/scope-boundary.md) for the full
rule.
