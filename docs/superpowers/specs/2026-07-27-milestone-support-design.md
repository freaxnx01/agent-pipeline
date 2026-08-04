# Milestone Support in the Slash Commands (GitHub + Forgejo) — Design

**Issue:** #172 · **Status:** Approved · **Date:** 2026-07-27

Issue #172 asks for milestone support in the agent-workflow slash commands, on both
forges: create a milestone (name + due date), assign issues to one, allow assigning a
milestone when creating an issue, and list milestones with their assigned issues.

## Problem

The command console has no milestone surface at all. Worse, both `commands/gh/new.md`
and `commands/fj/new.md` actively forbid it — each carries the line *"Don't assign,
milestone, or add other labels unless I said so."* So today a milestone can only be
set in the web UI, which breaks the otherwise-complete
`/new → /triage → /route → /enrich → /work → /review → /done` loop whenever work is
release-scoped.

`docs/glossary.md` already fixes the vocabulary this design must respect: a
**milestone** is the *"when does this ship"* axis — a native, repo-scoped, non-nesting
object holding a due date and a flat list of issues, at most one per issue. It is not
an epic (*what work, what scope*) and not a label (*a filter tag*). This design adds
the milestone axis only.

## Verified CLI surface

Empirically verified for `gh` (v2.92.0, run locally). Verified for `tea` **from its
source** — see [Known gaps](#known-gaps).

| Capability | GitHub (`gh` 2.92.0) | Forgejo (`tea`) |
|---|---|---|
| Create milestone + due date | **no `gh milestone` command** → `gh api repos/{o}/{r}/milestones -f title= -f due_on=` | `tea milestones create -t <title> [-d <desc>] --deadline/-x <date>` |
| Assign an existing issue | `gh issue edit <n> -m/--milestone "<name>"` (also `--remove-milestone`) | `tea milestones issues add "<name>" <index>` (also `remove`) |
| Milestone at issue creation | `gh issue create -m/--milestone "<name>"` | `tea issues create -m/--milestone "<name>"` |
| List milestones | `gh api repos/{o}/{r}/milestones?state=open` | `tea milestones list [--state]` / `tea api …/milestones` |
| Issues within a milestone | `gh issue list -m "<name>"`, and `milestone` is a valid `--json` field | `tea milestones issues "<name>" [--state]` |

`gh milestone` does **not** exist (`unknown command "milestone" for "gh"`), so on the
GitHub side only *assignment* has a first-class flag; creation and listing go through
`gh api`. `tea`'s milestone surface is fuller: `list`, `create`, `close`, `reopen`,
`delete`, and `issues` (with `add` / `remove` subcommands).

## Decisions

Four design forks, all settled with the user before writing this spec:

1. **One command with a verb argument**, not one file per verb. The `.md` files are
   prompts, so the verb is parsed from natural language. Three new files instead of
   nine, and a single place per forge to keep the two in sync.

2. **`/new` assigns a milestone only when the notes name one.** The existing "unless I
   said so" clause stays — milestone simply joins what counts as *said so*. `/new`
   remains a single round trip with no added question. If the named milestone does not
   exist, ask before creating it; never create silently.

3. **Three verbs only** — `list`, `new`, `assign`. No `unassign`, `close`, `reopen`,
   `delete`, or `edit`, even though both CLIs expose them cheaply (YAGNI; adding one
   later is a small edit to three files).

4. **`list` uses two calls and groups client-side** (approach C of three considered):
   - *N+1 queries* (one issue query per milestone) — simplest, but 1+N round trips and
     nothing to cross-check the per-milestone results against.
   - *One issue query, grouped locally* — two calls, but milestones with zero issues
     disappear, exactly the ones you want to see right after `/milestone new`.
   - **Chosen:** one milestone call + one issue query, grouped locally. Empty
     milestones still appear; cost is fixed regardless of milestone count; and the
     milestone call returns `open_issues` / `closed_issues` counts for free, so the
     grouped output can be cross-checked against the API's own numbers.

## Structure

Three new prompt files, following the established router pattern — the router holds no
logic of its own, and the forge files are the single source of truth:

```text
commands/milestone.md        ← router: detect forge from origin host, delegate
commands/gh/milestone.md     ← GitHub, via gh
commands/fj/milestone.md     ← Forgejo, via tea (login git-home)
```

The router reuses the host-matching snippet already shared by `commands/new.md`,
`commands/enrich.md`, and the other routers: derive the host from `origin` (handling
`https://`, `ssh://`, and scp-style `git@host:path`), then `gh auth token --hostname`
→ github, `tea logins list` → forgejo, `github.com` → github, else report the host and
stop without guessing.

`setup/link-commands.sh` installs `commands/**/*.md` discovered with `find`, so **no
manifest needs updating** — verified by reading the installer. Subdirectories become
the `/gh:` and `/fj:` namespaces automatically.

## Command behaviour

### `/milestone list`

Open milestones, each with its open issues nested underneath, plus the due date and
issue counts. Empty milestones are shown (that is the point of decision 4). Issues
with no milestone are **not** listed — that is what `/issues` is for.

GitHub:

```bash
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh api "repos/$repo/milestones?state=open&sort=due_on&direction=asc" \
  --jq '.[] | [.number, .title, (.due_on // "-"), .open_issues, .closed_issues] | @tsv'
gh issue list --state open --limit 200 --json number,title,milestone
```

Forgejo (`tea api` + `python3`, matching the idiom in `commands/fj/issues.md` and
`commands/fj/prs.md`):

```bash
url=$(git remote get-url origin); url=${url%.git}
repo=$(echo "$url" | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#')
tea api --login git-home "repos/$repo/milestones?state=open"
tea api --login git-home "repos/$repo/issues?state=open&type=issues&limit=100"
```

Group the issues by `.milestone.title` locally in both cases.

### `/milestone new <name> [due <date>]`

GitHub — no subcommand exists, so POST directly:

```bash
gh api "repos/$repo/milestones" -f title="<name>" -f due_on="<YYYY-MM-DD>T12:00:00Z"
```

Forgejo:

```bash
tea milestones create --login git-home --title "<name>" --deadline "<YYYY-MM-DD>"
```

The due date is optional on both forges; omit the flag entirely when the user gave no
date, rather than passing an empty value.

### `/milestone assign <issue> to <name>`

```bash
gh issue edit <n> --milestone "<name>"                      # GitHub
tea milestones issues add --login git-home "<name>" <n>     # Forgejo
```

### Milestone on issue creation

`commands/gh/new.md` and `commands/fj/new.md` each get their "Don't assign, milestone,
or add other labels unless I said so" line rewritten so milestone becomes an
*if-I-said-so* field, and gain the flag in their example invocation:

```bash
gh issue create --title … --body-file … --label needs-enrichment -m "<name>"
tea issues create --login git-home --title … --description … --labels needs-enrichment -m "<name>"
```

If the notes name a milestone that does not exist, ask whether to create it (and for a
due date) before creating the issue. Never create a milestone implicitly.

## Forge asymmetries the commands must absorb

- **No `gh milestone` command.** Creation and listing go through `gh api`; only
  assignment has a first-class flag. The `tea` side has real subcommands for all three.

- **Due-date normalization.** GitHub's `due_on` wants an ISO 8601 timestamp, so a bare
  `2026-08-31` is normalized to `2026-08-31T12:00:00Z` — **midday UTC, deliberately,
  not midnight**, so that no viewer timezone offset can roll the rendered date back to
  the previous day. Forgejo's `--deadline` accepts loose date strings (tea parses them
  with `dateparse`), so the bare date is passed through.

