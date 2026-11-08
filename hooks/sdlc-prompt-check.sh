#!/bin/bash
# Light SDLC hook - baseline reminder every prompt (~100 tokens)
# Full guidance in skill: .claude/skills/sdlc/

# Walk up from CWD to find nearest SDLC.md + TESTING.md (#171: monorepo support)
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HOOK_DIR/_find-sdlc-root.sh"

# Token-bloat fix: when both project + plugin register this hook, plugin yields.
# Prevents 2× SDLC BASELINE print per UserPromptSubmit (~300 tokens doubled).
# Pass real script path explicitly (not $0) so the dedupe heuristic recognizes
# plugin paths even when the script is sourced or invoked via aliases.
dedupe_plugin_or_project "${BASH_SOURCE[0]}" || exit 0

# Roadmap #224: opt-in fires-once instrumentation. CC 2.1.118 shipped a fix for
# prompt hooks double-firing when a verifier subagent itself made tool calls.
# When SDLC_HOOK_FIRE_LOG is set, append one tab-separated record per real
# invocation (post-dedupe). Maintainer can compare line count against prompt
# count to verify the CC fix in real sessions. See CLAUDE_CODE_SDLC_WIZARD.md →
# "Verifying Prompt-Hook-Fires-Once" for the procedure.
if [ -n "${SDLC_HOOK_FIRE_LOG:-}" ]; then
    {
        printf '%s\t%s\tsdlc-prompt-check\n' "$(date +%s)" "$$" >> "$SDLC_HOOK_FIRE_LOG"
    } 2>/dev/null || true
fi

# CWD walk-up finds nearest SDLC project (#173: silent exit for non-SDLC dirs)
if find_sdlc_root; then
    PROJECT_DIR="$SDLC_ROOT"
elif find_partial_sdlc_root; then
    # Partial setup — one file exists but not both. Warn about missing files
    PROJECT_DIR="$SDLC_ROOT"
else
    # Not an SDLC project at all — exit silently
    exit 0
fi

# #236(b): the ROADMAP #195 effort auto-bump detector that used to live here
# (phrase-matching low-confidence signals, loud '/effort xhigh' nudge after
# ≥2 in 30 min) was removed — never fired in ~2 months of live use, the
# largest unproven component in this file. SESSION_ID is still needed below
# for the BASELINE fires-once sentinel, so stdin is still read for it.
SESSION_ID=""
if [ ! -t 0 ]; then
    # Advisory hook, not a gate: degrade to empty rather than block a prompt.
    STDIN_JSON=$(read_stdin_bounded) || STDIN_JSON=""
    if [ -n "$STDIN_JSON" ]; then
        # session_id is a UUID-shaped string with no escapable content
        # in CC's stdin contract — regex extraction is sufficient.
        # `tr -cd` later strips anything filename-unsafe, so a malformed
        # input cannot escape the cache dir.
        SESSION_ID=$(printf '%s' "$STDIN_JSON" \
            | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' \
            | head -1 \
            | sed 's/.*"\([^"]*\)"$/\1/')
    fi
fi

if [ ! -s "$PROJECT_DIR/SDLC.md" ] || [ ! -s "$PROJECT_DIR/TESTING.md" ]; then
    cat << 'SETUP_REQUIRED'
SETUP NOT COMPLETE: SDLC.md and/or TESTING.md are missing.

MANDATORY FIRST ACTION: Invoke Skill tool, skill="claude-setup-wizard"
Do NOT proceed with any other task until setup is complete.
Tell the user: "I need to run the SDLC setup wizard first to configure your project."
SETUP_REQUIRED
    exit 0
fi

# Token-bloat fix: BASELINE block fires once per CC session (~250 tok × 50
# prompts = ~12K wasted tokens before this gate). Once Claude has the SDLC
# skill auto-invoked (covers TodoWrite/confidence/workflow), this static
# block is duplicate context. Sentinel is per-session_id so a fresh CC
# session re-emits the cold-start nudge. Without session_id (legacy CC, or
# direct shell tests with no JSON stdin), behavior is unchanged — emits
# every fire. SETUP-not-complete + EFFORT-bump branches above are NOT
# gated; they're dynamic state warnings that must fire every prompt.
#
# Concurrency: claim is atomic via `set -C` (noclobber) — the redirect
# `: > "$path"` create-or-fails. Across N parallel fires with the same
# session_id, exactly one wins the claim and emits BASELINE; the rest
# see file-exists and suppress. (Codex round 1 P1: previous "check then
# write after emit" pattern allowed N parallel fires to all emit.)
SHOULD_EMIT_BASELINE=1
BASELINE_SENTINEL=""
if [ -n "$SESSION_ID" ]; then
    BASELINE_CACHE_DIR="${SDLC_WIZARD_CACHE_DIR:-$HOME/.cache/sdlc-wizard}"
    # Strip path-traversal chars from session_id before using in filename
    # (defense-in-depth — CC session_ids are UUIDs, but never trust stdin).
    SAFE_SID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9._-')
    if [ -n "$SAFE_SID" ]; then
        BASELINE_SENTINEL="$BASELINE_CACHE_DIR/baseline-shown-${SAFE_SID}"
        mkdir -p "$BASELINE_CACHE_DIR" 2>/dev/null || true
        # Atomic create-or-fail: subshell sets noclobber so `: > "$path"`
        # fails (rc≠0) if the file already exists. The full conditional
        # tree:
        #   - claim succeeds → emit (we won the race)
        #   - claim fails AND file exists → suppress (someone else won)
        #   - claim fails AND file doesn't exist → cache unwritable;
        #     fall back to emit so user never loses cold-start nudge.
        if (set -C; : > "$BASELINE_SENTINEL") 2>/dev/null; then
            SHOULD_EMIT_BASELINE=1
        elif [ -f "$BASELINE_SENTINEL" ]; then
            SHOULD_EMIT_BASELINE=0
        else
            SHOULD_EMIT_BASELINE=1
        fi
    fi
fi

if [ "$SHOULD_EMIT_BASELINE" -eq 1 ]; then
    cat << 'EOF'
SDLC BASELINE:
1. Task list FIRST (TodoWrite or TaskCreate) (plan tasks before coding)
2. STATE CONFIDENCE: HIGH/MEDIUM/LOW
3. LOW confidence or FAILED 2x? Ladder: Sol (Codex) -> Fable only if you and Sol cannot reconcile -> human LAST (sequential)
4. Never ask what a model can settle; confidence is not authorization
5. ALL TESTS MUST PASS BEFORE COMMIT - NO EXCEPTIONS

AUTO-INVOKE SKILL (Claude MUST do this FIRST):
- implement/fix/refactor/feature/bug/build/test/TDD/release/publish/deploy → Invoke: Skill tool, skill="sdlc"
- DON'T invoke for: questions, explanations, reading/exploring code, simple queries
- DON'T wait for user to type /sdlc - AUTO-INVOKE based on task type

Workflow phases:
1. Plan Mode (research) → Present approach + confidence
2. Transition (update docs) → Request /compact
3. Implementation (TDD after compact)

Quick refs: SDLC.md | TESTING.md | *_DOCS.md for feature
EOF
    # Prune sentinels older than 7d so cache doesn't grow forever.
    # Best-effort: errors silently swallowed.
    if [ -n "$BASELINE_SENTINEL" ]; then
        find "$BASELINE_CACHE_DIR" -name 'baseline-shown-*' -type f -mtime +7 -delete 2>/dev/null || true
    fi
fi
