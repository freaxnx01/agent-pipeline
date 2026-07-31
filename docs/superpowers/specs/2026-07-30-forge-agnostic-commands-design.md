# Merge gh:*/fj:* command pairs into forge-agnostic commands

**Status:** Accepted
**Date:** 2026-07-30
**Relates to:** #198, #199, #204 (epic: reduce skill/slash-command context overhead)

## Problem

Twelve concepts (`done`, `enrich`, `enrich-phased`, `issues`, `milestone`, `new`,
`parked`, `prs`, `roadmap`, `route`, `triage`, `work`) each exist as three separate
command files:

- `commands/<concept>.md` — auto-router: detects GitHub vs Forgejo from the
  `origin` remote, then tells Claude to "read and follow" the matching one below.
- `commands/gh/<concept>.md` — the GitHub implementation.
- `commands/fj/<concept>.md` — the Forgejo implementation.

Every command file's frontmatter `description:` is loaded into every Claude Code
session's skill listing regardless of whether it's ever invoked — only the body
loads lazily on invocation. That's 36 always-loaded descriptions (3,454 bytes) for
12 concepts, when 12 would do.

The host-detection snippet itself (~20 lines of bash) is also copy-pasted verbatim
into all 12 auto-router files — a second, independent maintenance cost from the
same split.

## Non-goals

- **Unifying GitHub and Forgejo query logic behind a common function surface**
  (e.g. a `create_issue`/`list_issues` adapter library, as #199 originally framed
  it). Investigation shows most concepts don't share structure: GitHub queries via
  GraphQL (`gh api graphql`); Forgejo has no GraphQL, so WIP/parked/roadmap
  filtering is derived from REST + a Python regex script. Forcing a common
  interface over genuinely different logic would be the wrong abstraction. The
  only shared piece is host detection.
- **Changing what any command actually does.** This is a structural merge — the
  GitHub and Forgejo logic bodies move into new files unchanged; behavior for an
  end user typing `/issues`, `/enrich`, etc. does not change.
- **Touching GitHub-only commands with no Forgejo sibling** — `gh:assign`,
  `gh:implement`, `gh:implementation-contract`, `gh:review`. Out of scope; nothing
  to merge.
- **A deprecation shim for the removed `gh:x`/`fj:x` commands.** Clean removal,
  documented as a breaking change (see Rollout). Consumer installs are pinned by
  copy (`setup/link-commands.sh` default), so nothing breaks until a user
  re-installs — that's the softening, not a code-level shim.

## Design

### Shared piece: `scripts/lib/detect-forge.sh`

Extract the duplicated host-detection snippet into one sourceable script,
following this repo's existing `scripts/lib/*.sh` convention (e.g.
`gh-retry.sh`):

```bash
# scripts/lib/detect-forge.sh — sourced, not executed.
#   detect_forge   echoes "github <host>" | "forgejo <host>" | "unknown <host>"
detect_forge() {
  local host
  host=$(git remote get-url origin 2>/dev/null | sed -E 's#^[a-zA-Z]+://##; s#^[^@/]*@##; s#[:/].*##')
  if gh auth token --hostname "$host" >/dev/null 2>&1; then
    echo "github $host"
  elif tea logins list 2>/dev/null | grep -qiF "$host"; then
    echo "forgejo $host"
  elif [ "$host" = "github.com" ]; then
    echo "github $host"
  else
    echo "unknown $host"
  fi
}
```

### Merged command files

For each of the 12 concepts, `commands/<concept>.md` becomes:

````markdown
---
description: <forge-agnostic combined description>
[argument-hint: ... — carried over if either side had one]
---

Detect the forge, then run the matching section below.

```bash
source "$(dirname "$0")/../scripts/lib/detect-forge.sh"   # path resolved relative to repo root at runtime
detect_forge
```

## GitHub

<current commands/gh/<concept>.md body, verbatim, minus its own frontmatter>

## Forgejo

<current commands/fj/<concept>.md body, verbatim, minus its own frontmatter>

## Unknown host

Report the detected host and that no authed GitHub or Forgejo login matched it;
point at `gh auth login` / `tea login add`. Don't guess a forge.
````

`commands/gh/<concept>.md` and `commands/fj/<concept>.md` are deleted for these 12
concepts. `commands/gh/` and `commands/fj/` remain as directories, holding only the
GitHub-only commands (`assign`, `implement`, `implementation-contract`, `review`)
plus whatever Forgejo-only commands exist, if any.

### Docs

- `commands/README.md`: replace the separate "Forge routers" / "GitHub" /
  "Forgejo" sections with one list of the 12 forge-agnostic commands. Keep the
  GitHub-only and Forgejo-only sections for what remains there.
- `CHANGELOG.md`: `[Unreleased]` → `Removed` lists all 24 deleted commands,
  pointing at their replacement; `Changed` notes the `detect-forge.sh` extraction.
- `VERSION`: bump major (breaking change to the command console's public surface).

## Testing

`detect-forge.sh` is a genuine sourceable script — it gets real Layer-1 fixture
tests, TDD (write failing cases first):

- New `tests/mocks/tea`, parallel to the existing `tests/mocks/gh` argv-logging
  mock, with a controllable `tea logins list` output.
- New `tests/run-detect-forge-tests.sh`: builds a throwaway repo with each remote
  URL shape (`https://github.com/...`, `git@github.com:...`,
  `ssh://git@git.home.freaxnx01.ch/...`, an unrecognized host), and asserts
  `detect_forge` returns the expected `github <host>` / `forgejo <host>` /
  `unknown <host>` under each `gh`/`tea` mock outcome.

The merged `commands/<concept>.md` files are prompt files, not executable
scripts — no Layer-1 test applies. They get Layer 0 (`markdownlint` via
pre-commit, already gating this repo) plus a manual smoke check per concept
against a real GitHub-remote repo, confirming output matches the current
`gh:<concept>` behavior (no logic change, since bodies are copied verbatim).
Layers 2–4 don't apply — no `.github/workflows/` changes.

## Rollout

One PR, all 12 concepts — same mechanical pattern, no shared state between
concepts, easy to review concept-by-concept.

1. `scripts/lib/detect-forge.sh` + its tests (TDD: red → green).
2. Merge all 12 concepts.
3. Delete the 24 superseded `gh:x`/`fj:x` files.
4. Update `commands/README.md`.
5. `CHANGELOG.md` `Removed`/`Changed` entries; bump `VERSION` major.

Consumer repos install by copy by default (`setup/link-commands.sh`), so existing
installs of `/gh:issues` etc. keep working until the consumer re-runs the
installer — softening the breaking change without a code-level shim.

## Success criteria

1. 12 merged `commands/<concept>.md` files exist; 24 `commands/gh/<concept>.md` /
   `commands/fj/<concept>.md` files are deleted.
2. `scripts/lib/detect-forge.sh` exists, is sourced by all 12 merged files, and its
   fixture tests pass (`tests/run-detect-forge-tests.sh`).
3. For each of the 12 concepts, running the merged command against a real
   GitHub-remote repo produces output matching the current `gh:<concept>` output.
4. `commands/README.md`, `CHANGELOG.md`, and `VERSION` are updated.
5. Total skill-description byte count for these 12 concepts drops from 3,454 bytes
   (36 entries) to the 12 merged descriptions' actual size — re-measure and update
   the stats table in issue #204.
6. `pre-commit` (markdownlint + existing hooks) passes on the whole diff.