- **Assignment identity differs.** `gh issue edit -m` takes the milestone *name*, while
  Forgejo's REST API takes a numeric milestone *id*. That is why the Forgejo side uses
  `tea milestones issues add` (name-based) instead of a raw
  `tea api -X PATCH …/issues/<n>` — it avoids a name→id lookup on every assign.

- **JSON tooling differs.** `gh` has `--jq` built in; `tea api` does not, so the
  Forgejo side pipes into `python3 -c`, consistent with the existing `fj/*` commands.

## Error handling

- **Every write is read back, and the result reported from the read-back — never from
  the exit code.** This is not hypothetical. While filing issue #172 in this very
  session, `gh issue create --label needs-enrichment` printed the issue URL and exited
  `0`, yet the label was **silently dropped**: the ambient token lacked label-write
  permission (`gh issue edit --add-label` later surfaced the real error,
  `does not have the correct permissions to execute AddLabelsToLabelable`). A milestone
  write can fail exactly the same way. Both forge files state this rule explicitly, so
  `new` and `assign` confirm from a follow-up read (`gh api …/milestones`,
  `gh issue view <n> --json milestone`, or the `tea` equivalents), not from a clean
  exit.

- **Unknown milestone name on `assign`** → print the open milestones and stop. No fuzzy
  matching, no silent creation.

