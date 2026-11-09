#!/bin/bash
# The sdlc-skill gate (Fable ruling 2026-11-08).
#
# Predicate: "this context has an sdlc invocation on record" — a grep of the
# context's own transcript (the payload's transcript_path, or for a subagent
# its subagents/agent-<id>.jsonl) for a Skill tool_use, a typed /sdlc command
# record, or a post-compaction invoked_skills re-attachment naming sdlc.
#
# Gated at edit (tdd-pretool-check.sh, Write/Edit/MultiEdit on a gated path)
# and at commit (codex-gate-check.sh, staged gated paths, before any
# review-state allow). The transcript fixtures below are synthetic and copy
# only the STRUCTURE of real Claude Code records, never their content.
#
# Proof legs from the ruling covered here: 1, 2, 3, 4a, 5, 6, 7, 8. Legs 4b,
# 9 (the Skill line is on disk by the next tool's PreToolUse) and the real
# subagent transcript layout depend on Claude Code itself and are run live.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TDD_HOOK="$REPO_ROOT/hooks/tdd-pretool-check.sh"
PROMPT_HOOK="$REPO_ROOT/hooks/sdlc-prompt-check.sh"
GATE_HOOK="$REPO_ROOT/hooks/codex-gate-check.sh"
PASSED=0
FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

BLOCK_LINE='SDLC SKILL REQUIRED: invoke Skill(skill="sdlc") once this session, then retry.'

echo "=== sdlc skill gate tests ==="
echo ""

WORKSPACE=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-skill-gate.XXXXXX") || { echo "mktemp failed"; exit 1; }
[ -n "$WORKSPACE" ] && [ -d "$WORKSPACE" ] || { echo "no workspace"; exit 1; }
trap 'chmod -R u+rwx "$WORKSPACE" 2>/dev/null; rm -rf "$WORKSPACE"' EXIT

# An SDLC project (find_sdlc_root needs SDLC.md + TESTING.md) and a plain one.
PROJ="$WORKSPACE/proj"
PLAIN="$WORKSPACE/plain"
mkdir -p "$PROJ/src" "$PLAIN/src"
printf '# SDLC\n' > "$PROJ/SDLC.md"
printf '# TESTING\n' > "$PROJ/TESTING.md"

T="$WORKSPACE/transcripts"
mkdir -p "$T"

# --- transcript fixtures (structure of real records, synthetic content) ---
cat > "$T/base.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":"please fix the bug"},"sessionId":"S"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_r","name":"Read","input":{"file_path":"/p/README.md"}}]}}
EOF
skill_rec() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_s","name":"Skill","input":{"skill":"%s"},"caller":{"type":"direct"}}]}}\n' "$1"; }
slash_rec() { printf '{"type":"user","message":{"role":"user","content":"<command-message>%s</command-message>\\n<command-name>/%s</command-name>"}}\n' "$1" "$1"; }

{ cat "$T/base.jsonl"; skill_rec sdlc; } > "$T/skill.jsonl"
{ cat "$T/base.jsonl"; skill_rec sdlc-wizard:sdlc; } > "$T/skill-ns.jsonl"
{ cat "$T/base.jsonl"; slash_rec sdlc; } > "$T/slash.jsonl"
{ cat "$T/base.jsonl"; slash_rec sdlc-wizard-cowork:sdlc; } > "$T/slash-ns.jsonl"
# name-first ordering, as CC writes for built-in commands
{ cat "$T/base.jsonl"; printf '{"type":"user","message":{"role":"user","content":"<command-name>/sdlc</command-name>\\n<command-message>sdlc</command-message>"}}\n'; } > "$T/slash-namefirst.jsonl"
# leg 5: compaction drops the Skill call from context but CC re-attaches the body
{ cat "$T/base.jsonl"
  printf '{"type":"system","subtype":"compact_boundary","content":"Conversation compacted"}\n'
  printf '{"type":"attachment","attachment":{"type":"invoked_skills","skills":[{"name":"other","path":"plugin:x:other","content":"x"},{"name":"sdlc","path":"projectSettings:sdlc","content":"# SDLC body"}]}}\n'
} > "$T/compacted.jsonl"
{ cat "$T/base.jsonl"
  printf '{"type":"attachment","attachment":{"type":"invoked_skills","skills":[{"name":"sdlc-wizard-cowork:sdlc","path":"plugin:sdlc-wizard-cowork:sdlc","content":"# SDLC body"}]}}\n'
} > "$T/compacted-ns.jsonl"

