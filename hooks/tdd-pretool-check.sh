#!/bin/bash
# PreToolUse hook - sdlc-skill gate + TDD enforcement before editing source files
# Fires before Write/Edit/MultiEdit tools
#
# #436 fix: this hook printed a TDD reminder but never exited 2 — pure prose
# despite tdd_red being CRITICAL in the SDLC scoring rubric. It now blocks
# (exit 2) writes to src/** unless a test file was touched earlier this
# session. This is an edit-ordering proxy, not full "does a failing test
# exist" verification — a bash hook can't run the suite and confirm RED.
# Session-scoped (degrades to allow when session_id is absent — no cross-call
# state to track without it, matching the back-compat stance already taken
# for the nudge below).

# Token-bloat fix: when both project + plugin register this hook, plugin yields.
# Parameter-expansion-safe (no `dirname` dep): `%/*` strips trailing `/file`.
# Fallback `.` when BASH_SOURCE has no slash (direct invocation `bash hook.sh`).
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR="."
# shellcheck disable=SC1091
source "$HOOK_DIR/_find-sdlc-root.sh"
dedupe_plugin_or_project "${BASH_SOURCE[0]}" || exit 0

# Read the tool input (JSON with file_path, content, etc.)
TOOL_INPUT=$(read_stdin_bounded) || {
    # Fail CLOSED: unreadable stdin must not become an allow (#491 P0).
    echo "TDD GATE: could not read hook input within ${SDLC_HOOK_STDIN_TIMEOUT:-5}s. Refusing to allow an unchecked edit." >&2
    exit 2
}

# Extract the file path being edited (requires jq)
FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.tool_input.file_path // empty')

# session_id extraction is jq-independent (same pattern as sdlc-prompt-check.sh
# v1.69.0 — Codex round 1 P1 from that PR proved jq-coupling silently disabled
# the gate when jq was missing/broken). UUIDs are simple strings, no escapes.
SESSION_ID=$(sdlc_json_field "$TOOL_INPUT" session_id)

# Test-file detection: always allowed, and marks "a test was touched" for
# this session so the src/ gate below can unlock. Priority over the src/
# check since many conventions nest tests inside src/ (e.g. src/__tests__/).
if sdlc_is_test_path "$FILE_PATH"; then
  if [ -n "$SESSION_ID" ]; then
    CACHE_DIR="${SDLC_WIZARD_CACHE_DIR:-$HOME/.cache/sdlc-wizard}"
    SAFE_SID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9._-')
    if [ -n "$SAFE_SID" ]; then
      mkdir -p "$CACHE_DIR" 2>/dev/null || true
      : > "$CACHE_DIR/tdd-test-touched-${SAFE_SID}" 2>/dev/null || true
    fi
  fi
  exit 0
fi

# CUSTOMIZE the gated paths with SDLC_TDD_SRC_PATTERN (#236(b)): a
# "|"-separated substring list set in the hook's "command" string, e.g.
# "hooks/|cli/". Unset, the generic src/ rule applies in both its absolute and
# cwd-relative forms (hook-enforcement-436 round 1). The rule lives in
# _find-sdlc-root.sh so the commit-time check in codex-gate-check.sh gates
# exactly the same paths.
#
# This is the ONLY path filter. hooks/hooks.json carries no `if:` pre-filter:
# a second copy of the filter is what silently killed a consumer's TDD hook
# when its code did not live where the `if:` assumed.
SRC_MATCH=0
sdlc_path_is_gated "$FILE_PATH" && SRC_MATCH=1

# Claude Code reads ONE JSON object from stdout, so every notice for this call
# is collected here (already JSON-escaped, "\n"-joined) and printed once.
CONTEXT=""

