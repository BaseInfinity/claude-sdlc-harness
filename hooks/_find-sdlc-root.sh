#!/bin/bash
# Shared helper: walk up from CWD to find nearest SDLC.md + TESTING.md pair
# Sourced by sdlc-prompt-check.sh and instructions-loaded-check.sh
# Fixes #171: false-positive "SETUP NOT COMPLETE" in monorepos / nested projects

# find_sdlc_root — walks up from pwd, stops at $HOME (exclusive)
# Sets SDLC_ROOT to the found directory, or empty string if not found
find_sdlc_root() {
    local check_dir
    check_dir="$(pwd)"
    SDLC_ROOT=""
    while [ "$check_dir" != "/" ] && [ "$check_dir" != "$HOME" ] && [ -n "$check_dir" ]; do
        if [ -f "$check_dir/SDLC.md" ] && [ -f "$check_dir/TESTING.md" ]; then
            SDLC_ROOT="$check_dir"
            return 0
        fi
        check_dir="$(dirname "$check_dir")"
    done
    return 1
}

# find_partial_sdlc_root — walks up looking for EITHER SDLC.md OR TESTING.md
# Used to detect partial setup (one file exists but not both) vs not-an-SDLC-project
find_partial_sdlc_root() {
    local check_dir
    check_dir="$(pwd)"
    SDLC_ROOT=""
    while [ "$check_dir" != "/" ] && [ "$check_dir" != "$HOME" ] && [ -n "$check_dir" ]; do
        if [ -f "$check_dir/SDLC.md" ] || [ -f "$check_dir/TESTING.md" ]; then
            SDLC_ROOT="$check_dir"
            return 0
        fi
        check_dir="$(dirname "$check_dir")"
    done
    return 1
}

# dedupe_plugin_or_project — token-bloat fix.
# When a hook is registered via BOTH the project's `.claude/settings.json` AND
# a locally-installed wizard plugin (e.g., maintainer dogfooding the wizard
# while also having `~/.claude/plugins-local/sdlc-wizard-wrap/`), the same
# script fires twice per event = 2× tokens per prompt, 2× hook output noise.
#
# Resolution: plugin invocation yields if the project also registers the
# same hook by name. Project registration always wins (user-explicit).
# Consumer plugin-only installs (no project settings.json) still fire normally.
#
# Plugin path heuristic: $0 contains "/plugins-local/" or "/plugins/cache/".
#
# Usage:
#   source _find-sdlc-root.sh
#   dedupe_plugin_or_project || exit 0   # plugin yields when project registered
#
# Args (optional, for tests): $1 script_path, $2 project_dir
# Returns: 0 = proceed, 1 = yield (caller should exit 0).
#
# Codex review hardening (DEDUPE-001/002):
# - Uses parameter expansion (${path##*/}) instead of `basename` — survives
#   PATH-restricted environments. Falsely emitting `basename: command not found`
#   would corrupt the rc=1 (yield) signal.
# - Matches the script name only inside a `"command"` JSON field, not anywhere
#   in the settings file. Otherwise a basename mentioned in `permissions.allow`
#   or a comment would falsely trigger yield (plugin would skip when project
#   never actually registers the hook).
dedupe_plugin_or_project() {
    local script_path="${1:-${BASH_SOURCE[1]:-$0}}"
    local project_dir="${2:-${CLAUDE_PROJECT_DIR:-.}}"

    case "$script_path" in
        */plugins-local/*|*/plugins/cache/*)
            local proj_settings="$project_dir/.claude/settings.json"
            [ -f "$proj_settings" ] || return 0

            # Parameter-expansion basename: ${path##*/} strips up to last /.
            # If no / in path, returns path itself (defensive — caller passed
            # bare filename).
            local script_name="${script_path##*/}"
            [ -n "$script_name" ] || return 0

            # Match only inside a "command" JSON registration so a basename
            # appearing in permissions.allow / comments / unrelated sections
            # doesn't falsely yield. Pattern: `"command"` followed by colon,
            # any whitespace, optional quotes, anything, then the basename.
            # Example matches:
            #   "command": "$CLAUDE_PROJECT_DIR/hooks/sdlc-prompt-check.sh"
            #   "command":"hooks/sdlc-prompt-check.sh"
            # Does NOT match:
            #   "Bash(./hooks/sdlc-prompt-check.sh *)"  (in permissions.allow)
            if grep -qE '"command"[[:space:]]*:[[:space:]]*"[^"]*'"$script_name"'"' "$proj_settings" 2>/dev/null; then
                return 1  # yield — project will fire its own copy
            fi
            ;;
    esac
    return 0  # proceed
}

