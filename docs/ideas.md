# Ideas

## Complete AI-assisted SDLC loop

- id: 2026-07-30-complete-ai-assisted-sdlc-loop · captured: 2026-07-30 · status: raw
- value: Sketch of a full SDLC (intake through post-release) plus a 4-loop AI-first framing (Plan/Build/Validate/Operate), with open questions on daily workflow and multi-repo WIP limits.

Human tasks:

- Create Issues out of new req & Assign to Milestone
- Enrich Issues (Spec, Impl plan)
- Route Issues (assign Copilot / ai-implement)
- Review Issues (HITL)
- Loop: Manual Tests -> Process Test Feedback (own or others') -> Create Issues
- Documentation
- Release

Open questions:

- What am I doing on a work day?
- Multiple projects/repos — WIP limit?

### "complete" SDLC (fuller phase list, before/after implementation)

1. Intake & Planning — capture requirements, create issues, assign milestone/priority, define acceptance criteria
2. Specification — enrich issues (functional spec, technical design, implementation plan, dependencies, risks)
3. Implementation — route issues (assign developer / Copilot / ai-implement), create PR
4. Review (HITL) — code review, AI review, architecture review (if needed), security review (optional)
5. Verification loop — automated tests, manual tests, process test feedback, create follow-up issues, fix implementation, repeat until accepted
6. Documentation — user docs, developer docs, changelog, ADRs (if applicable)
7. Release — versioning, release notes, deploy, tag release
8. Post Release — monitor, bug reports, customer feedback, create new issues, feed backlog

### AI-first framing as four repeating loops

- Plan: create issues, enrich issues, prioritize
- Build: route issue, AI implement, review (HITL), merge
- Validate: automated tests, manual tests, process feedback, create follow-up issues
- Operate: documentation, release, monitor, feed backlog

Emphasizes the process is continuous rather than linear — production feedback becomes new requirements, starting the next cycle. Automated quality gates (linting, static analysis, unit/integration tests, security scanning) should be explicit in the Verification stage to reduce manual review load.
