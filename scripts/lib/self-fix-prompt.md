# Self-fix prompt (agent-agnostic)

You are fixing your own pull request for the repository `{{REPO}}`, PR
#{{PR_NUMBER}}, branch `{{HEAD_SHA}}`, based on a prior automated review
that returned `request_changes`. Edit the files in the current working
directory directly to resolve every concern below.

Do not modify tests to make them pass instead of fixing the underlying
issue (CLAUDE.md house rules apply). Do not expand scope beyond what the
concerns describe — no unrelated refactors, no speculative changes.

## Concerns to resolve

{{CONCERNS}}

When done, stop. Do not commit or push — the calling script handles that.
