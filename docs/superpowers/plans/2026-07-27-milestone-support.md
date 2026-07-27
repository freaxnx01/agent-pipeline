# Milestone Support in the Slash Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/milestone` command (router + `gh:` + `fj:` implementations) with three verbs — `list`, `new`, `assign` — and let `/gh:new` / `/fj:new` set a milestone when the notes name one (#172).

**Architecture:** Three new prompt files following the established router pattern — `commands/milestone.md` detects the forge from the `origin` remote and delegates; `commands/gh/milestone.md` and `commands/fj/milestone.md` hold all the logic and stay the single source of truth. One file per forge with the verb parsed from natural language (not one file per verb). `setup/link-commands.sh` discovers `commands/**/*.md` with `find`, so no manifest changes are needed. Two existing files (`gh/new.md`, `fj/new.md`) get their "don't milestone unless I said so" clause rewritten so milestone becomes an *if-I-said-so* field.

**Tech Stack:** Claude Code slash-command prompt files (Markdown + YAML front-matter), `gh` CLI (v2.92.0) incl. `gh api`, `tea` CLI (login `git-home`), `jq` via `gh --jq`, `python3` for the Forgejo side.

**Spec:** [`docs/superpowers/specs/2026-07-27-milestone-support-design.md`](../specs/2026-07-27-milestone-support-design.md)

## Global Constraints

Every task's requirements implicitly include this section.

