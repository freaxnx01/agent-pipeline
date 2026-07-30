---
description: List and triage roadmap issues — list | promote <n> to <milestone> | defer <n> "<reason>"
argument-hint: list | promote <n> to <milestone> | defer <n> "<reason>"
---

Detect the forge, then run the matching section below.

```bash
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib/detect-forge.sh"
detect_forge
```

## GitHub

Manage roadmap issues in the current GitHub repo with **`gh`**.

### Parse the verb

**Three verbs only** — `list`, `promote`, `defer`.

- No arguments at all → treat it as `list`.
- A first word that isn't one of the three → print the three usage forms below and
  **stop**. Don't guess the intent, don't fuzzy-match.

```text
/roadmap list
/roadmap promote <n> to <milestone>
/roadmap defer <n> "<reason>"
```

### list

List open issues in the current repo that carry the `roadmap` label — newest first.
Show a compact table: number, title, labels, age (relative), author, and latest
`roadmap:` reason.

```bash
gh api graphql \
  -f owner="$(gh repo view --json owner -q .owner.login)" \
  -f name="$(gh repo view --json name -q .name)" \
  -f query='
query($owner:String!,$name:String!){
  repository(owner:$owner,name:$name){
    issues(states:OPEN, first:100, orderBy:{field:CREATED_AT, direction:DESC}){
      nodes{
        number title createdAt
        author{login}
        labels(first:20){nodes{name}}
        comments(last:20){nodes{body}}
      }
    }
  }
}' \
  --jq '.data.repository.issues.nodes
    | map(select([.labels.nodes[].name] | index("roadmap")))
    | .[] | [ .number, .title,
              ([.labels.nodes[].name] | join(",")),
              .createdAt, .author.login,
              ( [ .comments.nodes[].body | select(startswith("roadmap:")) ]
                | last // "—" | split("\n")[0] ) ] | @tsv'
```

If there are none, say the roadmap is empty and stop. This includes repos where the
`roadmap` label doesn't exist at all. Do not create the label.

### promote

`promote <n> to <milestone>` moves an issue from *someday* to *scheduled* in two
writes, in this order, each confirmed by read-back:

```bash
# 1) schedule it
gh issue edit <n> --milestone "<milestone>"
gh issue view <n> --json number,milestone --jq '[.number, (.milestone.title // "-")] | @tsv'

# 2) only if scheduling read-back shows the milestone
gh issue edit <n> --remove-label "roadmap"
gh issue view <n> --json number,labels --jq '[.number, ([.labels[].name] | join(","))] | @tsv'
```

If milestone assignment fails (including unknown milestone), print open milestones
and stop. No fuzzy matching, no silent creation:

```bash
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh api "repos/$repo/milestones?state=open&sort=due_on&direction=asc&per_page=100" \
  --jq '.[] | [.title, (.due_on // "-")] | @tsv'
```

If step 1 read-back does not show the milestone, stop and do not remove the label.
After both read-backs confirm, offer `/route <n>` (read and follow
`~/.claude/commands/route.md`) rather than running it automatically.

If you hit a blocker (missing auth, renamed fields, or a milestone write/read-back
mismatch), find a fix and update this command for the future.

## Forgejo

Manage roadmap issues in the current Forgejo repo with **`tea`** (login
`git-home`).

### Forgejo access

Target the homelab Forgejo (`git.home.freaxnx01.ch`) via **`tea`** (login
`git-home`). Resolve `owner/name` from the clone's remote (needed for `tea api`):

```bash
url=$(git remote get-url origin); url=${url%.git}
repo=$(echo "$url" | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#')
```

### Parse the verb

**Three verbs only** — `list`, `promote`, `defer`.

- No arguments at all → treat it as `list`.
- A first word that isn't one of the three → print the three usage forms below and
  **stop**. Don't guess the intent, don't fuzzy-match.

```text
/roadmap list
/roadmap promote <n> to <milestone>
/roadmap defer <n> "<reason>"
```

### list

Forgejo has no GraphQL. List open issues newest first, filter roadmap issues
client-side, then read comments per roadmap issue to extract the newest `roadmap:`
reason.

```bash
tea api --login git-home "repos/$repo/issues?state=open&type=issues&limit=100&sort=created&order=desc" \
  | python3 -c '
import sys,json
for i in json.load(sys.stdin):
    labels=[l["name"] for l in i.get("labels") or []]
    if "roadmap" not in labels: continue
    print(i["number"], "|", i["title"], "|", ",".join(labels), "|", i["created_at"], "|", (i.get("user") or {}).get("login","?"))'

tea api --login git-home "repos/$repo/issues/<n>/comments" \
  | python3 -c '
import sys,json
reasons=[c["body"] for c in json.load(sys.stdin) if c.get("body","").startswith("roadmap:")]
print(reasons[-1].split("\n")[0] if reasons else "—")'
```

If there are none, say the roadmap is empty and stop. Do not create the `roadmap`
label.

### promote

Before writing, verify the exact flags with `tea milestones issues add --help` and
`tea issues edit --help`.

`promote <n> to <milestone>` performs two writes, each with read-back:

```bash
# 1) schedule it
tea milestones issues add --login git-home "<milestone>" <n>
tea api --login git-home "repos/$repo/issues/<n>" | python3 -c '
import sys,json
i=json.load(sys.stdin)
m=i.get("milestone") or {}
print(i["number"], m.get("title") or "-", sep="\t")'

# 2) only if scheduling read-back confirms
tea issues edit <n> --login git-home --remove-labels "roadmap"
tea api --login git-home "repos/$repo/issues/<n>" | python3 -c '
import sys,json
i=json.load(sys.stdin)
print(i["number"], ",".join([l["name"] for l in i.get("labels") or []]), sep="\t")'
```

If milestone assignment fails or read-back still shows no milestone, stop and do not
remove the label. For unknown milestone names, print open milestones and stop (no
fuzzy matching, no silent creation):

```bash
tea api --login git-home "repos/$repo/milestones?state=open&limit=50" | python3 -c '
import sys, json
for m in sorted(json.load(sys.stdin), key=lambda x: x.get("due_on") or "9999"):
    print(m["title"], m.get("due_on") or "-", sep="\t")'
```

After both read-backs confirm, offer `/route <n>` (read and follow
`~/.claude/commands/route.md`) rather than running it automatically.

### defer

`defer <n> "<reason>"` appends a roadmap reason comment and keeps labels unchanged:

```bash
tea comment <n> "roadmap: <reason>"
tea api --login git-home "repos/$repo/issues/<n>/comments" | python3 -c '
import sys,json
comments=json.load(sys.stdin)
reasons=[c.get("body","") for c in comments if c.get("body","").startswith("roadmap:")]
print(reasons[-1].split("\n")[0] if reasons else "—")'
```

If no reason argument was provided, ask for one and stop. Never edit the issue body
and never edit a previous comment.

### No forge context

If `tea` isn't on `PATH`, there's no `git-home` login, or the remote isn't the
homelab Forgejo (`git.home.freaxnx01.ch`), say which of those it is, point at
`tea login add`, and stop.

If you hit a blocker (repo not resolvable, `tea` flags differ, or read-back doesn't
match the write), find a fix and update this command for the future.

## Unknown host

Report the detected host and that no authed GitHub or Forgejo login matched
it; point at `gh auth login` / `tea login add`. Don't guess a forge.
