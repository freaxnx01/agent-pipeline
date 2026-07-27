---
description: Create a Forgejo issue from notes, labeled needs-enrichment
argument-hint: <notes describing the issue>
---

Create an issue in the current Forgejo repo with **`tea`** (login `git-home`).

- **Title**: a concise summary derived from my notes.
- **Body**: my notes, lightly cleaned up — keep my meaning, don't invent scope or
  pad. Add a short context line only if it's obvious from the repo.
- **Label**: `needs-enrichment` (always). If that label doesn't exist yet, create it
  first, then retry.
- **Milestone**: only if my notes name one — then pass it as `-m "<name>"`. If that
  milestone doesn't exist yet, **ask** me before creating it (and ask for a due
  date, via `tea milestones create --login git-home --title … --deadline …`); never
  create one silently. If my notes don't name a milestone, don't set one and don't
  ask.
- Don't assign or add other labels unless I said so.

```bash
# create the label if missing (idempotent: ignore "already exists")
tea labels create --login git-home --name needs-enrichment --color "#d4c5f9" \
  --description "Needs a spec/plan before an agent can implement" 2>/dev/null || true

# create the issue — NOTE: tea uses --description / -d for the body (not --body)
tea issues create --login git-home \
  --title "<concise title>" \
  --description "<cleaned-up notes>" \
  --labels needs-enrichment \
  -m "<milestone>"            # only when my notes named one
```

After creating, print the issue number, title, and URL. If there's no `tea` login
or repo context (not inside a Forgejo clone, or remote isn't
`git.home.freaxnx01.ch`), say so and stop.

My notes:
$ARGUMENTS

---

If you hit a blocker (label create rejects the color format, repo not resolvable),
find a fix and update this command for the future.
