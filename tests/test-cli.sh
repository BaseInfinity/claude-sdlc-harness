#!/bin/bash
# Test CLI distribution tool (agentic-sdlc-wizard)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$SCRIPT_DIR/../cli/bin/sdlc-wizard.js"
PASSED=0
FAILED=0

# Isolate tests from real HOME so plugin install detection (#181) doesn't
# false-trigger in dev environments with the plugin installed. Tests that
# need a specific HOME (marketplace, plugin-detect) override this explicitly.
export HOME="$(mktemp -d "${TMPDIR:-/tmp}/sdlc-cli-test-home-XXXXXX")"
trap 'rm -rf "$HOME"' EXIT

# Color output
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

# Create a fresh temp dir for each test
make_temp() {
    local d
    d=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-cli-test-XXXXXX")
    echo "$d"
}

echo "=== CLI Distribution Tests ==="
echo ""

# Test 1: --help exits 0 and shows usage
test_help() {
    if node "$CLI" --help 2>&1 | grep -q "Usage:"; then
        pass "--help exits 0 and shows usage"
    else
        fail "--help should show usage text"
    fi
}

# Test 2: --version exits 0 and matches package.json
test_version() {
    local cli_version pkg_version
    cli_version=$(node "$CLI" --version 2>&1)
    pkg_version=$(node -e "console.log(require('$SCRIPT_DIR/../package.json').version)")
    if [ "$cli_version" = "$pkg_version" ]; then
        pass "--version ($cli_version) matches package.json"
    else
        fail "--version ($cli_version) should match package.json ($pkg_version)"
    fi
}

# Test 3: init --dry-run creates no files
test_dry_run_no_files() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init --dry-run > /dev/null 2>&1)
    if [ ! -d "$d/.claude" ]; then
        pass "init --dry-run creates no files"
    else
        fail "init --dry-run should not create any files"
    fi
    rm -rf "$d"
}

# Test 4: init creates all 19 expected files (hooks + helper + skills + settings + wizard doc)
test_creates_all_files() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local count=0
    [ -f "$d/.claude/settings.json" ] && count=$((count + 1))
    [ -f "$d/.claude/hooks/sdlc-prompt-check.sh" ] && count=$((count + 1))
    [ -f "$d/.claude/hooks/tdd-pretool-check.sh" ] && count=$((count + 1))
    [ -f "$d/.claude/hooks/instructions-loaded-check.sh" ] && count=$((count + 1))
    [ -f "$d/.claude/hooks/model-effort-check.sh" ] && count=$((count + 1))
    [ -f "$d/.claude/hooks/precompact-seam-check.sh" ] && count=$((count + 1))
    [ -f "$d/.claude/hooks/_find-sdlc-root.sh" ] && count=$((count + 1))
    [ -f "$d/.claude/skills/sdlc/SKILL.md" ] && count=$((count + 1))
    [ -f "$d/.claude/skills/setup/SKILL.md" ] && count=$((count + 1))
    [ -f "$d/.claude/skills/update/SKILL.md" ] && count=$((count + 1))
    [ -f "$d/.claude/skills/feedback/SKILL.md" ] && count=$((count + 1))
    [ -f "$d/.claude/skills/conduct/SKILL.md" ] && count=$((count + 1))
    [ -f "$d/.claude/skills/conduct/references/protocol.md" ] && count=$((count + 1))
    [ -f "$d/.claude/skills/conduct/scripts/conduct.cjs" ] && count=$((count + 1))
    [ -x "$d/.claude/skills/conduct/scripts/claude-desktop.sh" ] && count=$((count + 1))
    [ -f "$d/.claude/skills/conduct/scripts/claude-desktop.py" ] && count=$((count + 1))
    [ -f "$d/.claude/skills/conduct/scripts/codex-thread.py" ] && count=$((count + 1))
    [ -x "$d/.claude/skills/conduct/scripts/status.cjs" ] && count=$((count + 1))
    [ -f "$d/CLAUDE_CODE_SDLC_WIZARD.md" ] && count=$((count + 1))
    if [ "$count" -eq 19 ]; then
        pass "init creates all 18 expected files (#254 ships _find-sdlc-root.sh)"
    else
        fail "init should create 19 files, found $count"
    fi
    rm -rf "$d"
}

# Test (#254 Bug 1): _find-sdlc-root.sh helper is shipped and sourceable.
# Hooks `source "$HOOK_DIR/_find-sdlc-root.sh"` and call `dedupe_plugin_or_project`
# defined inside. Without the helper, every session emits stderr noise:
#   "_find-sdlc-root.sh: No such file or directory"
#   "dedupe_plugin_or_project: command not found"
# and the SDLC root walk-up logic is silently dead.
test_init_ships_find_sdlc_root_helper() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local helper="$d/.claude/hooks/_find-sdlc-root.sh"
    if [ ! -f "$helper" ]; then
        fail "#254 Bug 1: _find-sdlc-root.sh not shipped to .claude/hooks/"
        rm -rf "$d"
        return
    fi
    # Helper must define dedupe_plugin_or_project (referenced by hooks)
    if ! grep -q "dedupe_plugin_or_project()" "$helper"; then
        fail "#254 Bug 1: shipped helper missing dedupe_plugin_or_project()"
        rm -rf "$d"
        return
    fi
    # Helper must define find_sdlc_root (referenced by hooks)
    if ! grep -q "find_sdlc_root()" "$helper"; then
        fail "#254 Bug 1: shipped helper missing find_sdlc_root()"
        rm -rf "$d"
        return
    fi
    pass "#254 Bug 1: init ships _find-sdlc-root.sh with required functions"
    rm -rf "$d"
}

# Test (#254 Bug 1): npm pack tarball includes hooks/_find-sdlc-root.sh.
# Catches regressions where package.json `files` whitelist drops the helper —
# even if cli/init.js references it, npm publish wouldn't ship it.
test_npm_pack_includes_find_sdlc_root() {
    if ! command -v npm > /dev/null 2>&1; then
        pass "skipped (npm not available)"
        return
    fi
    local d listing
    d=$(make_temp)
    # `npm pack --dry-run --json` lists files without producing a tarball
    listing=$(cd "$SCRIPT_DIR/.." && npm pack --dry-run --json 2>/dev/null) || {
        fail "#254 Bug 1: npm pack --dry-run failed"
        rm -rf "$d"
        return
    }
    if echo "$listing" | grep -q "hooks/_find-sdlc-root.sh"; then
        pass "#254 Bug 1: npm pack tarball includes hooks/_find-sdlc-root.sh"
    else
        fail "#254 Bug 1: npm pack tarball missing hooks/_find-sdlc-root.sh — package.json files whitelist drops it"
    fi
    rm -rf "$d"
}

# Test (#254 Bug 2): init --force invalidates the version cache so the hook
# re-fetches latest from npm instead of serving stale pre-upgrade values.
# Without bust, post-upgrade hook prints reverse nudge "1.42.1 → 1.41.1".
test_init_force_clears_version_cache() {
    local d cache_dir
    d=$(make_temp)
    cache_dir=$(make_temp)
    # Seed cache with a stale version
    echo "1.41.1" > "$cache_dir/latest-version"
    # Run init --force with cache override
    (cd "$d" && SDLC_WIZARD_CACHE_DIR="$cache_dir" node "$CLI" init --force > /dev/null 2>&1)
    if [ -f "$cache_dir/latest-version" ]; then
        fail "#254 Bug 2: init --force should remove $cache_dir/latest-version, but it still exists"
    else
        pass "#254 Bug 2: init --force invalidates SDLC_WIZARD_CACHE_DIR/latest-version"
    fi
    rm -rf "$d" "$cache_dir"
}

# Test 5: init sets all 5 installed hooks as executable
test_hooks_executable() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local exec_count=0
    [ -x "$d/.claude/hooks/sdlc-prompt-check.sh" ] && exec_count=$((exec_count + 1))
    [ -x "$d/.claude/hooks/tdd-pretool-check.sh" ] && exec_count=$((exec_count + 1))
    [ -x "$d/.claude/hooks/instructions-loaded-check.sh" ] && exec_count=$((exec_count + 1))
    [ -x "$d/.claude/hooks/model-effort-check.sh" ] && exec_count=$((exec_count + 1))
    [ -x "$d/.claude/hooks/precompact-seam-check.sh" ] && exec_count=$((exec_count + 1))
    if [ "$exec_count" -eq 5 ]; then
        pass "init sets all 5 hooks as executable"
    else
        fail "init should set 5 hooks as executable, found $exec_count"
    fi
    rm -rf "$d"
}

# Test 6: init skips existing files without --force
test_skip_existing() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude/hooks"
    echo "existing" > "$d/.claude/settings.json"
    local output
    output=$(cd "$d" && node "$CLI" init 2>&1)
    if echo "$output" | grep -q "SKIP.*settings.json"; then
        # Verify file was NOT overwritten
        local content
        content=$(cat "$d/.claude/settings.json")
        if [ "$content" = "existing" ]; then
            pass "init skips existing files without --force"
        else
            fail "init should not overwrite existing files without --force"
        fi
    else
        fail "init should report SKIP for existing files"
    fi
    rm -rf "$d"
}

# Test 7: init --force overwrites existing files
test_force_overwrite() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude/hooks"
    echo "old" > "$d/.claude/settings.json"
    (cd "$d" && node "$CLI" init --force > /dev/null 2>&1)
    local content
    content=$(cat "$d/.claude/settings.json")
    if [ "$content" != "old" ]; then
        pass "init --force overwrites existing files"
    else
        fail "init --force should overwrite existing files"
    fi
    rm -rf "$d"
}

# Test 8: init creates correct directory structure
test_dir_structure() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local ok=true
    [ -d "$d/.claude/hooks" ] || ok=false
    [ -d "$d/.claude/skills/sdlc" ] || ok=false
    [ -d "$d/.claude/skills/setup" ] || ok=false
    [ -d "$d/.claude/skills/update" ] || ok=false
    if [ "$ok" = true ]; then
        pass "init creates correct directory structure"
    else
        fail "init should create .claude/hooks, .claude/skills/sdlc, .claude/skills/setup, .claude/skills/update"
    fi
    rm -rf "$d"
}

# Test 9: init copies wizard doc
test_wizard_doc() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    if [ -f "$d/CLAUDE_CODE_SDLC_WIZARD.md" ] && grep -q "SDLC Harness" "$d/CLAUDE_CODE_SDLC_WIZARD.md"; then
        pass "init copies wizard doc with correct content"
    else
        fail "init should copy CLAUDE_CODE_SDLC_WIZARD.md"
    fi
    rm -rf "$d"
}

# Test 10: settings.json is valid JSON with 6 hook events
# (UserPromptSubmit, PreToolUse, InstructionsLoaded, SessionStart, PreCompact, Stop)
test_settings_json() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local hook_count
    hook_count=$(python3 -c "
import json, sys
with open('$d/.claude/settings.json') as f:
    data = json.load(f)
hooks = data.get('hooks', {})
print(len(hooks))
" 2>/dev/null)
    if [ "$hook_count" = "6" ]; then
        pass "settings.json is valid JSON with 6 hook events"
    else
        fail "settings.json should have 6 hook events (added Stop, #436), found: $hook_count"
    fi
    rm -rf "$d"
}

