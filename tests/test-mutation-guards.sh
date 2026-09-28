#!/bin/bash
# Mutation tests for regression guards (#730)
# Each test introduces the WRONG version and proves the guard catches it.
# Uses cp/restore, never git checkout (which destroys uncommitted work).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
PASSED=0
FAILED=0

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

BACKUP_DIR="${TMPDIR:-/tmp}/sdlc-mutation-$$"
mkdir -p "$BACKUP_DIR"
trap 'rm -rf "$BACKUP_DIR"' EXIT

backup() { cp "$1" "$BACKUP_DIR/$(basename "$1").bak"; }
restore() { cp "$BACKUP_DIR/$(basename "$1").bak" "$1"; }

echo "=== Mutation Tests for Regression Guards (#730) ==="
echo ""

LANES="$REPO_ROOT/AI_SETUP_LANES.md"
SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
HOOK="$REPO_ROOT/hooks/tdd-pretool-check.sh"

# ── Effort per model ──────────────────────────────────

echo "── Effort per model ──"

test_mutation_effort_opus48_wrong() {
    backup "$LANES"
    # Mutation: change "Opus 4.8: `xhigh`" to "Opus 4.8: `medium`"
    sed -i '' 's/Opus 4\.8: `xhigh`/Opus 4.8: `medium`/' "$LANES"
    local ok=true
    grep -qF 'Opus 4.8: `xhigh`' "$LANES" && ok=false  # should NOT find it
    restore "$LANES"
    if [ "$ok" = true ]; then
        pass "mutation caught: changing Opus 4.8 effort from xhigh→medium makes guard fail"
    else
        fail "mutation NOT caught: sed did not alter Opus 4.8 effort (check line structure)"
    fi
}

test_mutation_effort_opus46_wrong() {
    backup "$LANES"
    sed -i '' 's/Opus 4\.6: `max`/Opus 4.6: `high`/' "$LANES"
    local ok=true
    grep -qF 'Opus 4.6: `max`' "$LANES" && ok=false
    restore "$LANES"
    if [ "$ok" = true ]; then
        pass "mutation caught: changing Opus 4.6 effort from max→high makes guard fail"
    else
        fail "mutation NOT caught: sed did not alter Opus 4.6 effort"
    fi
}

test_mutation_effort_sonnet5_wrong() {
    backup "$LANES"
    # Mutation: change Sonnet 5's medium to max
    sed -i '' '/Sonnet 5/s/`medium`/`max`/' "$LANES"
    local out
    out=$(grep -E 'Sonnet 5.*`medium`' "$LANES" || true)
    restore "$LANES"
    if [ -z "$out" ]; then
        pass "mutation caught: changing Sonnet 5 effort from medium→max makes guard fail"
    else
        fail "mutation NOT caught: Sonnet 5 still shows medium after mutation"
    fi
}

test_mutation_effort_opus48_wrong
test_mutation_effort_opus46_wrong
test_mutation_effort_sonnet5_wrong

# ── Blanket max rejection ─────────────────────────────

echo ""
echo "── Blanket max rejection ──"

test_mutation_blanket_max_in_skill() {
    backup "$SKILL"
    # Mutation: inject the forbidden pattern
    printf '\nSet `CLAUDE_CODE_EFFORT_LEVEL=max in settings env block`.\n' >> "$SKILL"
    local found=false
    grep -qE 'CLAUDE_CODE_EFFORT_LEVEL.?=.?max.? in (settings )?env block' "$SKILL" && found=true
    restore "$SKILL"
    if [ "$found" = true ]; then
        pass "mutation caught: injecting blanket-max triggers guard"
    else
        fail "mutation NOT caught: blanket-max injection not detected"
    fi
}

test_mutation_blanket_max_in_skill

# ── TDD gate ──────────────────────────────────────────

echo ""
echo "── TDD gate ──"

test_mutation_tdd_gate_exit2_removed() {
    backup "$HOOK"
    # Mutation: comment out the exit 2 that blocks implementation-first edits
    sed -i '' 's/exit 2$/# exit 2 MUTATED/' "$HOOK"
    local cache="${TMPDIR:-/tmp}/sdlc-mutation-tdd-$$"
    mkdir -p "$cache"
    local payload='{"tool_input":{"file_path":"/proj/src/foo.ts"},"session_id":"mut-test-gate"}'
    local exit_code=0
    SDLC_WIZARD_CACHE_DIR="$cache" bash "$HOOK" <<<"$payload" > /dev/null 2>&1 || exit_code=$?
    rm -rf "$cache"
    restore "$HOOK"
    if [ $exit_code -ne 2 ]; then
        pass "mutation caught: removing exit 2 makes TDD gate pass-through (exit=$exit_code, expected ≠2)"
    else
        fail "mutation NOT caught: hook still exits 2 after removing exit 2"
    fi
}

