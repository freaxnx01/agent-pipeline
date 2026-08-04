# /enrich-phased Concurrency Lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `/enrich`'s concurrency lock (`enrichment-ongoing` label + timestamped comment, issue #229 / PR #233) to `/enrich-phased`, adapted to its phase/`` `/clear` `` structure, using a 24-hour staleness window instead of `/enrich`'s 4-hour one.

**Architecture:** All lock logic lives inside Phase `spec` — the only point in the phased flow equivalent to `/enrich`'s Step 1.5/2.5 — gated to run only on a genuinely new run (an issue number passed as this invocation's argument), never on a state-file resume. Detection and acquisition are added as new numbered steps within Phase `spec`, renumbering its existing steps; a release-on-early-abort note is added to Phase `plan`'s push-verification step; the final release is folded into Phase `issue`'s existing label-clearing step. Mirrored identically across the GitHub (`gh`) and Forgejo (`tea`) sections.

**Tech Stack:** Markdown instruction file (`commands/enrich-phased.md`), `gh` CLI (GitHub), `tea` CLI (Forgejo), plain bash (`date -u`, `jq`).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-04-enrich-phased-lock-design.md`
- No new scripts or application code — this is a `commands/enrich-phased.md` instruction change plus one follow-up update to `docs/superpowers/specs/2026-08-04-enrich-lock-design.md`.
- Staleness threshold: **24 hours** (not `/enrich`'s 4h), computed from ISO 8601 UTC timestamps (`date -u +%Y-%m-%dT%H:%M:%SZ`).
- Lock label name/color/description and comment marker format are **identical** to `/enrich`'s (already registered by `scripts/ensure-issue-labels.sh` per #229): label `enrichment-ongoing`; comment `🔒 Enrichment lock acquired at <timestamp>` (fresh) or `🔒 Enrichment lock re-acquired at <timestamp> (previous lock stale, <Xh> old)` (takeover); release comment `🔓 Enrichment lock released at <timestamp> (lost race to the lock acquired at <winner timestamp>)`. Reusing the exact format is what makes `/enrich` and `/enrich-phased` detect each other's locks — do not invent a second label or a differently-worded comment.
- The detect/acquire logic is added **only** to Phase `spec`, gated on "this invocation started a new run" (per the file's existing "On invocation" step 1 — an issue number was passed as the argument). Phase `plan` and Phase `issue` do not re-verify the lock; they trust it's still held from Phase `spec`'s acquisition (per the spec's Non-goals — accepted tradeoff, not a bug to fix here).
- This command has no automated test suite; verification is the manual dry-run scenarios in the spec's Testing section, reproduced per-task below.

---

### Task 1: Add the lock to `/enrich-phased`'s GitHub section

**Files:**
- Modify: `commands/enrich-phased.md` (GitHub section — Phase `spec`, Phase `plan`, Phase `issue`, as they exist under the `## GitHub` heading)

