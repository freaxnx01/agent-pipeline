# /enrich-phased concurrency lock — design

## Problem

`/enrich`'s concurrency lock (issue #229, merged in PR #233) prevents two
sessions from concurrently brainstorming/planning the same issue via an
`enrichment-ongoing` label + timestamped comment. It only covers
`commands/enrich.md` — `/enrich-phased` (`commands/enrich-phased.md`), the
split-context variant that runs spec → `/clear` → plan → `/clear` → issue
body as isolated phases, was explicitly out of scope for #229 and was never
touched.

Consequence: if a session acquires the lock via `/enrich` but the issue is
then finished off via `/enrich-phased` (or the reverse — started phased,
finished via plain `/enrich`), nothing on the `/enrich-phased` side ever
releases or even recognizes the lock in a way that matches its own longer
natural duration. Today `/enrich-phased` neither detects an existing lock
nor acquires one at all.

## Goals

- `/enrich-phased` gains the same detect/acquire/release lock behavior
  `/enrich` has, adapted to its phase/`/clear` structure.
- An issue locked by either command is correctly detected and respected by
  the other — achieved for free by reusing the identical label name and
  comment marker format `/enrich` already established.
- The staleness window accounts for `/enrich-phased`'s legitimately longer
  pauses between phases (hours to days), rather than reusing `/enrich`'s 4h
  window verbatim.
- Applies to both the GitHub and Forgejo sections of
  `commands/enrich-phased.md`, mirroring `/enrich`'s existing gh/tea
  symmetry.

## Non-goals

- No change to `/enrich`'s own lock (`commands/enrich.md`) — it already
  works and is out of scope here.
- No re-verification of the lock at every phase boundary (Phase `plan`,
  Phase `issue`) — see Design below for why a single acquisition in Phase
  `spec` is sufficient.
- No cross-session identity tracking (who owns a lock) — same accepted
  limitation as `/enrich`'s spec.

## Design

### Lock representation (reused, unchanged)

Same as `/enrich`: the `enrichment-ongoing` label plus an issue comment:

```text
🔒 Enrichment lock acquired at <ISO 8601 UTC timestamp>
```

or, on takeover of a stale lock:

```text
🔒 Enrichment lock re-acquired at <timestamp> (previous lock stale, <Xh> old)
```

Reusing the exact label name and comment format means an issue locked by
`/enrich` is transparently visible to `/enrich-phased`'s detection logic and
vice versa — no extra bridging code, no second label. This is the key
property that makes the two commands consistent with each other without
either needing to know the other exists beyond sharing a marker format.

### Staleness threshold: 24 hours (not 4h)

`/enrich`'s 4h threshold assumes a single continuous sitting. `/enrich-phased`
exists specifically for topics large enough to span multiple `/clear`'d
sessions — a legitimate gap between Phase `spec` finishing and Phase `plan`
resuming could be hours or span into the next day. A 4h threshold would let
a second session steal an actively-in-progress phased run's lock during an
ordinary pause. 24 hours absorbs a normal overnight gap while still
recovering from an abandoned run within a day.

### Where the lock lives in the phase flow

All detect/acquire/release logic lives in **Phase `spec`** — the only point
in the phased flow equivalent to `/enrich`'s Step 1.5/2.5, and specifically
only on a **new run** (an issue number passed as an argument), never on a
state-file resume:

- A resume (`/enrich-phased` invoked with no argument, continuing from
  `.claude/enrich-phased.state`) is the *same* run continuing, not a second
  session — re-running detection there would be a spurious self-collision
  check against a lock the same run itself is holding.
- Phase `plan` and Phase `issue` do not re-verify the lock at all. This
  trusts that once Phase `spec` acquires it, it remains held until Phase
  `issue` releases it — the same trust model `/enrich` uses between its own
  Step 2.5 and Step 6, just stretched across `/clear` boundaries instead of
  within one context. No re-verification keeps the phase transitions simple
  and avoids adding a failure mode (e.g. "lock mysteriously missing at Phase
  `plan`, now what?") that the design doesn't have an answer for and that a
  legitimate run wouldn't hit anyway (nothing else touches this label absent
  another `/enrich`/`/enrich-phased` run or the 24h staleness path, and if a
  competing run *did* take over, that's exactly the race path already
  handled).

