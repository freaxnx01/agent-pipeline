---
description: Resume work saved by /handoff (reads .claude/handoff-<branch>.md)
---

Resume the work saved by `/handoff` for the **current branch**.

## Locate the handoff file

Handoffs are keyed by branch so that sibling git worktrees, which share one file
path but not one task, don't resume each other's work:

```bash
slug="$(git rev-parse --abbrev-ref HEAD | tr '/' '-')"
[ "$slug" = "HEAD" ] && slug="detached-$(git rev-parse --short HEAD)"
ls -1 ".claude/handoff-$slug.md" 2>/dev/null || ls -1 .claude/handoff*.md 2>/dev/null
```

Resolution order:

1. `.claude/handoff-<slug>.md` — the current branch's handoff. Use it.
2. `.claude/handoff.md` — legacy unslugged name from before branch-keyed handoffs.
   Use it, and mention it should be renamed to the slugged form on the next
   `/handoff`.
3. Neither exists, but other `.claude/handoff-*.md` files do — those belong to
   **other branches**. Do not silently resume one. List them with their branch
   names and ask which (if any) to use.
4. Nothing at all — say there's nothing to resume and stop.

## Resume

Read the file and resume exactly as it directs: open the spec/plan file it
references, re-establish where things stand, and continue from the stated next
step — using `superpowers:subagent-driven-development` for any implementation.

**Check staleness first.** Report when the handoff was last committed
(`git log -1 --format=%ad --date=short -- <file>`) and, if the branch has moved on
since, say so before acting — a handoff that predates later commits may describe
work already done. A stale handoff nobody cleaned up is a known failure mode;
treat an old date as a reason to verify, not to trust.

## After resuming

Once the handed-off phase is genuinely complete, delete the handoff file and
commit that deletion. Leaving it behind is what turns it stale for the next
reader — including future you on another machine.

> **Related:** `/pickup` continues a single handed-off task. To see the whole-session
> checklist from `/wrap-up`, use `/todo` instead.
