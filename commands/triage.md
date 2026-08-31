---
description: Open issues ordered bugs/fixes first, then quick wins — with milestone, minus parked/roadmap
---

Detect the forge, then run the matching section below.

```bash
source "$HOME/.claude/scripts/lib/detect-forge.sh"
detect_forge
```

## GitHub

Fetch open issues with body, labels, and **milestone**, dropping the ones that
aren't current work — **not parked** (no `🧊 parked` label) and **not roadmap**
(no `roadmap` label). Parked issues are deliberately deferred; list them with
`/parked`. Roadmap issues are planned for a future milestone rather than current
work; list them with `/roadmap`.

Do the exclusion **in the query, not by eye** — a `--jq` filter can't be skipped,
a prose instruction can:

```bash
gh issue list --state open --limit 100 \
  --json number,title,labels,body,createdAt,milestone \
  --jq 'map(select([.labels[].name] | index("🧊 parked") | not))
    | map(select([.labels[].name] | index("roadmap") | not))
    | .[] | [
        .number,
        (.milestone.title // "-"),
        ((.milestone.dueOn // "-") | .[0:10]),
        .title,
        (([.labels[].name] | join(",")) | if . == "" then "-" else . end),
        ((.body // "") | length),
        ((.body // "") | gsub("\n"; " ") | .[0:200])
      ] | @tsv'
```

Two field-shape traps: `gh issue list --json labels` yields `[.labels[].name]` —
**not** `.labels.nodes[].name`, which is the GraphQL shape `/issues` uses — and
the due date is `.milestone.dueOn` (camelCase), unlike Forgejo's `due_on`.

The body is truncated to a 200-char preview, so its **full character count is
emitted as its own column** — that length, not the preview, is the "short and
well-defined" signal bucket 2 relies on. Never judge scope from the preview.

**Truncation guard:** the fetch caps at 100 *before* jq drops parked/roadmap, so
the visible count is twice-removed from the repo total. If 100 issues came back
pre-filter, say the list may be incomplete rather than implying it is the whole
set.

**WIP is deliberately not excluded here.** Dropping issues with an open linked PR
needs the GraphQL timeline query that `/issues` runs; `/triage` stays a single
cheap `gh issue list` call. Use `/issues` when you want the WIP filter too.

Then present them ordered for triage:

1. **Bugs / fixes first** — issues whose labels or title/body signal a defect
   (labels like `bug`, `type:bug`, `defect`, `regression`, `fix`; or clear
   bug wording).
2. **Then quick wins** — remaining low-complexity / small-scope issues
   (short, well-defined; labels like `good-first-issue`, `chore`, `docs`,
   `small`). Easiest first, by your judgment from title/body/labels.
3. **Everything else** after that.

For each: number, title, key labels, **milestone + due date**, body length, and a 3–6 word
reason it's in that bucket. Milestone is **shown, not sorted on** — the buckets
stay bugs → quick wins → rest, because triage asks *what's broken and what's
cheap*, not *when does it ship*. Render an issue with no milestone as
`no milestone` rather than a blank column, and close with a count of those — they
are what `/milestone triage` walks. Be concise — this is a reading aid, don't
start any work.

## Forgejo

Fetch open issues (with body, labels, and milestone) from the current Forgejo
repo, then present them ordered for triage. Same exclusions as the GitHub section
— **not parked**, **not roadmap** — applied in the query, not by eye.

### Forgejo access

Target the homelab Forgejo (`git.home.freaxnx01.ch`) via **`tea`** (login
`git-home`):

```bash
url=$(git remote get-url origin); url=${url%.git}
repo=$(echo "$url" | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#')
tea api --login git-home "repos/$repo/issues?state=open&type=issues&limit=100&sort=created&order=desc" \
  | python3 -c '
import sys, json
for i in json.load(sys.stdin):
    labels = [l["name"] for l in i.get("labels") or []]
    if "🧊 parked" in labels or "roadmap" in labels: continue
    m = i.get("milestone") or {}
    print(i["number"], "||", m.get("title") or "-", "||", (m.get("due_on") or "-")[:10],
          "||", i["title"], "||", ",".join(labels) or "-",
          "||", len(i.get("body") or ""),
          "||", (i.get("body") or "")[:200].replace(chr(10), " "))'
```

Forgejo spells the due date `due_on` (snake_case), unlike `gh`'s `dueOn`. As in
the GitHub half, the body is a 200-char preview and its **full length is its own
column** — that is the "short and well-defined" signal for bucket 2, not the
preview. The `limit=100` caps the fetch *before* the label skip, so if 100 came
back pre-filter, say the list may be incomplete.

### Ordering

Present them ordered for triage:

1. **Bugs / fixes first** — issues whose labels or title/body signal a defect
   (labels like `bug`, `type:bug`, `defect`, `regression`, `fix`; or clear bug
   wording).
2. **Then quick wins** — remaining low-complexity / small-scope issues (short,
   well-defined; labels like `good-first-issue`, `chore`, `docs`, `small`). Easiest
   first, by your judgment from title/body/labels.
3. **Everything else** after that.

For each: number, title, key labels, **milestone + due date**, body length, and a 3–6 word
reason it's in that bucket. Milestone is **shown, not sorted on** — the buckets
stay bugs → quick wins → rest. Render an issue with no milestone as
`no milestone` rather than a blank column, and close with a count of those — they
are what `/fj:milestone triage` walks. Be concise — this is a reading aid, don't
start any work.

## Unknown host

Report the detected host and that no authed GitHub or Forgejo login matched
it; point at `gh auth login` / `tea login add`. Don't guess a forge.
