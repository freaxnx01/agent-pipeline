---
description: Phased enrich (spec → /clear → plan → /clear → issue body), isolated context per phase
argument-hint: <issue number>
---

Detect the forge, then run the matching section below.

```bash
source "$HOME/.claude/scripts/lib/detect-forge.sh"
detect_forge
```

## GitHub

Like `/enrich`, but runs each heavy phase in its **own fresh context**, with a
`/handoff` + `/clear` between phases so brainstorm context doesn't bleed into
plan-writing and plan context doesn't bleed into the issue update. Use this instead
of `/enrich` when the topic is large or the session is already long.

You **cannot** run `/clear` yourself — it's the user's keystroke. So this command is
a **re-entrant state machine**: it runs one phase, records progress, writes a resume
handoff, and stops; after the user `/clear`s and resumes, it picks up the next phase.

### State

Track progress in `.claude/enrich-phased.state` (create `.claude/` if needed), a few
`key=value` lines: `issue=`, `phase=`, `spec=`, `plan=`. This file is the source of
truth for which phase runs next.

On invocation:

1. If an issue number was passed as an argument (strip any leading `#`), start a new
   run: write `issue=<N>` and `phase=spec`.
2. Else read `.claude/enrich-phased.state` and continue from its `phase`. If no
   argument and no state file, tell the user there's nothing to resume and stop.

Then dispatch to the matching phase below.

### Phase `spec`

1. `gh issue view <issue> --comments`. If the issue is closed, already has
   `ai-implement`, or is `🧊 parked`, stop and say so.
2. **Check for an existing enrichment lock — only on a new run** (an issue number
   was passed as this invocation's argument, per *On invocation* step 1 above; skip
   this step entirely when resuming from the state file, since that is the same run
   continuing, not a second session). If the issue carries the `enrichment-ongoing`
   label, scan the comments already fetched in step 1 for the most recent
   `🔒 Enrichment lock (re-)acquired at <timestamp>` line and compute its age:
   - No `enrichment-ongoing` label → continue to step 3.
   - Label present, a matching comment found, age < 24 hours → **stop**. Tell the
     user the issue is already being enriched (show the age) and end the command —
     do not write `issue=`/`phase=` to the state file, do not run step 3 or start
     brainstorming.
   - Label present, age ≥ 24 hours, or no matching comment found (treat unknown age
     as stale) → tell the user the lock looks abandoned (show age and the 24h
     threshold) and ask whether to take over.
     - No → stop, same as above.
     - Yes → continue to step 3; step 4 will re-acquire the lock and note the
       takeover.
3. Assess readiness (acceptance criteria + scope + no blocking unknowns). If it's
   already complete, say so, suggest `/gh:implement <issue>`, clear the state file,
   and stop.
4. **Acquire the enrichment lock** — before starting brainstorming, the expensive
   shared resource two sessions could collide on. Make sure the label exists first:

   ```bash
   gh label create enrichment-ongoing --color FBCA04 \
     --description "Another /enrich session is actively enriching this issue — do not start a second one" \
     2>/dev/null || true
   ```

   Post the timestamp comment before applying the label — a label with no matching
   comment reads as "unknown age → stale" to step 2's check, defeating detection.
   Fresh acquisition (step 2 found no lock):

   ```bash
   gh issue comment <issue> --body "🔒 Enrichment lock acquired at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
   ```

   Takeover of a stale lock (step 2 found one and the user agreed to take over —
   substitute the actual age you showed the user for `<Xh>`):

   ```bash
   gh issue comment <issue> --body "🔒 Enrichment lock re-acquired at $(date -u +%Y-%m-%dT%H:%M:%SZ) (previous lock stale, <Xh> old)"
   ```

   Note the exact timestamp you posted, then apply the label:

   ```bash
   gh issue edit <issue> --add-label enrichment-ongoing
   ```

   **Then re-check for a competitor** — step 2 and this step are not atomic (the
   readiness check, and on the takeover path a user prompt, sit between them).
   Re-fetch comments:

   ```bash
   gh issue view <issue> --comments
   ```

   Look for a `🔒 Enrichment lock (re-)acquired` comment that is **not** the one you
   just posted and was **not** already present at step 2. If one exists and its
   timestamp is earlier than yours (same second → the one listed first wins), you
   lost the race. Stand down:

   ```bash
   gh issue comment <issue> --body "🔓 Enrichment lock released at $(date -u +%Y-%m-%dT%H:%M:%SZ) (lost race to the lock acquired at <winner timestamp>)"
   ```

   Leave the `enrichment-ongoing` label in place — the winning session depends on
   it. Tell the user another session won the race, do not write `issue=`/`phase=` to
   the state file, and end the command without brainstorming.

   Otherwise the lock is yours — continue to step 5.
