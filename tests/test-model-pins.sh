#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

# Shipped docs that consumers read
WIZARD="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
LANES="$REPO_ROOT/AI_SETUP_LANES.md"
SDLC_SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
SETUP_SKILL="$REPO_ROOT/skills/setup/SKILL.md"
UPDATE_SKILL="$REPO_ROOT/skills/update/SKILL.md"
REVIEW_SCRIPT="$REPO_ROOT/scripts/run-review-leg.sh"

SHIPPED_DOCS=("$WIZARD" "$LANES" "$SDLC_SKILL" "$SETUP_SKILL" "$UPDATE_SKILL")

# --- Frontier lane: Opus 5 must appear ---

test_frontier_opus_55() {
    local found=0
    for f in "${SHIPPED_DOCS[@]}"; do
        if [ -f "$f" ] && grep -qi 'opus.5\.5\|claude-opus-5' "$f"; then
            found=$((found + 1))
        fi
    done
    if [ "$found" -ge 2 ]; then
        pass "Opus 5 referenced in $found shipped docs"
    else
        fail "Opus 5 referenced in only $found shipped docs (need >=2)"
    fi
}

# --- Reviewer: Sol must be the default ---

test_sol_in_docs() {
    local found=0
    for f in "${SHIPPED_DOCS[@]}"; do
        if [ -f "$f" ] && grep -qi 'GPT-5\.6.*Sol\|gpt-5\.6-sol\|Sol.*review' "$f"; then
            found=$((found + 1))
        fi
    done
    if [ "$found" -ge 2 ]; then
        pass "GPT-5.6 Sol referenced in $found shipped docs"
    else
        fail "GPT-5.6 Sol referenced in only $found shipped docs (need >=2)"
    fi
}

test_sol_is_review_default() {
    local default_model
    default_model=$(grep -o 'REVIEW_MODEL:-[^}]*' "$REVIEW_SCRIPT" | head -1)
    if echo "$default_model" | grep -q 'sol\|5\.6'; then
        pass "run-review-leg.sh defaults to Sol: $default_model"
    else
        fail "run-review-leg.sh defaults to $default_model — should be gpt-5.6-sol"
    fi
}

# --- Advisor: Fable 5 must appear, Fable 5.0 must not ---

test_fable_51_in_docs() {
    local found=0
    for f in "${SHIPPED_DOCS[@]}"; do
        if [ -f "$f" ] && grep -qi 'Fable.5\.1\|claude-fable-5' "$f"; then
            found=$((found + 1))
        fi
    done
    if [ "$found" -ge 2 ]; then
        pass "Fable 5 referenced in $found shipped docs"
    else
        fail "Fable 5 referenced in only $found shipped docs (need >=2)"
    fi
}

test_no_stale_fable_5() {
    # claude-fable-5 IS the correct model ID (no point releases exist).
    # Flag only stale claude-fable-5-1 references (the old wrong ID).
    local stale=0
    for f in "${SHIPPED_DOCS[@]}"; do
        if [ -f "$f" ] && grep -q 'claude-fable-5-1' "$f" 2>/dev/null; then
            stale=$((stale + 1))
        fi
    done
    if [ "$stale" -eq 0 ]; then
        pass "No stale claude-fable-5-1 refs in shipped docs"
    else
        fail "$stale shipped docs still reference claude-fable-5-1 (should be claude-fable-5)"
    fi
}

# --- No stale GPT-5.5 in live guidance (historical citations OK) ---

test_no_stale_gpt55_guidance() {
    # GPT-5.5 IS the Reliable lane's cross-model reviewer.
    # Flag only GPT-5.5 refs that are NOT in a Reliable context.
    # GPT-5.5 in Reliable guidance is correct; GPT-5.5 in Frontier/generic guidance is stale.
    local stale=0
    for f in "${SHIPPED_DOCS[@]}"; do
        if [ -f "$f" ]; then
            if grep -i 'GPT-5\.5' "$f" 2>/dev/null | grep -vi 'historical\|archive\|Vending-Bench\|citation\|was\|legacy\|retires\|retired\|previously\|Reliable\|reliable\|Opus 4\.6\|provenance\|field-proven\|dogfooded\|First brain\|Codex CLI\|concurred\|design review\|Cross-model\|adopt\|Mixed-mode\|reviewing.*escalating' > /dev/null; then
                stale=$((stale + 1))
            fi
        fi
    done
    if [ "$stale" -eq 0 ]; then
        pass "No stale GPT-5.5 outside Reliable-lane context"
    else
        fail "$stale shipped docs have GPT-5.5 outside Reliable-lane context"
    fi
}

# --- Run tests ---

echo "=== Model Pin Tests ==="

echo ""
echo "--- Frontier: Opus 5 ---"
test_frontier_opus_55

echo ""
echo "--- Reviewer: GPT-5.6 Sol ---"
test_sol_in_docs
test_sol_is_review_default

echo ""
echo "--- Advisor: Fable 5 ---"
test_fable_51_in_docs
test_no_stale_fable_5

echo ""
echo "--- No stale GPT-5.5 ---"
test_no_stale_gpt55_guidance

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