# Test 11: .gitignore gets required entries
test_gitignore_append() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local ok=true
    grep -q ".claude/plans/" "$d/.gitignore" || ok=false
    grep -q ".claude/settings.local.json" "$d/.gitignore" || ok=false
    if [ "$ok" = true ]; then
        pass ".gitignore gets required entries"
    else
        fail ".gitignore should contain .claude/plans/ and .claude/settings.local.json"
    fi
    rm -rf "$d"
}

# Test 12: .gitignore entries not duplicated on re-run
test_gitignore_no_dupes() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    (cd "$d" && node "$CLI" init --force > /dev/null 2>&1)
    local count
    count=$(grep -c ".claude/plans/" "$d/.gitignore")
    if [ "$count" -eq 1 ]; then
        pass ".gitignore entries not duplicated on re-run"
    else
        fail ".gitignore should have exactly 1 .claude/plans/ entry, found $count"
    fi
    rm -rf "$d"
}

# Test 13: Template hooks contain expected content
test_hook_content() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local ok=true
    grep -q "SDLC BASELINE" "$d/.claude/hooks/sdlc-prompt-check.sh" || ok=false
    grep -q "claude-setup-wizard" "$d/.claude/hooks/sdlc-prompt-check.sh" || ok=false
    grep -q "TDD CHECK" "$d/.claude/hooks/tdd-pretool-check.sh" || ok=false
    if [ "$ok" = true ]; then
        pass "Template hooks contain expected content"
    else
        fail "Template hooks should contain SDLC BASELINE + claude-setup-wizard (sdlc-prompt-check.sh), TDD CHECK (tdd-pretool-check.sh)"
    fi
    rm -rf "$d"
}

# Test 14: Template skills have correct frontmatter
test_skill_frontmatter() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local ok=true
    grep -q "^name: sdlc$" "$d/.claude/skills/sdlc/SKILL.md" || ok=false
    # v1.84.0: effort is model-aware (see AI_SETUP_LANES.md), so frontmatter
    # deliberately omits a blanket effort field
    grep -qE "^effort:" "$d/.claude/skills/sdlc/SKILL.md" && ok=false
    if [ "$ok" = true ]; then
        pass "Template skills have correct frontmatter (name, no blanket effort field)"
    else
        fail "Skills should have name: sdlc and no blanket effort: field in frontmatter"
    fi
    rm -rf "$d"
}

# Test 15: Template tdd hook uses /src/ pattern (not .github/workflows/)
test_tdd_hook_generic() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    if grep -q '"/src/"' "$d/.claude/hooks/tdd-pretool-check.sh"; then
        if ! grep -q '.github/workflows/' "$d/.claude/hooks/tdd-pretool-check.sh"; then
            pass "Template tdd hook uses /src/ pattern (generic)"
        else
            fail "Template tdd hook should NOT reference .github/workflows/"
        fi
    else
        fail "Template tdd hook should use /src/ pattern"
    fi
    rm -rf "$d"
}

# Test 16: Template settings.json has NO allowedTools key
test_no_allowed_tools() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    if ! grep -q "allowedTools" "$d/.claude/settings.json"; then
        pass "Template settings.json has no allowedTools key"
    else
        fail "Template settings.json should NOT have allowedTools (project-specific)"
    fi
    rm -rf "$d"
}

# Test 17: check on fresh init shows all MATCH
test_check_all_match() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local output
    output=$(cd "$d" && node "$CLI" check 2>&1)
    local exit_code=$?
    if [ "$exit_code" -eq 0 ] && echo "$output" | grep -q "MATCH"; then
        pass "check on fresh init shows MATCH and exits 0"
    else
        fail "check on fresh init should show MATCH and exit 0 (exit=$exit_code)"
    fi
    rm -rf "$d"
}

# Test 18: check on modified file shows CUSTOMIZED
test_check_customized() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    echo "modified" >> "$d/.claude/settings.json"
    local output
    output=$(cd "$d" && node "$CLI" check 2>&1)
    if echo "$output" | grep -q "CUSTOMIZED"; then
        pass "check on modified file shows CUSTOMIZED"
    else
        fail "check should show CUSTOMIZED for modified settings.json"
    fi
    rm -rf "$d"
}

# #383: consumer settings.json with extra hooks should still show MATCH for
# settings.json — the wizard hooks are all present, extras are intentional.
test_check_settings_match_with_extras() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    # Add extra consumer hooks (simulating PDLC or custom project hooks)
    node -e "
      const fs = require('fs');
      const s = JSON.parse(fs.readFileSync('$d/.claude/settings.json','utf8'));
      s.permissions = {allow:['Bash(npm test)']};
      s.hooks.SessionStart[0].hooks.push({type:'command',command:'echo custom-hook'});
      fs.writeFileSync('$d/.claude/settings.json', JSON.stringify(s,null,2)+'\n');
    "
    local output
    output=$(cd "$d" && node "$CLI" check 2>&1)
    if echo "$output" | grep "settings.json" | grep -q "MATCH"; then
        pass "#383: settings.json with extra hooks shows MATCH (wizard hooks present)"
    else
        fail "#383: settings.json with extra hooks should show MATCH, got: $(echo "$output" | grep settings)"
    fi
    rm -rf "$d"
}

# Test 19: check on empty dir shows all MISSING
test_check_all_missing() {
    local d
    d=$(make_temp)
    local output exit_code
    output=$(cd "$d" && node "$CLI" check 2>&1) || exit_code=$?
    exit_code=${exit_code:-0}
    if [ "$exit_code" -ne 0 ] && echo "$output" | grep -q "MISSING"; then
        pass "check on empty dir shows MISSING and exits non-zero"
    else
        fail "check on empty dir should show MISSING and exit non-zero (exit=$exit_code)"
    fi
    rm -rf "$d"
}

# Test 20: check --json outputs valid JSON
test_check_json() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local output
    output=$(cd "$d" && node "$CLI" check --json 2>&1)
    if echo "$output" | python3 -c "import json, sys; json.load(sys.stdin)" 2>/dev/null; then
        pass "check --json outputs valid JSON"
    else
        fail "check --json should output valid JSON"
    fi
    rm -rf "$d"
}

# Test 21: check detects non-executable hook (DRIFT)
test_check_drift_permissions() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    chmod -x "$d/.claude/hooks/sdlc-prompt-check.sh"
    local output exit_code
    output=$(cd "$d" && node "$CLI" check 2>&1) || exit_code=$?
    exit_code=${exit_code:-0}
    if [ "$exit_code" -ne 0 ] && echo "$output" | grep -q "DRIFT"; then
        pass "check detects non-executable hook as DRIFT"
    else
        fail "check should detect non-executable hook (exit=$exit_code)"
    fi
    rm -rf "$d"
}

# Test 22a (#323): check recommends --dry-run when CUSTOMIZED files + UPDATE available
test_check_recommends_dry_run_when_customized() {
    local result
    result=$(node -e "
const { buildUpdateRecommendation } = require('$SCRIPT_DIR/../cli/init.js');
const lines = buildUpdateRecommendation({ current: '1.0.0', latest: '2.0.0' }, 3);
console.log(lines.join('\n'));
" 2>&1) || true
    if echo "$result" | grep -q 'init --dry-run' \
        && echo "$result" | grep -qiE 'customized|preview|overwrite'; then
        pass "#323: check recommends 'init --dry-run' + warning when CUSTOMIZED files exist"
    else
        fail "#323: should recommend --dry-run + warn about customized files. Got: $result"
    fi
}

# Test 22b (#323): check still recommends --force when no CUSTOMIZED files
test_check_recommends_force_when_no_customized() {
    local result
    result=$(node -e "
const { buildUpdateRecommendation } = require('$SCRIPT_DIR/../cli/init.js');
const lines = buildUpdateRecommendation({ current: '1.0.0', latest: '2.0.0' }, 0);
console.log(lines.join('\n'));
" 2>&1) || true
    if echo "$result" | grep -q 'init --force' \
        && ! echo "$result" | grep -q 'init --dry-run'; then
        pass "#323: check recommends 'init --force' when no CUSTOMIZED files (no behavior change)"
    else
        fail "#323: no-customized case should recommend --force, not --dry-run. Got: $result"
    fi
}

# Test 22c (#325 P2 follow-up): buildUpdateRecommendation returns [] for null updateInfo
test_check_recommendation_null_updateinfo() {
    local result
    result=$(node -e "
const { buildUpdateRecommendation } = require('$SCRIPT_DIR/../cli/init.js');
const a = buildUpdateRecommendation(null, 5);
const b = buildUpdateRecommendation(undefined, 5);
console.log(JSON.stringify({ null: a, undefined: b }));
" 2>&1) || true
    if echo "$result" | grep -q '"null":\[\]' \
        && echo "$result" | grep -q '"undefined":\[\]'; then
        pass "#325 P2: buildUpdateRecommendation returns [] for null/undefined updateInfo (no UPDATE → no output)"
    else
        fail "#325 P2: null/undefined updateInfo should produce no recommendation lines. Got: $result"
    fi
}

# Test 22d (#325 P2 follow-up): undefined customizedCount falls through to --force path
test_check_recommendation_undefined_count() {
    local result
    result=$(node -e "
const { buildUpdateRecommendation } = require('$SCRIPT_DIR/../cli/init.js');
const lines = buildUpdateRecommendation({ current: '1.0.0', latest: '2.0.0' });
console.log(lines.join('\n'));
" 2>&1) || true
    if echo "$result" | grep -q 'init --force' \
        && ! echo "$result" | grep -q 'init --dry-run'; then
        pass "#325 P2: undefined customizedCount falls through to --force (defensive default)"
    else
        fail "#325 P2: undefined customizedCount should default to --force path. Got: $result"
    fi
}

# Test 22e (#323 option 2): init --force --preserve-customized skips CUSTOMIZED files
test_init_preserve_customized_skips_customized() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    echo "# user customization" >> "$d/.claude/hooks/sdlc-prompt-check.sh"
    local before_hash
    before_hash=$(shasum -a 256 "$d/.claude/hooks/sdlc-prompt-check.sh" | awk '{print $1}')
    (cd "$d" && node "$CLI" init --force --preserve-customized > /dev/null 2>&1)
    local after_hash
    after_hash=$(shasum -a 256 "$d/.claude/hooks/sdlc-prompt-check.sh" | awk '{print $1}')
    if [ "$before_hash" = "$after_hash" ]; then
        pass "#323 option 2: init --force --preserve-customized skips CUSTOMIZED files (file hash unchanged)"
    else
        fail "#323 option 2: --preserve-customized should NOT overwrite CUSTOMIZED files. Hash changed."
    fi
    rm -rf "$d"
}

# Test 22f (#323 option 2): --preserve-customized still creates MISSING files
test_init_preserve_customized_creates_missing() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    rm "$d/.claude/hooks/tdd-pretool-check.sh"
    (cd "$d" && node "$CLI" init --force --preserve-customized > /dev/null 2>&1)
    if [ -f "$d/.claude/hooks/tdd-pretool-check.sh" ]; then
        pass "#323 option 2: --preserve-customized creates MISSING files (preserve != skip-everything)"
    else
        fail "#323 option 2: --preserve-customized should still create MISSING files"
    fi
    rm -rf "$d"
}

# Test 22g (#323 option 2): regression guard — --force alone still overwrites CUSTOMIZED
test_init_force_alone_still_overwrites() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    echo "# user customization" >> "$d/.claude/hooks/sdlc-prompt-check.sh"
    local before_hash
    before_hash=$(shasum -a 256 "$d/.claude/hooks/sdlc-prompt-check.sh" | awk '{print $1}')
    (cd "$d" && node "$CLI" init --force > /dev/null 2>&1)
    local after_hash
    after_hash=$(shasum -a 256 "$d/.claude/hooks/sdlc-prompt-check.sh" | awk '{print $1}')
    if [ "$before_hash" != "$after_hash" ]; then
        pass "#323 option 2: regression guard — --force alone (no --preserve-customized) still overwrites CUSTOMIZED"
    else
        fail "#323 option 2: --force alone should still overwrite (existing behavior unchanged)"
    fi
    rm -rf "$d"
}

# Test 22h (#327 round-2 P2): --preserve-customized without --force is a no-op
# (existing files all SKIP regardless; the flag composes with --force, doesn't replace it)
test_preserve_customized_without_force_is_noop() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    echo "# user customization" >> "$d/.claude/hooks/sdlc-prompt-check.sh"
    local before_hash
    before_hash=$(shasum -a 256 "$d/.claude/hooks/sdlc-prompt-check.sh" | awk '{print $1}')
    # No --force, just --preserve-customized
    (cd "$d" && node "$CLI" init --preserve-customized > /dev/null 2>&1)
    local after_hash
    after_hash=$(shasum -a 256 "$d/.claude/hooks/sdlc-prompt-check.sh" | awk '{print $1}')
    if [ "$before_hash" = "$after_hash" ]; then
        pass "#323 option 2: --preserve-customized without --force is no-op (existing files unchanged)"
    else
        fail "#323 option 2: --preserve-customized without --force should not modify files. Hash changed."
    fi
    rm -rf "$d"
}