- **There is no automated validation of command `.md` files in this repo.** `just lint` runs `actionlint` + `shellcheck` over `.github/workflows/`, `scripts/`, and `tests/` only; nothing parses command front-matter and nothing executes the bash inside `commands/**/*.md`. **Do not add a test framework, a fixture, or a `tests/` entry for these files.** Each task's verification is the concrete shell check written into its steps (file exists, front-matter present, expected strings present, installer copies the file).
- **The two live-forge smoke tests from the spec are deliberately NOT part of any task.** They make real writes (create a milestone, assign #172, create two throwaway issues) and this plan is executed by the agent-workflow in CI. They live in the **Manual verification** section at the end, to be run locally by a human after merge.
- **Three verbs only** — `list`, `new`, `assign`. Do **not** add `unassign`, `close`, `reopen`, `delete`, or `edit`, even though both CLIs expose them.
- **Verb-parsing contract, identical in all three files:** no arguments at all → treat as `list`; a first word that is not `list`/`new`/`assign` → print the three usage forms and stop without guessing.
- **Every write is reported from a read-back, never from the exit code.** Verbatim rationale to carry into the files: while filing #172, `gh issue create --label needs-enrichment` printed the URL and exited `0` while the label was silently dropped (the token lacked label-write). `new` and `assign` must confirm from a follow-up read.
- **GitHub due-date normalization:** a bare `YYYY-MM-DD` becomes `YYYY-MM-DDT12:00:00Z` — **midday UTC, deliberately, not midnight**, so no viewer timezone offset rolls the rendered date back a day. Forgejo's `--deadline` takes the bare date unchanged.
- **The due date is optional on both forges** — omit the flag/field entirely when the user gave no date, never pass an empty value.
- **`tea` is always invoked with `--login git-home`.** Its issue-body flag is `--description`/`-d`, **not** `--body`.
- **`tea api` has no `--jq`** → pipe into `python3 -c`, matching `commands/fj/issues.md` and `commands/fj/prs.md`. `gh` uses its built-in `--jq`.
- **`gh milestone` does not exist** (`unknown command "milestone" for "gh"`). Creation and listing go through `gh api`; only assignment has a first-class flag (`gh issue edit -m`).
- **Each new command file ends with the self-improving footer** — the same shape as `commands/fj/new.md:34-37` and `commands/new.md:40-43`: a horizontal rule, then one sentence telling the command to fix itself and update the file when it hits a blocker.
- **Every command file starts with YAML front-matter containing `description:` and `argument-hint:`.** The `description:` shows in the `/` autocomplete menu.
- Reference `#172` in every commit message; use Conventional Commits (`feat(commands): …`, `docs(commands): …`).
- Do not modify `/issues`, `/triage`, `/route`, `/done`, `/parked`, any workflow under `.github/workflows/`, or `setup/link-commands.sh`.

## File Structure

| File | Responsibility |
|---|---|
| `commands/gh/milestone.md` | **Create.** GitHub milestone command — `list` / `new` / `assign` via `gh` + `gh api`. Single source of truth for the GitHub side. |
| `commands/fj/milestone.md` | **Create.** Forgejo milestone command — same three verbs via `tea` (login `git-home`) + `tea api` + `python3`. |
| `commands/milestone.md` | **Create.** Forge router — host detection snippet copied verbatim from `commands/new.md`, then delegate. Holds no logic of its own. |
| `commands/gh/new.md` | **Modify.** Line 13's "Don't assign, milestone, or add other labels unless I said so" → milestone becomes an if-I-said-so field; add `-m` to the guidance. |
| `commands/fj/new.md` | **Modify.** Same clause (line 13) plus the `-m` flag in the example `tea issues create` block. |
| `commands/README.md` | **Modify.** Add `/milestone` to the forge-routers line and `/gh:milestone` / `/fj:milestone` to the per-forge lines. |
| `README.md` | **Modify.** Add the command to the `commands/` tree sketch (the `fj/`, `gh/`, and router lines). |
| `commands/commands.md` | **Modify.** Add one release-scoped example workflow chain. (It enumerates commands dynamically at runtime — there is no static list in it to update.) |
| `CHANGELOG.md` | **Modify.** `[Unreleased]` → `### Added`. |

**Note on `commands/commands.md` (AC 8):** the acceptance criterion says "command lists are updated in … `commands/commands.md`". That file contains **no static command list** — it is a prompt that scans `~/.claude/commands` and `./.claude/commands` with `find` at runtime, so `/milestone` appears there automatically once installed. Its only hand-maintained surface is the **Example workflows** cheat-sheet. Task 5 therefore adds a chain there rather than a list entry; that is what satisfies AC 8 for this file.

---

### Task 1: GitHub milestone command

**Files:**
- Create: `commands/gh/milestone.md`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the file `commands/gh/milestone.md`, which Task 3's router delegates to by path (`~/.claude/commands/gh/milestone.md`). Its verb contract (`list` / `new` / `assign`, bare → `list`, unknown → usage + stop) is repeated by Tasks 2 and 3.

- [ ] **Step 1: Create the file with exactly this content**

````markdown
---
description: List, create, or assign GitHub milestones — list | new <name> [due <date>] | assign <issue> to <name>
argument-hint: list | new <name> [due <date>] | assign <issue> to <name>
---

Manage milestones in the current GitHub repo with **`gh`**.

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

> **`gh milestone` does not exist** (`unknown command "milestone" for "gh"`). Only
> assignment has a first-class flag; creation and listing go through `gh api`.

> **Report every write from a read-back — never from the exit code.** This is not
> hypothetical: `gh issue create --label needs-enrichment` has been observed printing
> the issue URL and exiting `0` while silently dropping the label, because the token
> lacked label-write permission. After `new` and `assign`, re-read and report what
> the read-back says, not what the write returned.

Resolve the repo once — `gh api` paths need it:

```bash
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

## list

Open milestones, each with its **open issues nested underneath**. Milestones with
zero issues are shown too — that's the point, they're what you want to see right
after `/milestone new`. Issues with *no* milestone are **not** listed; that's what
`/issues` is for.

Two calls, grouped locally — cost is fixed regardless of milestone count, and the
milestone call returns the API's own issue counts to cross-check against:

```bash
gh api "repos/$repo/milestones?state=open&sort=due_on&direction=asc" \
  --jq '.[] | [.title, (.due_on // "-"), .open_issues, .closed_issues] | @tsv'

gh issue list --state open --limit 200 --json number,title,milestone \
  --jq '.[] | [(.milestone.title // "-"), .number, .title] | @tsv'
```

Group the second output by milestone title and render a compact tree — title, due
date, `open/closed` counts, then the issues. No preamble. If there are no open
milestones, just say so.

**Truncation guard.** Print the API's `open_issues` count next to the number of
issues actually shown. When they differ, say so *and* say what it can mean — the
issue query hit its 200 limit, **or** pull requests are assigned to that milestone
(`open_issues` counts issues *and* PRs together, while `gh issue list` excludes
PRs). Don't claim truncation when it might be PRs.

## new

```bash
# with a due date — normalize a bare YYYY-MM-DD to MIDDAY UTC, deliberately:
# midnight would let a viewer timezone offset render the previous day.
gh api "repos/$repo/milestones" \
  -f title="<name>" \
  -f due_on="<YYYY-MM-DD>T12:00:00Z"

# no due date given — omit the field entirely, don't pass an empty value
gh api "repos/$repo/milestones" -f title="<name>"
```

Then **read back** and report from the read-back:

```bash
gh api "repos/$repo/milestones?state=open" \
  --jq '.[] | select(.title == "<name>") | [.number, .title, (.due_on // "-")] | @tsv'
```

Confirm the `due_on` that came back is the date I asked for. A `422` with
`already_exists` means the title is taken — report the existing milestone and
**stop**; don't retry with a variant name.

## assign

```bash
gh issue edit <issue> --milestone "<name>"
```

Then **read back**:

```bash
gh issue view <issue> --json number,milestone --jq '[.number, (.milestone.title // "-")] | @tsv'
```

If the milestone name doesn't exist, `gh` rejects it — print the open milestones
(the `list` call above) and stop. **No fuzzy matching, no silent creation.**

## No forge context

If `gh` isn't on `PATH`, isn't authenticated, or the cwd isn't a GitHub clone, say
which of those it is, point at `gh auth login`, and stop.

My arguments:
$ARGUMENTS

---

If you hit a blocker (a `gh api` field renamed, `due_on` coming back a day off, a
token missing milestone-write permission), find a fix and update this command for
the future.
````

- [ ] **Step 2: Verify the file's structure**

Run:

```bash
head -4 commands/gh/milestone.md
grep -c 'T12:00:00Z' commands/gh/milestone.md
grep -q 'read-back' commands/gh/milestone.md && echo "read-back rule: OK"
grep -q '\$ARGUMENTS' commands/gh/milestone.md && echo "arguments passthrough: OK"
grep -qE '^(unassign|close|reopen|delete|edit)$' <(grep -oE '^## (unassign|close|reopen|delete|edit)$' commands/gh/milestone.md | sed 's/^## //') || echo "no extra verbs: OK"
```

Expected: front-matter with `description:` and `argument-hint:`; `T12:00:00Z` count ≥ 1; all three OK lines printed.

- [ ] **Step 3: Commit**

```bash
git add commands/gh/milestone.md
git commit -m "feat(commands): add /gh:milestone — list, new, assign (#172)"
```

---

### Task 2: Forgejo milestone command

**Files:**
- Create: `commands/fj/milestone.md`

**Interfaces:**
- Consumes: the verb contract defined in Task 1 (`list` / `new` / `assign`; bare → `list`; unknown → usage + stop). Keep the two sides behaviourally identical — same verbs, same output shape, same read-back rule.
- Produces: the file `commands/fj/milestone.md`, delegated to by Task 3's router.

**Why the CLI surface differs from the GitHub side:** `tea` has real milestone subcommands (`list`, `create`, `close`, `reopen`, `delete`, `issues` with `add`/`remove`), so `new` and `assign` use them instead of raw API calls. Assignment specifically uses `tea milestones issues add` because Forgejo's REST API takes a numeric milestone **id** while `gh issue edit -m` takes the **name** — the subcommand is name-based and avoids a name→id lookup on every assign. Listing still goes through `tea api` because the grouping needs the raw JSON.

- [ ] **Step 1: Create the file with exactly this content**

````markdown
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
````

- [ ] **Step 2: Verify the file's structure**

Run:

```bash
head -4 commands/fj/milestone.md
grep -q 'login git-home' commands/fj/milestone.md && echo "tea login: OK"
grep -q 'read-back' commands/fj/milestone.md && echo "read-back rule: OK"
grep -q '\$ARGUMENTS' commands/fj/milestone.md && echo "arguments passthrough: OK"
grep -q -- '--body' commands/fj/milestone.md && echo "FAIL: --body must not appear" || echo "no --body: OK"
python3 - <<'PY'
import re, sys
src = open("commands/fj/milestone.md").read()
for block in re.findall(r"python3 -c '\n(.*?)'", src, re.S):
    compile(block, "<embedded>", "exec")
print("embedded python compiles: OK")
PY
```

Expected: front-matter present; all OK lines printed; the embedded python snippets compile.

- [ ] **Step 3: Commit**

```bash
git add commands/fj/milestone.md
git commit -m "feat(commands): add /fj:milestone — list, new, assign (#172)"
```

---

### Task 3: Forge router + install check

**Files:**
- Create: `commands/milestone.md`
- Reference (do not modify): `commands/new.md:12-24` — the detection snippet is copied from there verbatim.

**Interfaces:**
- Consumes: `commands/gh/milestone.md` (Task 1) and `commands/fj/milestone.md` (Task 2), by installed path.
- Produces: `/milestone`, the user-facing entry point. Holds **no logic of its own** — the forge files stay the single source of truth.

- [ ] **Step 1: Create the file with exactly this content**

The detection block is character-for-character the one in `commands/new.md` — AC 7 requires the *same* snippet, so copy it, don't rewrite it.

````markdown
---
description: List, create, or assign milestones — auto-routes to GitHub or Forgejo by remote
argument-hint: list | new <name> [due <date>] | assign <issue> to <name>
---

Route to the forge-specific **milestone** command based on the `origin` remote host,
then follow it exactly. This command holds no logic of its own — `/gh:milestone` and
`/fj:milestone` remain the single source of truth.

## Detect the forge (generic host-matching)

```bash
# Host from origin, handling https://, ssh://, and scp-style git@host:path remotes
host=$(git remote get-url origin 2>/dev/null | sed -E 's#^[a-zA-Z]+://##; s#^[^@/]*@##; s#[:/].*##')
if gh auth token --hostname "$host" >/dev/null 2>&1; then
  echo "github  ($host)"     # a GitHub / GHES host gh is logged into
elif tea logins list 2>/dev/null | grep -qiF "$host"; then
  echo "forgejo ($host)"     # matches a tea (Forgejo/Gitea) login
elif [ "$host" = "github.com" ]; then
  echo "github  ($host)"     # fallback: canonical GitHub host, even if gh isn't authed
else
  echo "unknown ($host)"
fi
```

## Then

- **github** → read and follow `~/.claude/commands/gh/milestone.md` (i.e. run `/gh:milestone`).
- **forgejo** → read and follow `~/.claude/commands/fj/milestone.md` (i.e. run `/fj:milestone`).
- **unknown** → report the detected host and that no authed GitHub or Forgejo login
  matched it; point at `gh auth login` / `tea login add`. Don't guess a forge.

The target command takes a verb — `list`, `new`, or `assign`. Pass it these
arguments unchanged; the forge file owns the parsing, including "no arguments →
`list`" and "unrecognized verb → print the usage forms and stop":

$ARGUMENTS

Announce the chosen forge in one line (e.g. `→ GitHub (github.com)`), then carry out
that command.

---

If detection misfires (new host, an SSH `Host` alias that hides the real domain,
`gh`/`tea` not on PATH), fix the snippet here and update this command for the future.
````

- [ ] **Step 2: Verify the detection snippet is identical to `commands/new.md`'s**

Run:

```bash
extract() { sed -n '/^host=\$(git remote get-url origin/,/^fi$/p' "$1"; }
diff <(extract commands/new.md) <(extract commands/milestone.md) && echo "snippet identical: OK"
```

Expected: no diff output, then `snippet identical: OK`.

- [ ] **Step 3: Verify all three files install**

Run:

```bash
setup/link-commands.sh --no-sync
ls -l ~/.claude/commands/milestone.md ~/.claude/commands/gh/milestone.md ~/.claude/commands/fj/milestone.md
for f in ~/.claude/commands/milestone.md ~/.claude/commands/gh/milestone.md ~/.claude/commands/fj/milestone.md; do
  sed -n '1,4p' "$f" | grep -q '^description: ' && sed -n '1,4p' "$f" | grep -q '^argument-hint: ' \
    && echo "front-matter OK: $f"
done
```

Expected: all three files listed by `ls`, and three `front-matter OK:` lines. `--no-sync` is required — without it the installer pulls `main` and would install the pre-change files.

If the CI environment has no `$HOME/.claude`, the installer creates it; if `setup/link-commands.sh` cannot run at all there, record that in the commit message and leave this check for the manual verification section.

- [ ] **Step 4: Commit**

```bash
git add commands/milestone.md
git commit -m "feat(commands): add /milestone forge router (#172)"
```

---

### Task 4: Milestone on issue creation

**Files:**
- Modify: `commands/gh/new.md:13`
- Modify: `commands/fj/new.md:13` and its `tea issues create` example block (lines 21-24)

**Interfaces:**
- Consumes: the `/milestone new` behaviour from Tasks 1-2 — when the notes name a milestone that doesn't exist, `/new` asks and then does what `/milestone new` does.
- Produces: nothing later tasks depend on.

The existing "unless I said so" clause **stays**. Milestone simply joins what counts as *said so*, so `/new` remains a single round trip with no added question in the common case.

- [ ] **Step 1: Edit `commands/gh/new.md`**

Replace line 13:

```markdown
- Don't assign, milestone, or add other labels unless I said so.
```

with:

```markdown
- **Milestone**: only if my notes name one — then pass it as `-m "<name>"`. If that
  milestone doesn't exist yet, **ask** me before creating it (and ask for a due
  date); never create one silently. If my notes don't name a milestone, don't set
  one and don't ask.
