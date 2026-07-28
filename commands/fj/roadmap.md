---
description: List and promote roadmap Forgejo issues — list | promote <n> to <milestone> | defer <n> "<reason>"
argument-hint: list | promote <n> to <milestone> | defer <n> "<reason>"
---

Manage roadmap issues in the current Forgejo repo with **`tea`** (login
`git-home`).

## Forgejo access

Target the homelab Forgejo (`git.home.freaxnx01.ch`) via **`tea`** (login
`git-home`). Resolve `owner/name` from the clone's remote (needed for `tea api`):

```bash
url=$(git remote get-url origin); url=${url%.git}
repo=$(echo "$url" | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#')
```

## Parse the verb

**Three verbs only** — `list`, `promote`, `defer`.

- No arguments at all → treat it as `list`.
- A first word that isn't one of the three → print the three usage forms below and
  **stop**. Don't guess the intent, don't fuzzy-match.

```text
/roadmap list
/roadmap promote <n> to <milestone>
/roadmap defer <n> "<reason>"
```

## list

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

## promote

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

After both read-backs confirm, offer `/fj:route <n>` (read and follow
`~/.claude/commands/fj/route.md`) rather than running it automatically.

## defer

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

## No forge context

If `tea` isn't on `PATH`, there's no `git-home` login, or the remote isn't the
homelab Forgejo (`git.home.freaxnx01.ch`), say which of those it is, point at
`tea login add`, and stop.

My arguments:
$ARGUMENTS

---

If you hit a blocker (repo not resolvable, `tea` flags differ, or read-back doesn't
match the write), find a fix and update this command for the future.
