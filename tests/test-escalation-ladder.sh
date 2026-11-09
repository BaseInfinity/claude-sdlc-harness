#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

info() {
    echo -e "${YELLOW}INFO${NC}: $1"
}

# --- Isolation setup ---
TEST_HOME="${TMPDIR:-/tmp}/escalation-ladder-test-$$"
mkdir -p "$TEST_HOME/.claude"

if [ -f "$HOME/.claude/settings.json" ]; then
    cp "$HOME/.claude/settings.json" "$TEST_HOME/.claude/settings.json"
fi

cleanup() {
    rm -rf "$TEST_HOME"
}
trap cleanup EXIT

# Read a stream-json transcript, one JSON event per line. Prints the answer to
# QUERY, or why there is none. "model" names the init event's model; "advisor"
# names the advisor_tool_result block. Both require a successful result first.
read_events() {
    python3 -c "
import json, sys
events = []
for line in open(sys.argv[1]):
    if not line.strip():
        continue
    try:
        events.append(json.loads(line))
    except ValueError:
        print('UNPARSEABLE OUTPUT')
        sys.exit()
ok = any(e.get('type') == 'result' and e.get('subtype') == 'success'
         and e.get('is_error') is False for e in events)
if not ok:
    print('NO SUCCESSFUL RESULT')
    sys.exit()
if sys.argv[2] == 'model':
    print(next((e.get('model', '') for e in events
                if e.get('type') == 'system' and e.get('subtype') == 'init'), 'NO INIT EVENT'))
else:
    blocks = [b for e in events if e.get('type') == 'assistant'
              for b in (e.get('message') or {}).get('content') or [] if isinstance(b, dict)]
    print(next((b['type'] for b in blocks if b.get('type') == 'advisor_tool_result'),
               'NO ADVISOR RESULT'))
" "$1" "$2"
}

# --- Rung 1: Opus builder (observed from a live session) ---

test_builder_is_opus() {
    # An unpinned settings.json has no "model" key and still runs Opus, so
    # the key cannot answer this. Read the model a live session reports.
    if ! command -v claude >/dev/null 2>&1; then
        fail "claude CLI not installed — builder unobservable"
        return
    fi
    local init_out="$TEST_HOME/builder-init.ndjson"
    local rc=0 model
    # perl's alarm bounds the child, since stock macOS has no timeout(1). It
    # survives exec, so a hung session exits 142 instead of blocking the suite.
    perl -e 'alarm shift; exec @ARGV or die "exec: $!"' 180 \
        claude -p "Say only: OK" \
        --settings "$TEST_HOME/.claude/settings.json" \
        --output-format stream-json --verbose > "$init_out" 2> "$init_out.err" < /dev/null || rc=$?
    if [ "$rc" -ne 0 ]; then
        fail "Builder session exited $rc (142 = no answer within 180s)"
        info "stderr: $(tail -c 300 "$init_out.err")"
        return
    fi
    # json prints one result object, which names no model, unless the config
    # sets verbose. stream-json --verbose always emits the init event as NDJSON.
    # The init event names the model before any work happens, so a session
    # that then failed would still report it. Require a successful result too.
    model=$(read_events "$init_out" model)
    if [[ "$model" == *"opus"* ]]; then
        pass "Builder session runs Opus: $model"
    else
        fail "Builder session is not Opus: $model"
        info "Output: $(tail -c 300 "$init_out") stderr: $(tail -c 300 "$init_out.err")"
    fi
}

# --- Rung 2: GPT-5.6 Sol via run-review-leg.sh ---

test_review_leg_script_exists() {
    if [ -x "$REPO_ROOT/scripts/run-review-leg.sh" ]; then
        pass "run-review-leg.sh exists and is executable"
    else
        fail "run-review-leg.sh missing or not executable"
    fi
}

test_review_leg_default_model() {
    local default_model
    default_model=$(grep -o 'REVIEW_MODEL:-[^}]*' "$REPO_ROOT/scripts/run-review-leg.sh" | head -1 | cut -d'-' -f2-)
    info "Default review model in script: $default_model"
    if [[ "$default_model" == *"sol"* ]] || [[ "$default_model" == *"5.6"* ]]; then
        pass "run-review-leg.sh defaults to Sol: $default_model"
    elif [ -n "$default_model" ]; then
        fail "run-review-leg.sh defaults to $default_model — should be gpt-5.6-sol (#715)"
    else
        fail "run-review-leg.sh has no default REVIEW_MODEL"
    fi
}