5. Invoke **superpowers:brainstorming** with the issue as context. Follow it
   end-to-end — clarifying questions, approaches, design sections, the spec
   self-review, and the **user approval gate**. Save the spec to the repo's tracked
   specs dir (see *Choosing a tracked path*), commit it, and record `spec=<path>`.

   **If the user declines the approval gate** (does not approve the spec), release
   the lock before stopping:

   ```bash
   gh issue edit <issue> --remove-label enrichment-ongoing 2>/dev/null || true
   ```

6. **Phase boundary** (see *Between phases*): set `phase=plan`, hand off, stop.

### Phase `plan`

1. Re-open the spec at `spec=` to re-establish context.
2. Invoke **superpowers:writing-plans** to produce the task-by-task implementation
   plan in the repo's tracked plans dir. Commit it and record `plan=<path>`.
   **Do not stop at writing-plans' own "Subagent-Driven or Inline Execution?"
   handoff prompt — don't even print it.** That's the skill's generic ending, not
   this phase's; `/enrich-phased` dispatches via the issue body + `ai-implement`
   label, not local execution. Suppress the question entirely: don't ask it,
   don't wait for an answer, don't execute the plan. Treat it as written the
   moment the skill exits and continue to step 3.
3. **Push** so both spec and plan are on the remote (the agent-workflow checks them
   out): `git push`. Verify it succeeded. **If the push fails and you stop here**,
   release the enrichment lock before ending — it was acquired back in Phase
   `spec` and nothing else will release it if this run doesn't continue:

   ```bash
   gh issue edit <issue> --remove-label enrichment-ongoing 2>/dev/null || true
   ```

4. **Phase boundary:** set `phase=issue`, hand off, stop.

### Phase `issue`

1. Replace the issue body (`gh issue edit <issue> --body-file …`) with:
   - the original description (keep it for humans),
   - an `## Acceptance Criteria` section as a `- [ ]` checklist,
   - an `## Implementation Plan` section with the **full plan content inlined
     verbatim** (not a link) — read `plan=` and paste its contents in, so the
     implementing agent can work from the issue body alone with no extra file reads,
   - a `## Spec` section with just the relative path to `spec=` (linked as
     markdown) — human/reviewer reference only, not needed by the implementing agent.
2. Clear the readiness labels — `needs-enrichment` and `❓ to-be-defined` mean
   "not ready yet," and the issue now is. `/gh:implement` treats either as a
   hard stop regardless of body content, so leaving one on is a silent trap.
   Also release the enrichment lock acquired back in Phase `spec` — the run is
   done, nothing else will clear it:

   ```bash
   gh issue edit <issue> --remove-label needs-enrichment 2>/dev/null || true
   gh issue edit <issue> --remove-label "❓ to-be-defined" 2>/dev/null || true
   gh issue edit <issue> --remove-label enrichment-ongoing 2>/dev/null || true
   ```

   (run each on its own line with `|| true` — a repo that doesn't define one of
   these label conventions would otherwise error on the `--remove-label`)
3. Push if anything else is pending.
4. **Done:** delete `.claude/enrich-phased.state` and `.claude/handoff.md`. Print the
   issue URL, the spec and plan paths, and: *"Issue is ready — run
   `/gh:implement <issue>` to trigger the agent-workflow."*

### Between phases (handoff protocol)

At each phase boundary, before stopping:

1. Ensure the phase's artifact is committed (and pushed where the phase says so).
2. Update `.claude/enrich-phased.state` with the new `phase` and any new path.
3. Write `.claude/handoff.md` — a short, self-contained resume prompt that names the
   issue, the next phase, the spec/plan paths so far, and says: **"Resume by running
   `/enrich-phased` (no argument) — it will continue at phase `<next>` from
   `.claude/enrich-phased.state`."** The `SessionStart(clear)` hook auto-injects this
   file, so after `/clear` the user only needs to say `go` (or `/pickup`).
