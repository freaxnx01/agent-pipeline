---
description: Save current phase to an MD file + a resume prompt, ready to /clear
---

Prepare a clean context handoff so I can `/clear` and resume cold. Do all of this,
then stop:

1. **Persist the artifact.** Identify the current phase's artifact — the spec or
   the implementation plan. If a spec/plan markdown file already exists for this
   work, use it; otherwise write the current spec or implementation plan to a
   markdown file at a sensible path (e.g. `docs/` or the repo's plans dir).
   Make it complete enough to resume from cold (decisions made, what's done, what's
   next). Report the path.

2. **Write the resume prompt.** Create `.claude/handoff-<slug>.md` (make `.claude/`
   if needed) containing a short, self-sufficient prompt that:
   - names the **exact path** to the artifact from step 1,
   - states the current phase and the next step,
   - instructs to resume using `superpowers:subagent-driven-development` for any
     implementation.

   `<slug>` is the **current branch** with `/` replaced by `-`:

   ```bash
   slug="$(git rev-parse --abbrev-ref HEAD | tr '/' '-')"
   [ "$slug" = "HEAD" ] && slug="detached-$(git rev-parse --short HEAD)"   # detached HEAD
   echo ".claude/handoff-$slug.md"
   ```

   **Never write a bare `.claude/handoff.md`.** A repo with several git worktrees
   checked out has one working copy per branch but a single shared file path — a
   fixed name means worktree B inherits worktree A's handoff the moment it rebases,
   and `/pickup` there resumes the wrong task. Branch-based naming keeps them
   distinct while still letting every handoff be committed and pushed, so it can be
   picked up from another machine or clone.

   Key by **branch**, not by worktree directory name: the branch travels with a
   clone, the `.worktrees/<name>` layout does not.

3. **Clipboard fallback.** Copy that same resume prompt to the system clipboard,
   using whichever tool exists: `clip.exe` (WSL2/Windows), `pbcopy` (macOS),
   `wl-copy` or `xclip` (Linux).

4. **Commit and push.** Stage the artifact from step 1 and
   `.claude/handoff-<slug>.md`, commit with a conventional message (e.g.
   `docs(handoff): save phase for resume`), and push to the current branch's
   remote. Do this without asking — handoff files are always meant to be durable,
   not left as local-only, uncommitted state. If there is no remote or push fails,
   say so and continue; don't block the handoff on it.

   From a worktree whose branch is published onto another branch (e.g.
   `git push origin worktree-finnova:main`), the handoff file lands on that target
   branch. That is fine and intended — the `<slug>` keeps it from colliding with
   any other worktree's handoff sitting beside it. Note that such a push updates
   the *remote* branch only; a local checkout of it stays behind until fetched.

   If a git network command hangs rather than failing, retry it with the
   credential helper cleared — `GIT_TERMINAL_PROMPT=0 git -c credential.helper=
   fetch -p origin` — an inherited helper can block on a prompt no tool-call
   subshell can answer.

5. **Tell me what to do next.** End by printing the artifact path and this exact
   instruction: run `/clear`, then `/pickup` (or paste the clipboard) to resume.
   Note that you cannot run `/clear` yourself — that keystroke is mine.

Keep the resume prompt to a few lines but self-contained.

> **Related:** `/handoff` saves *one* in-flight phase for a `/clear`-and-resume. To
> capture *all* the session's loose ends instead, use `/wrap-up` → `/todo`.