**Interfaces:**
- Consumes: the `enrichment-ongoing` label already registered by `scripts/ensure-issue-labels.sh` (#229) — this task also re-creates it inline (same as `/enrich`'s Step 2.5 does), since `/enrich-phased` can run standalone against repos that haven't run that script.
- Produces: nothing consumed by other tasks — Task 2 is the independent Forgejo mirror.

- [ ] **Step 1: Replace Phase `spec`'s step list with the detect/acquire-augmented version**

Find this exact block:

```markdown
### Phase `spec`

1. `gh issue view <issue> --comments`. If the issue is closed, already has
   `ai-implement`, or is `🧊 parked`, stop and say so.
2. Assess readiness (acceptance criteria + scope + no blocking unknowns). If it's
   already complete, say so, suggest `/gh:implement <issue>`, clear the state file,
   and stop.
3. Invoke **superpowers:brainstorming** with the issue as context. Follow it
   end-to-end — clarifying questions, approaches, design sections, the spec
   self-review, and the **user approval gate**. Save the spec to the repo's tracked
   specs dir (see *Choosing a tracked path*), commit it, and record `spec=<path>`.
4. **Phase boundary** (see *Between phases*): set `phase=plan`, hand off, stop.
```

Replace it with:

```markdown
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
```

- [ ] **Step 2: Add release-on-push-failure to Phase `plan`**

Find this exact block:

```markdown
3. **Push** so both spec and plan are on the remote (the agent-workflow checks them
   out): `git push`. Verify it succeeded.
4. **Phase boundary:** set `phase=issue`, hand off, stop.
```

Replace it with:

```markdown
3. **Push** so both spec and plan are on the remote (the agent-workflow checks them
   out): `git push`. Verify it succeeded. **If the push fails and you stop here**,
   release the enrichment lock before ending — it was acquired back in Phase
   `spec` and nothing else will release it if this run doesn't continue:

   ```bash
   gh issue edit <issue> --remove-label enrichment-ongoing 2>/dev/null || true
   ```
4. **Phase boundary:** set `phase=issue`, hand off, stop.
```

- [ ] **Step 3: Add the final release to Phase `issue`'s label-clearing step**

Find this exact block:

```markdown
2. Clear the readiness labels — `needs-enrichment` and `❓ to-be-defined` mean
   "not ready yet," and the issue now is. `/gh:implement` treats either as a
   hard stop regardless of body content, so leaving one on is a silent trap:

   ```bash
   gh issue edit <issue> --remove-label needs-enrichment 2>/dev/null || true
   gh issue edit <issue> --remove-label "❓ to-be-defined" 2>/dev/null || true
   ```

   (run each on its own line with `|| true` — a repo that doesn't define one of
   the two label conventions would otherwise error on the `--remove-label`)
```

Replace it with:

```markdown
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
```

- [ ] **Step 4: Verify the markdown structure**

Run:

```bash
sed -n '/^## GitHub$/,/^## Forgejo$/p' commands/enrich-phased.md | grep -nE '^[0-9]+\.'
```

Expected: Phase `spec`'s list now runs 1 through 6 with no gaps or duplicate
numbers; Phase `plan` and Phase `issue` still run 1 through 4 and 1 through 4
respectively (unchanged step counts, just added content inside existing steps).

- [ ] **Step 5: Commit**

```bash
git add commands/enrich-phased.md
git commit -m "feat(enrich-phased): add concurrency lock to GitHub section

Mirrors /enrich's lock (#229/#233) inside Phase \`spec\`: new steps 2/4
detect an existing enrichment-ongoing lock (24h staleness, vs /enrich's
4h) and acquire + race-recheck before brainstorming starts. Phase
\`plan\` releases on push failure; Phase \`issue\` releases on success
alongside the existing readiness-label cleanup.

See docs/superpowers/specs/2026-08-04-enrich-phased-lock-design.md."
```

---

### Task 2: Add the lock to `/enrich-phased`'s Forgejo section

**Files:**
- Modify: `commands/enrich-phased.md` (Forgejo section — Phase `spec`, Phase `plan`, Phase `issue`, as they exist under the `## Forgejo` heading)

**Interfaces:**
- Consumes: nothing from Task 1 — the Forgejo section is a self-contained mirror using `tea` instead of `gh`. Uses the same label name/color/description and comment format constants defined in Global Constraints above.
- Produces: nothing consumed elsewhere.

- [ ] **Step 1: Replace Phase `spec`'s step list with the detect/acquire-augmented version**

Find this exact block:

```markdown
### Phase `spec`

1. `tea issues <issue> --login git-home` + `tea api --login git-home
   "repos/$repo/issues/<issue>/comments"`. If the issue is closed or `🧊 parked`,
   stop and say so.
2. Assess readiness (acceptance criteria + scope + no blocking unknowns). If it's
   already complete, say so, suggest `/work <issue>`, clear the state file, and
   stop.
3. Invoke **superpowers:brainstorming** with the issue as context. Follow it
   end-to-end — clarifying questions, approaches, design sections, the spec
   self-review, and the **user approval gate**. Save the spec to the repo's tracked
   specs dir (see *Choosing a tracked path*), commit it, and record `spec=<path>`.
4. **Phase boundary** (see *Between phases*): set `phase=plan`, hand off, stop.
```

Replace it with:

```markdown
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
```

- [ ] **Step 2: Add release-on-push-failure to Phase `plan`**

Find this exact block:

```markdown
3. **Push** so both spec and plan are on the remote: `git push`. Verify it succeeded.
4. **Phase boundary:** set `phase=issue`, hand off, stop.
```

Replace it with:

```markdown
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
```

- [ ] **Step 3: Add the final release to Phase `issue`'s label-clearing step**

Find this exact block:

```markdown
2. Clear the readiness labels — `needs-enrichment` and `❓ to-be-defined` mean "not
   ready yet," and the issue now is. `tea` has no per-issue label add/remove
   subcommand, so read-filter-PUT:

   ```bash
   current=$(tea api --login git-home "repos/$repo/issues/<issue>" | jq -r '[.labels[].name]')
   kept=$(echo "$current" | jq -c '[.[] | select(. != "needs-enrichment" and . != "❓ to-be-defined")]')
   tea api --login git-home -X PUT "repos/$repo/issues/<issue>/labels" -f labels="$kept" >/dev/null
   ```
```

Replace it with:

```markdown
2. Clear the readiness labels — `needs-enrichment` and `❓ to-be-defined` mean "not
   ready yet," and the issue now is. Also release the enrichment lock acquired
   back in Phase `spec` — the run is done, nothing else will clear it. `tea` has
   no per-issue label add/remove subcommand, so read-filter-PUT:

   ```bash
   current=$(tea api --login git-home "repos/$repo/issues/<issue>" | jq -r '[.labels[].name]')
   kept=$(echo "$current" | jq -c '[.[] | select(. != "needs-enrichment" and . != "❓ to-be-defined" and . != "enrichment-ongoing")]')
   tea api --login git-home -X PUT "repos/$repo/issues/<issue>/labels" -f labels="$kept" >/dev/null
   ```
```

- [ ] **Step 4: Verify the markdown structure**

Run:

```bash
sed -n '/^## Forgejo$/,/^## Unknown host$/p' commands/enrich-phased.md | grep -nE '^[0-9]+\.'
```

Expected: Phase `spec`'s list now runs 1 through 6 with no gaps or duplicate
numbers; Phase `plan` and Phase `issue` still run 1 through 4 respectively
(unchanged step counts, just added content inside existing steps).

- [ ] **Step 5: Commit**

```bash
git add commands/enrich-phased.md
git commit -m "feat(enrich-phased): add concurrency lock to Forgejo section

Mirrors Task 1's GitHub-section lock via tea's label-PUT pattern:
Phase \`spec\` steps 2/4 detect and acquire (24h staleness), Phase
\`plan\` releases on push failure, Phase \`issue\` releases on success.

See docs/superpowers/specs/2026-08-04-enrich-phased-lock-design.md."
```

---

### Task 3: Close the loop on #229's spec Follow-up

**Files:**
- Modify: `docs/superpowers/specs/2026-08-04-enrich-lock-design.md`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing — documentation-only closure of a note left by the original spec.

- [ ] **Step 1: Update the Follow-ups section**

Find this exact block:

```markdown
## Follow-ups (out of scope here)

- Apply the same lock mechanism to `/enrich-phased`.
- Consider whether the "same person resuming" self-collision case is worth
  special-casing later (e.g. embedding a session/host identifier in the lock
  comment) if it proves annoying in practice.
```

Replace it with:

```markdown
## Follow-ups (out of scope here)

- ~~Apply the same lock mechanism to `/enrich-phased`.~~ Done — see
  `docs/superpowers/specs/2026-08-04-enrich-phased-lock-design.md` (issue
  #237).
- Consider whether the "same person resuming" self-collision case is worth
  special-casing later (e.g. embedding a session/host identifier in the lock
  comment) if it proves annoying in practice.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-08-04-enrich-lock-design.md
git commit -m "docs(enrich-lock): mark the enrich-phased follow-up as done

Closed by docs/superpowers/specs/2026-08-04-enrich-phased-lock-design.md (#237)."
```

---

## Manual Verification (after Tasks 1 and 2)

Not a task on its own — run once both forge sections are done, against a
scratch issue on each forge, per the spec's Testing section:

1. Pre-apply `enrichment-ongoing` + a fresh lock comment on a test issue. Run
   `/enrich-phased <issue>` (new run). Expected: hard stop in Phase `spec`'s
   new step 2, before readiness assessment or brainstorming, and
   `.claude/enrich-phased.state` (or `.claude/fj-enrich-phased.state`) is
   never written.
2. Backdate the lock comment past 24h. Re-run `/enrich-phased <issue>`.
   Expected: stale/takeover prompt fires; "no" stops, "yes" proceeds.
3. Run `/enrich-phased <issue>` end-to-end across all three phases (with the
   `/clear` boundaries). Expected: the label and lock comment appear before
   brainstorming starts in Phase `spec`, persist through Phase `plan`
   untouched, and the label (not the comment) is gone after Phase `issue`
   completes.
4. Cross-command check: lock an issue via `/enrich` (its Step 2.5), then run
   `/enrich-phased` on the same issue. Expected: Phase `spec`'s new step 2
   correctly sees `/enrich`'s lock and hard-stops. Repeat in reverse (lock
   via `/enrich-phased`, then run `/enrich`) to confirm `/enrich`'s existing
   Step 1.5 sees it too.
5. Resume check: start a run, let it stop at the Phase `spec` → `plan`
   boundary (normal handoff), `/clear`, resume with no argument. Expected:
   Phase `plan` proceeds directly with no lock-detection output (the new
   step 2 in Phase `spec` never re-runs on a resume).
