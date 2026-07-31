# Forge-Agnostic Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge the 12 `commands/<concept>.md` + `commands/gh/<concept>.md` + `commands/fj/<concept>.md` trios (36 files) into 12 single forge-agnostic `commands/<concept>.md` files, backed by a shared `scripts/lib/detect-forge.sh`, cutting the always-loaded skill-description count for these concepts from 36 to 12.

**Architecture:** Extract the duplicated host-detection bash into one sourceable script (`scripts/lib/detect-forge.sh`). For each concept, replace the 3-file trio with one file that sources that script, branches on its output, and contains the current `gh/<concept>.md` body under `## GitHub` and the current `fj/<concept>.md` body under `## Forgejo`, verbatim except for renaming in-body cross-references to sibling merged commands. Delete the 24 superseded files. No unification of GitHub/Forgejo query logic — see the design's Non-goals.

**Tech Stack:** Bash 5+ (`set -euo pipefail`), `gh` CLI, `tea` CLI, Claude Code slash-command markdown files, `markdownlint-cli2` (pre-commit), `git-cliff`/`Keep a Changelog` conventions.

**Reference spec:** `docs/superpowers/specs/2026-07-30-forge-agnostic-commands-design.md`

## Global Constraints

- Use Test-Driven Development for every task: write a failing test first, watch it fail, implement minimally to pass, verify green.
- For `scripts/lib/detect-forge.sh` (Task 1) this means real fixture tests (red → green) per the repo's Layer-1 convention.
- For the 12 merge tasks (Tasks 2–13), the "test" is not a unit test — merged files are prompt markdown, not executable code. Substitute verification, per the design's Testing section: (a) a grep-based static check that no stale `gh:`/`fj:` self-references remain among the 12 in-scope concepts, which must fail before the fix and pass after; (b) `markdownlint-cli2` on the new file, which must pass before commit. Treat the grep check as the "red" step and its clean pass as "green."
- Every task ends with a commit. Reference issues **#198** and **#199** in commit messages.
- Do not touch `gh:assign`, `gh:implement`, `gh:implementation-contract`, `gh:review` — no Forgejo sibling exists, out of scope.
- The 12 in-scope concepts, used throughout: `done`, `enrich`, `enrich-phased`, `issues`, `milestone`, `new`, `parked`, `prs`, `roadmap`, `route`, `triage`, `work`.

---

## Task 1: `scripts/lib/detect-forge.sh` + fixture tests

