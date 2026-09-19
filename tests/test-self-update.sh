#!/bin/bash
# Test self-update mechanism in the wizard document

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIZARD="$SCRIPT_DIR/../CLAUDE_CODE_SDLC_WIZARD.md"
PASSED=0
FAILED=0

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

echo "=== Self-Update Mechanism Tests ==="
echo ""

# Test 1: Wizard contains raw CHANGELOG URL
test_changelog_url() {
    if grep -q "raw.githubusercontent.com/BaseInfinity/claude-sdlc-harness/main/CHANGELOG.md" "$WIZARD"; then
        pass "Wizard contains raw CHANGELOG URL"
    else
        fail "Wizard should contain raw.githubusercontent.com CHANGELOG URL"
    fi
}

# Test 2: Wizard contains raw wizard URL
test_wizard_url() {
    if grep -q "raw.githubusercontent.com/BaseInfinity/claude-sdlc-harness/main/CLAUDE_CODE_SDLC_WIZARD.md" "$WIZARD"; then
        pass "Wizard contains raw wizard URL"
    else
        fail "Wizard should contain raw.githubusercontent.com wizard URL"
    fi
}

# Test 3: Step registry contains update-notify step
test_step_registry() {
    if grep -q "step-update-notify" "$WIZARD"; then
        pass "Step registry contains step-update-notify"
    else
        fail "Step registry should contain step-update-notify entry"
    fi
}

# Test 4: Update flow mentions CHANGELOG-first approach
test_changelog_first() {
    # The wizard should instruct Claude to fetch CHANGELOG before the full wizard
    if grep -qi "fetch.*changelog.*first\|changelog.*first\|phase 1.*changelog\|step 1.*changelog" "$WIZARD"; then
        pass "Update flow mentions CHANGELOG-first approach"
    else
        fail "Update flow should mention fetching CHANGELOG first"
    fi
}

# Test 5: Optional notification workflow template exists
test_notification_workflow_exists() {
    if grep -q "SDLC Harness Update Check\|wizard-update-check\|Wizard Update Notification" "$WIZARD"; then
        pass "Optional notification workflow template exists in wizard"
    else
        fail "Wizard should contain optional notification workflow template"
    fi
}

# Test 6: Notification workflow template is valid YAML
test_notification_workflow_yaml() {
    # Extract the workflow YAML block from the wizard and validate it
    # NOTE (prior bug): An earlier version of the wizard had the "# Note: ISSUE_EOF terminator
    # indentation is intentional" comment placed *inside* the ISSUE_EOF heredoc in the
    # gh issue create --body call. This caused the comment to appear verbatim in generated
    # GitHub Issue bodies. The comment has since been moved to just before the gh issue create
    # call (outside the heredoc). This test validates the YAML is structurally sound, which
    # would catch similar issues that break YAML parsing.
    local temp_yaml
    temp_yaml=$(mktemp "${TMPDIR:-/tmp}/wizard-workflow-XXXXXX.yml")

    # Extract YAML between the notification workflow code fence.
    # FRAGILITY NOTE: The closing-fence detection (grep '^\`\`\`$') will misfire if any
    # nested code fence appears between "name: SDLC Harness Update Check" and the real
    # closing fence. This is low-risk given the current wizard structure but is line-count
    # sensitive — if the workflow section is restructured, re-verify this extraction logic.
    local in_block=false
    local found=false
    while IFS= read -r line; do
        if echo "$line" | grep -q "name: SDLC Harness Update Check"; then
            in_block=true
            found=true
            echo "$line" > "$temp_yaml"
            continue
        fi
        if [ "$in_block" = true ]; then
            if echo "$line" | grep -q '^\`\`\`$'; then
                in_block=false
                break
            fi
            echo "$line" >> "$temp_yaml"
        fi
    done < "$WIZARD"

    if [ "$found" = false ]; then
        fail "Could not find notification workflow YAML block"
        rm -f "$temp_yaml"
        return
    fi

    if WIZARD_YAML_PATH="$temp_yaml" python3 -c "import yaml, os; yaml.safe_load(open(os.environ['WIZARD_YAML_PATH']))" 2>/dev/null; then
        pass "Notification workflow template is valid YAML"
    else
        fail "Notification workflow template is not valid YAML"
    fi

    rm -f "$temp_yaml"
}

# Test 7: Notification workflow uses sparse-checkout
test_sparse_checkout() {
    # The workflow should use sparse-checkout to avoid cloning entire repo
    if grep -A 50 "SDLC Harness Update Check" "$WIZARD" | grep -q "sparse-checkout"; then
        pass "Notification workflow uses sparse-checkout"
    else
        fail "Notification workflow should use sparse-checkout"
    fi
}

# Test 8: Notification workflow only needs issues:write permission
test_workflow_permissions() {
    if grep -A 10 "SDLC Harness Update Check" "$WIZARD" | grep -q "issues: write"; then
        pass "Notification workflow uses issues: write permission"
    else
        fail "Notification workflow should use issues: write permission"
    fi
}

# Test 9: Notification workflow creates issues (not PRs)
test_creates_issues() {
    if grep -A 200 "SDLC Harness Update Check" "$WIZARD" | grep -q "gh issue create"; then
        pass "Notification workflow creates issues (not PRs)"
    else
        fail "Notification workflow should create issues, not PRs"
    fi
}

# Test 10: Notification workflow deduplicates (checks for existing issue)
test_dedup_check() {
    if grep -A 200 "SDLC Harness Update Check" "$WIZARD" | grep -q "wizard-update.*open\|--state open.*wizard-update"; then
        pass "Notification workflow checks for existing open issues"
    else
        fail "Notification workflow should check for existing open wizard-update issues"
    fi
}

# Test 11: Version metadata format documented
test_version_metadata_format() {
    if grep -q '<!-- SDLC Harness Version:' "$WIZARD"; then
        pass "Version metadata format documented in wizard"
    else
        fail "Wizard should document version metadata comment format"
    fi
}

# Test 12: Update flow has multi-phase structure
test_multi_phase_flow() {
    # Should have at least 3 phases: version check, changelog, apply
    local phase_count
    phase_count=$(grep -Eci "phase [0-9]|step [0-9].*:.*(version|changelog|fetch|apply|compare)" "$WIZARD" || echo "0")
    if [ "$phase_count" -ge 3 ]; then
        pass "Update flow has multi-phase structure ($phase_count phases found)"
    else
        fail "Update flow should have at least 3 phases, found $phase_count"
    fi
}

# Test 13: CHANGELOG URL returns valid content from live repo
test_changelog_url_live() {
    local url="https://raw.githubusercontent.com/BaseInfinity/claude-sdlc-harness/main/CHANGELOG.md"
    local content
    content=$(curl -sf --max-time 10 "$url" 2>/dev/null) || {
        pass "SKIPPED (offline): CHANGELOG URL live fetch"
        return
    }
    if echo "$content" | grep -q "# Changelog"; then
        pass "CHANGELOG URL returns valid content from live repo"
    else
        fail "CHANGELOG URL did not return expected content (missing '# Changelog' header)"
    fi
}

# Test 14: Wizard URL returns valid content from live repo
test_wizard_url_live() {
    local url="https://raw.githubusercontent.com/BaseInfinity/claude-sdlc-harness/main/CLAUDE_CODE_SDLC_WIZARD.md"
    local content
    content=$(curl -sf --max-time 10 "$url" 2>/dev/null) || {
        pass "SKIPPED (offline): Wizard URL live fetch"
        return
    }
    # Accepts either brand during the wizard -> harness rename, and this is a
    # correctness fix rather than a loosening. The property worth asserting is
    # "this URL serves the wizard document", not "the title is exactly X".
    # Pinning the new title made the change unmergeable by its own gate: the
    # check fetches `main`, `main` still serves the old title until the rename
    # merges, CI runs this suite, and merge-pr.sh treats CI-green as NOT
    # waivable. A test that asserts published state while sitting inside the
    # unpublished diff can never go green on the branch that changes it.
    # Tighten to "SDLC Harness" alone once the rename is on main.
    if echo "$content" | grep -qE "SDLC (Harness|Wizard)"; then
        pass "Wizard URL returns valid content from live repo"
    else
        fail "Wizard URL did not return expected content (no 'SDLC Harness' or 'SDLC Wizard' title)"
    fi
}

# Test 15: Local CHANGELOG version matches local wizard version metadata
test_version_consistency() {
    local changelog="$SCRIPT_DIR/../CHANGELOG.md"

    if [ ! -f "$changelog" ]; then
        fail "CHANGELOG.md not found"
        return
    fi

    # Extract latest version from CHANGELOG (first ## [x.y.z] line)
    local changelog_version
    changelog_version=$(grep -m1 '## \[' "$changelog" | sed 's/.*\[\(.*\)\].*/\1/')

    # Extract version from wizard metadata comment
    local wizard_version
    wizard_version=$(grep -o 'SDLC Harness Version: [0-9.]*' "$WIZARD" | head -1 | sed 's/SDLC Harness Version: //')

    if [ -z "$changelog_version" ] || [ -z "$wizard_version" ]; then
        fail "Could not extract versions (CHANGELOG: '$changelog_version', wizard: '$wizard_version')"
        return
    fi

    if [ "$changelog_version" = "$wizard_version" ]; then
        pass "Version consistency: CHANGELOG ($changelog_version) matches wizard metadata ($wizard_version)"
    else
        fail "Version mismatch: CHANGELOG says $changelog_version but wizard metadata says $wizard_version"
    fi
}

# Test 16: Wizard contains Cross-Model Review section
test_cross_model_review_section() {
    if grep -q "### Cross-Model Review Loop (REQUIRED" "$WIZARD"; then
        pass "Wizard contains Cross-Model Review section (REQUIRED)"
    else
        fail "Wizard should contain '### Cross-Model Review Loop (REQUIRED for High-Stakes)' section"
    fi
}

# Test 17: Step registry contains cross-model-review step
test_cross_model_review_step() {
    if grep -q "step-cross-model-review" "$WIZARD"; then
        pass "Step registry contains step-cross-model-review"
    else
        fail "Step registry should contain step-cross-model-review entry"
    fi
}

# Test 18: SKILL.md has a real TodoWrite step for cross-model review (not just a comment)
test_skill_cross_model_review() {
    local skill_file="$SCRIPT_DIR/../.claude/skills/sdlc/SKILL.md"
    # Exclude // comment lines in the TodoWrite block — we need an actual step
    if grep -i 'content:.*cross-model review' "$skill_file" | grep -qv '^\s*//'; then
        pass "SKILL.md has TodoWrite step for cross-model review"
    else
        fail "SKILL.md should have a TodoWrite step (not a comment) for cross-model review"
    fi
}

# Test 20: SKILL.md has a dedicated cross-model review instructions section
test_skill_cross_model_review_instructions() {
    local skill_file="$SCRIPT_DIR/../.claude/skills/sdlc/SKILL.md"
    if grep -q "## Cross-Model Review" "$skill_file"; then
        pass "SKILL.md has dedicated cross-model review section"
    else
        fail "SKILL.md should have a '## Cross-Model Review' section with instructions"
    fi
}

# --- /claude-update-wizard Skill Tests (#33) ---

# Test 22: Update skill file exists in local skills directory
test_update_skill_exists() {
    local skill_file="$SCRIPT_DIR/../.claude/skills/update/SKILL.md"
    if [ -f "$skill_file" ]; then
        pass "Update skill file exists at .claude/skills/update/SKILL.md"
    else
        fail "Update skill should exist at .claude/skills/update/SKILL.md"
    fi
}

# Test 23: Update skill template exists in CLI templates
test_update_skill_template_exists() {
    local template_file="$SCRIPT_DIR/../skills/update/SKILL.md"
    if [ -f "$template_file" ]; then
        pass "Update skill template exists at skills/update/SKILL.md"
    else
        fail "Update skill template should exist at skills/update/SKILL.md"
    fi
}