- Don't assign or add other labels unless I said so.
```

And replace lines 15-16:

````markdown
After creating, print the issue number, title, and URL. If there's no `gh`/repo
context, say so and stop.
````

with:

````markdown
```bash
gh issue create --title "<concise title>" --body-file <notes> \
  --label needs-enrichment [-m "<milestone>"]
```

After creating, print the issue number, title, and URL — **read back** rather than
trusting the exit code (`gh issue create` has been seen exiting `0` while silently
dropping the label). If there's no `gh`/repo context, say so and stop.

```bash
gh issue view <number> --json number,labels,milestone
```
````

- [ ] **Step 2: Edit `commands/fj/new.md`**

Replace line 13 with the same milestone clause, adapted:

```markdown
- **Milestone**: only if my notes name one — then pass it as `-m "<name>"`. If that
  milestone doesn't exist yet, **ask** me before creating it (and ask for a due
  date, via `tea milestones create --login git-home --title … --deadline …`); never
  create one silently. If my notes don't name a milestone, don't set one and don't
  ask.
- Don't assign or add other labels unless I said so.
```

Then extend the `tea issues create` block (lines 21-24) so it reads:

```bash
# create the issue — NOTE: tea uses --description / -d for the body (not --body)
tea issues create --login git-home \
  --title "<concise title>" \
  --description "<cleaned-up notes>" \
  --labels needs-enrichment \
  -m "<milestone>"            # only when my notes named one