test_sol_reachable() {
    if ! command -v codex >/dev/null 2>&1; then
        fail "codex CLI not installed — Sol unreachable"
        return
    fi
    info "Calling GPT-5.6 Sol (isolated codex session)..."
    local sol_out="$TEST_HOME/sol-response.txt"
    local exit_code
    REVIEW_MODEL=gpt-5.6-sol "$REPO_ROOT/scripts/run-review-leg.sh" "$sol_out" \
        "Respond with exactly: {\"verdict\":\"CERTIFIED\",\"confidence\":100}. Nothing else." 2>&1 && exit_code=0 || exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        fail "GPT-5.6 Sol run-review-leg.sh exited $exit_code"
        return
    fi

    if [ ! -s "$sol_out" ]; then
        fail "GPT-5.6 Sol produced no output file"
        return
    fi

    if grep -q '"verdict"' "$sol_out" && grep -q '"CERTIFIED"\|"NOT_CERTIFIED"' "$sol_out"; then
        local token_line
        token_line=$(grep 'tokens used' "$sol_out" | head -1)
        pass "GPT-5.6 Sol returned a structured verdict ($token_line)"
    else
        fail "GPT-5.6 Sol output missing structured verdict JSON"
        info "Output: $(tail -3 "$sol_out")"
    fi
}

# --- Rung 3: Fable 5 via advisor() ---

test_advisor_model_configured() {
    local advisor
    advisor=$(python3 -c "
import json
s = json.load(open('$HOME/.claude/settings.json'))
print(s.get('advisorModel', 'NOT SET'))
")
    if [ "$advisor" = "claude-fable-5-1" ]; then
        pass "advisorModel pinned to claude-fable-5-1"
    elif [ "$advisor" = "claude-fable-5" ] || [ "$advisor" = "fable" ]; then
        # skills/update/SKILL.md migrates both to claude-fable-5-1. They still
        # reach Fable, which test_advisor_reachable observes, so note and pass.
        info "advisorModel is '$advisor' — /update migrates it to claude-fable-5-1"
        pass "advisorModel configured: $advisor"
    else
        fail "advisorModel unexpected: $advisor (expected claude-fable-5-1)"
    fi
}

test_advisor_reachable() {
    if ! command -v claude >/dev/null 2>&1; then
        fail "claude CLI not installed — advisor unreachable"
        return
    fi
    info "Calling advisor() in isolated session (Fable 5)..."
    local advisor_out="$TEST_HOME/advisor-response.ndjson"
    local rc=0 answer
    perl -e 'alarm shift; exec @ARGV or die "exec: $!"' 180 \
        claude -p "Call advisor() now. Say only: ADVISOR_OK" \
        --settings "$TEST_HOME/.claude/settings.json" \
        --output-format stream-json --verbose > "$advisor_out" 2> "$advisor_out.err" < /dev/null || rc=$?
    if [ "$rc" -eq 0 ]; then
        answer=$(read_events "$advisor_out" advisor)
    else
        answer="session exited $rc (142 = no answer within 180s)"
    fi

    if [ "$answer" = "advisor_tool_result" ]; then
        pass "advisor() returned an advisor_tool_result (Fable 5 responded)"
    elif grep -q 'authentication_failed\|Not logged in' "$advisor_out" "$advisor_out.err"; then
        fail "advisor() auth failed — check Max subscription"
    else
        fail "advisor() returned no advisor_tool_result: $answer"
        info "Output: $(tail -c 300 "$advisor_out") stderr: $(tail -c 300 "$advisor_out.err")"
    fi
}

# --- Ladder integrity ---

test_ladder_order_documented() {
    local wizard="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$wizard" ]; then
        fail "CLAUDE_CODE_SDLC_WIZARD.md not found"
        return
    fi
    if grep -qi 'escalat\|brain\|advisor\|cross-model' "$wizard"; then
        pass "Wizard doc references escalation/brain/advisor pattern"
    else
        fail "Wizard doc has no escalation/brain/advisor reference"
    fi
}

test_95_confidence_threshold() {
    local found=0
    local files=("$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md" "$REPO_ROOT/skills/sdlc/SKILL.md" "$REPO_ROOT/skills/setup/SKILL.md")
    for f in "${files[@]}"; do
        if [ -f "$f" ] && grep -qi '95%.*confiden\|confiden.*95%\|<95%' "$f"; then
            found=$((found + 1))
        fi
    done
    if [ "$found" -ge 2 ]; then
        pass "95% confidence threshold documented in $found shipped files"
    else
        fail "95% confidence threshold found in only $found files (need >=2)"
    fi
}

# --- Run tests ---

echo "=== Escalation Ladder E2E Tests (isolated) ==="
echo "Test home: $TEST_HOME"
echo ""

echo "=== Rung 1: Opus builder ==="
test_builder_is_opus

echo ""
echo "=== Rung 2: GPT-5.6 Sol ==="
test_review_leg_script_exists
test_review_leg_default_model
test_sol_reachable

echo ""
echo "=== Rung 3: Fable 5 advisor ==="
test_advisor_model_configured
test_advisor_reachable

echo ""
echo "=== Ladder integrity ==="
test_ladder_order_documented
test_95_confidence_threshold

# --- Results ---

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