4. Copy that resume prompt to the clipboard (`clip.exe` / `pbcopy` / `wl-copy` /
   `xclip` — whichever exists).
5. Tell the user: phase done, artifact path, and **"run `/clear`, then `go` (or
   `/pickup`) to continue."** Note you cannot run `/clear` yourself. Then stop.

### Choosing a tracked path

The agent-workflow can only read files that are **committed and not git-ignored**.
Some repos `.gitignore` the superpowers docs dir. So before writing a spec/plan:

- Pick an existing **tracked** specs/plans dir if present (e.g.
  `docs/ai-notes/specs` + `docs/ai-notes/plans`, or `docs/superpowers/specs` +
  `…/plans` **only if not ignored**).
- Never write to a path that `git check-ignore -q <path>` reports as ignored — if the
  default target is ignored, fall back to `docs/ai-notes/{specs,plans}`.
- Confirm with `git status`/`git ls-files` that the committed file is actually tracked
  before the push phase relies on it.

### Tools

`gh` (issue read/edit), `git` (commit/push, `check-ignore`), **superpowers:brainstorming**,
**superpowers:writing-plans**, and the `/handoff`-style `.claude/handoff.md` +
`SessionStart(clear)` hook for cross-`/clear` resume.

---

If you run into blockers (ignored docs dir, push auth, brainstorming/writing-plans
unavailable, state file lost), find a solution and update this command for the future.

## Forgejo

Like `/enrich`, but runs each heavy phase in its **own fresh context**, with a
`/handoff` + `/clear` between phases so brainstorm context doesn't bleed into
plan-writing and plan context doesn't bleed into the issue update. Use this instead
of `/enrich` when the topic is large or the session is already long.

You **cannot** run `/clear` yourself — it's the user's keystroke. So this command is
a **re-entrant state machine**: it runs one phase, records progress, writes a resume
handoff, and stops; after the user `/clear`s and resumes, it picks up the next phase.

### Forgejo access

Target the homelab Forgejo (`git.home.freaxnx01.ch`) via **`tea`** (login
`git-home`). Resolve the repo at the start of each phase:

```bash
url=$(git remote get-url origin); url=${url%.git}
repo=$(echo "$url" | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#')
```

### State

Track progress in `.claude/fj-enrich-phased.state` (create `.claude/` if needed), a
few `key=value` lines: `issue=`, `phase=`, `spec=`, `plan=`. This file is the source
of truth for which phase runs next.

On invocation:

1. If an issue number was passed as an argument (strip any leading `#`), start a new
   run: write `issue=<N>` and `phase=spec`.
2. Else read `.claude/fj-enrich-phased.state` and continue from its `phase`. If no
   argument and no state file, tell the user there's nothing to resume and stop.

Then dispatch to the matching phase below.

### Phase `spec`

1. `tea issues <issue> --login git-home` + `tea api --login git-home
   "repos/$repo/issues/<issue>/comments"`. If the issue is closed or `🧊 parked`,
   stop and say so.
2. **Check for an existing enrichment lock — only on a new run** (an issue number
   was passed as this invocation's argument, per *On invocation* step 1 above; skip
   this step entirely when resuming from the state file, since that is the same run
   continuing, not a second session). If the issue carries the `enrichment-ongoing`
   label, scan the comments already fetched in step 1 for the most recent
   `🔒 Enrichment lock (re-)acquired at <timestamp>` line and compute its age:
   - No `enrichment-ongoing` label → continue to step 3.
   - Label present, a matching comment found, age < 24 hours → **stop**. Tell the
     user the issue is already being enriched (show the age) and end the command —
     do not write `issue=`/`phase=` to the state file, do not run step 3 or start
     brainstorming.
   - Label present, age ≥ 24 hours, or no matching comment found (treat unknown age
     as stale) → tell the user the lock looks abandoned (show age and the 24h
     threshold) and ask whether to take over.
     - No → stop, same as above.
     - Yes → continue to step 3; step 4 will re-acquire the lock and note the
       takeover.
3. Assess readiness (acceptance criteria + scope + no blocking unknowns). If it's
   already complete, say so, suggest `/work <issue>`, clear the state file, and
   stop.
