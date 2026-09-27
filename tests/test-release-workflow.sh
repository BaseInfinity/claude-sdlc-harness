#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOW="$REPO_ROOT/.github/workflows/release.yml"

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

# --- Tests ---

test_workflow_exists() {
    if [ -f "$WORKFLOW" ]; then
        pass "release.yml exists"
    else
        fail "release.yml does not exist"
    fi
}

test_yaml_valid() {
    if python3 -c "import yaml; yaml.safe_load(open('$WORKFLOW'))" 2>/dev/null; then
        pass "release.yml is valid YAML"
    else
        fail "release.yml is invalid YAML"
    fi
}

test_trigger_on_tag_push() {
    if grep -A2 'on:' "$WORKFLOW" | grep -q "tags:" && grep -q "'v\*'" "$WORKFLOW"; then
        pass "release.yml triggers on tag push (v*)"
    else
        fail "release.yml does not trigger on tag push (v*)"
    fi
}

test_has_contents_write_permission() {
    if grep -q 'contents: write' "$WORKFLOW"; then
        pass "release.yml has contents: write permission"
    else
        fail "release.yml missing contents: write permission"
    fi
}

# #236(c): the plain "uses actions/checkout@v5" check that used to live here
# duplicated test-node24-compliance.sh's repo-wide action-version checks
# (which action versions everywhere, not what release.yml specifically does)
# — removed; that file is the one home for action-version checks.

test_uses_setup_node_with_registry() {
    if grep -q 'actions/setup-node@v5' "$WORKFLOW" && grep -q 'registry-url' "$WORKFLOW"; then
        pass "release.yml uses setup-node@v5 with registry-url"
    else
        fail "release.yml missing setup-node@v5 with registry-url"
    fi
}

test_uses_gh_release_create() {
    if grep -q 'gh release create' "$WORKFLOW"; then
        pass "release.yml uses gh release create"
    else
        fail "release.yml does not use gh release create"
    fi
}

test_uses_trusted_publishing_not_token() {
    # ROADMAP: v1.75.0 migrated from long-lived NPM_TOKEN to npm Trusted
    # Publishing (OIDC). NODE_AUTH_TOKEN must NOT appear in the publish env
    # — the presence of any auth-token env variable means we slipped back
    # to token-based publishing.
    if grep -qE '^[[:space:]]*NODE_AUTH_TOKEN:' "$WORKFLOW"; then
        fail "release.yml still uses NODE_AUTH_TOKEN — must use npm Trusted Publishing (OIDC) instead. ROADMAP: drop NPM_TOKEN dependency."
    elif ! grep -q 'id-token: write' "$WORKFLOW"; then
        fail "release.yml is missing 'id-token: write' permission required for npm Trusted Publishing OIDC"
    else
        pass "release.yml uses npm Trusted Publishing (OIDC) — no long-lived token"
    fi
}

test_upgrades_npm_for_trusted_publishing() {
    # npm Trusted Publishing requires npm CLI ≥11.5.1. There are two valid
    # strategies in release.yml: (a) use a Node version that ships npm 11.x
    # natively (Node 24+), or (b) run `npm install -g npm@latest` before
    # publish to bump the CLI in place. v1.75.0 tried (b) and hit the npm
    # MODULE_NOT_FOUND self-upgrade bug; v1.75.1 switched to (a).
    #
    # The test now accepts either approach:
    # 1. node-version: 24 (or higher) in actions/setup-node — npm 11+ baked in
    # 2. An explicit `npm install -g npm@(latest|11.|12.|...)` step BEFORE publish
    #
    # If approach (a), also require an explicit `npm --version` check to
    # fail-loudly if Node ever ships an older npm than expected (so the
    # publish doesn't silently fall back to token mode like in v1.74.0).
    local node_version
    node_version=$(grep -E '^[[:space:]]+node-version:[[:space:]]*[0-9]+' "$WORKFLOW" | head -1 | grep -oE '[0-9]+' | head -1)
    local publish_line
    publish_line=$(grep -nE '^[[:space:]]+run:[[:space:]]*npm publish' "$WORKFLOW" | head -1 | cut -d: -f1)
    local upgrade_line
    # Match actual command lines only, NOT comments. YAML comments start
    # with `#` after optional whitespace; exclude those so the explanatory
    # comment in release.yml about the legacy v1.75.0 step doesn't false-match.
    upgrade_line=$(grep -nE '^[[:space:]]*[^#[:space:]].*npm install -g npm@(latest|1[1-9]\.)' "$WORKFLOW" | head -1 | cut -d: -f1)
    local has_version_check
    has_version_check=$(grep -cE '(npm --version|NPM_VERSION=\$\(npm --version\))' "$WORKFLOW" || echo 0)

    if [ -z "$publish_line" ]; then
        fail "release.yml has no 'npm publish' line — workflow incomplete"
        return
    fi

    # Mutual exclusivity check (per CHANGELOG.md v1.75.1 claim and Codex
    # round-1 P1#2): once we're on Node 24+, the in-place `npm install -g
    # npm@latest` upgrade should NEVER reappear — it's the very pattern
    # that caused MODULE_NOT_FOUND: promise-retry on v1.75.0. Fail loudly
    # if both Node 24+ AND the flaky upgrade step coexist.
    if [ -n "$node_version" ] && [ "$node_version" -ge 24 ] && [ -n "$upgrade_line" ]; then
        fail "release.yml uses Node $node_version (ships npm 11+ natively) AND has 'npm install -g npm@…' at line $upgrade_line — the in-place upgrade is unreliable (MODULE_NOT_FOUND bug, v1.75.0 incident). Remove the upgrade step; Node 24+ already provides npm 11.x."
        return
    fi

    # Strategy (a): Node 24+ with version verification
    if [ -n "$node_version" ] && [ "$node_version" -ge 24 ] && [ "$has_version_check" -ge 1 ]; then
        pass "release.yml uses Node $node_version (ships npm 11+) with version-check guard — Trusted Publishing requirement met"
        return
    fi

    # Strategy (b): explicit upgrade before publish (back-compat for older Node)
    if [ -n "$upgrade_line" ] && [ "$upgrade_line" -lt "$publish_line" ]; then
        pass "release.yml runs explicit npm upgrade (line $upgrade_line) before publish (line $publish_line)"
        return
    fi

    if [ -n "$node_version" ] && [ "$node_version" -ge 24 ]; then
        fail "release.yml uses Node $node_version (ships npm 11+) but lacks an 'npm --version' guard — without it, a future Node 24 image with downgraded npm would silently fall back to token mode (cf. v1.74.0 EOTP)"
    else
        fail "release.yml must either (a) use node-version >=24 with an 'npm --version' fail-loud check, or (b) include 'npm install -g npm@latest' BEFORE 'npm publish'. Neither found. Trusted Publishing requires npm CLI >=11.5.1."
    fi
}

