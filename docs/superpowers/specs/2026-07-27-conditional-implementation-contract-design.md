# Design: conditional implementation contract (code vs docs-only)

**Issue:** [#177](https://github.com/freaxnx01/agent-workflow/issues/177)
**Date:** 2026-07-27
**Status:** approved — "extract to a shared file, two variants" confirmed by the
user; the *location* of that shared file is a spec-level correction, see below.

---

## Problem

`commands/gh/assign.md` and `commands/gh/implement.md` both post the same
non-negotiable TDD contract onto an issue before handing it to a coding agent:

> No production code without a failing test first.

For a **docs-only** issue that instruction is actively wrong. It contradicts the
issue's own acceptance criteria and invites the agent to invent tests for a change
that touches no code. The commands offer no way out, so the operator has to
silently deviate — which is what happened while assigning two enriched docs-only
issues in a downstream repo.

**This is live in this repo right now.** [#173](https://github.com/freaxnx01/agent-workflow/issues/173)
was just enriched and touches only `commands/**/*.md` and `CHANGELOG.md`; its plan
states explicitly that no test may be added. Running `/gh:assign 173` today would
post "no production code without a failing test first" on top of that.

## Correction: not `partials/`

The agreed shape was "extract to a shared partial". **`partials/` is the wrong
directory** and the spec deliberately departs from that word.

`setup/link-partials.sh:74` picks up *every* `*.md` in `partials/` except
`README.md` and `@`-imports it into the user-level `~/.claude/CLAUDE.md`:

```bash
mapfile -t partial_files < <(find "$SRC_DIR" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' | sort)
```

`partials/README.md` says the same in prose: *"Any other `*.md` dropped into this
directory **is** imported automatically the next time the installer runs, no code
change required."* A contract file placed there would be injected into **every
session in every project**, unconditionally — the opposite of "apply this only when
dispatching an issue".

**Chosen location: `commands/gh/implementation-contract.md`.**

- `setup/link-commands.sh` already installs every `*.md` under `commands/` (skipping
  only `README.md`), so it lands at `~/.claude/commands/gh/implementation-contract.md`
  with **no installer change**.
- Both commands reference it by that path — the exact mechanism `commands/issues.md`
  already uses for delegation (*"read and follow `~/.claude/commands/gh/issues.md`"*).
- It also becomes `/gh:implementation-contract`, which is a feature rather than a
  cost: it lets the operator print either variant to inspect or paste by hand.

## Design

### The two variants

**Code variant** — the existing block, unchanged. RED / GREEN / REFACTOR, PR
description must show the failing then passing output.

**Docs-only variant** — same *evidence* discipline, no tests. Adapted from the
version that was actually used successfully in the downstream repo (quoted verbatim
in #177):

- Do not add, modify, or delete any test; do not touch source directories.
- **BEFORE:** run the verification command from the AC, paste output showing the
  stale/missing state.
- **AFTER:** run the same command, paste output showing the AC satisfied.
- PR description lists every file changed and confirms the files marked
  *do NOT touch* are unmodified (`git diff --name-only` is enough).
- Do not "improve" adjacent documentation the AC does not name.

The before/after pair maps cleanly onto RED/GREEN, so the contract keeps its teeth
where tests are not the right evidence.

### Detection

Classify from the issue itself, in this order:

1. **Explicit statement wins.** An AC or body line of the form "docs-only", "no test
   is added or changed", or "no file under `<source dir>` is modified" → docs-only.
2. **`documentation` label** → docs-only.
3. **AC file paths.** If every path named in the AC is documentation-shaped
   (`docs/**`, `*.md`, `README`, `CHANGELOG`) → docs-only.
4. **Anything else, including ambiguity → code variant.** Defaulting to TDD is the
   safe direction: a spurious test is cheaper than a silently untested change.

The command must **state which variant it chose and why** in its output before
posting, so the operator can correct it before dispatch.

### The `.md`-is-source caveat

In this repo `commands/**/*.md` are the *product*, not documentation — yet they
correctly take the **docs-only** variant, because there is no test harness that can
cover them (`just lint` reaches only `.github/workflows/`, `scripts/`, and
`tests/`). Rule 3 gets this right by accident, so it must not be "fixed" to exclude
`.md` files that live outside `docs/`.

The inverse matters more: a change to `scripts/**` or `tests/**` **is** code even
though this is a CI-automation repo, and takes the code variant.

## Acceptance Criteria

1. `commands/gh/implementation-contract.md` exists, with YAML front-matter
   (`description:`), and contains both contract variants as separately-labelled,
   copy-pasteable blocks.
2. It is **not** placed in `partials/`, and `partials/` is unmodified — a file there
   would be `@`-imported into the global `~/.claude/CLAUDE.md`.
3. `setup/link-commands.sh` is **unmodified** — the new file is picked up by the
   existing `find … -name '*.md'` discovery.
4. `commands/gh/assign.md` no longer contains an inline unconditional TDD block; it
   references the shared file and selects a variant.
5. `commands/gh/implement.md` likewise.
6. The detection rule (4 ordered steps above, ambiguity → code variant) appears in
   `commands/gh/implementation-contract.md` as the single source of truth, and is
   not restated divergently in the two callers.
7. Both callers instruct the agent to **report the chosen variant and the reason**
   before posting the comment.
8. The docs-only variant never contains the string "No production code without a
   failing test first", and the code variant still does.
9. `CHANGELOG.md` has an entry under `[Unreleased]` → `### Changed` referencing #177.

## Out of scope

- **Auditing other commands** for the same code-change assumption (`gh/work.md`,
  `gh/route.md`, the `fj/*` equivalents). #177 raises it as an open question; the
  chosen scope is the shared file plus the two named callers. Capture as a
  follow-up if the sweep is wanted.
- **A Forgejo equivalent.** Neither `/fj:work` nor any `fj/*` command posts a
  contract today, so there is nothing to deduplicate there.

## Verification

Automated: string-presence checks per task step — this repo has **no test framework
for command `.md` files**, so no test file or fixture may be added.

Manual, after merge:

1. Re-run `setup/link-commands.sh`, confirm
   `~/.claude/commands/gh/implementation-contract.md` exists.
2. Run `/gh:assign 173` (docs-only, touches only `commands/**/*.md`) and confirm it
   announces the **docs-only** variant and posts the before/after contract.
3. Run `/gh:assign` against a `scripts/**` issue and confirm it announces the
   **code** variant.
