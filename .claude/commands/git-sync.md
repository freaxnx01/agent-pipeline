# Git Sync — Slash Command

Check whether the local clone is in sync with its remote, and bring it up to date when it's safe.

**Target:** $ARGUMENTS

---

## Steps

### Step 1 — Fetch

- Run `git fetch -p origin`
- Report any branches that were pruned/deleted on the remote (look for `[deleted]` / `- [pruned]` lines in the output)

### Step 2 — Assess sync state

- Run `git status -sb` for a quick overview (current branch, upstream, dirty files)
- Run `git rev-list --left-right --count HEAD...@{u}` to get an explicit ahead/behind count (left = ahead, right = behind)
  - If the current branch has no upstream, report that and stop — nothing further to compare

### Step 3 — Decide and act

Based on the ahead/behind counts and working tree state:

- **Dirty working tree** (uncommitted or untracked changes) → STOP before pulling. List the uncommitted/untracked files and let the user decide (commit, stash, or discard) before re-running.
- **Behind only, clean tree** → fast-forward with `git pull --ff-only`, then confirm the new `HEAD` and how many commits were pulled.
- **Ahead only** → report the commits that are ahead. Do NOT push automatically — leave pushing to the user (`/push`).
- **Diverged** (both ahead and behind) → STOP and surface the divergence clearly (ahead/behind counts, `git log` summary of both sides). Never auto-rebase or auto-merge.
- **Neither ahead nor behind** → already in sync, nothing to do.

### Step 4 — Summary

Print a single one-line final summary, one of:

- `in sync`
- `fast-forwarded N commits`
- `diverged (A ahead, B behind) — manual action needed`
- `dirty working tree — resolve before syncing`

---

## Rules

- Never rebase, merge, or force anything automatically — only a clean fast-forward pull is automatic
- Never push
- If pruned branches match the current branch, warn loudly before doing anything else