# Read stdin without ever blocking forever.
#
# #491 Class 2: every hook slurped stdin with `$(cat)`, guarded only by
# `[ ! -t 0 ]` — "is stdin not a terminal". A unix socket is not a terminal,
# so the guard passes and `cat` waits for an EOF that never arrives. Observed
# live: hooks/sdlc-prompt-check.sh alive 10h19m against a 10-second hook
# timeout, `lsof` showing `0u unix`. The documented timeout did not reap it.
#
# Usage:  STDIN_JSON=$(read_stdin_bounded)
# Drain:  read_stdin_bounded > /dev/null
#
# NEVER use `timeout(1)` here: it does not exist on macOS, and this repo has
# already shipped two "0 failing" reports from suites that ran zero tests
# because of it. bash's builtin `read -t` is portable to bash 3.2.
#
# RETURN CODE IS LOAD-BEARING — callers MUST check it:
#   0 = stdin was read to EOF. The payload is complete.
#   1 = the deadline expired first. The payload is INCOMPLETE, and on bash 3.2
#       an unterminated final line was discarded entirely, so "incomplete" can
#       mean "empty" even though the writer sent a full payload.
#
# A GATE MUST FAIL CLOSED ON 1. Codex review of the first version of this
# helper (2026-08-05, P0) proved why: a complete single-line payload with no
# trailing newline, on a pipe held open, produced empty input, and
# codex-gate-check.sh, tdd-pretool-check.sh and merge-gate-check.sh all fell
# through to exit 0 — a silent policy bypass. That is strictly worse than the
# hang this helper exists to fix. A gate that cannot read its input cannot
# make a safe decision; it must deny.
#
# The deadline is OVERALL, not per-read. The first version passed `-t` to each
# `read`, so every newline restarted the clock and a slow trickle could keep a
# hook alive indefinitely (same review, P1).
#
# CLOCK PRECISION, and why the budget is limit+1:
# bash 3.2 has no sub-second clock — `read -t` rejects fractional timeouts and
# EPOCHREALTIME does not exist — so elapsed time is measured with $SECONDS,
# which is integer and NOT aligned to when this function started. A payload
# that EOFs 0.2s in can therefore read as "1 second elapsed". Round-2 review
# measured the consequence directly: with the deadline at `limit`, a clean EOF
# at 0.20s against SDLC_HOOK_STDIN_TIMEOUT=1 falsely blocked 4 of 15 runs, and
# a clean EOF at 4.20s against the 5s default falsely blocked 1 of 5.
#
# Fix: compare against limit+1. Since $SECONDS can overstate true elapsed time
# by at most one second, requiring limit+1 guarantees at least `limit` real
# seconds passed before anything is declared incomplete — the configured
# contract is now a floor that is always honoured. The cost is that a genuine
# stall is detected somewhere in [limit, limit+1) rather than exactly at limit,
# which is immaterial: the purpose is bounding an unbounded hang, not precision.
read_stdin_bounded() {
    local limit="${SDLC_HOOK_STDIN_TIMEOUT:-5}"
    local line acc="" rc remaining budget
    local start=$SECONDS

    [ "$limit" -ge 1 ] 2>/dev/null || limit=5
    budget=$(( limit + 1 ))

    [ -t 0 ] && return 0

    while :; do
        remaining=$(( budget - (SECONDS - start) ))
        if [ "$remaining" -le 0 ]; then
            printf '%s' "$acc"
            return 1            # overall deadline hit — INCOMPLETE
        fi

        # `|| rc=$?` not `read; rc=$?` — under `set -e` a non-zero read
        # terminates the script before the next line ever runs.
        rc=0
        IFS= read -r -t "$remaining" line || rc=$?

        if [ "$rc" -eq 0 ]; then
            acc="$acc$line
"
            continue
        fi

        # Non-zero. On bash 4+ a timeout returns >128, but on bash 3.2 (the
        # macOS default) BOTH timeout and clean EOF return 1 — measured:
        #   timeout w/ partial data : rc=1, line=""            (data lost)
        #   clean EOF w/ partial data: rc=1, line="partial..."  (data kept)
        # So the return code cannot discriminate, and an earlier version of
        # this helper that branched on `rc > 128` never fail-closed on macOS
        # at all. Elapsed time is the only reliable discriminator.
        [ -n "$line" ] && acc="$acc$line"
        printf '%s' "$acc"

        if [ "$rc" -gt 128 ] || [ $(( SECONDS - start )) -ge "$budget" ]; then
            return 1            # deadline consumed — INCOMPLETE
        fi
        return 0                # returned early — clean EOF, COMPLETE
    done
}

# ---------------------------------------------------------------------------
# The sdlc-skill gate (Fable ruling 2026-11-08). Shared by tdd-pretool-check.sh
# (edit time) and codex-gate-check.sh (commit time), so the two cannot drift
# apart.
# ---------------------------------------------------------------------------

# sdlc_json_field <json> <key> — first string value of KEY, jq-free, the same
# extraction the hooks already use for session_id. An occurrence quoted inside
# another field's string value is JSON-escaped (\"key\") and cannot match.
sdlc_json_field() {
    printf '%s' "$1" \
        | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
        | head -1 \
        | sed 's/.*"\([^"]*\)"$/\1/'
}