# Test 24: Local and template update skill files are identical
test_update_skill_parity() {
    local skill_file="$SCRIPT_DIR/../.claude/skills/update/SKILL.md"
    local template_file="$SCRIPT_DIR/../skills/update/SKILL.md"
    if diff -q "$skill_file" "$template_file" > /dev/null 2>&1; then
        pass "Local and template update skill files are identical"
    else
        fail "Local and template update skill files have drifted"
    fi
}

# Test 25: Update skill contains key content markers
test_update_skill_content() {
    local skill_file="$SCRIPT_DIR/../.claude/skills/update/SKILL.md"
    local ok=true
    grep -q "name: claude-update-wizard" "$skill_file" || ok=false
    grep -q "WebFetch" "$skill_file" || ok=false
    grep -q "CHANGELOG" "$skill_file" || ok=false
    grep -qi "selective\|per-file\|selectively" "$skill_file" || ok=false
    grep -q "sdlc-wizard check" "$skill_file" || ok=false
    if [ "$ok" = true ]; then
        pass "Update skill contains key content markers"
    else
        fail "Update skill should reference WebFetch, CHANGELOG, selective updates, and sdlc-wizard check"
    fi
}

# Test 26: Step registry includes step-update-wizard
test_step_registry_update_wizard() {
    if grep -q "step-update-wizard" "$WIZARD"; then
        pass "Step registry contains step-update-wizard"
    else
        fail "Step registry should contain step-update-wizard entry"
    fi
}

# Run all tests
test_changelog_url
test_wizard_url
test_step_registry
test_changelog_first
test_notification_workflow_exists
test_notification_workflow_yaml
test_sparse_checkout
test_workflow_permissions
test_creates_issues
test_dedup_check
test_version_metadata_format
test_multi_phase_flow
test_changelog_url_live
test_wizard_url_live
test_version_consistency
test_cross_model_review_section
test_cross_model_review_step
test_skill_cross_model_review
test_skill_cross_model_review_instructions
test_update_skill_exists
test_update_skill_template_exists
test_update_skill_parity
test_update_skill_content
test_step_registry_update_wizard

# --- Cross-Model Review Dialogue Tests (#40) ---

# Helper: extract the wizard's cross-model section.
#
# There is ONE, not two. This helper used to run a second `sed` for
# `## Cross-Model Review (REQUIRED` ... `## Test Review` — headings that lived
# inside the 639-line hand-copy fence #513 deleted and that exist nowhere in the
# document now. That range matched ZERO bytes, so every assertion built on it was
# testing the extractor, not the document. Deleted rather than repaired: it has no
# surviving target.
#
# The invariant it violated, which is the third instance of the same family in
# this repo: AN EXTRACTION THAT FEEDS AN ASSERTION MUST ASSERT ITS OWN
# NON-EMPTINESS, or the assertion silently tests the extractor.
wizard_cross_model_blocks() {
    local out
    out=$(sed -n '/^### Cross-Model Review Loop/,/^### [^C]/p' "$WIZARD")
    if [ -z "$out" ]; then
        echo "EXTRACTOR RETURNED NOTHING — assertions below would test nothing" >&2
        return 1
    fi
    printf '%s\n' "$out"
}

# Test 22: Wizard cross-model sections document response.json protocol
test_wizard_response_protocol() {
    local blocks
    blocks=$(wizard_cross_model_blocks)
    if echo "$blocks" | grep -q "response.json" && echo "$blocks" | grep -q "DISPUTED"; then
        pass "Wizard cross-model sections document response.json dialogue protocol"
    else
        fail "Wizard cross-model sections should document response.json with DISPUTED action"
    fi
}

# Test 23: Wizard cross-model sections document targeted recheck
test_wizard_targeted_recheck() {
    local blocks
    blocks=$(wizard_cross_model_blocks)
    if echo "$blocks" | grep -qi "targeted recheck"; then
        pass "Wizard cross-model sections document targeted recheck for round 2+"
    else
        fail "Wizard cross-model sections should document targeted recheck protocol"
    fi
}

# Test 24: SKILL.md documents the dialogue response protocol (both copies)
test_skill_dialogue_protocol() {
    local skill_file="$SCRIPT_DIR/../.claude/skills/sdlc/SKILL.md"
    local template_file="$SCRIPT_DIR/../skills/sdlc/SKILL.md"
    local ok=true
    for f in "$skill_file" "$template_file"; do
        local section
        section=$(sed -n '/## Cross-Model Review/,/## Test Review/p' "$f")
        if ! echo "$section" | grep -q "FIXED" || ! echo "$section" | grep -q "DISPUTED" || ! echo "$section" | grep -q "ACCEPTED"; then
            ok=false
        fi
    done
    if $ok; then
        pass "Both SKILL.md cross-model sections document FIXED/DISPUTED/ACCEPTED"
    else
        fail "Both SKILL.md cross-model sections should document the dialogue response actions"
    fi
}

# Test 25: Wizard cross-model sections document convergence rule
test_wizard_convergence_rule() {
    local blocks
    blocks=$(wizard_cross_model_blocks)
    if echo "$blocks" | grep -qi "max.*round\|escalate.*user"; then
        pass "Wizard cross-model sections document convergence rule"
    else
        fail "Wizard cross-model sections should document max rounds / escalation"
    fi
}

# Test 26: Local SKILL.md and template SKILL.md cross-model sections match
test_skill_template_parity() {
    local skill_file="$SCRIPT_DIR/../.claude/skills/sdlc/SKILL.md"
    local template_file="$SCRIPT_DIR/../skills/sdlc/SKILL.md"
    local skill_section template_section
    skill_section=$(sed -n '/## Cross-Model Review/,/## Test Review/p' "$skill_file")
    template_section=$(sed -n '/## Cross-Model Review/,/## Test Review/p' "$template_file")
    if [ "$skill_section" = "$template_section" ]; then
        pass "Local and template SKILL.md cross-model sections are identical"
    else
        fail "Local and template SKILL.md cross-model sections have drifted"
    fi
}

# Test 27: All recheck prompts in wizard are consistent (catches deep-dive drift)
test_wizard_recheck_prompt_parity() {
    # Count actual codex exec recheck prompts (quoted strings, not flow diagrams)
    local prompts
    prompts=$(grep -c '"You are doing a TARGETED RECHECK.*First read .reviews/handoff.json' "$WIZARD")
    local total
    total=$(grep -c '"You are doing a TARGETED RECHECK' "$WIZARD")
    # `-ge 2` encoded an accident, not a contract: the prompt appeared twice
    # because the wizard doc carried a second copy of the skill that re-pasted
    # it. #513 deleted that copy, so demanding two occurrences would have
    # required re-duplicating the very text the fix de-duplicated. One canonical
    # prompt is the goal; the parity check below is the actual invariant.
    if [ "$prompts" -eq "$total" ] && [ "$total" -ge 1 ]; then
        pass "All $total wizard recheck prompts include handoff.json-first instruction"
    else
        fail "Wizard has $total recheck prompts but only $prompts include handoff.json-first ($total expected)"
    fi
}

test_wizard_response_protocol
test_wizard_targeted_recheck
test_skill_dialogue_protocol
test_wizard_convergence_rule
test_skill_template_parity
test_wizard_recheck_prompt_parity

# --- CI Shepherd Model Tests (#36) ---

# Wizard documents local shepherd CI fix model
test_wizard_shepherd_model() {
    if grep -q "local shepherd" "$WIZARD" || grep -q "Local Shepherd" "$WIZARD"; then
        pass "Wizard documents local shepherd CI fix model"
    else
        fail "Wizard should document the local shepherd CI fix model"
    fi
}

# CI_CD.md documents shepherd
test_cicd_shepherd_section() {
    local cicd="$SCRIPT_DIR/../CI_CD.md"
    if grep -q "Local Shepherd" "$cicd"; then
        pass "CI_CD.md documents the local shepherd"
    else
        fail "CI_CD.md should document the local shepherd"
    fi
}

# SKILL.md labels CI feedback loops as shepherd
test_skill_shepherd_label() {
    local skill_file="$SCRIPT_DIR/../.claude/skills/sdlc/SKILL.md"
    if grep -q "Local Shepherd" "$skill_file"; then
        pass "SKILL.md labels CI feedback loops as Local Shepherd"
    else
        fail "SKILL.md should label CI feedback loops as 'Local Shepherd'"
    fi
}

test_wizard_shepherd_model
test_cicd_shepherd_section
test_skill_shepherd_label

# --- Gap Analysis vs Automation Recommender Tests (#35) ---

# Wizard Step 0.3 references /claude-automation-recommender
test_wizard_recommender_reference() {
    if grep -q "claude-automation-recommender" "$WIZARD"; then
        pass "Wizard Step 0.3 references /claude-automation-recommender"
    else
        fail "Wizard Step 0.3 should reference /claude-automation-recommender by name"
    fi
}

# Wizard documents suggestions-vs-enforcement positioning
test_wizard_gap_analysis() {
    if grep -qi "suggestion.*engine\|enforcement.*engine\|suggestions.*vs.*enforcement" "$WIZARD"; then
        pass "Wizard documents suggestions vs enforcement positioning"
    else
        fail "Wizard should document the suggestions-vs-enforcement gap analysis"
    fi
}

# Wizard Going Further has complementary tools section
test_wizard_complementary_tools() {
    if grep -q "Complementary Tools" "$WIZARD" || grep -q "Stack-Specific Configuration" "$WIZARD"; then
        pass "Wizard has complementary tools section in Going Further"
    else
        fail "Wizard should have a complementary tools section under Going Further"
    fi
}

# Setup wizard skill mentions automation recommender post-setup
test_setup_skill_recommender() {
    local setup_skill="$SCRIPT_DIR/../skills/setup/SKILL.md"
    if grep -q "claude-automation-recommender" "$setup_skill"; then
        pass "Setup wizard skill mentions /claude-automation-recommender"
    else
        fail "Setup wizard skill should mention /claude-automation-recommender for post-setup"
    fi
}

test_wizard_recommender_reference
test_wizard_gap_analysis
test_wizard_complementary_tools
test_setup_skill_recommender

# --- Context Management Guidance Tests (#38) ---

# Wizard documents /clear vs /compact comparison
test_wizard_clear_vs_compact() {
    if grep -q "/clear" "$WIZARD" && grep -q "Context Management" "$WIZARD"; then
        pass "Wizard documents /clear vs /compact context management"
    else
        fail "Wizard should document /clear vs /compact comparison"
    fi
}

# Wizard explains when to use /clear (between unrelated tasks)
test_wizard_clear_guidance() {
    if grep -qi "unrelated task\|fresh context\|switch.*task\|new task" "$WIZARD" && grep -q "/clear" "$WIZARD"; then
        pass "Wizard explains when to use /clear"
    else
        fail "Wizard should explain /clear is for switching between unrelated tasks"
    fi
}

# Wizard explains auto-compact behavior
test_wizard_auto_compact() {
    if grep -qi "auto-compact\|auto.compact\|automatically.*compact" "$WIZARD"; then
        pass "Wizard documents auto-compact behavior"
    else
        fail "Wizard should document auto-compact behavior"
    fi
}

# SKILL.md references /clear for task switching
test_skill_clear_reference() {
    local skill_file="$SCRIPT_DIR/../.claude/skills/sdlc/SKILL.md"
    if grep -q "/clear" "$skill_file"; then
        pass "SKILL.md references /clear for task switching"
    else
        fail "SKILL.md should reference /clear for between-task context management"
    fi
}

test_wizard_clear_vs_compact
test_wizard_clear_guidance
test_wizard_auto_compact
test_skill_clear_reference

