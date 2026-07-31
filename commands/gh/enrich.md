---
description: Enrich an issue with a spec and implementation plan, then update the issue body so the agent-workflow can implement it
argument-hint: <issue number>
---

Enrich GitHub issue #$ARGUMENTS (strip any leading `#`) so it is ready for the
agent-workflow. The pipeline reads only the issue **body** — everything the agent
needs must end up there.

## Step 1 — Read the issue

```bash
gh issue view $ARGUMENTS --comments
```

If the issue is closed, already has `ai-implement` label, or is `🧊 parked`, stop and say so.

## Step 2 — Assess readiness

Judge whether the issue already has all three:

- **Acceptance criteria** — concrete, testable conditions
- **Scope / spec** — what to build, enough to start without guessing
- **No blocking unknowns** — no open design questions or TBDs the agent can't resolve from the codebase

If the issue is already complete, tell the user and suggest running `/gh:implement $ARGUMENTS` directly. Stop here.

## Step 3 — Brainstorm spec

Invoke **superpowers:brainstorming** with the issue as context. The goal is a
validated spec saved to `<specs-dir>/YYYY-MM-DD-<topic>-design.md` and committed.
Follow the brainstorming skill end-to-end (clarifying questions, approaches,
design sections, spec self-review, user approval gate).

## Step 4 — Write implementation plan

After brainstorming exits, invoke **superpowers:writing-plans** to produce the
full task-by-task plan at `<plans-dir>/YYYY-MM-DD-<topic>.md` and commit it.

**Do not stop at writing-plans' own handoff prompt.** That skill ends by asking
"Subagent-Driven or Inline Execution?" — that is writing-plans' generic ending,
not the end of `/gh:enrich`. Do not execute the plan and do not wait for an
answer to that question here. Treat the plan as written the moment the skill
exits, and continue straight to Step 5 — pushing the files and writing the plan
into the issue body is still required, always.

### Picking `<specs-dir>` / `<plans-dir>` — check gitignore first

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

## Step 5 — Push to remote

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

## Step 6 — Update the issue body

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
```

`--remove-label` on a label the issue doesn't carry is a no-op, but on a label
that doesn't exist **anywhere in the repo** it errors — many repos only define
one of the two conventions. Run each on its own line with `|| true` so a
missing repo label doesn't abort the step.

## Step 7 — Confirm

Print:

- Issue URL
- Paths to spec and plan files
- "Issue is ready — run `/gh:implement $ARGUMENTS` to trigger the agent-workflow."

---

If you run into blockers (brainstorming skill not available, push fails, issue edit
rejected), find a solution and update this skill for the future.
