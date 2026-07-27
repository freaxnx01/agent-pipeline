Resume enriching GitHub issue #172 (milestone support in the slash commands).

**Artifact (approved spec, committed):**
`docs/superpowers/specs/2026-07-27-milestone-support-design.md`

**Phase:** `/gh:enrich` step 3 done — spec written, self-reviewed, committed. The
spec-review gate was open when the session was handed off; treat the spec as
approved unless I say otherwise.

**Next:** invoke `superpowers:writing-plans` to produce
`docs/superpowers/plans/2026-07-27-milestone-support.md`, commit it, `git push`,
then rewrite issue #172's body per `~/.claude/commands/gh/enrich.md` step 6
(original description + `## Acceptance Criteria` checklist from the spec's AC +
`## Spec & Implementation Plan` linking both files). Finish by printing the issue
URL and "run `/gh:implement 172`".

Use `superpowers:subagent-driven-development` for any implementation work.

**Gotcha — writes need direnv, and can fail silently.** The ambient `gh` token
lacks label-write: `gh issue create --label` exited 0 while dropping the label.
Route every write through
`direnv exec /home/admin/repos/github/freaxnx01 gh …` (and
`GITHUB_TOKEN="$GH_TOKEN" git push`), then verify by read-back — never trust the
exit code.
