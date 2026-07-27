# Implementation Plan: exclude `roadmap`-labeled issues from `/issues`

**Issue:** [#173](https://github.com/freaxnx01/agent-workflow/issues/173)
**Spec:** [`docs/superpowers/specs/2026-07-27-roadmap-label-filter-design.md`](../specs/2026-07-27-roadmap-label-filter-design.md)
**Date:** 2026-07-27

---

## Constraints — read before starting

- **The label is bare lowercase `roadmap`.** Verified against
  `anim-bossinfo-ch/BI-ArchiveUploader`, where it reads
  `roadmap | Planned for future work, not yet scheduled to a milestone | #0e8a16`.
  It does **not** carry an emoji prefix — unlike `🧊 parked`. Writing `📍 roadmap`
  or `Roadmap` produces a filter that never matches and still passes a naive
  string-presence check. Use the exact string `roadmap` everywhere.
- **There is no automated validation of command `.md` files in this repo.**
  `just lint` runs `actionlint` + `shellcheck` over `.github/workflows/`,
  `scripts/`, and `tests/` only; nothing parses command front-matter and nothing
  executes the bash inside `commands/**/*.md`. **Do not add a test framework, a
  fixture, or a `tests/` entry for these files.** Each task's verification is the
  concrete shell check written into its steps.
- **No live-forge calls from a task step.** This plan is executed by the
  agent-workflow in CI, which has no `tea` login and no access to the private
  BI-ArchiveUploader repo. Running `/gh:issues` against a real repo lives in the
  **Manual verification** section at the end.
- **The Forgejo flag is `--labels` (plural), verified — not guessed.** #172 shipped
  an entirely unverified `/fj:milestone` surface because `tea` wasn't installed;
  `commands/fj/issues.md:27` carries an older scar from the same class of mistake
  (`--description`, not `--body`). `tea` 0.14.1 was installed while writing this
  plan and `tea issues list --help` confirms `--labels string, -L string` —
  comma-separated, plural. Do not "correct" it to `--label`.
- **Every verification check must print on both paths.** A bare
  `grep -q … && echo OK` is silent when it fails, and a `grep -c` returning `0`
  *exits* `1` — both read as an ambiguous or falsely-failed step in CI. Write every
  check as `… && echo "… OK" || echo "FAIL: …"`. (#172's plan was amended for
  exactly this — see `a6f7c75`.)
- **Do not use `git diff … main` in a verification step.** In an `actions/checkout`
  CI clone `main` is frequently not a local ref, so the command errors with
  *unknown revision* instead of failing the assertion. Scope violations are checked
  by asserting on **file content**, which works in any checkout.
- **Do not create the `roadmap` label in this repo.** Both filters are
  label-*absence* checks and are inert no-ops where the label doesn't exist. That
  inertness is an acceptance criterion, not a bug.
- **Two independent filter steps, not one merged list.** Mirror the existing
  `🧊 parked` idiom character-for-character and place the new step immediately
  after it. Do not collapse both into a single `["🧊 parked","roadmap"]` test —
  #174/#175 may give the two states different handling.
- **No GraphQL query change.** `labels(first:20){nodes{name}}` is already selected
  in `commands/gh/issues.md`; only the `--jq` post-filter changes.
- **Do not touch** `commands/gh/triage.md`, `commands/gh/parked.md`,
  `commands/fj/parked.md`, `commands/route.md`, `commands/done.md`, anything under
  `.github/workflows/`, or `setup/link-commands.sh`.
- **Do not touch the `author` column** on line 37 of `commands/gh/issues.md` /
  line 62 of `commands/fj/issues.md`, or any other adjacent prose the acceptance
  criteria do not name.
- **Preserve the self-improving footer** at the end of `commands/fj/issues.md` and
  `commands/issues.md`, and leave `commands/fj/issues.md`'s "Forgejo access"
  section (lines 11–28) untouched.
- Reference `#173` in every commit message; use Conventional Commits
  (`feat(commands): …`, `docs: …`).

## Verification checks are pre-validated

Every check below was dry-run against sandbox copies of the two command files —
once **before** the edits (to confirm each check fails loudly rather than going
silent) and once **after** (to confirm it passes), plus deliberately corrupted
copies to confirm it still catches a capitalised label, an emoji-prefixed label,
and a dropped footer. Two checks were wrong on the first pass and are fixed here:
a bare `Roadmap` regex that hit the legitimate sentence-initial "Roadmap issues
are planned for…", and a `tail -4` footer grep that missed because the footer
sentence wraps across lines. **If a check fails, suspect the edit before you
suspect the check.**

## File Structure

| File | Responsibility |
|---|---|
| `commands/gh/issues.md` | **Modify.** Add the jq roadmap filter step; update front-matter `description:`, opening prose, and the approach paragraph. |
| `commands/fj/issues.md` | **Modify.** Extend the python `continue` guard; update front-matter `description:`, opening prose, and the step-2 comment. |
| `commands/issues.md` | **Modify.** Front-matter `description:` only — the router holds no query logic. |
| `CHANGELOG.md` | **Modify.** `[Unreleased]` → `### Changed`. |

---

### Task 1: GitHub — roadmap filter in `/gh:issues`

**Files:**
- Modify: `commands/gh/issues.md`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the roadmap-exclusion contract that Task 2 mirrors on Forgejo and Task 3
  describes in the router's `description:`.

- [ ] **Step 1: Front-matter `description:` (line 2)**

Replace:

```yaml
description: List open issues that are not WIP (no open PR) and not parked, newest first
```

with:

```yaml
description: List open issues that are not WIP (no open PR), not parked, and not roadmap, newest first
```

- [ ] **Step 2: Opening prose (line 5)**

Replace the paragraph:

```markdown
List open issues in the current repo that are **not work-in-progress** — i.e. have no **open** PR — and **not parked** (no `🧊 parked` label) — **newest first**. Issues whose only linked PR is already merged still count as not-WIP and are shown. Parked issues are deliberately deferred; list them with `/gh:parked`.
```

with:

```markdown
List open issues in the current repo that are **not work-in-progress** — i.e. have no **open** PR — **not parked** (no `🧊 parked` label), and **not roadmap** (no `roadmap` label) — **newest first**. Issues whose only linked PR is already merged still count as not-WIP and are shown. Parked issues are deliberately deferred; list them with `/gh:parked`. Roadmap issues are planned for a future milestone rather than current work; find them with `gh issue list --label roadmap`.
```

Note: **no `/gh:roadmap` reference** — that command does not exist yet (#175).

- [ ] **Step 3: Approach paragraph (line 7)**

Replace:

```markdown
`gh issue list` can't see PR links, so query the timeline via GraphQL and drop any issue that has an open linked PR (a `Closes #`/cross-reference or a development-linked PR still in flight), then drop any issue carrying the `🧊 parked` label:
```

with:

```markdown
`gh issue list` can't see PR links, so query the timeline via GraphQL and drop any issue that has an open linked PR (a `Closes #`/cross-reference or a development-linked PR still in flight), then drop any issue carrying the `🧊 parked` label, then any carrying the `roadmap` label:
```

- [ ] **Step 4: The jq filter**

In the `--jq` block, after the existing parked line, add one line. The block becomes:

```jq
  --jq '.data.repository.issues.nodes
    | map(select([.timelineItems.nodes[] | (.source // .subject) | .state] | map(select(. == "OPEN")) | length == 0))
    | map(select([.labels.nodes[].name] | index("🧊 parked") | not))
    | map(select([.labels.nodes[].name] | index("roadmap") | not))
    | .[] | {number, title, labels: [.labels.nodes[].name], age: .createdAt, author: .author.login}'
```

The GraphQL query above it is unchanged.

- [ ] **Step 5: Verify**

```bash
f=commands/gh/issues.md

# the new filter line exists, with the exact bare label
grep -Fq 'index("roadmap") | not' "$f" && echo "jq filter OK" || echo "FAIL: jq filter missing"

# it sits after the parked filter, not before
awk '/index\("🧊 parked"\)/{p=NR} /index\("roadmap"\)/{r=NR} END{ if (p && r && r > p) print "filter order OK"; else print "FAIL: order parked=" p+0 " roadmap=" r+0 }' "$f"

# no emoji-prefixed or capitalised variant crept in.
# Match quoted/backticked label positions only — bare `Roadmap` would also hit the
# legitimate sentence-initial "Roadmap issues are planned for…" added in Step 2.
grep -Eq '📍 ?roadmap|"Roadmap"|`Roadmap`' "$f" && echo "FAIL: wrong label variant" || echo "label string OK"

# all three prose surfaces mention roadmap
sed -n '2p' "$f" | grep -q 'roadmap' && echo "front-matter OK" || echo "FAIL: front-matter"
grep -Fq 'gh issue list --label roadmap' "$f" && echo "escape hatch OK" || echo "FAIL: no escape hatch"
grep -q '/gh:roadmap' "$f" && echo "FAIL: references a command that does not exist" || echo "no phantom command OK"

# the GraphQL query is untouched
grep -Fq 'timelineItems(itemTypes:[CROSS_REFERENCED_EVENT,CONNECTED_EVENT], first:50)' "$f" && echo "query intact OK" || echo "FAIL: query altered"
```

Expected: seven `OK` lines, no `FAIL`.

- [ ] **Step 6: Commit**

```bash
git add commands/gh/issues.md
git commit -m "feat(commands): exclude roadmap-labeled issues from /gh:issues (#173)"
```

---

### Task 2: Forgejo — roadmap filter in `/fj:issues`

**Files:**
- Modify: `commands/fj/issues.md`

**Interfaces:**
- Consumes: the roadmap-exclusion contract established in Task 1 — same label
  string, same "not current work" framing.
- Produces: forge parity, which Task 3's router `description:` then claims.

- [ ] **Step 1: Front-matter `description:` (line 2)**

Replace:

```yaml
description: List open Forgejo issues that are not WIP (no open PR) and not parked, newest first
```

with:

```yaml
description: List open Forgejo issues that are not WIP (no open PR), not parked, and not roadmap, newest first
```

- [ ] **Step 2: Opening prose (lines 5–9)**

Replace:

```markdown
List open issues in the current Forgejo repo that are **not work-in-progress** —
i.e. have no **open** linked PR — and **not parked** (no `🧊 parked` label) —
**newest first**. Issues whose only linked PR is already merged/closed still count
as not-WIP and are shown. Parked issues are deliberately deferred; list them with
`/fj:parked`.
```

with:

```markdown
List open issues in the current Forgejo repo that are **not work-in-progress** —
i.e. have no **open** linked PR — **not parked** (no `🧊 parked` label), and **not
roadmap** (no `roadmap` label) — **newest first**. Issues whose only linked PR is
already merged/closed still count as not-WIP and are shown. Parked issues are
deliberately deferred; list them with `/fj:parked`. Roadmap issues are planned for
a future milestone rather than current work; find them with
`tea issues list --login git-home --labels roadmap`.
```

**`--labels` is plural** — verified against `tea issues list --help` (tea 0.14.1):
`--labels string, -L string   Comma-separated list of labels to match issues
against.` `--login git-home` matches this file's existing convention.

- [ ] **Step 3: Approach sentence (line 35) and step-2 comment (line 51)**

Line 35 — replace `Then drop parked issues.` with
`Then drop parked and roadmap issues.`

Line 51 — replace:

```python
# 2) open issues, newest first, minus WIP, minus parked
```

with:

```python
# 2) open issues, newest first, minus WIP, minus parked, minus roadmap
```

- [ ] **Step 4: The python filter (line 58)**

Replace:

```python
    if i["number"] in wip or "🧊 parked" in labels: continue
```

with:

```python
    if i["number"] in wip or "🧊 parked" in labels or "roadmap" in labels: continue
```

Everything else in the python block — including the `labels` list comprehension on
the line above — is unchanged.

- [ ] **Step 5: Verify**

```bash
f=commands/fj/issues.md

# the guard now covers roadmap, on the same line as the parked check
grep -Fq 'if i["number"] in wip or "🧊 parked" in labels or "roadmap" in labels: continue' "$f" \
  && echo "python guard OK" || echo "FAIL: guard not extended"

# exact bare label, no variants (quoted/backticked positions only — see Task 1)
grep -Eq '📍 ?roadmap|"Roadmap"|`Roadmap`' "$f" && echo "FAIL: wrong label variant" || echo "label string OK"

# prose surfaces
sed -n '2p' "$f" | grep -q 'roadmap' && echo "front-matter OK" || echo "FAIL: front-matter"
grep -Fq 'tea issues list --login git-home --labels roadmap' "$f" && echo "escape hatch OK" || echo "FAIL: no escape hatch"
grep -q '/fj:roadmap' "$f" && echo "FAIL: references a command that does not exist" || echo "no phantom command OK"

# the plural flag survived — --label singular does not exist in tea 0.14.1
grep -Eq '\-\-label[^s]' "$f" && echo "FAIL: singular --label, must be --labels" || echo "plural flag OK"

# untouched regions: Forgejo access section and the self-improving footer
grep -Fq 'tea api --login git-home' "$f" && echo "tea access intact OK" || echo "FAIL: tea access section"
# `tail -5`, and match without the trailing word — the footer sentence wraps, so
# "update this command for the future" never appears on a single line.
tail -5 "$f" | grep -q 'update this command for the' && echo "footer intact OK" || echo "FAIL: footer lost"

# the edited guard is still valid python
python3 - <<'PY' && echo "python parses OK" || echo "FAIL: python syntax"
src = '''
wip=set()
for i in []:
    labels=[l["name"] for l in i.get("labels") or []]
    if i["number"] in wip or "\U0001f9ca parked" in labels or "roadmap" in labels: continue
'''
compile(src, "guard", "exec")
PY
```

Expected: nine `OK` lines, no `FAIL`.

- [ ] **Step 6: Commit**

```bash
git add commands/fj/issues.md
git commit -m "feat(commands): exclude roadmap-labeled issues from /fj:issues (#173)"
```

---

### Task 3: Router description and changelog

**Files:**
- Modify: `commands/issues.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: Tasks 1 and 2 — the router only *describes* behaviour that now exists
  on both forges. Do not add query logic here.
- Produces: nothing downstream.

- [ ] **Step 1: Router front-matter (`commands/issues.md` line 2)**

Replace:

```yaml
description: List open issues (not WIP, not parked) — auto-routes to GitHub or Forgejo by remote
```

with:

```yaml
description: List open issues (not WIP, not parked, not roadmap) — auto-routes to GitHub or Forgejo by remote
```

**Nothing else in `commands/issues.md` changes** — the host-detection snippet, the
delegation bullets, and the footer all stay exactly as they are.

- [ ] **Step 2: Changelog**

Under `## [Unreleased]`, add a `### Changed` section immediately after the existing
`### Added` block (keep `### Added` and its two `#172` entries intact):

```markdown
### Changed

- **commands:** `/gh:issues` and `/fj:issues` now also exclude issues labeled
  `roadmap` (planned for a future milestone, not current work), alongside the
  existing `🧊 parked` exclusion (#173)
```

- [ ] **Step 3: Verify**

```bash
# router description updated, logic untouched
sed -n '2p' commands/issues.md | grep -q 'not roadmap' && echo "router description OK" || echo "FAIL: router description"
grep -Fq 'This command holds no query logic of its own' commands/issues.md && echo "router logic intact OK" || echo "FAIL: router prose"
grep -q 'index("roadmap")' commands/issues.md && echo "FAIL: query logic leaked into router" || echo "no logic leaked into router OK"

# changelog entry under Unreleased → Changed, referencing #173.
# Track the two markers separately — the entry wraps, so `roadmap` and `#173`
# land on different lines and a same-line match would never fire.
awk '/^## \[Unreleased\]/{u=1} /^## \[1\./{u=0} u && /^### Changed/{c=1} u && c && /roadmap/{r=1} u && c && /#173/{n=1} END{ if (r && n) print "changelog OK"; else print "FAIL: changelog roadmap=" (r?1:0) " ref173=" (n?1:0) }' CHANGELOG.md

# #172 entries survived
grep -Fq '/milestone` (+ `/gh:milestone`, `/fj:milestone`)' CHANGELOG.md \
  && echo "prior entries intact OK" || echo "FAIL: clobbered #172 entries"

# out-of-scope files carry no roadmap logic (AC 6).
# Asserted on CONTENT, not `git diff … main` — in an actions/checkout clone `main`
# is often not a local ref, so a diff-based check errors out instead of failing.
for x in commands/gh/triage.md commands/gh/parked.md commands/fj/parked.md; do
  grep -q 'roadmap' "$x" && echo "FAIL: roadmap leaked into $x" || echo "untouched OK: $x"
done
grep -rq 'roadmap' .github/ && echo "FAIL: roadmap reached .github/" || echo "workflows untouched OK"
```

Expected: nine `OK` lines, no `FAIL`.

- [ ] **Step 4: Commit**

```bash
git add commands/issues.md CHANGELOG.md
git commit -m "docs: note roadmap exclusion in /issues router and changelog (#173)"
```

---

## Manual verification (human, after merge)

Not task steps — these need a real forge and a local install.

1. Reinstall commands (`setup/link-commands.sh`), then run `/gh:issues` inside
   `anim-bossinfo-ch/BI-ArchiveUploader`. Issue **#164**
   (`needs-enrichment | roadmap`) must **not** appear. Confirm it is still findable
   with `gh issue list --label roadmap`.
2. Run `/gh:issues` in `freaxnx01/agent-workflow`, which has **no** `roadmap`
   label. Output must be identical to before the change — this proves the filter is
   inert rather than over-matching.
3. Run `/fj:issues` against a Forgejo repo to confirm the python edit did not break
   the existing WIP/parked pipeline.
4. Confirm `/` autocomplete shows the updated descriptions for `/issues`,
   `/gh:issues`, and `/fj:issues`.
