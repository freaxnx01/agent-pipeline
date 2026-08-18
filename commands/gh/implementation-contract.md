---
description: The implementation contract posted onto an issue before dispatch — code (TDD), docs-only, and buildless variants
---

The contract `/gh:assign` and `/gh:implement` post onto an issue before handing it
to a coding agent. Three variants; **pick exactly one** using the rule below, and say
which one you picked and why before posting it.

Invoked directly (`/gh:implementation-contract`), print all variants so they can be
inspected or pasted by hand.

## Which variant

Apply in order — first match wins:

1. **Explicit statement** in the AC or body — "docs-only", "no test is added or
   changed", or "no file under `<source dir>` is modified" → **docs-only**.
2. **`documentation` label** on the issue → **docs-only**.
3. **AC file paths** are all documentation-shaped (`docs/**`, `*.md`, `README`,
   `CHANGELOG`) → **docs-only**.
4. **Repo has no test harness** → **buildless**. The change touches source, so
   docs-only is wrong, but there is no runner to write a failing test with.
   Confirm with the repo itself, not a guess — all three of:
   - No test runner is resolvable — no `package.json` `test` script, no test
     framework config (`jest.config.*`, `vitest.config.*`, `pytest.ini`,
     `*.csproj` test project, `go.mod` with `_test.go` files, …), no `tests/`
     or `spec/` tree with real test files.
   - The repo's `CLAUDE.md` / stack overlay names a **manual** gate instead —
     grep for `manual .*playtest`, `no build/test toolchain`, `buildless`, or a
     documented "deviation from base's TDD-first mandate".
   - The issue's own plan contains no test step.

   If the repo has a runner but this issue merely doesn't add tests, that is
   **not** this case — use code and let the agent write the test.

5. **Anything else, including ambiguity → code.** Defaulting to TDD is the safe
   direction: a spurious test costs less than a silently untested change.

Three traps worth naming:

- In a repo whose *product* is `.md` files (this one — `commands/**/*.md`), rule 3
  correctly yields docs-only, because no test harness can cover them. That is not
  a bug in the rule; don't "fix" it to require a `docs/` prefix.
- A change under `scripts/**` or `tests/**` **is** code even in a
  CI-automation repo, and takes the code variant.
- Rule 5 used to be rule 4, and it silently swallowed buildless repos:
  `game-geography-quiz#18` (a data-only edit to `geo-data.js` in a vanilla-JS
  browser game) fell through to code, whose contract demands "write a failing
  test first… paste the failing output". That repo has no runner at all and its
  stack overlay *forbids* adding one, so the contract's only satisfiable
  readings were "scaffold a test framework against an explicit guardrail" or
  "fabricate RED/GREEN output". Rule 4 exists to catch that before dispatch.

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

## Buildless variant

Source changes in a repo with no test runner. Same evidence discipline as
docs-only, but it does **not** claim the change is documentation and does
**not** forbid touching source — the whole point is that source is being
edited without a harness to test it.

Fill in the two `<...>` placeholders from the issue's own plan before posting.
If the plan has no verification commands, that is a gap in the plan — say so
and stop, rather than posting a contract with nothing to verify against.

```bash
gh issue comment <N> --body "## Implementation contract — buildless repo, no test framework

This repo has **no test runner, no bundler, no package manifest**, and you must
**not** add one — that is an explicit stack guardrail. The standard TDD contract
does **not** apply: do not create, modify, or delete any test file. A PR that
adds a test framework or a test file for this change is wrong and will be
rejected.

The equivalent evidence requirement still holds — verify with commands, not
assertions:

- **BEFORE:** run the plan's verification commands and paste the output showing
  the pre-change state (expect: <expected before-state>).
- **AFTER:** run the same commands and paste the output showing the AC is
  satisfied (expect: <expected after-state>).

Your PR description must include:

- The before/after output of **every** verification command
- \`git diff --name-only\` output confirming only the files the Acceptance
  Criteria names were changed

This repo's real test gate is a **manual** check a pipeline cannot perform.
Do **not** claim you ran it. List it in the PR description as the outstanding
human verification step, so the reviewer knows it is still owed.

If a stated acceptance criterion contradicts what you actually observe in the
repo, do **not** bend the implementation to satisfy the wrong number. Implement
what the plan's concrete deliverable specifies and document the discrepancy in
the PR description.

## Turn budget discipline — non-negotiable

You are running with a finite turn budget in an unattended pipeline. If it runs
out mid-implementation, everything uncommitted is lost — there is no partial
credit for edits sitting only in your working tree.

- **Commit as soon as a step's verification commands pass** — do not batch every
  task into one final commit.
- **Trust the plan's line numbers and diffs.** Only re-read a file if a step's
  actual command output contradicts what the plan expected.

Do not \"improve\" adjacent code that the Acceptance Criteria does not name."
```

Replace `<N>` with the actual issue number.

---

If a real dispatch shows the detection rule misfiring, fix the rule here and update this file for the future.