test_generates_release_notes() {
    if grep -q '\-\-generate-notes' "$WORKFLOW"; then
        pass "release.yml generates release notes automatically"
    else
        fail "release.yml does not generate release notes"
    fi
}

test_npm_publish_step() {
    if grep -q 'npm publish' "$WORKFLOW"; then
        pass "release.yml has npm publish step"
    else
        fail "release.yml missing npm publish step"
    fi
}

test_verifies_tag_on_main() {
    if grep -q 'merge-base --is-ancestor' "$WORKFLOW"; then
        pass "release.yml verifies tag is on main branch"
    else
        fail "release.yml does not verify tag is on main branch"
    fi
}

test_dist_tag_derived_from_version() {
    if grep -q 'DIST_TAG' "$WORKFLOW" && grep -q '\-\-tag' "$WORKFLOW"; then
        pass "release.yml derives dist-tag from version and passes --tag to npm publish"
    else
        fail "release.yml does not derive dist-tag — bare npm publish steals @latest on prerelease tags (#713)"
    fi
}

test_prerelease_skips_main_check() {
    if grep -qE 'prerelease|IS_PRERELEASE|PRERELEASE' "$WORKFLOW"; then
        pass "release.yml allows prerelease tags from non-main branches"
    else
        fail "release.yml forces all tags onto main — blocks frontier publishes (#713)"
    fi
}

test_stable_still_requires_main() {
    if grep -q 'merge-base --is-ancestor' "$WORKFLOW"; then
        pass "release.yml still requires main-branch ancestry for stable releases"
    else
        fail "release.yml lost the main-branch check for stable releases"
    fi
}

test_npm_provenance() {
    # ROADMAP: v1.75.0 migrated to npm Trusted Publishing. Trusted publish
    # auto-generates provenance — the explicit --provenance flag is no
    # longer required (and is incompatible with the token-less mode in
    # some npm CLI versions). Test is now a no-op assertion that provenance
    # remains in force via the trusted-publish path (provenance is implicit
    # when id-token: write is set + publishing via OIDC).
    if grep -q 'id-token: write' "$WORKFLOW"; then
        pass "release.yml provides provenance via Trusted Publishing (id-token: write set)"
    else
        fail "release.yml missing id-token: write permission — required for OIDC + provenance"
    fi
}

test_has_id_token_permission() {
    if grep -q 'id-token: write' "$WORKFLOW"; then
        pass "release.yml has id-token: write permission (required for Trusted Publishing OIDC)"
    else
        fail "release.yml missing id-token: write permission"
    fi
}

test_verifies_version_tag_match() {
    if grep -q 'package.json' "$WORKFLOW" && grep -q 'GITHUB_REF' "$WORKFLOW"; then
        pass "release.yml verifies tag matches package.json version"
    else
        fail "release.yml does not verify tag-version consistency"
    fi
}

# --- Run tests ---

test_workflow_exists
test_yaml_valid
test_trigger_on_tag_push
test_has_contents_write_permission
test_uses_setup_node_with_registry
test_uses_gh_release_create
test_uses_trusted_publishing_not_token
test_upgrades_npm_for_trusted_publishing
test_generates_release_notes
test_npm_publish_step
test_verifies_tag_on_main
test_dist_tag_derived_from_version
test_prerelease_skips_main_check
test_stable_still_requires_main
test_npm_provenance
test_has_id_token_permission
test_verifies_version_tag_match

# --- Results ---

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