4. **Acquire the enrichment lock** — before starting brainstorming. `tea` has no
   per-issue label add/remove subcommand, so read the current labels and PUT back
   the set with `enrichment-ongoing` added (same pattern `/enrich`'s Forgejo
   section and this file's own Phase `issue` label-clearing step use):

   ```bash
   tea labels create --login git-home --name enrichment-ongoing --color "#fbca04" \
     --description "Another /enrich session is actively enriching this issue — do not start a second one" \
     2>/dev/null || true
   ```

   Post the timestamp comment before applying the label — a label with no matching
   comment reads as "unknown age → stale" to step 2's check, defeating detection.
   Fresh acquisition (step 2 found no lock):

   ```bash
   tea api --login git-home -X POST "repos/$repo/issues/<issue>/comments" \
     -f body="🔒 Enrichment lock acquired at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
   ```

   Takeover of a stale lock (step 2 found one and the user agreed to take over —
   substitute the actual age you showed the user for `<Xh>`):

   ```bash
   tea api --login git-home -X POST "repos/$repo/issues/<issue>/comments" \
     -f body="🔒 Enrichment lock re-acquired at $(date -u +%Y-%m-%dT%H:%M:%SZ) (previous lock stale, <Xh> old)"
   ```

   Note the exact timestamp you posted, then apply the label:

   ```bash
   current=$(tea api --login git-home "repos/$repo/issues/<issue>" | jq -r '[.labels[].name]')
   locked=$(echo "$current" | jq -c '. + ["enrichment-ongoing"] | unique')
   tea api --login git-home -X PUT "repos/$repo/issues/<issue>/labels" -f labels="$locked" >/dev/null
   ```

   **Then re-check for a competitor** — step 2 and this step are not atomic (the
   readiness check, and on the takeover path a user prompt, sit between them).
   Re-fetch comments:

   ```bash
   tea api --login git-home "repos/$repo/issues/<issue>/comments"
   ```

   Look for a `🔒 Enrichment lock (re-)acquired` comment that is **not** the one you
   just posted and was **not** already present at step 2. If one exists and its
   timestamp is earlier than yours (same second → lowest comment `id` wins), you
   lost the race. Stand down:

   ```bash
   tea api --login git-home -X POST "repos/$repo/issues/<issue>/comments" \
     -f body="🔓 Enrichment lock released at $(date -u +%Y-%m-%dT%H:%M:%SZ) (lost race to the lock acquired at <winner timestamp>)"
   ```

   Leave the `enrichment-ongoing` label in place — the winning session depends on
   it. Tell the user another session won the race, do not write `issue=`/`phase=` to
   the state file, and end the command without brainstorming.

   Otherwise the lock is yours — continue to step 5.
5. Invoke **superpowers:brainstorming** with the issue as context. Follow it
   end-to-end — clarifying questions, approaches, design sections, the spec
   self-review, and the **user approval gate**. Save the spec to the repo's tracked
   specs dir (see *Choosing a tracked path*), commit it, and record `spec=<path>`.

   **If the user declines the approval gate** (does not approve the spec), release
   the lock before stopping:

   ```bash
   current=$(tea api --login git-home "repos/$repo/issues/<issue>" | jq -r '[.labels[].name]')
   kept=$(echo "$current" | jq -c '[.[] | select(. != "enrichment-ongoing")]')
   tea api --login git-home -X PUT "repos/$repo/issues/<issue>/labels" -f labels="$kept" >/dev/null
   ```

6. **Phase boundary** (see *Between phases*): set `phase=plan`, hand off, stop.

### Phase `plan`

1. Re-open the spec at `spec=` to re-establish context.
2. Invoke **superpowers:writing-plans** to produce the task-by-task plan in the
   repo's tracked plans dir. Commit it and record `plan=<path>`.
   **Do not stop at writing-plans' own "Subagent-Driven or Inline Execution?"
   handoff prompt — don't even print it.** That's the skill's generic ending, not
   this phase's; `/enrich-phased` dispatches via the issue body + `ai-implement`
   label, not local execution. Suppress the question entirely: don't ask it,
   don't wait for an answer, don't execute the plan. Treat it as written the
   moment the skill exits and continue to step 3.
3. **Push** so both spec and plan are on the remote: `git push`. Verify it
   succeeded. **If the push fails and you stop here**, release the enrichment
   lock before ending — it was acquired back in Phase `spec` and nothing else
   will release it if this run doesn't continue:

   ```bash
   current=$(tea api --login git-home "repos/$repo/issues/<issue>" | jq -r '[.labels[].name]')
   kept=$(echo "$current" | jq -c '[.[] | select(. != "enrichment-ongoing")]')
   tea api --login git-home -X PUT "repos/$repo/issues/<issue>/labels" -f labels="$kept" >/dev/null
   ```

4. **Phase boundary:** set `phase=issue`, hand off, stop.

### Phase `issue`

1. Replace the issue body via API PATCH using the **typed** field `-F` so the file
   is read (`-f` stores the literal string; `tea issues edit` has no body flag):
   `tea api -X PATCH "repos/$repo/issues/<issue>" -F body=@bodyfile.md` — with:
   - the original description (keep it for humans),
   - an `## Acceptance Criteria` section as a `- [ ]` checklist,
   - a `## Spec & Implementation Plan` section linking the **relative paths** to
     `spec=` and `plan=`, plus: *"Read the plan before writing any code — it contains
     the full task breakdown, file structure, TDD steps, and exact code."*
2. Clear the readiness labels — `needs-enrichment` and `❓ to-be-defined` mean "not
   ready yet," and the issue now is. Also release the enrichment lock acquired
   back in Phase `spec` — the run is done, nothing else will clear it. `tea` has
   no per-issue label add/remove subcommand, so read-filter-PUT:

   ```bash
   current=$(tea api --login git-home "repos/$repo/issues/<issue>" | jq -r '[.labels[].name]')
   kept=$(echo "$current" | jq -c '[.[] | select(. != "needs-enrichment" and . != "❓ to-be-defined" and . != "enrichment-ongoing")]')
   tea api --login git-home -X PUT "repos/$repo/issues/<issue>/labels" -f labels="$kept" >/dev/null
   ```

3. Push if anything else is pending.
4. **Done:** delete `.claude/fj-enrich-phased.state` and `.claude/handoff.md`. Print
   the issue URL, the spec and plan paths, and: *"Issue is ready — run
   `/work <issue>` to implement it locally."*

> When the self-hosted **Forgejo Actions** agent-workflow exists (future tier), the
> final pointer becomes "apply `ai-implement` / run `/fj:implement`" instead.

### Between phases (handoff protocol)

At each phase boundary, before stopping:

1. Ensure the phase's artifact is committed (and pushed where the phase says so).
2. Update `.claude/fj-enrich-phased.state` with the new `phase` and any new path.
3. Write `.claude/handoff.md` — a short, self-contained resume prompt that names the
   issue, the next phase, the spec/plan paths so far, and says: **"Resume by running
   `/enrich-phased` (no argument) — it will continue at phase `<next>` from
   `.claude/fj-enrich-phased.state`."** The `SessionStart(clear)` hook auto-injects
   this file, so after `/clear` the user only needs to say `go` (or `/pickup`).
4. Copy that resume prompt to the clipboard (`clip.exe` / `pbcopy` / `wl-copy` /
   `xclip` — whichever exists).
5. Tell the user: phase done, artifact path, and **"run `/clear`, then `go` (or
   `/pickup`) to continue."** Note you cannot run `/clear` yourself. Then stop.

### Choosing a tracked path

The implementer can only read files that are **committed and not git-ignored**. Pick
an existing **tracked** specs/plans dir; never write to a path that `git check-ignore
-q <path>` reports as ignored — fall back to `docs/ai-notes/{specs,plans}`. Confirm
with `git ls-files` that the committed file is tracked before the push phase relies
on it.

### Tools

`tea` (issue read/edit via api PATCH), `git` (commit/push, `check-ignore`),
**superpowers:brainstorming**, **superpowers:writing-plans**, and the
`/handoff`-style `.claude/handoff.md` + `SessionStart(clear)` hook for cross-`/clear`
resume.

---

If you run into blockers (ignored docs dir, push auth, brainstorming/writing-plans
unavailable, state file lost, body PATCH rejected), find a solution and update this
command for the future.

## Unknown host

Report the detected host and that no authed GitHub or Forgejo login matched
it; point at `gh auth login` / `tea login add`. Don't guess a forge.