```

- [ ] **Step 3: Verify both edits**

Run:

```bash
grep -n 'Milestone' commands/gh/new.md commands/fj/new.md
grep -c 'Don.t assign, milestone' commands/gh/new.md commands/fj/new.md
grep -n -- '-m "<milestone>"' commands/gh/new.md commands/fj/new.md
```

Expected: a `**Milestone**:` bullet in each file; the old combined clause count is `0` in both; the `-m` flag present in both example blocks.

- [ ] **Step 4: Commit**

```bash
git add commands/gh/new.md commands/fj/new.md
git commit -m "feat(commands): let /gh:new and /fj:new set a milestone when named (#172)"
```

---

### Task 5: Documentation and changelog

**Files:**
- Modify: `commands/README.md:52-55` (forge-routers line) and `:65-70` (the `gh:`/`fj:` lines) — **both**
- Modify: `README.md:38`, `:39`, `:42` (the `commands/` tree sketch)
- Modify: `commands/commands.md` — the **Example workflows** section only
- Modify: `CHANGELOG.md` — `[Unreleased]`

**Interfaces:**
- Consumes: the three command names created in Tasks 1-3.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Edit `commands/README.md`**

In the **Forge routers** list (line 54-55), append `/milestone` after `/work`:

```markdown
`/issues` · `/prs` · `/parked` · `/triage` · `/done` · `/new` · `/enrich` ·
`/enrich-phased` · `/route` · `/work` · `/milestone`
```

In the **GitHub** list, append `/gh:milestone` after `/gh:done`:

```markdown
**GitHub** (`gh/`): `/gh:new` · `/gh:issues` · `/gh:parked` · `/gh:triage` ·
`/gh:enrich` · `/gh:enrich-phased` · `/gh:route` · `/gh:work` · `/gh:assign` ·
`/gh:implement` · `/gh:prs` · `/gh:review` · `/gh:done` · `/gh:milestone`
```

In the **Forgejo** list, append `/fj:milestone` after `/fj:done`:

```markdown
**Forgejo** (`fj/`): `/fj:new` · `/fj:issues` · `/fj:parked` · `/fj:triage` ·
`/fj:enrich` · `/fj:enrich-phased` · `/fj:route` · `/fj:work` · `/fj:prs` ·
`/fj:done` · `/fj:milestone`
```

- [ ] **Step 2: Edit `README.md`'s tree sketch**

Lines 38, 39 and 42 become:

```text
commands/
  fj/    → /fj:new  /fj:issues  /fj:triage  /fj:enrich  /fj:work  /fj:prs  /fj:milestone  …
  gh/    → /gh:new  /gh:issues  /gh:assign  /gh:implement  /gh:review  /gh:milestone  …
  wt/    → /wt:status  /wt:finish
  *.md   → /handoff  /pickup  /todo  /wrap-up  /loose-ends  /clear-check
           /issues  /prs  /triage  /route  /work  /milestone  (forge routers)
           /capture-idea  /commands  /update-commands
