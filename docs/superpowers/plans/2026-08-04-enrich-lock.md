# /enrich Concurrency Lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent two `/enrich` sessions from concurrently brainstorming/planning the same issue by adding a label + timestamped-comment lock, with a 4-hour staleness expiry, to both the GitHub and Forgejo sections of `commands/enrich.md`.

**Architecture:** Two new sub-steps per forge section — Step 1.5 (detect an existing lock, hard-stop or offer takeover) and Step 2.5 (acquire the lock right before brainstorming starts) — plus a release addition to the existing Step 6 (clear-labels step). The lock is a boolean label (`enrichment-ongoing`) for visibility/filtering, with the acquisition timestamp carried in an issue comment so age can be computed without a new API surface (Step 1 already fetches comments on both forges).

**Tech Stack:** Markdown instruction files (`commands/enrich.md`), `gh` CLI (GitHub), `tea` CLI (Forgejo), plain bash (`date -u`, `jq`).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-04-enrich-lock-design.md`
- No new scripts or application code — this is a `commands/enrich.md` instruction change plus one label registration in `scripts/ensure-issue-labels.sh`.
- Staleness threshold: **4 hours**, computed from ISO 8601 UTC timestamps (`date -u +%Y-%m-%dT%H:%M:%SZ`).
- Lock label name: `enrichment-ongoing`, color `FBCA04` (hex `#fbca04` where a `#` prefix is required), description: `Another /enrich session is actively enriching this issue — do not start a second one`.
- Lock comment format:
  - Fresh acquisition: `🔒 Enrichment lock acquired at <timestamp>`
  - Takeover of a stale lock: `🔒 Enrichment lock re-acquired at <timestamp> (previous lock stale, <Xh> old)`
