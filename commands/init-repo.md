---
description: Full repo bootstrap — sync AI agent instructions, then onboard onto agent-workflow
argument-hint: "[stack name for sync-ai-instructions]"
---

Bring a repo fully online in one call: AI agent instructions (CLAUDE.md +
overlay) **and** the agent-workflow issue-implementation pipeline. This is a
thin sequencer over two independent, already-idempotent flows — it does not
duplicate their logic.

**Target:** the current working directory's repo. **Argument:** `$ARGUMENTS`
is passed through to `sync-ai-instructions` unchanged (a stack name, or empty
to auto-detect / prompt).

## Step 1 — Sync AI instructions

Invoke the **sync-ai-instructions** skill with `$ARGUMENTS`. Let it run to
completion (it writes `CLAUDE.md`, `.github/copilot-instructions.md`,
`SKILL.md`, `.ai/**`, and reports what it wrote — it does not commit).

If this step stops early (missing stack, ambiguous `.ai/stacks/`), surface
that to the user and stop here — don't proceed to Step 2 with an unresolved
instruction set.

## Step 2 — Onboard onto agent-workflow

Run **`/agent-workflow-init`** (no argument — defaults to the current repo's
`origin`). Let it resolve Passbolt secrets, run `onboard-consumer.sh`, and
report as that command specifies.

## Step 3 — Report

A single combined summary covering both steps:

- Instruction files written/updated (from Step 1) — remind the user these are
  **uncommitted**, same as a standalone `/sync-ai-instructions` run
- agent-workflow wiring result (from Step 2) — secrets, labels, settings, and
  the stub PR link if one was opened

Then one closing checklist for the user:

1. Review and commit the instruction-file changes from Step 1
2. Review and merge the stub PR from Step 2 (if opened)
3. Label a low-risk issue `ai-implement` as a first smoke test before trusting
   the pipeline with real work (per `CONSUMER-SETUP.md` §0.3)

---

If either sub-step's own instructions change (a new sync-ai-instructions
argument shape, a new onboard-consumer.sh flag), this file shouldn't need
edits — it only orchestrates, it doesn't restate their logic. If that
stops being true (drift creeps in), fix it here.