if [ "$SRC_MATCH" -eq 1 ]; then
  # sdlc-skill gate (Fable ruling 2026-11-08), checked BEFORE the TDD gate.
  # A gated edit needs an sdlc invocation on record for THIS context: the
  # PostToolUse memo, else the transcript (a Skill call, a typed /sdlc, or the
  # invoked_skills re-attachment Claude Code writes after compaction).
  # Active only inside an SDLC project. No transcript_path allows silently
  # (the no-session_id stance); an unreadable one allows with a model-visible
  # notice; a miss blocks with the one ruled line.
  # Opt-out: SDLC_SKILL_GATE=off in the hook's own environment.
  if [ "${SDLC_SKILL_GATE:-}" != "off" ] && find_sdlc_root; then
    TRANSCRIPT_PATH=$(sdlc_json_field "$TOOL_INPUT" transcript_path)
    AGENT_ID=$(sdlc_json_field "$TOOL_INPUT" agent_id)
    if ! sdlc_skill_on_record "$SESSION_ID" "$AGENT_ID" "$TRANSCRIPT_PATH"; then
      case "$SDLC_RECORD" in
        unreadable) CONTEXT=$(sdlc_json_escape "$(sdlc_degraded_notice "$TRANSCRIPT_PATH")") ;;
        miss) echo "$SDLC_SKILL_BLOCK" >&2; exit 2 ;;
      esac
    fi
  fi

  # #436 gate: block implementation-first edits when no test file has been
  # touched yet this session. Degrades to allow without session_id.
  if [ -n "$SESSION_ID" ]; then
    CACHE_DIR="${SDLC_WIZARD_CACHE_DIR:-$HOME/.cache/sdlc-wizard}"
    SAFE_SID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9._-')
    if [ -n "$SAFE_SID" ] && [ ! -f "$CACHE_DIR/tdd-test-touched-${SAFE_SID}" ]; then
      echo "TDD RED REQUIRED: no test file touched yet this session. Write or edit a failing test before implementing in src/." >&2
      exit 2
    fi
  fi

  # Token-bloat fix (v1.70.0): nudge fires once per CC session. Once Claude
  # has the SDLC skill auto-invoked (covers TDD RED/GREEN), the per-Edit
  # nudge becomes duplicate context — typical session has 10-30 src Edits
  # = ~0.5-1.5K wasted tokens. Same atomic-noclobber claim pattern as
  # sdlc-prompt-check.sh BASELINE gate.
  #
  # No-session_id stdin (legacy CC, direct shell tests) → emit every fire,
  # preserving back-compat with existing tests in test-hooks.sh that don't
  # pass session_id.
  SHOULD_EMIT=1
  if [ -n "$SESSION_ID" ]; then
    CACHE_DIR="${SDLC_WIZARD_CACHE_DIR:-$HOME/.cache/sdlc-wizard}"
    SAFE_SID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9._-')
    if [ -n "$SAFE_SID" ]; then
      SENTINEL="$CACHE_DIR/tdd-shown-${SAFE_SID}"
      mkdir -p "$CACHE_DIR" 2>/dev/null || true
      # Atomic claim: subshell `set -C` makes `: > path` create-or-fail.
      # Conditional tree:
      #   - claim succeeds → emit (we won the race)
      #   - claim fails AND file exists → suppress (someone else won)
      #   - claim fails AND file missing → cache unwritable; fall back
      #     to emit so user never loses cold-start nudge.
      if (set -C; : > "$SENTINEL") 2>/dev/null; then
        SHOULD_EMIT=1
      elif [ -f "$SENTINEL" ]; then
        SHOULD_EMIT=0
      else
        SHOULD_EMIT=1
      fi
    fi
  fi

  if [ "$SHOULD_EMIT" -eq 1 ]; then
    CONTEXT="${CONTEXT:+$CONTEXT\\n}TDD CHECK: Are you writing IMPLEMENTATION before a FAILING TEST? If yes, STOP. Write the test first (TDD RED), then implement (TDD GREEN)."
    # Prune sentinels older than 7d so cache doesn't grow forever.
    if [ -n "$SESSION_ID" ] && [ -n "$SAFE_SID" ]; then
      find "$CACHE_DIR" -name 'tdd-shown-*' -type f -mtime +7 -delete 2>/dev/null || true
    fi
  fi
fi

if [ -n "$CONTEXT" ]; then
  # Output additionalContext that Claude will read
  printf '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "%s"}}\n' "$CONTEXT"
fi

# No output = allow the tool to proceed