Concretely, within Phase `spec`'s existing steps
(`commands/enrich-phased.md`'s "Phase `spec`" section):

1. **New step, immediately after step 1** (read issue) **and gated on this
   being a new run** (issue number passed as an argument, not a resume):
   detect an existing lock exactly as `/enrich`'s Step 1.5 does, but using
   the 24h threshold. No `enrichment-ongoing` label → continue. Label
   present, comment found, age < 24h → hard stop, tell the user, do not
   start this run at all (don't even write `phase=spec` to the state file).
   Age ≥ 24h or no matching comment → offer takeover; no → stop; yes →
   continue, noting the takeover for the acquisition step below.
2. **New step, between the existing readiness-assessment step and the
   brainstorming-invocation step**: acquire the lock — comment first
   (fresh-acquisition or takeover wording), then the label — then
   re-fetch comments and check for a competing lock comment that wasn't
   present during detection and has an earlier timestamp. If one exists,
   stand down (post a `🔓 … lost race …` comment, leave the label in place
   since the winner depends on it), tell the user, and end the command
   without starting brainstorming or writing any state file. Otherwise the
   lock is held — continue to brainstorming as today.
3. **Releasing early**: if the run ends before Phase `issue` for a
   user-driven reason — declining brainstorming's approval gate within
   Phase `spec`, or Phase `plan`'s existing push-verification failure —
   release the lock (`--remove-label enrichment-ongoing 2>/dev/null ||
   true`) before stopping. This mirrors `/enrich`'s "Releasing early"
   behavior and is the only lock-related addition to Phase `plan`.

**Phase `issue`**'s existing label-clearing step (which already removes
`needs-enrichment` / `❓ to-be-defined`) also removes `enrichment-ongoing`
there — the final release, matching `/enrich`'s Step 6.

Mirrored identically in the Forgejo section of `commands/enrich-phased.md`,
using the same `tea labels create` / read-filter-PUT pattern `/enrich`'s
Forgejo section and `/enrich-phased`'s existing Phase `issue` label-clearing
step already use.

### Crash recovery

Same model as `/enrich`: if a run dies (crash, abandoned session, user never
resumes) after acquiring the lock but before Phase `issue` releases it, the
label simply persists until a later run — same or different session — finds
it past the 24h threshold and offers takeover. No explicit crash-cleanup
step; staleness expiry is the entire recovery mechanism, same accepted
tradeoff as `/enrich`'s design.

## Testing / verification

`/enrich-phased` is a markdown-instruction command with no automated test
suite, same as `/enrich`. Verification is a manual dry run against a scratch
issue:

1. Pre-apply `enrichment-ongoing` + a fresh lock comment on a test issue.
   Run `/enrich-phased <issue>` (new run). Confirm it hard-stops in Phase
   `spec`'s new detection step, before readiness assessment or
   brainstorming, and never writes `.claude/enrich-phased.state`.
2. Backdate the lock comment past 24h. Re-run `/enrich-phased <issue>`.
   Confirm the stale/takeover prompt fires; "no" stops, "yes" proceeds.
3. Run `/enrich-phased <issue>` end-to-end on an unlocked issue across all
   three phases (with the `/clear` boundaries). Confirm the label and lock
   comment appear before brainstorming starts in Phase `spec`, persist
   through Phase `plan` untouched, and the label (not the comment) is gone
   after Phase `issue` completes.
4. Cross-command check: lock an issue via `/enrich` (Step 2.5), then run
   `/enrich-phased` on the same issue. Confirm Phase `spec`'s new detection
   step correctly sees `/enrich`'s lock and hard-stops. Repeat in reverse
   (lock via `/enrich-phased`, then run `/enrich`) to confirm `/enrich`'s
   existing Step 1.5 sees it too.
5. Resume check: start a run, let it stop at the Phase `spec` → `plan`
   boundary (normal handoff), `/clear`, resume with no argument. Confirm
   Phase `plan` does **not** re-run the detection step (no lock-related
   output) and simply proceeds.

## Follow-ups (out of scope here)

- None currently identified beyond what #229's own spec already tracks.