- **Duplicate title on `new`** → GitHub answers `422` with `already_exists`; report the
  existing milestone and stop rather than retrying.

- **Truncation guard on `list`** → print the milestone's API `open_issues` count next
  to the number of issues actually shown, so an incomplete table is visible rather than
  quietly wrong. The two legitimately differ: a milestone's `open_issues` counts
  **issues and pull requests together**, while the issue query is filtered to issues
  only (`gh issue list` excludes PRs; the Forgejo call passes `type=issues`). So a
  mismatch means *either* the issue query hit its limit *or* PRs are assigned to that
  milestone — the command says exactly that instead of claiming truncation.

- **No forge context** (`gh`/`tea` not on PATH, no login, unrecognized host) → say
  which of those it is, point at `gh auth login` / `tea login add`, and stop. Same
  behaviour as the existing routers.

## Testing

The repo has no automated validation of command `.md` files — `just lint` runs
`actionlint` + `shellcheck` over workflows and `scripts/`/`tests/`, and nothing parses
command front-matter. Verification is therefore:

1. **Install check** — `setup/link-commands.sh --no-sync`, then confirm
   `~/.claude/commands/milestone.md`, `gh/milestone.md`, and `fj/milestone.md` exist.
2. **GitHub smoke test on this repo** — `new` a real milestone with a due date,
   `assign` #172 to it, `list`; verify each by read-back, including that `due_on` came
   back as the intended date.
3. **`/new` regression** — one issue created with a milestone named in the notes, one
   without, confirming the second asks nothing and sets nothing.
4. **Forgejo** — deferred; see below.

## Known gaps

- **The Forgejo half cannot be smoke-tested from this machine: `tea` is not
  installed** (`tea: command not found`; not in `~/go/bin`, `~/.local/bin`, or
  `/usr/local/bin`). Its flags — `tea milestones create -t/-d/--deadline`,
  `tea milestones issues [add|remove]`, `tea issues create -m` — were verified by
  reading tea's own source (`cmd/milestones/*.go`, `cmd/flags/issue_pr.go`), not a
  live run. The first `/fj:milestone` invocation on a machine with `tea` is the real
  test, and the file carries the standard self-improving footer so any flag surprise
  gets written back into the command. This repo has precedent for exactly that kind of
  surprise: `fj/new.md` records *"tea uses `--description` / `-d` for the body (not
  `--body`)"*.

- **The label-drop token gap** found while filing #172 is recorded here as context for
  the read-back rule, but fixing the token's scopes is out of scope for this issue.

## Non-goals

- `/issues`, `/triage`, `/route`, `/done`, and `/parked` are **not** modified — no
  milestone column anywhere outside the new command.
- No `unassign`, `close`, `reopen`, `delete`, or `edit` verbs.
- No epic or sub-issue behaviour. Per `docs/glossary.md` those are separate axes, and
  `gh` has no first-class sub-issue command anyway.
- No changes to the `ai-implement` pipeline or its workflows.

## Acceptance criteria

- [ ] `commands/gh/milestone.md`, `commands/fj/milestone.md`, and the
      `commands/milestone.md` router exist, each with `description:` and
      `argument-hint:` front-matter.
- [ ] `/milestone list` shows open milestones with due date, issue counts, and their
      open issues nested — including milestones that have no issues — and shows the
      API's `open_issues` count alongside the number shown so a gap is visible.
- [ ] `/milestone new <name> [due <date>]` creates the milestone on both forges, with
      GitHub's `due_on` normalized to `T12:00:00Z`, and confirms by read-back.
- [ ] `/milestone assign <issue> to <name>` assigns an existing issue and confirms by
      read-back; an unknown milestone name lists the open milestones and stops.
- [ ] `/gh:new` and `/fj:new` assign a milestone when — and only when — the notes name
      one, and ask before creating a milestone that doesn't exist.
- [ ] Every write path reports from a read-back rather than from a clean exit code.
- [ ] The router detects the forge with the same snippet as the other routers and
      stops without guessing on an unknown host.
- [ ] Command lists are updated in `commands/README.md` (both the forge-routers line
      and the per-forge `gh:`/`fj:` lines), `commands/commands.md`, and `README.md`.
- [ ] `CHANGELOG.md` `[Unreleased]` records the addition.
- [ ] `setup/link-commands.sh --no-sync` installs all three files.
