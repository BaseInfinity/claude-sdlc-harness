#!/bin/bash
# Test Claude Code plugin format structure and parity
# Validates .claude-plugin/plugin.json, hooks/hooks.json, skills/, hooks/

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
PASSED=0
FAILED=0

# Isolate tests from real HOME so plugin install detection (#181) doesn't
# false-trigger in dev environments with the plugin installed.
export HOME="$(mktemp -d "${TMPDIR:-/tmp}/sdlc-plugin-test-home-XXXXXX")"
trap 'rm -rf "$HOME"' EXIT

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

echo "=== Plugin Format Tests ==="
echo ""

# --- plugin.json validation ---

test_plugin_json_exists() {
    if [ -f "$REPO_ROOT/.claude-plugin/plugin.json" ]; then
        pass "plugin.json exists at .claude-plugin/plugin.json"
    else
        fail "plugin.json should exist at .claude-plugin/plugin.json"
    fi
}

test_plugin_json_valid() {
    local file="$REPO_ROOT/.claude-plugin/plugin.json"
    [ -f "$file" ] || { fail "plugin.json missing (can't validate)"; return; }
    if python3 -c "import json; json.load(open('$file'))" 2>/dev/null; then
        pass "plugin.json is valid JSON"
    else
        fail "plugin.json should be valid JSON"
    fi
}

test_plugin_json_name() {
    local file="$REPO_ROOT/.claude-plugin/plugin.json"
    [ -f "$file" ] || { fail "plugin.json missing (can't check name)"; return; }
    local name
    name=$(python3 -c "import json; print(json.load(open('$file')).get('name',''))" 2>/dev/null)
    if [ "$name" = "sdlc-wizard" ]; then
        pass "plugin.json name is 'sdlc-wizard'"
    else
        fail "plugin.json name should be 'sdlc-wizard', got '$name'"
    fi
}

test_plugin_json_version_matches_package() {
    local plugin_file="$REPO_ROOT/.claude-plugin/plugin.json"
    local pkg_file="$REPO_ROOT/package.json"
    [ -f "$plugin_file" ] || { fail "plugin.json missing (can't check version)"; return; }
    local plugin_ver pkg_ver
    plugin_ver=$(python3 -c "import json; print(json.load(open('$plugin_file')).get('version',''))" 2>/dev/null)
    pkg_ver=$(python3 -c "import json; print(json.load(open('$pkg_file')).get('version',''))" 2>/dev/null)
    if [ "$plugin_ver" = "$pkg_ver" ]; then
        pass "plugin.json version ($plugin_ver) matches package.json"
    else
        fail "plugin.json version ($plugin_ver) should match package.json ($pkg_ver)"
    fi
}

test_marketplace_version_matches_package() {
    local mkt_file="$REPO_ROOT/.claude-plugin/marketplace.json"
    local pkg_file="$REPO_ROOT/package.json"
    [ -f "$mkt_file" ] || { fail "marketplace.json missing (can't check version)"; return; }
    local mkt_ver pkg_ver
    mkt_ver=$(python3 -c "import json; print(json.load(open('$mkt_file'))['plugins'][0].get('version',''))" 2>/dev/null)
    pkg_ver=$(python3 -c "import json; print(json.load(open('$pkg_file')).get('version',''))" 2>/dev/null)
    if [ "$mkt_ver" = "$pkg_ver" ]; then
        pass "marketplace.json plugin version ($mkt_ver) matches package.json"
    else
        fail "marketplace.json plugin version ($mkt_ver) should match package.json ($pkg_ver)"
    fi
}

test_plugin_json_required_fields() {
    local file="$REPO_ROOT/.claude-plugin/plugin.json"
    [ -f "$file" ] || { fail "plugin.json missing (can't check fields)"; return; }
    local ok=true
    for field in name version description author license; do
        local val
        val=$(python3 -c "import json; d=json.load(open('$file')); print(d.get('$field',''))" 2>/dev/null)
        if [ -z "$val" ]; then
            ok=false
        fi
    done
    if [ "$ok" = true ]; then
        pass "plugin.json has all recommended fields (name, version, description, author, license)"
    else
        fail "plugin.json should have name, version, description, author, license"
    fi
}

