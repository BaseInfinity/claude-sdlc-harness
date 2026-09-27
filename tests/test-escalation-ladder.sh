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

# --- Rung 1: Opus builder (reads REAL config) ---

test_opus_model_configured() {
    local model
    model=$(python3 -c "
import json
s = json.load(open('$HOME/.claude/settings.json'))
print(s.get('model', 'NOT SET'))
")
    if [[ "$model" == *"opus"* ]]; then
        pass "Opus builder model configured: $model"
    else
        fail "Builder model is not Opus: $model"
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

# --- Rung 3: Fable 5.1 via advisor() ---

test_advisor_model_configured() {
    local advisor
    advisor=$(python3 -c "
import json
s = json.load(open('$HOME/.claude/settings.json'))
print(s.get('advisorModel', 'NOT SET'))
")
    if [ "$advisor" = "claude-fable-5-1" ]; then
        pass "advisorModel pinned to claude-fable-5-1"
    elif [ "$advisor" = "fable" ]; then
        info "advisorModel is 'fable' (alias — resolves to 5.1 on CC >=2.1.257)"
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
    info "Calling advisor() in isolated session (Fable 5.1)..."
    local advisor_out="$TEST_HOME/advisor-response.json"
    claude -p "Call advisor() now. Say only: ADVISOR_OK" \
        --settings "$TEST_HOME/.claude/settings.json" \
        --output-format json > "$advisor_out" 2>&1 || true

    if [ ! -s "$advisor_out" ]; then
        fail "advisor() produced no output"
        return
    fi

    if grep -q '"advisor_tool_result"\|"advisor_redacted_result"' "$advisor_out"; then
        pass "advisor() returned an advisor_tool_result (Fable 5.1 responded)"
    elif grep -q 'authentication_failed\|Not logged in' "$advisor_out"; then
        fail "advisor() auth failed — check Max subscription"
    else
        fail "advisor() output missing advisor_tool_result"
        info "Output: $(tail -3 "$advisor_out")"
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
test_opus_model_configured

echo ""
echo "=== Rung 2: GPT-5.6 Sol ==="
test_review_leg_script_exists
test_review_leg_default_model
test_sol_reachable

echo ""
echo "=== Rung 3: Fable 5.1 advisor ==="
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
