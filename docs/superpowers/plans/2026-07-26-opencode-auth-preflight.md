# OpenCode Auth Preflight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fail the OpenCode agent path fast and legibly when `OPENROUTER_API_KEY` is missing, instead of dying deep inside `opencode run` with a misleading `ProviderModelNotFoundError` (#164).

**Architecture:** A new `scripts/check-opencode-auth.sh` runs at the top of the `Run OpenCode` step. When the key is present it exits 0 and the run proceeds unchanged. When the key is empty it writes an **opencode-shaped `error` event** to the same file `opencode run` would have written, and exits 64. The workflow step then publishes that file as `execution_file` and returns — so the existing degradation chain (`adapt-opencode-result.sh` → `classify-failure.sh` → `ai:failed` + run-report comment) fires untouched and reports the real cause. `classify-failure.sh` gains one regex alternative so the message buckets as `api_auth` (operator intervention, no retry) rather than `bug`.

**Tech Stack:** Bash 5 (`set -euo pipefail`), `jq`, GitHub Actions reusable workflow, Layer-1 fixture tests in `tests/run-script-tests.sh`.

## Background — why the issue's own diagnosis is wrong

Issue #164 claims the `openrouter/` prefix double-nests the model ID. It does not.
`opencode run -m openrouter/openai/gpt-oss-120b` is the **documented** syntax
(<https://opencode.ai/docs/providers/>) — the provider prefix plus the full
OpenRouter model ID, slash and all. Evidence from the failing run's
`opencode-raw-output` artifact (run 30215244908):

```
INFO  service=provider providerID=opencode found
ERROR ... {"providerID":"openrouter","modelID":"openai/gpt-oss-120b","suggestions":["openai/gpt-oss-120b"],"_tag":"ProviderModelNotFoundError"}
```

Only the built-in `opencode` provider was registered — `openrouter` never was,
because `gh secret list -R freaxnx01/freaxnx01.github.io` shows **no
`OPENROUTER_API_KEY`**. The model ID was fine; the provider was absent.

**Do not change the `openrouter/` prefix logic.** Removing it for IDs containing
a slash would break every currently-configured model (`mistralai/*`,
`deepseek/*`, `qwen/*`, `google/*`, `openai/*` — i.e. all of them).

## Global Constraints

- Use Test-Driven Development for every task: write a failing test first, watch it fail, implement minimally to pass, verify green.
- Every new bash script starts with `#!/usr/bin/env bash`, `set -euo pipefail`, `IFS=$'\n\t'`.
- Quote every variable expansion; `[[ ]]` over `[ ]`; `$( )` over backticks.
- CI scripts are env-driven, not flag-driven.
- Exit-code contract: `0` success, `2` required env missing, `64` task-specific failure. Document it in the script header.
- Inline bash added to a YAML step stays ≤5 lines; real logic lives in `scripts/`.
- Do not loosen workflow `permissions:`; do not repin or unpin any action.
- Secrets are never echoed. The preflight tests only ever check *presence*, never the value.
- Layer-1 tests must stay offline (no network, no real `gh`) and the whole suite must run in <5 seconds.
- Reference `#164` in every commit message.

## File Structure

| File | Responsibility |
|---|---|
| `scripts/check-opencode-auth.sh` | **Create.** Preflight: assert `OPENROUTER_API_KEY` is non-empty; on failure synthesize an opencode `error` event into `OUTPUT_FILE` and exit 64. |
| `scripts/classify-failure.sh` | **Modify.** One added alternative in the `api_auth` regex so the preflight message buckets as `api_auth`. |
| `tests/fixtures/opencode-missing-key.json` | **Create.** Canonical preflight output, drives the adapter → classifier chain test. |
| `tests/run-script-tests.sh` | **Modify.** New `check-opencode-auth` section + one chain assertion in the classifier section. |
| `.github/workflows/agent-implement.yml` | **Modify.** Call the preflight at the top of `Run OpenCode`; correct the stale comment about model-ID prefixing. |
| `docs/CONSUMER-SETUP.md` | **Modify.** Troubleshooting entry mapping `ProviderModelNotFoundError` → missing secret. |
| `CHANGELOG.md` | **Modify.** `[Unreleased] → Fixed`. |

---

### Task 1: Preflight script

**Files:**
- Create: `scripts/check-opencode-auth.sh`
- Test: `tests/run-script-tests.sh` (new section, inserted immediately after the `classify-agent` section)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `scripts/check-opencode-auth.sh`, env-driven.
  - Required env: `OUTPUT_FILE` (path to write the synthesized event to).
  - Optional env: `OPENROUTER_API_KEY` (may be empty/unset), `MODEL` (default `unknown`).
  - Exit `0` — key present, nothing written to `OUTPUT_FILE`. Prints `ok: OPENROUTER_API_KEY present`.
  - Exit `2` — `OUTPUT_FILE` unset.
  - Exit `64` — key missing; a single-line JSON `error` event written to `OUTPUT_FILE`; a `::error::` annotation printed to stdout.
  - The exact message text later tasks depend on:
    `AuthError: OPENROUTER_API_KEY is not set for this repository, so opencode cannot register the `openrouter` provider (model: <MODEL>). Add the OPENROUTER_API_KEY secret (see docs/CONSUMER-SETUP.md) or label the issue `agent:claude`.`

- [ ] **Step 1: Write the failing tests**

Insert into `tests/run-script-tests.sh` directly after the `classify-agent` section
(after the `assert_equals "$ec" "2" "missing REPO → exit 2"` line):

```bash
section "check-opencode-auth — OpenRouter key preflight (#164)"

OC_AUTH="$ROOT/scripts/check-opencode-auth.sh"
OC_AUTH_OUT="$(mktemp)"

# Key present → exit 0, nothing synthesized
: > "$OC_AUTH_OUT"
ec="$(run_capture_ec env OUTPUT_FILE="$OC_AUTH_OUT" OPENROUTER_API_KEY=sk-test \
      MODEL=openai/gpt-oss-120b bash "$OC_AUTH")"
assert_equals "$ec" "0" "key present → exit 0"
assert_equals "$(wc -c < "$OC_AUTH_OUT" | tr -d ' ')" "0" "key present → OUTPUT_FILE untouched"

# Key empty → exit 64
: > "$OC_AUTH_OUT"
ec="$(run_capture_ec env OUTPUT_FILE="$OC_AUTH_OUT" OPENROUTER_API_KEY= \
      MODEL=openai/gpt-oss-120b bash "$OC_AUTH")"
assert_equals "$ec" "64" "key empty → exit 64"

# ...and the synthesized event is a valid opencode `error` event
out="$(cat "$OC_AUTH_OUT")"
assert_equals "$(printf '%s' "$out" | jq -r '.type')"            "error"     "missing key → type=error"
assert_equals "$(printf '%s' "$out" | jq -r '.error.name')"      "AuthError" "missing key → error.name=AuthError"
assert_contains "$(printf '%s' "$out" | jq -r '.error.data.message')" \
  'OPENROUTER_API_KEY is not set' "missing key → message names the secret"
assert_contains "$(printf '%s' "$out" | jq -r '.error.data.message')" \
  'openai/gpt-oss-120b' "missing key → message carries the model for provenance"
assert_contains "$(printf '%s' "$out" | jq -r '.error.data.message')" \
  'docs/CONSUMER-SETUP.md' "missing key → message points at the setup doc"

# Key unset entirely (not just empty) → exit 64
: > "$OC_AUTH_OUT"
ec="$(run_capture_ec env OUTPUT_FILE="$OC_AUTH_OUT" MODEL=openai/gpt-oss-120b bash "$OC_AUTH")"
assert_equals "$ec" "64" "key unset → exit 64"

# The secret value is never echoed
out="$(OUTPUT_FILE="$OC_AUTH_OUT" OPENROUTER_API_KEY=sk-supersecret \
       MODEL=openai/gpt-oss-120b bash "$OC_AUTH" 2>&1)"
assert_not_contains "$out" 'sk-supersecret' "key value never printed"

# Missing OUTPUT_FILE → exit 2
ec="$(run_capture_ec env OPENROUTER_API_KEY= bash "$OC_AUTH")"
assert_equals "$ec" "2" "missing OUTPUT_FILE → exit 2"

rm -f "$OC_AUTH_OUT"
```

- [ ] **Step 2: Run the suite to verify the new section fails**

Run: `tests/run-script-tests.sh`
Expected: FAIL — `check-opencode-auth` assertions fail because `scripts/check-opencode-auth.sh` does not exist.

- [ ] **Step 3: Write the minimal implementation**

Create `scripts/check-opencode-auth.sh`:

```bash
#!/usr/bin/env bash
#
# check-opencode-auth.sh — Preflight for the OpenCode agent path (#164).
#
# opencode only registers the `openrouter` provider when it can find an
# OpenRouter credential. With OPENROUTER_API_KEY empty it registers nothing,
# then fails the run with a misleading
#
#   ProviderModelNotFoundError {"providerID":"openrouter","modelID":"openai/gpt-oss-120b"}
#
# which reads like a bad model id rather than a missing secret. This script
# catches that up front and, instead of letting the job die opaquely,
# synthesizes the opencode `error` event that `opencode run` never got to
# write — so adapt-opencode-result.sh → classify-failure.sh → post-run-report.sh
# degrade exactly as they do for any other OpenCode failure, but with an
# actionable message.
#
# Required environment variables:
#   OUTPUT_FILE  Path to write the synthesized event to. Must be the same
#                path the `Run OpenCode` step publishes as `execution_file`.
#
# Optional environment variables:
#   OPENROUTER_API_KEY  The credential under test. May be empty or unset.
#                       Never printed — only its presence is reported.
#   MODEL               OpenRouter model id for the run. Echoed into the
#                       message for provenance. Default: unknown.
#
# Exit codes:
#   0   OPENROUTER_API_KEY is present; OUTPUT_FILE untouched, run may proceed
#   2   required env missing
#   64  OPENROUTER_API_KEY missing; error event written to OUTPUT_FILE
set -euo pipefail
IFS=$'\n\t'

if [[ -z "${OUTPUT_FILE:-}" ]]; then
  printf 'error: OUTPUT_FILE must be set\n' >&2
  exit 2
fi

MODEL="${MODEL:-unknown}"

if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
  printf 'ok: OPENROUTER_API_KEY present\n'
  exit 0
fi

message="AuthError: OPENROUTER_API_KEY is not set for this repository, so opencode cannot register the \`openrouter\` provider (model: ${MODEL}). Add the OPENROUTER_API_KEY secret (see docs/CONSUMER-SETUP.md) or label the issue \`agent:claude\`."

# Same NDJSON `error` event shape opencode itself emits under `--format json`,
# so adapt-opencode-result.sh needs no special case.
jq -nc --arg msg "$message" \
  '{type:"error",timestamp:0,sessionID:"opencode-preflight",
    error:{name:"AuthError",data:{message:$msg}}}' > "$OUTPUT_FILE"

printf '::error::%s\n' "$message"
exit 64
```

- [ ] **Step 4: Run the suite to verify it passes**

Run: `tests/run-script-tests.sh`
Expected: PASS, all assertions in the new section green, no pre-existing test regressed.

- [ ] **Step 5: Lint**

Run: `shellcheck -x -e SC1091 scripts/check-opencode-auth.sh tests/run-script-tests.sh`
Expected: clean, no output.

- [ ] **Step 6: Commit**

```bash
git add scripts/check-opencode-auth.sh tests/run-script-tests.sh
git commit -m "fix(opencode): fail fast when OPENROUTER_API_KEY is missing

Refs #164"
```

---

### Task 2: Classify the preflight failure as `api_auth`

**Files:**
- Modify: `scripts/classify-failure.sh` (the `api_auth` branch, currently line 46)
- Create: `tests/fixtures/opencode-missing-key.json`
- Test: `tests/run-script-tests.sh` (adapter + classifier chain sections)

**Interfaces:**
- Consumes: the exact message string produced by Task 1.
- Produces: `class=api_auth` for a missing-key result — which the existing retry policy already maps to *stop, no retry, operator intervention*.

- [ ] **Step 1: Create the fixture**

`tests/fixtures/opencode-missing-key.json` — one line, byte-for-byte what Task 1's
script writes (regenerate rather than hand-type):

```bash
OUTPUT_FILE=tests/fixtures/opencode-missing-key.json \
MODEL=openai/gpt-oss-120b \
OPENROUTER_API_KEY= bash scripts/check-opencode-auth.sh || true
```

- [ ] **Step 2: Write the failing tests**

Add to the `adapt-opencode-result` section of `tests/run-script-tests.sh`, next to
the existing `opencode-auth-fail.json` assertions:

```bash
# Preflight missing-key event → canonical error result (#164)
out="$(EXECUTION_FILE="$FIXTURES/opencode-missing-key.json" MODEL=openai/gpt-oss-120b bash "$ADAPT_OC")"
assert_equals "$(printf '%s' "$out" | jq -r '.is_error')" "true" \
  "missing-key preflight → is_error true"
assert_contains "$(printf '%s' "$out" | jq -r '.result')" 'OPENROUTER_API_KEY is not set' \
  "missing-key preflight → result carries the actionable message"
```

And to the classifier chain section, next to the existing
`adapter_to_classifier opencode-auth-fail.json` assertion:

```bash
# Missing OPENROUTER_API_KEY is an operator problem, not a retryable one (#164)
out="$(adapter_to_classifier opencode-missing-key.json)"
assert_contains "$out" 'class=api_auth' "missing OPENROUTER_API_KEY → api_auth (no retry)"
```

- [ ] **Step 3: Run to verify the classifier assertion fails**

Run: `tests/run-script-tests.sh`
Expected: FAIL — `missing OPENROUTER_API_KEY → api_auth` reports `class=bug`, because
the current regex only matches `401|403|invalid bearer|authentication error|unauthorized|invalid api key|forbidden`.
(The two adapter assertions should already pass — the adapter is shape-driven and
needs no change. If they fail, the fixture is malformed; fix the fixture, not the adapter.)

- [ ] **Step 4: Extend the regex minimally**

In `scripts/classify-failure.sh`, change the `api_auth` branch condition from:

```bash
elif printf '%s' "$result_text" | grep -qiE '"?401"?|"?403"?|invalid.bearer|authentication.error|unauthorized|invalid.api.key|forbidden'; then
  # `403` / `forbidden` / `invalid api key` cover OpenRouter auth-fail
  # variants alongside Claude's `401` / `invalid bearer`.
```

to:

```bash
elif printf '%s' "$result_text" | grep -qiE '"?401"?|"?403"?|invalid.bearer|authentication.error|unauthorized|invalid.api.key|forbidden|api.key.is.not.set'; then
  # `403` / `forbidden` / `invalid api key` cover OpenRouter auth-fail
  # variants alongside Claude's `401` / `invalid bearer`;
  # `api.key.is.not.set` catches the missing-secret preflight (#164) —
  # an unset key is operator intervention, same as a rejected one.
```

- [ ] **Step 5: Run to verify it passes**

Run: `tests/run-script-tests.sh`
Expected: PASS, full suite green, still under 5 seconds.

- [ ] **Step 6: Lint**

Run: `shellcheck -x -e SC1091 scripts/classify-failure.sh tests/run-script-tests.sh`
Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add scripts/classify-failure.sh tests/fixtures/opencode-missing-key.json tests/run-script-tests.sh
git commit -m "fix(classify-failure): bucket a missing OPENROUTER_API_KEY as api_auth

Refs #164"
```

---

### Task 3: Wire the preflight into the workflow

**Files:**
- Modify: `.github/workflows/agent-implement.yml` — the `Run OpenCode` step (`id: opencode_run`, around lines 444–499)

**Interfaces:**
- Consumes: `scripts/check-opencode-auth.sh` from Task 1 (`OUTPUT_FILE` env, exit 64 on missing key).
- Produces: unchanged step outputs (`execution_file`, `exit_code`) on both paths, so every downstream step keeps working with no expression changes.

- [ ] **Step 1: Insert the preflight**

In the `run:` block of `Run OpenCode`, immediately after the `log_file=` assignment
and before the `opencode 1.x CLI` comment, insert:

```bash
          # Preflight (#164): with OPENROUTER_API_KEY empty, opencode registers
          # no `openrouter` provider and dies with a ProviderModelNotFoundError
          # that reads like a bad model id. Short-circuit into the normal
          # degradation path with an actionable AuthError instead.
          if ! OUTPUT_FILE="$out_file" bash .claude-pipeline/scripts/check-opencode-auth.sh; then
            printf 'execution_file=%s\n' "$out_file" >> "$GITHUB_OUTPUT"
            printf 'exit_code=64\n' >> "$GITHUB_OUTPUT"
            exit 0
          fi
```

`MODEL` is already in the step's `env:`, so the message picks up the model with no
extra wiring. `exit 0` — not a failure — because the job must continue on to
`Adapt OpenCode result`, `Classify failure`, and `Post run report`, which is what
turns this into an `ai:failed` label plus an explanatory issue comment.

- [ ] **Step 2: Correct the stale model-ID comment**

In the same step, replace this comment block:

```bash
          # Triage emits OpenRouter model ids (e.g. mistralai/mistral-large-latest,
          # google/gemma-4-31b-it); opencode needs the `openrouter/` provider
          # prefix, so prepend it unless already present.
```

with:

```bash
          # Triage emits OpenRouter model ids (e.g. mistralai/mistral-large-latest,
          # google/gemma-4-31b-it); opencode needs the `openrouter/` provider
          # prefix, so prepend it unless already present. Ids that already carry
          # a provider slug are prefixed too — `openrouter/openai/gpt-oss-120b`
          # is the documented form (opencode.ai/docs/providers), NOT a
          # double-prefix bug. See #164 before "fixing" this.
```

- [ ] **Step 3: Lint the workflow**

Run: `actionlint .github/workflows/agent-implement.yml`
Expected: clean. If `actionlint` is not installed locally, run `just lint`; if that is
also unavailable, note it and rely on the `lint.yml` CI job.

- [ ] **Step 4: Verify the shell fragment in isolation**

Confirm the short-circuit produces exactly the outputs downstream expects:

```bash
tmp="$(mktemp -d)"
GITHUB_OUTPUT="$tmp/out" out_file="$tmp/opencode-output.json"
export GITHUB_OUTPUT
if ! OUTPUT_FILE="$out_file" MODEL=openai/gpt-oss-120b OPENROUTER_API_KEY= \
     bash scripts/check-opencode-auth.sh; then
  printf 'execution_file=%s\n' "$out_file" >> "$GITHUB_OUTPUT"
  printf 'exit_code=64\n' >> "$GITHUB_OUTPUT"
fi
cat "$GITHUB_OUTPUT"
EXECUTION_FILE="$out_file" MODEL=openai/gpt-oss-120b bash scripts/adapt-opencode-result.sh | jq -r '.is_error, .result'
rm -rf "$tmp"
```

Expected: `$GITHUB_OUTPUT` holds `execution_file=…` and `exit_code=64`; the adapter
prints `true` followed by the actionable message.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/agent-implement.yml
git commit -m "fix(agent-implement): preflight OpenRouter auth before opencode run

Refs #164"
```

---

### Task 4: Documentation

**Files:**
- Modify: `docs/CONSUMER-SETUP.md` (the OpenRouter secret section, around lines 340–370)
- Modify: `CHANGELOG.md` (`[Unreleased]`)

**Interfaces:**
- Consumes: the behavior from Tasks 1–3.
- Produces: no code interface.

- [ ] **Step 1: Add the troubleshooting entry**

In `docs/CONSUMER-SETUP.md`, immediately after the paragraph describing how the
OpenCode step reads `OPENROUTER_API_KEY`, add:

```markdown
> **Troubleshooting — `ProviderModelNotFoundError` / "Model not found: openrouter/…".**
> This is almost always a **missing `OPENROUTER_API_KEY`**, not a bad model id.
> Without a credential, opencode never registers the `openrouter` provider, so
> every model under it looks unknown. The `openrouter/<model-id>` form is
> correct even when the id already contains a slash — `openrouter/openai/gpt-oss-120b`
> is what opencode documents. Since #164 the pipeline preflights the secret and
> fails with an explicit `OPENROUTER_API_KEY is not set` message instead.
> Verify with `gh secret list -R <owner>/<repo>`.
```

- [ ] **Step 2: Add the changelog entry**

Under `## [Unreleased]` → `### Fixed` in `CHANGELOG.md` (create the `### Fixed`
subsection if `[Unreleased]` doesn't have one yet):

```markdown
- **OpenCode runs now fail fast on a missing `OPENROUTER_API_KEY`** (#164).
  Previously the run reached `opencode run`, which silently skipped registering the
  `openrouter` provider and died with a misleading `ProviderModelNotFoundError`
  that looked like a model-id bug. `scripts/check-opencode-auth.sh` now preflights
  the secret and emits an actionable `AuthError`, classified `api_auth` (no retry).
  The `openrouter/` model prefix is unchanged — it was never the cause.
```

- [ ] **Step 3: Lint the docs**

Run: `markdownlint-cli2 docs/CONSUMER-SETUP.md CHANGELOG.md docs/superpowers/plans/2026-07-26-opencode-auth-preflight.md`
Expected: clean. If the tool isn't installed, run `just lint` or note the skip.

- [ ] **Step 4: Commit**

```bash
git add docs/CONSUMER-SETUP.md CHANGELOG.md
git commit -m "docs(opencode): document the missing-key failure mode

Refs #164"
```

---

## Final verification

- [ ] `tests/run-script-tests.sh` — full suite green, <5s
- [ ] `shellcheck -x -e SC1091 $(find scripts tests -type f -name '*.sh' | sort)` — clean
- [ ] `actionlint .github/workflows/agent-implement.yml` — clean
- [ ] `git log --oneline origin/main..HEAD` — four commits, each referencing #164

## Out of scope (captured, not acted on)

- Setting `OPENROUTER_API_KEY` on `freaxnx01/freaxnx01.github.io` — an operator
  action, not a code change. Re-run issue #4 there once the secret exists.
- Whether OpenCode model IDs should be stored fully-qualified per `model:*` label
  instead of derived by prefixing (#164's second suggestion). The prefixing works;
  this would be a refactor with no behavior change.
- Layer-2 (`act`) coverage of the preflight short-circuit. The Layer-1 chain test
  plus the isolated fragment check in Task 3 Step 4 cover the contract.
