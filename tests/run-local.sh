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
TOTAL_PASS=0
TOTAL_FAIL=0

run_suite() {
    local script="$1"
    local name
    name=$(basename "$script" .sh)
    if [ ! -x "$script" ]; then
        echo -e "${YELLOW}SKIP${NC}: $name (not found or not executable)"
        SUITES_SKIPPED=$((SUITES_SKIPPED + 1))
        return
    fi

    echo -e "\n--- $name ---"
    local output
    if output=$("$script" 2>&1); then
        local p f
        p=$(echo "$output" | grep -ci 'PASS' || true)
        f=$(echo "$output" | grep -ci 'FAIL' || true)
        TOTAL_PASS=$((TOTAL_PASS + p))
        echo -e "${GREEN}SUITE PASS${NC}: $name ($p checks)"
        SUITES_PASSED=$((SUITES_PASSED + 1))
    else
        local p f
        p=$(echo "$output" | grep -ci 'PASS' || true)
        f=$(echo "$output" | grep -ci 'FAIL' || true)
        TOTAL_PASS=$((TOTAL_PASS + p))
        TOTAL_FAIL=$((TOTAL_FAIL + f))
        echo "$output" | grep -i 'FAIL' || true
        echo -e "${RED}SUITE FAIL${NC}: $name ($f failures)"
        SUITES_FAILED=$((SUITES_FAILED + 1))
    fi
}

echo "=== SDLC Harness — Local Test Runner ==="
echo ""

# ── FREE TESTS (no API calls, no subscriptions) ──────────────────────

echo "── Core: docs, models, shipped surfaces ──"
run_suite "$SCRIPT_DIR/test-doc-consistency.sh"
run_suite "$SCRIPT_DIR/test-model-pins.sh"
run_suite "$SCRIPT_DIR/test-cowork-drift.sh"
run_suite "$SCRIPT_DIR/test-version-logic.sh"
run_suite "$SCRIPT_DIR/test-analysis-schema.sh"
run_suite "$SCRIPT_DIR/test-derive-dist-tag.sh"
run_suite "$SCRIPT_DIR/test-roadmap-integrity.sh"
run_suite "$SCRIPT_DIR/test-docs-usability.sh"

echo ""
echo "── Hooks ──"
run_suite "$SCRIPT_DIR/test-hooks.sh"
run_suite "$SCRIPT_DIR/test-hook-stdin-bounded.sh"
run_suite "$SCRIPT_DIR/test-prompt-hook-fires-once.sh"
run_suite "$SCRIPT_DIR/test-tdd-pretool-fires-once.sh"
run_suite "$SCRIPT_DIR/test-baseline-fires-once.sh"
run_suite "$SCRIPT_DIR/test-stop-hook-terminates.sh"
run_suite "$SCRIPT_DIR/test-token-spike.sh"
run_suite "$SCRIPT_DIR/test-codex-gate-command-position.sh"
run_suite "$SCRIPT_DIR/test-mcp-hook-audit.sh"
run_suite "$SCRIPT_DIR/test-wizard-doc-hook-templates.sh"

echo ""
echo "── Skills & plugin ──"
run_suite "$SCRIPT_DIR/test-skill-graduations.sh"
run_suite "$SCRIPT_DIR/test-plugin.sh"
run_suite "$SCRIPT_DIR/test-agents-md-interop.sh"
run_suite "$SCRIPT_DIR/test-prove-it.sh"
run_suite "$SCRIPT_DIR/test-postmortem-lessons.sh"
run_suite "$SCRIPT_DIR/test-memory-audit-protocol.sh"
run_suite "$SCRIPT_DIR/test-domain-detection.sh"

echo ""
echo "── CLI & installer ──"
run_suite "$SCRIPT_DIR/test-cli.sh"
run_suite "$SCRIPT_DIR/test-install-script.sh"
run_suite "$SCRIPT_DIR/test-wizard-installer.sh"
run_suite "$SCRIPT_DIR/test-setup-path.sh"
run_suite "$SCRIPT_DIR/test-node24-compliance.sh"

echo ""
echo "── Release & workflow ──"
run_suite "$SCRIPT_DIR/test-release-workflow.sh"
run_suite "$SCRIPT_DIR/test-release-dry-run-workflow.sh"
run_suite "$SCRIPT_DIR/test-workflow-triggers.sh"
run_suite "$SCRIPT_DIR/test-release-drift.sh"

echo ""
echo "── Review & merge gates ──"
run_suite "$SCRIPT_DIR/test-merge-gate.sh"
run_suite "$SCRIPT_DIR/test-cross-model-clearance.sh"
run_suite "$SCRIPT_DIR/test-clearance-binds-to-tree.sh"
run_suite "$SCRIPT_DIR/test-evidence-exception-bound.sh"
run_suite "$SCRIPT_DIR/test-review-verdict-schema.sh"
run_suite "$SCRIPT_DIR/test-self-pr-review-skip.sh"
run_suite "$SCRIPT_DIR/test-post-comment.sh"