# Test 22i (#327 round-2 P2): settings.json still MERGEs under --force --preserve-customized
# (MERGE branch in planOperations runs BEFORE the customized hash check — settings should
# get its custom-hooks-preserving merge, not be PRESERVED-as-blob)
test_settings_merges_under_preserve_customized() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    # Add a custom hook to settings.json that the merge logic should preserve
    python3 -c "
import json
with open('$d/.claude/settings.json') as f: data = json.load(f)
data.setdefault('hooks', {}).setdefault('UserPromptSubmit', []).append({
    'hooks': [{'type': 'command', 'command': 'echo custom-hook'}]
})
with open('$d/.claude/settings.json', 'w') as f: json.dump(data, f)
"
    local output
    output=$(cd "$d" && node "$CLI" init --force --preserve-customized 2>&1)
    # MERGE action should appear for settings.json (not PRESERVE — merge runs first)
    if echo "$output" | grep -E '(MERGE|OVERWRITE)' | grep -q 'settings.json'; then
        # And the custom hook should still be present after the merge
        if grep -q 'custom-hook' "$d/.claude/settings.json"; then
            pass "#323 option 2: settings.json MERGEs under --force --preserve-customized (custom hooks preserved)"
        else
            fail "#323 option 2: settings.json merge dropped custom hook"
        fi
    else
        fail "#323 option 2: settings.json should be MERGEd (or OVERWRITTEN), not PRESERVEd as blob. Got: $output"
    fi
    rm -rf "$d"
}

# Test 22j (#327 round-2 P2): WIZARD_DOC parity — customized wizard doc gets PRESERVED
test_wizard_doc_preserved_when_customized() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    echo "# user added section" >> "$d/CLAUDE_CODE_SDLC_WIZARD.md"
    local before_hash
    before_hash=$(shasum -a 256 "$d/CLAUDE_CODE_SDLC_WIZARD.md" | awk '{print $1}')
    (cd "$d" && node "$CLI" init --force --preserve-customized > /dev/null 2>&1)
    local after_hash
    after_hash=$(shasum -a 256 "$d/CLAUDE_CODE_SDLC_WIZARD.md" | awk '{print $1}')
    if [ "$before_hash" = "$after_hash" ]; then
        pass "#323 option 2: WIZARD_DOC also respects --preserve-customized (parity with FILES loop)"
    else
        fail "#323 option 2: WIZARD_DOC should be PRESERVEd when customized. Hash changed."
    fi
    rm -rf "$d"
}

# Test 22: check detects missing .gitignore entries (DRIFT)
test_check_drift_gitignore() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    # Replace .gitignore with commented-out entries (should NOT match)
    echo "# .claude/plans/" > "$d/.gitignore"
    echo "# .claude/settings.local.json" >> "$d/.gitignore"
    local output exit_code
    output=$(cd "$d" && node "$CLI" check 2>&1) || exit_code=$?
    exit_code=${exit_code:-0}
    if [ "$exit_code" -ne 0 ] && echo "$output" | grep -q "DRIFT"; then
        pass "check detects commented .gitignore entries as DRIFT"
    else
        fail "check should detect missing .gitignore entries (exit=$exit_code)"
    fi
    rm -rf "$d"
}

# Test 23: Template claude-setup-wizard skill has correct frontmatter
test_setup_wizard_frontmatter() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local ok=true
    grep -q "^name: claude-setup-wizard$" "$d/.claude/skills/setup/SKILL.md" || ok=false
    grep -q "^effort: high$" "$d/.claude/skills/setup/SKILL.md" || ok=false
    if [ "$ok" = true ]; then
        pass "Template claude-setup-wizard skill has correct frontmatter (name + effort)"
    else
        fail "claude-setup-wizard skill should have name: claude-setup-wizard and effort: high in frontmatter"
    fi
    rm -rf "$d"
}

# Test 24: init merges settings.json when existing has valid JSON
test_merge_settings_output() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    cat > "$d/.claude/settings.json" << 'FIXTURE'
{
  "allowedTools": ["Read", "Glob"],
  "hooks": {}
}
FIXTURE
    local output
    output=$(cd "$d" && node "$CLI" init 2>&1)
    if echo "$output" | grep -q "MERGE"; then
        pass "init shows MERGE for existing settings.json with valid JSON"
    else
        fail "init should show MERGE when settings.json exists with valid JSON"
    fi
    rm -rf "$d"
}

# Test 25: merge preserves custom keys and adds wizard hooks
test_merge_preserves_keys() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    cat > "$d/.claude/settings.json" << 'FIXTURE'
{
  "allowedTools": ["Read", "Glob"],
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "bash my-custom-hook.sh" }
        ]
      }
    ]
  }
}
FIXTURE
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local ok=true
    # Custom keys preserved
    grep -q "allowedTools" "$d/.claude/settings.json" || ok=false
    grep -q "my-custom-hook" "$d/.claude/settings.json" || ok=false
    # Wizard hooks added
    grep -q "sdlc-prompt-check" "$d/.claude/settings.json" || ok=false
    grep -q "tdd-pretool-check" "$d/.claude/settings.json" || ok=false
    grep -q "instructions-loaded-check" "$d/.claude/settings.json" || ok=false
    if [ "$ok" = true ]; then
        pass "merge preserves custom keys and adds wizard hooks"
    else
        fail "merge should preserve allowedTools + custom hooks AND add wizard hooks"
    fi
    rm -rf "$d"
}

# Test 26: merge falls back to SKIP for invalid JSON
test_merge_invalid_json_fallback() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    echo "not valid json {{{" > "$d/.claude/settings.json"
    local output
    output=$(cd "$d" && node "$CLI" init 2>&1)
    if echo "$output" | grep -q "SKIP.*settings.json"; then
        pass "merge falls back to SKIP for invalid JSON"
    else
        fail "merge should fall back to SKIP when settings.json has invalid JSON"
    fi
    rm -rf "$d"
}

# Test 27: --force with invalid JSON falls through to OVERWRITE
test_merge_force_invalid_json() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    echo "not valid json {{{" > "$d/.claude/settings.json"
    local output
    output=$(cd "$d" && node "$CLI" init --force 2>&1)
    if echo "$output" | grep -q "OVERWRITE.*settings.json"; then
        pass "--force with invalid JSON falls through to OVERWRITE"
    else
        fail "--force with invalid JSON should show OVERWRITE for settings.json"
    fi
    rm -rf "$d"
}

# Test 28: merge is idempotent — running init twice doesn't duplicate hooks
test_merge_idempotent() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    cat > "$d/.claude/settings.json" << 'FIXTURE'
{
  "allowedTools": ["Read"],
  "hooks": {}
}
FIXTURE
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    # Count occurrences of sdlc-prompt-check — should be exactly 1
    local count
    count=$(grep -c "sdlc-prompt-check" "$d/.claude/settings.json")
    if [ "$count" -eq 1 ]; then
        pass "merge is idempotent — no duplicate wizard hooks"
    else
        fail "merge should not duplicate wizard hooks (found $count occurrences)"
    fi
    rm -rf "$d"
}

# Test 29: --force updates wizard hooks but preserves custom keys
test_merge_force_updates_hooks() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    cat > "$d/.claude/settings.json" << 'FIXTURE'
{
  "allowedTools": ["Read", "Glob"],
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "bash my-custom-hook.sh" }
        ]
      },
      {
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/sdlc-prompt-check.sh" }
        ]
      }
    ]
  }
}
FIXTURE
    (cd "$d" && node "$CLI" init --force > /dev/null 2>&1)
    local ok=true
    # Custom keys preserved
    grep -q "allowedTools" "$d/.claude/settings.json" || ok=false
    grep -q "my-custom-hook" "$d/.claude/settings.json" || ok=false
    # Wizard hooks present (updated)
    grep -q "sdlc-prompt-check" "$d/.claude/settings.json" || ok=false
    grep -q "tdd-pretool-check" "$d/.claude/settings.json" || ok=false
    grep -q "instructions-loaded-check" "$d/.claude/settings.json" || ok=false
    # Not duplicated
    local sdlc_count
    sdlc_count=$(grep -c "sdlc-prompt-check" "$d/.claude/settings.json")
    [ "$sdlc_count" -eq 1 ] || ok=false
    if [ "$ok" = true ]; then
        pass "--force updates wizard hooks but preserves custom keys"
    else
        fail "--force should update wizard hooks AND preserve custom allowedTools + hooks"
    fi
    rm -rf "$d"
}

