---
description: Enrich an issue with a spec and implementation plan, then update the issue body so it's ready to implement
argument-hint: <issue number>
---

Detect the forge, then run the matching section below.

```bash
source "$HOME/.claude/scripts/lib/detect-forge.sh"
detect_forge
```

## GitHub

Enrich GitHub issue #$ARGUMENTS (strip any leading `#`) so it is ready for the
agent-workflow. The pipeline reads only the issue **body** — everything the agent
needs must end up there.

### Step 1 — Read the issue

```bash
gh issue view $ARGUMENTS --comments
```

If the issue is closed, already has `ai-implement` label, or is `🧊 parked`, stop and say so.

### Step 1.5 — Check for an existing enrichment lock

If the issue carries the `enrichment-ongoing` label, another session may already be
enriching it. Scan the comments already fetched in Step 1 for the most recent line
matching:

```text
🔒 Enrichment lock (re-)acquired at <timestamp>
```

Compute its age against the current UTC time:

```bash
date -u +%Y-%m-%dT%H:%M:%SZ
```

- No `enrichment-ongoing` label → continue to Step 2.
- Label present, a matching comment found, age < 4 hours → **stop**. Tell the user
  the issue is already being enriched (show the age) and end the command — do not
  run Step 2 or start brainstorming.
- Label present, age ≥ 4 hours, **or** no matching comment found (treat unknown age
  as stale) → tell the user the lock looks abandoned (show age and the 4h
  threshold) and ask whether to take over.
  - No → stop.
  - Yes → continue to Step 2; Step 2.5 will re-acquire the lock and note the
    takeover.

### Step 2 — Assess readiness

Judge whether the issue already has all three:

- **Acceptance criteria** — concrete, testable conditions
- **Scope / spec** — what to build, enough to start without guessing
- **No blocking unknowns** — no open design questions or TBDs the agent can't resolve from the codebase

If the issue is already complete, tell the user and suggest running `/gh:implement $ARGUMENTS` directly. Stop here.

### Step 2.5 — Acquire the enrichment lock

Before starting brainstorming — the expensive shared resource two sessions could
collide on — claim the lock so a second session can detect this one:

```bash
gh label create enrichment-ongoing --color FBCA04 \
  --description "Another /enrich session is actively enriching this issue — do not start a second one" \
  2>/dev/null || true
gh issue edit $ARGUMENTS --add-label enrichment-ongoing
```

Post the timestamp comment. Fresh acquisition (Step 1.5 found no lock):

```bash
gh issue comment $ARGUMENTS --body "🔒 Enrichment lock acquired at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

Takeover of a stale lock (Step 1.5 found one and the user agreed to take over —
substitute the actual age you showed the user for `<Xh>`):

```bash
gh issue comment $ARGUMENTS --body "🔒 Enrichment lock re-acquired at $(date -u +%Y-%m-%dT%H:%M:%SZ) (previous lock stale, <Xh> old)"
```

### Step 3 — Brainstorm spec

Invoke **superpowers:brainstorming** with the issue as context. The goal is a
validated spec saved to `<specs-dir>/YYYY-MM-DD-<topic>-design.md` and committed.
Follow the brainstorming skill end-to-end (clarifying questions, approaches,
design sections, spec self-review, user approval gate).

### Step 4 — Write implementation plan

After brainstorming exits, invoke **superpowers:writing-plans** to produce the
full task-by-task plan at `<plans-dir>/YYYY-MM-DD-<topic>.md` and commit it.

**Do not stop at writing-plans' own handoff prompt — don't even print it.**
That skill ends by asking "Subagent-Driven or Inline Execution?"; that is
writing-plans' generic ending, not the end of `/enrich`. `/enrich`'s own
execution model is neither of those — the plan goes into the issue body and
gets dispatched via the `ai-implement` label (Step 6), not run locally. So
suppress that question entirely: don't ask it, don't wait for an answer, don't
execute the plan. Treat the plan as written the moment writing-plans exits,
and continue straight to Step 5 — pushing the files and writing the plan into
the issue body is still required, always.

#### Picking `<specs-dir>` / `<plans-dir>` — check gitignore first

Both superpowers skills default to `docs/superpowers/{specs,plans}/`. **Many repos
gitignore `docs/superpowers/`**, so those defaults commit nothing and the paths you
then write into the issue body resolve to nothing for the implementing agent — a
silent failure. Resolve the directories before writing either file:

```bash
for d in docs/ai-notes/specs docs/superpowers/specs; do
  git check-ignore -q "$d/probe.md" && echo "$d IGNORED" || echo "$d ok"