- `/enrich-phased` and cross-session self-collision handling are explicitly out of scope (spec's Follow-ups section) — do not touch `commands/enrich-phased.md`.
- This command has no automated test suite; verification is the manual dry-run scenarios in the spec's Testing section, reproduced per-task below.

---

### Task 1: Register the `enrichment-ongoing` label

**Files:**
- Modify: `scripts/ensure-issue-labels.sh`

**Interfaces:**
- Consumes: nothing new — follows the existing `create <name> <color> <description>` helper already defined in the script (lines 42-49).
- Produces: the `enrichment-ongoing` label exists (idempotently) on any repo that runs this script. Tasks 2 and 3 assume this label name, color, and description.

- [ ] **Step 1: Add the label registration line**

Open `scripts/ensure-issue-labels.sh`. The file groups `create` calls by category with a comment header per group (`trigger`, `lifecycle`, `selectors`, `gates`, `outcome` — see the header comment block at the top of the file). Add a new category comment and call after the `outcome` group (after the last line, currently):

```bash
create ai:review-blocked D73A4A 'Auto-review left the PR draft; human action required'
```

Append:

```bash

create enrichment-ongoing FBCA04 'Another /enrich session is actively enriching this issue — do not start a second one'
```

Also update the categories comment block at the top of the file (the block starting `# Categories:` around line 6) to document this new category, following the existing style of the other category entries:

```text
#   coordination enrichment-ongoing
#              — read/written by /enrich (Step 1.5 / 2.5 / 6) to prevent two
#                sessions from concurrently enriching the same issue
```

- [ ] **Step 2: Verify the script is still valid bash**

Run:

```bash
bash -n scripts/ensure-issue-labels.sh
```

Expected: no output, exit code 0 (syntax check only — this script requires `REPO` env and network access to run for real, out of scope to execute here).

- [ ] **Step 3: Commit**

```bash
git add scripts/ensure-issue-labels.sh
git commit -m "chore(labels): register enrichment-ongoing label

Backs the /enrich concurrency lock (docs/superpowers/specs/2026-08-04-enrich-lock-design.md)."
```

---

### Task 2: Add the lock to `/enrich`'s GitHub section

**Files:**
- Modify: `commands/enrich.md` (GitHub section, lines 13-146 as of this plan's writing)

**Interfaces:**
- Consumes: the `enrichment-ongoing` label registered in Task 1 (same name/color/description — this task re-creates it inline too, since `/enrich` runs standalone against repos that may not have run `ensure-issue-labels.sh`, matching how `needs-enrichment` is already created inline in `/new`).
- Produces: nothing consumed by other tasks — Task 3 is the Forgejo mirror of this same behavior, written independently against the Forgejo section.

- [ ] **Step 1: Insert Step 1.5 (detect an existing lock) after the current Step 1**

Find this exact block (current lines 19-26):

```markdown
### Step 1 — Read the issue

```bash
gh issue view $ARGUMENTS --comments
```

If the issue is closed, already has `ai-implement` label, or is `🧊 parked`, stop and say so.

### Step 2 — Assess readiness
```

Replace it with (inserting the new Step 1.5 between the existing Step 1 and Step 2):

```markdown
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
```

- [ ] **Step 2: Insert Step 2.5 (acquire the lock) between Step 2 and Step 3**

Find this exact block (current lines 35-37):

```markdown
If the issue is already complete, tell the user and suggest running `/gh:implement $ARGUMENTS` directly. Stop here.

### Step 3 — Brainstorm spec
```

Replace it with:

```markdown
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
```

- [ ] **Step 3: Add lock release to Step 6**

Find this exact block (current lines 124-127):

```markdown
```bash
gh issue edit $ARGUMENTS --remove-label needs-enrichment 2>/dev/null || true
gh issue edit $ARGUMENTS --remove-label "❓ to-be-defined" 2>/dev/null || true
```
```

Replace it with:

```markdown
```bash
gh issue edit $ARGUMENTS --remove-label needs-enrichment 2>/dev/null || true
gh issue edit $ARGUMENTS --remove-label "❓ to-be-defined" 2>/dev/null || true
gh issue edit $ARGUMENTS --remove-label enrichment-ongoing 2>/dev/null || true
```
```

Immediately below that block, the existing prose says:

```markdown
`--remove-label` on a label the issue doesn't carry is a no-op, but on a label
that doesn't exist **anywhere in the repo** it errors — many repos only define
one of the two conventions. Run each on its own line with `|| true` so a
missing repo label doesn't abort the step.
```

Update it to cover three labels instead of two:

```markdown
`--remove-label` on a label the issue doesn't carry is a no-op, but on a label
that doesn't exist **anywhere in the repo** it errors — many repos only define
some of these conventions. Run each on its own line with `|| true` so a
missing repo label doesn't abort the step. The lock comment posted in Step 2.5
is left in place as an audit trail — only the label is removed.
```

- [ ] **Step 4: Verify the markdown structure**

Run:

```bash
grep -n '^### Step' commands/enrich.md | head -20
```

Expected: in the GitHub section (before the `## Forgejo` heading), the sequence
reads `Step 1`, `Step 1.5`, `Step 2`, `Step 2.5`, `Step 3`, `Step 4`, `Step 5`,
`Step 6`, `Step 7` — no step renumbered, no duplicate headings.

- [ ] **Step 5: Commit**

```bash
git add commands/enrich.md
git commit -m "feat(enrich): add concurrency lock to GitHub section

Adds Step 1.5 (detect an existing enrichment-ongoing lock, hard-stop or
offer takeover past the 4h staleness threshold) and Step 2.5 (acquire
the lock before brainstorming starts), and releases it in Step 6.

See docs/superpowers/specs/2026-08-04-enrich-lock-design.md."
```

---

### Task 3: Add the lock to `/enrich`'s Forgejo section

**Files:**
- Modify: `commands/enrich.md` (Forgejo section, lines 147-273 as of this plan's writing — line numbers will have shifted by the insertions in Task 2; locate by heading text, not line number)

**Interfaces:**
- Consumes: nothing from Task 2 — the Forgejo section is a self-contained mirror using `tea` instead of `gh`. Uses the same label name/color/description and comment format constants defined in Global Constraints above.
- Produces: nothing consumed elsewhere.

- [ ] **Step 1: Insert Step 1.5 (detect an existing lock) after the current Step 1**

Find this exact block:

```markdown
### Step 1 — Read the issue

```bash
tea issues $ARGUMENTS --login git-home
tea api --login git-home "repos/$repo/issues/$ARGUMENTS/comments"
```

If the issue is closed or `🧊 parked`, stop and say so.

### Step 2 — Assess readiness
```

Replace it with:

```markdown
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
```

- [ ] **Step 2: Insert Step 2.5 (acquire the lock) between Step 2 and Step 3**

Find this exact block:

```markdown
If it's already complete, tell me and suggest running `/work $ARGUMENTS` directly.
Stop here.

### Step 3 — Brainstorm spec
```

Replace it with:

```markdown
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
```

- [ ] **Step 3: Add lock release to Step 6**

Find this exact block:

```markdown
```bash
current=$(tea api --login git-home "repos/$repo/issues/$ARGUMENTS" | jq -r '[.labels[].name]')
kept=$(echo "$current" | jq -c '[.[] | select(. != "needs-enrichment" and . != "❓ to-be-defined")]')
tea api --login git-home -X PUT "repos/$repo/issues/$ARGUMENTS/labels" -f labels="$kept" >/dev/null
```
```

Replace it with:

```markdown
```bash
current=$(tea api --login git-home "repos/$repo/issues/$ARGUMENTS" | jq -r '[.labels[].name]')
kept=$(echo "$current" | jq -c '[.[] | select(. != "needs-enrichment" and . != "❓ to-be-defined" and . != "enrichment-ongoing")]')
tea api --login git-home -X PUT "repos/$repo/issues/$ARGUMENTS/labels" -f labels="$kept" >/dev/null
```
```

Immediately below that block, the existing prose has a parenthetical note about the
PUT being best-effort. Leave it as-is — it applies equally to the now-three-label
filter. Add one sentence after it noting the comment is intentionally kept:

```markdown
The lock comment posted in Step 2.5 is left in place as an audit trail — only the
label is removed here.
```

- [ ] **Step 4: Verify the markdown structure**

Run:

```bash
grep -n '^### Step' commands/enrich.md | tail -20
```

Expected: in the Forgejo section (after the `## Forgejo` heading), the sequence
reads `Step 1`, `Step 1.5`, `Step 2`, `Step 2.5`, `Step 3`, `Step 4`, `Step 5`,
`Step 6`, `Step 7` — matching the GitHub section's structure from Task 2.

- [ ] **Step 5: Commit**

```bash
git add commands/enrich.md
git commit -m "feat(enrich): add concurrency lock to Forgejo section

Mirrors the GitHub section's lock (Task 2): Step 1.5 detects an
existing enrichment-ongoing lock via the label-PUT pattern tea
requires, Step 2.5 acquires it before brainstorming, Step 6 releases
it alongside the existing readiness-label cleanup.

See docs/superpowers/specs/2026-08-04-enrich-lock-design.md."
```

---

## Manual Verification (after both Task 2 and Task 3)

Not a task on its own — run once both forge sections are done, against a scratch
issue on each forge, per the spec's Testing section:

1. Pre-apply `enrichment-ongoing` + a fresh lock comment on a test issue. Run
   `/enrich <issue>`. Expected: hard stop at Step 1.5, no brainstorming started.
2. Edit the lock comment's timestamp to >4h in the past. Re-run `/enrich <issue>`.
   Expected: stale/takeover prompt fires; answering "no" stops, answering "yes"
   proceeds to Step 2.
3. Run `/enrich <issue>` end-to-end on an unlocked issue. Expected: the
   `enrichment-ongoing` label and lock comment appear before brainstorming starts
   (Step 2.5), and the label (but not the comment) is gone after Step 6.
