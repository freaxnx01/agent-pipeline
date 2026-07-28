# AGENT-NOTES

Repo-local, agent-facing context for `agent-workflow` that the generated
`CLAUDE.md` can't carry (it is rebuilt from `.ai/base-instructions.md` +
`.ai/stacks/ci.md` by `/sync-ai-instructions` and any edit there is overwritten).

---

## Branch protection: `main` is protected, but admins are exempt

`CLAUDE.md` states that `main` requires passing CI, at least one PR review, and no
direct push. That is configured correctly — **but it does not apply to the repo
owner.**

Current settings (classic branch protection; no rulesets):

| Setting | Value |
|---|---|
| Required status check | `gate-selftest` (GitHub Actions) |
| ↳ strict | true — branch must be up to date before merge |
| Required approving reviews | 1 |
| **Enforce on admins** | **false** ← the exemption |
| Force pushes / deletions | blocked |
| Signatures / linear history / conversation resolution | not required |

Because `enforce_admins` is `false`, a push to `main` with an admin token succeeds
even when the required check hasn't reported yet. GitHub prints:

```text
remote: Bypassed rule violations for refs/heads/main:
remote: - Required status check "gate-selftest" is expected.
```

**This is not an error and not a failed gate.** The push lands, and `gate-selftest`
then runs against the new commit on `main` — check its result rather than assuming
the bypass skipped it.

### When a direct push is acceptable

**Never. Every change goes through a PR, including docs-only ones.** The
trivial-edit exception that used to live in `.ai/base-instructions.md` is being
removed upstream (freaxnx01/ai-instructions#22); this repo's vendored copy still
shows the old wording until someone re-runs `/sync-ai-instructions`. Follow this
section, not that sentence.

The reason is the ordering above: the push lands *first* and the required check
reports afterwards. That makes `gate-selftest` a postmortem rather than a gate — it
can tell you `main` is broken, but it cannot stop it from getting there. A PR
inverts that for the price of one extra command.

A direct push also breaks any open PR whose branch is now behind, since the
required check is `strict` (branch must be up to date before merge). On 2026-07-28
commit `0b81dfd` did exactly this to PR #184, which then needed
`gh pr update-branch` plus a full re-run of CI before it could merge — more work
than the PR it avoided.

The protection is a guardrail against automation mistakes, not against the owner —
so the bypass stays *available* for a genuine emergency (a broken `main` that needs
an immediate revert). Outside that, if bypass messages start appearing at all,
treat it as a signal to set `enforce_admins: true`.

---

## Pushing requires a token bridge

The ambient git credential on this machine may resolve to the wrong GitHub account
(symptom: `Permission to freaxnx01/agent-workflow.git denied to <other-account>`,
HTTP 403). The correct token lives in a direnv `.envrc` one level up from the repos
directory, and the agent shell does not trigger direnv hooks.

Git's credential helper reads `GITHUB_TOKEN`, while the `.envrc` provides `GH_TOKEN`,
so bridge the name inline:

```bash
direnv exec ~/repos/github/freaxnx01 \
  bash -c 'GITHUB_TOKEN="$GH_TOKEN" git push origin main'
```

Prefer this over suggesting an interactive `gh auth login`.
