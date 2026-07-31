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
- GREEN: command run + passing output

## Turn budget discipline — non-negotiable

You are running with a finite turn budget in an unattended pipeline. If it
runs out mid-implementation, everything uncommitted is lost — there is no
partial credit for edits sitting only in your working tree.

- **Commit after every task** in the Implementation Plan, the moment that
  task's own tests pass — do not front-load all edits across every task and
  commit once at the end. If this is the last task you complete before
  running out of turns, a committed-and-pushed partial PR (even an
  incomplete one, clearly noted as such in its description) is far more
  useful than nothing.
- **Trust the plan's line numbers and diffs.** The Implementation Plan
  already names exact files, line ranges, and before/after code. Only
  re-read a file if a step's actual command output contradicts what the
  plan expected (e.g. the diff doesn't apply cleanly) — don't defensively
  re-read files you were already given exact context for."
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

If a real dispatch shows the detection rule misfiring, fix the rule here and update this file for the future.
