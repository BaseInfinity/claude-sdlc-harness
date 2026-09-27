#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVE="$REPO_ROOT/scripts/derive-dist-tag.sh"

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

test_case() {
    local version="$1"
    local expected="$2"
    local description="$3"
    local actual
    local exit_code

    actual=$("$DERIVE" "$version" 2>/dev/null) && exit_code=0 || exit_code=$?

    if [ "$expected" = "ERROR" ]; then
        if [ "$exit_code" -ne 0 ]; then
            pass "$description: $version → error (exit $exit_code)"
        else
            fail "$description: $version → expected error, got '$actual'"
        fi
    else
        if [ "$exit_code" -eq 0 ] && [ "$actual" = "$expected" ]; then
            pass "$description: $version → $actual"
        else
            fail "$description: $version → expected '$expected', got '$actual' (exit $exit_code)"
        fi
    fi
}

# --- Tests ---

# Script must exist and be executable
if [ ! -x "$DERIVE" ]; then
    fail "scripts/derive-dist-tag.sh does not exist or is not executable"
    echo ""
    echo "=== Results ==="
    echo "Passed: $PASSED"
    echo "Failed: $FAILED"
    exit 1
fi

# Stable releases → latest
test_case "1.100.0" "latest" "stable release"
test_case "2.0.0" "latest" "major stable"
test_case "0.1.0" "latest" "pre-1.0 stable"

# Prerelease with alpha label → extract label
test_case "2.0.0-frontier.0" "frontier" "frontier prerelease"
test_case "2.0.0-frontier.1" "frontier" "frontier prerelease bump"
test_case "1.5.0-beta.1" "beta" "beta prerelease"
test_case "1.0.0-alpha.0" "alpha" "alpha prerelease"
test_case "3.0.0-rc1.0" "rc1" "rc with digit"
test_case "2.0.0-canary.42" "canary" "canary prerelease"

# Prerelease with hyphenated label → first segment
test_case "2.0.0-alpha-beta.1" "alpha-beta" "hyphenated label"

# Numeric-only prerelease → error (not a valid npm dist-tag)
test_case "2.0.0-0.3.7" "ERROR" "numeric prerelease"
test_case "1.0.0-0" "ERROR" "bare numeric prerelease"

# No argument → error
test_case "" "ERROR" "empty version"

# --- Results ---

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