# Test 29.1: cleanupPeriodDays default applied when missing from existing settings (#225)
test_cleanup_period_default_applied() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    cat > "$d/.claude/settings.json" << 'FIXTURE'
{
  "allowedTools": ["Read"]
}
FIXTURE
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local val
    val=$(jq -r '.cleanupPeriodDays // empty' "$d/.claude/settings.json" 2>/dev/null)
    if [ "$val" = "30" ]; then
        pass "cleanupPeriodDays default (30) applied when missing"
    else
        fail "cleanupPeriodDays default should be applied when missing — got '$val'"
    fi
    rm -rf "$d"
}

# Test 29.2: cleanupPeriodDays user override preserved on init --force (#225)
test_cleanup_period_user_override_preserved() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    cat > "$d/.claude/settings.json" << 'FIXTURE'
{
  "cleanupPeriodDays": 90,
  "allowedTools": ["Read"]
}
FIXTURE
    (cd "$d" && node "$CLI" init --force > /dev/null 2>&1)
    local val
    val=$(jq -r '.cleanupPeriodDays // empty' "$d/.claude/settings.json" 2>/dev/null)
    if [ "$val" = "90" ]; then
        pass "cleanupPeriodDays user override (90) preserved under --force"
    else
        fail "cleanupPeriodDays user override should be preserved under --force — got '$val' (expected 90)"
    fi
    rm -rf "$d"
}

# Test 30: init removes obsolete .claude/skills/testing/ on fresh install
test_upgrade_removes_obsolete_testing() {
    local d
    d=$(make_temp)
    # Simulate pre-upgrade state: old testing skill exists
    mkdir -p "$d/.claude/skills/testing"
    echo "old testing skill" > "$d/.claude/skills/testing/SKILL.md"
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    if [ ! -d "$d/.claude/skills/testing" ]; then
        pass "init removes obsolete .claude/skills/testing/ on fresh install"
    else
        fail "init should remove obsolete .claude/skills/testing/ directory"
    fi
    rm -rf "$d"
}

# Test 31: init removes obsolete testing skill even when all managed files exist (SKIP path)
test_upgrade_removes_testing_on_skip_path() {
    local d
    d=$(make_temp)
    # First install — creates all managed files
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    # Simulate stale testing skill left over from old version
    mkdir -p "$d/.claude/skills/testing"
    echo "old testing skill" > "$d/.claude/skills/testing/SKILL.md"
    # Re-run init (no --force) — all managed files are SKIP, but obsolete must still be removed
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    if [ ! -d "$d/.claude/skills/testing" ]; then
        pass "init removes obsolete testing skill even on all-SKIP path"
    else
        fail "init should remove .claude/skills/testing/ even when all managed files are SKIP"
    fi
    rm -rf "$d"
}

# Run all tests
test_help
test_version
test_dry_run_no_files
test_creates_all_files
test_init_ships_find_sdlc_root_helper
test_npm_pack_includes_find_sdlc_root
test_init_force_clears_version_cache
test_hooks_executable
test_skip_existing
test_force_overwrite
test_dir_structure
test_wizard_doc
test_settings_json
test_gitignore_append
test_gitignore_no_dupes
test_hook_content
test_skill_frontmatter
test_tdd_hook_generic
test_no_allowed_tools
test_check_all_match
test_check_customized
test_check_settings_match_with_extras
test_check_all_missing
test_check_json
test_check_drift_permissions
test_check_drift_gitignore
test_check_recommends_dry_run_when_customized
test_check_recommends_force_when_no_customized
test_check_recommendation_null_updateinfo
test_check_recommendation_undefined_count
test_init_preserve_customized_skips_customized
test_init_preserve_customized_creates_missing
test_init_force_alone_still_overwrites
test_preserve_customized_without_force_is_noop
test_settings_merges_under_preserve_customized
test_wizard_doc_preserved_when_customized
test_setup_wizard_frontmatter
test_merge_settings_output
test_merge_preserves_keys
test_merge_invalid_json_fallback
test_merge_force_invalid_json
test_merge_idempotent
test_merge_force_updates_hooks
test_cleanup_period_default_applied
test_cleanup_period_user_override_preserved
test_upgrade_removes_obsolete_testing
test_upgrade_removes_testing_on_skip_path

# Test 32: init output shows clear restart instructions with --continue
test_install_restart_messaging() {
    local d
    d=$(make_temp)
    local output
    output=$(cd "$d" && node "$CLI" init 2>&1)
    local ok=true
    # Must mention both restart options clearly
    echo "$output" | grep -q '\-\-continue' || ok=false
    # Must mention that --continue keeps conversation history
    echo "$output" | grep -qi 'keep.*conversation\|conversation.*history' || ok=false
    # Must mention fresh start as alternative
    echo "$output" | grep -qi 'fresh' || ok=false
    if [ "$ok" = true ]; then
        pass "init output shows clear restart instructions with --continue"
    else
        fail "init output should clearly show --continue and fresh start options"
    fi
    rm -rf "$d"
}

test_install_restart_messaging

# Test 33: Template settings.json has no top-level env defaults (opt-in via setup skill)
# Rationale (issue #198): unconditionally writing env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=30
# makes sense on 1M context but compacts too aggressively on 200K (30% of 200K = 60K).
# Since the model pin is now opt-in, the paired autocompact override is too.
test_template_has_no_default_env() {
    local template="$SCRIPT_DIR/../cli/templates/settings.json"
    local has_env
    has_env=$(python3 -c "
import json
with open('$template') as f:
    print('yes' if 'env' in json.load(f) else 'no')
" 2>/dev/null)
    if [ "$has_env" = "no" ]; then
        pass "Template settings.json has no default env (opt-in via setup skill Step 9.5)"
    else
        fail "Template settings.json should not have a default env block (issue #198)"
    fi
}

# Test 34: Fresh init does NOT write env to settings.json (opt-in via setup skill)
test_init_does_not_write_env() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local has_env
    has_env=$(python3 -c "
import json
with open('$d/.claude/settings.json') as f:
    print('yes' if 'env' in json.load(f) else 'no')
" 2>/dev/null)
    if [ "$has_env" = "no" ]; then
        pass "Fresh init does not write env to settings.json (opt-in preserves auto-mode defaults)"
    else
        fail "Fresh init should not write env block — user opts in via setup skill"
    fi
    rm -rf "$d"
}

# Test 35: Merge preserves existing env vars (wizard no longer adds AUTOCOMPACT — opt-in)
test_merge_preserves_existing_env() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    cat > "$d/.claude/settings.json" << 'FIXTURE'
{
  "hooks": {},
  "env": {
    "MY_CUSTOM_VAR": "keep-me"
  }
}
FIXTURE
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local result
    result=$(python3 -c "
import json
with open('$d/.claude/settings.json') as f:
    data = json.load(f)
env = data.get('env', {})
custom = env.get('MY_CUSTOM_VAR', '')
has_autocompact = 'CLAUDE_AUTOCOMPACT_PCT_OVERRIDE' in env
print(f'{custom}|{has_autocompact}')
" 2>/dev/null)
    if [ "$result" = "keep-me|False" ]; then
        pass "Merge preserves user env var and does NOT add wizard AUTOCOMPACT (opt-in)"
    else
        fail "Merge should preserve MY_CUSTOM_VAR and leave AUTOCOMPACT unset (got: '$result')"
    fi
    rm -rf "$d"
}

# Test 36: Merge does NOT add env block to settings without env field (opt-in)
test_merge_does_not_add_env_to_existing_settings() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    cat > "$d/.claude/settings.json" << 'FIXTURE'
{
  "allowedTools": ["Read"],
  "hooks": {}
}
FIXTURE
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local result
    result=$(python3 -c "
import json
with open('$d/.claude/settings.json') as f:
    data = json.load(f)
allowed = 'allowedTools' in data
has_env = 'env' in data
print(f'{allowed}|{has_env}')
" 2>/dev/null)
    if [ "$result" = "True|False" ]; then
        pass "Merge preserves allowedTools and does NOT add env block (opt-in)"
    else
        fail "Merge should preserve allowedTools and not create an env block (got: '$result')"
    fi
    rm -rf "$d"
}

# Test 37: Merge does not overwrite user's existing autocompact value.
# User may have opted in explicitly — never clobber their setting.
test_merge_respects_user_autocompact() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    cat > "$d/.claude/settings.json" << 'FIXTURE'
{
  "hooks": {},
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "50"
  }
}
FIXTURE
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local val
    val=$(python3 -c "
import json
with open('$d/.claude/settings.json') as f:
    data = json.load(f)
print(data.get('env', {}).get('CLAUDE_AUTOCOMPACT_PCT_OVERRIDE', ''))
" 2>/dev/null)
    if [ "$val" = "50" ]; then
        pass "Merge respects user's existing AUTOCOMPACT value (50)"
    else
        fail "Merge should not overwrite user's AUTOCOMPACT=50 (got: '$val')"
    fi
    rm -rf "$d"
}

# Test 38: --force does NOT clobber user's autocompact value.
# Template has no env defaults (opt-in), so there's nothing to reset TO.
# User's explicit opt-in must survive --force.
test_merge_force_preserves_user_autocompact() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    cat > "$d/.claude/settings.json" << 'FIXTURE'
{
  "hooks": {},
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "50"
  }
}
FIXTURE
    (cd "$d" && node "$CLI" init --force > /dev/null 2>&1)
    local val
    val=$(python3 -c "
import json
with open('$d/.claude/settings.json') as f:
    data = json.load(f)
print(data.get('env', {}).get('CLAUDE_AUTOCOMPACT_PCT_OVERRIDE', ''))
" 2>/dev/null)
    if [ "$val" = "50" ]; then
        pass "--force preserves user's explicit AUTOCOMPACT value (50)"
    else
        fail "--force should preserve user's AUTOCOMPACT=50 (got: '$val')"
    fi
    rm -rf "$d"
}

# Test 39: Setup wizard skill Step 9.5 references settings.json (not shell profile)
test_setup_skill_references_settings_json() {
    local skill="$SCRIPT_DIR/../skills/setup/SKILL.md"
    if grep -q "settings.json" "$skill" && grep -q "Step 9.5" "$skill"; then
        if grep -A20 "Step 9.5" "$skill" | grep -q "settings.json"; then
            pass "Setup skill Step 9.5 references settings.json"
        else
            fail "Setup skill Step 9.5 should reference settings.json"
        fi
    else
        fail "Setup skill should have Step 9.5 referencing settings.json"
    fi
}

# Test 39b: Setup skill Step 9.5 frames the Opus pin as opt-in with default No
# (issue #198). The key user-visible signals are: "opt-in", default "[y/N]" or
# "Default: No" language, and an explicit note about auto-mode. Without these,
# the wizard is still pushing the pin as the implicit default.
#
# v1.80.0 flipped from the opus[1m] alias to the explicit claude-opus-4-6[1m]
# model id for the recommended flagship — both forms are acceptable references.
test_setup_skill_step95_is_opt_in_default_no() {
    local skill="$SCRIPT_DIR/../skills/setup/SKILL.md"
    local step95
    step95=$(awk '/^### Step 9.5/,/^### Step 10/' "$skill")
    local ok=true
    echo "$step95" | grep -qiE 'opt.?in|\[y/N\]|default.*no' || ok=false
    echo "$step95" | grep -qiE 'auto.?mode|auto.?select' || ok=false
    echo "$step95" | grep -qE 'opusplan|claude-opus-4-[0-9]+' || ok=false
    if [ "$ok" = true ]; then
        pass "Setup skill Step 9.5 frames Opus pin as opt-in (default No, mentions auto-mode)"
    else
        fail "Setup skill Step 9.5 must frame Opus pin as opt-in with default No + auto-mode note (issue #198)"
    fi
}

