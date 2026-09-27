#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

SUITES_PASSED=0
SUITES_FAILED=0
SUITES_SKIPPED=0

run_suite() {
    local script="$1"
    local name
    name=$(basename "$script" .sh)
    local needs_sub="${2:-false}"

    if [ ! -x "$script" ]; then
        echo -e "${YELLOW}SKIP${NC}: $name (not found or not executable)"
        SUITES_SKIPPED=$((SUITES_SKIPPED + 1))
        return
    fi

    if [ "$needs_sub" = "true" ] && [ "${RUN_LIVE:-false}" != "true" ]; then
        echo -e "${YELLOW}SKIP${NC}: $name (needs live subs — run with RUN_LIVE=true)"
        SUITES_SKIPPED=$((SUITES_SKIPPED + 1))
        return
    fi

    echo -e "\n--- $name ---"
    if "$script"; then
        echo -e "${GREEN}SUITE PASS${NC}: $name"
        SUITES_PASSED=$((SUITES_PASSED + 1))
    else
        echo -e "${RED}SUITE FAIL${NC}: $name"
        SUITES_FAILED=$((SUITES_FAILED + 1))
    fi
}

echo "=== Local Test Runner ==="
echo "RUN_LIVE=${RUN_LIVE:-false} (set RUN_LIVE=true for tests that call Sol/advisor)"
echo ""

# Free tests (no API calls)
run_suite "$SCRIPT_DIR/test-derive-dist-tag.sh"
run_suite "$SCRIPT_DIR/test-release-workflow.sh"
run_suite "$SCRIPT_DIR/test-version-logic.sh"
run_suite "$SCRIPT_DIR/test-analysis-schema.sh"
run_suite "$SCRIPT_DIR/test-doc-consistency.sh"

# Live tests (use your Max + OpenAI subs)
run_suite "$SCRIPT_DIR/test-escalation-ladder.sh" true

echo ""
echo "=== Summary ==="
echo -e "Passed: ${GREEN}$SUITES_PASSED${NC}"
echo -e "Failed: ${RED}$SUITES_FAILED${NC}"
echo -e "Skipped: ${YELLOW}$SUITES_SKIPPED${NC}"

if [ $SUITES_FAILED -gt 0 ]; then
    exit 1
fi