# sdlc_json_escape <text> — escape \ and " for embedding in a JSON string.
sdlc_json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# sdlc_is_test_path <path> — the TDD hook's test-file convention.
sdlc_is_test_path() {
    [[ "$1" =~ (\.test\.|\.spec\.|/__tests__/|/tests?/|/test_|^test_) ]]
}

# sdlc_path_is_gated <path> — a non-test path matching SDLC_TDD_SRC_PATTERN
# (a "|"-separated substring list, #236(b)) or, when unset, the generic src/
# rule. Absolute (edit payloads) and repo-relative (staged paths) both match.
sdlc_path_is_gated() {
    local path="$1" _p _patterns
    [ -n "$path" ] || return 1
    sdlc_is_test_path "$path" && return 1
    if [ -n "${SDLC_TDD_SRC_PATTERN:-}" ]; then
        IFS='|' read -ra _patterns <<< "$SDLC_TDD_SRC_PATTERN"
        for _p in "${_patterns[@]}"; do
            [ -n "$_p" ] && [[ "$path" == *"$_p"* ]] && return 0
        done
        return 1
    fi
    [[ "$path" == *"/src/"* || "$path" == "src/"* ]]
}

# The transcript records that count as "sdlc was invoked in this context":
#   - a Skill tool_use naming sdlc or <ns>:sdlc
#   - a typed /sdlc or /<ns>:sdlc: a user record whose content OPENS with the
#     command tags (either tag order), not prose that merely quotes them
#   - an invoked_skills attachment naming sdlc, which Claude Code re-attaches,
#     skill body included, after every compact_boundary
# A Read of SKILL.md does not count: it is not re-attached after compaction.
# Text quoted inside any other string field is JSON-escaped, so none of these
# unescaped shapes can match it.
SDLC_SKILL_RE='"name":"Skill","input":\{[^{}]*"skill":"([A-Za-z0-9_.-]+:)?sdlc"'
SDLC_SLASH_RE='"role":"user","content":"(<command-message>[^"<]*</command-message>\\n)?<command-name>/([A-Za-z0-9_.-]+:)?sdlc</command-name>'
SDLC_ATTACH_RE='"type":"invoked_skills","skills":\[.*\{"name":"([A-Za-z0-9_.-]+:)?sdlc","path":"'

# sdlc_skill_on_record <agent_id> <transcript_path>
# Greps THIS context's own transcript: the payload's transcript_path for the
# main session, or for a subagent ${transcript_path%.jsonl}/subagents/
# agent-<agent_id>.jsonl. A subagent's payload names the PARENT's transcript
# (observed live, CC 2.1.289), but it does not get the parent's skill body,
# so the parent's record never counts for it, nor a subagent's for the parent.
# The Skill tool_use line is on disk by the next tool's PreToolUse (observed
# live, 5/5 main and 4/4 subagent), so no other record is kept.
# Sets SDLC_RECORD to hit | miss | nopath | unreadable and SDLC_RECORD_PATH to
# the file read. Returns 0 only on hit.
sdlc_skill_on_record() {
    local aid tp="$2"
    aid=$(printf '%s' "$1" | tr -cd 'A-Za-z0-9._-')
    SDLC_RECORD=miss
    SDLC_RECORD_PATH="$tp"
    if [ -z "$tp" ]; then
        SDLC_RECORD=nopath
        return 1
    fi
    [ -z "$aid" ] || SDLC_RECORD_PATH="${tp%.jsonl}/subagents/agent-${aid}.jsonl"
    if [ ! -f "$SDLC_RECORD_PATH" ] || [ ! -r "$SDLC_RECORD_PATH" ]; then
        SDLC_RECORD=unreadable
        return 1
    fi
    # The fixed-string prefilter keeps a 75 MB transcript near 1.5 s; the
    # regexes then run only on candidate lines.
    if LC_ALL=C grep -F -e '"name":"Skill"' -e '<command-name>/' -e '"type":"invoked_skills"' -- "$SDLC_RECORD_PATH" 2>/dev/null \
        | LC_ALL=C grep -qE -e "$SDLC_SKILL_RE" -e "$SDLC_SLASH_RE" -e "$SDLC_ATTACH_RE"; then
        SDLC_RECORD=hit
        return 0
    fi
    return 1
}

# The one block line, verbatim from the ruling.
SDLC_SKILL_BLOCK='SDLC SKILL REQUIRED: invoke Skill(skill="sdlc") once this session, then retry.'

# sdlc_degraded_notice <transcript_path> — the model-visible fail-open text.
sdlc_degraded_notice() {
    printf 'SDLC gate degraded: cannot read %s; invoke Skill(sdlc) now if not loaded' "$1"
}