**Files:**
- Create: `scripts/lib/detect-forge.sh`
- Create: `tests/mocks/tea`
- Modify: `tests/mocks/gh` (additive env-var seam only — do not change existing behavior)
- Create: `tests/run-detect-forge-tests.sh`
- Modify: `justfile:20` (add a line to the `test` recipe)
- Test: `tests/run-detect-forge-tests.sh` (self-contained; also the deliverable's own test runner)

**Interfaces:**
- Produces: `detect_forge()` — a bash function, sourced (not executed), taking no arguments, reading `origin` from the cwd's git config, printing exactly one line to stdout: `"github <host>"`, `"forgejo <host>"`, or `"unknown <host>"`. Consumed by Tasks 2–13's merged command files via `source "$(dirname "$0")/../scripts/lib/detect-forge.sh"` (conceptually — command files are prompts, not scripts, so the merged file's bash step literally contains `source .../detect-forge.sh; detect_forge`).

- [ ] **Step 1: Write the failing test script**

Create `tests/run-detect-forge-tests.sh`:

```bash
#!/usr/bin/env bash
#
# run-detect-forge-tests.sh — Layer-1 fixture tests for scripts/lib/detect-forge.sh
# (no network). Builds a throwaway git repo per case, points PATH at tests/mocks/,
# sources the script, and asserts detect_forge's output.
#
# Usage: tests/run-detect-forge-tests.sh
# Exit codes: 0 all pass; 1 at least one assertion failed.
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/scripts/lib/detect-forge.sh"
MOCKS="$ROOT/tests/mocks"

PASS=0
FAIL=0
FAIL_NAMES=()

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_GREEN=''; C_RED=''; C_DIM=''; C_OFF=''
fi

section() { printf '\n%s── %s ──%s\n' "$C_DIM" "$1" "$C_OFF"; }
pass() { PASS=$((PASS + 1)); printf '  %s✓%s %s\n' "$C_GREEN" "$C_OFF" "$1"; }
fail() {
  FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1")
  printf '  %s✗%s %s\n' "$C_RED" "$C_OFF" "$1"
  [ $# -gt 1 ] && printf '      %s\n' "$2"
  return 0
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "expected: $expected | actual: $actual"
  fi
}

# make_repo <remote-url>  — throwaway git repo with that origin, echoes its path
make_repo() {
  local dir; dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$1"
  echo "$dir"
}

# run_detect_forge <repo-dir> [GH_MOCK_AUTH_HOSTS] [TEA_MOCK_LOGINS]
run_detect_forge() {
  local dir="$1" auth_hosts="${2:-}" tea_logins="${3:-}"
  (
    cd "$dir"
    export PATH="$MOCKS:$PATH"
    export GH_MOCK_AUTH_HOSTS="$auth_hosts"
    export TEA_MOCK_LOGINS="$tea_logins"
    # shellcheck disable=SC1090
    source "$LIB"
    detect_forge
  )
}

# --- cases -------------------------------------------------------------

section "github"

REPO="$(make_repo "https://github.com/freaxnx01/agent-workflow.git")"
assert_eq "https remote, gh authed" "github github.com" \
  "$(run_detect_forge "$REPO" "github.com" "")"
rm -rf "$REPO"

REPO="$(make_repo "git@github.com:freaxnx01/agent-workflow.git")"
assert_eq "scp-style remote, gh authed" "github github.com" \
  "$(run_detect_forge "$REPO" "github.com" "")"
rm -rf "$REPO"

REPO="$(make_repo "https://github.com/freaxnx01/agent-workflow.git")"
assert_eq "github.com fallback when gh not authed" "github github.com" \
  "$(run_detect_forge "$REPO" "" "")"
rm -rf "$REPO"

section "forgejo"

REPO="$(make_repo "ssh://git@git.home.freaxnx01.ch/freax/hello-forgejo.git")"
assert_eq "ssh remote, tea login matches" "forgejo git.home.freaxnx01.ch" \
  "$(run_detect_forge "$REPO" "" "git.home.freaxnx01.ch")"
rm -rf "$REPO"

section "unknown"

REPO="$(make_repo "https://gitlab.example.com/freax/whatever.git")"
assert_eq "unrecognized host, no gh/tea match" "unknown gitlab.example.com" \
  "$(run_detect_forge "$REPO" "" "")"
rm -rf "$REPO"

# --- summary -------------------------------------------------------------

printf '\n%s─────%s\n' "$C_DIM" "$C_OFF"
printf '  %s%d passed%s' "$C_GREEN" "$PASS" "$C_OFF"
if [ "$FAIL" -gt 0 ]; then
  printf ', %s%d failed%s\n' "$C_RED" "$FAIL" "$C_OFF"
  printf '\nFailed:\n'
  for n in "${FAIL_NAMES[@]}"; do printf '  - %s\n' "$n"; done
  exit 1
fi
printf '\n'
exit 0
```

```bash
chmod +x tests/run-detect-forge-tests.sh
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run-detect-forge-tests.sh`
Expected: FAIL — `scripts/lib/detect-forge.sh: No such file or directory` (the lib doesn't exist yet), and `tests/mocks/tea` doesn't exist either.

- [ ] **Step 3: Write `tests/mocks/tea`**

```bash
#!/usr/bin/env bash
#
# tea — minimal stand-in for the Forgejo/Gitea `tea` CLI used by Layer-1 fixture
# tests. `tea logins list` prints $TEA_MOCK_LOGINS (one login/host per line)
# instead of querying real config. If $TEA_MOCK_LOG is set, appends each
# invocation's argv as a space-joined line to it. Exits 0 by default.
set -euo pipefail
IFS=$'\n\t'

if [[ -n "${TEA_MOCK_LOG:-}" ]]; then
  ( IFS=' '; printf '%s\n' "$*" >> "$TEA_MOCK_LOG" )
fi

if [[ "${1:-}" == "logins" && "${2:-}" == "list" ]]; then
  printf '%s\n' "${TEA_MOCK_LOGINS:-}"
  exit 0
fi

exit 0
```

```bash
chmod +x tests/mocks/tea
```

- [ ] **Step 4: Add the auth-hosts seam to `tests/mocks/gh`**

Open `tests/mocks/gh`. After the argv-logging line (`( IFS=' '; printf '%s\n' "$*" >> "$GH_MOCK_LOG" )`) and before the existing `pr create` fail-injection block, insert:

```bash
if [[ "${1:-}" == "auth" && "${2:-}" == "token" && -n "${GH_MOCK_AUTH_HOSTS:-}" ]]; then
  host="${4:-}"
  for h in $GH_MOCK_AUTH_HOSTS; do
    [[ "$h" == "$host" ]] && exit 0
  done
  exit 1
fi
```

Also update the mock's header comment to document the new seam:
`#   GH_MOCK_AUTH_HOSTS  space-separated hosts 'gh auth token --hostname' succeeds for`

This is purely additive — when `GH_MOCK_AUTH_HOSTS` is unset (every existing caller of this mock), the new branch's condition is false and behavior is unchanged.

- [ ] **Step 5: Write `scripts/lib/detect-forge.sh`**

```bash
#!/usr/bin/env bash
#
# detect-forge.sh — sourced, not executed.
#   detect_forge   echoes "github <host>" | "forgejo <host>" | "unknown <host>"
#                  based on the cwd's `origin` remote.
set -euo pipefail
IFS=$'\n\t'

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

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash tests/run-detect-forge-tests.sh`
Expected: `5 passed`, exit 0.

- [ ] **Step 7: Wire into `just test`**

In `justfile`, the `test` recipe (around line 19-20) currently reads:

```just
test:
    bash tests/run-script-tests.sh
```

Change to:

```just
test:
    bash tests/run-script-tests.sh
    bash tests/run-detect-forge-tests.sh
```

- [ ] **Step 8: Commit**

```bash
git add scripts/lib/detect-forge.sh tests/mocks/tea tests/mocks/gh tests/run-detect-forge-tests.sh justfile
git commit -m "feat(commands): add shared detect-forge.sh for gh/fj consolidation

Refs #198, #199"
```

---

## Task template for Tasks 2–13 (one per concept)

Each of the following 12 tasks follows this exact procedure, substituting `<concept>` and the frontmatter given in that task's own section. Read this template once; it is not repeated in full for each task.

**Files (per concept):**
- Create/Overwrite: `commands/<concept>.md`
- Delete: `commands/gh/<concept>.md`
- Delete: `commands/fj/<concept>.md`

**Procedure:**

1. **Read** the current `commands/gh/<concept>.md` and `commands/fj/<concept>.md` in full.
2. **Write the failing check** — before changing anything, run:
   ```bash
   grep -nE '(/|[^:/A-Za-z])(gh|fj):(done|enrich|enrich-phased|issues|milestone|new|parked|prs|roadmap|route|triage|work)\b' commands/gh/<concept>.md commands/fj/<concept>.md
   ```
   This lists every in-body cross-reference to a sibling merged command that will need renaming (empty output is fine — not every file has one). This grep run *is* the red step: it must be re-run after the merge (Step 5 below) and produce **zero** matches inside the new `commands/<concept>.md`, which is the green step.
3. **Compose** `commands/<concept>.md`:
   - Frontmatter: the `description:` (and `argument-hint:` if present) given in this task's own section below.
   - Body:
     ```markdown
     Detect the forge, then run the matching section below.

     ```bash
     source "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib/detect-forge.sh"
     detect_forge
     ```

     ## GitHub

     <body of commands/gh/<concept>.md, everything after its closing `---`, unchanged>

     ## Forgejo

     <body of commands/fj/<concept>.md, everything after its closing `---`, unchanged>

     ## Unknown host

     Report the detected host and that no authed GitHub or Forgejo login matched
     it; point at `gh auth login` / `tea login add`. Don't guess a forge.
     ```
4. **Rename in-body cross-references**: in the `## GitHub` and `## Forgejo` sections just pasted, rewrite every match the Step 2 grep found — `/gh:X` → `/X`, `gh:X` → `X`, `/fj:X` → `/X`, `fj:X` → `X` — for `X` in the 12 in-scope concepts only. Do **not** touch `gh:assign`, `gh:implement`, `gh:implementation-contract`, `gh:review` — leave those exactly as written.
5. **Run the grep again** to verify it's now clean:
   ```bash
   grep -nE '(/|[^:/A-Za-z])(gh|fj):(done|enrich|enrich-phased|issues|milestone|new|parked|prs|roadmap|route|triage|work)\b' commands/<concept>.md
   ```
   Expected: no output (exit 1 from grep, meaning zero matches). This is the green step.
6. **Lint**: `pre-commit run markdownlint-cli2 --files commands/<concept>.md`. Fix anything it flags.
7. **Delete** the superseded files: `git rm commands/gh/<concept>.md commands/fj/<concept>.md`.
8. **Commit**:
   ```bash
   git add commands/<concept>.md
   git commit -m "refactor(commands): merge gh:<concept>/fj:<concept> into /<concept>

   Refs #198, #199"
   ```

---

## Task 2: `done`

**Frontmatter:**
```yaml
description: Recently implemented (closed) issues
```
(no `argument-hint`)

- [ ] Follow the Task template above for `done`.

## Task 3: `enrich`

**Frontmatter:**
```yaml
description: Enrich an issue with a spec and implementation plan, then update the issue body so it's ready to implement
argument-hint: <issue number>
```

- [ ] Follow the Task template above for `enrich`.

## Task 4: `enrich-phased`

**Frontmatter:**
```yaml
description: Phased enrich (spec → /clear → plan → /clear → issue body), isolated context per phase
argument-hint: <issue number>
```

- [ ] Follow the Task template above for `enrich-phased`.

## Task 5: `issues`

**Frontmatter:**
```yaml
description: List open issues that are not WIP (no open PR), not parked, and not roadmap, newest first
```
(no `argument-hint`)

- [ ] Follow the Task template above for `issues`.

## Task 6: `milestone`

**Frontmatter:**
```yaml
description: List, create, assign, or triage milestones — list | new <name> [due <date>] | assign <issue> to <name> | triage
argument-hint: list | new <name> [due <date>] | assign <issue> to <name> | triage
```

- [ ] Follow the Task template above for `milestone`.

## Task 7: `new`

**Frontmatter:**
```yaml
description: Create an issue from notes, labeled needs-enrichment
argument-hint: <notes describing the issue>
```

- [ ] Follow the Task template above for `new`.

## Task 8: `parked`

**Frontmatter:**
```yaml
description: List and triage parked (🧊) issues — list | unpark <n> | repark <n> "<reason>" | review
argument-hint: list | unpark <n> | repark <n> "<reason>" | review
```

- [ ] Follow the Task template above for `parked`.

## Task 9: `prs`

**Frontmatter:**
```yaml
description: List pull requests awaiting review
```
(no `argument-hint`)

- [ ] Follow the Task template above for `prs`.

## Task 10: `roadmap`

**Frontmatter:**
```yaml
description: List and triage roadmap issues — list | promote <n> to <milestone> | defer <n> "<reason>"
argument-hint: list | promote <n> to <milestone> | defer <n> "<reason>"
```

- [ ] Follow the Task template above for `roadmap`.

## Task 11: `route`

**Frontmatter:**
```yaml
description: Recommend how to implement an issue — by complexity & readiness
argument-hint: <issue number>
```

- [ ] Follow the Task template above for `route`.

(Note: the current `commands/gh/route.md` frontmatter description mentions `gh:work / gh:assign copilot|claude / gh:implement` — that whole description string is replaced by the one above, not merged. Within the body text itself, rename only `gh:work` → `work` per Step 4 of the template; `gh:assign` and `gh:implement` stay as-is.)

## Task 12: `triage`

**Frontmatter:**
```yaml
description: Open issues ordered bugs/fixes first, then quick wins
```
(no `argument-hint`)

- [ ] Follow the Task template above for `triage`.

## Task 13: `work`

**Frontmatter:**
```yaml
description: Work on an issue end-to-end — plan then subagent-driven implementation
argument-hint: <issue number>
```

- [ ] Follow the Task template above for `work`.

---

## Task 14: Update `commands/README.md`

**Files:**
- Modify: `commands/README.md`

**Interfaces:**
- Consumes: the fact that Tasks 2–13 deleted `commands/gh/{done,enrich,enrich-phased,issues,milestone,new,parked,prs,roadmap,route,triage,work}.md` and the equivalent `fj/` files, and created the 12 merged `commands/<concept>.md` files.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the failing check**

```bash
grep -n "Forge routers\|/gh:issues\|/gh:parked\|/gh:triage\|/gh:enrich\|/gh:route\|/gh:work\|/gh:done\|/gh:milestone\|/gh:new ·\|/fj:issues\|/fj:parked\|/fj:triage\|/fj:enrich\|/fj:route\|/fj:work\|/fj:done\|/fj:milestone\|/fj:new ·\|/fj:prs\|/gh:prs" commands/README.md
```

Expected (red): several matches in the "Forge routers", "GitHub", and "Forgejo" sections listing the now-deleted commands.

- [ ] **Step 2: Edit the "Commands" section**

Replace this block:

```markdown
**Forge routers** (auto-detect GitHub vs Forgejo from the `origin` remote, then
delegate to the matching `gh:`/`fj:` command):
`/issues` · `/prs` · `/parked` · `/triage` · `/done` · `/new` · `/enrich` ·
`/enrich-phased` · `/route` · `/work` · `/milestone`
```

with:

```markdown
**Forge-agnostic** (detect GitHub vs Forgejo from the `origin` remote internally):
`/issues` · `/prs` · `/parked` · `/triage` · `/done` · `/new` · `/enrich` ·
`/enrich-phased` · `/route` · `/work` · `/milestone`
```

Replace this block:

```markdown
**GitHub** (`gh/`): `/gh:new` · `/gh:issues` · `/gh:parked` · `/gh:triage` ·
`/gh:enrich` · `/gh:enrich-phased` · `/gh:route` · `/gh:work` · `/gh:assign` ·
`/gh:implement` · `/gh:prs` · `/gh:review` · `/gh:done` · `/gh:milestone`

**Forgejo** (`fj/`): `/fj:new` · `/fj:issues` · `/fj:parked` · `/fj:triage` ·
`/fj:enrich` · `/fj:enrich-phased` · `/fj:route` · `/fj:work` · `/fj:prs` ·
`/fj:done` · `/fj:milestone`
```

with:

```markdown
**GitHub-only** (`gh/`, no Forgejo equivalent): `/gh:assign` · `/gh:implement` ·
`/gh:implementation-contract` · `/gh:review`
```

- [ ] **Step 3: Re-run the check to verify it's clean**

Run the same grep from Step 1. Expected (green): no matches.

- [ ] **Step 4: Lint**

```bash
pre-commit run markdownlint-cli2 --files commands/README.md
```

- [ ] **Step 5: Commit**

```bash
git add commands/README.md
git commit -m "docs(commands): update README for merged forge-agnostic commands

Refs #198, #199"
```

---

## Task 15: Update root `README.md` illustrative examples

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Write the failing check**

```bash
grep -n "fj/    →\|gh/    →\|forge routers)\|\`/fj:work\`\|\`/gh:new\`, \`/fj:new\`" README.md
```

Expected (red): matches at the `commands/` tree diagram (around line 36-44) and the two prose mentions (around lines 60 and 177) identified during design research.

- [ ] **Step 2: Edit the tree diagram**

Find:

```text
commands/
  fj/    → /fj:new  /fj:issues  /fj:triage  /fj:enrich  /fj:work  /fj:prs  /fj:milestone  …
  gh/    → /gh:new  /gh:issues  /gh:assign  /gh:implement  /gh:review  /gh:milestone  …
  wt/    → /wt:status  /wt:finish
  *.md   → /handoff  /pickup  /todo  /wrap-up  /loose-ends  /clear-check
           /issues  /prs  /triage  /route  /work  /milestone  (forge routers)
           /capture-idea  /commands  /update-commands
```

Replace with:

```text
commands/
  gh/    → /gh:assign  /gh:implement  /gh:implementation-contract  /gh:review
  wt/    → /wt:status  /wt:finish
  *.md   → /handoff  /pickup  /todo  /wrap-up  /loose-ends  /clear-check
           /issues  /prs  /triage  /route  /work  /milestone  /new  /enrich
           /enrich-phased  /parked  /roadmap  /done  (forge-agnostic)
           /capture-idea  /commands  /update-commands
```

- [ ] **Step 3: Fix the two prose mentions**

Near line 60, change:
> `/fj:work` works in a non-coding repo (`org`) exactly as it does in a code repo

to:
> `/work` works in a non-coding repo (`org`) exactly as it does in a code repo

Near line 177, change:
> a skill that calls `/gh:new`, `/fj:new` and this repo's `area:*` label conventions

to:
> a skill that calls `/new` and this repo's `area:*` label conventions

- [ ] **Step 4: Re-run the check to verify it's clean**

Run the same grep from Step 1. Expected (green): no matches.

- [ ] **Step 5: Lint**

```bash
pre-commit run markdownlint-cli2 --files README.md
```

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs(readme): update illustrative examples for merged commands

Refs #198, #199"
```

---

## Task 16: Changelog, version bump, full verification

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `VERSION`

**Interfaces:**
- Consumes: the full set of changes from Tasks 1–15.
- Produces: nothing (final task).

- [ ] **Step 1: Write the failing check**

```bash
grep -n "^## \[Unreleased\]" CHANGELOG.md
cat VERSION
```

Expected (red): `VERSION` still reads `1.11.0`; `[Unreleased]` section (if present) has no entry about this change yet.

- [ ] **Step 2: Add the CHANGELOG entry**

At the top of `CHANGELOG.md`, under a `## [Unreleased]` heading (add one if it doesn't exist, directly under the file's intro paragraph and above the `## [1.11.0]` entry), add:

```markdown
## [Unreleased]

### Removed

- **commands:** Remove `/gh:done` `/gh:enrich` `/gh:enrich-phased` `/gh:issues`
  `/gh:milestone` `/gh:new` `/gh:parked` `/gh:prs` `/gh:roadmap` `/gh:route`
  `/gh:triage` `/gh:work` and their `/fj:*` equivalents — merged into the
  forge-agnostic `/done` `/enrich` `/enrich-phased` `/issues` `/milestone`
  `/new` `/parked` `/prs` `/roadmap` `/route` `/triage` `/work` commands.
  **BREAKING CHANGE:** anyone invoking a `gh:x`/`fj:x` name directly for one of
  these 12 concepts must switch to the prefix-less command; re-run
  `setup/link-commands.sh` to pick up the change (#198, #199).

### Changed

- **commands:** Extract the duplicated forge host-detection snippet into
  `scripts/lib/detect-forge.sh`, sourced by the 12 merged commands above (#198,
  #199).
```

- [ ] **Step 3: Bump `VERSION`**

```bash
echo "2.0.0" > VERSION
```

(Major bump — `BREAKING CHANGE` per this repo's Conventional-Commits-to-SemVer mapping.)

- [ ] **Step 4: Re-run the check to verify it's green**

```bash
head -5 CHANGELOG.md   # shows the new [Unreleased] > Removed/Changed entries
cat VERSION            # shows 2.0.0
```

- [ ] **Step 5: Full verification sweep**

```bash
bash tests/run-script-tests.sh
bash tests/run-detect-forge-tests.sh
pre-commit run --all-files
```

Expected: all three exit 0. If `pre-commit run --all-files` flags unrelated pre-existing issues outside files this plan touched, do not fix them here — note them for a separate follow-up and confirm the diff this plan produced is clean.

- [ ] **Step 6: Manual smoke check**

From this repo (a real GitHub remote), run each of the 12 merged commands once (e.g. `/issues`, `/prs`, `/done`, `/triage`) and confirm the output matches what `/gh:issues` etc. produced before the merge (per the design's success criterion 3). This step is manual — record the outcome in the PR description, don't skip it.

- [ ] **Step 7: Commit**

```bash
git add CHANGELOG.md VERSION
git commit -m "chore(release): bump VERSION to 2.0.0 for gh/fj command merge

BREAKING CHANGE: /gh:x and /fj:x commands for done, enrich, enrich-phased,
issues, milestone, new, parked, prs, roadmap, route, triage, and work are
removed, replaced by their prefix-less forge-agnostic equivalents.

Refs #198, #199"
```

---

## Self-Review Notes

- **Spec coverage:** Non-goals (no adapter unification, no behavior change, gh-only commands untouched, no deprecation shim) are honored by the template's "verbatim except renames" rule and Tasks 2–13's scope. Design's file layout (Task 1), testing approach (Tasks 1's fixtures + Tasks 2–13's grep/lint substitute-verification), docs updates (Tasks 14–15), and rollout steps (single PR, Task 16's version bump) are each covered by a task. Success criteria 1–6 map to Tasks 2–13 (criterion 1), Task 1 (criterion 2), Task 16 Step 6 (criterion 3), Tasks 14–16 (criterion 4), issue #204's stats table update (criterion 5 — a follow-up comment on #204 after this PR merges, not a task here since it's bookkeeping on a different issue), and Task 16 Step 5 (criterion 6).
- **Placeholder scan:** No TBD/TODO. The "copy body verbatim" instructions reference exact existing file paths and are mechanical, not vague — the alternative (reproducing ~18KB of existing file content 24 times in this plan) would be pure duplication with no added precision.
- **Type consistency:** N/A — no functions/types beyond `detect_forge()`, used consistently across Task 1 (defines) and the Task template (consumes, conceptually, since command files are prompts not scripts).