# Test 39c: Update skill has a migration block for users with an existing
# wizard-installed model: opus[1m] pin (from v1.31–1.33). Without this, users
# who upgrade from the old default silently keep auto-mode disabled.
test_update_skill_has_model_pin_migration() {
    local skill="$SCRIPT_DIR/../skills/update/SKILL.md"
    local ok=true
    grep -qiE 'opus\[1m\].*migration|migration.*opus\[1m\]|model.*pin.*migration|migrate.*model.*pin' "$skill" || ok=false
    grep -qiE '#198|issue.*198' "$skill" || ok=false
    if [ "$ok" = true ]; then
        pass "Update skill has model-pin migration block referencing issue #198"
    else
        fail "Update skill needs a migration block for pre-#198 users with opus[1m] pinned"
    fi
}

test_setup_skill_step95_is_opt_in_default_no
test_update_skill_has_model_pin_migration

# Test 39d: Setup skill Step 9 must direct users to permissions.allow
# (not allowedTools). Issue #197: allowedTools in project settings.json
# silently disables Claude Code auto-mode, same failure family as #198.
test_setup_skill_step9_writes_permissions_allow() {
    local skill="$SCRIPT_DIR/../skills/setup/SKILL.md"
    local step9
    step9=$(awk '/^### Step 9: Configure Tool Permissions/,/^### Step 9\.5/' "$skill")
    local ok=true
    echo "$step9" | grep -qE 'permissions\.allow|"permissions"|permissions.*allow' || ok=false
    # Step 9 must NOT instruct users to use allowedTools for new configs.
    # Anti-patterns: "suggest allowedTools entries", "write ... allowedTools array".
    # Allow: "Do NOT write ... allowedTools", "deprecated allowedTools" — warnings.
    if echo "$step9" | grep -qiE 'suggest[^.]*allowedTools[^.]*entries|write the[[:space:]]+allowedTools'; then
        ok=false
    fi
    if [ "$ok" = true ]; then
        pass "Setup skill Step 9 directs users to permissions.allow (not allowedTools)"
    else
        fail "Setup skill Step 9 must write permissions.allow, not allowedTools (issue #197)"
    fi
}

# Test 39e: Update skill has migration for allowedTools → permissions.allow
test_update_skill_has_allowedtools_migration() {
    local skill="$SCRIPT_DIR/../skills/update/SKILL.md"
    local ok=true
    grep -qiE 'allowedTools.*migration|migration.*allowedTools|allowedTools.*permissions\.allow|permissions\.allow.*allowedTools' "$skill" || ok=false
    grep -qiE '#197|issue.*197' "$skill" || ok=false
    if [ "$ok" = true ]; then
        pass "Update skill has allowedTools → permissions.allow migration (issue #197)"
    else
        fail "Update skill needs a migration for users with allowedTools in settings (issue #197)"
    fi
}

# Test 39f (Codex round-1 finding #1 + round-2 note): Step 7.6 "both present"
# branch must NOT instruct any destructive/non-preserving operation. A user
# could intentionally have duplicate entries, and we must not silently collapse
# them or replace one list with the other. The migration must use additive
# language: "append", "concat", "preserve", AND explicitly forbid the common
# destructive verbs: dedup, replace, overwrite, drop entries.
test_update_skill_migration_is_non_destructive() {
    local skill="$SCRIPT_DIR/../skills/update/SKILL.md"
    local step7_6
    step7_6=$(awk '/^### Step 7\.6/,/^### Step [0-9]+[^.]/' "$skill")
    local ok=true
    # (1) Must have additive/preserving language
    echo "$step7_6" | grep -qiE 'preserve|append|byte.?for.?byte' || ok=false
    # (2) Must explicitly say 'do not dedup' (dedup is the quiet destructive path)
    echo "$step7_6" | grep -qiE 'do not dedup|not dedup|no dedup|without dedup' || ok=false
    # (3) Must NOT contain positive migration instructions using destructive verbs.
    # Catch: "union ... dedup", "dedup the list", "replace permissions.allow",
    # "overwrite permissions.allow", "drop all entries", "clear permissions.allow".
    # Use a targeted anti-pattern list instead of a broad search so we don't
    # false-positive on the "drop the legacy allowedTools key" phrase (that's
    # dropping the *container*, which is correct).
    if echo "$step7_6" | grep -qiE 'union[^.]*dedup|dedup[^.]*drop|dedup the|dedup across|replace[[:space:]]+(the[[:space:]]+)?permissions\.allow|overwrite[[:space:]]+(the[[:space:]]+)?permissions\.allow|replace[[:space:]]+(the[[:space:]]+)?(existing[[:space:]]+)?list|overwrite[[:space:]]+(the[[:space:]]+)?(existing[[:space:]]+)?list|clear[[:space:]]+permissions\.allow|drop[[:space:]]+all[[:space:]]+entries|discard[[:space:]]+(the[[:space:]]+)?entries'; then
        ok=false
    fi
    if [ "$ok" = true ]; then
        pass "Update skill Step 7.6 migration is non-destructive (no dedup/replace/overwrite)"
    else
        fail "Update skill Step 7.6 must NOT instruct dedup/replace/overwrite during migration (Codex rounds 1+2)"
    fi
}

test_setup_skill_step9_writes_permissions_allow
test_update_skill_has_allowedtools_migration
test_update_skill_migration_is_non_destructive

# Test 40: Merge preserves malformed env (array) — wizard no longer writes env unconditionally
test_merge_malformed_env_array_left_alone() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    cat > "$d/.claude/settings.json" << 'FIXTURE'
{
  "hooks": {},
  "env": ["not", "an", "object"]
}
FIXTURE
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local val
    val=$(python3 -c "
import json
with open('$d/.claude/settings.json') as f:
    data = json.load(f)
env = data.get('env')
# Malformed env should be left untouched since template has nothing to merge in
if isinstance(env, list) and env == ['not', 'an', 'object']:
    print('PRESERVED')
else:
    print(repr(env))
" 2>/dev/null)
    if [ "$val" = "PRESERVED" ]; then
        pass "Merge leaves malformed env (array) untouched when template has no env"
    else
        fail "Merge should not rewrite malformed env when template has no env (got: '$val')"
    fi
    rm -rf "$d"
}

# Test 41: Merge preserves malformed env (string) — wizard no longer writes env unconditionally
test_merge_malformed_env_string_left_alone() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    cat > "$d/.claude/settings.json" << 'FIXTURE'
{
  "hooks": {},
  "env": "not-an-object"
}
FIXTURE
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local val
    val=$(python3 -c "
import json
with open('$d/.claude/settings.json') as f:
    data = json.load(f)
env = data.get('env')
if env == 'not-an-object':
    print('PRESERVED')
else:
    print(repr(env))
" 2>/dev/null)
    if [ "$val" = "PRESERVED" ]; then
        pass "Merge leaves malformed env (string) untouched when template has no env"
    else
        fail "Merge should not rewrite malformed env when template has no env (got: '$val')"
    fi
    rm -rf "$d"
}

test_merge_malformed_env_array_left_alone
test_merge_malformed_env_string_left_alone
test_template_has_no_default_env
test_init_does_not_write_env
test_merge_preserves_existing_env
test_merge_does_not_add_env_to_existing_settings
test_merge_respects_user_autocompact
test_merge_force_preserves_user_autocompact
test_setup_skill_references_settings_json

# Model field merge tests — issue #198 flipped opus[1m] from unconditional default
# to opt-in during setup. Default template has NO model pin so Claude Code's
# built-in model auto-selection stays enabled. The setup skill prompts the user
# and writes the pin only if they explicitly opt in.

