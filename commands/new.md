---
description: Create an issue from notes, labeled needs-enrichment
argument-hint: <notes describing the issue>
---

Detect the forge, then run the matching section below.

```bash
source "$HOME/.claude/scripts/lib/detect-forge.sh"
detect_forge
```

## GitHub

Create a GitHub issue in the current repo with `gh issue create`.

- **Title**: a concise summary derived from my notes.
- **Body**: my notes, lightly cleaned up — keep my meaning, don't invent scope or
  pad. Add a short context line only if it's obvious from the repo.
- **Label**: `needs-enrichment` (always). If that label doesn't exist yet, create
  it first (`gh label create needs-enrichment` with a sensible color), then retry.
- **Type label**: classify my notes as `type:feat` (a new capability — "add",
  "support for", a new mode/screen/entry point), `type:fix` (something is
  broken, wrong, or behaves unexpectedly and should be corrected), or
  `type:chore` (maintenance — refactor, docs, cleanup, tooling, deps) — this is
  a judgment call on what the notes actually describe, not a keyword match.
  Check whether that label exists in the target repo first
  (`gh label list --search "type:"`); if it does, add it alongside
  `needs-enrichment`. If none of the three exist there, this repo hasn't
  adopted the convention — skip it silently, don't create it.
- **Milestone**: only if my notes name one — then pass it as `-m "<name>"`. If that
  milestone doesn't exist yet, **ask** me before creating it (and ask for a due
  date); never create one silently. If I give no due date, omit `-f due_on=…`
  entirely — never pass an empty value. `gh milestone` doesn't exist — create it
  with `gh api "repos/$repo/milestones" -f title="<name>" -f due_on="<date>T12:00:00Z"`
  (`$repo` = `gh repo view --json nameWithOwner -q .nameWithOwner`), normalizing
  the due date to **midday UTC** so a viewer's timezone can't roll it back a day.
  If my notes don't name a milestone, don't set one and don't ask.
- Don't assign or add other labels unless I said so.

Write the cleaned-up notes to a temp file first (`mktemp`) — `--body-file` needs a
path, not inline text — then pass it as `<notes-file>`:

```bash
gh issue create --title "<concise title>" --body-file <notes-file> \
  --label needs-enrichment [--label "type:<feat|fix|chore>"] [-m "<milestone>"]
```

After creating, print the issue number, title, and URL — **read back** rather than
trusting the exit code (`gh issue create` has been seen exiting `0` while silently
dropping the label). If there's no `gh`/repo context, say so and stop.

```bash
gh issue view <number> --json number,title,url,labels,milestone
```

My notes:
$ARGUMENTS

## Forgejo

Create an issue in the current Forgejo repo with **`tea`** (login `git-home`).

- **Title**: a concise summary derived from my notes.
- **Body**: my notes, lightly cleaned up — keep my meaning, don't invent scope or
  pad. Add a short context line only if it's obvious from the repo.
- **Label**: `needs-enrichment` (always). If that label doesn't exist yet, create it
  first, then retry.
- **Type label**: same classification as the GitHub section — `type:feat` /
  `type:fix` / `type:chore`, a judgment call on what the notes describe. Check
  `tea labels list --login git-home` (repo path per the `tea api` note below)
  for a `type:` label first; if none exist, this repo hasn't adopted the
  convention — skip it silently, don't create it.
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
  --labels needs-enrichment[,type:<feat|fix|chore>]  # type: only if it exists here \
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

If you hit a blocker (label create rejects the color format, repo not resolvable),
find a fix and update this command for the future. The `-m "<milestone>"` flag on
`tea issues create` above is likewise unverified against a live run — same
epistemic status as `/milestone`'s flags — so check it against tea's own source
if it misbehaves, and update this command.

## Unknown host

Report the detected host and that no authed GitHub or Forgejo login matched
it; point at `gh auth login` / `tea login add`. Don't guess a forge.
