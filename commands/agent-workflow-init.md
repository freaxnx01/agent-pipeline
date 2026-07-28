---
description: Onboard the current (or a named) repo onto agent-workflow in one call — secrets, labels, settings, consumer stub PR
argument-hint: "[owner/repo] [-- extra onboard-consumer.sh flags]"
---

Wire the target repo onto `freaxnx01/agent-workflow` by running
`scripts/onboard-consumer.sh` from this repo. This is the one-call replacement
for the manual §0–§4 checklist in `docs/CONSUMER-SETUP.md` — see that doc for
what each step actually does and why.

**Target:** $ARGUMENTS (optional `owner/repo`; defaults to the current
directory's `origin` remote. Anything after a bare `--` is forwarded verbatim
to `onboard-consumer.sh`, e.g. `/agent-workflow-init -- --auto-review --chain`.)

## Step 1 — Resolve the target repo

If `$ARGUMENTS` names an `owner/repo`, use it. Otherwise:

```bash
url=$(git remote get-url origin); url=${url%.git}
repo=$(echo "$url" | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#')
```

Stop if this isn't a git repo with an `origin` pointing at GitHub.

## Step 2 — Resolve the Passbolt secret sources

Look these up **by name**, not by a hardcoded ID (IDs can rot; names are the
stable handle):

```bash
passbolt list resources 2>/dev/null | grep -i "Claude Code OAuth"
passbolt list resources 2>/dev/null | grep -i "OpenRouter API Key 'OpenCode'"
```

Use the first column (the resource UUID) from each match to build:

```bash
SECRET_CMD="passbolt get resource --id <claude-uuid> --json | jq -r '.password'"
OPENROUTER_CMD="passbolt get resource --id <openrouter-uuid> --json | jq -r '.password'"
```

If either lookup finds zero or more than one match, stop and ask the user —
don't guess which resource is the right one. Never print the resource's
`.password` value yourself; only the command string (which `onboard-consumer.sh`
pipes internally) ever touches the secret.

## Step 3 — Run the script

```bash
bash "$(git -C ~/repos/github/freaxnx01/public/agent-workflow rev-parse --show-toplevel)/scripts/onboard-consumer.sh" \
  -R "$repo" \
  --secret-cmd "$SECRET_CMD" \
  --openrouter-cmd "$OPENROUTER_CMD" \
  $EXTRA_ARGS
```

Where `$EXTRA_ARGS` is whatever followed `--` in `$ARGUMENTS` (empty by
default — the script's own defaults are draft-PR-only, repo-scoped secrets,
`agent claude`, `model claude-sonnet-5`, matching this project's conventions).

If the repo already has `.github/workflows/agent.yml` merged on its default
branch (check with `gh api repos/$repo/contents/.github/workflows/agent.yml
--jq .sha 2>/dev/null` against the default branch), pass `--no-stub` — the
stub already exists; re-running the full script would just open a no-op PR.

## Step 4 — Report

Print:

- Repo name
- What was set: secrets (names only, never values), labels created, the
  Actions "create/approve PRs" setting, and whether a stub PR was opened
- If a PR was opened: its URL, and "review + merge it, then label an issue
  `ai-implement` to trigger the pipeline"
- If `--no-stub` was used because the stub already exists: say so plainly

---

If you hit a blocker (Passbolt resource not found, ambiguous match, the
onboard script erroring on a transient GitHub API failure), retry transient
failures a couple of times before giving up, then report clearly and update
this command for the future.
