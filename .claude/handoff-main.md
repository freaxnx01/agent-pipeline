Resume: non-game repo onboarding, sync-ai-instructions half.

Artifact: `docs/ai-notes/nongame-onboarding-sync-ai-instructions.md` (full repo
table, stack-fit analysis, open decision, next steps).

Phase: `agent-workflow-init` half is done (30/30 repos, no failures). The
`sync-ai-instructions` half is deferred — only 2 of 30 candidates
(`quotes`, `flowhub`) have a clean existing stack-overlay match; the rest need
a scope decision (new overlays? skip? per-repo inspection?) before proceeding.

Next step: read the artifact's "Next step, when resumed" section and decide
scope with the user before running `/sync-ai-instructions` anywhere. If this
turns into implementation work (e.g. authoring new stack overlays), use
`superpowers:subagent-driven-development`.
