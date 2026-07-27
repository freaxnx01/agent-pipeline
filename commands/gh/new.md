---
description: Create a GitHub issue from notes, labeled needs-enrichment
argument-hint: <notes describing the issue>
---

Create a GitHub issue in the current repo with `gh issue create`.

- **Title**: a concise summary derived from my notes.
- **Body**: my notes, lightly cleaned up — keep my meaning, don't invent scope or
  pad. Add a short context line only if it's obvious from the repo.
- **Label**: `needs-enrichment` (always). If that label doesn't exist yet, create
  it first (`gh label create needs-enrichment` with a sensible color), then retry.
- **Milestone**: only if my notes name one — then pass it as `-m "<name>"`. If that
  milestone doesn't exist yet, **ask** me before creating it (and ask for a due
  date); never create one silently. `gh milestone` doesn't exist — create it with
  `gh api "repos/$repo/milestones" -f title="<name>" -f due_on="<date>T12:00:00Z"`
  (`$repo` = `gh repo view --json nameWithOwner -q .nameWithOwner`), normalizing
  the due date to **midday UTC** so a viewer's timezone can't roll it back a day.
  If my notes don't name a milestone, don't set one and don't ask.
- Don't assign or add other labels unless I said so.

Write the cleaned-up notes to a temp file first (`mktemp`) — `--body-file` needs a
path, not inline text — then pass it as `<notes-file>`:

```bash
gh issue create --title "<concise title>" --body-file <notes-file> \
  --label needs-enrichment [-m "<milestone>"]
```

After creating, print the issue number, title, and URL — **read back** rather than
trusting the exit code (`gh issue create` has been seen exiting `0` while silently
dropping the label). If there's no `gh`/repo context, say so and stop.

```bash
gh issue view <number> --json number,labels,milestone
```

My notes:
$ARGUMENTS
