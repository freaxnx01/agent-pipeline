# TODO

## PR #215 follow-ups (deferred, non-blocking, flagged in the PR itself)

- [ ] No fixture asserts `setup/link-commands.sh` actually installs
      `scripts/lib/detect-forge.sh` to `~/.claude/scripts/lib/` (in either copy or
      `--link` mode) — a regression there would go green.
- [ ] `README.md`'s delivery-path table doesn't document the
      `scripts/lib/` → `~/.claude/scripts/lib/` mapping the installer now performs.

## `/enrich` concurrency lock (2026-08-04 session, merged in #233)

- [x] Core lock mechanism shipped: `commands/enrich.md` Step 1.5/2.5/6,
      `enrichment-ongoing` label, race re-check-after-acquire. Issue #229, merged
      `bf01ae3`.
- [x] Cosmetic review nits filed as follow-up issue #236, cross-linked on PR #233.
- [x] `/enrich-phased` still never releases the `enrichment-ongoing` lock if a
      lock acquired via `/enrich` is finished off via `/enrich-phased` instead —
      out of scope for #229, called out as a known gap in
      `docs/superpowers/specs/2026-08-04-enrich-lock-design.md`'s Follow-ups
      section. Filed as issue #237.
- [ ] Discovered `main`'s branch protection has no `required_pull_request_reviews`
      configured, despite `CLAUDE.md`'s "at least 1 PR review" convention
      (`gh api repos/freaxnx01/agent-workflow/branches/main/protection` — only
      `gate-selftest` is a required status check). Worth reconciling: either wire
      up the required-review rule, or correct the doc if 1-review-required was
      never actually intended for this repo.

## Worktrees with real in-progress work (left untouched, not stale)

- [ ] `.worktrees/div` (branch `worktree-div`) — 1 local commit
      (`commands/gh/review.md` changes, "don't default to @copilot for
      agent-workflow PRs") with no upstream tracking branch and no PR yet.
- [ ] `.worktrees/enrich` (branch `worktree-enrich`) — 14 commits ahead of its own
      `origin/worktree-enrich`, unpushed changes to
      `.github/workflows/agent-implement.yml` (self-fix / #193-adjacent work).
- [ ] `.worktrees/factory-map` (branch `docs/pre-preview-self-fix-enrich-81`) — 2
      files not on `main` (design/plan docs); its own remote counterpart has
      diverged heavily from the local branch — needs a closer look before any
      cleanup decision.

## Bridge dispatch — subscription budget (2026-09-01/03 session)

Both issues live in **`freaxnx01/bridge`**, not this repo — `/enrich` must run from
`~/repos/github/freaxnx01/public/bridge`. Nothing was implemented; this session only
investigated and filed.

- [ ] Enrich + dispatch **bridge#253** — `feat(dispatch): wire up --retry-only mode
      for the hourly timer ticks`. `NextAction` in `internal/dispatch/failure.go`
      fully specifies transient-vs-substantive retry handling but nothing calls it;
      the hourly systemd ticks (23:00–06:00) re-run the full dispatch path, guarded
      only by the "already dispatched" eligibility check. Self-contained and ready
      to enrich now. https://github.com/freaxnx01/bridge/issues/253
- [x] **Daytime-dispatch schedule decided (2026-09-03): extend the timer to
      07:00–18:00.** Recorded on the issue, which pulls the schedule change into
      #254's scope. Sequencing constraint: the timer extension must ship *with* the
      budget rung, never ahead of it — a daytime timer without the guard is bounded
      only by the existing caps, i.e. the exact failure mode #254 prevents.
      `docs/systemd/bridge-dispatch.timer` is unchanged so far, deliberately.
      https://github.com/freaxnx01/bridge/issues/254#issuecomment-5529972799
- [ ] Enrich **bridge#254** — `feat(dispatch): reserve subscription headroom with a
      daytime usage-budget rung` (only after the decision above). Night 18:00–07:00:
      rung off. Day 07:00–18:00: refuse dispatch once combined trailing-5h usage
      (HITL + pipeline) hits 80% of the window, leaving 20% for the operator.
      API key for CI is ruled out (cost). https://github.com/freaxnx01/bridge/issues/254
- [ ] Confirm empirically that subscription limits are account-scoped, i.e. that a
      local `/usage` reading already includes Action-run consumption. Recorded as an
      inference, not a documented fact, in
      https://github.com/freaxnx01/bridge/issues/254#issuecomment-5500108394 — it is
      the calibration reference for `window_budget_usd`, so it matters.
