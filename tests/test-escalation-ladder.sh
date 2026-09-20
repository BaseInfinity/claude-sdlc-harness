#!/bin/bash
# Tests for the brain escalation ladder (#707).
#
# The Workhorse flavor: Opus 4.6[1m] max builds, GPT-5.5 xhigh reviews
# (Codex CLI), Fable 5.1 high escalation (advisor). These tests verify
# that scripts/run-review-leg.sh wires the first brain correctly.
#
# Two categories:
#   1. Source-level — grep the script for the expected model and effort pins
#   2. Runtime — stub codex on PATH, run the launcher, assert it received
#      the right -m and -c arguments

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/run-review-leg.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAIL=$((FAIL + 1)); }

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/escalation-ladder-tests.XXXXXX") || {
    echo "FATAL: could not create a temp dir" >&2
    exit 1
}
trap 'rm -rf "$TMPROOT"' EXIT

echo "=== Escalation ladder (#707) ==="
echo ""

# ---------------------------------------------------------------------------
# CATEGORY 1: SOURCE-LEVEL VERIFICATION
# ---------------------------------------------------------------------------

echo "--- Source-level pins ---"

# 1. The review leg script must use GPT-5.5 as the first brain.
if grep -q 'gpt-5.5' "$RUNNER"; then
    pass "run-review-leg.sh pins codex to gpt-5.5"
else
    fail "run-review-leg.sh does not pin codex to gpt-5.5 — first brain is wrong"
fi

# 2. The review leg script must use xhigh effort.
if grep -q 'model_reasoning_effort="xhigh"' "$RUNNER"; then
    pass "run-review-leg.sh pins effort to xhigh"
else
    fail "run-review-leg.sh does not pin effort to xhigh"
fi

# 3. The model pin must not be commented out.
if grep -E '^\s*#.*gpt-5.5' "$RUNNER" | grep -qv '^\s*$'; then
    fail "the gpt-5.5 pin is commented out"
else
    pass "the gpt-5.5 pin is not commented out"
fi

# 4. The effort pin must not be commented out.
if grep -E '^\s*#.*model_reasoning_effort="xhigh"' "$RUNNER" | grep -qv '^\s*$'; then
    fail "the xhigh effort pin is commented out"
else
    pass "the xhigh effort pin is not commented out"
fi

echo ""

# ---------------------------------------------------------------------------
# CATEGORY 2: RUNTIME VERIFICATION
# ---------------------------------------------------------------------------

echo "--- Runtime verification (stub codex) ---"

# Stub codex that records all arguments and produces a conforming verdict.
STUBDIR="$TMPROOT/bin"
mkdir -p "$STUBDIR"
cat > "$STUBDIR/codex" <<'STUB'
#!/bin/bash
# Record all args for the test to inspect.
ARGS_FILE="${STUB_ARGS_FILE:-/dev/null}"
for arg in "$@"; do
    printf '%s\n' "$arg"
done > "$ARGS_FILE"

# Read stdin to EOF (real codex behavior).
cat > /dev/null

# Write a conforming verdict if --output-last-message was passed.
VERDICT_PATH=""
prev=""
for arg in "$@"; do
    if [ "$prev" = "--output-last-message" ]; then VERDICT_PATH="$arg"; fi
    prev="$arg"
done
if [ -n "$VERDICT_PATH" ]; then
    printf '{"verdict":"CERTIFIED","shape":"SOUND","confidence":99,"findings":[]}' > "$VERDICT_PATH"
fi

printf '%s' "${STUB_STDOUT:-VERDICT: CERTIFIED}"
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$STUBDIR/codex"

# Stub gh so the CI probe doesn't hit the network.
cat > "$STUBDIR/gh" <<'STUB'
#!/bin/bash
cat > /dev/null
printf '%s' "${GH_STUB_STDOUT:-validate	pass	1m	https://example/run}"
exit "${GH_STUB_EXIT:-0}"
STUB
chmod +x "$STUBDIR/gh"

export PATH="$STUBDIR:$PATH"

new_leg() {
    local d
    d=$(mktemp -d "$TMPROOT/leg.XXXXXX")
    echo "$d/out.md"
}

# 5. The stub codex receives -m gpt-5.5 at runtime.
out=$(new_leg)
argsfile="$(dirname "$out")/codex-args"
set +e
STUB_ARGS_FILE="$argsfile" \
    "$RUNNER" "$out" 'review this' >/dev/null 2>&1
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
    fail "launcher exited $rc — runtime verification cannot proceed"
elif [ -f "$argsfile" ] && grep -q '^-m$' "$argsfile" && grep -q '^gpt-5\.5$' "$argsfile"; then
    pass "codex received -m gpt-5.5 at runtime"
else
    fail "codex did not receive -m gpt-5.5 at runtime"
    [ -f "$argsfile" ] && echo "  recorded args:" && cat "$argsfile" | head -20
fi

# 6. The stub codex receives model_reasoning_effort="xhigh" at runtime.
if [ -f "$argsfile" ] && grep -q 'model_reasoning_effort="xhigh"' "$argsfile"; then
    pass "codex received model_reasoning_effort=\"xhigh\" at runtime"
else
    fail "codex did not receive model_reasoning_effort=\"xhigh\" at runtime"
fi

echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "Some escalation ladder tests failed"
    exit 1
fi
echo "All escalation ladder tests passed!"