done
```

Prefer whichever sibling convention the repo already uses — look for existing dated
`*-design.md` and plan files and follow them.

Tell the brainstorming and writing-plans skills the resolved path explicitly —
both honour "user preferences for spec/plan location override this default".

### Step 5 — Push to remote

Ensure both the spec and plan files are committed and pushed before touching the
issue body — the body will reference these files by path and the agent must be
able to check them out:

```bash
git push
```

**Push to the branch the implementing agent will start from — normally `main`.**
A plain `git push` from a local-only scratch branch (e.g. a long-lived
`.worktrees/<name>` checkout) publishes nothing the agent can see, and the body's
paths dangle. From such a worktree, push the branch *at* main explicitly:

```bash
git fetch origin && git rebase origin/main   # main often moved while you were writing
git push origin <local-branch>:main
git ls-tree -r --name-only origin/main -- docs | grep <today>   # prove the files landed
```

Verify the push succeeded before proceeding.

### Step 6 — Update the issue body

The implementing agent should be able to work from the issue body alone — no
extra file reads to orient itself. Replace the issue body with:

1. The original description (keep it — context for humans)
2. An `## Acceptance Criteria` section with the approved AC as a `- [ ]` checklist
3. An `## Implementation Plan` section containing the **full plan content
   inlined verbatim** (not a link) — the task breakdown, file structure, TDD
   steps, and exact code to produce, exactly as written to the plan file in
   Step 4
4. A `## Spec` section with just the relative path to the spec file (linked as
   markdown) — for human/reviewer reference only; the implementing agent
   should not need it

```bash
gh issue edit $ARGUMENTS --body "..."
```

**Also clear the readiness labels** — `needs-enrichment` and `❓ to-be-defined`
mean "not ready yet," and the issue now is. Leaving either on is a silent trap:
`/gh:implement` treats them as a hard stop regardless of what the body says.

```bash
gh issue edit $ARGUMENTS --remove-label needs-enrichment 2>/dev/null || true
gh issue edit $ARGUMENTS --remove-label "❓ to-be-defined" 2>/dev/null || true
gh issue edit $ARGUMENTS --remove-label enrichment-ongoing 2>/dev/null || true
```

`--remove-label` on a label the issue doesn't carry is a no-op, but on a label
that doesn't exist **anywhere in the repo** it errors — many repos only define
some of these conventions. Run each on its own line with `|| true` so a
missing repo label doesn't abort the step. The lock comment posted in Step 2.5
is left in place as an audit trail — only the label is removed.

### Step 7 — Confirm

Print:

- Issue URL
- Paths to spec and plan files
- "Issue is ready — run `/gh:implement $ARGUMENTS` to trigger the agent-workflow."

---

If you run into blockers (brainstorming skill not available, push fails, issue edit
rejected), find a solution and update this skill for the future.

## Forgejo

Enrich Forgejo issue #$ARGUMENTS (strip any leading `#`) so it is ready to
implement. Everything the implementer needs must end up in the issue **body** (+ the
committed spec/plan it links to).

### Forgejo access

Target the homelab Forgejo (`git.home.freaxnx01.ch`) via **`tea`** (login
`git-home`):

```bash
url=$(git remote get-url origin); url=${url%.git}
repo=$(echo "$url" | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#')
```

### Step 1 — Read the issue

```bash
tea issues $ARGUMENTS --login git-home
tea api --login git-home "repos/$repo/issues/$ARGUMENTS/comments"
```

If the issue is closed or `🧊 parked`, stop and say so.

### Step 1.5 — Check for an existing enrichment lock

If the issue carries the `enrichment-ongoing` label, another session may already be
enriching it. Scan the comments already fetched in Step 1 for the most recent line
matching:

```text
🔒 Enrichment lock (re-)acquired at <timestamp>
```

Compute its age against the current UTC time:

```bash
date -u +%Y-%m-%dT%H:%M:%SZ
```

- No `enrichment-ongoing` label → continue to Step 2.
- Label present, a matching comment found, age < 4 hours → **stop**. Tell the user
  the issue is already being enriched (show the age) and end the command — do not
  run Step 2 or start brainstorming.
- Label present, age ≥ 4 hours, **or** no matching comment found (treat unknown age
  as stale) → tell the user the lock looks abandoned (show age and the 4h
  threshold) and ask whether to take over.
  - No → stop.
  - Yes → continue to Step 2; Step 2.5 will re-acquire the lock and note the
    takeover.

### Step 2 — Assess readiness

Judge whether the issue already has all three:

- **Acceptance criteria** — concrete, testable conditions
- **Scope / spec** — what to build, enough to start without guessing
- **No blocking unknowns** — no open design questions or TBDs the implementer can't
  resolve from the codebase

If it's already complete, tell me and suggest running `/work $ARGUMENTS` directly.
Stop here.

### Step 2.5 — Acquire the enrichment lock

Before starting brainstorming — the expensive shared resource two sessions could
collide on — claim the lock so a second session can detect this one. `tea` has no
per-issue label add/remove subcommand, so read the current labels and PUT back the
set with `enrichment-ongoing` added (same pattern Step 6 already uses to remove
labels):

```bash
tea labels create --login git-home --name enrichment-ongoing --color "#fbca04" \
  --description "Another /enrich session is actively enriching this issue — do not start a second one" \
  2>/dev/null || true

current=$(tea api --login git-home "repos/$repo/issues/$ARGUMENTS" | jq -r '[.labels[].name]')
locked=$(echo "$current" | jq -c '. + ["enrichment-ongoing"] | unique')
tea api --login git-home -X PUT "repos/$repo/issues/$ARGUMENTS/labels" -f labels="$locked" >/dev/null
```

