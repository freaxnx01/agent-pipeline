# Manual-test checklist — design

Issue: [freaxnx01/agent-workflow#158](https://github.com/freaxnx01/agent-workflow/issues/158)

## Problem

There's no way to quickly answer "what changed on `main` that I still need to
manually test?" The user tests changes by hand periodically (not on every
merge); each time, they currently have to reconstruct the list of relevant
commits themselves. This command automates that: it remembers the last commit
the user finished testing (the "bookmark") and, on request, shows everything
user-facing that landed on `main` since then.

## Command surface

**`/manual-test`** — new user-level slash command, forge-agnostic, local-only
(git-based, no GitHub/Forgejo calls). Lives at `commands/manual-test.md`
alongside `capture-idea.md` in the "Idea capture" style category (session-local,
works from any repo's working directory).

Two verbs:

- `/manual-test` (bare) — diff `origin/main` since the saved bookmark, print a
  grouped manual-test checklist.
- `/manual-test done` — advance the bookmark to `origin/main`'s current HEAD
  commit + timestamp, once testing is finished.

Both verbs require the current working directory to be inside a git repo with
a `main` branch. If not, stop with a clear message — no fallback branch
guessing (this repo's branching strategy, per base-instructions.md, is
`main`-centric; there is no secondary default to fall back to).

## Bookmark storage

- Path: `.claude/manual-test-bookmark.md` in the **consuming repo** (the repo
  the command is run from — not agent-workflow itself, unless that's the repo
  being tested).
- Contents — two lines, plain text:
  ```
  commit: <full 40-char sha>
  date: <ISO 8601 timestamp, e.g. 2026-07-29T10:15:00+02:00>
  ```
- **Local-only, gitignored.** Manual testing is done by one person at a time;
  a shared/committed bookmark would race if two people ran the command
  independently. This deliberately differs from `/handoff`'s committed
  `.claude/handoff-<branch>.md` — that file hands work to *another session or
  person*; this one tracks *this person's* personal testing progress.
- On first write, ensure `.gitignore` contains the single line
  `.claude/manual-test-bookmark.md` (append if missing; check with
  `git check-ignore` first so it isn't duplicated). Do **not** gitignore the
  whole `.claude/` directory — other files under it (e.g. handoff files) are
  intentionally committed.
- The bookmark always compares against `main`, regardless of which branch is
  currently checked out when the command runs.

## Checklist generation (`/manual-test` bare)

1. **Read the bookmark.** If `.claude/manual-test-bookmark.md` doesn't exist:
   print `No bookmark set yet — run /manual-test done to set today's main HEAD
   as your baseline, then /manual-test will show what changes going forward.`
   and stop. Do not guess a fallback window (e.g. "last N commits") — an
   unset bookmark has no principled starting point.

2. **Refresh `main`.**
   ```bash
   GIT_TERMINAL_PROMPT=0 git -c credential.helper= fetch -p origin main
   ```
   (belt-and-braces against credential-helper hangs, per this project's own
   fetch guidance — harmless when no auth is actually needed).

3. **Validate the bookmark is still reachable.**
   ```bash
   git merge-base --is-ancestor <bookmark-hash> origin/main
   ```
   If this fails (non-zero exit), the bookmark predates a history rewrite on
   `main` (rare — `main` is protected, no force-push, per branch strategy —
   but the file could also just be stale/corrupted). Print a warning
   explaining the bookmark is no longer valid and suggest `/manual-test done`
   to reset it. Stop — do not attempt a diff against an unreachable commit.

4. **Collect commits since the bookmark**, excluding merge commits:
   ```bash
   git log <bookmark-hash>..origin/main --no-merges \
     --pretty=format:'%H%x09%s'
   ```
   If this list is empty: print `No changes since last test (<short-hash>,
   <date>) — nothing to verify.` and stop.

5. **Parse each commit subject** as Conventional Commits
   (`type(scope): summary` or `type: summary`). A subject that doesn't match
   either pattern is kept, grouped under `other`, shown verbatim.

6. **Filter out non-user-facing types**: `chore`, `docs`, `ci`, `test`,
   `refactor` are dropped from the checklist (per this project's own SemVer
   mapping — these types never bump a version and have no user-visible
   behavior to test). `feat`, `fix`, `perf`, and unparsed subjects are kept.
   Track the count of dropped commits for the footer.

7. **Group** the kept commits by `scope` (fallback to `type` when there's no
   scope, `other` when neither parses). Sort groups alphabetically; sort
   commits within a group by commit order (oldest first).

8. **Render** as markdown:

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

   Omit the "Skipped" line entirely when N is 0.

## Advancing the bookmark (`/manual-test done`)

1. Refresh `main` the same way (step 2 above).
2. Read `origin/main`'s current HEAD: `git rev-parse origin/main`.
3. Overwrite `.claude/manual-test-bookmark.md` with the new commit hash and
   the current timestamp.
4. Ensure the `.gitignore` entry exists (same check as first-write, in case
   the file was manually deleted and `.gitignore` was too).
5. Print confirmation: `Bookmark advanced to <short-hash> (<date>). Future
   /manual-test runs will show changes after this point.`

`/manual-test done` does **not** require a prior `/manual-test` run in the
same session — it's a standalone stamp, which is also how a first-time
baseline gets set (per the "no bookmark yet" message above).

## Out of scope (deliberately)

- No linked-issue/PR enrichment in the checklist (commit subjects only, per
  design decision) — keeps the command fast and dependency-free (no `gh`
  calls).
- No diff-content analysis (file-level or line-level) — commit-message-driven
  only.
- No per-branch bookmarks — always `main` only. A per-branch variant is a
  plausible future extension (e.g. testing long-lived feature branches before
  merge) but isn't needed for the current use case and would complicate the
  storage format for no immediate benefit.
- No auto-advance — advancing the bookmark is always an explicit,
  user-initiated action (`/manual-test done`), never implicit.

## Testing

This is a markdown-defined slash command (procedural instructions for Claude
Code to follow), not compiled code — there's no unit-test harness for it in
this repo (consistent with every other file under `commands/`). Verification
is manual: exercise both verbs against a scratch repo covering the "no
bookmark", "bookmark set with pending changes", "bookmark set with no
changes", and "bookmark not an ancestor" cases described above.
