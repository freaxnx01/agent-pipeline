#!/usr/bin/env bash
#
# detect-forge.sh — sourced, not executed.
#   detect_forge   echoes "github <host>" | "forgejo <host>" | "unknown <host>"
#                  based on the cwd's `origin` remote.
set -euo pipefail
IFS=$'\n\t'

detect_forge() {
  local host
  host=$(git remote get-url origin 2>/dev/null | sed -E 's#^[a-zA-Z]+://##; s#^[^@/]*@##; s#[:/].*##')
  if gh auth token --hostname "$host" >/dev/null 2>&1; then
    echo "github $host"
  elif tea logins list 2>/dev/null | grep -qiF "$host"; then
    echo "forgejo $host"
  elif [ "$host" = "github.com" ]; then
    echo "github $host"
  else
    echo "unknown $host"
  fi
}
