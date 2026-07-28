---
description: List and triage parked issues (🧊 parked) — list | unpark <n> | repark <n> "<reason>" | review
argument-hint: list | unpark <n> | repark <n> "<reason>" | review
---

Manage parked issues in the current GitHub repo with **`gh`**.

## Parse the verb

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

## list

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
        comments(last:100){nodes{body}}
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

## unpark

Remove only the `🧊 parked` label, then confirm from a read-back:

```bash
gh issue edit <n> --remove-label "🧊 parked"
gh issue view <n> --json number,labels --jq '[.number, ([.labels[].name] | join(","))] | @tsv'
```

Report from the read-back. If `🧊 parked` is still present, say the removal
failed and stop — do not continue to routing.

If the issue also has `needs-enrichment`, say so before routing. Then delegate:
read and follow `~/.claude/commands/gh/route.md` (i.e. run `/gh:route <n>`).
`/parked` must not reimplement route logic.

## repark

`repark` keeps labels as-is and appends a fresh reason comment:

```bash
gh issue comment <n> --body "🧊 parked: <reason>"
```

Then confirm from read-back:

```bash
gh issue view <n> --json comments --jq '.comments | last | .body // "—" | split("\n")[0]'
```

If no reason argument was provided, ask for one and stop. Never edit the issue
body and never edit a previous comment.

## review

Walk the parked issues from `list`, newest first, one at a time. For each issue:
show number, title, labels, age, and current reason; ask *still valid to stay
parked?* with options `unpark` / `repark` / `skip`.

- One issue at a time. No bulk actions.
- Never act without an explicit answer. Unanswered means skipped.
- `skip` is silent and never re-prompts.
- Stop cleanly when told to.
- **`unpark` chosen mid-walk is deferred**, not run immediately — running
  `/gh:route` per issue would derail the one-at-a-time walk with a heavy
  interactive analysis. Record the issue number and continue the walk; after the
  walk completes, run `/gh:route <n>` for each unparked issue number and list
  those numbers in the tally.
- Report a final tally: unparked, reparked, skipped, remaining.

My arguments:
$ARGUMENTS
