---
description: Pre-review PRs against their issue's AC, then trigger the right agent (@copilot/@claude) to fix
argument-hint: "[PR numbers, e.g. 83 84 — or empty for all open non-merged PRs]"
---

Pre-review open pull request(s) in the current repo, post the review, and — only
when there are actionable fixes — nudge the agent that owns the PR to address them.

## Which PRs

`$ARGUMENTS` is an optional space-separated list of PR numbers. If empty, review
every open PR that still needs attention: `gh pr list --state open --json
number,title,author,isDraft,headRefName` — include drafts (agent PRs are usually
drafts), but skip a PR that is already approved with no open threads. Always say
which PRs you picked before starting.

**Skip a PR the pipeline's own pre-preview (ADR-004) already reviewed and
approved** — check for a "Pre-reviewed ✓ — promoted to ready" comment from the
pipeline on the PR (`gh pr view <N> --json comments`). That means an agent
already reviewed this exact diff and a human just needs to merge; running this
manual pass again is redundant unless the user explicitly wants a second
opinion. If the linked issue instead carries `ai:review-blocked`, pre-preview
ran and found problems (left the PR draft) — still worth this manual pass, and
say so, since pre-preview's own verdict/reason is useful context to fold in
rather than re-derive from scratch.

## Reviewing (one reviewer per PR, in parallel)

For **each** PR, dispatch a subagent (parallel when there are 2+ — one per PR) that
does a real review, not a diff skim:

1. **Find the linked issue** — from the PR body (`Closes #N` / `implements #N`) or
   the branch name; `gh pr view <N> --json title,body,files,headRefName` +
   `gh pr diff <N>`.
2. **Read the actual source**, not just the diff — verify claims in context.
3. **Review focus, in priority order:**
   - **Correctness bugs** — logic errors, regressions, broken behavior.
   - **Acceptance-criteria coverage** — walk the linked issue's checklist; mark each
     met / partial / missing.
   - **Project conventions** — read `CLAUDE.md`; honor the stack rules (e.g. for
     .NET here: `ProblemDetails` for all errors, `IStringLocalizer` for UI strings,
     `WebApplicationFactory` integration tests, no swallowed exceptions, no hardcoded
     test returns, non-root Docker final stage).
   - **Security** — secrets, header logging, auth, CORS, input validation.
   - **Quality** — reuse, simplification, dead code, scope creep.
4. **Return** a tight report: size, a **verdict** (`Approve` / `Approve-with-nits` /
   `Changes-requested`), findings grouped **Blocking** / **Should-fix** / **Nits**
   (each with `file:line` + one line), then an **AC coverage** checklist. No file dumps.

## Posting the review

Post each review as a **comment-type** review (works on drafts; never auto-approve):

```bash
gh pr review <N> --comment --body-file <file>
```

Lead the body with the verdict. Keep it to the structured findings + AC coverage.

## Triggering the owning agent (only if fixes are needed)

Skip this entirely for a clean `Approve`. For `Changes-requested` or
`Approve-with-nits` **with actionable items**, post a **second, separate** comment
(not the review) addressed to the agent, with a concise **numbered** fix list (the
blocking items first).

Pick the mention from the PR's owner — `gh pr view <N> --json author,assignees,headRefName`:

- `app/copilot-swe-agent` → **`@copilot`**.
- `app/anthropic-code-agent` (assignee *Claude*, branch `claude/…`) → Claude's agent.

**Learned default — prefer `@copilot`.** In practice `@copilot` is the reliable
trigger: it reacts (👀) within a minute and starts a session, and it can **take
over any PR**, including ones Claude's agent opened. A bare `@claude` mention
registers in the timeline but the native Anthropic agent does **not** reliably
wake from a PR comment. So:

- Copilot-owned PR → `@copilot`.
- Claude-owned PR → first choice is still to hand it to **`@copilot`** ("the agent
  that opened this hasn't picked up the review — can you take it over and address
  the feedback?"). Use `@claude` only if the user has confirmed the Anthropic agent
  is responsive in this repo, and fall back to `@copilot` if no 👀 reaction appears.
- If a repo defines its own `.github/workflows/*claude*.yml`, that's a self-hosted
  `@claude` Action — then `@claude` is genuinely the trigger; check for it first.

Reformat code-fence/backtick content safely for a shell `--body` (or use a body file).

## Verifying the agent's follow-up — don't trust the self-report

After nudging, re-check the PR directly rather than trusting the agent's reply
comment. Observed on a real nudge round-trip: the agent's summary claimed it
had updated the PR description **and** un-drafted it; neither was true — only
the code-file fix in its list actually landed. Diff the actual commit / fetch
the actual PR body before treating any item as resolved.

**Known structural limit — some coding-agent sandboxes can't edit PR metadata
at all.** A coding agent's internal `report_progress`-style tool can commit and
push code, but its sandbox may have GitHub REST API egress blocked (observed:
`Blocked by DNS monitoring proxy`, `gh auth` failing) — so it has **no path** to
`gh pr edit` / a PATCH call, no matter how it's asked. If a nudge asks for a
title/description/draft-state change and the agent's follow-up says it can't
apply it (rather than silently omitting it), that's not a one-off miss to
re-nudge — apply the edit yourself with your own `gh` access
(`gh pr edit <N> --title "..." --body-file <file>`, `gh pr ready <N>`) using
the exact text the agent proposed. Re-nudging a structural limitation just
burns another round-trip for nothing.

When monitoring a PR for "is this actually done" (e.g. a background poll),
gate on the literal content, not a cosmetic flag: hash the PR body with one
consistent command chain used at both baseline and each check (don't mix e.g.
jq's `@base64` filter with an external `base64` binary — they encode
identically-same text differently and produce false positives), and don't
gate solely on `isDraft`/a `[WIP]` title, since some agents leave both
untouched even after genuinely finishing (see the note on `review_requested`
above). The GitHub web UI's "Agents" tab showing a run as "Completed" is a
useful nudge to go look, not proof of a specific outcome — always re-verify
the actual PR state or diff. Default poll interval for this kind of loop: **60
seconds** — comfortably within a monitor's own 30s-minimum guidance for remote
APIs, with no need to go slower.

## After

Print, per PR: number, URL, verdict, and whether an agent was pinged (and which
mention). Note that Copilot pushes to the **existing branch**, so PR numbers don't
change and commit authorship will be mixed. Don't merge anything.

If there's no `gh`/repo context, say so and stop.
