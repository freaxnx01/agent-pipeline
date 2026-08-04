---
description: List open issues that are not WIP (no open PR), not parked, and not roadmap, newest first
---

Detect the forge, then run the matching section below.

```bash
source "$HOME/.claude/scripts/lib/detect-forge.sh"
detect_forge
```

## GitHub

List open issues in the current repo that are **not work-in-progress** — i.e. have no **open** PR — **not parked** (no `🧊 parked` label), and **not roadmap** (no `roadmap` label) — **newest first**. Issues whose only linked PR is already merged still count as not-WIP and are shown. Parked issues are deliberately deferred; list them with `/parked`. Roadmap issues are planned for a future milestone rather than current work; list them with `/roadmap`.

`gh issue list` can't see PR links, so query the timeline via GraphQL and drop any issue that has an open linked PR (a `Closes #`/cross-reference or a development-linked PR still in flight), then drop any issue carrying the `🧊 parked` label, then any carrying the `roadmap` label:

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
        timelineItems(itemTypes:[CROSS_REFERENCED_EVENT,CONNECTED_EVENT], first:50){
          nodes{
            ... on CrossReferencedEvent{source{... on PullRequest{state}}}
            ... on ConnectedEvent{subject{... on PullRequest{state}}}
          }
        }
      }
    }
  }
}' \
  --jq '.data.repository.issues.nodes
    | map(select([.timelineItems.nodes[] | (.source // .subject) | .state] | map(select(. == "OPEN")) | length == 0))
    | map(select([.labels.nodes[].name] | index("🧊 parked") | not))
    | map(select([.labels.nodes[].name] | index("roadmap") | not))
    | .[] | {number, title, labels: [.labels.nodes[].name], age: .createdAt, author: .author.login}'
```

Show a compact table — number, title, labels, age (relative), author. No preamble.
If there are none, just say so.

## Forgejo

List open issues in the current Forgejo repo that are **not work-in-progress** —
i.e. have no **open** linked PR — **not parked** (no `🧊 parked` label), and **not
roadmap** (no `roadmap` label) — **newest first**. Issues whose only linked PR is
already merged/closed still count as not-WIP and are shown. Parked issues are
deliberately deferred; list them with `/parked`. Roadmap issues are planned for
a future milestone rather than current work; list them with `/roadmap`.

### Forgejo access

Target the homelab Forgejo (`git.home.freaxnx01.ch`) via **`tea`** (login
`git-home`). Prefer `tea` subcommands; use `tea api [-X METHOD] [-f k=v | -d JSON]
<path>` for anything tea lacks. The repo resolves from the cwd git remote — pass
`--repo owner/name` when outside a clone. Forgejo has **no GraphQL**, so PR↔issue
links are derived from REST.

Resolve `owner/name` from the clone's remote (needed for `tea api` paths):

```bash
url=$(git remote get-url origin); url=${url%.git}
repo=$(echo "$url" | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#')   # e.g. freax/hello-forgejo
```

> `tea` infers the repo from the cwd for its subcommands, but `tea api` needs the
> explicit path above. Note `tea issues create` uses `--description`/`-d` (not
> `--body`); comments are `tea comment <index> "body"`.

### Approach

`tea issues list` can't tell you which issues have an open PR. Forgejo has no
GraphQL timeline, so derive WIP from the open PRs themselves: an issue is WIP if an
**open** PR closes it (`closes/fixes/resolves #N` in the PR title or body, or a
same-named `issue-N-*` branch). Then drop parked and roadmap issues.

```bash
# repo resolved as above
# 1) issue numbers referenced by OPEN pull requests
tea api --login git-home "repos/$repo/pulls?state=open&limit=50&type=pulls" \
  | python3 -c '
import sys,json,re
prs=json.load(sys.stdin)
wip=set()
pat=re.compile(r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)", re.I)
for p in prs:
    for n in pat.findall((p.get("title") or "")+" "+(p.get("body") or "")): wip.add(int(n))
    m=re.match(r"issue-(\d+)", p.get("head",{}).get("ref","") or "")
    if m: wip.add(int(m.group(1)))
print(" ".join(map(str,sorted(wip))))' > /tmp/fj_wip.txt
# 2) open issues, newest first, minus WIP, minus parked, minus roadmap
tea api --login git-home "repos/$repo/issues?state=open&type=issues&limit=100&sort=created&order=desc" \
  | python3 -c '
import sys,json
wip=set(int(x) for x in open("/tmp/fj_wip.txt").read().split())
for i in json.load(sys.stdin):
    labels=[l["name"] for l in i.get("labels") or []]
    if i["number"] in wip or "🧊 parked" in labels or "roadmap" in labels: continue
    print(i["number"], "|", i["title"], "|", ",".join(labels) or "-", "|", i["created_at"], "|", (i.get("user") or {}).get("login","?"))'
```

Show a compact table — number, title, labels, age (relative), author. No preamble.
If there are none, just say so.

### Forgejo blockers

If you hit a blocker (repo not resolvable, `tea` login missing, PR-link regex
misses a convention this repo uses), find a fix and update this command for the
future.

## Unknown host

Report the detected host and that no authed GitHub or Forgejo login matched
it; point at `gh auth login` / `tea login add`. Don't guess a forge.