# --- Autocompact + Context Model Guidance Tests (#88) ---

# Wizard documents CLAUDE_AUTOCOMPACT_PCT_OVERRIDE env var
test_wizard_autocompact_env_var() {
    if grep -q "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE" "$WIZARD"; then
        pass "Wizard documents CLAUDE_AUTOCOMPACT_PCT_OVERRIDE env var"
    else
        fail "Wizard should document CLAUDE_AUTOCOMPACT_PCT_OVERRIDE for autocompact tuning"
    fi
}

# Wizard has recommended thresholds, scoped to models that actually compact
# proactively.
#
# 2026-07-24: this test used to require both "75%" and "30%" to appear
# anywhere in the wizard, with the comment "(75% for 200K, 30% for 1M)".
# That framing is wrong at the concept level, not merely stale: per raw
# env-vars.md, the axis is NOT 200K-vs-1M, it is whether the model compacts
# PROACTIVELY. CLAUDE_AUTOCOMPACT_PCT_OVERRIDE only lowers the trigger when
# CLAUDE_CODE_AUTO_COMPACT_WINDOW is set, in cloud sessions, on Sonnet
# 4.6/Opus 4.6 without extended context, and on Sonnet 5. A local Opus
# session is the doc's own counter-example, so a 1M window alone never
# justified a percentage.
test_wizard_autocompact_thresholds() {
    if ! grep -qi "AUTOCOMPACT" "$WIZARD"; then
        fail "Wizard should document autocompact tuning"
        return
    fi
    # 75% must remain, explicitly scoped to Sonnet 5 (the documented
    # proactive case) — not floating as a generic "200K" recommendation.
    if grep -qE 'Sonnet 5.*75%|75%.*Sonnet 5' "$WIZARD"; then
        pass "Wizard scopes the 75% threshold to Sonnet 5's proactive compaction"
    else
        fail "Wizard must scope 75% to Sonnet 5 specifically (proactive-compaction case), not to a generic context size"
    fi
}

# Wizard has 1M vs 200K context model guidance
test_wizard_1m_vs_200k_guidance() {
    if grep -qF "1M" "$WIZARD" && grep -qF "200K" "$WIZARD" && grep -qi "context window" "$WIZARD"; then
        pass "Wizard has 1M vs 200K context model guidance"
    else
        fail "Wizard should have 1M vs 200K context model guidance"
    fi
}

# SKILL.md references autocompact tuning
test_skill_autocompact_reference() {
    local skill_file="$SCRIPT_DIR/../.claude/skills/sdlc/SKILL.md"
    if grep -qi "autocompact\|AUTOCOMPACT\|context.*window.*tun" "$skill_file"; then
        pass "SKILL.md references autocompact tuning"
    else
        fail "SKILL.md should reference autocompact tuning guidance"
    fi
}

# Setup skill includes context window configuration step
test_setup_skill_context_step() {
    local setup_skill="$SCRIPT_DIR/../skills/setup/SKILL.md"
    if grep -qi "autocompact\|context.*window\|AUTOCOMPACT" "$setup_skill"; then
        pass "Setup skill includes context window configuration step"
    else
        fail "Setup skill should include context window configuration during setup"
    fi
}

test_wizard_autocompact_env_var
test_wizard_autocompact_thresholds
test_wizard_1m_vs_200k_guidance
test_skill_autocompact_reference
test_setup_skill_context_step

# --- Token Efficiency Tests (#42) ---

# Wizard documents token efficiency techniques
test_wizard_token_efficiency() {
    if grep -q "Token Efficiency" "$WIZARD"; then
        pass "Wizard documents token efficiency techniques"
    else
        fail "Wizard should document token efficiency techniques"
    fi
}

# Wizard documents --max-budget-usd for CI cost control
test_wizard_max_budget() {
    if grep -q "max-budget-usd" "$WIZARD"; then
        pass "Wizard documents --max-budget-usd for CI cost control"
    else
        fail "Wizard should document --max-budget-usd as a CI cost safety net"
    fi
}

# CI_CD.md documents token tracking capabilities
test_cicd_token_tracking() {
    local cicd="$SCRIPT_DIR/../CI_CD.md"
    if grep -qi "OpenTelemetry\|otel\|cost.*track\|token.*track" "$cicd"; then
        pass "CI_CD.md documents token tracking capabilities"
    else
        fail "CI_CD.md should document available token tracking capabilities"
    fi
}

# Wizard documents /usage command for session monitoring (formerly /cost; CC 2.1.118 renamed with aliases)
test_wizard_cost_command() {
    if grep -q "/usage" "$WIZARD"; then
        pass "Wizard documents /usage command"
    else
        fail "Wizard should document /usage command for session monitoring"
    fi
}

test_wizard_token_efficiency
test_wizard_max_budget
test_cicd_token_tracking
test_wizard_cost_command

# --- Blank Repo Guidance Tests (#31) ---

# Wizard documents blank repo setup path
test_wizard_blank_repo_guidance() {
    if grep -qi "blank.*repo\|empty.*repo\|no.*CLAUDE.md\|fresh.*repo" "$WIZARD"; then
        pass "Wizard documents blank repo setup path"
    else
        fail "Wizard should document blank repo setup path"
    fi
}

# Blank repo fixture exists
test_blank_repo_fixture() {
    local fixture_dir="$SCRIPT_DIR/e2e/fixtures/blank-repo"
    if [ -d "$fixture_dir" ] && [ -f "$fixture_dir/README.md" ]; then
        pass "Blank repo fixture exists"
    else
        fail "Blank repo fixture should exist at tests/e2e/fixtures/blank-repo/"
    fi
}

test_wizard_blank_repo_guidance
test_blank_repo_fixture

# --- Feature Documentation Enforcement Tests (#43) ---

SKILL="$SCRIPT_DIR/../.claude/skills/sdlc/SKILL.md"
SKILL_TEMPLATE="$SCRIPT_DIR/../skills/sdlc/SKILL.md"

# Wizard has ADR pattern guidance
test_wizard_adr_pattern() {
    if grep -q "docs/decisions/" "$WIZARD" && grep -q "ADR" "$WIZARD"; then
        pass "Wizard has ADR (Architecture Decision Record) pattern guidance"
    else
        fail "Wizard should document ADR pattern (docs/decisions/)"
    fi
}

# Wizard recommends claude-md-improver for CLAUDE.md health
test_wizard_claude_md_improver() {
    if grep -q "claude-md-improver" "$WIZARD" && grep -q "CLAUDE.md health" "$WIZARD"; then
        pass "Wizard recommends claude-md-improver for CLAUDE.md health"
    else
        fail "Wizard should recommend claude-md-improver for CLAUDE.md health"
    fi
}

# SDLC skill enforces doc updates when code changes affect documented features
test_skill_doc_enforcement() {
    if grep -q "doc.*update" "$SKILL" && grep -q "code change.*doc\|feature doc.*update\|update.*feature doc" "$SKILL"; then
        pass "SDLC skill enforces doc updates for code changes"
    else
        fail "SDLC skill should enforce doc updates when code changes affect documented features"
    fi
}

# Wizard documents docs-in-sync detection
test_wizard_docs_in_sync() {
    if grep -q "docs.*sync\|doc.*drift\|doc.*stale" "$WIZARD"; then
        pass "Wizard documents docs-in-sync detection"
    else
        fail "Wizard should document how to detect when docs fall out of sync with code"
    fi
}

# SDLC skill template matches live skill (parity)
test_skill_doc_enforcement_template_parity() {
    if grep -q "doc.*update" "$SKILL_TEMPLATE" && grep -q "code change.*doc\|feature doc.*update\|update.*feature doc" "$SKILL_TEMPLATE"; then
        pass "SDLC skill template has doc enforcement (parity)"
    else
        fail "SDLC skill template should match live skill doc enforcement"
    fi
}

# Wizard has feature doc structure with ADR alongside existing patterns
test_wizard_feature_doc_structure() {
    if grep -q "docs/decisions/" "$WIZARD" && grep -q "_PLAN.md\|_DOCS.md" "$WIZARD"; then
        pass "Wizard feature doc structure includes ADRs alongside existing patterns"
    else
        fail "Wizard should show ADRs alongside existing feature doc patterns"
    fi
}

test_wizard_adr_pattern
test_wizard_claude_md_improver
test_skill_doc_enforcement
test_wizard_docs_in_sync
test_skill_doc_enforcement_template_parity
test_wizard_feature_doc_structure

# --- Feature Doc Enforcement Teeth ---
echo ""
echo "--- Feature Doc Enforcement Teeth ---"

# SKILL.md recommends _DOCS.md as primary pattern (not _PLAN.md)
test_skill_docs_md_primary() {
    if grep -q '_DOCS.md' "$SKILL" && grep -q 'AUTH_DOCS.md\|LOGIN_DOCS.md\|PAYMENTS_DOCS.md' "$SKILL"; then
        pass "SKILL.md uses _DOCS.md as primary feature doc pattern"
    else
        fail "SKILL.md should recommend _DOCS.md as primary feature doc pattern (living docs, not plans)"
    fi
}

# SKILL.md has feature doc creation gate (not just update)
test_skill_doc_creation_gate() {
    if grep -q 'create.*feature doc\|no.*_DOCS.md.*exists.*create' "$SKILL"; then
        pass "SKILL.md enforces feature doc creation for major features"
    else
        fail "SKILL.md should enforce creating feature docs for major features, not just updating existing ones"
    fi
}

# SKILL.md doc sync section has ROADMAP feeds CHANGELOG enforcement
test_skill_roadmap_enforcement() {
    if grep -q 'ROADMAP.*feeds CHANGELOG\|ROADMAP feeds CHANGELOG' "$SKILL"; then
        pass "SKILL.md enforces ROADMAP feeds CHANGELOG in doc sync section"
    else
        fail "SKILL.md doc sync section should enforce ROADMAP feeds CHANGELOG"
    fi
}

# Wizard Feature Documentation section recommends _DOCS.md as living docs
test_wizard_docs_md_primary() {
    if grep -A5 '### Feature Documentation' "$WIZARD" | grep -q 'living doc'; then
        pass "Wizard Feature Documentation section recommends _DOCS.md as living docs"
    else
        fail "Wizard Feature Documentation section should recommend _DOCS.md as living documentation"
    fi
}

# Doc sync TodoWrite step includes creation, not just update
test_skill_todow_doc_creation() {
    if grep -q 'update or create feature doc\|create.*feature doc.*if.*needed\|Doc sync.*create' "$SKILL"; then
        pass "TodoWrite doc sync step includes doc creation"
    else
        fail "TodoWrite doc sync step should include creating feature docs, not just updating"
    fi
}

# SKILL.md doc section has enforcement language (MUST/REQUIRED, not just "consider")
test_skill_doc_enforcement_teeth() {
    if grep -q 'MUST.*update.*doc\|doc.*MUST.*current\|REQUIRED.*doc' "$SKILL"; then
        pass "SKILL.md has enforcement language for doc sync"
    else
        fail "SKILL.md doc sync should use enforcement language (MUST/REQUIRED), not just suggestions"
    fi
}

test_skill_docs_md_primary
test_skill_doc_creation_gate
test_skill_roadmap_enforcement
test_wizard_docs_md_primary
test_skill_todow_doc_creation
test_skill_doc_enforcement_teeth

# --- Version-Pinned Update Gate Tests (#46) ---
# DEPRECATED per #231 Phase 3a: the version-test job that these guarded was
# deleted in v1.51.0. Manual local replacement: `npm i -g
# @anthropic-ai/claude-code@<version> && tests/e2e/local-shepherd.sh <PR>`.
# Stubs preserve harness counters; remove after one release if no regressions.
echo ""
echo "--- Version-Pinned Update Gate (#46, DEPRECATED Phase 3a) ---"

