# Implementation Plan: `/roadmap`

**Issue:** [#175](https://github.com/freaxnx01/agent-workflow/issues/175)
**Spec:** [`docs/superpowers/specs/2026-07-27-roadmap-command-design.md`](../specs/2026-07-27-roadmap-command-design.md)
**Date:** 2026-07-27

---

## Constraints — read before starting

- **Merge #173 first.** Task 4 replaces a sentence that #173 adds to
  `commands/gh/issues.md` and `commands/fj/issues.md`. If that sentence isn't
  present, **say so and skip Task 4** — do not invent the surrounding prose.
- **Do not merge this with `/parked`.** #174 and #175 were deliberately kept as two
  commands. Duplication between `commands/gh/roadmap.md` and
  `commands/gh/parked.md` is accepted; do not extract a shared abstraction.
- **Never create the `roadmap` label**, and never add it to an issue. `list` in a
  repo without the label reports an empty roadmap — that is correct behaviour, not
  an error to fix.
- **`promote` assigns the milestone first, then removes the label.** If the
  assignment fails, stop without touching the label — a scheduled-but-hidden issue
  is bad, an unscheduled-and-hidden one is merely the status quo.
- **Offer `/route` after promote, don't run it.** Unlike `/parked unpark`,
  promotion doesn't imply work starts now.
- **Every write reported from a read-back, never the exit code.**
- **The label is bare lowercase `roadmap`** — no emoji prefix, unlike `🧊 parked`.
  Verified in `anim-bossinfo-ch/BI-ArchiveUploader`:
  `roadmap | Planned for future work, not yet scheduled to a milestone | #0e8a16`.
- **`tea api` has no `--jq`** — pipe into `python3 -c`. **`tea` is always invoked
  with `--login git-home`.** `tea` 0.14.1 is installed locally: **verify every flag
  with `tea <subcommand> --help`** rather than writing it from memory.
- **Forgejo: filter labels client-side** — the `labels=` query param is broken on
  this Forgejo (`commands/fj/parked.md:35`).
- **There is no automated validation of command `.md` files in this repo.** **Do not
  add a test framework, a fixture, or a `tests/` entry.**
- **Every verification check must print on both paths** — `… && echo "… OK" ||
  echo "FAIL: …"`. **Do not use `git diff … main`** — assert on file content.
- **No live-forge writes from a task step.**
- Reference `#175` in every commit; Conventional Commits.

## The queries are pre-validated

Run on 2026-07-27:

- In `freaxnx01/agent-workflow` (**no** `roadmap` label): the list query returns
  empty output and **exit 0** — the empty-roadmap path needs no special-casing.
- In `anim-bossinfo-ch/BI-ArchiveUploader` (label present): returns issue **#164**
  with `—` for the reason, as designed.

## File Structure

| File | Responsibility |
|---|---|
| `commands/gh/roadmap.md` | **Create.** `list` / `promote` / `defer` via `gh` + GraphQL. |
| `commands/fj/roadmap.md` | **Create.** Same via `tea api` + `python3`. |
| `commands/roadmap.md` | **Create.** Forge router — detection snippet copied verbatim from `commands/parked.md`, no logic. |
| `commands/gh/issues.md` | **Modify.** Replace #173's placeholder escape-hatch sentence. |
| `commands/fj/issues.md` | **Modify.** Same. |
| `CHANGELOG.md` | **Modify.** `[Unreleased]` → `### Added`. |

---

### Task 1: GitHub — `/gh:roadmap`

**Files:**
- Create: `commands/gh/roadmap.md`

**Interfaces:**
- Consumes: nothing. Mirrors `commands/gh/parked.md`'s structure.
- Produces: the verb contract Tasks 2 and 3 mirror, and the command name Task 4
  points at.

- [ ] **Step 1: Front-matter**

```yaml
description: List and promote roadmap issues — list | promote <n> to <milestone> | defer <n> "<reason>"
argument-hint: list | promote <n> to <milestone> | defer <n> "<reason>"
```

- [ ] **Step 2: Parse the verb**

No arguments → `list`. A first word that is not `list` / `promote` / `defer` →
print the three usage forms and stop without guessing.

- [ ] **Step 3: `list`**

```bash
gh api graphql \
  -f owner="$(gh repo view --json owner -q .owner.login)" \
  -f name="$(gh repo view --json name -q .name)" \
  -f query='
query($owner:String!,$name:String!){
  repository(owner:$owner,name:$name){
    issues(states:OPEN, first:100, orderBy:{field:CREATED_AT, direction:DESC}){
      nodes{
        number title createdAt
        author{login}
        labels(first:20){nodes{name}}
        comments(last:20){nodes{body}}
      }
    }
  }
}' \
  --jq '.data.repository.issues.nodes
    | map(select([.labels.nodes[].name] | index("roadmap")))
    | .[] | [ .number, .title,
              ([.labels.nodes[].name] | join(",")),
              .createdAt, .author.login,
              ( [ .comments.nodes[].body | select(startswith("roadmap:")) ]
                | last // "—" | split("\n")[0] ) ] | @tsv'
```

Compact table — number, title, labels, age (relative), author, reason. No preamble.

**Empty output is the normal empty-roadmap case**, including in repos that have no
`roadmap` label at all. Say the roadmap is empty and stop. **Do not create the
label.**

- [ ] **Step 4: `promote <n> to <milestone>`**

Two writes, in this order, each followed by a read-back:

```bash
# 1) schedule it
gh issue edit <n> --milestone "<milestone>"
gh issue view <n> --json number,milestone --jq '[.number, (.milestone.title // "-")] | @tsv'

# 2) only if the read-back shows the milestone: stop hiding it
gh issue edit <n> --remove-label "roadmap"
gh issue view <n> --json number,labels --jq '[.number, ([.labels[].name] | join(","))] | @tsv'
```

**If step 1's read-back shows no milestone, stop — do not remove the label.** An
issue that is visible but unscheduled is worse than one that is hidden and
correctly labelled.

If the milestone name doesn't exist, `gh` rejects it: print the open milestones and
stop. **No fuzzy matching, no silent creation** — point at `/milestone new`.

```bash
gh api "repos/$repo/milestones?state=open&sort=due_on&direction=asc&per_page=100" \
  --jq '.[] | [.title, (.due_on // "-")] | @tsv'
```

After both read-backs confirm, **offer** to run `/gh:route <n>` — offer, don't run.

- [ ] **Step 5: `defer <n> "<reason>"`**

```bash
gh issue comment <n> --body "roadmap: <reason>"
gh issue view <n> --json comments --jq '.comments | last | .body | split("\n")[0]'
```

The `roadmap:` prefix is what `list` matches on — required, not decorative. Leave
the label in place. Never edit the issue body, never edit a previous comment. With
no reason argument, ask for one and stop.

- [ ] **Step 6: Self-improving footer**

End the file with a horizontal rule and one sentence telling the command to fix its
own blockers and update itself, matching `commands/fj/issues.md`'s footer shape.

- [ ] **Step 7: Verify**

```bash
f=commands/gh/roadmap.md
test -f "$f" && echo "file exists OK" || echo "FAIL: missing"
sed -n '1,4p' "$f" | grep -q '^description: ' && echo "front-matter OK" || echo "FAIL: front-matter"
sed -n '1,4p' "$f" | grep -q '^argument-hint: ' && echo "argument-hint OK" || echo "FAIL: argument-hint"
for v in list promote defer; do
  grep -q "^## $v" "$f" && echo "verb section OK: $v" || echo "FAIL: no section $v"
done
grep -Fq 'index("roadmap")' "$f" && echo "list filter OK" || echo "FAIL: list filter"
grep -Fq 'startswith("roadmap:")' "$f" && echo "reason prefix OK" || echo "FAIL: reason prefix"
grep -Fq -- '--remove-label "roadmap"' "$f" && echo "promote unlabels OK" || echo "FAIL: promote unlabel"

# bare lowercase label only
grep -Eq '📍 ?roadmap|"Roadmap"|`Roadmap`' "$f" && echo "FAIL: wrong label variant" || echo "label string OK"
# never adds the label, never creates it
grep -Fq -- '--add-label "roadmap"' "$f" && echo "FAIL: adds roadmap label" || echo "never adds label OK"
grep -Fq 'gh label create' "$f" && echo "FAIL: creates the label" || echo "never creates label OK"
# offers route rather than running it
grep -Fq 'offer' "$f" && echo "offers route OK" || echo "FAIL: no offer wording"
tail -4 "$f" | grep -q 'update this command for the' && echo "self-improving footer OK" || echo "FAIL: footer"
```

Expected: fourteen `OK` lines.

- [ ] **Step 8: Commit**

```bash
git add commands/gh/roadmap.md
git commit -m "feat(commands): add /gh:roadmap with list/promote/defer (#175)"
```

---

### Task 2: Forgejo — `/fj:roadmap`

**Files:**
- Create: `commands/fj/roadmap.md`

**Interfaces:**
- Consumes: Task 1's verb contract and rules — same wording, Forgejo mechanics,
  and it offers `/fj:route`, not `/gh:route`.

- [ ] **Step 1: Create the file**

Mirror Task 1, with the Forgejo access preamble copied from
`commands/fj/parked.md` (repo resolution + the `tea api` note). Two calls for
`list` — issues, then comments per roadmap issue:

````markdown
```bash
tea api --login git-home "repos/$repo/issues?state=open&type=issues&limit=100&sort=created&order=desc" \
  | python3 -c '
import sys,json
for i in json.load(sys.stdin):
    labels=[l["name"] for l in i.get("labels") or []]
    if "roadmap" not in labels: continue
    print(i["number"], "|", i["title"], "|", ",".join(labels), "|", i["created_at"], "|", (i.get("user") or {}).get("login","?"))'

tea api --login git-home "repos/$repo/issues/<n>/comments" \
  | python3 -c '
import sys,json
reasons=[c["body"] for c in json.load(sys.stdin) if c.get("body","").startswith("roadmap:")]
print(reasons[-1].split("\n")[0] if reasons else "—")'
```
````

Labels are filtered **client-side** — the `labels=` query param is broken on this
Forgejo. `defer` uses `tea comment <n> "roadmap: <reason>"`. For `promote`, verify
the milestone and label flags with `tea <subcommand> --help` before writing them,
and read back after each write.

- [ ] **Step 2: Verify**

```bash
f=commands/fj/roadmap.md
test -f "$f" && echo "file exists OK" || echo "FAIL: missing"
sed -n '1,4p' "$f" | grep -q '^description: ' && echo "front-matter OK" || echo "FAIL: front-matter"
for v in list promote defer; do
  grep -q "^## $v" "$f" && echo "verb section OK: $v" || echo "FAIL: no section $v"
done
grep -Fq 'startswith("roadmap:")' "$f" && echo "reason prefix OK" || echo "FAIL: reason prefix"
grep -Fq 'tea api --login git-home' "$f" && echo "login convention OK" || echo "FAIL: login"
grep -Fq 'commands/fj/route.md' "$f" && echo "offers fj route OK" || echo "FAIL: route reference"
grep -Fq 'commands/gh/route.md' "$f" && echo "FAIL: cross-forge leak" || echo "no cross-forge leak OK"
grep -Eq '"repos/\$repo/issues\?[^"]*labels=' "$f" && echo "FAIL: broken labels= param" || echo "client-side filter OK"

python3 - <<'PY' && echo "python parses OK" || echo "FAIL: python syntax"
src = '''
import sys,json
for i in []:
    labels=[l["name"] for l in i.get("labels") or []]
    if "roadmap" not in labels: continue
'''
compile(src, "roadmap", "exec")
PY
```

Expected: eleven `OK` lines.

- [ ] **Step 3: Commit**

```bash
git add commands/fj/roadmap.md
git commit -m "feat(commands): add /fj:roadmap with list/promote/defer (#175)"
```

---

### Task 3: Router

**Files:**
- Create: `commands/roadmap.md`

- [ ] **Step 1:** Copy `commands/parked.md` wholesale and adapt: front-matter
naming the three verbs, the host-detection snippet **verbatim**, delegation
bullets pointing at `~/.claude/commands/gh/roadmap.md` and
`~/.claude/commands/fj/roadmap.md`, the "holds no query logic of its own"
sentence, and the footer.

- [ ] **Step 2: Verify**

```bash
f=commands/roadmap.md
test -f "$f" && echo "file exists OK" || echo "FAIL: missing"
grep -Fq 'gh auth token --hostname' "$f" && echo "detection snippet OK" || echo "FAIL: detection"
grep -Fq 'holds no query logic of its own' "$f" && echo "router contract OK" || echo "FAIL: contract"
grep -Fq 'commands/gh/roadmap.md' "$f" && echo "gh delegation OK" || echo "FAIL: gh delegation"
grep -Fq 'commands/fj/roadmap.md' "$f" && echo "fj delegation OK" || echo "FAIL: fj delegation"
grep -Fq 'index("roadmap")' "$f" && echo "FAIL: query logic leaked into router" || echo "no logic in router OK"

# the detection snippet must match /parked's byte-for-byte
diff <(sed -n '/^host=/,/^fi$/p' commands/parked.md) <(sed -n '/^host=/,/^fi$/p' "$f") >/dev/null \
  && echo "detection identical OK" || echo "FAIL: detection snippet drifted"
```

Expected: seven `OK` lines.

- [ ] **Step 3: Commit**

```bash
git add commands/roadmap.md
git commit -m "feat(commands): add /roadmap forge router (#175)"
```

---

### Task 4: Retire #173's placeholder escape hatch

**Files:**
- Modify: `commands/gh/issues.md`
- Modify: `commands/fj/issues.md`

**Interfaces:**
- Consumes: Tasks 1–2 — the commands must exist before the prose points at them.

**Precondition.** #173 must be merged. Check first:

Each file carries its **own** placeholder wording, so check each against its own
string — `commands/gh/issues.md` says `gh issue list --label roadmap`, while
`commands/fj/issues.md` says `tea issues list --login git-home --labels roadmap`:

```bash
grep -Fq 'gh issue list --label roadmap' commands/gh/issues.md \
  && echo "#173 present in gh — proceed" || echo "#173 not merged (gh) — SKIP this task"
grep -Fq 'tea issues list --login git-home --labels roadmap' commands/fj/issues.md \
  && echo "#173 present in fj — proceed" || echo "#173 not merged (fj) — SKIP this task"
```

If it says SKIP, skip the task and say so in the PR description. Do not write the
surrounding prose from scratch.

- [ ] **Step 1: `commands/gh/issues.md`**

Replace:

```markdown
Roadmap issues are planned for a future milestone rather than current work; find them with `gh issue list --label roadmap`.
```

with:

```markdown
Roadmap issues are planned for a future milestone rather than current work; list them with `/gh:roadmap`.
```

- [ ] **Step 2: `commands/fj/issues.md`**

Replace the `tea issues list --login git-home --labels roadmap` sentence with the
same pointer to `/fj:roadmap`.

- [ ] **Step 3: Verify**

Check each file against **its own** placeholder string. Testing the gh-worded string
against both is a false pass on the Forgejo side: `commands/fj/issues.md` never
contained it, so the check reports "retired" before any edit is made.

```bash
check_retired() {
  local f="$1" stale="$2"
  grep -Fq "$stale" "$f" && echo "FAIL: placeholder still in $f" || echo "placeholder retired OK: $f"
  # wording-independent backstop, in case #173's sentence gets reworded
  grep -Eq '(gh|tea) issues? list[^`]*roadmap' "$f" && echo "FAIL: a raw escape hatch remains in $f" || echo "no raw escape hatch OK: $f"
  grep -Eq '/(gh|fj):roadmap' "$f" && echo "points at the command OK: $f" || echo "FAIL: no command pointer in $f"
}
check_retired commands/gh/issues.md 'gh issue list --label roadmap'
check_retired commands/fj/issues.md 'tea issues list --login git-home --labels roadmap'
# the filters themselves are untouched
grep -Fq 'index("roadmap") | not' commands/gh/issues.md && echo "gh filter intact OK" || echo "FAIL: gh filter"
grep -Fq '"roadmap" in labels' commands/fj/issues.md && echo "fj filter intact OK" || echo "FAIL: fj filter"
```

Expected: eight `OK` lines.

The backstop regex relies on the closing backtick of `` `gh issue list` `` to avoid
matching the unrelated prose line that explains why GraphQL is used. If you reword
that line, re-run this block against the **pre-change** file too and confirm it still
reports `FAIL` — a verification that cannot fail is not a verification.

- [ ] **Step 4: Commit**

```bash
git add commands/gh/issues.md commands/fj/issues.md
git commit -m "docs(commands): point /issues at /roadmap instead of raw gh (#175)"
```

---

### Task 5: Changelog

- [ ] **Step 1:** Under `## [Unreleased]` → `### Added`:

