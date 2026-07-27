---
description: List, create, assign, or triage milestones — auto-routes to GitHub or Forgejo by remote
argument-hint: list | new <name> [due <date>] | assign <issue> to <name> | triage
---

Route to the forge-specific **milestone** command based on the `origin` remote host,
then follow it exactly. This command holds no logic of its own — `/gh:milestone` and
`/fj:milestone` remain the single source of truth.

## Detect the forge (generic host-matching)

```bash
# Host from origin, handling https://, ssh://, and scp-style git@host:path remotes
host=$(git remote get-url origin 2>/dev/null | sed -E 's#^[a-zA-Z]+://##; s#^[^@/]*@##; s#[:/].*##')
if gh auth token --hostname "$host" >/dev/null 2>&1; then
  echo "github  ($host)"     # a GitHub / GHES host gh is logged into
elif tea logins list 2>/dev/null | grep -qiF "$host"; then
  echo "forgejo ($host)"     # matches a tea (Forgejo/Gitea) login
elif [ "$host" = "github.com" ]; then
  echo "github  ($host)"     # fallback: canonical GitHub host, even if gh isn't authed
else
  echo "unknown ($host)"
fi
```

## Then

- **github** → read and follow `~/.claude/commands/gh/milestone.md` (i.e. run `/gh:milestone`).
- **forgejo** → read and follow `~/.claude/commands/fj/milestone.md` (i.e. run `/fj:milestone`).
- **unknown** → report the detected host and that no authed GitHub or Forgejo login
  matched it; point at `gh auth login` / `tea login add`. Don't guess a forge.

The target command takes a verb — `list`, `new`, `assign`, or `triage`. Pass it these
arguments unchanged; the forge file owns the parsing, including "no arguments →
`list`" and "unrecognized verb → print the usage forms and stop":

$ARGUMENTS

Announce the chosen forge in one line (e.g. `→ GitHub (github.com)`), then carry out
that command.

---

If detection misfires (new host, an SSH `Host` alias that hides the real domain,
`gh`/`tea` not on PATH), fix the snippet here and update this command for the future.