test_plugin_json_kebab_case_name() {
    local file="$REPO_ROOT/.claude-plugin/plugin.json"
    [ -f "$file" ] || { fail "plugin.json missing"; return; }
    local name
    name=$(python3 -c "import json; print(json.load(open('$file')).get('name',''))" 2>/dev/null)
    if echo "$name" | grep -qE '^[a-z][a-z0-9-]*$'; then
        pass "plugin.json name is kebab-case"
    else
        fail "plugin.json name must be kebab-case, got '$name'"
    fi
}

# --- hooks/hooks.json validation ---

test_hooks_json_exists() {
    if [ -f "$REPO_ROOT/hooks/hooks.json" ]; then
        pass "hooks.json exists at hooks/hooks.json"
    else
        fail "hooks.json should exist at hooks/hooks.json"
    fi
}

test_hooks_json_valid() {
    local file="$REPO_ROOT/hooks/hooks.json"
    [ -f "$file" ] || { fail "hooks.json missing (can't validate)"; return; }
    if python3 -c "import json; json.load(open('$file'))" 2>/dev/null; then
        pass "hooks.json is valid JSON"
    else
        fail "hooks.json should be valid JSON"
    fi
}

test_hooks_json_uses_plugin_root() {
    local file="$REPO_ROOT/hooks/hooks.json"
    [ -f "$file" ] || { fail "hooks.json missing"; return; }
    if grep -q 'CLAUDE_PLUGIN_ROOT' "$file"; then
        if ! grep -q 'CLAUDE_PROJECT_DIR' "$file"; then
            pass "hooks.json uses CLAUDE_PLUGIN_ROOT (not CLAUDE_PROJECT_DIR)"
        else
            fail "hooks.json should NOT reference CLAUDE_PROJECT_DIR"
        fi
    else
        fail "hooks.json should use \${CLAUDE_PLUGIN_ROOT} for script paths"
    fi
}