test_version_gate_install_id() {
    pass "n/a per #231 Phase 3a — version-test deleted; install step gone with it"
}

test_version_gate_cc_path_capture() {
    pass "n/a per #231 Phase 3a — version-test deleted; cc_path capture gone with it"
}

test_version_gate_path_passed() {
    pass "n/a per #231 Phase 3a — version-test deleted; path_to_claude_code_executable not needed"
}

# CI_CD.md must document the manual local replacement procedure.
test_cicd_version_pinned_gate() {
    local cicd="$SCRIPT_DIR/../CI_CD.md"
    if grep -qE "manual.*local-shepherd|npm i -g @anthropic-ai/claude-code@" "$cicd"; then
        pass "CI_CD.md documents the manual local replacement for version-test"
    else
        fail "CI_CD.md should document the manual `npm i + local-shepherd.sh` replacement procedure"
    fi
}

test_version_gate_install_id
test_version_gate_cc_path_capture
test_version_gate_path_passed
test_cicd_version_pinned_gate

# --- Release Consistency Tests ---
echo ""
echo "--- Release Consistency ---"

# package.json version matches CHANGELOG latest entry
test_package_version_matches_changelog() {
    local pkg="$SCRIPT_DIR/../package.json"
    local changelog="$SCRIPT_DIR/../CHANGELOG.md"
    local pkg_version
    pkg_version=$(node -e "console.log(require('$pkg').version)")
    local changelog_version
    changelog_version=$(grep -m1 '## \[' "$changelog" | sed 's/.*\[\(.*\)\].*/\1/')
    if [ "$pkg_version" = "$changelog_version" ]; then
        pass "package.json ($pkg_version) matches CHANGELOG ($changelog_version)"
    else
        fail "package.json ($pkg_version) should match CHANGELOG latest ($changelog_version)"
    fi
}

