#!/usr/bin/env bash
#
# AGENT-resolution mock for self-fix-pr.sh's FIX_LIB_DIR test seam —
# proves AGENT=claude resolves specifically to this file, not the
# opencode sibling.
set -euo pipefail
IFS=$'\n\t'
printf 'fixed-by-claude\n' >> file.txt
