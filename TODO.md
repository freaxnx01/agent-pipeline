# TODO

## PR #215 follow-ups (deferred, non-blocking, flagged in the PR itself)

- [ ] No fixture asserts `setup/link-commands.sh` actually installs
      `scripts/lib/detect-forge.sh` to `~/.claude/scripts/lib/` (in either copy or
      `--link` mode) — a regression there would go green.
- [ ] `README.md`'s delivery-path table doesn't document the
      `scripts/lib/` → `~/.claude/scripts/lib/` mapping the installer now performs.

## `/enrich` + `/enrich-phased` concurrency lock (2026-08-04/05 session)

- [x] Core lock mechanism shipped: `commands/enrich.md` Step 1.5/2.5/6,
      `enrichment-ongoing` label, race re-check-after-acquire. Issue #229, merged
      `bf01ae3`.
- [x] Cosmetic review nits filed as follow-up issue #236, cross-linked on PR #233.
- [x] `/enrich-phased` lock shipped (issue #237, merged `cce9ecb` in PR #244) —
      detect/acquire/release adapted to its phase/`/clear` structure, gated on
      new-run vs resume, staleness threshold aligned to **24h in both commands**
      (`/enrich`'s own threshold was raised from 4h — the lock comment doesn't
      record which command acquired it, so both must agree on one window).
      Took 3 automated pipeline rounds (PRs #240/#241/#243, all closed as
      superseded after real review findings — a state-file race, a self-collision
      bug on mid-phase resume, the threshold mismatch) plus a 4th round that
      timed out before opening a PR; the final threshold/resume-release/
      label-verify fixes were applied by hand and merged directly as PR #244.
- [ ] **Manual verification never run.** Both specs
      (`docs/superpowers/specs/2026-08-04-enrich-lock-design.md` and
      `…/2026-08-04-enrich-phased-lock-design.md`) document dry-run scenarios
      (hard-stop, stale takeover, full run, cross-command detection in both
      directions, resume-at-boundary, mid-phase resume, abandoned-resume
      release) as the only test coverage this docs-only feature has — none of
      them have actually been exercised against a real scratch issue yet.
- [ ] Issue #236 (the two cosmetic nits from #233's review — missing
      `2>/dev/null || true` comment, gh/tea tie-break wording) is still open,
      still `needs-enrichment` — never enriched or dispatched.
- [ ] Cosmetic: `docs/superpowers/plans/2026-08-04-enrich-phased-lock.md` was
      rewritten mid-review to describe the diff in prose ("as implemented in
      commands/enrich-phased.md") rather than keep the original verbatim
      find/replace blocks — flagged as circular/hard-to-independently-verify in
      round 3's review, explicitly deferred as not worth another round. Still
      true after the final hand-applied fixes.
- [ ] Discovered `main`'s branch protection has no `required_pull_request_reviews`
      configured, despite `CLAUDE.md`'s "at least 1 PR review" convention
      (`gh api repos/freaxnx01/agent-workflow/branches/main/protection` — only
      `gate-selftest` is a required status check). Worth reconciling: either wire
      up the required-review rule, or correct the doc if 1-review-required was
      never actually intended for this repo.
- [ ] Observed the pipeline's own review agent time out mid-run
      (`RESULT_FILE not valid JSON`, exit 124) on round 4, likely from the issue
      body growing large across multiple appended review-finding rounds. No
      issue filed — worth watching for whether this recurs on other
      multi-round redispatches; if so, may be worth having `/gh:implement`'s
      redispatch guidance trim/summarize prior rounds instead of appending
      indefinitely.

## Worktrees (status as of 2026-08-05)

- [ ] `.worktrees/div` (branch `worktree-div`) — still 1 local commit
      (`commands/gh/review.md` changes, "don't default to @copilot for
      agent-workflow PRs") with no upstream tracking branch and no PR yet.
      Unchanged since last check — real work, still untouched.
- [x] `.worktrees/enrich` (branch `worktree-enrich`) — now shows **no diff**
      against `main`; its content (self-fix routing, #193) landed via PRs
      #232/#235/#239 and #238's PR #242, both merged this session. Safe to
      clean up (`git worktree remove` + `git branch -d`) next time it's
      touched — not done here since worktree cleanup wasn't this session's
      task.
- [ ] `.worktrees/factory-map` (branch `docs/pre-preview-self-fix-enrich-81`) — 2
      files not on `main` (design/plan docs); its own remote counterpart has
      diverged heavily from the local branch — needs a closer look before any
      cleanup decision. Unchanged since last check.
- [ ] **New**: `.worktrees/new` (branch `worktree-new`) appeared since last
      check, tip `540c3ca` — matches a commit made *in this session's own
      worktree* (`worktree-richy`'s TODO.md update), not obviously this
      worktree's own work. Shows no diff against `main`. Unclear what created
      it or what it's for — worth checking before assuming it's safe to
      remove.
