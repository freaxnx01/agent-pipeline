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
  create one silently. If I give no due date, omit `--deadline` entirely — never
  pass an empty value. If my notes don't name a milestone, don't set one and don't
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

`tea api` needs the explicit `owner/name` path (plain `tea` subcommands infer it
from cwd):

```bash
url=$(git remote get-url origin); url=${url%.git}
repo=$(echo "$url" | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#')
```

After creating, print the issue number, title, and URL — **read back** rather than
trusting the exit code (a forge CLI can exit `0` while silently dropping a field
the token lacked permission for, same as `gh issue create` has with a label).
Report the label and the milestone from the read-back, not from the write:

```bash
tea api --login git-home "repos/$repo/issues/<number>" | python3 -c '
import sys, json
i = json.load(sys.stdin)
labels = [l["name"] for l in i.get("labels", [])]
m = i.get("milestone") or {}
print(i["number"], i["title"], i.get("html_url") or "-", labels, m.get("title") or "-", sep="\t")'
```

If there's no `tea` login or repo context (not inside a Forgejo clone, or remote
isn't `git.home.freaxnx01.ch`), say so and stop.

My notes:
$ARGUMENTS

---

If you hit a blocker (label create rejects the color format, repo not resolvable),
find a fix and update this command for the future. The `-m "<milestone>"` flag on
`tea issues create` above is likewise unverified against a live run — same
epistemic status as `/fj:milestone`'s flags — so check it against tea's own source
if it misbehaves, and update this command.