# package.json version matches SDLC.md visible version table (not just metadata comment)
test_package_version_matches_sdlc() {
    local pkg="$SCRIPT_DIR/../package.json"
    local sdlc="$SCRIPT_DIR/../SDLC.md"
    local pkg_version
    pkg_version=$(node -e "console.log(require('$pkg').version)")
    # Check visible table row (| Wizard Version | X.X.X |), not metadata comment
    local sdlc_table_version
    sdlc_table_version=$(grep '^| Wizard Version' "$sdlc" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
    # Also check metadata comment for consistency
    local sdlc_meta_version
    sdlc_meta_version=$(grep '<!-- SDLC Harness Version:' "$sdlc" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
    if [ "$pkg_version" = "$sdlc_table_version" ] && [ "$pkg_version" = "$sdlc_meta_version" ]; then
        pass "package.json ($pkg_version) matches SDLC.md table ($sdlc_table_version) and metadata ($sdlc_meta_version)"
    else
        fail "package.json ($pkg_version) vs SDLC.md table ($sdlc_table_version) vs metadata ($sdlc_meta_version) — should all match"
    fi
}

test_package_version_matches_changelog
test_package_version_matches_sdlc

# --- CI Shepherd Opt-In + Workflow Analyzer Tests (#48) ---
echo ""
echo "--- CI Shepherd Opt-In + Workflow Analyzer (#48) ---"

# Wizard has shepherd opt-in as explicit top-level CI question
test_wizard_shepherd_optin_question() {
    if grep -q "CI shepherd" "$WIZARD" && grep -q "opt-in\|Enable.*shepherd" "$WIZARD"; then
        pass "Wizard has shepherd opt-in as explicit CI question"
    else
        fail "Wizard should have shepherd opt-in as an explicit top-level CI question"
    fi
}

# Wizard gates CI sub-questions behind shepherd opt-in
test_wizard_shepherd_gates_sub_questions() {
    # The shepherd question should appear BEFORE the CI monitoring detail questions
    local shepherd_line
    shepherd_line=$(grep -n "CI shepherd" "$WIZARD" | head -1 | cut -d: -f1)
    local monitoring_line
    monitoring_line=$(grep -n "monitor CI checks" "$WIZARD" | head -1 | cut -d: -f1)
    if [ -n "$shepherd_line" ] && [ -n "$monitoring_line" ] && [ "$shepherd_line" -lt "$monitoring_line" ]; then
        pass "Wizard gates CI sub-questions behind shepherd opt-in"
    else
        fail "Wizard shepherd opt-in (line $shepherd_line) should appear before CI monitoring detail (line $monitoring_line)"
    fi
}

# Setup wizard uses confidence-driven approach (no fixed question count)
test_setup_skill_confidence_driven() {
    local skill_file="$SCRIPT_DIR/../.claude/skills/setup/SKILL.md"
    if grep -qi "confidence" "$skill_file" && ! grep -q "Ask ALL 18" "$skill_file"; then
        pass "Setup wizard uses confidence-driven approach (no fixed 18 questions)"
    else
        fail "Setup wizard should use confidence-driven approach, not fixed 18 questions"
    fi
}

# Setup wizard skill uses resolved/unresolved state model (not numeric threshold)
test_setup_skill_resolved_state_model() {
    local skill_file="$SCRIPT_DIR/../.claude/skills/setup/SKILL.md"
    if grep -qi "UNRESOLVED\|RESOLVED" "$skill_file" && ! grep -qE '(HIGH|MEDIUM|LOW).*95%|confidence.*>=.*95' "$skill_file"; then
        pass "Setup wizard uses resolved/unresolved state model (no vague numeric threshold)"
    else
        fail "Setup wizard should use RESOLVED/UNRESOLVED states, not a numeric confidence threshold"
    fi
}

# Setup wizard skill scans FIRST, asks SECOND (step ordering)
test_setup_skill_scan_then_ask() {
    local skill_file="$SCRIPT_DIR/../.claude/skills/setup/SKILL.md"
    local scan_line
    scan_line=$(grep -n "### Step 1: Auto-Scan" "$skill_file" | head -1 | cut -d: -f1)
    local confidence_line
    confidence_line=$(grep -n "### Step 2: Build Confidence\|### Step 3: Present Findings and Fill Gaps" "$skill_file" | head -1 | cut -d: -f1)
    if [ -n "$scan_line" ] && [ -n "$confidence_line" ] && [ "$scan_line" -lt "$confidence_line" ]; then
        pass "Setup wizard scans before asking (Step 1 scan=$scan_line < Step 2/3 confidence=$confidence_line)"
    else
        fail "Setup wizard should scan FIRST (Step 1) then build confidence and ask (Step 2/3) (scan=$scan_line, confidence=$confidence_line)"
    fi
}

# Setup wizard does NOT hardcode a fixed number of questions
test_setup_skill_no_fixed_question_count() {
    local skill_file="$SCRIPT_DIR/../.claude/skills/setup/SKILL.md"
    # Check for prescriptive fixed counts like "Ask ALL 18 Questions" or "asks 18 config questions"
    if grep -qE "Ask ALL [0-9]+ Questions|asks [0-9]+ .* questions" "$skill_file"; then
        fail "Setup wizard should NOT hardcode a fixed number of questions"
    else
        pass "Setup wizard does not hardcode a fixed question count"
    fi
}

# Setup wizard skill describes data points not numbered questions
test_setup_skill_data_points() {
    local skill_file="$SCRIPT_DIR/../.claude/skills/setup/SKILL.md"
    if grep -qi "data point\|configuration data" "$skill_file"; then
        pass "Setup wizard describes configuration as data points to resolve"
    else
        fail "Setup wizard should describe configuration as data points, not numbered questions"
    fi
}

# Setup wizard template parity (live matches CLI template)
test_setup_skill_template_parity() {
    local live="$SCRIPT_DIR/../.claude/skills/setup/SKILL.md"
    local template="$SCRIPT_DIR/../skills/setup/SKILL.md"
    if diff -q "$live" "$template" > /dev/null 2>&1; then
        pass "Setup wizard live skill matches CLI template"
    else
        fail "Setup wizard live skill does NOT match CLI template"
    fi
}

# Setup wizard terminology consistency (no stale "confidence levels" in resolved/unresolved model)
test_setup_skill_no_stale_confidence_terminology() {
    local skill_file="$SCRIPT_DIR/../.claude/skills/setup/SKILL.md"
    # The Rules section should use "resolution state" not "confidence levels"
    # (confidence-driven is fine as a high-level name, but data point states are resolved/unresolved)
    if grep -q "with confidence levels" "$skill_file"; then
        fail "Setup wizard Rules still uses stale 'with confidence levels' (should be 'resolution state')"
    else
        pass "Setup wizard terminology consistent (no stale 'with confidence levels')"
    fi
}

# ci-analyzer was deleted (unvalidated addition — violated Prove It philosophy)
test_ci_analyzer_deleted() {
    if [ -d "$SCRIPT_DIR/../.claude/skills/ci-analyzer" ]; then
        fail "ci-analyzer skill directory must NOT exist (deleted — unvalidated addition)"
    else
        pass "ci-analyzer skill directory does not exist (correctly deleted)"
    fi
}

# ci-analyzer template was also deleted
test_ci_analyzer_template_deleted() {
    if [ -d "$SCRIPT_DIR/../skills/ci-analyzer" ]; then
        fail "ci-analyzer CLI template directory must NOT exist (deleted)"
    else
        pass "ci-analyzer CLI template directory does not exist (correctly deleted)"
    fi
}

# Wizard doc should NOT reference /ci-analyzer as a skill to run
test_wizard_no_ci_analyzer_skill() {
    if grep -q "/ci-analyzer" "$WIZARD"; then
        fail "Wizard should NOT reference /ci-analyzer (skill was deleted)"
    else
        pass "Wizard does not reference /ci-analyzer skill"
    fi
}

# CLI init.js should NOT distribute ci-analyzer in FILES array
test_no_stale_ci_analyzer_distribution() {
    local init_js="$SCRIPT_DIR/../cli/init.js"
    # Check specifically for ci-analyzer in the FILES distribution array (src/dest lines)
    if grep -q "src:.*ci-analyzer\|dest:.*ci-analyzer" "$init_js"; then
        fail "cli/init.js should NOT distribute ci-analyzer in FILES array (skill was deleted)"
    else
        pass "cli/init.js does not distribute ci-analyzer in FILES array"
    fi
}

# SDLC skill must have Prove It Gate section
test_skill_prove_it_gate() {
    if grep -q "Prove It Gate" "$SKILL"; then
        pass "SDLC skill has Prove It Gate section"
    else
        fail "SDLC skill should have 'Prove It Gate' section to prevent unvalidated additions"
    fi
}

# SDLC skill TodoWrite checklist must include prove-it step (not just section heading)
test_skill_prove_it_gate_in_checklist() {
    # Check specifically for the TodoWrite entry, not the section heading
    if grep -q 'content:.*Prove It Gate.*adding new component' "$SKILL"; then
        pass "SDLC skill TodoWrite includes prove-it gate checklist entry"
    else
        fail "SDLC skill TodoWrite checklist should include a 'Prove It Gate: adding new component?' entry"
    fi
}

# Wizard "Prove It" section must mention own additions (not just native vs custom)
test_wizard_prove_it_own_additions() {
    if grep -A 20 "Prove It" "$WIZARD" | grep -qi "your own additions\|own additions too"; then
        pass "Wizard Prove It section covers own additions"
    else
        fail "Wizard Prove It section should mention own additions (not just native vs custom)"
    fi
}

# Wizard should reference ci-analyzer deletion as evidence
test_wizard_prove_it_evidence() {
    if grep -qi "ci-analyzer.*deleted\|ci-analyzer.*existence-only" "$WIZARD"; then
        pass "Wizard references ci-analyzer as Prove It evidence"
    else
        fail "Wizard should reference ci-analyzer deletion as evidence for Prove It enforcement"
    fi
}

# No skill should reference deleted features (internal consistency)
test_skill_no_stale_references() {
    local stale_found=false
    local stale_details=""
    for skill_dir in "$SCRIPT_DIR"/../.claude/skills/*/; do
        local skill_file="$skill_dir/SKILL.md"
        if [ -f "$skill_file" ]; then
            local skill_name
            skill_name=$(basename "$skill_dir")
            # Check for references to deleted features
            if grep -qi "ci-self-heal\|ci-autofix\|autofix\.yml\|bot fallback\|auto-fix bot\|auto-fix loop" "$skill_file"; then
                stale_found=true
                stale_details="$skill_name references deleted self-heal/autofix features"
                break
            fi
            if grep -qi "/ci-analyzer" "$skill_file"; then
                stale_found=true
                stale_details="$skill_name references deleted /ci-analyzer skill"
                break
            fi
        fi
    done
    if [ "$stale_found" = true ]; then
        fail "Stale reference found: $stale_details"
    else
        pass "No skills reference deleted features (internal consistency check)"
    fi
}

test_wizard_shepherd_optin_question
test_wizard_shepherd_gates_sub_questions
test_setup_skill_confidence_driven
test_setup_skill_resolved_state_model
test_setup_skill_scan_then_ask
test_setup_skill_no_fixed_question_count
test_setup_skill_data_points
test_setup_skill_template_parity
test_setup_skill_no_stale_confidence_terminology
test_ci_analyzer_deleted
test_ci_analyzer_template_deleted
test_wizard_no_ci_analyzer_skill
test_no_stale_ci_analyzer_distribution
test_skill_prove_it_gate
test_skill_prove_it_gate_in_checklist
test_wizard_prove_it_own_additions
test_wizard_prove_it_evidence
test_skill_no_stale_references

# --- Cross-Model Release Review Tests (#49) ---
echo ""
echo "--- Cross-Model Release Review (#49) ---"

# Wizard "When to use this" includes releases/publishes
test_wizard_release_review_trigger() {
    if grep -A 8 "When to use this:" "$WIZARD" | grep -qi "release.*publish"; then
        pass "Wizard lists releases/publishes as cross-model review trigger"
    else
        fail "Wizard 'When to use this' should include releases/publishes"
    fi
}

# Wizard has Release Review Focus subsection
test_wizard_release_review_focus() {
    # Renamed by #513: the doc carried both a "Release Review Checklist" and a
    # near-identical "Release Review Focus"; they were merged under the latter.
    # Anchored end-to-end, depth left free — depth is not the contract.
    if grep -qE "^#+ Release Review Focus[[:space:]]*$" "$WIZARD"; then
        pass "Wizard has Release Review Focus subsection"
    else
        fail "Wizard should have a 'Release Review Focus' subsection"
    fi
}

# Wizard references v1.20.0 as evidence for release review
test_wizard_release_review_evidence() {
    if grep -A 30 "Release Review Focus" "$WIZARD" | grep -q "v1.20.0"; then
        pass "Wizard Release Review references v1.20.0 evidence"
    else
        fail "Wizard Release Review Focus should reference v1.20.0 as evidence"
    fi
}

# SKILL.md "When to run" includes releases
test_skill_release_review_trigger() {
    if grep "When to run" "$SKILL" | grep -qi "release.*publish"; then
        pass "SKILL.md 'When to run' includes releases/publishes"
    else
        fail "SKILL.md 'When to run' should include releases/publishes"
    fi
}

# GH #489: Release Review Focus lives in the wizard doc, not the byte-capped skill.
# It is read at a discrete, self-announcing moment — you know when you are cutting
# a release — so it is on-demand content, not something the driver needs mid-task
# without warning. Asserted against the doc that now owns it.
test_skill_release_review_section() {
    # Anchored end-to-end, depth left free. Unanchored, this matched the
    # `#### Release Review Focus` heading by substring — accidentally correct
    # after #513 renested it, which is not the same as being right. Depth is not
    # the contract; the section existing under its own heading is.
    if grep -qE "^#+ Release Review Focus[[:space:]]*$" "$WIZARD"; then
        pass "#489: Release Review Focus is in the wizard doc"
    else
        fail "wizard doc is missing a 'Release Review Focus' heading — the skill points here for it"
    fi
}

# Shipped SKILL "When to run" includes releases
test_shipped_skill_release_trigger() {
    # GH #513: this used to read the wizard doc's embedded skill copy, inside a
    # ```` fence under "## Step 6: Create SDLC Skill" — the lane the CLI never
    # installs, and which this PR deletes. Re-pointed at the file that ships.
    if grep "When to run" "$SCRIPT_DIR/../skills/sdlc/SKILL.md" | grep -qi "release\|publish"; then
        pass "shipped SKILL.md 'When to run' includes releases/publishes"
    else
        fail "shipped SKILL.md 'When to run' should include releases/publishes"
    fi
}

test_wizard_release_review_trigger
test_wizard_release_review_focus
test_wizard_release_review_evidence
test_skill_release_review_trigger
test_skill_release_review_section
test_shipped_skill_release_trigger

# Release review focus areas — wizard doc only since #489 moved the section
# out of the byte-capped skill. Checking the skill too would now assert that
# on-demand content is duplicated into the always-loaded file, which is the
# thing #489 exists to stop.
# The five needles are INLINE rather than looped through "${areas[@]}". A needle
# reaching grep through a variable is opaque to tests/lib/fence-only-assertions.py,
# which reported it as unverifiable — correctly: had any of these strings existed
# only inside the deleted hand-copy fence, this test would have passed by matching
# a quotation of a draft nobody installs, which is the #513 defect exactly.
test_release_review_focus_area_parity() {
    local all_match=true
    local area
    for area in "CHANGELOG consistency" "Version parity" "Stale examples" \
                "Docs accuracy" "CLI-distributed file parity"; do
        case "$area" in
            "CHANGELOG consistency")        grep -q "CHANGELOG consistency" "$WIZARD" ;;
            "Version parity")               grep -q "Version parity" "$WIZARD" ;;
            "Stale examples")               grep -q "Stale examples" "$WIZARD" ;;
            "Docs accuracy")                grep -q "Docs accuracy" "$WIZARD" ;;
            "CLI-distributed file parity")  grep -q "CLI-distributed file parity" "$WIZARD" ;;
        esac || {
            fail "Wizard missing release review focus area: $area"
            all_match=false
            break
        }
    done
    if [ "$all_match" = true ]; then
        pass "#489: all 5 release review focus areas present in the wizard doc"
    fi
}

# Wizard has release review_instructions example
test_wizard_release_review_instructions_example() {
    if grep -q "review_instructions.*for releases" "$WIZARD" && grep -q "CHANGELOG completeness" "$WIZARD"; then
        pass "Wizard has release review_instructions example"
    else
        fail "Wizard should have example review_instructions for releases"
    fi
}

test_release_review_focus_area_parity
test_wizard_release_review_instructions_example

# -------------------------------------------------------------------
# #53 Plan Auto-Approval Gate
# -------------------------------------------------------------------

echo ""
echo "--- #53 Plan Auto-Approval Gate ---"

# Test: SDLC skill has auto-approval guidance
test_skill_auto_approval_gate() {
    if grep -qi 'auto.?approv\|skip.*plan.*approval\|skip.*approval.*step' "$SKILL"; then
        pass "SDLC skill has plan auto-approval guidance"
    else
        fail "SDLC skill missing plan auto-approval guidance"
    fi
}

# Test: Auto-approval requires HIGH confidence (95%+)
test_skill_auto_approval_requires_high_confidence() {
    if grep -qiE '95.*confidence|confidence.*95|HIGH.*skip|HIGH.*auto' "$SKILL"; then
        pass "Auto-approval requires 95%+ confidence"
    else
        fail "Auto-approval should require 95%+ confidence"
    fi
}

# Test: Auto-approval requires low complexity
test_skill_auto_approval_requires_low_complexity() {
    if grep -qi 'single.?file\|trivial\|low.*complex\|small.*change' "$SKILL"; then
        pass "Auto-approval has complexity guard"
    else
        fail "Auto-approval should have complexity guard (single-file, trivial)"
    fi
}

# Test: Wizard doc has auto-approval section
test_wizard_auto_approval() {
    if grep -qi 'auto.?approv\|skip.*plan.*approval' "$WIZARD"; then
        pass "Wizard doc has plan auto-approval guidance"
    else
        fail "Wizard doc missing plan auto-approval guidance"
    fi
}

test_skill_auto_approval_gate
test_skill_auto_approval_requires_high_confidence
test_skill_auto_approval_requires_low_complexity
test_wizard_auto_approval

# -------------------------------------------------------------------
# #55 Debugging Methodology
# -------------------------------------------------------------------

echo ""
echo "--- #55 Debugging Methodology ---"

# Test: SDLC skill has debugging methodology section
test_skill_debugging_methodology() {
    if grep -qi 'debug.*methodol\|systematic.*debug\|debugging.*workflow' "$SKILL"; then
        pass "SDLC skill has debugging methodology"
    else
        fail "SDLC skill missing debugging methodology section"
    fi
}

# Test: Debugging section has reproduce→isolate→root cause flow
test_skill_debugging_flow() {
    if grep -qi 'reproduce' "$SKILL" && grep -qi 'isolate\|narrow' "$SKILL" && grep -qiE 'root.?cause' "$SKILL"; then
        pass "Debugging section has reproduce→isolate→root cause flow"
    else
        fail "Debugging section should have reproduce→isolate→root cause flow"
    fi
}

# Test: Debugging section mentions git bisect
test_skill_debugging_bisect() {
    if grep -q 'git bisect' "$SKILL"; then
        pass "Debugging section mentions git bisect"
    else
        fail "Debugging section should mention git bisect for regressions"
    fi
}

# Test: Wizard doc has debugging methodology
test_wizard_debugging_methodology() {
    if grep -qi 'debug.*methodol\|systematic.*debug\|debugging.*workflow' "$WIZARD"; then
        pass "Wizard doc has debugging methodology"
    else
        fail "Wizard doc missing debugging methodology"
    fi
}

test_skill_debugging_methodology
test_skill_debugging_flow
test_skill_debugging_bisect
test_wizard_debugging_methodology

# -------------------------------------------------------------------
# #37 /feedback Community Loop
# -------------------------------------------------------------------

echo ""
echo "--- #37 /feedback Community Loop ---"

# Test: /feedback skill exists in templates
test_feedback_skill_exists() {
    if [ -f "$SCRIPT_DIR/../skills/feedback/SKILL.md" ]; then
        pass "/feedback skill template exists"
    else
        fail "/feedback skill template not found"
    fi
}

# Test: /feedback skill has correct frontmatter
test_feedback_skill_frontmatter() {
    local skill="$SCRIPT_DIR/../skills/feedback/SKILL.md"
    if [ -f "$skill" ] && grep -q '^name: feedback$' "$skill" && grep -q '^effort:' "$skill"; then
        pass "/feedback skill has correct frontmatter"
    else
        fail "/feedback skill missing correct frontmatter (name: feedback + effort)"
    fi
}

# Test: /feedback skill mentions privacy/permission
test_feedback_skill_privacy() {
    local skill="$SCRIPT_DIR/../skills/feedback/SKILL.md"
    if [ -f "$skill" ] && grep -qi 'privacy\|permission\|consent\|opt.?in' "$skill"; then
        pass "/feedback skill addresses privacy"
    else
        fail "/feedback skill should address privacy/permission before scanning"
    fi
}

# Test: /feedback skill creates GH issue
test_feedback_skill_gh_issue() {
    local skill="$SCRIPT_DIR/../skills/feedback/SKILL.md"
    if [ -f "$skill" ] && grep -qi 'gh issue\|github issue\|create.*issue' "$skill"; then
        pass "/feedback skill creates GH issues"
    else
        fail "/feedback skill should create GH issues for contributions"
    fi
}

test_feedback_skill_exists
test_feedback_skill_frontmatter
test_feedback_skill_privacy
test_feedback_skill_gh_issue

# -------------------------------------------------------------------
# #44 BRANDING.md Detection
# -------------------------------------------------------------------

echo ""
echo "--- #44 BRANDING.md Detection ---"

# Test: Setup wizard detects branding-related files
test_setup_detects_branding() {
    local setup="$SCRIPT_DIR/../skills/setup/SKILL.md"
    if grep -qi 'brand\|BRANDING' "$setup"; then
        pass "Setup wizard detects branding files"
    else
        fail "Setup wizard should detect branding-related files"
    fi
}

# Test: Wizard doc has BRANDING.md template or guidance
test_wizard_branding_template() {
    if grep -qi 'BRANDING.md' "$WIZARD"; then
        pass "Wizard doc has BRANDING.md guidance"
    else
        fail "Wizard doc missing BRANDING.md guidance"
    fi
}

# Test: BRANDING.md generation is conditional (only when UI/content detected)
test_branding_conditional() {
    local setup="$SCRIPT_DIR/../skills/setup/SKILL.md"
    if grep -qi 'brand.*detect\|detect.*brand\|if.*brand\|brand.*found\|UI.*brand\|content.*brand' "$setup"; then
        pass "BRANDING.md generation is conditional on detection"
    else
        fail "BRANDING.md should only be generated when branding assets detected"
    fi
}

test_setup_detects_branding
test_wizard_branding_template
test_branding_conditional

# -------------------------------------------------------------------
# #32 N-Reviewer CI Pipeline
# -------------------------------------------------------------------

echo ""
echo "--- #32 N-Reviewer CI Pipeline ---"

# Test: Wizard has multi-reviewer guidance
# -E (extended regex) is required for the bare `?` in `multi.?review` to act
# as a quantifier — in basic regex (grep's default) an unescaped `?` matches
# a LITERAL question mark, so this always fell through to the other
# alternatives. Previously masked by an incidental "parallel ... reviewer"
# phrase collision elsewhere in the file (unrelated content, not real
# multi-reviewer guidance) — exposed once that unrelated text was trimmed.
test_wizard_multi_reviewer() {
    if grep -qiE 'multi.?review|N.?review|parallel.*review|multiple.*review' "$WIZARD"; then
        pass "Wizard has multi-reviewer guidance"
    else
        fail "Wizard missing multi-reviewer CI guidance"
    fi
}

# Test: SDLC skill has multi-reviewer section
test_skill_multi_reviewer() {
    if grep -qiE 'multi.?review|N.?review|parallel.*review|multiple.*review' "$SKILL"; then
        pass "SDLC skill has multi-reviewer guidance"
    else
        fail "SDLC skill missing multi-reviewer guidance"
    fi
}

# Test: Multi-reviewer guidance mentions per-reviewer response
test_multi_reviewer_response_pattern() {
    if grep -qiE 'per.?review|each.*review|respond.*each|address.*each' "$SKILL"; then
        pass "Multi-reviewer guidance has per-reviewer response pattern"
    else
        fail "Multi-reviewer should describe responding to each reviewer independently"
    fi
}

test_wizard_multi_reviewer
test_skill_multi_reviewer
test_multi_reviewer_response_pattern

# -------------------------------------------------------------------
# #45 /agents Subagent Exploration
# -------------------------------------------------------------------

echo ""
echo "--- #45 /agents Subagent Exploration ---"

# Test: Wizard has agents/subagent guidance
test_wizard_agents_guidance() {
    if grep -qi '\.claude/agents\|custom.*subagent\|agents.*directory' "$WIZARD"; then
        pass "Wizard has .claude/agents/ guidance"
    else
        fail "Wizard missing .claude/agents/ guidance"
    fi
}

# Test: SDLC skill mentions agents as optional enhancement
test_skill_agents_mention() {
    if grep -qi '\.claude/agents\|subagent\|custom.*agent' "$SKILL"; then
        pass "SDLC skill mentions agents"
    else
        fail "SDLC skill missing agents mention"
    fi
}

test_wizard_agents_guidance
test_skill_agents_mention

# -------------------------------------------------------------------
# #57 Context Position Audit — critical content in first 30%
# -------------------------------------------------------------------

echo ""
echo "--- #57 Context Position Audit ---"

# Test: "ALL TESTS MUST PASS" appears in first 40% of SKILL.md
test_tests_must_pass_position() {
    local total_lines
    total_lines=$(wc -l < "$SKILL")
    local threshold=$((total_lines * 40 / 100))
    local match_line
    match_line=$(grep -n "ALL TESTS MUST PASS" "$SKILL" | head -1 | cut -d: -f1)
    if [ -n "$match_line" ] && [ "$match_line" -le "$threshold" ]; then
        pass "ALL TESTS MUST PASS in first 40% of SKILL.md (line $match_line of $total_lines, threshold $threshold)"
    else
        fail "ALL TESTS MUST PASS should be in first 40% of SKILL.md (line ${match_line:-missing} of $total_lines, threshold $threshold)"
    fi
}

# Test: Scoring Rubric appears BEFORE Test Failure Recovery
test_rubric_before_test_failure() {
    local rubric_line test_failure_line
    rubric_line=$(grep -n "Scoring Rubric" "$SKILL" | head -1 | cut -d: -f1)
    test_failure_line=$(grep -n "Test Failure Recovery" "$SKILL" | head -1 | cut -d: -f1)
    if [ -n "$rubric_line" ] && [ -n "$test_failure_line" ] && [ "$rubric_line" -lt "$test_failure_line" ]; then
        pass "Scoring Rubric (line $rubric_line) before Test Failure Recovery (line $test_failure_line)"
    else
        fail "Scoring Rubric should appear before Test Failure Recovery"
    fi
}

# Test: Self-Review Loop appears BEFORE CI Feedback Loop
# GH #486: the Self-Review Loop section is deleted from the skill, so an
# ordering assertion about it would pass vacuously forever (both greps empty ->
# the -n guard fails -> permanent fail, or worse, a rewrite that always passes).
# Replaced with an absence assertion: the section must NOT come back to the
# always-loaded skill. The cheap read-back survives as a scored rubric row.
test_self_review_section_absent() {
    if grep -q "^## Self-Review Loop" "$SKILL"; then
        fail "the Self-Review Loop section is back in the always-loaded skill — #486 deleted it as same-model verification; cross-model review carries this"
    else
        pass "#486: no Self-Review Loop section in the skill"
    fi
}

test_tests_must_pass_position
test_rubric_before_test_failure
test_self_review_section_absent

# -------------------------------------------------------------------
# #72+#56 Cross-Model Review Standardization + Adversarial Prompting
# -------------------------------------------------------------------

echo ""
echo "--- #72+#56 Cross-Model Review Standardization ---"

# Test: Handoff schema has mission/success/failure fields
test_handoff_mission_fields() {
    local has_mission has_success has_failure
    # GH #489: handoff schema mechanics moved to the wizard doc — the skill
    # keeps only the two steps whose details are landmines if improvised (#364
    # codex flags, #437 commit_sha). Asserted where the schema now lives.
    has_mission=$(grep -c '"mission"' "$WIZARD") || true
    has_success=$(grep -c '"success"' "$WIZARD") || true
    has_failure=$(grep -c '"failure"' "$WIZARD") || true
    if [ "$has_mission" -gt 0 ] && [ "$has_success" -gt 0 ] && [ "$has_failure" -gt 0 ]; then
        pass "Handoff schema has mission/success/failure fields"
    else
        fail "Wizard doc handoff schema should have mission, success, and failure fields (found: mission=$has_mission, success=$has_success, failure=$has_failure)"
    fi
}

# Test: Review prompt does NOT contain "find at least N" anti-pattern
test_no_find_n_problems() {
    if grep -qi "find at least [0-9]" "$SKILL"; then
        fail "Review prompt should NOT use 'find at least N' pattern (incentivizes false positives)"
    else
        pass "Review prompt does not use 'find at least N' anti-pattern"
    fi
}

# Test: Preflight self-review doc is mentioned
test_preflight_doc_mentioned() {
    if grep -qi "preflight" "$SKILL"; then
        pass "SKILL.md mentions preflight self-review doc"
    else
        fail "SKILL.md should mention preflight self-review doc (proven to reduce findings to 0-1/round)"
    fi
}

# Test: Review prompt includes verification checklist pattern
test_verification_checklist() {
    # Anchored on the literal JSON key, not a loose phrase: the loose pattern
    # matched 4+ unrelated places in a 291KB doc, so deleting the handoff
    # schema would not have failed it. Near-vacuous.
    if grep -q '"verification_checklist"' "$WIZARD"; then
        pass "Review prompt includes verification checklist pattern"
    else
        fail "Review prompt should include verification checklist pattern (not generic 'review this')"
    fi
}

# Test: Domain template guidance exists (code is default, others possible)
test_domain_template_guidance() {
    if grep -qi "domain.*template\|domain.*specific\|non-code.*domain\|code.*default" "$SKILL"; then
        pass "SKILL.md has domain template guidance"
    else
        fail "SKILL.md should note code review as default domain with guidance for other domains"
    fi
}

# Test: Wizard doc cross-model section has mission-first handoff
test_wizard_mission_first() {
    if grep -qi "mission.*success.*failure\|THE MISSION\|mission-first" "$WIZARD"; then
        pass "Wizard doc has mission-first handoff pattern"
    else
        fail "Wizard doc should have mission-first handoff pattern in cross-model review section"
    fi
}

test_handoff_mission_fields
test_no_find_n_problems
test_preflight_doc_mentioned
test_verification_checklist
test_domain_template_guidance
test_wizard_mission_first

# -------------------------------------------------------------------
# #73 Release Planning Gate (section in SDLC skill)
# -------------------------------------------------------------------

echo ""
echo "--- #73 Release Planning Gate ---"

# Test: SKILL.md has Release Planning section
test_release_planning_section() {
    if grep -qi "Release Planning" "$SKILL"; then
        pass "SKILL.md has Release Planning section"
    else
        fail "SKILL.md should have Release Planning section"
    fi
}

# Test: Release planning mentions 95% confidence for all items
test_release_planning_confidence() {
    # Use multiline approach: check that both concepts exist in the file
    local has_release has_confidence
    has_release=$(grep -ci "release.*plan\|plan.*release" "$SKILL") || true
    has_confidence=$(grep -c "95%" "$SKILL") || true
    if [ "$has_release" -gt 0 ] && [ "$has_confidence" -gt 0 ]; then
        pass "Release planning references 95% confidence threshold"
    else
        fail "Release planning should reference 95% confidence for all items"
    fi
}

# Test: Prove It Gate includes skill absorption check
test_prove_it_absorption() {
    if grep -qi "absorb\|existing skill\|existing.*component" "$SKILL" && grep -qi "prove it\|new.*skill\|new.*addition" "$SKILL"; then
        pass "Prove It Gate includes absorption check"
    else
        fail "Prove It Gate should check if new addition can be absorbed into existing skill"
    fi
}

test_release_planning_section
test_release_planning_confidence
test_prove_it_absorption

# -------------------------------------------------------------------
# #65 Testing Diamond Boundary Clarification
# -------------------------------------------------------------------

echo ""
echo "--- #65 Testing Diamond Boundary ---"

# Test: Wizard doc draws explicit E2E vs Integration boundary
test_diamond_boundary_wizard() {
    if grep -qi "E2E.*UI\|E2E.*browser\|through.*UI\|through.*browser" "$WIZARD" && grep -qi "Integration.*API\|Integration.*without.*UI\|without.*UI" "$WIZARD"; then
        pass "Wizard doc draws explicit E2E (UI/browser) vs Integration (API/no UI) boundary"
    else
        fail "Wizard doc should explicitly define: E2E = through UI/browser, Integration = real systems via API without UI"
    fi
}

# Test: SKILL.md mentions the boundary
test_diamond_boundary_skill() {
    if grep -qi "E2E.*UI\|E2E.*browser\|through.*UI" "$SKILL" && grep -qi "Integration.*API\|without.*UI" "$SKILL"; then
        pass "SKILL.md draws E2E vs Integration boundary"
    else
        fail "SKILL.md should draw explicit E2E vs Integration boundary"
    fi
}

test_diamond_boundary_wizard
test_diamond_boundary_skill

# -------------------------------------------------------------------
# #69 Skill Frontmatter Improvements
# -------------------------------------------------------------------

echo ""
echo "--- #69 Skill Frontmatter ---"

# Test: Wizard doc documents skill frontmatter fields (paths, context, effort)
test_frontmatter_docs() {
    local has_paths has_context has_effort
    has_paths=$(grep -c "paths:" "$WIZARD") || true
    has_context=$(grep -c "context:.*fork\|context: fork" "$WIZARD") || true
    has_effort=$(grep -c "effort:" "$WIZARD") || true
    if [ "$has_paths" -gt 0 ] && [ "$has_context" -gt 0 ] && [ "$has_effort" -gt 0 ]; then
        pass "Wizard doc documents skill frontmatter (paths, context, effort)"
    else
        fail "Wizard doc should document skill frontmatter fields: paths ($has_paths), context:fork ($has_context), effort ($has_effort)"
    fi
}

# Test: All distributed skills have effort: frontmatter, except sdlc which
# deliberately omits it (v1.84.0: effort is model-aware, see AI_SETUP_LANES.md,
# not a fixed value the skill can hardcode)
test_skills_have_effort() {
    local missing=""
    for skill_dir in skills/*/; do
        local skill_file="$skill_dir/SKILL.md"
        if [ "$(basename "$skill_dir")" = "sdlc" ]; then
            continue
        fi
        if [ -f "$skill_file" ]; then
            if ! grep -q "^effort:" "$skill_file"; then
                missing="${missing:+${missing}, }$(basename "$skill_dir")"
            fi
        fi
    done
    if [ -z "$missing" ]; then
        pass "All distributed skills (except model-aware sdlc) have effort: frontmatter"
    else
        fail "Skills missing effort: frontmatter: $missing"
    fi
}

test_frontmatter_docs
test_skills_have_effort

# -------------------------------------------------------------------
# #70 --bare Incompatibility Documentation
# -------------------------------------------------------------------

echo ""
echo "--- #70 --bare Docs ---"

# Test: Wizard doc mentions --bare bypass
test_bare_docs_wizard() {
    if grep -q "\-\-bare" "$WIZARD"; then
        pass "Wizard doc documents --bare mode"
    else
        fail "Wizard doc should document that --bare bypasses all hooks/skills/plugins"
    fi
}

# Test: SKILL.md mentions --bare
test_bare_docs_skill() {
    if grep -q "\-\-bare" "$SKILL"; then
        pass "SKILL.md mentions --bare"
    else
        fail "SKILL.md should mention --bare as a complete wizard bypass"
    fi
}

test_bare_docs_wizard
test_bare_docs_skill

# -------------------------------------------------------------------
# CI Shepherd Enforcement Gate
# -------------------------------------------------------------------

echo ""
echo "--- CI Shepherd Enforcement ---"

# Test: SKILL.md has a hard NEVER AUTO-MERGE enforcement block
test_never_auto_merge_gate() {
    if grep -qi "NEVER AUTO-MERGE\|NEVER.*auto.merge\|auto.merge.*NEVER" "$SKILL"; then
        pass "SKILL.md has NEVER AUTO-MERGE enforcement gate"
    else
        fail "SKILL.md should have a hard NEVER AUTO-MERGE enforcement block in CI Shepherd section"
    fi
}

# Test: CI shepherd section requires reading review comments before merge
test_shepherd_requires_review_read() {
    if grep -qi "read.*review.*comment\|read.*CI.*review\|gh api.*pulls.*comments" "$SKILL" && grep -qi "merge.*explicit\|explicit.*merge\|gh pr merge --squash" "$SKILL"; then
        pass "CI shepherd requires reading review + explicit merge"
    else
        fail "CI shepherd should require reading review comments and explicit merge (no auto-merge)"
    fi
}

test_never_auto_merge_gate
test_shepherd_requires_review_read

# Test: `gh pr merge --auto` (GitHub's own auto-merge-on-green feature) stays
# permanently, unconditionally banned — this is the exact PR #145 incident
# (auto-merge fired before any review was read). The new conditional-merge
# exception (2026-07-21) applies only to the assistant's own explicit
# `gh pr merge --squash` step, never to this GitHub-native mechanism.
test_gh_pr_merge_auto_stays_unconditionally_banned() {
    if grep -qF '`gh pr merge --auto`' "$SKILL"; then
        pass "SKILL.md still explicitly names gh pr merge --auto as banned"
    else
        fail "SKILL.md should still explicitly name gh pr merge --auto as banned"
    fi
}

# Shared check functions for CI Feedback Loop section content, reused below
# against both the real SKILL.md (positive assertions) and synthetic
# negative-control fixtures (so we prove these checks have real selectivity,
# not just "some keyword is present anywhere" laxity — Codex's review of the
# original versions of these tests demonstrated they'd pass on text saying
# "release PRs qualify" or "do not tell the user", i.e. plausible-sounding
# negations of the intended rule). Grep-based checks can't be made fully
# adversarial-negation-proof (that would need real NLP), but they CAN be
# made to reliably catch the realistic failure mode this repo has actually
# hit before: a section silently truncated or drifted to omit a requirement.
section_requires_both_reviewers() {
    local text="$1"
    echo "$text" | grep -qi "CERTIFIED" \
        && echo "$text" | grep -qi "fresh Fable subagent" \
        && echo "$text" | grep -qi "zero unresolved findings" \
        && echo "$text" | grep -qi "dialogue round"
}

section_requires_ci_green_and_excludes_denylist() {
    local text="$1"
    echo "$text" | grep -qi "validate.*green\|validate.*check.*green" \
        && echo "$text" | grep -qi "workflows" \
        && echo "$text" | grep -qi "hooks" \
        && echo "$text" | grep -qi "\.claude"
}

section_requires_post_hoc_transparency() {
    local text="$1"
    echo "$text" | grep -qiE "tell the user|inform the user|report.*(merged|what was merged)" \
        && echo "$text" | grep -qi "never silent\|not.*silent.*merge"
}

# Test: the conditional exception requires Codex CERTIFIED (full dialogue, not
# a round-1 rubber stamp) AND a FRESH Fable subagent given only the diff
# reporting zero unresolved findings after a real dialogue round — not a
# leading "are you 95% confident?" self-report (Fable's own review of this
# policy flagged that framing as a weak, easily-hand-waved gate).
test_conditional_merge_requires_both_reviewers() {
    local shepherd_section
    shepherd_section=$(awk '/## CI Feedback Loop/{f=1} /^## /{if(f && !/CI Feedback Loop/) exit} f' "$SKILL")
    if section_requires_both_reviewers "$shepherd_section"; then
        pass "conditional-merge exception requires Codex CERTIFIED + fresh-Fable zero-findings dialogue round"
    else
        fail "conditional-merge exception text is missing one of: CERTIFIED, fresh Fable subagent, zero unresolved findings, or dialogue round"
    fi
}

# Test: negative control — prose that omits the reviewer requirements
# entirely must NOT satisfy the check above (proves the check isn't
# vacuously true regardless of content).
test_conditional_merge_reviewer_check_rejects_missing_conditions() {
    local fixture="## CI Feedback Loop
An agent may merge without asking anyone, no review needed at all.
## Next Section"
    if section_requires_both_reviewers "$fixture"; then
        fail "reviewer-requirement check should NOT be satisfied by prose lacking CERTIFIED/Fable/dialogue-round language"
    else
        pass "reviewer-requirement check correctly rejects prose missing all required conditions"
    fi
}

# Test: the conditional exception also requires CI 'validate' green and
# excludes a concrete denylist of policy/release-adjacent paths (workflows,
# hooks, .claude/) — tightened from a loose "release\|tag-adjacent\|npm
# publish" OR-of-generic-words (which Codex demonstrated would pass on text
# saying "release PRs qualify," i.e. the inverted rule) to require the actual
# denylist categories the mechanism enforces.
test_conditional_merge_requires_ci_green_and_excludes_releases() {
    local shepherd_section
    shepherd_section=$(awk '/## CI Feedback Loop/{f=1} /^## /{if(f && !/CI Feedback Loop/) exit} f' "$SKILL")
    if section_requires_ci_green_and_excludes_denylist "$shepherd_section"; then
        pass "conditional-merge exception requires CI validate green and names the concrete policy/release-adjacent denylist"
    else
        fail "conditional-merge exception is missing a CI-green requirement or the concrete denylist categories"
    fi
}

# Test: negative control for the denylist check.
test_conditional_merge_denylist_check_rejects_vague_release_only() {
    local fixture="## CI Feedback Loop
CI validate is green. Release PRs qualify for this exception too.
## Next Section"
    if section_requires_ci_green_and_excludes_denylist "$fixture"; then
        fail "denylist check should NOT be satisfied by a vague 'release PRs qualify' fixture lacking the concrete categories"
    else
        pass "denylist check correctly rejects vague release-only prose lacking workflows/hooks/.claude categories"
    fi
}

# Test: even under the conditional exception, the assistant must tell the user
# what was merged and why immediately afterward — no silent merges.
test_conditional_merge_requires_post_hoc_transparency() {
    local shepherd_section
    shepherd_section=$(awk '/## CI Feedback Loop/{f=1} /^## /{if(f && !/CI Feedback Loop/) exit} f' "$SKILL")
    if section_requires_post_hoc_transparency "$shepherd_section"; then
        pass "conditional-merge exception requires telling the user afterward, not silent merging"
    else
        fail "conditional-merge exception should require informing the user after an unconfirmed merge"
    fi
}

# Test: negative control — a fixture that only says "do not tell the user"
# contains the substring "tell the user" but must still fail the check once
# the "never silent" companion requirement is added.
test_conditional_merge_transparency_check_rejects_negation() {
    local fixture="## CI Feedback Loop
The agent should not tell the user anything, merges can be silent.
## Next Section"
    if section_requires_post_hoc_transparency "$fixture"; then
        fail "transparency check should NOT be satisfied by a fixture explicitly permitting silent merges"
    else
        pass "transparency check correctly rejects a fixture that permits silent merges"
    fi
}

test_gh_pr_merge_auto_stays_unconditionally_banned
test_conditional_merge_requires_both_reviewers
test_conditional_merge_reviewer_check_rejects_missing_conditions
test_conditional_merge_requires_ci_green_and_excludes_releases
test_conditional_merge_denylist_check_rejects_vague_release_only
test_conditional_merge_requires_post_hoc_transparency
test_conditional_merge_transparency_check_rejects_negation

# -------------------------------------------------------------------
# Post-Mortem Pattern
# -------------------------------------------------------------------

echo ""
echo "--- Post-Mortem Pattern ---"

# Test: SKILL.md has a post-mortem section
test_postmortem_section() {
    if grep -qi "post.mortem\|Post-Mortem" "$SKILL"; then
        pass "SKILL.md has post-mortem pattern"
    else
        fail "SKILL.md should have a post-mortem section for feeding process failures back into the process"
    fi
}

# Test: Post-mortem feeds back into process (every mistake becomes a rule)
test_postmortem_feedback_loop() {
    if grep -qi "mistake.*rule\|failure.*enforcement\|incident.*add.*gate\|feed.*back.*process" "$SKILL"; then
        pass "Post-mortem feeds failures back into process enforcement"
    else
        fail "Post-mortem should describe how process failures become enforcement rules"
    fi
}

test_postmortem_section
test_postmortem_feedback_loop

# -------------------------------------------------------------------
# Plan Lifecycle Cleanup
# -------------------------------------------------------------------

test_plan_cleanup_in_checklist() {
    if grep -qi "close.*plan\|plan.*complete\|plan.*delete" "$SKILL"; then
        pass "SKILL.md checklist has plan file cleanup step"
    else
        fail "SKILL.md should have a plan cleanup step — stale plans mislead future sessions"
    fi
}

test_plan_cleanup_in_wizard() {
    if grep -qi "plan.*closed\|plan.*deleted\|plan.*complete\|plan.*misled" "$WIZARD"; then
        pass "Wizard doc mentions plan file cleanup in staleness prevention"
    else
        fail "Wizard doc should mention plan file cleanup alongside doc staleness prevention"
    fi
}

test_plan_cleanup_in_checklist
test_plan_cleanup_in_wizard

# -------------------------------------------------------------------
# Hook Auto-Invoke Triggers
# -------------------------------------------------------------------

HOOK="hooks/sdlc-prompt-check.sh"

test_hook_triggers_on_release() {
    if grep -qi "release.*publish\|publish.*deploy\|release/publish/deploy" "$HOOK"; then
        pass "Hook auto-invokes SDLC for release/publish/deploy tasks"
    else
        fail "Hook should trigger SDLC for release/publish/deploy — missed release review on v1.23.0 publish"
    fi
}

test_hook_triggers_on_release

# -------------------------------------------------------------------
# CC Version Check in Notification Hook
# -------------------------------------------------------------------

echo ""
echo "--- CC version check in notification hook ---"

INSTRUCTIONS_HOOK="$SCRIPT_DIR/../hooks/instructions-loaded-check.sh"

# Test: Hook checks CC version (claude --version) not just wizard version
test_hook_checks_cc_version() {
    if grep -q "claude --version\|claude-code.*version\|@anthropic-ai/claude-code" "$INSTRUCTIONS_HOOK"; then
        pass "instructions-loaded-check.sh checks Claude Code version"
    else
        fail "instructions-loaded-check.sh should check Claude Code version — we were 9 versions behind (2.1.81 vs 2.1.90) with no notification"
    fi
}

# Test: CC version check is non-blocking (exits 0 even if check fails)
test_cc_version_check_nonblocking() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.23.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    # Fake claude that reports old version
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nif [ "$1" = "--version" ]; then echo "2.1.81 (Claude Code)"; else echo "1.23.0"; fi\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nif [ "$1" = "view" ] && echo "$@" | grep -q "claude-code"; then echo "2.1.90"; elif [ "$1" = "view" ]; then echo "1.23.0"; fi\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/claude" "$tmpdir/bin/npm"
    local exit_code
    (cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" "$INSTRUCTIONS_HOOK") > /dev/null 2>&1
    exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ]; then
        pass "CC version check is non-blocking (exits 0)"
    else
        fail "CC version check should not block session start, got exit code: $exit_code"
    fi
}

# Test: Shows CC update notification when behind
test_cc_version_shows_update() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.23.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nif [ "$1" = "--version" ]; then echo "2.1.81 (Claude Code)"; else echo "1.23.0"; fi\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nif [ "$1" = "view" ] && echo "$@" | grep -q "claude-code"; then echo "2.1.90"; elif [ "$1" = "view" ]; then echo "1.23.0"; fi\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/claude" "$tmpdir/bin/npm"
    local output
    # #236(b): isolate the cache dir — without this, a fresh real
    # ~/.cache/sdlc-wizard/latest-cc-version from actual hook usage on this
    # machine short-circuits the npm stub and this test sees the real cached
    # version instead of "2.1.90".
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$INSTRUCTIONS_HOOK" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "Claude Code update" && echo "$output" | grep -q "2.1.81" && echo "$output" | grep -q "2.1.90"; then
        pass "Shows CC update notification with version numbers"
    else
        fail "Should show CC update notification with both versions, got: $output"
    fi
}

