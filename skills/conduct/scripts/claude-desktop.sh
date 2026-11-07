#!/bin/bash
# Start a Claude Desktop Code session from a terminal and submit its first
# prompt without a human, by pressing NAMED controls through macOS
# Accessibility. Never sends a keystroke blind.
#
# Usage:
#   claude-desktop.sh FOLDER PROMPT_FILE       open, trust if asked, send
#   claude-desktop.sh --dry-run FOLDER PROMPT_FILE   print the deep link only
#   claude-desktop.sh --no-trust FOLDER PROMPT_FILE  never press Trust; exit 4
#                                                    if the folder needs it
#
# Observed on Claude.app 4.23118.0. Requires the terminal to hold the macOS
# Accessibility permission. Exit codes: 0 sent, 1 usage, 2 control not found
# or script error, 3 wrong folder or composer does not hold this prompt
# (refuses to send), 4 folder needs Trust and --no-trust was given. Prints
# TRUSTED_SENT instead of SENT when it pressed Trust.
set -e

DRY=0
TRUST=1
while :; do
    case "${1:-}" in
        --dry-run) DRY=1; shift ;;
        --no-trust) TRUST=0; shift ;;
        *) break ;;
    esac
done
FOLDER="${1:-}"
PROMPT_FILE="${2:-}"

case "$FOLDER" in
    /*) ;;
    *) echo "claude-desktop: FOLDER must be an absolute path" >&2; exit 1 ;;
esac
if [ ! -f "$PROMPT_FILE" ]; then
    echo "claude-desktop: PROMPT_FILE not found: $PROMPT_FILE" >&2
    exit 1
fi

URL=$(python3 - "$FOLDER" "$PROMPT_FILE" <<'PY'
import sys, urllib.parse
folder = sys.argv[1]
prompt = open(sys.argv[2], encoding="utf-8").read().rstrip("\n")
q = urllib.parse.quote
print("claude://code/new?folder=" + q(folder, safe="") + "&q=" + q(prompt, safe="") + "&source=services")
PY
)

if [ "$DRY" = 1 ]; then
    echo "$URL"
    exit 0
fi

PID=$(pgrep -x Claude | head -1)
if [ -z "$PID" ]; then
    open -a Claude
    sleep 8
    PID=$(pgrep -x Claude | head -1)
fi
if [ -z "$PID" ]; then echo "claude-desktop: Claude is not running" >&2; exit 2; fi

open "$URL"
sleep 5

# The AX half holds native element handles, verifies the folder (trust dialog
# path, then the session's Folder label) and the exact prompt, then presses
# "Send" in that same window.
HERE=$(cd "$(dirname "$0")" && pwd)
# claude-desktop.py owns the result-to-exit-code table; a crash becomes 2.
RC=0
RESULT=$(python3 "$HERE/claude-desktop.py" "$PID" "$FOLDER" "$PROMPT_FILE" "$TRUST") || RC=$?

echo "claude-desktop: ${RESULT:-ERROR}"
case "$RC" in
    0|3|4) exit "$RC" ;;
    *) exit 2 ;;
esac