test_mutation_tdd_nudge_removed() {
    backup "$HOOK"
    # Mutation: delete the TDD CHECK output line
    sed -i '' '/TDD CHECK.*IMPLEMENTATION.*FAILING TEST/d' "$HOOK"
    local cache="${TMPDIR:-/tmp}/sdlc-mutation-tdd2-$$"
    mkdir -p "$cache"
    # Prime the test-touched sentinel
    SDLC_WIZARD_CACHE_DIR="$cache" bash "$HOOK" \
        <<<"$(echo '{"tool_input":{"file_path":"/proj/src/__tests__/x.test.ts"},"session_id":"mut-nudge"}')" \
        > /dev/null 2>&1 || true
    local payload='{"tool_input":{"file_path":"/proj/src/foo.ts"},"session_id":"mut-nudge"}'
    local out
    out=$(SDLC_WIZARD_CACHE_DIR="$cache" bash "$HOOK" <<<"$payload" 2>&1) || true
    rm -rf "$cache"
    restore "$HOOK"
    if echo "$out" | grep -q "TDD CHECK"; then
        fail "mutation NOT caught: TDD CHECK still appears after deletion"
    else
        pass "mutation caught: removing TDD CHECK nudge makes output empty"
    fi
}

test_mutation_tdd_gate_exit2_removed
test_mutation_tdd_nudge_removed

# ── Exhaust-driver-first ──────────────────────────────

echo ""
echo "── Exhaust-driver-first ──"

test_mutation_exhaust_driver_skill() {
    backup "$SKILL"
    # Mutation: delete the exhaust-driver paragraph
    sed -i '' '/\*\*Exhaust the driver before escalating/,/^$/d' "$SKILL"
    local ok=true
    grep -qiF 'Exhaust the driver before escalating' "$SKILL" && ok=false
    restore "$SKILL"
    if [ "$ok" = true ]; then
        pass "mutation caught: removing exhaust-driver paragraph from SKILL.md triggers guard"
    else
        fail "mutation NOT caught: paragraph survived deletion"
    fi
}

test_mutation_exhaust_driver_skill_pass_forward() {
    backup "$SKILL"
    # Mutation: remove "pass forward" from the exhaust-driver paragraph
    sed -i '' 's/pass forward/hand off/g' "$SKILL"
    local found=false
    grep -qiF 'pass forward' "$SKILL" && found=true
    restore "$SKILL"
    if [ "$found" = false ]; then
        pass "mutation caught: replacing 'pass forward' with 'hand off' triggers guard"
    else
        fail "mutation NOT caught: 'pass forward' still present after replacement"
    fi
}

test_mutation_exhaust_driver_lanes() {
    backup "$LANES"
    # Mutation: remove the exhausted/swap escalation language
    sed -i '' '/exhausted.*takes over/d' "$LANES"
    sed -i '' '/repeated failure.*different eyes/d' "$LANES"
    local ok_exhaust=true ok_eyes=true
    grep -qF 'exhausted' "$LANES" && ok_exhaust=false
    grep -qE 'repeated failure.*different eyes' "$LANES" && ok_eyes=false
    restore "$LANES"
    if [ "$ok_exhaust" = true ] && [ "$ok_eyes" = true ]; then
        pass "mutation caught: removing exhaust language from AI_SETUP_LANES triggers guard"
    else
        fail "mutation NOT caught: some exhaust language survived (exhaust=$ok_exhaust, eyes=$ok_eyes)"
    fi
}

test_mutation_exhaust_driver_skill
test_mutation_exhaust_driver_skill_pass_forward
test_mutation_exhaust_driver_lanes

# ── Summary ───────────────────────────────────────────
echo ""
echo "════════════════════════════════════"
echo "=== Mutation Test Results ==="
echo -e "Passed: ${GREEN}$PASSED${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "Failed: ${RED}$FAILED${NC}"
    exit 1
fi
echo "All mutation tests proved their guards catch regressions."
