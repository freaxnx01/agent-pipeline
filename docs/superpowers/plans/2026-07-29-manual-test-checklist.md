# Manual-Test Checklist Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/manual-test` user-level slash command that shows a checklist
of user-facing changes on `main` since a personal, local "last tested"
bookmark, and a `/manual-test done` verb that advances that bookmark.

**Architecture:** A single new procedural command file
(`commands/manual-test.md`) — Claude Code interprets the file's instructions
at invocation time, there is no compiled/runtime code. The bookmark is a
two-line, gitignored, per-repo state file (`.claude/manual-test-bookmark.md`)
in whichever repo the command is run from. Because this is a prompt file, not
code, "tests" in this plan mean empirically verifying the exact `git` command
sequence the file instructs Claude to run — against a real scratch repo —
before those commands are baked into the prompt.

**Tech Stack:** Markdown command file (Claude Code slash-command convention),
`git` CLI (`fetch`, `merge-base --is-ancestor`, `log`, `rev-parse`), `bash`.

## Global Constraints

- Spec of record: `docs/superpowers/specs/2026-07-29-manual-test-checklist-design.md`.
- Bookmark file path is exactly `.claude/manual-test-bookmark.md`, gitignored
  individually (never gitignore the whole `.claude/` directory — other files
  under it, e.g. handoff files, are committed elsewhere in this repo's
  conventions).
- The command always compares against `origin/main`, never the current
  checked-out branch.
- Commit types `chore`, `docs`, `ci`, `test`, `refactor` are excluded from the
  checklist; `feat`, `fix`, `perf`, and unparsed subjects are kept.
- No `gh`/network calls beyond `git fetch` — no issue/PR enrichment.
- Advancing the bookmark (`/manual-test done`) is always explicit, never
  automatic.
