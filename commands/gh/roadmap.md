---
description: List and promote roadmap issues — list | promote <n> to <milestone> | defer <n> "<reason>"
argument-hint: list | promote <n> to <milestone> | defer <n> "<reason>"
---

Manage roadmap issues in the current GitHub repo with **`gh`**.

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

## promote

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
After both read-backs confirm, offer `/gh:route <n>` (read and follow
`~/.claude/commands/gh/route.md`) rather than running it automatically.

## defer

`defer <n> "<reason>"` appends a roadmap reason comment and keeps labels unchanged:

```bash
gh issue comment <n> --body "roadmap: <reason>"
gh issue view <n> --json comments --jq '.comments | last | .body | split("\n")[0]'
```

If no reason argument was provided, ask for one and stop. Never edit the issue body
and never edit a previous comment.

## No forge context

If `gh` isn't on `PATH`, isn't authenticated, or the cwd isn't a GitHub clone, say
which of those it is, point at `gh auth login`, and stop.

My arguments:
$ARGUMENTS

---

If you hit a blocker (missing auth, renamed fields, or a milestone write/read-back
mismatch), find a fix and update this command for the future.