```markdown
- **commands:** `/roadmap` (+ `/gh:roadmap`, `/fj:roadmap`) — lists issues labeled
  `roadmap`, promotes one into a milestone (schedule first, then unlabel), and
  records a `roadmap:` reason comment; `/issues` now points here instead of a raw
  `gh` invocation (#175)
```

- [ ] **Step 2: Verify**

```bash
awk '/^## \[Unreleased\]/{u=1} /^## \[1\./{u=0} u && /^### Added/{a=1} u && a && /roadmap/{r=1} u && a && /#175/{n=1} END{ if (r && n) print "changelog OK"; else print "FAIL: changelog roadmap=" (r?1:0) " ref175=" (n?1:0) }' CHANGELOG.md
grep -Fq '/milestone` (+ `/gh:milestone`, `/fj:milestone`)' CHANGELOG.md && echo "prior entries intact OK" || echo "FAIL: clobbered earlier entries"
```

Expected: two `OK` lines.

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for /roadmap (#175)"
```

---

## Manual verification (human, after merge)

[ ] **1.** Re-run `setup/link-commands.sh`, then `/roadmap` in
`freaxnx01/agent-workflow` — this repo has **no** `roadmap` label. Confirm it says
the roadmap is empty and that `gh label list` still shows no `roadmap` label
afterwards (it must not have been created).

[ ] **2.** `/roadmap` in `anim-bossinfo-ch/BI-ArchiveUploader` — confirm issue
**#164** lists with `—` for the reason.

[ ] **3.** `/roadmap defer 164 "waiting on the dedupe spike"` — confirm the reason
shows on the next `/roadmap`.

[ ] **4.** `/roadmap promote 164 to <an existing milestone>` — confirm the milestone
read-back succeeds, then the label read-back shows `roadmap` gone, then that
`/gh:route 164` is **offered** and not run. Confirm #164 no longer appears in
`/roadmap` and now appears under `/milestone list`.

[ ] **5.** `/roadmap promote 164 to nonsense-milestone` — confirm it prints the open
milestones, stops, and leaves the `roadmap` label in place.