Post the timestamp comment. Fresh acquisition (Step 1.5 found no lock):

```bash
tea api --login git-home -X POST "repos/$repo/issues/$ARGUMENTS/comments" \
  -f body="🔒 Enrichment lock acquired at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

Takeover of a stale lock (Step 1.5 found one and the user agreed to take over —
substitute the actual age you showed the user for `<Xh>`):

```bash
tea api --login git-home -X POST "repos/$repo/issues/$ARGUMENTS/comments" \
  -f body="🔒 Enrichment lock re-acquired at $(date -u +%Y-%m-%dT%H:%M:%SZ) (previous lock stale, <Xh> old)"
```

### Step 3 — Brainstorm spec

Invoke **superpowers:brainstorming** with the issue as context. The goal is a
validated spec saved to a **tracked** specs dir (see *Choosing a tracked path*) and
committed. Follow the brainstorming skill end-to-end (clarifying questions,
approaches, design sections, spec self-review, user approval gate).

### Step 4 — Write implementation plan

After brainstorming exits, invoke **superpowers:writing-plans** to produce the full
task-by-task plan in a tracked plans dir and commit it.

**Do not stop at writing-plans' own handoff prompt — don't even print it.**
That skill ends by asking "Subagent-Driven or Inline Execution?"; that is
writing-plans' generic ending, not the end of `/enrich`. `/enrich`'s own
execution model is neither of those — the plan goes into the issue body and
gets dispatched via the `ai-implement` label (Step 6), not run locally. So
suppress that question entirely: don't ask it, don't wait for an answer, don't
execute the plan. Treat the plan as written the moment writing-plans exits,
and continue straight to Step 5 — pushing the files and writing the plan into
the issue body is still required, always.

### Step 5 — Push to remote

Commit and push both the spec and plan before touching the issue body — the body
references these files by path:

```bash
git push
```

Verify the push succeeded before proceeding.

### Step 6 — Update the issue body

Replace the issue body via API PATCH — use the **typed** field `-F` so it reads the
file (`-f` would store the literal string `@bodyfile.md`; `tea issues edit` has no
body flag):

```bash
tea api -X PATCH "repos/$repo/issues/$ARGUMENTS" -F body=@bodyfile.md
```

The new body has:

1. The original description (keep it — context for humans)
2. An `## Acceptance Criteria` section with the approved AC as a `- [ ]` checklist
3. A `## Spec & Implementation Plan` section with relative paths to the spec and plan
   files (linked as markdown) plus: *"Read the plan before writing any code — it
   contains the full task breakdown, file structure, TDD steps, and exact code to
   produce."*

**Also clear the readiness labels** — `needs-enrichment` and `❓ to-be-defined` mean
"not ready yet," and the issue now is. `tea` has no per-issue label add/remove
subcommand (`tea labels` only manages repo-level label *definitions*), so read the
issue's current labels and PUT back the set with those names — plus the
`enrichment-ongoing` lock from Step 2.5 — filtered out:

```bash
current=$(tea api --login git-home "repos/$repo/issues/$ARGUMENTS" | jq -r '[.labels[].name]')
kept=$(echo "$current" | jq -c '[.[] | select(. != "needs-enrichment" and . != "❓ to-be-defined" and . != "enrichment-ongoing")]')
tea api --login git-home -X PUT "repos/$repo/issues/$ARGUMENTS/labels" -f labels="$kept" >/dev/null
```

(This is best-effort against Forgejo's labels API, which has had both name- and
ID-keyed variants across versions — if the `PUT` errors, check `tea api
--login git-home "repos/$repo/issues/$ARGUMENTS/labels"` for the shape this
instance expects and fix this step for the future.)

The lock comment posted in Step 2.5 is left in place as an audit trail — only the
label is removed here.

### Step 7 — Confirm

Print the issue URL, the spec and plan paths, and: *"Issue is ready — run
`/work $ARGUMENTS` to implement it locally."*

> When the self-hosted **Forgejo Actions** agent-workflow exists (future tier), this
> final pointer becomes "apply the `ai-implement` label / run `/fj:implement`" to
> trigger the runner instead — update this step then.

### Choosing a tracked path

A spec/plan is only useful if it's **committed and not git-ignored**. Pick an
existing tracked specs/plans dir; never write to a path that `git check-ignore -q
<path>` reports as ignored — fall back to `docs/ai-notes/{specs,plans}`. Confirm with
`git ls-files` that the committed file is tracked before the push step relies on it.

---

If you run into blockers (brainstorming/writing-plans unavailable, push auth fails,
the issue-body PATCH is rejected, ignored docs dir), find a solution and update this
command for the future.

## Unknown host

Report the detected host and that no authed GitHub or Forgejo login matched it;
point at `gh auth login` / `tea login add`. Don't guess a forge.
