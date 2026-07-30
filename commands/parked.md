---
description: List and triage parked (🧊) issues — list | unpark <n> | repark <n> "<reason>" | review
argument-hint: list | unpark <n> | repark <n> "<reason>" | review
---

Detect the forge, then run the matching section below.

```bash
source "$HOME/.claude/scripts/lib/detect-forge.sh"
detect_forge
```

## GitHub

Manage parked issues in the current GitHub repo with **`gh`**.

### Parse the verb

**Four verbs only** — `list`, `unpark`, `repark`, `review`.

- No arguments at all → treat it as `list`.
- A first word that isn't one of the four → print the four usage forms below and
  **stop**. Don't guess the intent, don't fuzzy-match.

```text
/parked list
/parked unpark <n>
/parked repark <n> "<reason>"
/parked review
```

### list

List open issues in the current repo that are **parked** — i.e. carry the
`🧊 parked` label — **newest first**. Keep the existing table shape and add a
`reason` column from the most recent `🧊 parked:` comment.

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
    | map(select([.labels.nodes[].name] | index("🧊 parked")))
    | .[] | [ .number, .title,
              ([.labels.nodes[].name] | join(",")),
              .createdAt, .author.login,
              ( [ .comments.nodes[].body | select(startswith("🧊 parked:")) ]
                | last // "—" | split("\n")[0] ) ] | @tsv'
```

Show a compact table — number, title, labels, age (relative), author, reason.
No preamble. If there are none, just say so.

### unpark

Remove only the `🧊 parked` label, then confirm from a read-back:

```bash
gh issue edit <n> --remove-label "🧊 parked"
gh issue view <n> --json number,labels --jq '[.number, ([.labels[].name] | join(","))] | @tsv'
```

Report from the read-back. If `🧊 parked` is still present, say the removal
failed and stop — do not continue to routing.

If the issue also has `needs-enrichment`, say so before routing. Then delegate:
read and follow `~/.claude/commands/route.md` (i.e. run `/route <n>`).
`/parked` must not reimplement route logic.

### repark

`repark` keeps labels as-is and appends a fresh reason comment:

```bash
gh issue comment <n> --body "🧊 parked: <reason>"
```

Then confirm from read-back:

```bash
gh issue view <n> --json comments --jq '.comments | last | .body | split("\n")[0]'
```

If no reason argument was provided, ask for one and stop. Never edit the issue
body and never edit a previous comment.

### review

Walk the parked issues from `list`, newest first, one at a time. For each issue:
show number, title, labels, age, and current reason; ask *still valid to stay
parked?* with options `unpark` / `repark` / `skip`.

- One issue at a time. No bulk actions.
- Never act without an explicit answer. Unanswered means skipped.
- `skip` is silent and never re-prompts.
- Stop cleanly when told to.
- Report a final tally: unparked, reparked, skipped, remaining.

My arguments:
$ARGUMENTS

## Forgejo

Manage parked issues in the current Forgejo repo with **`tea`** (login
`git-home`).

### Forgejo access

Target the homelab Forgejo (`git.home.freaxnx01.ch`) via **`tea`** (login
`git-home`). Resolve `owner/name` from the clone's remote (needed for `tea api`):

```bash
url=$(git remote get-url origin); url=${url%.git}
repo=$(echo "$url" | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#')
```

### Parse the verb

**Four verbs only** — `list`, `unpark`, `repark`, `review`.

- No arguments at all → treat it as `list`.
- A first word that isn't one of the four → print the four usage forms below and
  **stop**. Don't guess the intent, don't fuzzy-match.

```text
/parked list
/parked unpark <n>
/parked repark <n> "<reason>"
/parked review
```

### list

Forgejo has no GraphQL, so we can't get everything in one query. List parked
issues first, then fetch comments for each parked issue to extract the newest
`🧊 parked:` reason.

```bash
# open PRs → set of referenced issue numbers (for the WIP annotation)
tea api --login git-home "repos/$repo/pulls?state=open&limit=50&type=pulls" \
  | python3 -c '
import sys,json,re
pat=re.compile(r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)", re.I)
wip=set()
for p in json.load(sys.stdin):
    for n in pat.findall((p.get("title") or "")+" "+(p.get("body") or "")): wip.add(int(n))
open("/tmp/fj_wip.txt","w").write(" ".join(map(str,sorted(wip))))'

# parked issues, newest first — filter client-side (the labels= query param breaks
# on a label name containing a space + emoji; it isn't URL-encoded by tea api)
tea api --login git-home "repos/$repo/issues?state=open&type=issues&limit=100&sort=created&order=desc" \
  | python3 -c '
import sys,json
wip=set(int(x) for x in open("/tmp/fj_wip.txt").read().split())
for i in json.load(sys.stdin):
    labels=[l["name"] for l in i.get("labels") or []]
    if "🧊 parked" not in labels: continue
    print(i["number"],"|",i["title"],"|",",".join(labels),"|",i["created_at"],"|",(i.get("user") or {}).get("login","?"),"|","WIP" if i["number"] in wip else "")'

# then, per parked issue number, its most recent reason
tea api --login git-home "repos/$repo/issues/<n>/comments" \
  | python3 -c '
import sys,json
reasons=[c["body"] for c in json.load(sys.stdin) if c.get("body","").startswith("🧊 parked:")]
print(reasons[-1].split("\n")[0] if reasons else "—")'
```

> Client-side filtering is used deliberately: `labels=🧊 parked` in the query string
> isn't URL-encoded by `tea api`, so the space+emoji breaks the request.

Show a compact table — number, title, labels, age (relative), author, open-PR
note, reason. No preamble. If there are none, just say so.

### unpark

Remove only the `🧊 parked` label, then confirm from a read-back:

```bash
tea issues edit <n> --login git-home --remove-labels "🧊 parked"

tea api --login git-home "repos/$repo/issues/<n>" | python3 -c '
import sys,json
i=json.load(sys.stdin)
print(i["number"], ",".join([l["name"] for l in i.get("labels") or []]), sep="\t")'
```

Report from the read-back. If `🧊 parked` is still present, say removal failed
and stop — do not continue to routing.

If the issue also has `needs-enrichment`, say so before routing. Then delegate:
read and follow `~/.claude/commands/route.md` (i.e. run `/route <n>`).
`/parked` must not reimplement route logic.

### repark

`repark` keeps labels as-is and appends a fresh reason comment:

```bash
tea comment <n> "🧊 parked: <reason>"
```

Then confirm from read-back:

```bash
tea api --login git-home "repos/$repo/issues/<n>/comments" | python3 -c '
import sys,json
comments=json.load(sys.stdin)
reasons=[c.get("body","") for c in comments if c.get("body","").startswith("🧊 parked:")]
print(reasons[-1].split("\n")[0] if reasons else "—")'
```

If no reason argument was provided, ask for one and stop. Never edit the issue
body and never edit a previous comment.

### review

Walk the parked issues from `list`, newest first, one at a time. For each issue:
show number, title, labels, age, open-PR note, and current reason; ask *still
valid to stay parked?* with options `unpark` / `repark` / `skip`.

- One issue at a time. No bulk actions.
- Never act without an explicit answer. Unanswered means skipped.
- `skip` is silent and never re-prompts.
- Stop cleanly when told to.
- Report a final tally: unparked, reparked, skipped, remaining.

My arguments:
$ARGUMENTS

If you hit a blocker (label filter param ignored, repo not resolvable), find a fix
and update this command for the future.

## Unknown host

Report the detected host and that no authed GitHub or Forgejo login matched it;
point at `gh auth login` / `tea login add`. Don't guess a forge.