test_template_has_no_model_pin() {
    local template="$SCRIPT_DIR/../cli/templates/settings.json"
    local has_model
    has_model=$(python3 -c "
import json
with open('$template') as f:
    print('yes' if 'model' in json.load(f) else 'no')
" 2>/dev/null)
    if [ "$has_model" = "no" ]; then
        pass "Template settings.json has no model pin (opt-in per issue #198)"
    else
        fail "Template settings.json should not have a default model pin (issue #198)"
    fi
}

test_fresh_init_does_not_write_model() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local has_model
    has_model=$(python3 -c "
import json
with open('$d/.claude/settings.json') as f:
    print('yes' if 'model' in json.load(f) else 'no')
" 2>/dev/null)
    if [ "$has_model" = "no" ]; then
        pass "Fresh init does NOT write model to settings.json (auto-mode preserved)"
    else
        fail "Fresh init should not write a model pin — it disables auto mode"
    fi
    rm -rf "$d"
}

test_merge_does_not_add_model_when_missing() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    cat > "$d/.claude/settings.json" << 'FIXTURE'
{
  "hooks": {},
  "env": { "MY_VAR": "x" }
}
FIXTURE
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local has_model
    has_model=$(python3 -c "
import json
with open('$d/.claude/settings.json') as f:
    print('yes' if 'model' in json.load(f) else 'no')
" 2>/dev/null)
    if [ "$has_model" = "no" ]; then
        pass "Merge does NOT add model pin when absent (opt-in via setup skill)"
    else
        fail "Merge should not silently add a model pin — user opts in"
    fi
    rm -rf "$d"
}

test_merge_respects_user_model() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    cat > "$d/.claude/settings.json" << 'FIXTURE'
{
  "model": "sonnet",
  "hooks": {}
}
FIXTURE
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local val
    val=$(python3 -c "
import json
with open('$d/.claude/settings.json') as f:
    print(json.load(f).get('model', ''))
" 2>/dev/null)
    if [ "$val" = "sonnet" ]; then
        pass "Merge respects user's explicit model (sonnet)"
    else
        fail "Merge should not overwrite user's model=sonnet (got: '$val')"
    fi
    rm -rf "$d"
}

# --force must NOT overwrite an existing user model pin either — template has
# no model to reset to. User's explicit choice survives.
test_merge_force_preserves_user_model() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    cat > "$d/.claude/settings.json" << 'FIXTURE'
{
  "model": "sonnet",
  "hooks": {}
}
FIXTURE
    (cd "$d" && node "$CLI" init --force > /dev/null 2>&1)
    local val
    val=$(python3 -c "
import json
with open('$d/.claude/settings.json') as f:
    print(json.load(f).get('model', ''))
" 2>/dev/null)
    if [ "$val" = "sonnet" ]; then
        pass "--force preserves user's explicit model (template has no model to reset to)"
    else
        fail "--force should preserve user's model=sonnet (got: '$val')"
    fi
    rm -rf "$d"
}

test_template_has_no_model_pin
test_fresh_init_does_not_write_model
test_merge_does_not_add_model_when_missing
test_merge_respects_user_model
test_merge_force_preserves_user_model

# === advisorModel Tests (v1.81.0) ===

test_template_has_no_advisor_model() {
    local template="$SCRIPT_DIR/../cli/templates/settings.json"
    local has_advisor
    has_advisor=$(python3 -c "
import json
with open('$template') as f:
    print('yes' if 'advisorModel' in json.load(f) else 'no')
" 2>/dev/null)
    if [ "$has_advisor" = "no" ]; then
        pass "Template settings.json has no advisorModel (opt-in during setup)"
    else
        fail "Template settings.json should not have a default advisorModel"
    fi
}

test_fresh_init_does_not_write_advisor_model() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local has_advisor
    has_advisor=$(python3 -c "
import json
with open('$d/.claude/settings.json') as f:
    print('yes' if 'advisorModel' in json.load(f) else 'no')
" 2>/dev/null)
    if [ "$has_advisor" = "no" ]; then
        pass "Fresh init does NOT write advisorModel to settings.json"
    else
        fail "Fresh init should not write advisorModel — it's opt-in during setup"
    fi
    rm -rf "$d"
}

test_merge_preserves_user_advisor_model() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    cat > "$d/.claude/settings.json" << 'FIXTURE'
{
  "advisorModel": "fable",
  "hooks": {}
}
FIXTURE
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local val
    val=$(python3 -c "
import json
with open('$d/.claude/settings.json') as f:
    print(json.load(f).get('advisorModel', ''))
" 2>/dev/null)
    if [ "$val" = "fable" ]; then
        pass "Merge preserves user's existing advisorModel (fable)"
    else
        fail "Merge should not overwrite user's advisorModel=fable (got: '$val')"
    fi
    rm -rf "$d"
}

test_merge_force_preserves_user_advisor_model() {
    local d
    d=$(make_temp)
    mkdir -p "$d/.claude"
    cat > "$d/.claude/settings.json" << 'FIXTURE'
{
  "advisorModel": "opus",
  "model": "claude-opus-4-6",
  "hooks": {}
}
FIXTURE
    (cd "$d" && node "$CLI" init --force > /dev/null 2>&1)
    local val
    val=$(python3 -c "
import json
with open('$d/.claude/settings.json') as f:
    print(json.load(f).get('advisorModel', ''))
" 2>/dev/null)
    if [ "$val" = "opus" ]; then
        pass "--force preserves user's advisorModel (template has no advisorModel to reset to)"
    else
        fail "--force should preserve user's advisorModel=opus (got: '$val')"
    fi
    rm -rf "$d"
}

test_template_has_no_advisor_model
test_fresh_init_does_not_write_advisor_model
test_merge_preserves_user_advisor_model
test_merge_force_preserves_user_advisor_model

# === Marketplace Path Check Tests (#174) ===

# Test 42: check warns on ephemeral /tmp/ marketplace path (EPHEMERAL — path exists)
test_check_marketplace_ephemeral_tmp() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    # make_temp creates under $TMPDIR which is /tmp/... — matches ephemeral regex
    local ephemeral_dir
    ephemeral_dir=$(make_temp)
    local fake_home
    fake_home=$(make_temp)
    mkdir -p "$fake_home/.claude"
    cat > "$fake_home/.claude/settings.json" << FIXTURE
{
  "extraKnownMarketplaces": {
    "sdlc-local": {
      "source": { "source": "directory", "path": "$ephemeral_dir" }
    }
  }
}
FIXTURE
    local output
    output=$(cd "$d" && HOME="$fake_home" node "$CLI" check 2>&1)
    if echo "$output" | grep -q "EPHEMERAL"; then
        pass "check warns on ephemeral /tmp/ marketplace path"
    else
        fail "check should warn EPHEMERAL for /tmp/ path (got: $output)"
    fi
    rm -rf "$d" "$fake_home" "$ephemeral_dir"
}

# Test 43: check detects reaped ephemeral path as DANGLING with ephemeral message
test_check_marketplace_reaped_ephemeral() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local fake_home
    fake_home=$(make_temp)
    mkdir -p "$fake_home/.claude"
    cat > "$fake_home/.claude/settings.json" << 'FIXTURE'
{
  "extraKnownMarketplaces": {
    "my-plugin": {
      "source": { "source": "directory", "path": "/tmp/definitely-reaped-plugin-xyz" }
    }
  }
}
FIXTURE
    local output exit_code
    output=$(cd "$d" && HOME="$fake_home" node "$CLI" check 2>&1) || exit_code=$?
    exit_code=${exit_code:-0}
    if [ "$exit_code" -ne 0 ] && echo "$output" | grep -q "DANGLING" && echo "$output" | grep -qi "reaped"; then
        pass "check detects reaped ephemeral path as DANGLING"
    else
        fail "check should show DANGLING + reaped message for missing ephemeral path (exit=$exit_code)"
    fi
    rm -rf "$d" "$fake_home"
}

# Test (#266): check flags DANGLING + enabledPlugins=true as CRASH RISK with
# actionable remediation. The combo is what crashes UserPromptSubmit on every
# turn (CC's plugin loader tries to resolve the path, fails, propagates to
# every hook). Detecting just DANGLING isn't enough — the crash only fires
# when a package from the dangling marketplace is also enabled.
test_check_marketplace_dangling_with_enabled_plugin_flags_crash_risk() {
    local d fake_home output exit_code=0
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    fake_home=$(make_temp)
    mkdir -p "$fake_home/.claude"
    cat > "$fake_home/.claude/settings.json" << 'FIXTURE'
{
  "enabledPlugins": {
    "sdlc-wizard@sdlc-wizard-local": true
  },
  "extraKnownMarketplaces": {
    "sdlc-wizard-local": {
      "source": { "source": "directory", "path": "/opt/missing-plugin-dir" }
    }
  }
}
FIXTURE
    output=$(cd "$d" && HOME="$fake_home" node "$CLI" check 2>&1) || exit_code=$?
    rm -rf "$d" "$fake_home"
    if [ "$exit_code" -ne 0 ] \
        && echo "$output" | grep -q "DANGLING" \
        && echo "$output" | grep -qE "(CRASH RISK|enabled.*plugin|enabledPlugins)" \
        && echo "$output" | grep -qE "(false|disable|/plugin uninstall)"; then
        pass "#266: check flags DANGLING + enabledPlugins=true as CRASH RISK with remediation"
    else
        fail "#266: dangling+enabled should flag crash risk + remediation (exit=$exit_code, got: $output)"
    fi
}

# Test (#266): DANGLING but NOT in enabledPlugins → just dangling warning, no crash flag
test_check_marketplace_dangling_without_enabled_plugin_no_crash_flag() {
    local d fake_home output exit_code=0
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    fake_home=$(make_temp)
    mkdir -p "$fake_home/.claude"
    cat > "$fake_home/.claude/settings.json" << 'FIXTURE'
{
  "enabledPlugins": {},
  "extraKnownMarketplaces": {
    "harmless-orphan": {
      "source": { "source": "directory", "path": "/opt/missing-but-disabled" }
    }
  }
}
FIXTURE
    output=$(cd "$d" && HOME="$fake_home" node "$CLI" check 2>&1) || exit_code=$?
    rm -rf "$d" "$fake_home"
    # Still DANGLING (path missing) but should NOT escalate to CRASH RISK
    if echo "$output" | grep -q "DANGLING" \
        && ! echo "$output" | grep -qE "CRASH RISK"; then
        pass "#266: DANGLING without enabled plugin → no crash flag (just dangling warning)"
    else
        fail "#266: dangling without enabled should not escalate to CRASH RISK (got: $output)"
    fi
}

# Test (#266): DANGLING + enabledPlugins=false → no crash flag (user already disabled)
test_check_marketplace_dangling_with_disabled_plugin_no_crash_flag() {
    local d fake_home output exit_code=0
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    fake_home=$(make_temp)
    mkdir -p "$fake_home/.claude"
    cat > "$fake_home/.claude/settings.json" << 'FIXTURE'
{
  "enabledPlugins": {
    "sdlc-wizard@sdlc-wizard-local": false
  },
  "extraKnownMarketplaces": {
    "sdlc-wizard-local": {
      "source": { "source": "directory", "path": "/opt/missing-plugin-dir" }
    }
  }
}
FIXTURE
    output=$(cd "$d" && HOME="$fake_home" node "$CLI" check 2>&1) || exit_code=$?
    rm -rf "$d" "$fake_home"
    if echo "$output" | grep -q "DANGLING" \
        && ! echo "$output" | grep -qE "CRASH RISK"; then
        pass "#266: DANGLING + enabledPlugins=false → no crash flag (already disabled)"
    else
        fail "#266: dangling+disabled should not flag crash risk (got: $output)"
    fi
}

# Test 44: check errors on dangling (non-existent, non-ephemeral) marketplace path
test_check_marketplace_dangling() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local fake_home
    fake_home=$(make_temp)
    mkdir -p "$fake_home/.claude"
    cat > "$fake_home/.claude/settings.json" << 'FIXTURE'
{
  "extraKnownMarketplaces": {
    "gone-plugin": {
      "source": { "source": "directory", "path": "/opt/definitely-does-not-exist-xyz" }
    }
  }
}
FIXTURE
    local output exit_code
    output=$(cd "$d" && HOME="$fake_home" node "$CLI" check 2>&1) || exit_code=$?
    exit_code=${exit_code:-0}
    if [ "$exit_code" -ne 0 ] && echo "$output" | grep -q "DANGLING"; then
        pass "check errors on dangling marketplace path (exit=$exit_code)"
    else
        fail "check should error on non-existent marketplace path (exit=$exit_code)"
    fi
    rm -rf "$d" "$fake_home"
}

# Test 45: check passes clean with no marketplace entries
test_check_marketplace_no_entries() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local fake_home
    fake_home=$(make_temp)
    mkdir -p "$fake_home/.claude"
    echo '{}' > "$fake_home/.claude/settings.json"
    local output
    output=$(cd "$d" && HOME="$fake_home" node "$CLI" check 2>&1)
    if ! echo "$output" | grep -qi "marketplace\|ephemeral\|DANGLING"; then
        pass "check passes clean with no marketplace entries"
    else
        fail "check should not mention marketplace when no entries exist"
    fi
    rm -rf "$d" "$fake_home"
}

# Test 46: check --json includes marketplace field
test_check_marketplace_json_output() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local ephemeral_dir
    ephemeral_dir=$(make_temp)
    local fake_home
    fake_home=$(make_temp)
    mkdir -p "$fake_home/.claude"
    cat > "$fake_home/.claude/settings.json" << FIXTURE
{
  "extraKnownMarketplaces": {
    "test-plugin": {
      "source": { "source": "directory", "path": "$ephemeral_dir" }
    }
  }
}
FIXTURE
    local output
    output=$(cd "$d" && HOME="$fake_home" node "$CLI" check --json 2>&1)
    if echo "$output" | python3 -c "import json, sys; d=json.load(sys.stdin); assert 'marketplace' in d" 2>/dev/null; then
        pass "check --json includes marketplace field"
    else
        fail "check --json should include marketplace field"
    fi
    rm -rf "$d" "$fake_home" "$ephemeral_dir"
}

