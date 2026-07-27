# Implementation Plan: `/parked` triage verbs

**Issue:** [#174](https://github.com/freaxnx01/agent-workflow/issues/174)
**Spec:** [`docs/superpowers/specs/2026-07-27-parked-triage-design.md`](../specs/2026-07-27-parked-triage-design.md)
**Date:** 2026-07-27

---

## Constraints — read before starting

- **Extend the existing three files.** Do not create `/gh:parked-triage` or any new
  top-level command. Verbs go into `commands/gh/parked.md`,
  `commands/fj/parked.md`, `commands/parked.md`.
- **`list` stays behaviourally identical** apart from the added reason column. Its
  existing query and output shape are not to be reworked.
- **Never add the `🧊 parked` label** from any verb. Parking stays manual.
- **`unpark` delegates to `/gh:route`** (`/fj:route` on Forgejo). Do not reimplement
  route's readiness gate, complexity assessment, or model choice here.
- **`repark` posts a new comment.** It must never edit the issue body (that races
  with `/enrich`, which rewrites bodies wholesale) and never edit a previous
  comment.
- **Every write reported from a read-back, never the exit code** — `gh issue create
  --label needs-enrichment` has been observed exiting `0` while silently dropping
  the label.
- **`tea api` has no `--jq`** — pipe into `python3 -c`. `gh` uses its built-in
  `--jq`. **`tea` is always invoked with `--login git-home`.**
- **Forgejo: filter labels client-side.** `commands/fj/parked.md:35` already records
  that the `labels=` query param is broken on this Forgejo — do not "optimise" the
  client-side filter into a server-side one.
- **There is no automated validation of command `.md` files in this repo.**
  `just lint` covers only `.github/workflows/`, `scripts/`, and `tests/`. **Do not
  add a test framework, a fixture, or a `tests/` entry.**
- **Every verification check must print on both paths** — `… && echo "… OK" ||
  echo "FAIL: …"`. (See `a6f7c75`.)
- **Do not use `git diff … main`** in a check — assert on file content.
- **No live-forge writes from a task step.** This plan runs in CI.
- Reference `#174` in every commit; Conventional Commits.

## The GitHub queries are pre-validated

Run against `freaxnx01/agent-workflow` on 2026-07-27. The repo has exactly **1**
parked issue (#116); the list query returns it with `—` for the reason. The
reason-extraction jq was tested on three inputs — multiple matching comments (picks
the most recent, truncates to the first line), one non-matching comment, and no
comments at all (both yield `—`).

Note `last // "—"` works because `last` on an empty array yields `null`, which `//`
then replaces. (`.[-1] // "—"` happens to behave identically — jq returns `null`
rather than erroring — so either is safe; `last` is used for readability.)

## File Structure

| File | Responsibility |
|---|---|
| `commands/gh/parked.md` | **Modify.** Verbs + reason column via `gh` / GraphQL. |
| `commands/fj/parked.md` | **Modify.** Same via `tea api` + `python3`. |
| `commands/parked.md` | **Modify.** Router — verb names only, no logic. |
| `CHANGELOG.md` | **Modify.** `[Unreleased]` → `### Added`. |

---

### Task 1: GitHub — verbs on `/gh:parked`

**Files:**
- Modify: `commands/gh/parked.md`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the verb contract and interaction rules Tasks 2 and 3 mirror.

- [ ] **Step 1: Front-matter**

```yaml
description: List and triage parked issues (🧊 parked) — list | unpark <n> | repark <n> "<reason>" | review
argument-hint: list | unpark <n> | repark <n> "<reason>" | review
```

- [ ] **Step 2: Parse the verb**

Add a `## Parse the verb` section modelled on `commands/gh/milestone.md:12`: no
arguments → `list`; a first word that is not `list` / `unpark` / `repark` /
`review` → print the four usage forms and stop without guessing.

- [ ] **Step 3: `list` gains a reason column**

Replace the existing query with one that also pulls comments, so the most recent
`🧊 parked:` reason can be shown:

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
    | map(select([.labels.nodes[].name] | index("🧊 parked")))
    | .[] | [ .number, .title,
              ([.labels.nodes[].name] | join(",")),
              .createdAt, .author.login,
              ( [ .comments.nodes[].body | select(startswith("🧊 parked:")) ]
                | last // "—" | split("\n")[0] ) ] | @tsv'
```

Show a compact table — number, title, labels, age (relative), author, **reason**.
`—` means no reason was ever recorded, which marks issues parked before this
existed. No preamble. If there are none, just say so.

- [ ] **Step 4: `unpark <n>`**

```bash
gh issue edit <n> --remove-label "🧊 parked"
gh issue view <n> --json number,labels --jq '[.number, ([.labels[].name] | join(","))] | @tsv'
```

Report from the read-back. If `🧊 parked` is still present, say the removal failed
and stop — do not continue to routing.

Then **read and follow `~/.claude/commands/gh/route.md`** for issue `<n>` (i.e. run
`/gh:route <n>`) so the freshly-unparked issue gets an implementation
recommendation. Do not reimplement route's logic here.

If the issue also carries `needs-enrichment`, say so before routing — unparking
doesn't make it implementable, and route's own readiness gate will catch it.

- [ ] **Step 5: `repark <n> "<reason>"`**

```bash
gh issue comment <n> --body "🧊 parked: <reason>"
```

Then read back the last comment and confirm from it:

```bash
gh issue view <n> --json comments --jq '.comments | last | .body | split("\n")[0]'
```

The `🧊 parked:` prefix is what `list` matches on — it is **required**, not
decorative. Leave the label in place; `repark` never removes it. Never edit the
issue body and never edit a previous comment: the point is an append-only history
of why this kept being deferred.

If no reason argument was given, ask for one and stop — a reasonless repark is a
no-op.

- [ ] **Step 6: `review`**

Walk the parked issues from `list`, newest first, one at a time. For each: show
number, title, labels, age, current reason; ask *still valid to stay parked?* and
offer `unpark` / `repark` / `skip`.

- **One issue at a time.** No bulk actions.
- **Never act without an explicit answer.** Unanswered means skipped.
- **`skip` is silent** and never re-prompts.
- **Stop cleanly** when told to.
- At the end report the tally: unparked, reparked, skipped, remaining.

- [ ] **Step 7: Verify**

```bash
f=commands/gh/parked.md
sed -n '1,4p' "$f" | grep -q 'unpark' && echo "front-matter OK" || echo "FAIL: front-matter"
for v in unpark repark review; do
  grep -q "^## $v" "$f" && echo "verb section OK: $v" || echo "FAIL: no section $v"
done
grep -Fq 'Parse the verb' "$f" && echo "verb parsing OK" || echo "FAIL: no verb parsing"
grep -Fq 'comments(last:20)' "$f" && echo "comments query OK" || echo "FAIL: comments query"
grep -Fq 'last // "—"' "$f" && echo "reason fallback OK" || echo "FAIL: reason fallback"
grep -Fq 'startswith("🧊 parked:")' "$f" && echo "reason prefix OK" || echo "FAIL: reason prefix"
grep -Fq -- '--remove-label "🧊 parked"' "$f" && echo "unpark mechanics OK" || echo "FAIL: unpark"
grep -Fq 'commands/gh/route.md' "$f" && echo "delegates to route OK" || echo "FAIL: no route delegation"

# never adds the label
grep -Fq -- '--add-label "🧊 parked"' "$f" && echo "FAIL: adds parked label" || echo "never adds label OK"
# never edits the body
grep -Fq 'issue edit <n> --body' "$f" && echo "FAIL: edits issue body" || echo "no body edit OK"
```

Expected: twelve `OK` lines.

- [ ] **Step 8: Commit**

```bash
git add commands/gh/parked.md
git commit -m "feat(commands): add unpark/repark/review verbs to /gh:parked (#174)"
```

---

### Task 2: Forgejo — verbs on `/fj:parked`

**Files:**
- Modify: `commands/fj/parked.md`

**Interfaces:**
- Consumes: Task 1's verb contract and interaction rules — same wording, Forgejo
  mechanics. `unpark` delegates to `/fj:route`, not `/gh:route`.

- [ ] **Step 1: Front-matter, verb parsing, and the four verbs**

Mirror Task 1 Steps 1–2 and 4–6, with Forgejo mechanics. Forgejo has no GraphQL, so
`list` needs a second call for comments — fetch them **only for the issues that came
back parked**, not for every open issue:

````markdown
```bash
# parked issues (labels filtered client-side — the labels= param is broken here)
tea api --login git-home "repos/$repo/issues?state=open&type=issues&limit=100&sort=created&order=desc" \
  | python3 -c '
import sys,json
for i in json.load(sys.stdin):
    labels=[l["name"] for l in i.get("labels") or []]
    if "🧊 parked" not in labels: continue
    print(i["number"], "|", i["title"], "|", ",".join(labels), "|", i["created_at"], "|", (i.get("user") or {}).get("login","?"))'

# then, per parked issue number, its most recent reason
tea api --login git-home "repos/$repo/issues/<n>/comments" \
  | python3 -c '
import sys,json
reasons=[c["body"] for c in json.load(sys.stdin) if c.get("body","").startswith("🧊 parked:")]
print(reasons[-1].split("\n")[0] if reasons else "—")'
```
````

Write operations:

```bash
# unpark — tea has no remove-label flag; read labels, drop the one, PATCH the rest
# repark
tea comment <n> "🧊 parked: <reason>"
```

Use `tea api -X PATCH` for the label edit if `tea` exposes no direct removal, and
**read back** the issue's labels afterwards either way.

> `tea` 0.14.1 is installed locally. **Verify every flag with
> `tea <subcommand> --help` before writing it into this file** — do not copy flags
> from memory. `tea issues create` uses `--description`, not `--body`, and
> `tea issues list` uses `--labels` (plural); this file already carries scars from
> exactly this class of mistake.

- [ ] **Step 2: Verify**

```bash
f=commands/fj/parked.md
sed -n '1,4p' "$f" | grep -q 'unpark' && echo "front-matter OK" || echo "FAIL: front-matter"
for v in unpark repark review; do
  grep -q "^## $v" "$f" && echo "verb section OK: $v" || echo "FAIL: no section $v"
done
grep -Fq 'startswith("🧊 parked:")' "$f" && echo "reason prefix OK" || echo "FAIL: reason prefix"
grep -Fq 'tea api --login git-home' "$f" && echo "login convention OK" || echo "FAIL: login"
grep -Fq 'commands/fj/route.md' "$f" && echo "delegates to fj route OK" || echo "FAIL: route delegation"
grep -Fq 'commands/gh/route.md' "$f" && echo "FAIL: delegates to the GitHub route" || echo "no cross-forge leak OK"
# Match query-string USE, not the word: this file mentions "labels=" in a prose
# comment explaining why it's avoided, so a bare `grep -F 'labels='` fires today.
grep -Eq '"repos/\$repo/issues\?[^"]*labels=' "$f" && echo "FAIL: uses the broken labels= param" || echo "client-side filter OK"

python3 - <<'PY' && echo "python parses OK" || echo "FAIL: python syntax"
src = '''
import sys,json
for i in []:
    labels=[l["name"] for l in i.get("labels") or []]
    if "\U0001f9ca parked" not in labels: continue
'''
compile(src, "parked", "exec")
PY
```

Expected: ten `OK` lines.

- [ ] **Step 3: Commit**

```bash
git add commands/fj/parked.md
git commit -m "feat(commands): add unpark/repark/review verbs to /fj:parked (#174)"
```

---

### Task 3: Router

**Files:**
- Modify: `commands/parked.md`

- [ ] **Step 1:** Front-matter names the verbs; add one sentence that the target
command takes `list` / `unpark` / `repark` / `review` and that arguments pass
through. The host-detection snippet, delegation bullets, and footer are unchanged.

- [ ] **Step 2: Verify**

```bash
f=commands/parked.md
sed -n '1,4p' "$f" | grep -q 'unpark' && echo "front-matter OK" || echo "FAIL: front-matter"
grep -q 'review' "$f" && echo "verbs named OK" || echo "FAIL: verbs missing"
grep -Fq 'comments(last:20)' "$f" && echo "FAIL: query logic leaked into router" || echo "no logic in router OK"
grep -Fq 'holds no query logic of its own' "$f" && echo "router contract intact OK" || echo "FAIL: router prose"
```

Expected: four `OK` lines.

- [ ] **Step 3: Commit**

```bash
git add commands/parked.md
git commit -m "feat(commands): route /parked verbs to both forges (#174)"
```

---

### Task 4: Changelog

- [ ] **Step 1:** Under `## [Unreleased]` → `### Added`:

```markdown
- **commands:** `/parked` (+ `/gh:parked`, `/fj:parked`) gains `unpark`, `repark`,
  and `review` verbs — unparking hands off to `/route`, reparking records a
  `🧊 parked:` reason comment, and `list` now shows the most recent reason (#174)
```

- [ ] **Step 2: Verify**

```bash
awk '/^## \[Unreleased\]/{u=1} /^## \[1\./{u=0} u && /^### Added/{a=1} u && a && /unpark/{r=1} u && a && /#174/{n=1} END{ if (r && n) print "changelog OK"; else print "FAIL: changelog unpark=" (r?1:0) " ref174=" (n?1:0) }' CHANGELOG.md
grep -Fq '/milestone` (+ `/gh:milestone`, `/fj:milestone`)' CHANGELOG.md && echo "prior entries intact OK" || echo "FAIL: clobbered earlier entries"
```

Expected: two `OK` lines.

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for /parked triage verbs (#174)"
```

---

## Manual verification (human, after merge)

`freaxnx01/agent-workflow` has exactly **1** parked issue as of 2026-07-27:
**#116** *"WIP limit for autonomous agent work across bridge + agent-pipeline"*,
with no reason comment.

[ ] **1.** Re-run `setup/link-commands.sh`, then `/parked` — confirm #116 appears
with `—` in the reason column.

[ ] **2.** `/parked repark 116 "blocked on bridge rate-limiting"` — confirm a
comment is posted and the next `/parked` shows the reason.

[ ] **3.** `/parked unpark 116` — confirm the label is gone from the read-back and
that `/gh:route 116` then runs.

[ ] **4.** Re-add `🧊 parked` to #116 by hand to restore the repo's state.

[ ] **5.** `/parked review` — confirm it walks one issue at a time and that `skip`
leaves the issue untouched.
