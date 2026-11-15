#!/bin/bash
# PreToolUse hook — advisory context-size reminder to save a handoff.
#
# Uses the session transcript's size as a proxy for context use. Once it
# passes SDLC_HANDOFF_THRESHOLD_BYTES (default 800000), prints one reminder,
# then writes a per-session marker in $TMPDIR so it never repeats.
# The reminder goes to stderr and, because a PreToolUse hook's stderr at exit
# 0 does not reach the model, also as additionalContext on stdout.
#
# Non-blocking: always exits 0.

HOOK_DIR="${BASH_SOURCE[0]%/*}"
[ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR="."
# shellcheck disable=SC1091
source "$HOOK_DIR/_find-sdlc-root.sh"
dedupe_plugin_or_project "${BASH_SOURCE[0]}" || { read_stdin_bounded > /dev/null || true; exit 0; }

INPUT=$(read_stdin_bounded) || exit 0

json_field() {
    printf '%s' "$INPUT" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

SESSION=$(json_field session_id | tr -cd 'A-Za-z0-9_-')
[ -n "$SESSION" ] || exit 0
MARKER="${TMPDIR:-/tmp}/sdlc-handoff-check-$SESSION"
[ -e "$MARKER" ] && exit 0

TRANSCRIPT=$(json_field transcript_path)
[ -f "$TRANSCRIPT" ] || exit 0

THRESHOLD="${SDLC_HANDOFF_THRESHOLD_BYTES:-800000}"
[ "$THRESHOLD" -ge 1 ] 2>/dev/null || THRESHOLD=800000
SIZE=$(wc -c < "$TRANSCRIPT" | tr -d ' ')
[ "$SIZE" -gt "$THRESHOLD" ] || exit 0

# Claim the marker atomically: noclobber opens with O_EXCL, so of concurrent
# calls in one session exactly one creates it and reminds.
( set -C; : > "$MARKER" ) 2>/dev/null || exit 0
MSG="Context is high. Consider running /conduct handoff to save state for the next session."
echo "$MSG" >&2
printf '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "%s"}}\n' "$MSG"
exit 0