# Test: No CC notification when versions match
test_cc_version_no_notification_when_current() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.23.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nif [ "$1" = "--version" ]; then echo "2.1.90 (Claude Code)"; else echo "1.23.0"; fi\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nif [ "$1" = "view" ] && echo "$@" | grep -q "claude-code"; then echo "2.1.90"; elif [ "$1" = "view" ]; then echo "1.23.0"; fi\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/claude" "$tmpdir/bin/npm"
    local output
    # #236(b): isolate the cache dir, same reason as the test above.
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$INSTRUCTIONS_HOOK" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "Claude Code update"; then
        fail "Should NOT show CC update notification when versions match, got: $output"
    else
        pass "No CC update notification when versions match"
    fi
}

test_hook_checks_cc_version
test_cc_version_check_nonblocking
test_cc_version_shows_update
test_cc_version_no_notification_when_current

# -------------------------------------------------------------------
# Cross-Model Review Staleness Check
# -------------------------------------------------------------------

echo ""
echo "--- Cross-model review staleness check ---"

# Test: Hook source contains review staleness check logic
test_hook_has_review_staleness_check() {
    if grep -q "reviews.*stale\|latest-review\|cross-model.*review\|REVIEW_MTIME\|review.*staleness" "$INSTRUCTIONS_HOOK"; then
        pass "instructions-loaded-check.sh has cross-model review staleness check"
    else
        fail "instructions-loaded-check.sh should check for stale cross-model reviews — v1.23.0 shipped without review and nobody was warned"
    fi
}

