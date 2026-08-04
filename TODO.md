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
- [ ] `/enrich-phased` still never releases the `enrichment-ongoing` lock if a
      lock acquired via `/enrich` is finished off via `/enrich-phased` instead —
      out of scope for #229, called out as a known gap in
      `docs/superpowers/specs/2026-08-04-enrich-lock-design.md`'s Follow-ups
      section, no issue filed yet.
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