echo ""
echo "── Mutation tests (regression proof) ──"
run_suite "$SCRIPT_DIR/test-mutation-guards.sh"

echo ""
echo "── Model config & autocompact ──"
run_suite "$SCRIPT_DIR/test-model-config-batch.sh"
run_suite "$SCRIPT_DIR/test-autocompact-methodology.sh"
run_suite "$SCRIPT_DIR/test-cleanup-period-guidance.sh"
run_suite "$SCRIPT_DIR/test-cc-drift-check.sh"
run_suite "$SCRIPT_DIR/test-cc-version-drift.sh"
run_suite "$SCRIPT_DIR/test-api-feature-detection.sh"
run_suite "$SCRIPT_DIR/test-audit-session-load.sh"

echo ""
echo "── Compliance & community ──"
run_suite "$SCRIPT_DIR/test-compliance.sh"
run_suite "$SCRIPT_DIR/test-community-fetch.sh"
run_suite "$SCRIPT_DIR/test-community-paths.sh"
run_suite "$SCRIPT_DIR/test-community-scanner.sh"
run_suite "$SCRIPT_DIR/test-repo-complexity.sh"
run_suite "$SCRIPT_DIR/test-firmware-fixture.sh"
run_suite "$SCRIPT_DIR/test-fixtures-fail-closed.sh"

echo ""
echo "── E2E (evaluation framework, no API) ──"
run_suite "$SCRIPT_DIR/test-external-benchmark.sh"
run_suite "$SCRIPT_DIR/test-effectiveness-scoreboard.sh"
run_suite "$SCRIPT_DIR/test-calibration-scenarios.sh"
run_suite "$SCRIPT_DIR/test-usage-diagnostics.sh"
run_suite "$SCRIPT_DIR/test-sdp-calculation.sh"
run_suite "$SCRIPT_DIR/test-score-analytics.sh"
run_suite "$SCRIPT_DIR/test-cusum.sh"
run_suite "$SCRIPT_DIR/test-stats.sh"
run_suite "$SCRIPT_DIR/test-evaluate-bugs.sh"
run_suite "$SCRIPT_DIR/test-evaluate-cli-mode.sh"
run_suite "$SCRIPT_DIR/test-ground-truth.sh"
run_suite "$SCRIPT_DIR/test-persist-score-history.sh"
run_suite "$SCRIPT_DIR/test-update-skill-cli-version.sh"
run_suite "$SCRIPT_DIR/test-update-skill-step-7-7.sh"
run_suite "$SCRIPT_DIR/test-update-skill-step-7-8.sh"

echo ""
echo "── E2E simulation (no API) ──"
run_suite "$SCRIPT_DIR/../tests/e2e/test-deterministic-checks.sh"
run_suite "$SCRIPT_DIR/../tests/e2e/test-scenario-rotation.sh"
run_suite "$SCRIPT_DIR/../tests/e2e/test-simulation-prompt.sh"
run_suite "$SCRIPT_DIR/../tests/e2e/test-eval-prompt-regression.sh"
run_suite "$SCRIPT_DIR/../tests/e2e/test-eval-validation.sh"
run_suite "$SCRIPT_DIR/../tests/e2e/test-json-extraction.sh"
run_suite "$SCRIPT_DIR/../tests/e2e/test-multi-call-eval.sh"
run_suite "$SCRIPT_DIR/../tests/e2e/test-pairwise-compare.sh"

# ── LIVE TESTS (need Max + OpenAI subs) ──────────────────────────────

echo ""
echo "── Live: uses Max + OpenAI subs ──"
run_suite "$SCRIPT_DIR/test-escalation-ladder.sh"
run_suite "$SCRIPT_DIR/test-run-review-leg.sh"
run_suite "$SCRIPT_DIR/test-review-leg-launcher-required.sh"
run_suite "$SCRIPT_DIR/test-codex-progress-wrapper.sh"
run_suite "$SCRIPT_DIR/test-self-update.sh"
run_suite "$SCRIPT_DIR/test-local-shepherd.sh"

echo ""
echo "════════════════════════════════════"
echo "=== Summary ==="
echo -e "Suites:  ${GREEN}$SUITES_PASSED passed${NC}  ${RED}$SUITES_FAILED failed${NC}  ${YELLOW}$SUITES_SKIPPED skipped${NC}"
echo -e "Checks:  ${GREEN}$TOTAL_PASS passed${NC}  ${RED}$TOTAL_FAIL failed${NC}"
echo "════════════════════════════════════"

if [ $SUITES_FAILED -gt 0 ]; then
    exit 1
fi
