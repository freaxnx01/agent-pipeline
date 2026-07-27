# Implementation Plan: `/milestone triage`

**Issue:** [#178](https://github.com/freaxnx01/agent-workflow/issues/178)
**Spec:** [`docs/superpowers/specs/2026-07-27-milestone-triage-design.md`](../specs/2026-07-27-milestone-triage-design.md)
**Date:** 2026-07-27

---

## Constraints — read before starting

- **This adds a fourth verb to an existing command.** Do not create a new
  top-level command file. `triage` joins `list` / `new` / `assign` in all three
  milestone files.
- **#172's "three verbs only" constraint is deliberately superseded** for `triage`
  and *only* for `triage`. Still do **not** add `unassign`, `close`, `reopen`,
  `delete`, or `edit`.
- **The three existing verbs must come out behaviourally unchanged.** Their query
  blocks, read-back rules, and truncation guard are not to be edited — `triage` is
  additive.
- **Preserve the two rules that apply to every verb** (`commands/gh/milestone.md:26`,
  `commands/fj/milestone.md:26`), especially read-back-not-exit-code. `triage`
  inherits them; do not restate them inside the new section.
- **`tea api` has no `--jq`** — pipe into `python3 -c`, the idiom already used
  throughout `commands/fj/*`. `gh` uses its built-in `--jq`.
- **`tea` is always invoked with `--login git-home`.**
- **There is no automated validation of command `.md` files in this repo.**
  `just lint` covers only `.github/workflows/`, `scripts/`, and `tests/`. **Do not
  add a test framework, a fixture, or a `tests/` entry.**
- **Every verification check must print on both paths** — `… && echo "… OK" ||
  echo "FAIL: …"`. A bare `grep -q … && echo OK` is silent on failure and a
  `grep -c` returning `0` *exits* `1`. (See `a6f7c75`.)
- **Do not use `git diff … main`** in a check — `main` is often not a local ref in
  an `actions/checkout` clone. Assert on file content.
- **No live-forge writes from a task step.** This plan runs in CI. Assigning a real
  milestone is manual verification.
- Reference `#178` in every commit; Conventional Commits.

## The GitHub query is pre-validated

Run against `freaxnx01/agent-workflow` on 2026-07-27: 26 open issues have no
milestone, the 6 in milestone `next` are correctly absent, and the `🧊 parked`
filter removes exactly the 1 parked issue (26 → 25). Two details that were wrong on
the first attempt and are already fixed below:

- `([.labels[].name] | join(",")) // "-"` does **not** produce `-` for an unlabelled
  issue — jq treats `""` as truthy, so `//` never fires. Use
  `| if . == "" then "-" else . end`.
- `.milestone` must be tested with `== null`, not truthiness.

## File Structure

| File | Responsibility |
|---|---|
| `commands/gh/milestone.md` | **Modify.** Add the `triage` verb — `gh` query + walk. |
| `commands/fj/milestone.md` | **Modify.** Same via `tea api` + `python3`. |
| `commands/milestone.md` | **Modify.** Router — verb list and usage forms only, no logic. |
| `CHANGELOG.md` | **Modify.** `[Unreleased]` → `### Added`. |

---

### Task 1: GitHub — `/gh:milestone triage`

**Files:**
- Modify: `commands/gh/milestone.md`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the verb contract and interaction rules Tasks 2 and 3 mirror.

- [ ] **Step 1: Front-matter**

Add `triage` to both lines:

```yaml
description: List, create, assign, or triage GitHub milestones — list | new <name> [due <date>] | assign <issue> to <name> | triage
argument-hint: list | new <name> [due <date>] | assign <issue> to <name> | triage
```

- [ ] **Step 2: Register the verb**

In `## Parse the verb`, add `triage` to the recognised set. Bare invocation still
means `list`; an unrecognised first word still prints the usage forms and stops.

- [ ] **Step 3: Add the `## triage` section**

After `## assign`, before `## No forge context`:

````markdown
## triage

Open issues with **no milestone** — the gap `list` deliberately doesn't show.
Two phases: show the whole gap first, then walk it one issue at a time.

Excludes `🧊 parked` (paused on purpose) and `roadmap` (*planned for future work,
not yet scheduled to a milestone* — being un-milestoned is its whole meaning, so
nagging about it is noise). Pull requests are excluded by `gh issue list`.

**Phase 1 — show the gap.** Newest first:

```bash
gh issue list --state open --limit 200 --json number,title,labels,milestone,createdAt \
  --jq 'map(select(.milestone == null))
    | map(select([.labels[].name] | index("🧊 parked") | not))
    | map(select([.labels[].name] | index("roadmap") | not))
    | sort_by(.createdAt) | reverse
    | .[] | [.number, .title, (([.labels[].name] | join(",")) | if . == "" then "-" else . end)] | @tsv'
```

Print the count with the list. **Truncation guard:** the query caps at 200 — if that
many came back, say the list may be incomplete rather than implying it's the whole
gap. If nothing came back, say the gap is empty and **stop — do not enter the walk.**

**Phase 2 — walk it.** Fetch the open milestones **once**, before the walk:

```bash
gh api "repos/$repo/milestones?state=open&sort=due_on&direction=asc&per_page=100" \
  --jq '.[] | [.title, (.due_on // "-")] | @tsv'
```

Then, for each issue newest first: show number, title, labels; offer the milestone
titles plus `skip`; on an answer, assign and **read back**:

```bash
gh issue edit <issue> --milestone "<name>"
gh issue view <issue> --json number,milestone --jq '[.number, (.milestone.title // "-")] | @tsv'
```

Report from the read-back, never from the exit code.

Rules for the walk:

- **One issue at a time.** No bulk-assign, no "apply to the rest".
- **`skip` is always offered**, and skipping is silent — don't re-prompt.
- **Never assign without an explicit answer.** No default milestone, no inferring
  from labels or title. Unanswered means skipped.
- **Never create a milestone.** An unknown name → print the open milestones and
  stop; point at `/milestone new`. No fuzzy matching, no silent creation.
- **Stop cleanly** when told to, and report how many were assigned and how many
  remain.
````

- [ ] **Step 4: Verify**

```bash
f=commands/gh/milestone.md
sed -n '1,4p' "$f" | grep -q 'triage' && echo "front-matter OK" || echo "FAIL: front-matter"
grep -q '^## triage' "$f" && echo "section OK" || echo "FAIL: no section"
grep -Fq 'select(.milestone == null)' "$f" && echo "gap query OK" || echo "FAIL: gap query"
grep -Fq 'if . == "" then "-" else . end' "$f" && echo "label fallback OK" || echo "FAIL: label fallback"
grep -Fq 'index("🧊 parked") | not' "$f" && echo "parked excluded OK" || echo "FAIL: parked"
grep -Fq 'index("roadmap") | not' "$f" && echo "roadmap excluded OK" || echo "FAIL: roadmap"
grep -Fq 'do not enter the walk' "$f" && echo "empty-gap stop OK" || echo "FAIL: empty-gap"
grep -Fq 'Never create a milestone' "$f" && echo "no-create rule OK" || echo "FAIL: no-create"
grep -Fq 'gh issue view <issue> --json number,milestone' "$f" && echo "read-back OK" || echo "FAIL: read-back"

# existing verbs untouched
for v in '^## list' '^## new' '^## assign'; do
  grep -q "$v" "$f" && echo "verb intact OK: $v" || echo "FAIL: lost $v"
done
grep -Fq '`open_issues` counts issues' "$f" && echo "list truncation guard intact OK" || echo "FAIL: list guard lost"
```

Expected: thirteen `OK` lines.

- [ ] **Step 5: Commit**

```bash
git add commands/gh/milestone.md
git commit -m "feat(commands): add /gh:milestone triage for un-milestoned issues (#178)"
```

---

### Task 2: Forgejo — `/fj:milestone triage`

**Files:**
- Modify: `commands/fj/milestone.md`

**Interfaces:**
- Consumes: Task 1's verb contract and interaction rules — same wording, Forgejo
  mechanics.

- [ ] **Step 1: Front-matter and verb registration**

Same as Task 1 Steps 1–2, with "Forgejo" in the description.

- [ ] **Step 2: Add the `## triage` section**

Same two phases and the same six walk rules. Forgejo mechanics:

````markdown
```bash
tea api --login git-home "repos/$repo/issues?state=open&type=issues&limit=100&sort=created&order=desc" \
  | python3 -c '
import sys,json
rows=[]
for i in json.load(sys.stdin):
    if i.get("milestone"): continue
    labels=[l["name"] for l in i.get("labels") or []]
    if "🧊 parked" in labels or "roadmap" in labels: continue
    rows.append((i["number"], i["title"], ",".join(labels) or "-"))
print(len(rows), "un-milestoned")
for n,t,l in rows: print(n, "|", t, "|", l)'
```
````

`type=issues` excludes pull requests. Assignment and read-back reuse the existing
`## assign` mechanics in this file — do not invent a second path.

- [ ] **Step 3: Verify**

```bash
f=commands/fj/milestone.md
sed -n '1,4p' "$f" | grep -q 'triage' && echo "front-matter OK" || echo "FAIL: front-matter"
grep -q '^## triage' "$f" && echo "section OK" || echo "FAIL: no section"
grep -Fq 'if i.get("milestone"): continue' "$f" && echo "gap filter OK" || echo "FAIL: gap filter"
grep -Fq '"🧊 parked" in labels or "roadmap" in labels' "$f" && echo "exclusions OK" || echo "FAIL: exclusions"
grep -Fq 'type=issues' "$f" && echo "PRs excluded OK" || echo "FAIL: PR exclusion"
grep -Fq 'tea api --login git-home' "$f" && echo "login convention OK" || echo "FAIL: login"
grep -Fq 'Never create a milestone' "$f" && echo "no-create rule OK" || echo "FAIL: no-create"

# the new python parses
python3 - <<'PY' && echo "python parses OK" || echo "FAIL: python syntax"
src = '''
import sys,json
rows=[]
for i in []:
    if i.get("milestone"): continue
    labels=[l["name"] for l in i.get("labels") or []]
    if "\U0001f9ca parked" in labels or "roadmap" in labels: continue
    rows.append((i["number"], i["title"], ",".join(labels) or "-"))
'''
compile(src, "triage", "exec")
PY

for v in '^## list' '^## new' '^## assign'; do
  grep -q "$v" "$f" && echo "verb intact OK: $v" || echo "FAIL: lost $v"
done
```

Expected: eleven `OK` lines.

- [ ] **Step 4: Commit**

```bash
git add commands/fj/milestone.md
git commit -m "feat(commands): add /fj:milestone triage for un-milestoned issues (#178)"
```

---

### Task 3: Router

**Files:**
- Modify: `commands/milestone.md`

**Interfaces:**
- Consumes: Tasks 1 and 2 — the router only names the verb. **No query logic here.**

- [ ] **Step 1: Front-matter and verb list**

```yaml
description: List, create, assign, or triage milestones — auto-routes to GitHub or Forgejo by remote
argument-hint: list | new <name> [due <date>] | assign <issue> to <name> | triage
```

Then, in the body, add `triage` to the sentence naming the verbs the target command
takes. The host-detection snippet, the delegation bullets, and the footer are
unchanged.

- [ ] **Step 2: Verify**

```bash
f=commands/milestone.md
sed -n '1,4p' "$f" | grep -q 'triage' && echo "front-matter OK" || echo "FAIL: front-matter"
grep -q 'triage' "$f" && echo "verb named OK" || echo "FAIL: verb missing"
grep -Fq 'select(.milestone == null)' "$f" && echo "FAIL: query logic leaked into router" || echo "no logic in router OK"
grep -Fq 'gh auth token --hostname' "$f" && echo "detection intact OK" || echo "FAIL: detection lost"
```

Expected: four `OK` lines.

- [ ] **Step 3: Commit**

```bash
git add commands/milestone.md
git commit -m "feat(commands): route /milestone triage to both forges (#178)"
```

---

### Task 4: Changelog

- [ ] **Step 1:** Under `## [Unreleased]` → `### Added`:

```markdown
- **commands:** `/milestone triage` (+ `/gh:milestone`, `/fj:milestone`) — lists
  open issues with no milestone, excluding `🧊 parked` and `roadmap`, then walks
  them one at a time to assign one, every write confirmed by read-back (#178)
```

- [ ] **Step 2: Verify**

```bash
awk '/^## \[Unreleased\]/{u=1} /^## \[1\./{u=0} u && /^### Added/{a=1} u && a && /triage/{r=1} u && a && /#178/{n=1} END{ if (r && n) print "changelog OK"; else print "FAIL: changelog triage=" (r?1:0) " ref178=" (n?1:0) }' CHANGELOG.md
grep -Fq '/milestone` (+ `/gh:milestone`, `/fj:milestone`)' CHANGELOG.md && echo "prior entries intact OK" || echo "FAIL: clobbered earlier entries"
```

Expected: two `OK` lines.

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for /milestone triage (#178)"
```

---

## Manual verification (human, after merge)

[ ] **1.** Re-run `setup/link-commands.sh`, then `/milestone triage` in
`freaxnx01/agent-workflow`. As of 2026-07-27 expect ~25 un-milestoned issues, with
the 6 in `next` absent and the 1 `🧊 parked` issue absent.

[ ] **2.** Skip an issue — confirm it stays un-milestoned and isn't re-prompted.

[ ] **3.** Assign one, confirm the reported result comes from the read-back, then
re-run `triage` and confirm that issue is gone from the gap list.

[ ] **4.** Answer with a milestone name that doesn't exist — confirm the command
prints the open milestones and stops rather than creating it.

[ ] **5.** Run `/fj:milestone triage` against a Forgejo repo (`tea` 0.14.1 is
installed locally; the `git-home` login is still required).