test_hooks_json_six_events() {
    local file="$REPO_ROOT/hooks/hooks.json"
    [ -f "$file" ] || { fail "hooks.json missing"; return; }
    local count
    count=$(python3 -c "
import json
with open('$file') as f:
    d = json.load(f)
hooks = d.get('hooks', {})
print(len(hooks))
" 2>/dev/null)
    if [ "$count" = "6" ]; then
        pass "hooks.json has 6 hook events"
    else
        fail "hooks.json should have 6 hook events (added Stop, #436), got $count"
    fi
}

test_hooks_json_event_parity() {
    local hooks_file="$REPO_ROOT/hooks/hooks.json"
    local settings_file="$REPO_ROOT/cli/templates/settings.json"
    [ -f "$hooks_file" ] || { fail "hooks.json missing"; return; }
    [ -f "$settings_file" ] || { fail "settings.json missing"; return; }
    local hooks_events settings_events
    hooks_events=$(python3 -c "
import json
with open('$hooks_file') as f:
    d = json.load(f)
print(' '.join(sorted(d.get('hooks', {}).keys())))
" 2>/dev/null)
    settings_events=$(python3 -c "
import json
with open('$settings_file') as f:
    d = json.load(f)
print(' '.join(sorted(d.get('hooks', {}).keys())))
" 2>/dev/null)
    if [ "$hooks_events" = "$settings_events" ]; then
        pass "hooks.json events match CLI settings.json events"
    else
        fail "Event mismatch: hooks.json='$hooks_events' settings.json='$settings_events'"
    fi
}

# #436: event-name parity alone is too weak — an event key can exist in both
# files while the actual registered SCRIPTS under it differ (this is exactly
# how codex-gate-check.sh shipped in .claude/settings.json + CLI template but
# was never added to the plugin's hooks/hooks.json — "PreToolUse" existed in
# both, so the weaker test above passed while plugin users silently got no
# cross-model gate at all). This compares the actual basename set of scripts
# referenced per event across all three distribution channels.
test_hooks_json_script_parity() {
    local hooks_file="$REPO_ROOT/hooks/hooks.json"
    local project_file="$REPO_ROOT/.claude/settings.json"
    local cli_file="$REPO_ROOT/cli/templates/settings.json"
    for f in "$hooks_file" "$project_file" "$cli_file"; do
        [ -f "$f" ] || { fail "$f missing"; return; }
    done
    local hooks_scripts project_scripts cli_scripts
    hooks_scripts=$(python3 -c "
import json
with open('$hooks_file') as f:
    d = json.load(f)
scripts = set()
for entries in d.get('hooks', {}).values():
    for entry in entries:
        for h in entry.get('hooks', []):
            cmd = h.get('command', '')
            scripts.add(cmd.rsplit('/', 1)[-1])
print(' '.join(sorted(scripts)))
" 2>/dev/null)
    project_scripts=$(python3 -c "
import json
with open('$project_file') as f:
    d = json.load(f)
scripts = set()
for entries in d.get('hooks', {}).values():
    for entry in entries:
        for h in entry.get('hooks', []):
            cmd = h.get('command', '')
            scripts.add(cmd.rsplit('/', 1)[-1])
print(' '.join(sorted(scripts)))
" 2>/dev/null)
    cli_scripts=$(python3 -c "
import json
with open('$cli_file') as f:
    d = json.load(f)
scripts = set()
for entries in d.get('hooks', {}).values():
    for entry in entries:
        for h in entry.get('hooks', []):
            cmd = h.get('command', '')
            scripts.add(cmd.rsplit('/', 1)[-1])
print(' '.join(sorted(scripts)))
" 2>/dev/null)
    # merge-gate-check.sh is a deliberate, documented exception: it lives at
    # .claude/hooks/ (not hooks/) and is repo-local-only by design — this
    # repo's own merge-safety mechanism, hardcoded to its Codex/Fable/
    # .reviews/ contribution stack, intentionally not shipped to consumer
    # repos (see ROADMAP.md #462, CLAUDE_CODE_SDLC_WIZARD.md's "Explicit
    # Merge Confirmation" section). It's expected to appear ONLY in the
    # project (this repo's own .claude/settings.json) channel, never in
    # hooks.json or the CLI template.
    local project_scripts_shippable
    project_scripts_shippable=$(printf '%s\n' "$project_scripts" | tr ' ' '\n' | grep -v '^merge-gate-check\.sh$' | tr '\n' ' ' | sed 's/ $//')
    if [ "$hooks_scripts" = "$project_scripts_shippable" ] && [ "$project_scripts_shippable" = "$cli_scripts" ]; then
        pass "hooks.json, .claude/settings.json, and CLI template register the same shippable hook scripts (merge-gate-check.sh correctly excluded as repo-local-only)"
    else
        fail "Script mismatch across distribution channels: hooks.json='$hooks_scripts' project(shippable)='$project_scripts_shippable' cli='$cli_scripts'"
    fi
}

# --- Plugin directory structure ---

test_plugin_skills_exist() {
    local ok=true
    for skill in sdlc setup update feedback conduct; do
        [ -f "$REPO_ROOT/skills/$skill/SKILL.md" ] || ok=false
    done
    if [ "$ok" = true ]; then
        pass "All 5 skill SKILL.md files exist at skills/"
    else
        fail "skills/ should contain sdlc, setup, update, feedback, conduct SKILL.md files"
    fi
}

test_plugin_hook_scripts_exist() {
    local ok=true
    local missing=""
    for script in sdlc-prompt-check.sh tdd-pretool-check.sh instructions-loaded-check.sh model-effort-check.sh precompact-seam-check.sh codex-gate-check.sh token-spike-check.sh codex-review-stop-check.sh; do
        [ -f "$REPO_ROOT/hooks/$script" ] || { ok=false; missing="$missing $script"; }
    done
    if [ "$ok" = true ]; then
        pass "All 8 hook scripts exist at hooks/"
    else
        fail "hooks/ missing scripts:$missing"
    fi
}

test_plugin_hook_scripts_executable() {
    local ok=true
    local missing=""
    for script in sdlc-prompt-check.sh tdd-pretool-check.sh instructions-loaded-check.sh model-effort-check.sh precompact-seam-check.sh codex-gate-check.sh token-spike-check.sh codex-review-stop-check.sh; do
        [ -x "$REPO_ROOT/hooks/$script" ] || { ok=false; missing="$missing $script"; }
    done
    if [ "$ok" = true ]; then
        pass "All 8 hook scripts are executable"
    else
        fail "hooks/ non-executable:$missing"
    fi
}

# --- Parity: plugin files match CLI-installed files ---

test_skill_parity() {
    local ok=true
    for skill in sdlc setup update feedback conduct; do
        local plugin_file="$REPO_ROOT/skills/$skill/SKILL.md"
        # CLI init copies from wherever init.js points. After refactor, CLI reads from skills/ too.
        # Verify content matches what CLI would install by running init and comparing.
        [ -f "$plugin_file" ] || { ok=false; continue; }
    done
    if [ "$ok" = true ]; then
        pass "Plugin skills all exist (parity check)"
    else
        fail "Plugin skills/ should match CLI templates"
    fi
}

test_cli_installs_from_plugin_source() {
    # After refactor, CLI reads skills/hooks from repo root (not cli/templates/)
    # Verify by running init and comparing output to plugin source files
    local d
    d=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-plugin-test-XXXXXX")
    local CLI="$REPO_ROOT/cli/bin/sdlc-wizard.js"
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local ok=true
    for rel in sdlc/SKILL.md setup/SKILL.md update/SKILL.md feedback/SKILL.md \
               conduct/SKILL.md conduct/references/protocol.md conduct/scripts/conduct.cjs; do
        local installed="$d/.claude/skills/$rel"
        local source="$REPO_ROOT/skills/$rel"
        [ -f "$installed" ] || { ok=false; continue; }
        [ -f "$source" ] || { ok=false; continue; }
        if ! diff -q "$installed" "$source" > /dev/null 2>&1; then
            ok=false
        fi
    done
    if [ "$ok" = true ]; then
        pass "CLI-installed skills match plugin source skills"
    else
        fail "CLI init should install skills identical to plugin skills/"
    fi
    rm -rf "$d"
}

test_cli_installs_hooks_from_plugin_source() {
    local d
    d=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-plugin-test-XXXXXX")
    local CLI="$REPO_ROOT/cli/bin/sdlc-wizard.js"
    (cd "$d" && node "$CLI" init > /dev/null 2>&1)
    local ok=true
    for script in sdlc-prompt-check.sh tdd-pretool-check.sh instructions-loaded-check.sh model-effort-check.sh precompact-seam-check.sh; do
        local installed="$d/.claude/hooks/$script"
        local source="$REPO_ROOT/hooks/$script"
        [ -f "$installed" ] || { ok=false; continue; }
        [ -f "$source" ] || { ok=false; continue; }
        if ! diff -q "$installed" "$source" > /dev/null 2>&1; then
            ok=false
        fi
    done
    if [ "$ok" = true ]; then
        pass "CLI-installed hooks match plugin source hooks"
    else
        fail "CLI init should install hooks identical to plugin hooks/"
    fi
    rm -rf "$d"
}

# --- Marketplace ---

test_marketplace_json_exists() {
    if [ -f "$REPO_ROOT/.claude-plugin/marketplace.json" ]; then
        pass "marketplace.json exists at .claude-plugin/marketplace.json"
    else
        fail "marketplace.json should exist at .claude-plugin/marketplace.json"
    fi
}

test_marketplace_json_valid() {
    local file="$REPO_ROOT/.claude-plugin/marketplace.json"
    [ -f "$file" ] || { fail "marketplace.json missing"; return; }
    if python3 -c "import json; json.load(open('$file'))" 2>/dev/null; then
        pass "marketplace.json is valid JSON"
    else
        fail "marketplace.json should be valid JSON"
    fi
}

test_marketplace_json_has_plugin() {
    local file="$REPO_ROOT/.claude-plugin/marketplace.json"
    [ -f "$file" ] || { fail "marketplace.json missing"; return; }
    local plugin_count
    plugin_count=$(python3 -c "
import json
with open('$file') as f:
    d = json.load(f)
print(len(d.get('plugins', [])))
" 2>/dev/null)
    if [ "$plugin_count" -ge 1 ]; then
        pass "marketplace.json lists at least 1 plugin"
    else
        fail "marketplace.json should list at least 1 plugin"
    fi
}

# --- npm package.json includes plugin files ---

test_package_json_includes_plugin_dirs() {
    local file="$REPO_ROOT/package.json"
    local ok=true
    python3 -c "
import json, sys
with open('$file') as f:
    d = json.load(f)
files = d.get('files', [])
needed = ['skills/', 'hooks/', '.claude-plugin/']
for n in needed:
    if n not in files:
        sys.exit(1)
" 2>/dev/null
    if [ $? -eq 0 ]; then
        pass "package.json files field includes skills/, hooks/, .claude-plugin/"
    else
        fail "package.json files should include skills/, hooks/, .claude-plugin/"
    fi
}

# --- No stale template directories ---

test_no_stale_template_skills() {
    if [ ! -d "$REPO_ROOT/cli/templates/skills" ]; then
        pass "cli/templates/skills/ removed (canonical location is skills/)"
    else
        fail "cli/templates/skills/ should be removed — canonical location is skills/"
    fi
}

test_no_stale_template_hooks() {
    if [ ! -d "$REPO_ROOT/cli/templates/hooks" ]; then
        pass "cli/templates/hooks/ removed (canonical location is hooks/)"
    else
        fail "cli/templates/hooks/ should be removed — canonical location is hooks/"
    fi
}

# --- Dogfooding: .claude/ points to plugin root ---

test_dogfood_settings_uses_root_hooks() {
    local file="$REPO_ROOT/.claude/settings.json"
    [ -f "$file" ] || { fail ".claude/settings.json missing"; return; }
    # Should reference hooks/ at repo root (not .claude/hooks/) for every
    # SHIPPED hook. merge-gate-check.sh is the sole documented exception —
    # a deliberately repo-local-only hook (see ROADMAP.md #462) that MUST
    # live at .claude/hooks/ precisely because it must never ship. Any
    # OTHER .claude/hooks/ reference is still a real dogfooding-drift bug.
    if ! grep -q 'CLAUDE_PROJECT_DIR.*/hooks/' "$file"; then
        fail "Dogfood settings.json should reference hooks/ at repo root"
        return
    fi
    local stray_claude_hooks
    stray_claude_hooks=$(grep -o '\.claude/hooks/[A-Za-z0-9_-]*\.sh' "$file" | grep -v '^\.claude/hooks/merge-gate-check\.sh$' || true)
    if [ -z "$stray_claude_hooks" ]; then
        pass "Dogfood settings.json references hooks/ at repo root (merge-gate-check.sh is the sole documented .claude/hooks/ exception)"
    else
        fail "Dogfood settings.json references unexpected .claude/hooks/ script(s): $stray_claude_hooks (should reference hooks/ instead)"
    fi
}

# Run all tests
test_plugin_json_exists
test_plugin_json_valid
test_plugin_json_name
test_plugin_json_version_matches_package
test_marketplace_version_matches_package
test_plugin_json_required_fields
test_plugin_json_kebab_case_name
test_hooks_json_exists
test_hooks_json_valid
test_hooks_json_uses_plugin_root
test_hooks_json_six_events
test_hooks_json_event_parity
test_hooks_json_script_parity
test_plugin_skills_exist
test_plugin_hook_scripts_exist
test_plugin_hook_scripts_executable
test_skill_parity
test_cli_installs_from_plugin_source
test_cli_installs_hooks_from_plugin_source
test_marketplace_json_exists
test_marketplace_json_valid
test_marketplace_json_has_plugin
test_package_json_includes_plugin_dirs
test_no_stale_template_skills
test_no_stale_template_hooks
test_dogfood_settings_uses_root_hooks

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All plugin format tests passed!"
