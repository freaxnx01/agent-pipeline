# Configurable max-turns Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose the Claude Code implement step's turn cap as a `max-turns` `workflow_call` input on `agent-implement.yml`, defaulting to the current hardcoded value (`30`), so consumer repos can raise it for larger tasks.

**Architecture:** A one-line input addition (matching the existing `timeout-minutes` input's shape) plus a one-line change threading that input into the already-existing `max_turns:` field of the "Run Claude Code" step — the same pattern already used one line above it (`model: ${{ steps.triage.outputs.model }}`).

**Tech Stack:** GitHub Actions reusable workflow YAML. No scripts, no application code.

## Global Constraints

- Single file: `.github/workflows/agent-implement.yml`. No other files change.
- **Deliberate TDD deviation, documented:** this repo's test architecture (see `CLAUDE.md` "Testing Strategy — Layered") has Layer-1 fixture tests for **bash scripts** and Layer-2 `act` tests that assert on **stub-injected result outputs** (`outcome`, `cost-usd`, `num-turns`, etc. — see `agent-implement.test.yml`'s `Assert *` jobs). Neither layer can observe a `with:` value threaded into a real (non-stubbed) action step — the "Run Claude Code" step only runs when `!inputs.stub-claude`, and stub-mode tests never reach it. There is no test seam for "does this workflow_call input reach that action's `with:` block" short of a live run against the real `claude-code-base-action`, which is disproportionate for a one-line passthrough. The verification gate for this task is **`actionlint`** (already a required gate per this repo's `CLAUDE.md`: "Do not edit a workflow without verifying actionlint and shellcheck pass") plus a full local `act` run of the existing Layer-2 suite to confirm no regression — not a new automated assertion of the threading itself. This mirrors the browser-game stack's own documented deviation for buildless repos (same principle: test what the architecture can actually observe).
- Do not touch the `error_max_turns` stub simulator at line 564 (`jq -nc '{type:"result",subtype:"error_max_turns",...}'`) — it simulates a test failure scenario for the existing `call-opencode-task-failure` job and is unrelated to this real input.
- Match existing style exactly: unquoted `${{ ... }}` expression (not `'${{ ... }}'`), same as the `model:` line immediately above it.

---

### Task 1: Add `max-turns` input and thread it into the Claude Code step

**Files:**
- Modify: `.github/workflows/agent-implement.yml:27-30` (add new input, after `timeout-minutes`)
- Modify: `.github/workflows/agent-implement.yml:433` (thread the input in)

**Interfaces:**
- Produces: a `max-turns` `workflow_call` input (`type: number`, `default: 30`) — consumers can pass e.g. `max-turns: 60` in their `.github/workflows/agent.yml` stub's `with:` block, or leave it unset to keep today's behavior unchanged.

- [ ] **Step 1: Add the new input**

In `.github/workflows/agent-implement.yml`, the `timeout-minutes` input currently reads (lines 27-30):

```yaml
      timeout-minutes:
        description: Hard cap on the implementation job runtime.
        type: number
        default: 30
```

Add a new `max-turns` input immediately after it (so it now reads):

```yaml
      timeout-minutes:
        description: Hard cap on the implementation job runtime.
        type: number
        default: 30
      max-turns:
        description: |
          Hard cap on Claude Code tool-use turns for the implement step.
          Raise this for issues whose implementation plan needs more than
          the default 30 turns (e.g. multiple files, or several edit
          locations in one file) to fully implement, test, commit, and
          open a PR in one run.
        type: number
        default: 30
```

- [ ] **Step 2: Thread it into the Run Claude Code step**

In the same file, the "Run Claude Code" step's `with:` block currently reads
(line 429-434):

```yaml
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          prompt_file: ${{ steps.issue.outputs.prompt-file }}
          model: ${{ steps.triage.outputs.model }}
          max_turns: '30'
```

Change the `max_turns:` line to reference the new input:

```yaml
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          prompt_file: ${{ steps.issue.outputs.prompt-file }}
          model: ${{ steps.triage.outputs.model }}
          max_turns: ${{ inputs.max-turns }}
```

- [ ] **Step 3: Verify with actionlint**

```bash
actionlint .github/workflows/agent-implement.yml
```

Expected: no output (clean pass). If `actionlint` reports anything, fix it
before proceeding — do not suppress.

- [ ] **Step 4: Regression-verify with the existing Layer-2 act suite**

This confirms the new input's default (`30`) preserves every existing test's
behavior unchanged — no new test is added (per Global Constraints), this is
a regression check on the suite that already exists.

```bash
act pull_request -W .github/workflows/agent-implement.test.yml -j call-success
act pull_request -W .github/workflows/agent-implement.test.yml -j assert-success
act pull_request -W .github/workflows/agent-implement.test.yml -j call-opencode-task-failure
act pull_request -W .github/workflows/agent-implement.test.yml -j assert-opencode-task-failure
```

(Job names come from `.github/workflows/agent-implement.test.yml`'s existing
`jobs:` keys — run `act pull_request -W .github/workflows/agent-implement.test.yml -l`
first if any of the above don't match, and substitute the real names.)

Expected: all four pass, identical to their behavior before this change
(these exercise `stub-claude: true` paths and the `error_max_turns` stub,
neither of which this change touches).

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/agent-implement.yml
git commit -m "feat(agent-implement): expose max_turns as a configurable input

Adds a max-turns workflow_call input (default: 30, matching prior hardcoded
behavior) and threads it into the Run Claude Code step's max_turns field.
Consumers with implementation plans that need more than 30 tool-use turns
to fully implement, test, commit, and open a PR can now raise the cap
per call site.

Closes #166"
```

---

## Self-review notes

- **Spec coverage:** the issue's exact suggested fix (add a `max-turns`
  input, thread it into the hardcoded value at line 433) is implemented
  verbatim in Step 1/Step 2 — no gap.
- **No placeholders:** every step shows the literal before/after YAML.
- **Type/name consistency:** the input is named `max-turns` (kebab-case,
  matching every other input in this file — `runner-labels`,
  `default-model`, `timeout-minutes`) and referenced as `inputs.max-turns`
  consistently in Step 2.
- **Scope check:** single task is correct here — this is a two-line change
  to one file; splitting further would be artificial.