# Test 47: check skips non-directory marketplace sources
test_check_marketplace_skips_non_directory() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local fake_home
    fake_home=$(make_temp)
    mkdir -p "$fake_home/.claude"
    cat > "$fake_home/.claude/settings.json" << 'FIXTURE'
{
  "extraKnownMarketplaces": {
    "remote-plugin": {
      "source": { "source": "url", "url": "https://example.com/plugin" }
    }
  }
}
FIXTURE
    local output
    output=$(cd "$d" && HOME="$fake_home" node "$CLI" check 2>&1)
    if ! echo "$output" | grep -qi "ephemeral\|DANGLING"; then
        pass "check skips non-directory marketplace sources"
    else
        fail "check should not warn about non-directory marketplace sources"
    fi
    rm -rf "$d" "$fake_home"
}

# Test 48: check suggests stable path for ephemeral marketplace
test_check_marketplace_suggests_fix() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local ephemeral_dir
    ephemeral_dir=$(make_temp)
    local fake_home
    fake_home=$(make_temp)
    mkdir -p "$fake_home/.claude"
    cat > "$fake_home/.claude/settings.json" << FIXTURE
{
  "extraKnownMarketplaces": {
    "my-wizard": {
      "source": { "source": "directory", "path": "$ephemeral_dir" }
    }
  }
}
FIXTURE
    local output
    output=$(cd "$d" && HOME="$fake_home" node "$CLI" check 2>&1)
    if echo "$output" | grep -q "plugins-local"; then
        pass "check suggests stable ~/.claude/plugins-local/ path"
    else
        fail "check should suggest ~/.claude/plugins-local/ for ephemeral paths"
    fi
    rm -rf "$d" "$fake_home" "$ephemeral_dir"
}

# Test 49: check detects /private/var/folders/ as ephemeral (Codex finding #1)
test_check_marketplace_private_var_folders() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    # Create a real dir under /private/var/folders (macOS canonical realpath)
    # Use TMPDIR's realpath which should be under /private/var/folders/
    local real_tmpdir
    real_tmpdir=$(python3 -c "import os; print(os.path.realpath('${TMPDIR:-/tmp}'))")
    local ephemeral_dir
    ephemeral_dir=$(mktemp -d "${real_tmpdir}/sdlc-pvf-test-XXXXXX")
    local fake_home
    fake_home=$(make_temp)
    mkdir -p "$fake_home/.claude"
    cat > "$fake_home/.claude/settings.json" << FIXTURE
{
  "extraKnownMarketplaces": {
    "pvf-plugin": {
      "source": { "source": "directory", "path": "$ephemeral_dir" }
    }
  }
}
FIXTURE
    local output
    output=$(cd "$d" && HOME="$fake_home" node "$CLI" check 2>&1)
    if echo "$output" | grep -q "EPHEMERAL"; then
        pass "check detects /private/var/folders/ as ephemeral"
    else
        fail "check should detect /private/var/folders/ as ephemeral (got: $output)"
    fi
    rm -rf "$d" "$fake_home" "$ephemeral_dir"
}

# Test 50: check handles malformed source.path (non-string) gracefully (Codex finding #2)
test_check_marketplace_malformed_path() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local fake_home
    fake_home=$(make_temp)
    mkdir -p "$fake_home/.claude"
    cat > "$fake_home/.claude/settings.json" << 'FIXTURE'
{
  "extraKnownMarketplaces": {
    "bad-plugin": {
      "source": { "source": "directory", "path": {"not": "a-string"} }
    }
  }
}
FIXTURE
    local output exit_code
    output=$(cd "$d" && HOME="$fake_home" node "$CLI" check --json 2>&1) || exit_code=$?
    exit_code=${exit_code:-0}
    # Should not crash — should output valid JSON
    if echo "$output" | python3 -c "import json, sys; json.load(sys.stdin)" 2>/dev/null; then
        pass "check handles malformed source.path (non-string) gracefully"
    else
        fail "check should not crash on non-string source.path (exit=$exit_code)"
    fi
    rm -rf "$d" "$fake_home"
}

# Test 51: non-ephemeral DANGLING path shows "does not exist" heading (Codex finding #3)
test_check_marketplace_dangling_heading() {
    local d
    d=$(make_temp)
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local fake_home
    fake_home=$(make_temp)
    mkdir -p "$fake_home/.claude"
    cat > "$fake_home/.claude/settings.json" << 'FIXTURE'
{
  "extraKnownMarketplaces": {
    "gone-plugin": {
      "source": { "source": "directory", "path": "/opt/definitely-does-not-exist-xyz" }
    }
  }
}
FIXTURE
    local output exit_code
    output=$(cd "$d" && HOME="$fake_home" node "$CLI" check 2>&1) || exit_code=$?
    exit_code=${exit_code:-0}
    if echo "$output" | grep -q "does not exist:" && ! echo "$output" | grep -q "ephemeral:"; then
        pass "non-ephemeral DANGLING shows 'does not exist' heading, not 'ephemeral'"
    else
        fail "non-ephemeral DANGLING should say 'does not exist:', not 'ephemeral:'"
    fi
    rm -rf "$d" "$fake_home"
}

test_check_marketplace_ephemeral_tmp
test_check_marketplace_reaped_ephemeral
test_check_marketplace_dangling
test_check_marketplace_no_entries
test_check_marketplace_json_output
test_check_marketplace_skips_non_directory
test_check_marketplace_suggests_fix
test_check_marketplace_private_var_folders
test_check_marketplace_malformed_path
test_check_marketplace_dangling_heading
test_check_marketplace_dangling_with_enabled_plugin_flags_crash_risk
test_check_marketplace_dangling_without_enabled_plugin_no_crash_flag
test_check_marketplace_dangling_with_disabled_plugin_no_crash_flag

# === Dual-channel install drift guardrails (#181) ===

# Helper: create fake HOME with plugin install path
# which: "local", "cache", "both", or "none"
make_plugin_home() {
    local home="$1"
    local which="$2"
    mkdir -p "$home/.claude"
    if [ "$which" = "local" ] || [ "$which" = "both" ]; then
        mkdir -p "$home/.claude/plugins-local/sdlc-wizard-wrap"
        echo "{}" > "$home/.claude/plugins-local/sdlc-wizard-wrap/.marker"
    fi
    if [ "$which" = "cache" ] || [ "$which" = "both" ]; then
        mkdir -p "$home/.claude/plugins/cache/sdlc-wizard-local"
        echo "{}" > "$home/.claude/plugins/cache/sdlc-wizard-local/.marker"
    fi
}

# Run init with split stdout/stderr and explicit exit code.
# Writes stdout to $1, stderr to $2, echoes exit code.
run_init_split() {
    local stdout_file="$1" stderr_file="$2" workdir="$3" fake_home="$4"
    shift 4
    local exit_code=0
    ( cd "$workdir" && HOME="$fake_home" node "$CLI" init "$@" ) \
        > "$stdout_file" 2> "$stderr_file" || exit_code=$?
    echo "$exit_code"
}

# Test 52: init blocks when plugin install detected (plugins-local path)
test_init_blocks_on_plugin_local() {
    local d fake_home stdout_f stderr_f exit_code
    d=$(make_temp); fake_home=$(make_temp)
    stdout_f=$(make_temp)/stdout; stderr_f=$(make_temp)/stderr
    make_plugin_home "$fake_home" "local"
    exit_code=$(run_init_split "$stdout_f" "$stderr_f" "$d" "$fake_home")
    local error_lines
    error_lines=$(grep -cE '^Error:' "$stderr_f" || true)
    if [ "$exit_code" -ne 0 ] \
       && grep -qi "plugin install detected" "$stderr_f" \
       && [ ! -d "$d/.claude" ] \
       && [ "$error_lines" = "0" ]; then
        pass "init blocks, guidance stands alone (no duplicate Error: line)"
    else
        fail "init block should not duplicate Error prefix (exit=$exit_code, error_lines=$error_lines, stderr=$(cat "$stderr_f"))"
    fi
    rm -rf "$d" "$fake_home" "$(dirname "$stdout_f")" "$(dirname "$stderr_f")"
}

# Test 53: init blocks when plugin cache path detected
test_init_blocks_on_plugin_cache() {
    local d fake_home stdout_f stderr_f exit_code
    d=$(make_temp); fake_home=$(make_temp)
    stdout_f=$(make_temp)/stdout; stderr_f=$(make_temp)/stderr
    make_plugin_home "$fake_home" "cache"
    exit_code=$(run_init_split "$stdout_f" "$stderr_f" "$d" "$fake_home")
    if [ "$exit_code" -ne 0 ] && grep -qi "plugin install detected" "$stderr_f"; then
        pass "init blocks and warns (stderr) when plugin cache detected"
    else
        fail "init should block on plugin cache (exit=$exit_code, stderr=$(cat "$stderr_f"))"
    fi
    rm -rf "$d" "$fake_home" "$(dirname "$stdout_f")" "$(dirname "$stderr_f")"
}

# Test 54: init --force bypasses plugin detection
test_init_force_bypasses_plugin() {
    local d fake_home stdout_f stderr_f exit_code
    d=$(make_temp); fake_home=$(make_temp)
    stdout_f=$(make_temp)/stdout; stderr_f=$(make_temp)/stderr
    make_plugin_home "$fake_home" "both"
    exit_code=$(run_init_split "$stdout_f" "$stderr_f" "$d" "$fake_home" --force)
    if [ "$exit_code" -eq 0 ] && [ -f "$d/.claude/settings.json" ]; then
        pass "init --force bypasses plugin detection and installs"
    else
        fail "init --force should bypass (exit=$exit_code)"
    fi
    rm -rf "$d" "$fake_home" "$(dirname "$stdout_f")" "$(dirname "$stderr_f")"
}

# Test 55: init --dry-run is not blocked by plugin detection
test_init_dry_run_ignores_plugin() {
    local d fake_home stdout_f stderr_f exit_code
    d=$(make_temp); fake_home=$(make_temp)
    stdout_f=$(make_temp)/stdout; stderr_f=$(make_temp)/stderr
    make_plugin_home "$fake_home" "both"
    exit_code=$(run_init_split "$stdout_f" "$stderr_f" "$d" "$fake_home" --dry-run)
    if [ "$exit_code" -eq 0 ] && [ ! -d "$d/.claude" ]; then
        pass "init --dry-run not blocked by plugin detection"
    else
        fail "init --dry-run should succeed (exit=$exit_code)"
    fi
    rm -rf "$d" "$fake_home" "$(dirname "$stdout_f")" "$(dirname "$stderr_f")"
}

