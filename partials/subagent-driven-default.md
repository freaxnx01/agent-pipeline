# Implementing plans

When executing an implementation plan (after the plan is written and approved),
use the `superpowers:subagent-driven-development` skill **by default** — dispatch
the plan's independent tasks to subagents rather than implementing inline — unless
I explicitly say otherwise.

**Exception — issue-based dispatch.** If the plan was written for a GitHub issue
(brainstorming/writing-plans ran against an issue's context, not ad hoc local
work) **and** the repo has agent-workflow's pipeline wired up — detect via
`.github/workflows/agent-implement.yml` (agent-workflow itself) or
`.github/workflows/agent.yml` (a consumer repo) — do not default to
subagent-driven-development. Instead follow the `/enrich` command's own
ending: push the spec + plan, inline the full plan into the issue body under
an `## Implementation Plan` section, clear `needs-enrichment` /
`❓ to-be-defined`, then dispatch via `/gh:implement` (the `ai-implement`
label) so the pipeline implements it — not this session. `/enrich`'s Step 5–7
(`commands/enrich.md`) is the source of truth for the exact mechanics; don't
duplicate it here, follow it.

This also means: suppress writing-plans' own "Subagent-Driven or Inline
Execution?" handoff question outright in this case — don't ask it, don't wait
for an answer, don't execute the plan locally. Same suppression `/enrich`
already applies to itself.

Falls back to the general subagent-driven-development default above when
either condition is false (no GitHub issue behind the plan, or the repo has
no agent-workflow pipeline wired up), or when I explicitly ask for local/inline
execution regardless of the repo's wiring.

Per Superpowers' own instruction-priority rules, this user-level instruction
overrides the plugin's default skill selection.