# Near misses: every one of these must NOT count as an invocation.
{ cat "$T/base.jsonl"; skill_rec rdlc; } > "$T/neg-rdlc.jsonl"
{ cat "$T/base.jsonl"; skill_rec sdlc-wizard:update; } > "$T/neg-update.jsonl"
{ cat "$T/base.jsonl"; skill_rec mysdlc; } > "$T/neg-mysdlc.jsonl"
{ cat "$T/base.jsonl"; slash_rec sdlc-wizard:update; } > "$T/neg-slash-update.jsonl"
# a Read of the skill file is not an invocation (it is never re-attached)
{ cat "$T/base.jsonl"; printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_x","name":"Read","input":{"file_path":"/p/.claude/skills/sdlc/SKILL.md"}}]}}\n'; } > "$T/neg-read.jsonl"
# a QUOTED record inside another tool's input is JSON-escaped, so it cannot match
{ cat "$T/base.jsonl"; printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_w","name":"Write","input":{"file_path":"/p/x.md","content":"{\\"name\\":\\"Skill\\",\\"input\\":{\\"skill\\":\\"sdlc\\"}} <command-name>/sdlc</command-name> \\"type\\":\\"invoked_skills\\",\\"skills\\":[{\\"name\\":\\"sdlc\\",\\"path\\":\\"p\\"}]"}}]}}\n'; } > "$T/neg-quoted.jsonl"
# a human prompt that merely mentions /sdlc or quotes the tag mid-text
{ cat "$T/base.jsonl"; printf '{"type":"user","message":{"role":"user","content":"run /sdlc then see <command-name>/sdlc</command-name>"}}\n'; } > "$T/neg-prose.jsonl"
# an invoked_skills attachment for some other skill
{ cat "$T/base.jsonl"; printf '{"type":"attachment","attachment":{"type":"invoked_skills","skills":[{"name":"rdlc","path":"projectSettings:rdlc","content":"sdlc sdlc"}]}}\n'; } > "$T/neg-attach-other.jsonl"

# Every negative fixture must be a VALID JSONL file, or a miss proves nothing.
for f in "$T"/*.jsonl; do
    python3 -c 'import json,sys
for l in open(sys.argv[1]): json.loads(l)' "$f" || { echo "fixture $f is not valid JSONL"; exit 1; }
done

# edit_payload <file_path> <transcript_path|""> [session_id] [agent_id]
edit_payload() {
    local fp="$1" tp="$2" sid="${3:-S}" aid="${4:-}"
    local extra=""
    [ -n "$tp" ] && extra="$extra,\"transcript_path\":\"$tp\""
    [ -n "$aid" ] && extra="$extra,\"agent_id\":\"$aid\""
    printf '{"session_id":"%s"%s,"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' \
        "$sid" "$extra" "$fp"
}

# run_tdd <cache> <payload> [cwd] — sets RC, OUT, ERR
run_tdd() {
    local cache="$1" payload="$2" cwd="${3:-$PROJ}"
    RC=0
    OUT=$(cd "$cwd" && SDLC_WIZARD_CACHE_DIR="$cache" bash "$TDD_HOOK" <<<"$payload" 2>"$WORKSPACE/err") || RC=$?
    ERR=$(cat "$WORKSPACE/err")
}

# A fresh cache dir with the TDD "test touched" sentinel already primed, so a
# result below reflects the skill gate and not the separate TDD gate.
fresh_cache() {
    local c="$WORKSPACE/cache-$1"
    rm -rf "$c"; mkdir -p "$c"
    : > "$c/tdd-test-touched-${2:-S}"
    printf '%s' "$c"
}

# --- leg 2: no invocation on record -> exit 2, exactly the ruled line ---
test_leg2_miss_blocks_with_exact_line() {
    local c; c=$(fresh_cache l2)
    run_tdd "$c" "$(edit_payload "$PROJ/src/app.js" "$T/base.jsonl")"
    if [ "$RC" -eq 2 ] && [ "$ERR" = "$BLOCK_LINE" ]; then
        pass "leg 2: gated edit with no sdlc on record exits 2 with exactly the ruled line"
    else
        fail "leg 2: expected exit 2 + '$BLOCK_LINE', got rc=$RC stderr='$ERR'"
    fi
}

# --- near misses all block ---
test_near_misses_block() {
    local f c bad=""
    for f in neg-rdlc neg-update neg-mysdlc neg-slash-update neg-read neg-quoted neg-prose neg-attach-other; do
        c=$(fresh_cache "nm-$f")
        run_tdd "$c" "$(edit_payload "$PROJ/src/app.js" "$T/$f.jsonl")"
        [ "$RC" -eq 2 ] && [ "$ERR" = "$BLOCK_LINE" ] || bad="$bad $f(rc=$RC)"
    done
    if [ -z "$bad" ]; then
        pass "near misses (rdlc, sdlc-wizard:update, mysdlc, /sdlc-wizard:update, Read of SKILL.md, escaped quote, prose mention, other skill attached) all block"
    else
        fail "near misses wrongly counted as an invocation:$bad"
    fi
}

# --- leg 1 / 4a / 5: each record kind counts ---
test_each_record_kind_allows() {
    local f c bad=""
    for f in skill skill-ns slash slash-ns slash-namefirst compacted compacted-ns; do
        c=$(fresh_cache "ok-$f")
        run_tdd "$c" "$(edit_payload "$PROJ/src/app.js" "$T/$f.jsonl")"
        if [ "$RC" -ne 0 ] || printf '%s' "$ERR" | grep -q "SDLC SKILL REQUIRED"; then
            bad="$bad $f(rc=$RC)"
        fi
    done
    if [ -z "$bad" ]; then
        pass "legs 1/4a/5: Skill(sdlc), Skill(ns:sdlc), typed /sdlc and /ns:sdlc (both orders), and post-compaction invoked_skills all allow"
    else
        fail "a real invocation record was not recognised:$bad"
    fi
}

run_prompt_hook() {
    local cache="$1" payload="$2" cwd="${3:-$PROJ}"
    RC=0
    OUT=$(cd "$cwd" && SDLC_WIZARD_CACHE_DIR="$cache" bash "$PROMPT_HOOK" <<<"$payload" 2>"$WORKSPACE/err") || RC=$?
    ERR=$(cat "$WORKSPACE/err")
}

# --- the skill gate runs BEFORE the TDD gate ---
test_skill_gate_precedes_tdd_gate() {
    local c="$WORKSPACE/cache-order"
    rm -rf "$c"; mkdir -p "$c"   # no test touched either
    run_tdd "$c" "$(edit_payload "$PROJ/src/app.js" "$T/base.jsonl")"
    if [ "$RC" -eq 2 ] && [ "$ERR" = "$BLOCK_LINE" ]; then
        pass "skill gate is checked before the TDD gate"
    else
        fail "expected the skill gate first, got rc=$RC err='$ERR'"
    fi
}

# --- leg 3: allow paths ---
test_leg3_non_gated_path_allows() {
    local c; c=$(fresh_cache l3)
    run_tdd "$c" "$(edit_payload "$PROJ/README.md" "$T/base.jsonl")"
    if [ "$RC" -eq 0 ] && [ -z "$ERR" ]; then
        pass "leg 3: a non-gated path (README.md) is never blocked"
    else
        fail "leg 3: README.md edit blocked (rc=$RC err=$ERR)"
    fi
    run_tdd "$c" "$(edit_payload "$PROJ/src/__tests__/app.test.js" "$T/base.jsonl")"
    if [ "$RC" -eq 0 ]; then
        pass "a test file under src/ is not gated"
    else
        fail "test file under src/ blocked (rc=$RC err=$ERR)"
    fi
}

test_non_sdlc_project_allows() {
    local c; c=$(fresh_cache plain)
    run_tdd "$c" "$(edit_payload "$PLAIN/src/app.js" "$T/base.jsonl")" "$PLAIN"
    if [ "$RC" -eq 0 ] && ! printf '%s' "$ERR" | grep -q "SDLC SKILL REQUIRED"; then
        pass "no SDLC.md/TESTING.md root -> the skill gate is inactive"
    else
        fail "skill gate fired outside an SDLC project (rc=$RC err=$ERR)"
    fi
}

test_nested_src_is_gated_by_default() {
    # GH #475: the path filter lives in the script now; it must catch monorepo src/
    local c; c=$(fresh_cache nested)
    run_tdd "$c" "$(edit_payload "$PROJ/packages/api/src/widget.ts" "$T/base.jsonl")"
    if [ "$RC" -eq 2 ] && [ "$ERR" = "$BLOCK_LINE" ]; then
        pass "GH #475: packages/api/src/widget.ts is gated by the script's default pattern"
    else
        fail "GH #475: nested src not gated (rc=$RC err=$ERR)"
    fi
}

test_src_pattern_override_is_shared() {
    local c; c=$(fresh_cache pat)
    RC=0
    ERR=$(cd "$PROJ" && SDLC_TDD_SRC_PATTERN='hooks/|cli/' SDLC_WIZARD_CACHE_DIR="$c" bash "$TDD_HOOK" \
        <<<"$(edit_payload "$PROJ/hooks/x.sh" "$T/base.jsonl")" 2>&1 >/dev/null) || RC=$?
    local rc1=$RC
    RC=0
    (cd "$PROJ" && SDLC_TDD_SRC_PATTERN='hooks/|cli/' SDLC_WIZARD_CACHE_DIR="$c" bash "$TDD_HOOK" \
        <<<"$(edit_payload "$PROJ/src/app.js" "$T/base.jsonl")" >/dev/null 2>&1) || RC=$?
    if [ "$rc1" -eq 2 ] && [ "$RC" -eq 0 ]; then
        pass "SDLC_TDD_SRC_PATTERN decides what the skill gate covers"
    else
        fail "pattern override not honoured (hooks/ rc=$rc1, src/ rc=$RC)"
    fi
}

# --- fail mode ---
test_no_transcript_path_allows_silently() {
    local c; c=$(fresh_cache notp)
    run_tdd "$c" "$(edit_payload "$PROJ/src/app.js" "")"
    if [ "$RC" -eq 0 ] && ! printf '%s%s' "$OUT" "$ERR" | grep -q "SDLC"; then
        pass "no transcript_path -> allow silently"
    else
        fail "no transcript_path should allow silently (rc=$RC out=$OUT err=$ERR)"
    fi
}

test_leg7_unreadable_transcript_allows_with_context() {
    local c; c=$(fresh_cache l7)
    local tp="$WORKSPACE/missing/t.jsonl"
    run_tdd "$c" "$(edit_payload "$PROJ/src/app.js" "$tp")"
    local want="SDLC gate degraded: cannot read $tp; invoke Skill(sdlc) now if not loaded"
    local ctx
    ctx=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null || true)
    local n
    n=$(printf '%s' "$OUT" | jq -s 'length' 2>/dev/null || echo bad)
    if [ "$RC" -eq 0 ] && [ "$n" = "1" ] && printf '%s' "$ctx" | grep -qF "$want"; then
        pass "leg 7: unreadable transcript_path -> exit 0, one JSON object carrying the degraded notice"
    else
        fail "leg 7: expected exit 0 + additionalContext '$want', got rc=$RC objects=$n out=$OUT"
    fi
    # it merges with the TDD nudge instead of printing a second object
    if printf '%s' "$ctx" | grep -q "TDD CHECK"; then
        pass "leg 7: degraded notice and TDD nudge share one additionalContext"
    else
        fail "leg 7: TDD nudge lost when the degraded notice is emitted (ctx=$ctx)"
    fi
    # a present-but-unreadable file degrades the same way
    local tp2="$T/locked.jsonl"
    cp "$T/skill.jsonl" "$tp2"; chmod 000 "$tp2"
    if [ -r "$tp2" ]; then
        pass "leg 7: (chmod 000 still readable here, e.g. root — missing-file case above covers it)"
    else
        c=$(fresh_cache l7b)
        run_tdd "$c" "$(edit_payload "$PROJ/src/app.js" "$tp2")"
        if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -qF "SDLC gate degraded: cannot read"; then
            pass "leg 7: chmod-000 transcript -> exit 0 with the degraded notice"
        else
            fail "leg 7: chmod-000 transcript should degrade, got rc=$RC out=$OUT err=$ERR"
        fi
    fi
    chmod 644 "$tp2"
}

test_opt_out() {
    local c; c=$(fresh_cache off)
    RC=0
    ERR=$(cd "$PROJ" && SDLC_SKILL_GATE=off SDLC_WIZARD_CACHE_DIR="$c" bash "$TDD_HOOK" \
        <<<"$(edit_payload "$PROJ/src/app.js" "$T/base.jsonl")" 2>&1 >/dev/null) || RC=$?
    if [ "$RC" -eq 0 ] && ! printf '%s' "$ERR" | grep -q "SDLC SKILL REQUIRED"; then
        pass "SDLC_SKILL_GATE=off disables the edit gate"
    else
        fail "opt-out ignored (rc=$RC err=$ERR)"
    fi
}

# --- subagents (leg 6) ---
# A subagent's payload carries agent_id and the PARENT's transcript_path. It
# does not get the parent's skill body, so it is read from its OWN transcript,
# ${transcript_path%.jsonl}/subagents/agent-<agent_id>.jsonl (observed live,
# CC 2.1.289), and the parent's record never counts for it.
test_subagent_own_transcript() {
    local c; c=$(fresh_cache sub)
    local par="$T/parent.jsonl"
    cp "$T/skill.jsonl" "$par"
    mkdir -p "$T/parent/subagents"
    { cat "$T/base.jsonl"; skill_rec sdlc; } > "$T/parent/subagents/agent-agentE.jsonl"
    cp "$T/base.jsonl" "$T/parent/subagents/agent-agentF.jsonl"
    run_tdd "$c" "$(edit_payload "$PROJ/src/app.js" "$par" S agentE)"
    if [ "$RC" -eq 0 ] && ! printf '%s%s' "$OUT" "$ERR" | grep -q "SDLC SKILL\|degraded"; then
        pass "leg 6: subagent whose own transcript holds Skill(sdlc) is allowed"
    else
        fail "leg 6: subagent own-transcript hit not recognised (rc=$RC out=$OUT err=$ERR)"
    fi
    run_tdd "$c" "$(edit_payload "$PROJ/src/app.js" "$par" S agentF)"
    if [ "$RC" -eq 2 ] && [ "$ERR" = "$BLOCK_LINE" ]; then
        pass "leg 6: subagent without its own call is blocked although the parent transcript holds one"
    else
        fail "leg 6: subagent passed on the parent's invocation (rc=$RC err=$ERR)"
    fi
    cp "$T/base.jsonl" "$T/parent-miss.jsonl"
    mkdir -p "$T/parent-miss/subagents"
    { cat "$T/base.jsonl"; skill_rec sdlc; } > "$T/parent-miss/subagents/agent-agentE.jsonl"
    run_tdd "$c" "$(edit_payload "$PROJ/src/app.js" "$T/parent-miss.jsonl")"
    if [ "$RC" -eq 2 ]; then
        pass "leg 6: the parent never counts a subagent's call"
    else
        fail "leg 6: parent passed on a subagent's call (rc=$RC)"
    fi
    run_tdd "$c" "$(edit_payload "$PROJ/src/app.js" "$par" S agentG)"
    if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -qF "SDLC gate degraded: cannot read $T/parent/subagents/agent-agentG.jsonl"; then
        pass "leg 6: a missing subagent transcript degrades with its own path named (leg 7 rule)"
    else
        fail "leg 6: missing subagent transcript handled wrong (rc=$RC out=$OUT err=$ERR)"
    fi
    # "/" is stripped, so a crafted id cannot climb to agentE's transcript
    run_tdd "$c" "$(edit_payload "$PROJ/src/app.js" "$par" S '../parent/subagents/agent-agentE')"
    if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -qF "cannot read $T/parent/subagents/agent-..parentsubagentsagent-agentE.jsonl"; then
        pass "leg 6: agent_id is sanitised before it builds a path"
    else
        fail "leg 6: crafted agent_id not sanitised (rc=$RC out=$OUT)"
    fi
    if ! ls "$c" | grep -q '^sdlc-invoked-'; then
        pass "no gate check writes a sdlc-invoked-* memo"
    else
        fail "a memo was written: $(ls "$c")"
    fi
}

# --- leg 5 nudge repair: compaction re-arms BASELINE, never the skill memo ---
test_leg5_compact_rearms_baseline() {
    local c; c=$(fresh_cache l5)
    : > "$c/baseline-shown-S"
    run_prompt_hook "$c" '{"session_id":"S","hook_event_name":"SessionStart","source":"compact"}'
    local ss_rc=$RC ss_out="$OUT"
    if [ "$ss_rc" -eq 0 ] && [ -z "$ss_out" ] && [ ! -f "$c/baseline-shown-S" ]; then
        pass "leg 5: SessionStart compact deletes baseline-shown-<sid> and prints nothing"
    else
        fail "leg 5: compact handling wrong (rc=$ss_rc out='$ss_out' files: $(ls "$c"))"
    fi
    run_prompt_hook "$c" '{"session_id":"S","hook_event_name":"UserPromptSubmit","prompt":"next"}'
    if printf '%s' "$OUT" | grep -q "SDLC BASELINE"; then
        pass "leg 5: the next prompt after compaction re-emits BASELINE once"
    else
        fail "leg 5: BASELINE not re-emitted after compaction (out=$OUT)"
    fi
    run_prompt_hook "$c" '{"session_id":"S","hook_event_name":"UserPromptSubmit","prompt":"again"}'
    if ! printf '%s' "$OUT" | grep -q "SDLC BASELINE"; then
        pass "leg 5: ...and only once"
    else
        fail "leg 5: BASELINE emitted twice after one compaction"
    fi
    local s bad=""
    for s in startup resume clear; do
        : > "$c/baseline-shown-S"
        run_prompt_hook "$c" "{\"session_id\":\"S\",\"hook_event_name\":\"SessionStart\",\"source\":\"$s\"}"
        [ -f "$c/baseline-shown-S" ] && [ -z "$OUT" ] || bad="$bad $s"
    done
    if [ -z "$bad" ]; then
        pass "SessionStart startup/resume/clear leave the BASELINE sentinel alone"
    else
        fail "non-compact SessionStart touched the sentinel or printed:$bad"
    fi
}

# --- r1 P1: the plugin copy's dedupe must not swallow the non-prompt events ---
# An older CLI install registers this script under UserPromptSubmit only. The
# plugin copy then yields the prompt (correct: the project prints BASELINE),
# but nothing else runs the compaction reset.
test_dedupe_spares_non_prompt_events() {
    local c; c=$(fresh_cache dd)
    local plug="$WORKSPACE/home/.claude/plugins-local/sdlc-wizard-wrap"
    rm -rf "$plug"; mkdir -p "$plug" "$PROJ/.claude"
    cp -R "$REPO_ROOT/hooks" "$plug/hooks"
    cat > "$PROJ/.claude/settings.json" <<'EOF'
{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/hooks/sdlc-prompt-check.sh"}]}]}}
EOF
    local log="$WORKSPACE/fire-dd.log"; rm -f "$log"
    run_plug() {
        RC=0
        OUT=$(cd "$PROJ" && CLAUDE_PROJECT_DIR="$PROJ" SDLC_WIZARD_CACHE_DIR="$c" SDLC_HOOK_FIRE_LOG="$log" \
            bash "$plug/hooks/sdlc-prompt-check.sh" <<<"$1" 2>/dev/null) || RC=$?
    }
    : > "$c/baseline-shown-S"
    run_plug '{"session_id":"S","hook_event_name":"SessionStart","source":"compact"}'
    if [ ! -f "$c/baseline-shown-S" ] && [ -z "$OUT" ]; then
        pass "dedupe: plugin copy still runs the compact reset when the project registers only UserPromptSubmit"
    else
        fail "dedupe: plugin copy skipped the compact reset (files: $(ls "$c"))"
    fi
    run_plug '{"session_id":"S","hook_event_name":"UserPromptSubmit","prompt":"hi"}'
    if [ -z "$OUT" ]; then
        pass "dedupe: plugin copy still yields the prompt to the project registration"
    else
        fail "dedupe: plugin copy printed on UserPromptSubmit despite the project registration"
    fi
    rm -f "$PROJ/.claude/settings.json"
}

# --- r1 P2: the fires-once log counts prompts, not every event ---
test_fire_log_counts_prompts_only() {
    local c; c=$(fresh_cache fl)
    local log="$WORKSPACE/fire-fl.log"; rm -f "$log"
    local p
    for p in '{"session_id":"S","hook_event_name":"SessionStart","source":"compact"}' \
             '{"session_id":"S","hook_event_name":"UserPromptSubmit","prompt":"hi"}'; do
        (cd "$PROJ" && SDLC_WIZARD_CACHE_DIR="$c" SDLC_HOOK_FIRE_LOG="$log" bash "$PROMPT_HOOK" <<<"$p" >/dev/null 2>&1) || true
    done
    local n=0; [ -f "$log" ] && n=$(wc -l < "$log" | tr -d ' ')
    if [ "$n" = "1" ]; then
        pass "fire log: one compaction and one prompt log exactly one line"
    else
        fail "fire log: expected 1 line, got $n"
    fi
}

# --- leg 8: commit-time late catch in codex-gate-check.sh ---
GREPO="$WORKSPACE/grepo"
setup_grepo() {
    rm -rf "$GREPO"; mkdir -p "$GREPO/src" "$GREPO/hooks"
    (
        cd "$GREPO"
        git init -q
        git config user.email t@t; git config user.name t
        printf '# SDLC\n' > SDLC.md; printf '# TESTING\n' > TESTING.md
        printf 'x\n' > README.md
        git add -A; git commit -qm base
    )
}

commit_payload() {
    local tp="$1" sid="${2:-S}" aid="${3:-}"
    local extra=""
    [ -n "$tp" ] && extra=",\"transcript_path\":\"$tp\""
    [ -n "$aid" ] && extra="$extra,\"agent_id\":\"$aid\""
    printf '{"session_id":"%s"%s,"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git commit -m wip","description":"commit"}}' "$sid" "$extra"
}

run_gate() {
    local cache="$1" payload="$2"
    shift 2
    RC=0
    ERR=$(cd "$GREPO" && env SDLC_WIZARD_CACHE_DIR="$cache" "$@" bash "$GATE_HOOK" <<<"$payload" 2>&1 >/dev/null) || RC=$?
}

# Mark the staged tree as passing locally — the FIRST allow in codex-gate.
mark_local_pass() { (cd "$GREPO" && printf '%s PASS\n' "$(git write-tree)" > .local-test-result); }

test_leg8_commit_late_catch() {
    local c; c=$(fresh_cache l8)
    setup_grepo
    (cd "$GREPO" && printf 'y\n' > src/app.js && git add src/app.js)
    mark_local_pass
    # also a certified handoff on exactly this tree: a review never substitutes
    (cd "$GREPO" && mkdir -p .reviews && printf '{"status":"CERTIFIED","candidate_tree":"%s"}\n' "$(git write-tree)" > .reviews/handoff.json)
    run_gate "$c" "$(commit_payload "$T/base.jsonl")"
    if [ "$RC" -eq 2 ] && printf '%s' "$ERR" | grep -qF "$BLOCK_LINE" && printf '%s' "$ERR" | grep -qi "late catch"; then
        pass "leg 8: staged gated path + no sdlc on record -> exit 2 before the local-pass and certified allows"
    else
        fail "leg 8: expected late-catch exit 2, got rc=$RC err=$ERR"
    fi
    run_gate "$c" "$(commit_payload "$T/skill.jsonl")"
    if [ "$RC" -eq 0 ]; then
        pass "leg 8: with sdlc on record the commit falls through to the existing allows"
    else
        fail "leg 8: hit should fall through to the local-pass allow (rc=$RC err=$ERR)"
    fi
    mkdir -p "$T/skill/subagents"; cp "$T/base.jsonl" "$T/skill/subagents/agent-agentD.jsonl"
    run_gate "$c" "$(commit_payload "$T/skill.jsonl" S agentD)"
    if [ "$RC" -eq 2 ] && printf '%s' "$ERR" | grep -qF "$BLOCK_LINE"; then
        pass "leg 8: a subagent's commit is caught even when the parent transcript holds Skill(sdlc)"
    else
        fail "leg 8: subagent commit passed on the parent's invocation (rc=$RC err=$ERR)"
    fi
    run_gate "$c" "$(commit_payload "$T/base.jsonl")" SDLC_SKILL_GATE=off
    if [ "$RC" -eq 0 ]; then
        pass "leg 8: SDLC_SKILL_GATE=off disables the commit check"
    else
        fail "leg 8: opt-out ignored at commit (rc=$RC err=$ERR)"
    fi
}

test_leg8_fall_through_reaches_review_gate() {
    local c; c=$(fresh_cache l8b)
    setup_grepo
    (cd "$GREPO" && printf 'y\n' > src/app.js && git add src/app.js)
    run_gate "$c" "$(commit_payload "$T/skill.jsonl")"
    if [ "$RC" -eq 2 ] && printf '%s' "$ERR" | grep -q "CROSS-MODEL REVIEW REQUIRED" && ! printf '%s' "$ERR" | grep -q "SDLC SKILL"; then
        pass "leg 8: a hit leaves the existing review gate in charge"
    else
        fail "leg 8: hit did not fall through to the review gate (rc=$RC err=$ERR)"
    fi
}

test_leg8_ungated_staged_paths_pass() {
    local c; c=$(fresh_cache l8c)
    setup_grepo
    (cd "$GREPO" && printf 'z\n' >> README.md && git add README.md)
    mark_local_pass
    run_gate "$c" "$(commit_payload "$T/base.jsonl")"
    if [ "$RC" -eq 0 ]; then
        pass "leg 8: only non-gated paths staged -> no skill check at commit"
    else
        fail "leg 8: README-only commit blocked (rc=$RC err=$ERR)"
    fi
    # pattern override applies at commit too
    (cd "$GREPO" && printf 'h\n' > hooks/x.sh && git add hooks/x.sh)
    mark_local_pass
    run_gate "$c" "$(commit_payload "$T/base.jsonl")" SDLC_TDD_SRC_PATTERN='hooks/'
    if [ "$RC" -eq 2 ] && printf '%s' "$ERR" | grep -qF "$BLOCK_LINE"; then
        pass "leg 8: SDLC_TDD_SRC_PATTERN decides the gated paths at commit"
    else
        fail "leg 8: pattern override not honoured at commit (rc=$RC err=$ERR)"
    fi
}

test_leg8_non_commit_untouched() {
    local c; c=$(fresh_cache l8d)
    setup_grepo
    (cd "$GREPO" && printf 'y\n' > src/app.js && git add src/app.js)
    run_gate "$c" '{"session_id":"S","transcript_path":"'"$T/base.jsonl"'","tool_name":"Bash","tool_input":{"command":"git status"}}'
    if [ "$RC" -eq 0 ]; then
        pass "leg 8: a non-commit Bash command is never checked"
    else
        fail "leg 8: git status blocked (rc=$RC err=$ERR)"
    fi
}

# --- registration: the shipped manifests wire the compaction re-arm and drop the pre-filter ---
test_registration() {
    local f bad=""
    for f in "$REPO_ROOT/hooks/hooks.json" "$REPO_ROOT/cli/templates/settings.json"; do
        python3 - "$f" <<'PYEOF' || bad="$bad ${f#"$REPO_ROOT"/}"
import json, sys
d = json.load(open(sys.argv[1]))["hooks"]
def cmds(event, matcher=None):
    out = []
    for e in d.get(event, []):
        if matcher is not None and e.get("matcher") != matcher:
            continue
        out += [h for h in e.get("hooks", [])]
    return out
post = [h["command"] for h in cmds("PostToolUse")]
assert not any(c.endswith("sdlc-prompt-check.sh") for c in post), "PostToolUse -> sdlc-prompt-check.sh still registered"
ss = [h["command"] for h in cmds("SessionStart")]
assert any(c.endswith("sdlc-prompt-check.sh") for c in ss), "SessionStart -> sdlc-prompt-check.sh missing"
tdd = [h for h in cmds("PreToolUse", "Write|Edit|MultiEdit") if h["command"].endswith("tdd-pretool-check.sh")]
assert tdd, "tdd hook missing"
assert all("if" not in h for h in tdd), "tdd hook still carries an if: pre-filter"
PYEOF
    done
    if [ -z "$bad" ]; then
        pass "hooks.json and the CLI template register SessionStart (and no PostToolUse) on sdlc-prompt-check.sh, and the TDD hook has no if: pre-filter"
    else
        fail "registration wrong in:$bad"
    fi
}

test_leg2_miss_blocks_with_exact_line
test_near_misses_block
test_each_record_kind_allows
test_skill_gate_precedes_tdd_gate
test_leg3_non_gated_path_allows
test_non_sdlc_project_allows
test_nested_src_is_gated_by_default
test_src_pattern_override_is_shared
test_no_transcript_path_allows_silently
test_leg7_unreadable_transcript_allows_with_context
test_opt_out
test_subagent_own_transcript
test_leg5_compact_rearms_baseline
test_dedupe_spares_non_prompt_events
test_fire_log_counts_prompts_only
test_leg8_commit_late_catch
test_leg8_fall_through_reaches_review_gate
test_leg8_ungated_staged_paths_pass
test_leg8_non_commit_untouched
test_registration

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ "$FAILED" -eq 0 ] || exit 1
