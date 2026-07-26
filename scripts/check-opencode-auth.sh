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