# Test: Warns when many commits since last review
test_review_staleness_warns_when_stale() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.23.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    # Create .reviews/ with an old latest-review.md
    mkdir -p "$tmpdir/.reviews"
    echo "CERTIFIED" > "$tmpdir/.reviews/latest-review.md"
    # Touch the file to be 5 days old (432000 seconds)
    touch -t "$(date -v-5d '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '5 days ago' '+%Y%m%d%H%M.%S' 2>/dev/null)" "$tmpdir/.reviews/latest-review.md" 2>/dev/null || true
    # Create a fake git repo with commits after the review
    git -C "$tmpdir" init -q 2>/dev/null
    git -C "$tmpdir" config user.email "test@test.com" 2>/dev/null
    git -C "$tmpdir" config user.name "Test" 2>/dev/null
    git -C "$tmpdir" add -A 2>/dev/null
    git -C "$tmpdir" commit -q -m "initial" 2>/dev/null
    for i in 1 2 3 4 5 6; do
        echo "change $i" >> "$tmpdir/SDLC.md"
        git -C "$tmpdir" add -A 2>/dev/null
        git -C "$tmpdir" commit -q -m "commit $i" 2>/dev/null
    done
    # Fake npm and claude so other checks don't interfere
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nif echo "$@" | grep -q "claude-code"; then echo "2.1.90"; else echo "1.23.0"; fi\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\necho "2.1.90 (Claude Code)"\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\necho "codex-cli 0.118.0"\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" "$INSTRUCTIONS_HOOK" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qi "review\|stale\|cross-model"; then
        pass "Warns when cross-model reviews are stale (many commits since last review)"
    else
        fail "Should warn about stale cross-model reviews, got: $output"
    fi
}