```

- [ ] **Step 3: Add one chain to `commands/commands.md`'s Example workflows**

`commands/commands.md` builds its command list by scanning directories at runtime,
so `/milestone` shows up there with no edit. Its only hand-maintained surface is the
baseline chain list — add this entry after the **Forgejo pipeline** bullet:

```markdown
- **Release-scoped work:** `/milestone new <name> due <date>` → `/new` → `/milestone assign <issue> to <name>` → `/milestone list`
  _Open a milestone, file work into it, then see everything still open for that ship date._
```

- [ ] **Step 4: Add the `CHANGELOG.md` entry**

Under `## [Unreleased]`, add an `### Added` section (it currently has none):

```markdown
## [Unreleased]

### Added

- **commands:** `/milestone` (+ `/gh:milestone`, `/fj:milestone`) — `list`, `new`,
  and `assign` verbs across both forges, with every write confirmed by read-back (#172)
- **commands:** `/gh:new` and `/fj:new` accept a milestone when the notes name one (#172)
```

- [ ] **Step 5: Verify the docs**

Run:

```bash
grep -n 'milestone' commands/README.md README.md commands/commands.md CHANGELOG.md
```

Expected: `/milestone` on the forge-routers line **and** `/gh:milestone` **and** `/fj:milestone` on the two per-forge lines of `commands/README.md`; three hits in `README.md`'s tree sketch; the new chain in `commands/commands.md`; two `[Unreleased] → Added` bullets in `CHANGELOG.md`.