# Test 56: init runs silently when no plugin install present
test_init_silent_without_plugin() {
    local d fake_home stdout_f stderr_f exit_code
    d=$(make_temp); fake_home=$(make_temp)
    stdout_f=$(make_temp)/stdout; stderr_f=$(make_temp)/stderr
    make_plugin_home "$fake_home" "none"
    exit_code=$(run_init_split "$stdout_f" "$stderr_f" "$d" "$fake_home")
    if [ "$exit_code" -eq 0 ] \
       && [ -f "$d/.claude/settings.json" ] \
       && ! grep -qi "plugin install detected" "$stderr_f"; then
        pass "init silent about plugins when absent"
    else
        fail "init should be silent without plugins (exit=$exit_code)"
    fi
    rm -rf "$d" "$fake_home" "$(dirname "$stdout_f")" "$(dirname "$stderr_f")"
}

# Test 57: plugin warning mentions how to resolve (pick one channel)
test_init_plugin_warning_guidance() {
    local d fake_home stdout_f stderr_f exit_code
    d=$(make_temp); fake_home=$(make_temp)
    stdout_f=$(make_temp)/stdout; stderr_f=$(make_temp)/stderr
    make_plugin_home "$fake_home" "local"
    exit_code=$(run_init_split "$stdout_f" "$stderr_f" "$d" "$fake_home")
    if [ "$exit_code" -ne 0 ] \
       && grep -qi "force" "$stderr_f" \
       && grep -qi "plugin" "$stderr_f"; then
        pass "plugin warning mentions --force and plugin on stderr"
    else
        fail "plugin warning should mention --force (exit=$exit_code, stderr=$(cat "$stderr_f"))"
    fi
    rm -rf "$d" "$fake_home" "$(dirname "$stdout_f")" "$(dirname "$stderr_f")"
}

# Test 58c: unset HOME (env -u HOME) does not false-trigger on cwd-relative path
test_init_unset_home_no_false_positive() {
    local d stdout_f stderr_f exit_code
    d=$(make_temp)
    stdout_f=$(make_temp)/stdout; stderr_f=$(make_temp)/stderr
    # Seed cwd with a would-match dir (only matters if guard fails)
    mkdir -p "$d/.claude/plugins-local/sdlc-wizard-wrap"
    exit_code=0
    # env -u HOME makes os.homedir() fall back to /etc/passwd, returning the
    # real absolute user home (not empty). Guard should route detection to
    # that absolute path — never to the cwd-relative .claude/... path.
    ( cd "$d" && env -u HOME node "$CLI" init ) \
        > "$stdout_f" 2> "$stderr_f" || exit_code=$?
    # If any plugin warning fires, it must reference an absolute path.
    # Reject any relative path like ".claude/plugins-local/..." in stderr.
    if grep -Eq '(^|[^/])\.claude/plugins' "$stderr_f"; then
        fail "unset HOME produced cwd-relative plugin path (stderr=$(cat "$stderr_f"))"
    else
        pass "unset HOME does not false-trigger on cwd-relative path"
    fi
    rm -rf "$d" "$(dirname "$stdout_f")" "$(dirname "$stderr_f")"
}

# Test 58b: detectPluginInstall guard rejects empty, undefined, and relative homeDir
test_detect_plugin_install_guards_bad_homedir() {
    local d result
    d=$(make_temp)
    # Seed cwd with a dir that WOULD match if guard were missing
    mkdir -p "$d/.claude/plugins-local/sdlc-wizard-wrap"
    # Call exported detectPluginInstall directly with each bad homeDir value.
    # Use HOME="" so os.homedir() fallback is also empty — isolates the guard.
    result=$(cd "$d" && HOME="" node -e '
      const { detectPluginInstall } = require("'"$SCRIPT_DIR/../cli/init.js"'");
      const cases = { empty: "", undef: undefined, relative: ".claude" };
      for (const [k, v] of Object.entries(cases)) {
        const out = detectPluginInstall(v);
        console.log(k + "=" + out.length);
      }
    ')
    if echo "$result" | grep -q "^empty=0$" \
       && echo "$result" | grep -q "^undef=0$" \
       && echo "$result" | grep -q "^relative=0$"; then
        pass "detectPluginInstall guards against empty/undefined/relative homeDir"
    else
        fail "detectPluginInstall guard failed (got: $result)"
    fi
    rm -rf "$d"
}

# Test 58: empty HOME does not false-trigger plugin detection via relative paths
test_init_empty_home_no_false_positive() {
    local d stdout_f stderr_f exit_code
    d=$(make_temp)
    stdout_f=$(make_temp)/stdout; stderr_f=$(make_temp)/stderr
    # Seed cwd with a directory that would match if path.join used "" as home
    mkdir -p "$d/.claude/plugins-local/sdlc-wizard-wrap"
    exit_code=0
    ( cd "$d" && HOME="" node "$CLI" init ) \
        > "$stdout_f" 2> "$stderr_f" || exit_code=$?
    if [ "$exit_code" -eq 0 ] \
       && ! grep -qi "plugin install detected" "$stderr_f"; then
        pass "empty HOME does not false-trigger plugin detection"
    else
        fail "empty HOME should not trigger plugin block (exit=$exit_code, stderr=$(cat "$stderr_f"))"
    fi
    rm -rf "$d" "$(dirname "$stdout_f")" "$(dirname "$stderr_f")"
}

# === Stale CLI version nudge at init time (#358) ===
# init time is where stale-npx-cache bites hardest — users who copy
# `npx agentic-sdlc-wizard init` from old docs get whatever cached version
# is on disk. /update Step 1.5 already does this check; init didn't.
# Reuses the SDLC_WIZARD_CACHE_DIR/latest-version cache the
# instructions-loaded hook already populates (#64/#196), so no extra npm hit.

# Test (#358): nudge fires when cache says local CLI is older than latest.
# Uses 999.999.999 as a far-future sentinel that will always exceed
# package.json's current version regardless of future releases.
test_init_emits_stale_cli_nudge_when_cache_indicates_newer() {
    local d cache_dir stdout_f exit_code
    d=$(make_temp)
    cache_dir=$(make_temp)
    stdout_f=$(make_temp)/stdout
    echo "999.999.999" > "$cache_dir/latest-version"
    exit_code=0
    ( cd "$d" && SDLC_WIZARD_CACHE_DIR="$cache_dir" node "$CLI" init ) \
        > "$stdout_f" 2>&1 || exit_code=$?
    if [ "$exit_code" -eq 0 ] \
       && grep -qF "npx -y agentic-sdlc-wizard@latest init" "$stdout_f" \
       && grep -qF "999.999.999" "$stdout_f"; then
        pass "#358: init emits stale-CLI nudge when cache indicates newer version"
    else
        fail "#358: stale-CLI nudge missing (exit=$exit_code, stdout=$(cat "$stdout_f"))"
    fi
    rm -rf "$d" "$cache_dir" "$(dirname "$stdout_f")"
}

# Test (#358): no nudge when cache version == package.json version.
# Prevents post-upgrade "1.77.0 → 1.77.0" noise.
test_init_silent_when_cache_matches_current_version() {
    local d cache_dir stdout_f pkg_version exit_code
    d=$(make_temp)
    cache_dir=$(make_temp)
    stdout_f=$(make_temp)/stdout
    pkg_version=$(node -e "console.log(require('$SCRIPT_DIR/../package.json').version)")
    echo "$pkg_version" > "$cache_dir/latest-version"
    exit_code=0
    ( cd "$d" && SDLC_WIZARD_CACHE_DIR="$cache_dir" node "$CLI" init ) \
        > "$stdout_f" 2>&1 || exit_code=$?
    if [ "$exit_code" -eq 0 ] \
       && ! grep -qF "@latest init" "$stdout_f"; then
        pass "#358: init silent when cache shows latest == current"
    else
        fail "#358: init should NOT nudge when up-to-date (exit=$exit_code, stdout=$(cat "$stdout_f"))"
    fi
    rm -rf "$d" "$cache_dir" "$(dirname "$stdout_f")"
}

# Test (#358): no reverse nudge when cache shows local > latest.
# Mirrors #239 cache-poison sanity: cached "latest=0.0.1" is impossible,
# so we treat installed as already-current and stay silent.
test_init_silent_when_cache_shows_local_newer_than_latest() {
    local d cache_dir stdout_f exit_code
    d=$(make_temp)
    cache_dir=$(make_temp)
    stdout_f=$(make_temp)/stdout
    echo "0.0.1" > "$cache_dir/latest-version"
    exit_code=0
    ( cd "$d" && SDLC_WIZARD_CACHE_DIR="$cache_dir" node "$CLI" init ) \
        > "$stdout_f" 2>&1 || exit_code=$?
    if [ "$exit_code" -eq 0 ] \
       && ! grep -qF "@latest init" "$stdout_f"; then
        pass "#358: init silent when cache shows local > latest (no reverse nudge)"
    else
        fail "#358: init should NOT nudge in reverse direction (exit=$exit_code, stdout=$(cat "$stdout_f"))"
    fi
    rm -rf "$d" "$cache_dir" "$(dirname "$stdout_f")"
}

# Test (#358): no nudge + no crash when npm is unavailable AND cache is absent.
# Fault-injects a fake `npm` that always exits 1, with PATH override. Catches
# regressions where someone removes the try/catch wrapping execSync — the
# nudge would then crash init in environments without npm (CI sandboxes, etc.).
test_init_silent_when_npm_unavailable_and_cache_empty() {
    local d cache_dir bin_dir stdout_f exit_code
    d=$(make_temp)
    cache_dir=$(make_temp)
    bin_dir=$(make_temp)
    stdout_f=$(make_temp)/stdout
    cat > "$bin_dir/npm" <<'NPMEOF'
#!/bin/bash
exit 1
NPMEOF
    chmod +x "$bin_dir/npm"
    exit_code=0
    ( cd "$d" && SDLC_WIZARD_CACHE_DIR="$cache_dir" PATH="$bin_dir:$PATH" node "$CLI" init ) \
        > "$stdout_f" 2>&1 || exit_code=$?
    if [ "$exit_code" -eq 0 ] \
       && ! grep -qF "@latest init" "$stdout_f" \
       && grep -qF "SDLC Harness installed successfully" "$stdout_f"; then
        pass "#358: init silent + successful when npm unavailable + no cache (offline-graceful)"
    else
        fail "#358: init should be silent + succeed offline (exit=$exit_code, stdout=$(cat "$stdout_f"))"
    fi
    rm -rf "$d" "$cache_dir" "$bin_dir" "$(dirname "$stdout_f")"
}

test_init_blocks_on_plugin_local
test_init_blocks_on_plugin_cache
test_init_force_bypasses_plugin
test_init_dry_run_ignores_plugin
test_init_silent_without_plugin
test_init_plugin_warning_guidance
test_init_empty_home_no_false_positive
test_init_unset_home_no_false_positive
test_detect_plugin_install_guards_bad_homedir
test_init_emits_stale_cli_nudge_when_cache_indicates_newer
test_init_silent_when_cache_matches_current_version
test_init_silent_when_cache_shows_local_newer_than_latest
test_init_silent_when_npm_unavailable_and_cache_empty

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All CLI distribution tests passed!"