# Test: Silent when review is recent
test_review_staleness_silent_when_recent() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.23.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/.reviews"
    echo "CERTIFIED" > "$tmpdir/.reviews/latest-review.md"
    # Recent review — touch to now
    touch "$tmpdir/.reviews/latest-review.md"
    # Create git repo with only 1 commit after review
    git -C "$tmpdir" init -q 2>/dev/null
    git -C "$tmpdir" config user.email "test@test.com" 2>/dev/null
    git -C "$tmpdir" config user.name "Test" 2>/dev/null
    git -C "$tmpdir" add -A 2>/dev/null
    git -C "$tmpdir" commit -q -m "initial" 2>/dev/null
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nif echo "$@" | grep -q "claude-code"; then echo "2.1.90"; else echo "1.23.0"; fi\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\necho "2.1.90 (Claude Code)"\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\necho "codex-cli 0.118.0"\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" "$INSTRUCTIONS_HOOK" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qi "review\|stale\|cross-model"; then
        fail "Should NOT warn when cross-model review is recent, got: $output"
    else
        pass "Silent when cross-model review is recent"
    fi
}

# Test: Silent when no .reviews/ directory (reviews not configured)
test_review_staleness_silent_no_reviews_dir() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.23.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    # No .reviews/ directory
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nif echo "$@" | grep -q "claude-code"; then echo "2.1.90"; else echo "1.23.0"; fi\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\necho "2.1.90 (Claude Code)"\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\necho "codex-cli 0.118.0"\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" "$INSTRUCTIONS_HOOK" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qi "review\|stale\|cross-model"; then
        fail "Should NOT warn when .reviews/ doesn't exist (not configured), got: $output"
    else
        pass "Silent when .reviews/ directory doesn't exist"
    fi
}

# Test: Silent when codex not installed
test_review_staleness_silent_no_codex() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.23.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/.reviews"
    echo "CERTIFIED" > "$tmpdir/.reviews/latest-review.md"
    touch -t "$(date -v-10d '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 days ago' '+%Y%m%d%H%M.%S' 2>/dev/null)" "$tmpdir/.reviews/latest-review.md" 2>/dev/null || true
    # Empty bin — no codex, no npm, no claude
    mkdir -p "$tmpdir/bin"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin" CLAUDE_PROJECT_DIR="$tmpdir" "$INSTRUCTIONS_HOOK" 2>/dev/null)
    local exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ] && ! echo "$output" | grep -qi "review\|stale\|cross-model"; then
        pass "Silent and exit 0 when codex not installed (even with stale reviews)"
    else
        fail "Should be silent when codex not installed, exit=$exit_code, got: $output"
    fi
}

# Test: Staleness check is non-blocking (exit 0)
test_review_staleness_nonblocking() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.23.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/.reviews"
    echo "CERTIFIED" > "$tmpdir/.reviews/latest-review.md"
    touch -t "$(date -v-10d '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 days ago' '+%Y%m%d%H%M.%S' 2>/dev/null)" "$tmpdir/.reviews/latest-review.md" 2>/dev/null || true
    git -C "$tmpdir" init -q 2>/dev/null
    git -C "$tmpdir" config user.email "test@test.com" 2>/dev/null
    git -C "$tmpdir" config user.name "Test" 2>/dev/null
    git -C "$tmpdir" add -A 2>/dev/null
    git -C "$tmpdir" commit -q -m "initial" 2>/dev/null
    for i in 1 2 3 4 5 6 7 8 9 10; do
        echo "change $i" >> "$tmpdir/SDLC.md"
        git -C "$tmpdir" add -A 2>/dev/null
        git -C "$tmpdir" commit -q -m "commit $i" 2>/dev/null
    done
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nif echo "$@" | grep -q "claude-code"; then echo "2.1.90"; else echo "1.23.0"; fi\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\necho "2.1.90 (Claude Code)"\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\necho "codex-cli 0.118.0"\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    local exit_code
    (cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" "$INSTRUCTIONS_HOOK") > /dev/null 2>&1
    exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ]; then
        pass "Review staleness check is non-blocking (exit 0)"
    else
        fail "Review staleness check should not block session start, got exit code: $exit_code"
    fi
}

test_hook_has_review_staleness_check
test_review_staleness_warns_when_stale
test_review_staleness_silent_when_recent
test_review_staleness_silent_no_reviews_dir
test_review_staleness_silent_no_codex
test_review_staleness_nonblocking

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All self-update mechanism tests passed!"
