#!/bin/bash
# Test scenario rotation logic for multi-scenario CI
#
# Tests the round-robin selection that picks different scenarios
# for different PR numbers while remaining deterministic.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/scenario-selector.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASSED=0
FAILED=0

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

echo "=== Scenario Rotation Tests ==="
echo ""

SCENARIOS_DIR="$SCRIPT_DIR/scenarios"

# Test 1: Returns a valid scenario file
test_returns_valid_file() {
    local result
    result=$(select_scenario "$SCENARIOS_DIR" 1)
    if [ -f "$result" ]; then
        pass "PR #1: returns valid file ($result)"
    else
        fail "PR #1: file not found: $result"
    fi
}

# Test 2: Same PR number always returns same scenario (deterministic)
test_deterministic() {
    local result1 result2
    result1=$(select_scenario "$SCENARIOS_DIR" 42)
    result2=$(select_scenario "$SCENARIOS_DIR" 42)
    if [ "$result1" = "$result2" ]; then
        pass "Deterministic: PR #42 returns same scenario twice"
    else
        fail "Not deterministic: got '$result1' then '$result2'"
    fi
}

# Test 3: Different PR numbers can return different scenarios
test_different_prs() {
    local results=()
    local unique_count
    for i in 1 2 3 4 5 6 7 8 9 10 11; do
        results+=("$(select_scenario "$SCENARIOS_DIR" "$i")")
    done
    unique_count=$(printf '%s\n' "${results[@]}" | sort -u | wc -l | tr -d ' ')
    if [ "$unique_count" -gt 1 ]; then
        pass "Different PRs get different scenarios ($unique_count unique out of 11)"
    else
        fail "All 11 PRs got the same scenario"
    fi
}

# Test 4: All returned files end in .md
test_md_extension() {
    local all_md=true
    for i in 1 2 3 4 5; do
        local result
        result=$(select_scenario "$SCENARIOS_DIR" "$i")
        if [[ "$result" != *.md ]]; then
            all_md=false
            break
        fi
    done
    if [ "$all_md" = "true" ]; then
        pass "All selected scenarios are .md files"
    else
        fail "Non-.md file returned"
    fi
}

# Test 5: PR number 0 works (edge case)
test_pr_zero() {
    local result
    result=$(select_scenario "$SCENARIOS_DIR" 0)
    if [ -f "$result" ]; then
        pass "PR #0: returns valid file"
    else
        fail "PR #0: file not found: $result"
    fi
}

# Test 6: Large PR number works
test_large_pr() {
    local result
    result=$(select_scenario "$SCENARIOS_DIR" 99999)
    if [ -f "$result" ]; then
        pass "PR #99999: returns valid file"
    else
        fail "PR #99999: file not found: $result"
    fi
}

# Test 7: list_scenarios returns all scenario files
test_list_scenarios() {
    local count
    count=$(list_scenarios "$SCENARIOS_DIR" | wc -l | tr -d ' ')
    local actual_count
    actual_count=$(ls "$SCENARIOS_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" = "$actual_count" ] && [ "$count" -gt 0 ]; then
        pass "list_scenarios returns all $count scenarios"
    else
        fail "list_scenarios returned $count, expected $actual_count"
    fi
}

# Test 8: Handles push events (no PR number) with fallback
test_push_fallback() {
    local result
    result=$(select_scenario "$SCENARIOS_DIR" "")
    if [ -f "$result" ]; then
        pass "Empty PR number: falls back to valid file"
    else
        fail "Empty PR number: file not found: $result"
    fi
}

# -----------------------------------------------
# Fixture extraction tests
# -----------------------------------------------

echo ""
echo "--- Fixture extraction ---"

# Test 9: get_fixture_for_scenario extracts fixture name from header
test_fixture_extraction() {
    local fixture
    fixture=$(get_fixture_for_scenario "$SCENARIOS_DIR/add-feature.md")
    if [ "$fixture" = "test-repo" ]; then
        pass "get_fixture_for_scenario extracts 'test-repo' from add-feature.md"
    else
        fail "Expected fixture 'test-repo', got '$fixture'"
    fi
}

# Test 10: get_fixture_for_scenario defaults to 'test-repo' when no header
test_fixture_default() {
    local tmpfile
    tmpfile=$(mktemp "${TMPDIR:-/tmp}/scenario.XXXXXX")
    echo "# Scenario: No Fixture Header" > "$tmpfile"
    echo "## Task" >> "$tmpfile"
    echo "Do something" >> "$tmpfile"
    local fixture
    fixture=$(get_fixture_for_scenario "$tmpfile")
    if [ "$fixture" = "test-repo" ]; then
        pass "get_fixture_for_scenario defaults to 'test-repo' when no Fixture header"
    else
        fail "Expected default 'test-repo', got '$fixture'"
    fi
    rm -f "$tmpfile"
}

# Test 11: All scenarios have ## Fixture header
test_all_scenarios_have_fixture() {
    local missing=0
    local missing_files=""
    while IFS= read -r scenario; do
        if ! grep -q '^## Fixture' "$scenario"; then
            missing=$((missing + 1))
            missing_files="$missing_files $(basename "$scenario")"
        fi
    done < <(list_scenarios "$SCENARIOS_DIR")
    if [ "$missing" -eq 0 ]; then
        pass "All scenarios have ## Fixture header"
    else
        fail "$missing scenarios missing ## Fixture header:$missing_files"
    fi
}

# Test 12: Scenario count is at least 16 (13 existing + 3 new)
test_scenario_count() {
    local count
    count=$(list_scenarios "$SCENARIOS_DIR" | wc -l | tr -d ' ')
    if [ "$count" -ge 16 ]; then
        pass "At least 16 scenarios present ($count found)"
    else
        fail "Expected at least 16 scenarios, got $count"
    fi
}

# Test 13: New scenarios target test-repo fixture gaps
test_new_scenarios_exist() {
    local ok=true
    [ -f "$SCENARIOS_DIR/expand-test-coverage.md" ] || ok=false
    [ -f "$SCENARIOS_DIR/add-batch-operations.md" ] || ok=false
    [ -f "$SCENARIOS_DIR/add-task-persistence.md" ] || ok=false
    if [ "$ok" = true ]; then
        pass "3 new gap-filling scenarios exist"
    else
        fail "Missing new scenarios: expand-test-coverage, add-batch-operations, add-task-persistence"
    fi
}

# Run all tests
test_returns_valid_file
test_deterministic
test_different_prs
test_md_extension
test_pr_zero
test_large_pr
test_list_scenarios
test_push_fallback
test_fixture_extraction
test_fixture_default
test_all_scenarios_have_fixture
test_scenario_count
test_new_scenarios_exist

echo ""
echo "=========================================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=========================================="

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All scenario rotation tests passed!"
