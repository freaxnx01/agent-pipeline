# TODO

Loose ends from the 2026-08-01 session (forge-agnostic commands merge, #198/#199,
plus the `setup/link-commands.sh` prune fixes, #219/#220).

## PR #215 follow-ups (deferred, non-blocking, flagged in the PR itself)

- [ ] `setup/link-commands.sh`'s success banner still says
      `(e.g. /gh:enrich, /route, /capture-idea)` — `/gh:enrich` no longer exists,
      pick a command that still does.
- [ ] No fixture asserts `setup/link-commands.sh` actually installs
      `scripts/lib/detect-forge.sh` to `~/.claude/scripts/lib/` (in either copy or
      `--link` mode) — a regression there would go green.
- [ ] `README.md`'s delivery-path table doesn't document the
      `scripts/lib/` → `~/.claude/scripts/lib/` mapping the installer now performs.

## Open PRs unrelated to this session (pre-existing, not touched)

- [ ] PR #170 — `docs: reconcile Phase 6 runner docs with what actually got built`
- [ ] PR #115 — `docs(#114): qwen3.6-27b benchmarking campaign — spec + plan`
