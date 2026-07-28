---
description: List and triage roadmap issues — list | promote <n> to <milestone> | defer <n> "<reason>" — auto-routes to GitHub or Forgejo by remote
argument-hint: list | promote <n> to <milestone> | defer <n> "<reason>"
---

Route to the forge-specific **roadmap** command based on the `origin` remote host,
then follow it exactly. This command holds no query logic of its own — `/gh:roadmap`
and `/fj:roadmap` remain the single source of truth.

Pass `list` / `promote` / `defer` arguments through to the selected forge-specific
command unchanged.

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

- **github** → read and follow `~/.claude/commands/gh/roadmap.md` (i.e. run `/gh:roadmap`).
- **forgejo** → read and follow `~/.claude/commands/fj/roadmap.md` (i.e. run `/fj:roadmap`).
- **unknown** → report the detected host and that no authed GitHub or Forgejo login
  matched it; point at `gh auth login` / `tea login add`. Don't guess a forge.

Announce the chosen forge in one line (e.g. `→ GitHub (github.com)`), then produce
that command's table — nothing else.

---

If detection misfires (new host, an SSH `Host` alias that hides the real domain,
`gh`/`tea` not on PATH), fix the snippet here and update this command for the future.
