---
description: Assign an issue to a GitHub coding agent (@claude / @copilot) to implement it
argument-hint: "<issue-number> [copilot|claude] — agent defaults to claude"
---

Hand an existing issue to a GitHub **coding agent** so it opens a PR implementing it.
`$ARGUMENTS` is `<issue-number>` plus an optional agent (`copilot` or `claude`).

## Agent default — prefer `@claude`

If no agent is given, default to **claude** (`anthropic-code-agent`). Only pick
copilot (`copilot-swe-agent`) when the user explicitly asks for Copilot (or has
confirmed it's responsive in this repo).

## Preconditions — confirm before assigning

1. The issue is **open**, **not parked** (`🧊 parked`), and not already assigned to an agent —
   `gh issue view <N> --json state,labels,assignees`. If parked or already agent-owned, stop and say so.
2. The issue is **actionable** — it has clear scope/AC. If it's `❓ to-be-defined` or
   `needs-enrichment`, warn that the agent will likely produce a weak PR, and confirm before proceeding.
3. The chosen agent is **assignable** in this repo (see the suggestedActors query below); if it
   isn't listed, the GitHub app isn't installed — say so and stop.

## Post the implementation contract

Read `~/.claude/commands/gh/implementation-contract.md` and follow it: apply its
ordered detection rule to this issue, pick **one** variant, and post that variant
as an issue comment with `<N>` replaced by the issue number from `$ARGUMENTS`.

That file is the single source of truth for both the rule and the two contract
bodies — do not restate either here.

Before posting, print one line naming the variant chosen and the rule that selected
it, e.g. `contract: docs-only (rule 1 — AC says "no test is added or changed")`, so
the operator can correct it before the agent picks the issue up.

## Resolve the actor and assign

Bots can't be assigned via `gh issue edit --add-assignee` (it resolves logins as users).
Use the GraphQL `replaceActorsForAssignable` mutation with the bot's actor id:

```bash
n="<issue-number>"; agent="${1:-claude}"
case "$agent" in
  copilot) bot="copilot-swe-agent" ;;
  claude)  bot="anthropic-code-agent" ;;
  *) echo "agent must be 'copilot' or 'claude'"; exit 1 ;;
esac
owner="$(gh repo view --json owner -q .owner.login)"
name="$(gh repo view --json name -q .name)"

# Issue node id
issueId="$(gh api graphql -f owner="$owner" -f name="$name" -F n="$n" -f query='
query($owner:String!,$name:String!,$n:Int!){
  repository(owner:$owner,name:$name){ issue(number:$n){ id } } }' \
  --jq '.data.repository.issue.id')"

# Bot actor id (also proves the agent is assignable here)
botId="$(gh api graphql -f owner="$owner" -f name="$name" -f query='
query($owner:String!,$name:String!){
  repository(owner:$owner,name:$name){
    suggestedActors(capabilities:[CAN_BE_ASSIGNED], first:50){
      nodes{ login __typename ... on Bot{ id } ... on User{ id } } } } }' \
  --jq ".data.repository.suggestedActors.nodes[] | select(.login==\"$bot\") | .id")"
[ -z "$botId" ] && { echo "Agent '$bot' is not assignable in this repo (app not installed)."; exit 1; }

# Assign (replaceActorsForAssignable handles bot actors; replaces existing assignees)
gh api graphql -f assignableId="$issueId" -f actorId="$botId" -f query='
mutation($assignableId:ID!,$actorId:ID!){
  replaceActorsForAssignable(input:{assignableId:$assignableId, actorIds:[$actorId]}){
    assignable{ ... on Issue{ number assignees(first:10){ nodes{ login } } } } } }' \
  --jq '.data.replaceActorsForAssignable.assignable | "assigned #\(.number) → \([.assignees.nodes[].login]|join(", "))"'
```

## After

Print the issue number, the agent assigned, and the issue URL. Note that the agent works
on its **own branch** and opens a (usually draft) PR — watch for the 👀 reaction as the
signal it picked the task up. Review its PR later with `/gh:review`. Don't merge anything.

### If you set up a monitor to wait for "ready to review"

Don't gate on `isDraft == false` or the title losing a `[WIP]`/`WIP` prefix. Observed
with `anthropic-code-agent`: it pushed its final commit and requested review while
leaving the PR as `isDraft: true` with `[WIP]` still in the title — those are cosmetic
leftovers of its workflow, not an in-progress indicator. A monitor gated on the draft
flag or title text will poll forever and never fire even though the agent finished
minutes earlier.

Poll the PR's timeline for a `review_requested` event (or a terminal `state != OPEN`)
as the exit condition instead:

```bash
owner="$(gh repo view --json owner -q .owner.login)"; name="$(gh repo view --json name -q .name)"
gh api "repos/$owner/$name/issues/<PR_NUMBER>/timeline" --paginate \
  --jq '.[] | select(.event=="review_requested") | .created_at'
```

The GitHub web UI's Agents tab (`https://github.com/<owner>/<repo>/agents?author=<you>`)
shows a plain "Completed Xm ago" status for the underlying agent task too — quicker
to eyeball manually than polling the API. (Only verified against `anthropic-code-agent`
so far — treat the same behavior for `copilot-swe-agent` as unconfirmed until observed.)

If there's no `gh`/repo context, say so and stop.
