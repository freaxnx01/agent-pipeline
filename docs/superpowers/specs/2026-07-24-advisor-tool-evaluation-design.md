# Evaluate the Advisor Tool for `ai-implement` — Design

**Issue:** #160 · **ADR:** 008 · **Status:** Accepted · **Date:** 2026-07-24

Issue #160 asks whether the "advisor strategy"
(https://claude.com/blog/the-advisor-strategy) can be used with the `ai-implement`
pipeline's headless Claude runs. This is a research task: produce a decision record,
not a code change.

## Problem

The advisor strategy lets a cheap executor model (Sonnet/Haiku) call a stronger
"advisor" model (Opus) mid-task, within the same request, only at decision points it
can't resolve on its own — near-Opus judgement at near-Sonnet cost. The `implement`
job in `.github/workflows/agent-implement.yml` runs Claude Code headlessly via
`anthropics/claude-code-base-action` with a fixed `allowed_tools` allowlist
(`Edit,Write,Read,Glob,Grep,MultiEdit,TodoWrite,Bash`, line 437) and one model per run
picked up front by `classify-task.sh`. If the advisor tool is reachable from that
headless run, it's a natural fit for hard mid-implementation calls; if it isn't yet,
that needs to be documented so the question doesn't get re-asked from scratch.

## Research findings (static — no live pipeline run)

Sources: this session's local `claude --help` (CLI v2.1.218, matching the version the
pinned base-action installs), the `claude-code-base-action` `action.yml` at the pinned
SHA (`2d6abe4aa8adacaa322e24a040787cf155cf1d09`), the public
`anthropics/claude-code` `CHANGELOG.md`, and the blog post itself.

**Confirmed:**

- The advisor tool is a real, shipped Anthropic feature — not exclusive to any one
  product surface. At the API level it's a beta tool: request header
  `anthropic-beta: advisor-tool-2026-03-01`, tool block `"type": "advisor_20260301"`
  (blog post, includes a `max_uses` parameter).
- The Claude Code CLI has its own integration, first appearing in the public
  changelog at **v2.1.117** ("Advisor Tool (experimental): dialog now carries an
  'experimental' label..."), still labeled experimental through v2.1.214+.
- **v2.1.218** — the exact version `claude-code-base-action`'s `action.yml` pins for
  installation, and the version installed locally in this session — postdates
  v2.1.117, so the feature is present in the binary the pipeline runs.
- The action exposes a `claude_args` input ("Additional arguments to pass directly to
  Claude CLI"), a generic passthrough not currently used by
  `agent-implement.yml` — in principle a channel for flags beyond `allowed_tools`.

**Not confirmed (the open gap):**

- No changelog entry, `--help` output, or reachable docs page describes a headless
  (`-p`/`--print`) or `settings.json` path to enable/configure the advisor tool.
  Every changelog mention describes interactive-session UI: "`/advisor` **dialog**",
  "advisor **picker**", "startup **notification** when enabled" — a human picking an
  advisor model. There is no evidence either way for whether it's silently
  unavailable headlessly, or reachable via an undocumented flag.
- The blog post documents the raw Messages API usage only; it does not mention the
  Claude Code CLI, headless/non-interactive execution, or GitHub Actions at all.

**Conclusion: inconclusive from static research.** The feature is real and present in
the pinned CLI version; headless reachability is an open question that only a live
test can answer, and a live test is out of scope for this issue (per scope decision
during enrichment).

## Decision

Write **ADR-008** into `docs/DECISIONS.md`, following the file's existing
`### Context` / `### Decision` / `### Consequences` structure:

- **Context**: issue #160, what the advisor pattern is, why it's attractive for
  `ai-implement` (see Problem above).
- **Decision**: do not wire the advisor tool into `agent-implement.yml` in this pass.
  State the confirmed-vs-unconfirmed split from the research findings above.
- **Consequences**:
  - Relationship to the existing `auto-review` / `pre-preview` jobs
    (`review-pr.sh`): those are a coarser, already-working second-opinion
    mechanism — a separate Claude invocation reviewing the *finished* PR diff after
    the fact. The advisor pattern, if it ever lands headlessly, would be
    complementary rather than a replacement — fine-grained, mid-task, same-context
    consultation vs. a post-hoc whole-PR gate.
  - Revisit trigger: the next `anthropics/claude-code` `CHANGELOG.md` entry that
    mentions non-interactive/headless advisor support, or `claude-code-base-action`
    documenting how to pass advisor-enabling flags through `claude_args`.
  - Links to the follow-up issue (below) for the one experiment that would close
    the gap.

No changes to `.github/workflows/agent-implement.yml` or any script in this pass.

## Follow-up issue (filed, not executed, here)

A new GitHub issue, labeled `needs-enrichment`:

> **Title:** Spike: try enabling Advisor Tool in a sandboxed `ai-implement` run
>
> **Body:** ADR-008 (`docs/DECISIONS.md`) found the Advisor Tool present in the
> pinned Claude Code CLI version (2.1.218+) but could not confirm headless/`-p`
> reachability from static research alone. Scoped experiment: on a throwaway sandbox
> repo (per this repo's CI-stack Layer-3 convention), add a candidate advisor-enabling
> flag to the `implement` job's `claude_args` (e.g. via `--tools` or an undocumented
> flag discovered by testing `claude -p --help` output more exhaustively / asking
> Anthropic support), trigger one `ai-implement` run, and observe whether the advisor
> tool actually engages (check the run's execution log / cost breakdown for an
> advisor-model call). Report back into ADR-008 as an addendum with the result either
> way. Single run — this is a yes/no probe, not a benchmark.

The ADR's Consequences section links to this issue by number once created.

## Issue #160 disposition

Close #160 with a comment linking the merged ADR-008 and the new follow-up issue —
the evaluation asked for in #160 is complete once the ADR lands; further work
continues on the follow-up issue, not #160.

## Out of scope

- Any live/sandbox pipeline run (explicit scope decision during enrichment).
- Any code change to `agent-implement.yml`, `review-pr.sh`, or any script.
- The OpenCode/OpenRouter agent path — the advisor tool is a Claude-specific
  feature; not applicable there.