Then confirm nothing outside scope was touched:

```bash
git status --short
```

Expected: only the four files of this task.

- [ ] **Step 6: Commit**

```bash
git add commands/README.md README.md commands/commands.md CHANGELOG.md
git commit -m "docs(commands): document /milestone across the command lists (#172)"
```

---

## Manual verification (local, after merge)

These make **real writes to a real forge** and are deliberately excluded from the
tasks above, because this plan is executed by the agent-workflow in CI. Run them by
hand on a machine with the credentials, after the PR merges and
`setup/link-commands.sh` has been re-run.

Route every GitHub write through direnv — the ambient token has been observed
lacking write scopes and failing *silently*:
`direnv exec /home/admin/repos/github/freaxnx01 gh …`.

[ ] **1.** **GitHub smoke test** on `freaxnx01/agent-workflow`: `/milestone new test-milestone due 2026-08-31`, then `/milestone assign 172 to test-milestone`, then `/milestone list`. Confirm each from the read-back — in particular that `due_on` came back as `2026-08-31T12:00:00Z` and renders as **Aug 31**, not Aug 30. Delete the test milestone in the web UI afterwards.

[ ] **2.** **`/gh:new` regression**: create one throwaway issue whose notes name a milestone and one whose notes don't. Confirm the first gets the milestone and the second asks nothing and sets nothing. Close both.

[ ] **3.** **Forgejo**: `tea` was not installed on the machine where these commands were written, so the entire `/fj:milestone` surface is unverified against a live run — its flags come from reading tea's source. The first real invocation is the test; if a flag is wrong, fix it and update `commands/fj/milestone.md` per its own footer.

## Out of scope (do not implement)

- `/issues`, `/triage`, `/route`, `/done`, `/parked` — no milestone column anywhere outside the new command.
- `unassign`, `close`, `reopen`, `delete`, `edit` verbs.
- Epics and sub-issues — separate axes per `docs/glossary.md`; `gh` has no first-class sub-issue command anyway.
- The `ai-implement` pipeline and its workflows.
- Fixing the token's missing label-write scope (noted in the spec as context for the read-back rule, not as work).