- Follow this repo's existing command-file conventions: YAML front-matter
  with a `description:` field, plain numbered/step prose (see
  `commands/handoff.md`, `commands/pickup.md`, `commands/wrap-up.md`,
  `commands/todo.md`), and the closing self-improvement line ("If you run
  into blockers, find a solution and update this skill for the future.")
  that `commands/todo.md` and `commands/pickup.md` already use.

---

### Task 1: Verify the git command sequence against a scratch repo

**Files:**
- None created/modified — this task only runs commands in a throwaway
  directory to prove the exact `git` invocations Task 2 will encode behave
  as the spec expects. Use the scratchpad directory, not the agent-workflow
  working tree.

**Interfaces:**
- Produces: a confirmed, exact sequence of `git` commands (fetch, merge-base
  ancestor check, log with `--no-merges --pretty=format:'%H%x09%s'`,
  rev-parse) that Task 2's command file will instruct Claude Code to run.
  Task 2 consumes this verified sequence verbatim.

- [ ] **Step 1: Build a scratch repo with a fake `origin`**

```bash
SCRATCH="$(mktemp -d)"
git init --bare "$SCRATCH/origin.git" -q
git init -q "$SCRATCH/work"
cd "$SCRATCH/work"
git remote add origin "$SCRATCH/origin.git"
git config user.email test@example.com
git config user.name "Test"
git commit --allow-empty -m "chore: initial commit" -q
git branch -M main
git push -u origin main -q
```

- [ ] **Step 2: Add commits that exercise every grouping/filtering case**

```bash
git commit --allow-empty -m "feat(auth): add token refresh" -q
git commit --allow-empty -m "fix(auth): correct expiry check" -q
git commit --allow-empty -m "feat(orders): add cancellation endpoint" -q
git commit --allow-empty -m "chore(deps): bump lodash" -q
git commit --allow-empty -m "docs: update README" -q
git commit --allow-empty -m "tweak stuff" -q
git push origin main -q
BOOKMARK_HASH="$(git rev-parse HEAD~6)"   # the initial "chore: initial commit"
echo "bookmark=$BOOKMARK_HASH"
```

- [ ] **Step 3: Verify `fetch` works against the fake origin**

```bash
GIT_TERMINAL_PROMPT=0 git -c credential.helper= fetch -p origin main
```

Expected: exits 0, no prompt, no error (local filesystem remote needs no
auth — this proves the credential-helper-clearing pattern is harmless when
unneeded, matching the spec's "belt-and-braces" framing).

- [ ] **Step 4: Verify the ancestor check**

```bash
git merge-base --is-ancestor "$BOOKMARK_HASH" origin/main; echo "exit=$?"
```

Expected: `exit=0` (the bookmark commit is an ancestor of `origin/main`).

Then verify the failure path with a bogus hash:

```bash
git merge-base --is-ancestor "$(git hash-object -w --stdin <<<'not a commit' 2>/dev/null || echo deadbeef)" origin/main; echo "exit=$?"
```

Expected: non-zero exit — confirms the command file's "stop and warn" branch
has a real, distinguishable signal to key off.

- [ ] **Step 5: Verify the log format and `--no-merges` filtering**

```bash
git log "$BOOKMARK_HASH..origin/main" --no-merges --pretty=format:'%H%x09%s'
```

Expected output: 6 lines (newest first), each `<full-sha><TAB><subject>`,
covering `feat(auth):`, `fix(auth):`, `feat(orders):`, `chore(deps):`,
`docs:`, and the unparsed `tweak stuff` line. Confirm by eye that:
- tab-separated (`%x09`) parses cleanly into (hash, subject) pairs,
- order is newest-first (so a later grouping step must reverse it for
  oldest-first display, per the spec).

- [ ] **Step 6: Verify `rev-parse` for the `done` verb**

```bash
git rev-parse origin/main
```

Expected: the full 40-char sha of the last pushed commit (`tweak stuff`).

- [ ] **Step 7: Clean up the scratch repo**

```bash
rm -rf "$SCRATCH"
```

- [ ] **Step 8: Record the confirmed command sequence**

No commit for this task (nothing in the working tree changed) — the verified
commands above are what Task 2 encodes into `commands/manual-test.md`. Note
in your own working notes (not committed) that `%x09` is the tab separator
used for parsing, and that `git log` output is newest-first and must be
reversed for the oldest-first rendering the spec requires.

---

### Task 2: Create `commands/manual-test.md`

**Files:**
- Create: `commands/manual-test.md`

**Interfaces:**
- Consumes: the verified `git` command sequence from Task 1 (fetch,
  merge-base ancestor check, `git log <bookmark>..origin/main --no-merges
  --pretty=format:'%H%x09%s'`, `git rev-parse origin/main`).
- Produces: the `/manual-test` and `/manual-test done` command surface,
  consumed by end users (no other task depends on this file's internals).

- [ ] **Step 1: Write the command file**

```markdown
---
description: Show a manual-test checklist of user-facing changes on main since your last bookmark, or advance the bookmark once you're done testing
---

Track what still needs manual testing on `main`, using a personal,
local-only bookmark. Two forms:

- `/manual-test` (no argument) — show what's changed since the bookmark.
- `/manual-test done` — advance the bookmark to `main`'s current HEAD, once
  you've verified everything the checklist listed.

## Bookmark file

The bookmark lives at `.claude/manual-test-bookmark.md` in **this repo** (the
repo the command is run from), and is **local-only — never commit it**. Two
lines:

```
commit: <full 40-char sha>
date: <ISO 8601 timestamp>
```

On first write (either verb below), ensure `.gitignore` contains exactly this
line — not the whole `.claude/` directory, since other files under it (e.g.
handoff files) are intentionally committed:

```bash
grep -qxF '.claude/manual-test-bookmark.md' .gitignore 2>/dev/null || \
  echo '.claude/manual-test-bookmark.md' >> .gitignore
```

## If `$ARGUMENTS` is `done`

1. Refresh `main`:

   ```bash
   GIT_TERMINAL_PROMPT=0 git -c credential.helper= fetch -p origin main
   ```

2. Read `origin/main`'s current HEAD:

   ```bash
   git rev-parse origin/main
   ```

3. Write the bookmark:

   ```bash
   mkdir -p .claude
   {
     echo "commit: $(git rev-parse origin/main)"
     echo "date: $(date -Iseconds)"
   } > .claude/manual-test-bookmark.md
   ```

4. Ensure the `.gitignore` entry exists (see above).

5. Print: `Bookmark advanced to <short-hash> (<date>). Future /manual-test
   runs will show changes after this point.`

Stop here — do not also show the checklist in the same invocation.

## Otherwise (bare `/manual-test`)

1. **Check for a repo with `main`.** If the current directory isn't a git
   repo, or there's no `main` branch/ref, say so and stop. Don't fall back to
   another branch — this command is `main`-specific by design.

2. **Check for a bookmark.** If `.claude/manual-test-bookmark.md` doesn't
   exist, print:

   > No bookmark set yet — run `/manual-test done` to set today's `main` HEAD
   > as your baseline, then `/manual-test` will show what changes going
   > forward.

   and stop. Don't guess a fallback window (e.g. "last N commits").

3. **Refresh `main`:**

   ```bash
   GIT_TERMINAL_PROMPT=0 git -c credential.helper= fetch -p origin main
   ```

4. **Validate the bookmark is still reachable:**

   ```bash
   git merge-base --is-ancestor <bookmark-hash> origin/main
   ```

   If this exits non-zero, the bookmark predates a history rewrite on `main`
   (rare — `main` is protected, no force-push — but the file could also be
   stale or hand-edited). Print a warning explaining the bookmark is no
   longer valid, suggest `/manual-test done` to reset it, and stop. Do not
   attempt the diff in step 5 against an unreachable commit.

5. **Collect commits since the bookmark, excluding merges:**

   ```bash
   git log <bookmark-hash>..origin/main --no-merges --pretty=format:'%H%x09%s'
   ```

   Output is tab-separated `<full-sha>\t<subject>` pairs, newest first. If
   the output is empty, print:

   > No changes since last test (`<short-hash>`, `<date>`) — nothing to
   > verify.

   and stop.

6. **Parse each subject** as Conventional Commits: `type(scope): summary` or
   `type: summary`. A subject matching neither pattern is kept as-is, grouped
   under `other`.

7. **Filter.** Drop commits whose `type` is `chore`, `docs`, `ci`, `test`, or
   `refactor` — these never carry user-facing behavior (same mapping this
   project's own SemVer rules use). Count the drops. Keep `feat`, `fix`,
   `perf`, and unparsed subjects.

8. **Group** the kept commits by `scope` (fallback: `type` when there's no
   scope; `other` when neither parsed). Sort groups alphabetically. Within a
   group, sort oldest-first — reverse the `git log` order, which comes back
   newest-first.

9. **Render and print:**

   ```markdown
   ## Manual test checklist — since <short-hash> (<bookmark-date>)

   ### <scope-1>
   - [ ] <summary> (<type>, <short-hash>)
   - [ ] <summary> (<type>, <short-hash>)

   ### <scope-2>
   - [ ] <summary> (<type>, <short-hash>)

   _Skipped <N> non-user-facing commits (chore/docs/ci/refactor/test)._

   Run `/manual-test done` once you've verified all of the above.
   ```

   Omit the "Skipped" line entirely when `N` is 0.

---

If you run into blockers, find a solution and update this skill for the
future.
```

- [ ] **Step 2: Sanity-check the front-matter**

```bash
cd /home/anim/repos/github/freaxnx01/public/agent-workflow
head -4 commands/manual-test.md
```

Expected: a `---`-delimited YAML block containing only a `description:` key,
matching the shape of `commands/wrap-up.md`'s front-matter (compare with
`head -4 commands/wrap-up.md`).

- [ ] **Step 3: Confirm markdownlint passes**

```bash
cd /home/anim/repos/github/freaxnx01/public/agent-workflow
npx --yes markdownlint-cli2 commands/manual-test.md
```

Expected: no errors. If it flags something (e.g. line length, heading
levels), fix `commands/manual-test.md` and re-run until clean — this repo's
`.markdownlint-cli2.yaml` config applies to every file under `commands/`.

- [ ] **Step 4: Commit**

```bash
cd /home/anim/repos/github/freaxnx01/public/agent-workflow
git add commands/manual-test.md
git commit -m "feat(commands): add /manual-test checklist command

Implements the design in docs/superpowers/specs/2026-07-29-manual-test-checklist-design.md."
```

---

### Task 3: Register the command in `commands/README.md` and end-to-end verify

**Files:**
- Modify: `commands/README.md:57-58`

**Interfaces:**
- Consumes: nothing from Task 1/2 beyond the command's existence.
- Produces: nothing further consumes this — terminal task.

- [ ] **Step 1: Add the README entry**

Current content at `commands/README.md:57-58`:

```markdown
**Idea capture** (forge-agnostic, local — precedes the issue funnel):
`/capture-idea <idea>` — jot an idea into the current repo's `docs/ideas.md`.
```

Replace with:

```markdown
**Idea capture** (forge-agnostic, local — precedes the issue funnel):
`/capture-idea <idea>` — jot an idea into the current repo's `docs/ideas.md`.
`/manual-test [done]` — show a manual-test checklist of user-facing changes
on `main` since your last bookmark, or advance the bookmark once you're done
testing.
```

- [ ] **Step 2: Confirm markdownlint passes on the README**

```bash
cd /home/anim/repos/github/freaxnx01/public/agent-workflow
npx --yes markdownlint-cli2 commands/README.md
```

Expected: no errors. Fix and re-run if it flags anything.

- [ ] **Step 3: End-to-end dry run against a fresh scratch repo**

Rebuild the same scratch repo shape as Task 1 (fresh `mktemp -d`, bare
`origin.git`, `work` clone, same 7 commits including the initial one). Then,
**read `commands/manual-test.md` and manually execute exactly what it
instructs**, playing the role of Claude Code processing the slash command,
for all four cases:

1. **No bookmark yet** — bare `/manual-test` (no `.claude/manual-test-bookmark.md`
   present). Expected: the "No bookmark set yet" message, nothing else
   happens, no file written.

2. **`/manual-test done`** — run the `done` steps against the scratch repo.
   Expected: `.claude/manual-test-bookmark.md` is created with a `commit:`
   line equal to `git rev-parse origin/main` in that scratch repo, and a
   `date:` line; `.gitignore` gains the one-line entry (create `.gitignore`
   if the scratch repo doesn't have one).

3. **Bare `/manual-test` with the bookmark set to `HEAD~6` (before the 6
   feature/fix/chore/docs/tweak commits)** — manually point the bookmark file
   at `HEAD~6`'s sha, then run the bare-command steps. Expected rendered
   checklist has two groups (`auth`, `orders`) with 3 kept commits total,
   plus `other` for `tweak stuff`, a "Skipped 2" footer (the `chore(deps)`
   and `docs` commits), and items within `auth` ordered oldest-first
   (`feat(auth)` before `fix(auth)`).

4. **Bare `/manual-test` immediately after `/manual-test done`** (bookmark
   now at current HEAD, no new commits) — expected: "No changes since last
   test" message.

5. **Bookmark not an ancestor of `origin/main`.** Create a second, unrelated
   scratch repo (`git init` in a fresh `mktemp -d`, one commit, no shared
   history with the first). Take that unrelated repo's commit sha and write
   it into the first scratch repo's `.claude/manual-test-bookmark.md`. Run
   the bare-command steps. Expected: the "bookmark is no longer valid /
   run `/manual-test done` to reset it" warning, and no attempt to run the
   `git log <hash>..origin/main` diff.

6. **Not a git repo.** In a plain `mktemp -d` with no `git init`, run the
   bare-command steps. Expected: the "not a git repo" message, and no
   further steps attempted (no fetch, no bookmark read).

Confirm all six match the spec's edge-case section
(`docs/superpowers/specs/2026-07-29-manual-test-checklist-design.md`,
"Edge cases & first run"). If any step in `commands/manual-test.md` produces
output that doesn't match, fix the command file, re-run
Step 2 (markdownlint), and repeat this dry run until all six pass.

Clean up both scratch repos afterward (`rm -rf` their temp directories).

- [ ] **Step 4: Commit the README change**

```bash
cd /home/anim/repos/github/freaxnx01/public/agent-workflow
git add commands/README.md
git commit -m "docs(commands): list /manual-test in README

Closes #158."
```

(If Step 3 required fixes to `commands/manual-test.md`, amend those into
Task 2's commit instead of adding a separate fix-up commit — check
`git log --oneline -3` first to confirm Task 2's commit hasn't already been
pushed; if it has, make a new `fix(commands):` commit instead of amending
published history.)

- [ ] **Step 5: Push**

```bash
cd /home/anim/repos/github/freaxnx01/public/agent-workflow
set -a; source /home/anim/repos/github/freaxnx01/.envrc; set +a
git -c credential.helper= \
    -c "credential.helper=!f() { echo username=x-access-token; echo password=\$GH_TOKEN; }; f" \
    push origin main
```

Verify the push output shows both commits landing on `origin/main`.
