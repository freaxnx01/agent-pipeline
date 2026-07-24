# Advisor Tool Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record ADR-008 in `docs/DECISIONS.md` documenting that the Advisor Tool's
headless reachability from `ai-implement` is unconfirmed, file a scoped follow-up
spike issue, and close issue #160 referencing both.

**Architecture:** Pure documentation + `gh` CLI calls. No workflow, script, or code
changes. Three sequential tasks: file the follow-up issue first (its number is needed
inside the ADR text), write the ADR referencing that issue number, then close #160
referencing the ADR.

**Tech Stack:** `git`, `gh` CLI.

## Global Constraints

- No changes to `.github/workflows/agent-implement.yml`, `review-pr.sh`, or any
  script in this repo (per spec's "Out of scope").
- No live/sandbox pipeline run — the follow-up issue is filed, not executed
  (per spec's "Out of scope").
- ADR entries in `docs/DECISIONS.md` are immutable once committed — supersession
  is a new entry, never an edit to this one (file header, `docs/DECISIONS.md:1-8`).
- Follow the file's existing lightweight-ADR format: `## ADR-NNN — <title> (date)`
  then `### Context` / `### Decision` / `### Consequences` (see ADR-007,
  `docs/DECISIONS.md:779`, for the current header style — no `Status:`/`Tracking:`
  lines on recent entries).

---

### Task 1: File the follow-up spike issue

**Files:** none (GitHub API call only)

**Interfaces:**
- Produces: an issue number, referred to as `<FOLLOWUP_N>` in Task 2 and Task 3.

- [ ] **Step 1: Confirm the `needs-enrichment` label exists**

Run: `gh label list --search needs-enrichment`
Expected: one row, `needs-enrichment`. (It already exists in this repo — created for
issue #160 — so no `gh label create` should be needed. If the row is missing, run
`gh label create needs-enrichment --description "Issue needs a spec/plan before
implementation" --color FBCA04` first.)

- [ ] **Step 2: Create the issue**

```bash
gh issue create \
  --title "Spike: try enabling Advisor Tool in a sandboxed ai-implement run" \
  --label "needs-enrichment" \
  --body "$(cat <<'EOF'
ADR-008 (`docs/DECISIONS.md`) found the Advisor Tool present in the pinned Claude
Code CLI version (2.1.218+) but could not confirm headless/`-p` reachability from
static research alone.

Scoped experiment: on a throwaway sandbox repo (per this repo's CI-stack Layer-3
convention), add a candidate advisor-enabling flag to the `implement` job's
`claude_args` (e.g. via `--tools` or an undocumented flag discovered by testing
`claude -p --help` output more exhaustively / asking Anthropic support), trigger
one `ai-implement` run, and observe whether the advisor tool actually engages
(check the run's execution log / cost breakdown for an advisor-model call).

Report back into ADR-008 as an addendum with the result either way. Single run —
this is a yes/no probe, not a benchmark.
EOF
)"
```

Expected: prints the new issue's URL, e.g.
`https://github.com/freaxnx01/agent-workflow/issues/161`. Record the number after
`issues/` as `<FOLLOWUP_N>` — it is used verbatim in Task 2 Step 1 and Task 3 Step 1.

- [ ] **Step 3: Verify**

Run: `gh issue view <FOLLOWUP_N> --json number,title,labels,state`
Expected: `"state": "OPEN"`, title exactly `Spike: try enabling Advisor Tool in a
sandboxed ai-implement run`, labels contains `needs-enrichment`.

No commit — nothing in the working tree changed.

---

### Task 2: Write ADR-008 into docs/DECISIONS.md

**Files:**
- Modify: `docs/DECISIONS.md` (append after the last line, currently line 835 —
  confirm with `wc -l docs/DECISIONS.md` since Task 1 may have run in a fresh
  checkout with a different line count if the file changed upstream; append after
  whatever the current last line is)

**Interfaces:**
- Consumes: `<FOLLOWUP_N>` from Task 1 Step 2.

- [ ] **Step 1: Append the ADR entry**

Append this block to the end of `docs/DECISIONS.md`, separated from the prior entry
by a blank line (match the existing spacing between ADR-006 and ADR-007). Replace
every `<FOLLOWUP_N>` with the literal issue number from Task 1:

```markdown

## ADR-008 — Advisor Tool not yet wired into ai-implement (2026-07-24)

### Context

Issue #160 asked whether the "advisor strategy"
(https://claude.com/blog/the-advisor-strategy) can be used with the `ai-implement`
pipeline's headless Claude runs. The pattern lets a cheap executor model
(Sonnet/Haiku) call a stronger "advisor" model (Opus) mid-task, within the same
request, only at decision points it can't resolve on its own — near-Opus judgement
at near-Sonnet cost. The `implement` job in `agent-implement.yml` runs Claude Code
headlessly via `anthropics/claude-code-base-action` with a fixed `allowed_tools`
allowlist (`Edit,Write,Read,Glob,Grep,MultiEdit,TodoWrite,Bash`) and one model per
run picked up front by `classify-task.sh`. If the advisor tool is reachable from
that headless run, it's a natural fit for hard mid-implementation calls.

### Decision

**Do not wire the advisor tool into `agent-implement.yml` in this pass.** Static
research (this session's local `claude --help` on CLI v2.1.218 — the exact version
`claude-code-base-action`'s `action.yml` pins at SHA
`2d6abe4aa8adacaa322e24a040787cf155cf1d09` — the public `anthropics/claude-code`
`CHANGELOG.md`, and the blog post) found:

- **Confirmed:** the advisor tool is a real, shipped Anthropic feature. At the API
  level it's a beta tool (`anthropic-beta: advisor-tool-2026-03-01` header, `"type":
  "advisor_20260301"` tool block, per the blog post). The Claude Code CLI has its
  own integration, first appearing in the public changelog at v2.1.117 ("Advisor
  Tool (experimental)..."), still labeled experimental through v2.1.214+ — present
  in the v2.1.218 binary the pipeline installs. The action exposes a `claude_args`
  passthrough input, not currently used by `agent-implement.yml`, that in principle
  could carry flags beyond `allowed_tools`.
- **Not confirmed:** no changelog entry, `--help` output, or reachable docs page
  describes a headless (`-p`/`--print`) or `settings.json` path to enable/configure
  the advisor tool. Every changelog mention describes interactive-session UI
  ("`/advisor` dialog", "advisor picker", "startup notification when enabled") — a
  human picking an advisor model. The blog post documents the raw Messages API
  usage only and does not mention the Claude Code CLI, headless execution, or
  GitHub Actions.

Headless reachability is therefore an open question that only a live test can
answer; a live pipeline run was out of scope for this evaluation (issue #160).

### Consequences

+ The existing `auto-review` / `pre-preview` jobs (`review-pr.sh`) remain the
  pipeline's only second-opinion mechanism — a separate Claude invocation
  reviewing the *finished* PR diff after the fact. If the advisor tool ever lands
  headlessly, it would be complementary rather than a replacement: fine-grained,
  mid-task, same-context consultation vs. a post-hoc whole-PR gate.
+ Revisit trigger: the next `anthropics/claude-code` `CHANGELOG.md` entry that
  mentions non-interactive/headless advisor support, or `claude-code-base-action`
  documenting how to pass advisor-enabling flags through `claude_args`.
+ Follow-up: [#<FOLLOWUP_N>](https://github.com/freaxnx01/agent-workflow/issues/<FOLLOWUP_N>)
  — a scoped sandbox-repo spike to test headless reachability directly, filed
  rather than executed here.
```

- [ ] **Step 2: Verify the substitution**

Run: `grep -n "FOLLOWUP_N" docs/DECISIONS.md`
Expected: no output (empty) — confirms every `<FOLLOWUP_N>` placeholder was replaced
with the real issue number.

- [ ] **Step 3: Verify the ADR renders as valid markdown**

Run: `tail -n 45 docs/DECISIONS.md`
Expected: the appended block reads cleanly — heading, three `###` subsections,
no stray placeholder text, matches the structure of ADR-007 above it.

- [ ] **Step 4: Commit and push**

```bash
git add docs/DECISIONS.md
git commit -m "docs(decisions): add ADR-008 — advisor tool not yet wired into ai-implement

Static research found the Advisor Tool is a real, shipped feature present in the
pinned Claude Code CLI version, but headless/-p reachability from ai-implement is
unconfirmed. Follow-up spike filed as #<FOLLOWUP_N>.

Refs #160"
git push
```

Expected: push succeeds (fast-forward on `main`); if it fails with a permission
error, check for an allowed `.envrc` providing `GH_TOKEN`/`GITHUB_TOKEN` before
falling back to an interactive `gh auth login` prompt.

---

### Task 3: Close issue #160

**Files:** none (GitHub API call only)

**Interfaces:**
- Consumes: `<FOLLOWUP_N>` from Task 1 Step 2; the commit SHA from Task 2 Step 4
  (`git rev-parse --short HEAD` after that push).

- [ ] **Step 1: Close with a comment**

```bash
sha="$(git rev-parse --short HEAD)"
gh issue close 160 --comment "Evaluated in ADR-008 (\`docs/DECISIONS.md\`, ${sha}) — the Advisor Tool is a real, shipped feature present in the pinned Claude Code CLI version, but headless reachability from \`ai-implement\` is unconfirmed by static research. Follow-up spike to test it live: #<FOLLOWUP_N>."
```

Replace `<FOLLOWUP_N>` with the literal issue number from Task 1.

- [ ] **Step 2: Verify**

Run: `gh issue view 160 --json state,comments -q '.state, (.comments | length)'`
Expected: first line `CLOSED`, second line `>= 1` (at least one comment present).

No commit — nothing in the working tree changed.

---

## Definition of Done

- [ ] Follow-up spike issue open, labeled `needs-enrichment`, number known.
- [ ] `docs/DECISIONS.md` has a new ADR-008 entry, no `<FOLLOWUP_N>` placeholders
      remaining, committed and pushed to `main`.
- [ ] Issue #160 is closed with a comment linking ADR-008 and the follow-up issue.
