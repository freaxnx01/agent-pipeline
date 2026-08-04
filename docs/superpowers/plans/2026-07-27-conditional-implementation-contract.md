# Implementation Plan: conditional implementation contract (code vs docs-only)

**Issue:** [#177](https://github.com/freaxnx01/agent-workflow/issues/177)
**Spec:** [`docs/superpowers/specs/2026-07-27-conditional-implementation-contract-design.md`](../specs/2026-07-27-conditional-implementation-contract-design.md)
**Date:** 2026-07-27

---

## Constraints — read before starting

- **Do not put the shared file in `partials/`.** `setup/link-partials.sh:74` picks
  up every `*.md` there except `README.md` and `@`-imports it into the user-level
  `~/.claude/CLAUDE.md` — the contract would be injected into every session in
  every project. The file goes in `commands/gh/`. This overrides the word
  "partial" in #177's own suggestion; the spec records why.
- **Do not modify `setup/link-commands.sh`.** Its existing
  `find "$SRC_DIR" -type f -name '*.md'` already picks up the new file.
- **There is no automated validation of command `.md` files in this repo.**
  `just lint` runs `actionlint` + `shellcheck` over `.github/workflows/`,
  `scripts/`, and `tests/` only. **Do not add a test framework, a fixture, or a
  `tests/` entry.** Verification is the string-presence checks written into each
  step.
- **Every verification check must print on both paths** — `… && echo "… OK" ||
  echo "FAIL: …"`. A bare `grep -q … && echo OK` is silent on failure and a
  `grep -c` returning `0` *exits* `1`; both read as ambiguous steps in CI. (See
  `a6f7c75`.)
- **Do not use `git diff … main`** in a check — in an `actions/checkout` clone
  `main` is often not a local ref, so it errors instead of failing. Assert on file
  content.
- **The code variant's wording is not up for editing.** Copy the existing block
  verbatim out of `commands/gh/implement.md:47-61`. This task deduplicates it; it
  does not reword it.
- **Preserve** each caller's other sections — `assign.md`'s agent-default and
  actor-resolution logic, `implement.md`'s four preconditions and label mechanics.
- Reference `#177` in every commit; Conventional Commits.

## Verification checks are pre-validated

The `grep`/`awk` idioms below follow the ones dry-run validated for #173. Where a
check greps for prose that wraps across lines, it matches a **single-line
substring**, never the full sentence.

## File Structure

| File | Responsibility |
|---|---|
| `commands/gh/implementation-contract.md` | **Create.** Single source of truth: both variants + the detection rule. Also usable directly as `/gh:implementation-contract`. |
| `commands/gh/assign.md` | **Modify.** Replace the inline TDD block (lines 25–45) with variant selection + a reference. |
| `commands/gh/implement.md` | **Modify.** Same for lines 43–63. |
| `CHANGELOG.md` | **Modify.** `[Unreleased]` → `### Changed`. |

---

### Task 1: The shared contract file

**Files:**
- Create: `commands/gh/implementation-contract.md`

**Interfaces:**
- Consumes: nothing.
- Produces: the file both Task 2 and Task 3 reference by the installed path
  `~/.claude/commands/gh/implementation-contract.md`, and the detection rule they
  must **not** restate.

- [ ] **Step 1: Create the file**

Front-matter, then three sections — detection, code variant, docs-only variant.

```markdown
---
description: The implementation contract posted onto an issue before dispatch — code (TDD) and docs-only variants
---

The contract `/gh:assign` and `/gh:implement` post onto an issue before handing it
to a coding agent. Two variants; **pick exactly one** using the rule below, and say
which one you picked and why before posting it.

Invoked directly (`/gh:implementation-contract`), print both variants so they can be
inspected or pasted by hand.

## Which variant

Apply in order — first match wins:

1. **Explicit statement** in the AC or body — "docs-only", "no test is added or
   changed", or "no file under `<source dir>` is modified" → **docs-only**.
2. **`documentation` label** on the issue → **docs-only**.
3. **AC file paths** are all documentation-shaped (`docs/**`, `*.md`, `README`,
   `CHANGELOG`) → **docs-only**.
4. **Anything else, including ambiguity → code.** Defaulting to TDD is the safe
   direction: a spurious test costs less than a silently untested change.

Two traps worth naming:

- In a repo whose *product* is `.md` files (this one — `commands/**/*.md`), rule 3
  correctly yields docs-only, because no test harness can cover them. That is not
  a bug in the rule; don't "fix" it to require a `docs/` prefix.
- A change under `scripts/**` or `tests/**` **is** code even in a
  CI-automation repo, and takes the code variant.

## Code variant

```bash
gh issue comment <N> --body "## TDD Required — Non-Negotiable

Implement using Test-Driven Development:
- **RED:** Write a failing test first. Run it. Confirm it fails for the right reason.
- **GREEN:** Write the minimal code to make it pass. No more.
- **REFACTOR:** Clean up while keeping tests green.

No production code without a failing test first.

Your PR description must include TDD evidence:
- RED: command run + relevant failing output
- GREEN: command run + passing output"
```

## Docs-only variant

Same evidence discipline, no tests.

```bash
gh issue comment <N> --body "## Implementation contract — docs-only change

This issue is **documentation-only**. The standard TDD contract does **not** apply:
do not add, modify, or delete any test, and do not touch source directories. A PR
that adds tests for this change is wrong and will be rejected.

The equivalent evidence requirement still holds — verify with commands, not
assertions:

- **BEFORE:** run the verification command from the Acceptance Criteria and paste
  the output showing the stale/missing state.
- **AFTER:** run the same command and paste the output showing the AC is satisfied.

Your PR description must include:

- The before/after output of the verification command
- An explicit list of every file changed, and confirmation that the files marked
  **do NOT touch** in the issue are unmodified (\`git diff --name-only\` output is
  enough)

Do not \"improve\" adjacent documentation that the Acceptance Criteria does not name."
```

Replace `<N>` with the actual issue number.

---

If a real dispatch shows the detection rule misfiring, fix the rule here and update
this file for the future.
```

- [ ] **Step 2: Verify**

```bash
f=commands/gh/implementation-contract.md
test -f "$f" && echo "file exists OK" || echo "FAIL: missing"
sed -n '1,4p' "$f" | grep -q '^description: ' && echo "front-matter OK" || echo "FAIL: front-matter"
grep -Fq 'No production code without a failing test first' "$f" && echo "code variant OK" || echo "FAIL: code variant"
grep -Fq 'Implementation contract — docs-only change' "$f" && echo "docs variant OK" || echo "FAIL: docs variant"
grep -Fq 'ambiguity → code' "$f" && echo "default-to-code rule OK" || echo "FAIL: default rule"
tail -4 "$f" | grep -q 'update this file for the future' && echo "self-improving footer OK" || echo "FAIL: footer"

# it must NOT have landed in partials/ — that directory is @-imported globally
test -e partials/implementation-contract.md && echo "FAIL: file is in partials/" || echo "not in partials OK"
ls partials/ | sort | tr '\n' ' '; echo "  <- must be the original 6 files"

# the installer was not touched
grep -Fq "find \"\$SRC_DIR\" -type f -name '*.md'" setup/link-commands.sh \
  && echo "installer untouched OK" || echo "FAIL: installer changed"
```

Expected: seven `OK` lines, and `partials/` listing exactly
`README.md response-formatting.md scope-boundary.md skill-authoring.md subagent-driven-default.md task-checklist.md`.

- [ ] **Step 3: Commit**

```bash
git add commands/gh/implementation-contract.md
git commit -m "feat(commands): add shared implementation contract with docs-only variant (#177)"
```

---

### Task 2: `/gh:assign` selects a variant

**Files:**
- Modify: `commands/gh/assign.md`

**Interfaces:**
- Consumes: `commands/gh/implementation-contract.md` from Task 1, referenced by its
  installed path.
- Produces: the caller pattern Task 3 repeats verbatim.

- [ ] **Step 1: Replace the `## Post TDD contract` section**

Replace the whole section — heading on line 25 through
`Replace \`<N>\` with the actual issue number (from \`$ARGUMENTS\`).` on line 45 —
with:

```markdown
## Post the implementation contract

Read `~/.claude/commands/gh/implementation-contract.md` and follow it: apply its
ordered detection rule to this issue, pick **one** variant, and post that variant
as an issue comment with `<N>` replaced by the issue number from `$ARGUMENTS`.

That file is the single source of truth for both the rule and the two contract
bodies — do not restate either here.

Before posting, print one line naming the variant chosen and the rule that selected
it, e.g. `contract: docs-only (rule 1 — AC says "no test is added or changed")`, so
the operator can correct it before the agent picks the issue up.
```

**Match on the quoted text, not the line numbers** — they shift as soon as the
first edit lands.

- [ ] **Step 2: Verify**

```bash
f=commands/gh/assign.md
grep -Fq 'implementation-contract.md' "$f" && echo "references shared file OK" || echo "FAIL: no reference"
grep -Fq 'No production code without a failing test first' "$f" && echo "FAIL: inline TDD block still here" || echo "inline block removed OK"
grep -Fq 'do not restate either here' "$f" && echo "no-duplication note OK" || echo "FAIL: missing note"
grep -Fq 'contract: docs-only' "$f" && echo "announces variant OK" || echo "FAIL: no announcement"

# the rest of the command survived
grep -Fq 'copilot-swe-agent' "$f" && echo "actor logic intact OK" || echo "FAIL: actor logic lost"
grep -Fq 'Agent default' "$f" && echo "agent default intact OK" || echo "FAIL: agent default lost"
grep -Fq 'replaceActorsForAssignable' "$f" && echo "mutation intact OK" || echo "FAIL: mutation lost"
```

Expected: seven `OK` lines.

- [ ] **Step 3: Commit**

```bash
git add commands/gh/assign.md
git commit -m "feat(commands): /gh:assign selects contract variant by issue shape (#177)"
```

---

### Task 3: `/gh:implement` selects a variant

**Files:**
- Modify: `commands/gh/implement.md`

**Interfaces:**
- Consumes: Task 1's file and Task 2's caller wording — use the **same** block,
  changing only the `$ARGUMENTS` phrasing to match this command.

- [ ] **Step 1: Replace the `## Post TDD contract` section**

Replace the heading on line 43 through `Replace \`<N>\` with the actual issue
number.` on line 63 with the same block as Task 2 Step 1, with the first paragraph's
closing clause reading `with \`<N>\` replaced by the actual issue number.`

- [ ] **Step 2: Verify**

```bash
f=commands/gh/implement.md
grep -Fq 'implementation-contract.md' "$f" && echo "references shared file OK" || echo "FAIL: no reference"
grep -Fq 'No production code without a failing test first' "$f" && echo "FAIL: inline TDD block still here" || echo "inline block removed OK"
grep -Fq 'contract: docs-only' "$f" && echo "announces variant OK" || echo "FAIL: no announcement"

# preconditions and label mechanics survived
grep -Fq 'ai-implement' "$f" && echo "label mechanics intact OK" || echo "FAIL: label logic lost"
grep -Fq 'Issue is ready for an agent' "$f" && echo "preconditions intact OK" || echo "FAIL: preconditions lost"

# neither caller still carries a duplicated contract body
for g in commands/gh/assign.md commands/gh/implement.md; do
  grep -Fq 'RED:' "$g" && echo "FAIL: contract body still inline in $g" || echo "deduplicated OK: $g"
done
```

Expected: seven `OK` lines.

- [ ] **Step 3: Commit**

```bash
git add commands/gh/implement.md
git commit -m "feat(commands): /gh:implement selects contract variant by issue shape (#177)"
```

---

### Task 4: Changelog

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add the entry**

Under `## [Unreleased]`, in `### Changed` (create it after `### Added` if absent):

```markdown
- **commands:** `/gh:assign` and `/gh:implement` now pick an implementation
  contract by issue shape — the TDD contract for code changes, a before/after
  verification contract for docs-only issues — from the new shared
  `/gh:implementation-contract` (#177)
```

- [ ] **Step 2: Verify**

```bash
awk '/^## \[Unreleased\]/{u=1} /^## \[1\./{u=0} u && /^### Changed/{c=1} u && c && /contract/{r=1} u && c && /#177/{n=1} END{ if (r && n) print "changelog OK"; else print "FAIL: changelog contract=" (r?1:0) " ref177=" (n?1:0) }' CHANGELOG.md
grep -Fq '/milestone` (+ `/gh:milestone`, `/fj:milestone`)' CHANGELOG.md && echo "prior entries intact OK" || echo "FAIL: clobbered earlier entries"
```

Expected: two `OK` lines.

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for conditional implementation contract (#177)"
```

---

## Manual verification (human, after merge)

[ ] **1.** Re-run `setup/link-commands.sh`, confirm
`~/.claude/commands/gh/implementation-contract.md` exists and
`/gh:implementation-contract` prints both variants.

[ ] **2.** Run `/gh:assign 173` — #173 touches only `commands/**/*.md` and
`CHANGELOG.md`, and its plan forbids adding tests. Confirm the command announces
the **docs-only** variant and posts the before/after contract, not the TDD one.

[ ] **3.** Run `/gh:assign` against an issue whose AC names `scripts/**` and confirm
it announces the **code** variant.

[ ] **4.** Confirm `~/.claude/CLAUDE.md` gained **no** new `@`-import — the contract
must not have leaked into the global partial set.
