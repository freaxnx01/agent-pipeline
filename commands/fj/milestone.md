---
description: List, create, or assign Forgejo milestones — list | new <name> [due <date>] | assign <issue> to <name>
argument-hint: list | new <name> [due <date>] | assign <issue> to <name>
---

Manage milestones in the current Forgejo repo with **`tea`** (login `git-home`).

A milestone is the *when does this ship* axis: repo-scoped, no nesting, one due
date, at most one per issue. It is not an epic (*what work, what scope*) and not a
label (*a filter tag*) — see `docs/glossary.md` in agent-workflow.

## Parse the verb

**Three verbs only** — `list`, `new`, `assign`.

- No arguments at all → treat it as `list`.
- A first word that isn't one of the three → print the three usage forms below and
  **stop**. Don't guess the intent, don't fuzzy-match.

```text
/milestone list
/milestone new <name> [due <date>]
/milestone assign <issue> to <name>
```

## Two rules that apply to every verb

> **Report every write from a read-back — never from the exit code.** A forge CLI
> can exit `0` while silently dropping a field the token lacked permission for —
> that has already happened in this workflow with a label on issue creation. After
> `new` and `assign`, re-read and report what the read-back says.

> **`tea api` has no `--jq`** — pipe into `python3 -c`, same idiom as
> `/fj:issues` and `/fj:prs`. `tea` subcommands infer the repo from the cwd, but
> `tea api` needs the explicit `owner/name` path below.

```bash
url=$(git remote get-url origin); url=${url%.git}
repo=$(echo "$url" | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#')   # e.g. freax/hello-forgejo
```

## list

Open milestones, each with its **open issues nested underneath**. Milestones with
zero issues are shown too — that's the point, they're what you want to see right
after `/milestone new`. Issues with *no* milestone are **not** listed; that's what
`/fj:issues` is for.

Two calls, grouped locally — cost is fixed regardless of milestone count, and the
milestone call returns the API's own issue counts to cross-check against:

```bash
tea api --login git-home "repos/$repo/milestones?state=open" | python3 -c '
import sys, json
for m in sorted(json.load(sys.stdin), key=lambda x: x.get("due_on") or "9999"):
    print(m["title"], m.get("due_on") or "-", m.get("open_issues", 0), m.get("closed_issues", 0), sep="\t")'

tea api --login git-home "repos/$repo/issues?state=open&type=issues&limit=100" | python3 -c '
import sys, json
for i in json.load(sys.stdin):
    m = i.get("milestone") or {}
    print(m.get("title") or "-", i["number"], i["title"], sep="\t")'
```

Group the second output by milestone title and render a compact tree — title, due
date, `open/closed` counts, then the issues. No preamble. If there are no open
milestones, just say so.

**Truncation guard.** Print the API's `open_issues` count next to the number of
issues actually shown. When they differ, say so *and* say what it can mean — the
issue query hit its `limit=100`, **or** pull requests are assigned to that
milestone (`open_issues` counts issues *and* PRs together, while the query above
passes `type=issues`). Don't claim truncation when it might be PRs.

## new

```bash
# with a due date — tea parses loose date strings, so a bare YYYY-MM-DD is fine
tea milestones create --login git-home --title "<name>" --deadline "<YYYY-MM-DD>"

# no due date given — omit the flag entirely, don't pass an empty value
tea milestones create --login git-home --title "<name>"
```

Then **read back** and report from the read-back:

```bash
tea api --login git-home "repos/$repo/milestones?state=open" | python3 -c '
import sys, json
want = "<name>"
for m in json.load(sys.stdin):
    if m["title"] == want:
        print(m["id"], m["title"], m.get("due_on") or "-", sep="\t")'
```

Confirm the deadline that came back is the date I asked for. If the title already
exists, report the existing milestone and **stop**; don't retry with a variant name.

## assign

`tea milestones issues add` takes the milestone **name** — use it rather than a raw
`tea api -X PATCH …/issues/<n>`, which would need a name→id lookup first:

```bash
tea milestones issues add --login git-home "<name>" <issue>
```

Then **read back**:

```bash
tea api --login git-home "repos/$repo/issues/<issue>" | python3 -c '
import sys, json
i = json.load(sys.stdin)
m = i.get("milestone") or {}
print(i["number"], m.get("title") or "-", sep="\t")'
```

If the milestone name doesn't exist, print the open milestones (the `list` call
above) and stop. **No fuzzy matching, no silent creation.**

## No forge context

If `tea` isn't on `PATH`, there's no `git-home` login, or the remote isn't the
homelab Forgejo (`git.home.freaxnx01.ch`), say which of those it is, point at
`tea login add`, and stop.

My arguments:
$ARGUMENTS

---

`tea`'s milestone flags here were verified from tea's own source
(`cmd/milestones/*.go`, `cmd/flags/issue_pr.go`), not from a live run — `tea` wasn't
installed on the machine where this command was written. If a flag turns out
different (this repo already has precedent: `tea issues create` uses
`--description`/`-d`, not `--body`), find the right one and **update this command**
so the next run doesn't rediscover it.
