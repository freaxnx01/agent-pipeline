#!/usr/bin/env bash
#
# AGENT-resolution mock for self-fix-pr.sh's FIX_LIB_DIR test seam —
# proves AGENT=opencode resolves specifically to this file, not the
# claude sibling.
set -euo pipefail
IFS=$'\n\t'
printf 'fixed-by-opencode\n' >> file.txt
