#!/bin/bash
# Test cross-document consistency: hardcoded counts must match filesystem reality
# Roadmap #102: docs drift silently when counts are hardcoded
#
# Philosophy: targeted checks for known-drifting claims, NOT generic
# "grep all numbers" which would be too noisy and brittle.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

# Strip fenced code blocks from a file before grepping for claims.
# Prevents false positives from example code like: "run 2 workflows"
strip_code_blocks() {
    sed '/^```/,/^```/d' "$1"
}

echo "=== Cross-Document Consistency Tests ==="
echo ""

# ────────────────────────────────────────────
# Workflow Count Consistency
# ────────────────────────────────────────────

echo "--- Workflow Count ---"

ACTUAL_WORKFLOWS=$(ls "$REPO_ROOT"/.github/workflows/*.yml 2>/dev/null | wc -l | tr -d ' ')

# Test 1: README should NOT hardcode workflow count (use count-free language)
test_readme_no_hardcoded_workflow_count() {
    local README="$REPO_ROOT/README.md"
    if [ ! -f "$README" ]; then fail "README.md not found"; return; fi
    # Should say "All workflows" not "All 7 workflows" or "7 workflows"
    # Strip code blocks to avoid false positives from examples
    if strip_code_blocks "$README" | grep -qE '\b[0-9]+\s+workflows?\b'; then
        local found
        found=$(strip_code_blocks "$README" | grep -oE '\b[0-9]+\s+workflows?\b' | head -1)
        fail "README.md hardcodes workflow count: '$found' (should use count-free language)"
    else
        pass "README.md does not hardcode workflow count"
    fi
}

# Test 2: No doc outside CHANGELOG/ROADMAP/plans claims wrong workflow count
test_no_stale_workflow_count() {
    local stale=""
    # Search for "N workflows" in active docs (not historical)
    for doc in "$REPO_ROOT"/README.md "$REPO_ROOT"/CI_CD.md "$REPO_ROOT"/ARCHITECTURE.md \
               "$REPO_ROOT"/CONTRIBUTING.md "$REPO_ROOT"/COMPETITIVE_AUDIT.md \
               "$REPO_ROOT"/CODE_REVIEW_EXCEPTIONS.md "$REPO_ROOT"/SDLC.md; do
        [ ! -f "$doc" ] && continue
        local basename
        basename=$(basename "$doc")
        # Find lines claiming N workflows where N is wrong (exclude code blocks)
        while IFS= read -r line; do
            local claimed
            claimed=$(echo "$line" | grep -oE '\b[0-9]+\s+workflows?\b' | head -1 | grep -oE '[0-9]+')
            if [ -n "$claimed" ] && [ "$claimed" != "$ACTUAL_WORKFLOWS" ]; then
                stale="$stale\n  $basename: claims $claimed workflows (actual: $ACTUAL_WORKFLOWS)"
            fi
        done < <(strip_code_blocks "$doc" | grep -nE '\b[0-9]+\s+workflows?\b' 2>/dev/null || true)
    done
    if [ -z "$stale" ]; then
        pass "No stale workflow counts in active docs (actual: $ACTUAL_WORKFLOWS)"
    else
        fail "Stale workflow counts found:$stale"
    fi
}

test_readme_no_hardcoded_workflow_count
test_no_stale_workflow_count

# ────────────────────────────────────────────
# CLI File Count Consistency
# ────────────────────────────────────────────

echo ""
echo "--- CLI File Count ---"

# Count FILES entries in init.js (the source of truth)
# The full install output = FILES array entries + the wizard doc (CLAUDE_CODE_SDLC_WIZARD.md)
INIT_JS="$REPO_ROOT/cli/init.js"
FILES_COUNT=$(grep -c "src:.*dest:" "$INIT_JS" 2>/dev/null || echo "0")
# init.js also copies WIZARD_DOC (CLAUDE_CODE_SDLC_WIZARD.md) separately
ACTUAL_CLI_FILES=$((FILES_COUNT + 1))

# Test 3: CI_CD.md file count claims match init.js
test_ci_cd_file_count() {
    local CI_CD="$REPO_ROOT/CI_CD.md"
    if [ ! -f "$CI_CD" ]; then fail "CI_CD.md not found"; return; fi
    # Look for "N files created" or "all N files" in install verification context
    local stale=""
    while IFS= read -r line; do
        local claimed
        claimed=$(echo "$line" | grep -oE '\b[0-9]+\s+files?\b' | head -1 | grep -oE '[0-9]+')
        if [ -n "$claimed" ] && [ "$claimed" != "$ACTUAL_CLI_FILES" ]; then
            stale="$stale\n  claims $claimed files (actual: $ACTUAL_CLI_FILES)"
        fi
    done < <(strip_code_blocks "$CI_CD" | grep -nE '\b[0-9]+\s+files?\s*(created|simulates)' 2>/dev/null || true)
    # Also check "all N files"
    while IFS= read -r line; do
        local claimed
        claimed=$(echo "$line" | grep -oE 'all\s+[0-9]+\s+files' | grep -oE '[0-9]+')
        if [ -n "$claimed" ] && [ "$claimed" != "$ACTUAL_CLI_FILES" ]; then
            stale="$stale\n  claims 'all $claimed files' (actual: $ACTUAL_CLI_FILES)"
        fi
    done < <(strip_code_blocks "$CI_CD" | grep -niE 'all\s+[0-9]+\s+files' 2>/dev/null || true)
    if [ -z "$stale" ]; then
        pass "CI_CD.md CLI file counts match init.js ($ACTUAL_CLI_FILES files)"
    else
        fail "CI_CD.md stale CLI file counts:$stale"
    fi
}

# Test 4: CI_CD.md should prefer count-free language for CLI install verification
test_ci_cd_no_hardcoded_file_count() {
    local CI_CD="$REPO_ROOT/CI_CD.md"
    if [ ! -f "$CI_CD" ]; then fail "CI_CD.md not found"; return; fi
    if strip_code_blocks "$CI_CD" | grep -qE '\b[0-9]+\s+files\s+created\b' || strip_code_blocks "$CI_CD" | grep -qiE 'all\s+[0-9]+\s+files'; then
        fail "CI_CD.md hardcodes CLI file count (should use count-free language like 'all CLI files')"
    else
        pass "CI_CD.md uses count-free language for CLI files"
    fi
}

test_ci_cd_file_count
test_ci_cd_no_hardcoded_file_count

# ────────────────────────────────────────────
# Skill Count Consistency
# ────────────────────────────────────────────

echo ""
echo "--- Skill Count ---"

# Skills live at repo root skills/ (symlinked into .claude/skills/)
ACTUAL_SKILLS=$(ls "$REPO_ROOT"/skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')

# Test 5: COMPETITIVE_AUDIT.md skill count matches actual
test_competitive_audit_skill_count() {
    local AUDIT="$REPO_ROOT/COMPETITIVE_AUDIT.md"
    if [ ! -f "$AUDIT" ]; then fail "COMPETITIVE_AUDIT.md not found"; return; fi
    # Look for "N skills" in our column (not competitor column like "80+ skills")
    # The pattern is "| N skills" in a table row about us
    local our_claim
    our_claim=$(grep -i 'skill library' "$AUDIT" | grep -oE '\|\s*[0-9]+\s+skills' | tail -1 | grep -oE '[0-9]+' || echo "")
    if [ -z "$our_claim" ]; then
        pass "COMPETITIVE_AUDIT.md does not hardcode our skill count"
    elif [ "$our_claim" = "$ACTUAL_SKILLS" ]; then
        pass "COMPETITIVE_AUDIT.md skill count correct ($our_claim = $ACTUAL_SKILLS)"
    else
        fail "COMPETITIVE_AUDIT.md claims $our_claim skills (actual: $ACTUAL_SKILLS)"
    fi
}

test_competitive_audit_skill_count

# ────────────────────────────────────────────
# Scenario Count Consistency
# ────────────────────────────────────────────

echo ""
echo "--- Scenario Count ---"

ACTUAL_SCENARIOS=$(ls "$REPO_ROOT"/tests/e2e/scenarios/*.md 2>/dev/null | wc -l | tr -d ' ')

# Test 6: No doc outside CHANGELOG/ROADMAP claims wrong scenario count
test_no_stale_scenario_count() {
    local stale=""
    for doc in "$REPO_ROOT"/README.md "$REPO_ROOT"/CI_CD.md "$REPO_ROOT"/TESTING.md \
               "$REPO_ROOT"/CONTRIBUTING.md "$REPO_ROOT"/COMPETITIVE_AUDIT.md; do
        [ ! -f "$doc" ] && continue
        local basename
        basename=$(basename "$doc")
        while IFS= read -r line; do
            local claimed
            claimed=$(echo "$line" | grep -oE '\b[0-9]+\s+scenarios\b' | head -1 | grep -oE '[0-9]+')
            if [ -n "$claimed" ] && [ "$claimed" != "$ACTUAL_SCENARIOS" ]; then
                stale="$stale\n  $basename: claims $claimed scenarios (actual: $ACTUAL_SCENARIOS)"
            fi
        done < <(strip_code_blocks "$doc" | grep -nE '\b[0-9]+\s+scenarios\b' 2>/dev/null || true)
    done
    if [ -z "$stale" ]; then
        pass "No stale scenario counts in active docs (actual: $ACTUAL_SCENARIOS)"
    else
        fail "Stale scenario counts found:$stale"
    fi
}

test_no_stale_scenario_count

# ────────────────────────────────────────────
# CODE_REVIEW_EXCEPTIONS Consistency
# ────────────────────────────────────────────

echo ""
echo "--- Code Review Exceptions ---"

# Test 7: CODE_REVIEW_EXCEPTIONS.md should not hardcode workflow count
test_code_review_exceptions_no_hardcoded_count() {
    local EXCEPTIONS="$REPO_ROOT/CODE_REVIEW_EXCEPTIONS.md"
    if [ ! -f "$EXCEPTIONS" ]; then pass "CODE_REVIEW_EXCEPTIONS.md not found (OK)"; return; fi
    if strip_code_blocks "$EXCEPTIONS" | grep -qE '\b[0-9]+\s+workflows?\b'; then
        local found
        found=$(strip_code_blocks "$EXCEPTIONS" | grep -oE '\b[0-9]+\s+workflows?\b' | head -1)
        fail "CODE_REVIEW_EXCEPTIONS.md hardcodes workflow count: '$found'"
    else
        pass "CODE_REVIEW_EXCEPTIONS.md does not hardcode workflow count"
    fi
}

test_code_review_exceptions_no_hardcoded_count

# ────────────────────────────────────────────
# Cross-Check: init.js FILES vs filesystem
# ────────────────────────────────────────────

echo ""
echo "--- Init.js Source-of-Truth ---"

# Test 8: Every file in init.js FILES actually exists
test_init_js_files_exist() {
    if [ ! -f "$INIT_JS" ]; then fail "cli/init.js not found"; return; fi
    local missing=""
    # Extract src paths from FILES array (lines with both src: and dest:)
    while IFS= read -r src_path; do
        # Check both REPO_ROOT and TEMPLATES_DIR locations
        if [ ! -f "$REPO_ROOT/$src_path" ] && [ ! -f "$REPO_ROOT/cli/templates/$src_path" ]; then
            missing="$missing $src_path"
        fi
    done < <(grep "src:.*dest:" "$INIT_JS" | sed "s/.*src: *['\"]//;s/['\"].*//" )
    if [ -z "$missing" ]; then
        pass "All init.js FILES entries exist on disk ($ACTUAL_CLI_FILES files)"
    else
        fail "init.js references missing files:$missing"
    fi
}

test_init_js_files_exist

# Test 9: Every skill in init.js FILES has a matching SKILL.md on disk
test_init_js_skills_match_disk() {
    if [ ! -f "$INIT_JS" ]; then fail "cli/init.js not found"; return; fi
    local init_skills disk_skills
    # Extract skill paths from FILES array (lines with src: and dest:)
    init_skills=$(grep "src:.*dest:" "$INIT_JS" | sed "s/.*src: *['\"]//;s/['\"].*//" | grep 'skills/' | sort)
    # Get skills from disk (repo root skills/, same path format as init.js)
    disk_skills=$(ls "$REPO_ROOT"/skills/*/SKILL.md 2>/dev/null | \
        sed "s|$REPO_ROOT/||" | sort)
    if [ "$init_skills" = "$disk_skills" ]; then
        pass "init.js skill list matches disk ($(echo "$init_skills" | wc -l | tr -d ' ') skills)"
    else
        local only_init only_disk
        only_init=$(comm -23 <(echo "$init_skills") <(echo "$disk_skills"))
        only_disk=$(comm -13 <(echo "$init_skills") <(echo "$disk_skills"))
        fail "init.js skills != disk skills. Only in init.js: [$only_init] Only on disk: [$only_disk]"
    fi
}

test_init_js_skills_match_disk

# ────────────────────────────────────────────
# Scoring Rubric Consistency
# ────────────────────────────────────────────

echo ""
echo "--- Scoring Rubric ---"

# Test 10: README should not hardcode criteria count (it drifts when rubric changes)
test_readme_no_hardcoded_criteria_count() {
    local README="$REPO_ROOT/README.md"
    if [ ! -f "$README" ]; then fail "README.md not found"; return; fi
    if strip_code_blocks "$README" | grep -qE '\b[0-9]+\s+criteria\b'; then
        local found
        found=$(strip_code_blocks "$README" | grep -oE '\b[0-9]+\s+criteria\b' | head -1)
        fail "README.md hardcodes criteria count: '$found' (should use count-free language)"
    else
        pass "README.md does not hardcode criteria count"
    fi
}

test_readme_no_hardcoded_criteria_count

# ────────────────────────────────────────────
# Recommended Model Consistency (opus[1m] — opt-in per issue #198)
# ────────────────────────────────────────────

echo ""
echo "--- Recommended Model (opus[1m], opt-in) ---"

# Wizard recommends opus[1m] for power users but does NOT pin it by default
# (issue #198: a top-level model disables Claude Code auto-mode). These tests
# ensure the recommendation is surfaced in docs for discovery, while the CLI
# template and repo settings leave the pin opt-in via setup Step 9.5.

test_wizard_doc_recommends_opus_1m() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    if grep -qE 'opus\[1m\]' "$DOC"; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md references opus[1m]"
    else
        fail "CLAUDE_CODE_SDLC_WIZARD.md missing opus[1m] recommendation"
    fi
}

# After #198, the wizard doc must frame opus[1m] as opt-in (not "default").
# Guard against regression: someone re-writes the doc to call it the default again.
test_wizard_doc_frames_opus_1m_as_opt_in() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    # Must mention opt-in / auto-mode / #198 somewhere in the 1M section.
    if grep -qiE 'opt.?in.*opus\[1m\]|opus\[1m\].*opt.?in|issue.*198|auto.?mode.*disable|disable.*auto.?mode' "$DOC"; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md frames opus[1m] as opt-in (not silent default)"
    else
        fail "Wizard doc must frame opus[1m] as opt-in + mention auto-mode impact (issue #198)"
    fi
}

# Regression guard (Codex round 1 finding #1): the doc must NOT contain any
# live phrase that calls opus[1m] the SDLC default. The prior test was too
# loose — it only required opt-in language to exist somewhere in the doc,
# so a contradictory "SDLC default (opus[1m])" table row slipped through.
# This test greps for the anti-pattern directly.
test_wizard_doc_no_default_opus_1m_wording() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    # Anti-patterns: assertions that opus[1m] IS the default.
    # - "SDLC default (opus[1m])"  — table cell format
    # - "default (opus[1m])" or "default (`opus[1m]`)"
    # - "opus[1m] as (the/our) default"
    # - "opus[1m] is (the/our) default"
    # - "opus[1m] as default" (no article)
    # Allowed: "default No", "default autocompact", "its default", where
    # "default" refers to something other than opus[1m].
    local hits
    hits=$(grep -nE 'SDLC default[[:space:]]*\(`?opus\[1m\]|default[[:space:]]+\(`?opus\[1m\]`?\)|`?opus\[1m\]`?[[:space:]]+(as|is)([[:space:]]+(the|our|a))?[[:space:]]+default' "$DOC" || true)
    if [ -z "$hits" ]; then
        pass "Wizard doc has no live 'default opus[1m]' phrasing (issue #198)"
    else
        fail "Wizard doc contains contradictory 'default opus[1m]' language: $hits"
    fi
}

test_sdlc_skill_recommends_opus_or_opusplan() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    if grep -qE 'opusplan|claude-opus-4-[0-9]+' "$SKILL"; then
        pass "skills/sdlc/SKILL.md references opusplan or Opus model pin"
    else
        fail "skills/sdlc/SKILL.md missing opusplan or claude-opus-4-X recommendation"
    fi
}

# #236(c): "no default model pin" / "no default env" for
# cli/templates/settings.json were tested identically here and in
# test-cli.sh (which pairs them with follow-on behavioral tests —
# test_fresh_init_does_not_write_model, merge/--force preservation) — kept
# test-cli.sh's, removed the duplicate here.

# Setup skill Step 9.5 must reference an Opus model alias (either the
# `opus[1m]` generic alias or an explicit `claude-opus-4-X[1m]` id) so users
# can discover the pin during the opt-in prompt — just without calling it the
# default. v1.80.0 flipped to explicit model ids for the recommended flagship.
test_setup_skill_mentions_model_pin_in_optin_prompt() {
    local SKILL="$REPO_ROOT/skills/setup/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/setup/SKILL.md not found"; return; fi
    if grep -qE 'opusplan|claude-opus-4-[0-9]+' "$SKILL"; then
        pass "skills/setup/SKILL.md references opusplan or Opus model pin (Step 9.5)"
    else
        fail "skills/setup/SKILL.md must reference opusplan or claude-opus-4-X in Step 9.5"
    fi
}

# Repo's tracked .claude/settings.json must have advisorModel=fable and
# NO model pin (pin = 200K; omitting = 1M default on Max per feedback_model_pin_1m).
test_repo_settings_dogfood_setup_a() {
    local SETTINGS="$REPO_ROOT/.claude/settings.json"
    if [ ! -f "$SETTINGS" ]; then fail ".claude/settings.json not found"; return; fi
    local model advisor
    model=$(jq -r '.model // ""' "$SETTINGS" 2>/dev/null)
    advisor=$(jq -r '.advisorModel // ""' "$SETTINGS" 2>/dev/null)
    if [ "$model" = "" ] && [ "$advisor" = "fable" ]; then
        pass ".claude/settings.json dogfoods Setup A (no model pin + Fable advisor)"
    else
        fail ".claude/settings.json should have no model pin and advisorModel=fable (model=$model advisorModel=$advisor)"
    fi
}

# Hook must recommend a model pin (plain or opusplan — no [1m] since #390).
test_hooks_recommend_model() {
    local H1="$REPO_ROOT/hooks/model-effort-check.sh"
    if [ ! -f "$H1" ]; then fail "$H1 not found"; return; fi
    if ! grep -qE 'RECOMMENDED_MODELS=.*opusplan' "$H1"; then
        fail "model-effort-check.sh should set RECOMMENDED_MODELS including opusplan (#403)"
        return
    fi
    # instructions-loaded-check.sh must NOT re-declare the variable (would
    # reintroduce the #217 duplicate-nudge bug).
    local H2="$REPO_ROOT/hooks/instructions-loaded-check.sh"
    if [ -f "$H2" ] && grep -qE 'RECOMMENDED_MODEL=' "$H2"; then
        fail "instructions-loaded-check.sh declares RECOMMENDED_MODEL — must delegate to model-effort-check.sh per #217"
        return
    fi
    pass "model-effort-check.sh is single source of truth for Opus model recommendation (#217)"
}

# Setup skill must point users at /less-permission-prompts so they can
# auto-tune their allowlist without enabling auto mode. This is a native CC
# skill (ships with the CLI), so we just reference it — we don't reimplement.
test_setup_skill_mentions_less_permission_prompts() {
    local SKILL="$REPO_ROOT/skills/setup/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/setup/SKILL.md not found"; return; fi
    if grep -qF '/less-permission-prompts' "$SKILL"; then
        pass "skills/setup/SKILL.md mentions /less-permission-prompts"
    else
        fail "skills/setup/SKILL.md should recommend /less-permission-prompts post-setup"
    fi
}

# Wizard doc must surface /less-permission-prompts in a Further Reading /
# complementary-tools section so readers know it's native CC, not wizard-owned.
test_wizard_doc_mentions_less_permission_prompts() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    if grep -qF '/less-permission-prompts' "$DOC"; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md mentions /less-permission-prompts"
    else
        fail "CLAUDE_CODE_SDLC_WIZARD.md should reference /less-permission-prompts as a complementary native skill"
    fi
}

# Pin the second row of the "Complementary native skills" table too —
# otherwise a future edit could silently drop /permissions and no test catches it.
test_wizard_doc_mentions_permissions_command() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    if grep -qE '\| `/permissions` \|' "$DOC"; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md pins /permissions row in complementary-skills table"
    else
        fail "CLAUDE_CODE_SDLC_WIZARD.md should keep /permissions in the complementary-skills table"
    fi
}

# Test (#207, RETARGETED by #520): these two assertions used to require the
# words "do not set both" / "pick one". That doctrine is now known to be false,
# so the assertions were enforcing a falsehood — the single worst state for a
# guard to be in, because it actively resists the correction.
#
# What the decompile of v2.1.221 established (evidence on GH #520):
#   - Setting both is MULTIPLICATION, not a misconfiguration. 35% x 1000000 is
#     a 350000 trigger, which is a sane deliberate boundary.
#   - The real trap is a window below 200000, which disables autocompact
#     ENTIRELY (ZJu returns false under bIe = 200000) rather than compacting
#     sooner. "Pick one" never mentioned it, so a consumer following the old
#     advice could turn compaction off while believing they had tuned it.
#
# The property both now assert is the one that is actually true and actually
# protects someone: the sub-200000 disable trap must be named, on the surface
# that reader is holding. Naming the threshold is what makes it actionable —
# prose about "small windows" would not be.
# Does the text ASSERT that something disables compaction? Three attempts got
# here:
#   1. exact retired sentence  — missed "disables autocompact altogether"
#   2. bare pattern            — failed the CORRECT sentence "nothing disables
#                                compaction outright", the mirror of the very
#                                polarity defect this guard exists for
#   3. pattern + negator       — defeated by a DOWNSTREAM negator, because the
#                                exclusion ran on the whole line: "A sub-200000
#                                window disables compaction outright; no later
#                                trigger occurs" excluded itself via the "no".
# So the negator has to be scoped to the CLAUSE carrying the claim, not the
# line. Clauses are split on . ; , and — before the test is applied.
#
# The comma is a splitter for the same reason the semicolon is (round 16): "A
# window under 200000 disables compaction, but no other setting does" put the
# claim and a *different* sentence's negator on one clause, and the "no" in the
# second half excused the first. Splitting on the comma separates them. Once
# commas split, no clause can contain one, so the old `[^,]{0,40}` proximity
# bound is exactly equivalent to `.{0,40}` — the simpler form is kept.
#
# DECLARED BOUND: this is a clause-scoped textual guard, and it is a BACKSTOP
# behind the canonical-sentence pins, not the primary defence. A negator placed
# outside any punctuation this splits on will defeat it. That is accepted: the
# pins already fail if the canonical sentences change, so defeating this guard
# alone does not let a wrong claim through silently. Further grammar defeats are
# classification questions against this bound, not bugs to patch.
#
# `\bdisables?\b` and not `disables?`: the latter matches inside "disabled",
# which caught this document's own past-tense account of the mistake — a guard
# that forbids describing the error it exists to prevent is unusable.
_doc_asserts_disabling() {
    printf '%s' "$1" \
        | sed 's/[.;,]/\n/g; s/ — /\n/g' \
        | grep -iE '\bdisables?\b.{0,40}(autocompact|compaction)' \
        | grep -viqE 'nothing|never|\bno\b|\bnot\b'
}

test_wizard_doc_states_the_sub_200k_window_mechanic() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    # SCOPED to the autocompact section, not the whole document. A whole-file
    # grep for "compound" was satisfied by the prompt-brevity section 600 lines
    # away, so every autocompact multiplication sentence could have been deleted
    # with this assertion still green — the same guard-and-artifact-point-at-
    # different-objects defect as #513. Caught by cross-model review.
    local section
    # Stop at the NEXT heading of any level, not just `### `. An earlier
    # version stopped only at `### `, so it swallowed the "Why opus[1m] is
    # opt-in" bullets below — where "Pinning disables auto-mode" satisfied the
    # disable check on its own.
    # Extract from the RENDERED PROJECTION, not the raw file. Cross-model
    # review defeated the column-1 pins three more times without altering one
    # character of the pinned claims — it wrapped them in an HTML comment, in
    # `<del>`, and in a fence. Each time the constant still began its line and
    # the suite stayed green while the document told the reader nothing.
    # Enumerating containers is unbounded; projecting once is not. The
    # guarantee this assertion makes is now exactly: "in the output of
    # `mdfence.py --rendered`, some line begins with the canonical constant."
    #
    # TWO extractions, on purpose. The PROSE CLAIMS are guidance and must
    # survive the projection — #513 settled that fenced content in this repo is
    # a quotation, not an instruction, so a claim that only exists inside a
    # fence is not guidance no matter how it renders. The FORMULA BLOCK is the
    # opposite: it is deliberately fenced, it is an illustration rather than a
    # claim, and `--rendered` would demand it be un-fenced. So it gets
    # `--visible`, which keeps fenced content but still drops anything hidden.
    # It does NOT get raw bytes: cross-model review wrapped the formula fence
    # in an HTML comment and all 129 assertions stayed green — the same defect
    # as the prose pins had, on the one surface I had exempted.
    local section_vis
    section_vis=$(python3 "$REPO_ROOT/tests/lib/mdfence.py" --visible "$DOC" \
        | awk '/^#### Autocompact mechanics/{f=1;print;next} f && /^#{1,4} /{exit} f')
    section=$(python3 "$REPO_ROOT/tests/lib/mdfence.py" --rendered "$DOC" \
        | awk '/^#### Autocompact mechanics/{f=1;print;next} f && /^#{1,4} /{exit} f')
    if [ -z "$section_vis" ]; then
        fail "#520: the 'Autocompact mechanics' section is gone — this assertion is now vacuous, re-anchor it"
        return
    fi
    if [ -z "$section" ]; then
        fail "#520: the 'Autocompact mechanics' section exists in the file but nothing in it survives the rendered projection — the whole section is commented out, struck, or fenced"
        return
    fi
    local missing=""
    # ANCHOR TO THE NUMBERED TRAP ITEMS THEMSELVES, not to loose vocabulary
    # anywhere in the section. Round 2 of cross-model review deleted BOTH
    # numbered mechanics and this assertion still passed 129/129, because
    # summary prose later in the section re-satisfied every keyword. A guard
    # that survives deletion of the thing it guards is decoration.
    #
    # `^N. ` pins the list item. The trap sentence must carry the threshold and
    # the consequence together, so neither can be dropped independently.
    printf '%s' "$section" | grep -qiE '^1\..*200000[^.]*sooner' \
        || missing="$missing trap1-sooner-bound-to-threshold"
    # And the retired falsehood must not come back on this surface. The claim
    # was guarded, pinned and cross-model certified for thirteen rounds while
    # being wrong, so its exact wording is now a denylist entry.
    # Not the exact retired sentence — that missed "disables autocompact
    # altogether", and the stale wording was still sitting in a comment one
    # copy-paste away. Not a bare pattern either: "nothing disables compaction
    # outright" is a CORRECT sentence and a bare pattern fails it, which is the
    # mirror image of the polarity defect this guard exists for. So: the
    # assertion shape, minus anything carrying a negator.
    if _doc_asserts_disabling "$section"; then
        missing="$missing retired-disable-falsehood"
    fi
    # The multiplication must stay documented — it is real, it is just not a
    # prohibition. Losing it puts #207's 120000 case back in the dark.
    printf '%s' "$section" | grep -qiE '^2\..*multipl' || missing="$missing trap2-multiplication"
    # ---- POLARITY ----
    # The anchors above verify that the right WORDS co-occur on the right list
    # item. They cannot verify that the sentence says the true thing: cross-model
    # review passed this suite 129/129 after replacing both mechanics with their
    # exact inversions ("under 200000 does not disable autocompact", "the two
    # vars do not multiply"). A negation denylist would be the fourth patch in
    # the same arms race and loses to "fails to disable" or a clause reorder.
    #
    # So pin the load-bearing sentence verbatim. The only string that satisfies
    # a literal match for the true claim is the true claim. Rewording the doc
    # now requires deliberately updating this constant — that friction IS the
    # guard, and it is the property the token patterns never had.
    #
    # AND ANCHOR THE PIN TO COLUMN 1. A free-floating `grep -F` matches a
    # SUBSTRING, and a substring is not an assertion: cross-model review then
    # passed 129/129 with "It is false that A window under 200000 disables
    # autocompact entirely." The pinned claim was intact — it had simply been
    # placed under negating scope. Requiring the constant to BEGIN the line
    # removes the room to put anything in front of it, so the claim's own
    # structural unit can no longer be re-scoped. (A separate contradicting
    # sentence elsewhere in the doc is still review's job, not grep's.)
    #
    # `awk index($0,pfx)==1` rather than a regex: the constants contain `*`,
    # `.` and backticks, and escaping them for grep -E is how these guards
    # acquired their bugs in the first place. index() is literal by construction.
    _doc_line_begins_with() {
        printf '%s\n' "$1" | awk -v pfx="$2" 'index($0, pfx) == 1 { f = 1 } END { exit !f }'
    }
    _doc_line_begins_with "$section" \
        '1. **A window under 200000 makes compaction fire sooner, not later.**' \
        || missing="$missing trap1-canonical-polarity"
    _doc_line_begins_with "$section" '2. **The two vars multiply.**' \
        || missing="$missing trap2-canonical-polarity"
    # And the formula block, which is what makes the rest checkable.
    # Visible projection: the formula lives inside a fence by design, but a
    # fence inside a comment is not visible to anyone (see above).
    printf '%s' "$section_vis" | grep -qE 'min\(model_window' || missing="$missing window-formula"
    printf '%s' "$section_vis" | grep -qE 'window .{0,3} 13000' || missing="$missing threshold-cap-formula"
    if [ -z "$missing" ]; then
        pass "#520: the autocompact section names the sub-200000 disable trap and the multiplication"
    else
        fail "#520: the 'Autocompact mechanics' section must bind the 200000 threshold to the SOONER consequence — missing:$missing"
    fi
}

# The specific harmful artifact #520 removed, guarded on the surface it lived
# on longest. An explicit `claude-opus-4-6` string pins 200K (the Max
# auto-upgrade is the bare `opus` alias only), and Opus 4.6 without extended
# context IS a proactive case — so a 30% override there is live and fires at
# ~60K, which is the same over-aggression this doc warns about for `opusplan`.
# The old text shipped that pairing annotated "(1M)", wrong on both counts.
test_wizard_doc_has_no_harmful_opus46_autocompact_pairing() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    # Look only at the JSON settings blocks that pin claude-opus-4-6, so an
    # explanatory sentence ABOUT the retired pairing does not trip this.
    local bad
    # POSITIVE assertion, not a denylist. The first version only rejected bad
    # values, so deleting the whole recommendation passed — cross-model review
    # proved it by removing the block and staying 129/129 green. The block must
    # EXIST and carry an acceptable value.
    #
    # `|| true` is load-bearing on both greps: this suite runs under `set -e`,
    # and a grep that finds nothing exits 1, which would kill the entire run
    # silently and take every later assertion with it. That is exactly what
    # happened when this test was first wired in.
    #
    # `--visible`, not raw bytes. The block is fenced JSON, so `--rendered`
    # would demand it be un-fenced — but raw bytes accepted the whole block
    # wrapped in an HTML comment, invisible to every reader, at 129/129 green.
    # Cross-model review found this after the prose pins were already fixed:
    # the exemption travelled, so the same defect survived on the surfaces I
    # had not converted yet.
    local block good bad
    block=$(python3 "$REPO_ROOT/tests/lib/mdfence.py" --visible "$DOC" \
        | awk '/"model": "claude-opus-4-6"/{f=1} f{print} f && /^```$/{f=0}' || true)
    if [ -z "$block" ]; then
        fail "#520: the claude-opus-4-6 settings example is gone — this assertion is now vacuous, re-anchor it or delete it deliberately"
        return
    fi
    # Acceptable: 60-100. Below 60 on a 200K pin is the ~60K-or-worse trigger
    # this doc calls over-aggressive for opusplan.
    good=$(printf '%s' "$block" | grep -E '"CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "(6[0-9]|7[0-9]|8[0-9]|9[0-9]|100)"' || true)
    bad=$(printf '%s' "$block" | grep -E '"CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "([0-9]|[1-5][0-9])"' || true)
    if [ -n "$bad" ]; then
        fail "#520: a claude-opus-4-6 block (200K, proactive) sets an over-aggressive percentage — 30 there is a ~60K trigger: $bad"
    elif [ -z "$good" ]; then
        fail "#520: the claude-opus-4-6 block no longer carries an autocompact recommendation at all — the guidance was deleted rather than corrected"
    else
        pass "#520: the claude-opus-4-6 block recommends a percentage sized for its 200K window"
    fi
}

# Same property on the SHIPPED skill. This file is distributed via npm to every
# consumer's .claude/skills/sdlc/, so it is the surface where wrong autocompact
# advice reaches the most people — it is where the `PCT_OVERRIDE=30` pairing
# that #520 deleted had been sitting.
test_sdlc_skill_states_the_sub_200k_window_mechanic() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    local missing=""
    # Every check on this file reads the VISIBLE projection. A commented-out
    # threshold is not guidance, and — the direction that actually bit — an
    # invisible `<!-- PCT_OVERRIDE=30 -->` must not trip the denylist below
    # and fail a document that is perfectly correct.
    local skill_vis
    skill_vis=$(python3 "$REPO_ROOT/tests/lib/mdfence.py" --visible "$SKILL")
    # Cause and consequence on the SAME line. A whole-file grep for the
    # consequence word was once satisfied by unrelated text elsewhere in this
    # skill, so the sentence naming the mechanic could be deleted with the
    # assertion still green — proved by cross-model review, second instance of
    # this exact defect in one round.
    printf '%s' "$skill_vis" | grep -qiE 'smaller window[^.]*sooner' \
        || missing="$missing sooner-consequence-bound-to-cause"
    # The retired falsehood is a denylist entry on this surface too: it shipped
    # to every consumer repo via npm and was certified thirteen times.
    if _doc_asserts_disabling "$skill_vis"; then
        missing="$missing retired-disable-falsehood"
    fi
    # ...and the polarity, which no token pattern can carry. Same finding as the
    # wizard-doc guard above: the inversion "does not disable compaction"
    # satisfies every keyword check. This surface phrases the fact differently
    # from the wizard doc on purpose — the skill is byte-capped — so the
    # constant is per-surface, not shared.
    #
    # Anchored to column 1 for the same reason as the wizard-doc pins: a
    # free substring match was defeated by wrapping the claim in negating
    # scope (`the assertion "..." is false`). The constant therefore runs from
    # the start of the line THROUGH the consequence, so there is nowhere to
    # insert a qualifier ahead of it.
    # Same rendered projection as the wizard-doc pins above, and for the same
    # reason: hiding this line in an HTML comment left it at column 1 and kept
    # the suite green while the shipped skill said nothing.
    python3 "$REPO_ROOT/tests/lib/mdfence.py" --rendered "$SKILL" \
        | awk -v pfx='**Autocompact: set neither override by default.** For a deliberately earlier boundary use `CLAUDE_CODE_AUTO_COMPACT_WINDOW` alone — a smaller window compacts sooner, and nothing in that range switches compaction off.' \
        'index($0, pfx) == 1 { f = 1 } END { exit !f }' \
        || missing="$missing disable-canonical-polarity"
    # The retired advice must not come back on this surface.
    printf '%s' "$skill_vis" | grep -qiE 'PCT_OVERRIDE=30|PCT_OVERRIDE=`?30' \
        && missing="$missing retired-pct30-pairing"
    if [ -z "$missing" ]; then
        pass "#520: shipped skill states the sub-200000 mechanic correctly, and the PCT=30 pairing is gone"
    else
        fail "#520: shipped skill must state that a smaller window compacts SOONER (it does not disable), and must not re-add the PCT_OVERRIDE=30 pairing — missing:$missing"
    fi
}

# Test (#207, Codex round 1 finding 2; updated #434 for Sonnet 5): the shipped
# `/sdlc` skill must frame the model pin as a recommendation, not a silent
# default. v1.80.0 flipped opus[1m] -> claude-opus-4-6[1m]; #434 (2026-07-04)
# made Sonnet 5 the new recommended driver. Any of the three is acceptable —
# what matters is the section explicitly frames it as "Recommended:".
test_sdlc_skill_frames_model_as_recommendation() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    if grep -qE 'Recommended:.*claude-opus|Recommended:.*opusplan|Recommended:.*Sonnet|opusplan.*claude-opus' "$SKILL"; then
        pass "skills/sdlc/SKILL.md frames model pin as recommendation"
    else
        fail "skills/sdlc/SKILL.md must recommend Sonnet 5, opusplan, or claude-opus-4-X"
    fi
}

# Tests (#251 + #225): Browser Tooling Policy section.
# Greps run INSIDE the policy section, not against the whole doc — otherwise
# claims could be satisfied by unrelated mentions elsewhere (Codex round 1
# finding 3).

# Extract the Browser Tooling Policy section: from `### Browser Tooling Policy`
# heading to the next `###` or `##` heading. Echoes the section content.
extract_browser_tooling_policy_section() {
    local DOC="$1"
    awk '
        /^### Browser Tooling Policy/ { in_section = 1; print; next }
        in_section && /^##[#]?[^#]/ { in_section = 0 }
        in_section { print }
    ' "$DOC"
}

test_wizard_doc_has_browser_tooling_policy_section() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    if grep -qE '^### Browser Tooling Policy[[:space:]]*$' "$DOC"; then
        pass "wizard doc has 'Browser Tooling Policy' section heading (#225, #251)"
    else
        fail "wizard doc must have a 'Browser Tooling Policy' section (#225, #251)"
    fi
}

# #225: 3-way split — all 3 tools must be named INSIDE the policy section
test_wizard_doc_browser_policy_covers_three_way_split() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    local section
    section=$(extract_browser_tooling_policy_section "$DOC")
    if [ -z "$section" ]; then fail "Browser Tooling Policy section is empty/missing"; return; fi
    local ok=true
    echo "$section" | grep -qE 'Playwright tests' || ok=false
    echo "$section" | grep -qE 'Playwright MCP' || ok=false
    echo "$section" | grep -qiE 'browser-use|real.browser tooling' || ok=false
    if [ "$ok" = true ]; then
        pass "policy section covers 3-way browser-tooling split (tests / MCP / real-browser, #225)"
    else
        fail "policy section must cover all 3 browser tooling approaches (#225)"
    fi
}

# #251: profile isolation for concurrent agents — INSIDE the policy section
test_wizard_doc_mcp_profile_isolation_for_concurrent_agents() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    local section
    section=$(extract_browser_tooling_policy_section "$DOC")
    if echo "$section" | grep -qiE 'concurrent.*(agent|MCP client)|multiple (agent|MCP client)|profile.lock|--user-data-dir|--isolated' ; then
        pass "policy section covers MCP profile-isolation for concurrent agent workflows (#251)"
    else
        fail "policy section must explain MCP profile isolation for concurrent agents (#251)"
    fi
}

# #251: upstream Playwright rejection — INSIDE the policy section
test_wizard_doc_notes_playwright_default_isolation_rejected() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    local section
    section=$(extract_browser_tooling_policy_section "$DOC")
    if echo "$section" | grep -qiE '(playwright/issues/40419|playwright/pull/40420|upstream.*rejected|very breaking)'; then
        pass "policy section notes upstream Playwright rejected default-isolated (#251)"
    else
        fail "policy section must explain that upstream Playwright rejected default-isolated (#251)"
    fi
}

# #225: trigger examples for real-browser tooling — INSIDE the policy section
test_wizard_doc_real_browser_trigger_examples() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    local section
    section=$(extract_browser_tooling_policy_section "$DOC")
    if echo "$section" | grep -qiE 'registrar|DNS setup|wallet|Web3|auth.heavy|profile.dependent|stateful operator|admin panel'; then
        pass "policy section includes real-browser trigger examples (#225)"
    else
        fail "policy section must include trigger examples for real-browser tooling (#225)"
    fi
}

test_wizard_doc_recommends_opus_1m
test_wizard_doc_frames_opus_1m_as_opt_in
test_wizard_doc_no_default_opus_1m_wording
test_wizard_doc_states_the_sub_200k_window_mechanic
test_wizard_doc_has_no_harmful_opus46_autocompact_pairing
test_sdlc_skill_states_the_sub_200k_window_mechanic
test_sdlc_skill_frames_model_as_recommendation
test_wizard_doc_has_browser_tooling_policy_section
test_wizard_doc_browser_policy_covers_three_way_split
test_wizard_doc_mcp_profile_isolation_for_concurrent_agents
test_wizard_doc_notes_playwright_default_isolation_rejected
test_wizard_doc_real_browser_trigger_examples
test_sdlc_skill_recommends_opus_or_opusplan
test_setup_skill_mentions_model_pin_in_optin_prompt
test_repo_settings_dogfood_setup_a
test_hooks_recommend_model
test_setup_skill_mentions_less_permission_prompts
test_wizard_doc_mentions_less_permission_prompts
test_wizard_doc_mentions_permissions_command

# ────────────────────────────────────────────
# XDLC Ecosystem Cross-References
# ────────────────────────────────────────────
#
# This repo is one of three published siblings:
#   - agentic-sdlc-wizard (this repo, npm) — Claude Code SDLC
#   - codex-sdlc-wizard (npm) — Codex SDLC adapter
#   - claude-gdlc-wizard (npm) — Game Development Life Cycle sibling
#
# Each package's README and primary docs should cross-reference the others
# so users landing on one package can discover the family. Without this,
# discoverability across the 3 packages is weak.

echo ""
echo "--- XDLC Ecosystem Cross-Refs ---"

# README must reference all 3 sibling packages by name so users on npm/GH
# can discover the family. Codex sibling = `codex-sdlc-wizard`,
# GDLC sibling = `claude-gdlc-wizard`. This repo's npm name is
# `agentic-sdlc-wizard` (already implicit in install commands, but the
# Ecosystem section should make all three explicit).
test_readme_references_all_siblings() {
    local README="$REPO_ROOT/README.md"
    if [ ! -f "$README" ]; then fail "README.md not found"; return; fi
    local missing=()
    grep -q 'codex-sdlc-wizard' "$README" || missing+=("codex-sdlc-wizard")
    grep -q 'claude-gdlc-wizard' "$README" || missing+=("claude-gdlc-wizard")
    if [ ${#missing[@]} -gt 0 ]; then
        fail "README.md missing sibling refs: ${missing[*]}"
    else
        pass "README.md references both sibling packages (codex-sdlc-wizard, claude-gdlc-wizard)"
    fi
}

# README should have a discoverable Ecosystem/Family section heading so
# users skimming the TOC find the cross-references, not just inline mentions.
test_readme_has_ecosystem_section() {
    local README="$REPO_ROOT/README.md"
    if [ ! -f "$README" ]; then fail "README.md not found"; return; fi
    if grep -qiE '^##+ (XDLC )?(Ecosystem|Family|Sibling|Related Projects)' "$README"; then
        pass "README.md has an Ecosystem/Family section heading"
    else
        fail "README.md missing an Ecosystem/Family/Siblings section heading"
    fi
}

# Wizard doc already mentions Codex sibling (line 501); GDLC was added to
# the family 2026-04-26 and should be referenced wherever Codex is.
test_wizard_doc_mentions_gdlc_sibling() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    if grep -q 'claude-gdlc-wizard' "$DOC"; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md references claude-gdlc-wizard sibling"
    else
        fail "Wizard doc missing claude-gdlc-wizard sibling reference"
    fi
}

# Codex sibling must surface near the top of README + wizard doc so users
# landing on either entry point see the alternative-agent option without
# scrolling 250+ lines to the Ecosystem section. (User feedback
# 2026-05-04: "mention codex-sdlc-wizard towards the top after mentioning
# this is for claude — 'this is for Claude but check out codex for
# alternatives'.")
test_readme_mentions_codex_near_top() {
    local README="$REPO_ROOT/README.md"
    if [ ! -f "$README" ]; then fail "README.md not found"; return; fi
    if head -30 "$README" | grep -q 'codex-sdlc-wizard'; then
        pass "README.md mentions codex-sdlc-wizard within first 30 lines"
    else
        fail "README.md does not mention codex-sdlc-wizard near top (first 30 lines)"
    fi
}

test_wizard_doc_mentions_codex_near_top() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    if head -50 "$DOC" | grep -q 'codex-sdlc-wizard'; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md mentions codex-sdlc-wizard within first 50 lines"
    else
        fail "CLAUDE_CODE_SDLC_WIZARD.md does not mention codex-sdlc-wizard near top (first 50 lines)"
    fi
}

test_readme_references_all_siblings
test_readme_has_ecosystem_section
test_wizard_doc_mentions_gdlc_sibling
test_readme_mentions_codex_near_top
test_wizard_doc_mentions_codex_near_top

# Setup skill must point users at /insights with the explicit qualitative-only
# caveat (ROADMAP #235a, original research #206). Without the caveat, the doc
# risks drifting into "we have token-spike detection via /insights" — which
# would be wrong; /insights is qualitative friction surfacing only, NOT a
# substitute for #220's raw-JSONL token instrumentation.
test_setup_skill_mentions_insights_with_caveat() {
    local SKILL="$REPO_ROOT/skills/setup/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/setup/SKILL.md not found"; return; fi
    if grep -qF '/insights' "$SKILL" && \
       grep -qE 'friction|qualitative' "$SKILL" && \
       grep -qE '#220|token-spike|raw.*session.*JSONL|does NOT replace' "$SKILL"; then
        pass "skills/setup/SKILL.md mentions /insights with qualitative-only caveat (#235a)"
    else
        fail "skills/setup/SKILL.md must reference /insights + friction/qualitative + the #220 non-replacement caveat"
    fi
}

# Wizard doc must list /insights in the "Complementary native skills" table
# (next to /less-permission-prompts and /permissions) AND carry the
# qualitative-only caveat as a paragraph below the table. Same anti-overclaim
# protection as the setup-skill test above.
test_wizard_doc_lists_insights_with_caveat() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    # Extract the Complementary native skills section
    local section
    section=$(awk '/Complementary native skills/,/### When Claude Code Improves/' "$DOC")
    if echo "$section" | grep -qF '/insights' && \
       echo "$section" | grep -qE 'friction|qualitative' && \
       echo "$section" | grep -qE '#220|token-spike|raw.*session.*JSONL|not a substitute'; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md lists /insights with qualitative-only caveat (#235a)"
    else
        fail "CLAUDE_CODE_SDLC_WIZARD.md 'Complementary native skills' section must list /insights with the #220 non-replacement caveat"
    fi
}

# SDLC skill must carry the skill-source-and-precedence preamble (ROADMAP
# #338). Prevents user confusion when both repo-local .claude/skills/sdlc/
# and global ~/.claude/skills/sdlc/ exist with the same name.
test_sdlc_skill_has_precedence_preamble() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    if grep -qE '^## Skill source & precedence' "$SKILL" && \
       grep -qF 'repo-local' "$SKILL" && \
       grep -qF 'head -5' "$SKILL"; then
        pass "skills/sdlc/SKILL.md carries 'Skill source & precedence' preamble (#338)"
    else
        fail "skills/sdlc/SKILL.md must include '## Skill source & precedence' section with repo-local-wins guidance + head -5 verification one-liner"
    fi
}

# Codex stdin-hang fix: every documented multi-line `codex exec` block must
# append `< /dev/null` so callers don't hit the codex stdin-read hang from
# non-interactive parents (background, hooks, CI, CC Bash tool). Validated
# on codex-cli 0.130.0 / macOS 14, 2026-05-15.
#
# Matcher covers BOTH multi-line shapes:
#   1. `codex exec \`                (bare, args on continuation lines)
#   2. `codex exec -c '...' -s ... \` (flags on the first line, continuing)
# Both end the first line with a trailing backslash. False positives are
# limited to lines containing the literal word "codex exec" followed by a
# trailing-backslash continuation, which is exactly what we want to enforce.
test_codex_exec_blocks_redirect_stdin() {
    local missing=0
    for f in "$REPO_ROOT/README.md" "$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md" "$REPO_ROOT/skills/sdlc/SKILL.md"; do
        if [ ! -f "$f" ]; then continue; fi
        local total stdin_redirected
        total=$(grep -cE '^[[:space:]]*codex exec( .*)? \\$' "$f" || true)
        stdin_redirected=$(awk '
            /^[[:space:]]*codex exec( .*)? \\$/ { in_block=1; depth=0; next }
            in_block {
                depth++
                if (/<[[:space:]]*\/dev\/null/) { count++; in_block=0; next }
                if (depth > 25) { in_block=0 }
            }
            END { print count+0 }
        ' "$f")
        if [ "$total" -gt 0 ] && [ "$stdin_redirected" -lt "$total" ]; then
            fail "$f: $stdin_redirected of $total multi-line codex exec blocks redirect stdin (need all $total to append '< /dev/null'). Matcher covers both 'codex exec \\' and 'codex exec -c ... \\' shapes."
            missing=$((missing+1))
        fi
    done
    if [ "$missing" -eq 0 ]; then
        pass "All documented multi-line codex exec blocks append '< /dev/null' (stdin-hang fix)"
    fi
}

# SDLC skill must carry the /goal wrapper with all 5 quality elements
# (#347 corrected 2026-05-24). Existence-only would let drift remove the
# safety guidance — each item below is a load-bearing claim from the
# corrected research doc (.reviews/347-goal-mode-research-CORRECTED.md).
test_sdlc_skill_has_goal_wrapper() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    local missing=""
    grep -qE '^## Long-Running Goals \(`?/goal`?\)' "$SKILL" || missing+=" section-header"
    grep -qF 'v2.1.143' "$SKILL" || missing+=" version-floor-2.1.143"
    grep -qiE 'trusted|untrusted' "$SKILL" || missing+=" trusted-workspace-preflight"
    grep -qF 'disableAllHooks' "$SKILL" || missing+=" disableAllHooks-preflight"
    grep -qiE 'turn(/| )?time bound|hard.*bound|stop after' "$SKILL" || missing+=" hard-bound-guidance"
    grep -qiE 'cannot call tools|can.t call tools|transcript[ -]only' "$SKILL" || missing+=" anti-pattern-off-transcript"
    grep -qiE 'resume.*reset|--resume.*counters|counters.*reset' "$SKILL" || missing+=" resume-caveat"
    # PR-D additions: 95% confidence gate + DLC binding in condition.
    # Without these, /goal becomes "20 turns of flailing" — the evaluator
    # has no anchor for correctness, only for completion.
    grep -qiE 'confidence gate|HIGH 95%|below.*95%|95%.*confidence' "$SKILL" || missing+=" 95-percent-confidence-gate"
    grep -qiE 'DLC binding|name the (active )?DLC|condition MUST name' "$SKILL" || missing+=" DLC-binding-rule"
    if [ -z "$missing" ]; then
        pass "skills/sdlc/SKILL.md /goal wrapper has all required quality elements (#347 + PR-D)"
    else
        fail "skills/sdlc/SKILL.md /goal wrapper missing:$missing"
    fi
}

# Cross-model review guidance must teach background-mode (issue #364, 2026-05-27).
# Bash tool clamps `timeout` to 600000 ms; foreground codex gets force-killed at
# the wall. Without this guidance, sessions burn 60+ minutes on 7-minute reviews
# (incident: 70 min + 9 Stop-hook re-invocations before harness safeguard fired).
test_codex_review_guidance_teaches_background_mode() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    local WIZARD="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    local missing=""
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    if [ ! -f "$WIZARD" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    # SKILL.md must teach background-mode + cite the 10-min cap reason
    grep -qF 'run_in_background: true' "$SKILL" || missing+=" SKILL.md:run_in_background"
    grep -qiE '600000|10 min|10-min' "$SKILL" || missing+=" SKILL.md:10-min-cap-reason"
    # Wizard doc must carry the same guidance (verified in at least one of the
    # two Cross-Model Review sections — both edits land in the same release).
    grep -qF 'run_in_background: true' "$WIZARD" || missing+=" WIZARD.md:run_in_background"
    grep -qiE '600000|10 min|10-min' "$WIZARD" || missing+=" WIZARD.md:10-min-cap-reason"
    if [ -z "$missing" ]; then
        pass "Cross-model review guidance teaches background-mode + cites 10-min cap (#364)"
    else
        fail "Cross-model review background-mode guidance missing:$missing"
    fi
}

test_setup_skill_mentions_insights_with_caveat
test_wizard_doc_lists_insights_with_caveat
test_sdlc_skill_has_precedence_preamble
test_codex_exec_blocks_redirect_stdin
test_sdlc_skill_has_goal_wrapper
test_codex_review_guidance_teaches_background_mode

# #372: Cross-model review is REQUIRED for high-stakes, not opt-in
test_cross_model_review_required_not_optional() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    local WIZARD="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    local ok=true
    grep -q '## Cross-Model Review (REQUIRED' "$SKILL" || ok=false
    grep -q 'REQUIRED' "$WIZARD" || ok=false
    grep -q 'If Configured' "$SKILL" && ok=false
    grep -q 'log justification' "$SKILL" || ok=false
    if [ "$ok" = true ]; then
        pass "#372: Cross-model review REQUIRED in skill + wizard, skip requires justification"
    else
        fail "#372: Cross-model review heading must say REQUIRED, not 'If Configured', with log justification"
    fi
}

test_cross_model_review_required_not_optional

# ────────────────────────────────────────────
# AI Setup Lanes — Sonnet 5 + model-aware effort (July 2026 update)
# ────────────────────────────────────────────

echo ""
echo "--- AI Setup Lanes ---"

test_setup_lanes_references_sonnet_5() {
    local LANES="$REPO_ROOT/AI_SETUP_LANES.md"
    if [ ! -f "$LANES" ]; then fail "AI_SETUP_LANES.md not found"; return; fi
    if grep -qE 'Sonnet 5|claude-sonnet-5' "$LANES"; then
        pass "AI_SETUP_LANES.md references Sonnet 5"
    else
        fail "AI_SETUP_LANES.md must reference Sonnet 5 (launched June 30, replaces Sonnet 4.6)"
    fi
}

test_setup_lanes_has_model_aware_effort() {
    local LANES="$REPO_ROOT/AI_SETUP_LANES.md"
    if [ ! -f "$LANES" ]; then fail "AI_SETUP_LANES.md not found"; return; fi
    if grep -qE 'xhigh.*Opus 4\.8|Opus 4\.8.*xhigh' "$LANES" \
        && grep -qE 'high.*Sonnet 5|Sonnet 5.*high' "$LANES"; then
        pass "AI_SETUP_LANES.md has model-aware effort (xhigh for Opus 4.8, high for Sonnet 5)"
    else
        fail "AI_SETUP_LANES.md must recommend effort per model (xhigh for Opus 4.8, high for Sonnet 5)"
    fi
}

test_setup_lanes_no_blanket_max() {
    local LANES="$REPO_ROOT/AI_SETUP_LANES.md"
    if [ ! -f "$LANES" ]; then fail "AI_SETUP_LANES.md not found"; return; fi
    if grep -qE 'max.*all models|always.*max|max.*every' "$LANES"; then
        fail "AI_SETUP_LANES.md must NOT recommend blanket max for all models (max overthinks on Opus 4.8 and Sonnet 5)"
    else
        pass "AI_SETUP_LANES.md does not blanket-recommend max for all models"
    fi
}

test_setup_lanes_effort_escalation_ladder() {
    local LANES="$REPO_ROOT/AI_SETUP_LANES.md"
    if [ ! -f "$LANES" ]; then fail "AI_SETUP_LANES.md not found"; return; fi
    if grep -qiE 'escalat|ramp|bump.*effort|raise.*effort|ladder' "$LANES"; then
        pass "AI_SETUP_LANES.md documents effort escalation (start at default, raise when needed)"
    else
        fail "AI_SETUP_LANES.md must document effort escalation strategy"
    fi
}

test_setup_lanes_references_sonnet_5
test_setup_lanes_has_model_aware_effort
test_setup_lanes_no_blanket_max
test_setup_lanes_effort_escalation_ladder

# The /sdlc skill's "Recommended Model" section is read on every /sdlc
# invocation — it must not enshrine the same blanket-max bug the hook had.
# Real incident: a user's ~/.zshrc had CLAUDE_CODE_EFFORT_LEVEL=max from
# this exact advice, and it silently overrode /effort xhigh after they
# switched to Sonnet 5 (2026-07-04).
test_sdlc_skill_recommended_model_is_model_aware() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    if grep -qE 'CLAUDE_CODE_EFFORT_LEVEL.?=.?max.? in (settings )?env block' "$SKILL"; then
        fail "skills/sdlc/SKILL.md must not blanket-recommend persisting max via env var (bit a real user, 2026-07-04)"
    else
        pass "skills/sdlc/SKILL.md does not blanket-recommend persisting max via env var"
    fi
}

test_sdlc_skill_recommended_model_mentions_sonnet_5() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    if grep -qE 'Sonnet 5|claude-sonnet-5' "$SKILL"; then
        pass "skills/sdlc/SKILL.md Recommended Model section mentions Sonnet 5"
    else
        fail "skills/sdlc/SKILL.md must mention Sonnet 5 in Recommended Model section"
    fi
}

test_sdlc_skill_recommended_model_is_model_aware
test_sdlc_skill_recommended_model_mentions_sonnet_5

# This repo's own dogfooded SDLC.md has the identical table/callout pattern
# as skills/sdlc/SKILL.md had — same blanket-max bug, same stale opus-4-6
# recommendation. It also already has a "Lessons Learned" entry (added
# 2026-07-04) explaining why blanket max is wrong, which the table
# contradicted until fixed. Found while shipping #436/#437, 2026-07-05.
test_sdlc_config_recommended_effort_is_model_aware() {
    local CONFIG="$REPO_ROOT/SDLC.md"
    if [ ! -f "$CONFIG" ]; then fail "SDLC.md not found"; return; fi
    if grep -qE 'CLAUDE_CODE_EFFORT_LEVEL.?=.?max.? in (settings )?env block' "$CONFIG"; then
        fail "SDLC.md must not blanket-recommend persisting max via env var (contradicts its own Lessons Learned entry)"
    else
        pass "SDLC.md does not blanket-recommend persisting max via env var"
    fi
}

test_sdlc_config_recommended_model_mentions_sonnet_5() {
    local CONFIG="$REPO_ROOT/SDLC.md"
    if [ ! -f "$CONFIG" ]; then fail "SDLC.md not found"; return; fi
    if grep -qE 'Sonnet 5|claude-sonnet-5' "$CONFIG"; then
        pass "SDLC.md Recommended Model row mentions Sonnet 5"
    else
        fail "SDLC.md must mention Sonnet 5 in its Recommended Model row"
    fi
}

test_sdlc_config_recommended_effort_is_model_aware
test_sdlc_config_recommended_model_mentions_sonnet_5

# Cowork plugin (cowork/) shipped in PR #410 (ROADMAP #424) with working
# skills + prompt-based hooks and its own README, but was never
# cross-referenced from the main wizard doc — invisible to anyone who
# only reads CLAUDE_CODE_SDLC_WIZARD.md. Found 2026-07-05.
test_wizard_doc_has_cowork_section() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    if grep -qiE '^#+ .*Cowork' "$DOC"; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md has a Cowork section"
    else
        fail "CLAUDE_CODE_SDLC_WIZARD.md must have a Cowork section cross-referencing cowork/README.md"
    fi
}

test_wizard_doc_has_cowork_section

# Autocompact Tuning table previously blanket-recommended 30% for "any 1M
# model" — this was Opus-specific (opus[1m] needed an opt-in pin for
# extended context). Sonnet 5 always runs 1M natively with its own
# proactive-compaction default (~967K, per code.claude.com/docs/en/
# model-config#sonnet-5-context-window) — the 30% figure was never
# re-derived for it and doesn't apply. Verified via live research
# 2026-07-05, not carried over from the Opus-era table unexamined.
#
# 2026-07-24 REWRITE (PR #468 review): the previous assertion was
# `grep -qE 'Sonnet 5'` — a substring check that passed as long as the
# string appeared anywhere in the section. It green-lit the exact
# regression it was written to prevent: the Opus 5 lane restructure
# relabeled Setup A from Sonnet 5 to Opus 5 and carried the 30% figure
# onto Opus 5 unexamined. Vacuous-test pattern (cf. #462's keyword-only
# findings). Now asserts the semantic, and is mutation-tested.
#
# The contract, per raw env-vars.md (fetched via curl, not WebFetch —
# ROADMAP #450): CLAUDE_AUTOCOMPACT_PCT_OVERRIDE only lowers the trigger
# where compaction is PROACTIVE — when CLAUDE_CODE_AUTO_COMPACT_WINDOW is
# set, in cloud sessions, on Sonnet 4.6/Opus 4.6 without extended context,
# and on Sonnet 5 at its default threshold. A local Opus session is the
# doc's own counter-example. So Sonnet 5's scoped 75% is legitimate; an
# Opus-5-bound percentage is not. Deliberately worded as a documentation
# gap, NOT a runtime claim — Codex xhigh put ~96% on the policy and only
# ~65% on "a local Opus 5 override is inert", so the docs must not assert
# the latter.
test_wizard_doc_autocompact_sonnet5_scoped_not_opus5() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    local section
    section=$(awk '/^### Autocompact Tuning/{f=1} f && /^###[^#]/ && !/^### Autocompact Tuning/{f=0} f' "$DOC")
    local ok=true

    # (a) Sonnet 5's own scoped guidance must survive — it is correct.
    #     Line-anchored to the paragraph itself, not a cross-reference.
    echo "$section" | grep -qE '^\*\*Sonnet 5 specifics' || ok=false

    # (b) Opus 5 must be addressed explicitly, not left to inherit
    #     whatever the Opus-era rows said. MUST be line-anchored: the
    #     section contains three `see "Opus 5 specifics" above` cross-refs,
    #     so an unanchored grep still matched after the real paragraph was
    #     deleted — caught by mutation 3 on 2026-07-24, and exactly the
    #     vacuousness this rewrite exists to eliminate.
    echo "$section" | grep -qE '^\*\*Opus 5 specifics' || ok=false

    # (c) THE REGRESSION GUARD — bind the actual Setup A TABLE ROW to "none".
    #
    #     Codex xhigh defeated the previous version of this check
    #     (2026-07-24) with a one-line mutation:
    #       | **Setup A default driver (...)** | **30%** | Fires around 300K ... |
    #     The old check grepped for lines containing the literal string
    #     "Opus 5" and a percentage. The mutation says "Setup A" instead,
    #     so it sailed through — the test never associated Setup A WITH
    #     Opus 5. Second vacuousness in the same assertion in one session;
    #     self-chosen mutations all happened to use the literal "Opus 5".
    #
    #     Round-2 recheck found a THIRD hole (2026-07-24): checking only the
    #     threshold cell (field 3) let the recommendation move to the "Why"
    #     cell — `| **Setup A ...** | **none** | ...but set
    #     `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=30` for long work. |` passed 77/77
    #     while restoring the defect. A second bypass: add a SECOND Setup A
    #     row, since grep|awk|grep accepted the valid `none` from either match.
    #
    #     Now: require EXACTLY ONE Setup A row, its threshold cell to be
    #     `none`, and NO percentage or PCT key anywhere in the whole row.
    local setup_a_rows setup_a_count setup_a_row
    setup_a_rows=$(echo "$section" | grep -E '^\|[^|]*(Setup A|Opus 5.*bleeding)[^|]*\|')
    setup_a_count=$(printf '%s\n' "$setup_a_rows" | grep -c . || true)
    if [ "$setup_a_count" != "1" ]; then
        ok=false
    else
        setup_a_row="$setup_a_rows"
        # threshold cell must be exactly "none"
        echo "$setup_a_row" | awk -F'|' '{print $3}' \
            | grep -qiE '^[[:space:]]*\*{0,2}none\*{0,2}[[:space:]]*$' || ok=false
        # ...and no percentage or PCT key ANYWHERE in the row, including the
        # "Why" cell. This is the check the round-2 mutation defeated.
        if echo "$setup_a_row" | grep -qE '[0-9]+%|CLAUDE_AUTOCOMPACT_PCT_OVERRIDE'; then
            ok=false
        fi
    fi

    # (c2) Belt-and-braces: still reject a percentage bound to a line that
    #      does name Opus 5 (the original shape), so both spellings fail.
    if echo "$section" | grep -E 'Opus 5' | grep -qE '[0-9]+%'; then
        ok=false
    fi

    # (c3) Round-3 recheck found a FOURTH bypass: a prose recommendation
    #      with the number spelled out — "set the autocompact threshold to
    #      thirty percent for long-running work" — evading `[0-9]+%`, the
    #      PCT key name, and the strings "Setup A"/"Opus 5" at once.
    #      This check catches spelled-out numerals near threshold language.
    #
    #      LIMITS — stated deliberately, not an oversight. A regex cannot be
    #      semantically complete against natural language: "roughly a third",
    #      "0.3 of the window", or "300K of 1M" would still pass. This guard
    #      covers the shapes the real regression took (table cell, adjacent
    #      cell, duplicate row, literal-string evasion) plus the cheapest
    #      prose evasion. Beyond that the control is cross-model review, not
    #      this test. Do not read a green result as proof no recommendation
    #      exists — read it as proof the known shapes are absent.
    if echo "$section" | grep -qiE '(ten|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety) percent'; then
        ok=false
    fi

    # (d) The unsupported causal inference must be gone: a 1M upgrade
    #     establishes capacity, not proactive mode.
    if echo "$section" | grep -qiE 'auto-upgrade[sd]? to 1M context, so|so the `?[0-9]+%`? override applies'; then
        ok=false
    fi

    # (e) No runtime assertion about what a local Opus session DOES.
    #     Codex set the leash: ~96% confidence on the documentation policy,
    #     only ~65% on the runtime behavior, because the official text scopes
    #     its example to "a local session on Opus 4.8" specifically. Prose
    #     that generalizes it to "a local Opus session" overclaims.
    if echo "$section" | grep -qiE 'a local Opus session (is|triggers|compacts|fires)'; then
        ok=false
    fi

    if $ok; then
        pass "Autocompact Tuning: Setup A row is 'none', 75% stays scoped to Sonnet 5, no runtime overclaim"
    else
        fail "Autocompact Tuning must set Setup A's threshold cell to 'none', keep Sonnet 5's scoped guidance and Opus 5 specifics headings, bind NO percentage to Setup A/Opus 5, and make no runtime claim about a local Opus session"
    fi
}

# The EMITTED consumer-settings contract, separate from prose: Step 9.5's
# [o] handler must write no autocompact key at all, and [s] must keep its
# scoped 75. Codex's review found the prose test alone couldn't catch a
# regression in the handler that physically writes consumer settings.
test_setup_skill_handlers_autocompact_shape() {
    local F="$REPO_ROOT/skills/setup/SKILL.md"
    if [ ! -f "$F" ]; then fail "skills/setup/SKILL.md not found"; return; fi
    local ok=true

    # [o] handler: the json block containing "model": "opus" must have no PCT key.
    local o_block
    o_block=$(awk '/"model": "opus"/{f=1} f{print} f&&/^\}/{exit}' "$F")
    if [ -z "$o_block" ]; then
        ok=false
    elif echo "$o_block" | grep -q 'CLAUDE_AUTOCOMPACT_PCT_OVERRIDE'; then
        ok=false
    fi

    # [s] handler: the json block containing "model": "sonnet" must keep 75.
    local s_block
    s_block=$(awk '/"model": "sonnet"/{f=1} f{print} f&&/^\}/{exit}' "$F")
    if ! echo "$s_block" | grep -q '"CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "75"'; then
        ok=false
    fi

    if $ok; then
        pass "setup SKILL.md: [o] writes no autocompact key, [s] keeps its scoped 75"
    else
        fail "setup SKILL.md: Setup A's [o] handler must emit NO CLAUDE_AUTOCOMPACT_PCT_OVERRIDE, and Setup B's [s] handler must keep \"75\""
    fi
}

test_setup_skill_handlers_autocompact_shape

test_wizard_doc_autocompact_sonnet5_scoped_not_opus5

# ROADMAP #437: the wizard doc has 2 separate copies of the cross-model
# review protocol (a condensed summary section and a fuller tutorial
# section), each with its own prose instruction AND its own flow diagram —
# 3 prose "If CERTIFIED" lines plus 4 diagram terminal states (2 per
# section), 7 decision points total. The v1.86.0 codex-gate-check.sh fix
# requires every one of them to write commit_sha into handoff.json.
#
# Codex round 1 caught 2 of 3 prose lines fixed (1 missed); a global-count
# comparison (commit_sha mentions >= "If CERTIFIED" mentions) briefly
# replaced it but round 2's mutation testing proved that heuristic has slack
# — extra commit_sha mentions elsewhere in the doc could mask an individual
# line silently losing its own instruction, and it never covered the
# diagram terminal states at all (round 2 also found a 3rd, entirely
# separate diagram — the first section's own flow chart at lines ~2515/2526
# — that neither the prose fix nor the original test had ever touched).
#
# Per-line check instead: every line matching one of the 3 known decision-
# point shapes (prose "If CERTIFIED", diagram "CERTIFIED? ", or diagram
# "→ CERTIFIED") must contain "commit_sha" on that SAME line — no aggregate
# slack possible. Verified the exact pattern below matches all 7 real
# decision-point lines and none of the ~13 other CERTIFIED mentions in the
# doc (explanatory prose, reviewer-prompt "End with CERTIFIED or NOT
# CERTIFIED" text, unrelated "implicit CERTIFIED" references).
test_wizard_doc_certified_paths_all_mention_commit_sha() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    local decision_lines total missing offenders
    decision_lines=$(grep -nE "If CERTIFIED|CERTIFIED\? |→ CERTIFIED" "$DOC" 2>/dev/null || true)
    total=$(echo "$decision_lines" | { grep -c . || true; })
    offenders=$(echo "$decision_lines" | { grep -v "commit_sha" || true; })
    missing=$(echo "$offenders" | { grep -c . || true; })
    if [ "$total" -gt 0 ] && [ "$missing" -eq 0 ]; then
        pass "every CERTIFIED decision point in the wizard doc mentions commit_sha on the same line ($total checked)"
    else
        fail "$missing of $total CERTIFIED decision points in the wizard doc are missing a same-line commit_sha mention — at least one path silently skips the ROADMAP #437 staleness-fix instruction. Offending lines:
$offenders"
    fi
}

test_wizard_doc_certified_paths_all_mention_commit_sha

# #236(c): relocated from the dissolved tests/test-degradation-detection.sh
# (5 of that file's 14 tests, the only non-stub non-duplicate survivors —
# doc-hardening checks belong here with the rest of the wizard-doc consistency
# suite, not in a file named for CI score-persistence/degradation-detection).

# Wizard doc effort section must explain WHY effort matters — not just how to
# set it — by naming "adaptive thinking" as the degradation mechanism.
test_wizard_doc_effort_section_cites_adaptive_thinking() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    local effort_section
    effort_section=$(sed -n '/## Recommended Effort Level/,/^## /p' "$DOC")
    if echo "$effort_section" | grep -iq "adaptive thinking"; then
        pass "wizard doc effort section references adaptive thinking as root cause"
    else
        fail "wizard doc effort section must reference 'adaptive thinking' as degradation root cause"
    fi
}

# Must scope "medium is the default" to Pro/Max plans specifically (API/Team/
# Enterprise default to high) rather than a blanket claim.
test_wizard_doc_medium_default_scoped_to_pro_max() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    local effort_section
    effort_section=$(sed -n '/## Recommended Effort Level/,/^## /p' "$DOC")
    if echo "$effort_section" | grep -iE "Pro.*Max|Max.*Pro|Pro/Max|Pro and Max"; then
        if echo "$effort_section" | grep -iE "medium.*(default|defaults)" | grep -iqE "Pro|Max|plan"; then
            pass "wizard doc medium-default claim scoped to Pro/Max plans"
        elif ! echo "$effort_section" | grep -iqE "medium.*(default|defaults)"; then
            pass "wizard doc medium-default scoped to Pro/Max plans (no blanket claim)"
        else
            fail "wizard doc has a medium-default claim not scoped to Pro/Max"
        fi
    else
        fail "wizard doc effort section must reference Pro/Max plans for medium-default scope"
    fi
}

test_wizard_doc_cites_live_effort_docs_url() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    local effort_section
    effort_section=$(sed -n '/## Recommended Effort Level/,/^## /p' "$DOC")
    if echo "$effort_section" | grep -q "code.claude.com"; then
        pass "wizard doc effort section cites code.claude.com docs"
    else
        fail "wizard doc effort section must cite code.claude.com docs (not memory files or vague references)"
    fi
}

# CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING is a "nuclear option" — must be
# documented as opt-in, never shipped as a default in the CLI template.
test_wizard_doc_disable_adaptive_thinking_is_optin() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    local SETTINGS="$REPO_ROOT/cli/templates/settings.json"
    local effort_section
    effort_section=$(sed -n '/## Recommended Effort Level/,/^## /p' "$DOC")
    if echo "$effort_section" | grep -q "CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING"; then
        if jq -e '.env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING' "$SETTINGS" > /dev/null 2>&1; then
            fail "CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING should be opt-in, not in default settings.json"
        else
            pass "CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING documented as opt-in (not in default template)"
        fi
    else
        fail "wizard doc must document CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING env var"
    fi
}

# Anti-laziness guidance must name at least 2 specific mechanisms, not a vague
# "be thorough" — otherwise it reads as unenforceable advice.
test_wizard_doc_anti_laziness_names_specific_mechanisms() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    local wizard_content
    wizard_content=$(cat "$DOC")
    local mechanism_count=0
    echo "$wizard_content" | grep -iq "adaptive thinking" && mechanism_count=$((mechanism_count + 1))
    echo "$wizard_content" | grep -iq "effort.level\|effort:.*high\|effort.*level" && mechanism_count=$((mechanism_count + 1))
    echo "$wizard_content" | grep -iq "thinking budget\|reasoning.*budget\|reasoning.*allocat" && mechanism_count=$((mechanism_count + 1))
    echo "$wizard_content" | grep -iq "CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING" && mechanism_count=$((mechanism_count + 1))
    if [ "$mechanism_count" -ge 2 ]; then
        pass "wizard doc anti-laziness guidance references $mechanism_count specific mechanisms"
    else
        fail "anti-laziness guidance must reference specific mechanisms (adaptive thinking, effort levels, etc.), found $mechanism_count"
    fi
}

test_wizard_doc_effort_section_cites_adaptive_thinking
test_wizard_doc_medium_default_scoped_to_pro_max
test_wizard_doc_cites_live_effort_docs_url
test_wizard_doc_disable_adaptive_thinking_is_optin
test_wizard_doc_anti_laziness_names_specific_mechanisms

# ────────────────────────────────────────────
# ROADMAP archive split (#236(f), 2026-07-06)
# ────────────────────────────────────────────

# A row number must never appear in both the active table and the archive —
# that would mean a row was copied instead of moved, or edited independently
# in both places after the split.
test_roadmap_no_duplicate_row_numbers_across_files() {
    local ROADMAP="$REPO_ROOT/ROADMAP.md"
    local ARCHIVE="$REPO_ROOT/ROADMAP_ARCHIVE.md"
    if [ ! -f "$ROADMAP" ] || [ ! -f "$ARCHIVE" ]; then
        fail "ROADMAP.md or ROADMAP_ARCHIVE.md not found"
        return
    fi
    local active_nums archive_nums dupes
    active_nums=$(grep -oE '^\| *[0-9]+ *\|' "$ROADMAP" | grep -oE '[0-9]+' | sort -un)
    archive_nums=$(grep -oE '^\| *[0-9]+ *\|' "$ARCHIVE" | grep -oE '[0-9]+' | sort -un)
    # NOTE: avoid `comm <(...) <(...)` here — BSD comm on macOS silently
    # returns empty output when both inputs are process substitutions
    # (verified: two real files behave correctly, two /dev/fd fifos don't).
    # Concatenating two already-deduped lists and taking uniq -d is
    # portable and gives the same "appears in both" answer.
    dupes=$(printf '%s\n%s\n' "$active_nums" "$archive_nums" | sort -n | uniq -d)
    if [ -z "$dupes" ]; then
        pass "no row number appears in both ROADMAP.md and ROADMAP_ARCHIVE.md"
    else
        fail "row number(s) present in BOTH ROADMAP.md and ROADMAP_ARCHIVE.md (should be moved, not copied): $dupes"
    fi
}

# Spot-check a sample of rows known to still be open as of the 2026-07-06
# split — proves the split didn't silently archive an active item.
test_roadmap_key_open_items_present() {
    local ROADMAP="$REPO_ROOT/ROADMAP.md"
    if [ ! -f "$ROADMAP" ]; then fail "ROADMAP.md not found"; return; fi
    local missing=""
    for n in 19 89 236 424 434 438; do
        if ! grep -qE "^\| *$n *\|" "$ROADMAP"; then
            missing="$missing $n"
        fi
    done
    if [ -z "$missing" ]; then
        pass "known-open ROADMAP rows (19/89/236/424/434/438) all present in ROADMAP.md"
    else
        fail "known-open ROADMAP row(s) missing from ROADMAP.md:$missing"
    fi
}

# Spot-check a sample of rows known to be fully resolved as of the 2026-07-06
# split — proves the split actually moved them out of the active table.
test_roadmap_archive_has_key_archived_items() {
    local ROADMAP="$REPO_ROOT/ROADMAP.md"
    local ARCHIVE="$REPO_ROOT/ROADMAP_ARCHIVE.md"
    if [ ! -f "$ROADMAP" ] || [ ! -f "$ARCHIVE" ]; then
        fail "ROADMAP.md or ROADMAP_ARCHIVE.md not found"
        return
    fi
    local bad=""
    for n in 1 14 20 231; do
        if ! grep -qE "^\| *$n *\|" "$ARCHIVE"; then
            bad="$bad $n(missing-from-archive)"
        fi
        if grep -qE "^\| *$n *\|" "$ROADMAP"; then
            bad="$bad $n(still-in-active-table)"
        fi
    done
    if [ -z "$bad" ]; then
        pass "known-resolved ROADMAP rows (1/14/20/231) all archived, none left in active table"
    else
        fail "archive split issue(s):$bad"
    fi
}

test_roadmap_no_duplicate_row_numbers_across_files
test_roadmap_key_open_items_present
test_roadmap_archive_has_key_archived_items

# ────────────────────────────────────────────
# ROADMAP #439: GPT-5.6 (Sol) supersedes GPT-5.5 as cross-model reviewer
# Per-location checks, not whole-file counts (per #437's CHANGELOG lesson:
# aggregate checks have slack that lets one unfixed line hide behind an
# unrelated match elsewhere in the same file). Each line must both GAIN
# "5.6" and LOSE "5.5" (and "5.4" on fallback-chain lines) — a half-applied
# edit (mentions 5.6 nearby but leaves the old 5.5/5.4 name in place) fails.
# ────────────────────────────────────────────

# Checks one line of a file both contains a required substring and does NOT
# contain any of the forbidden substrings. Echoes a descriptive failure (or
# nothing on success) for the caller to collect via command substitution,
# rather than calling fail() directly, so one test function can report every
# stale line in one message. (bash 3.x on macOS has no namerefs.)
_check_line_has_and_lacks() {
    local file="$1" line_num="$2" must_have_csv="$3"
    shift 3
    local content
    content="$(sed -n "${line_num}p" "$file")"
    if [ -z "$content" ]; then
        echo "${file}:${line_num}(line-missing)"
        return
    fi
    local required
    for required in ${must_have_csv//,/ }; do
        if ! printf '%s' "$content" | grep -qi "$required"; then
            echo "${file}:${line_num}(missing '$required')"
            return
        fi
    done
    for forbidden in "$@"; do
        if printf '%s' "$content" | grep -qi "$forbidden"; then
            echo "${file}:${line_num}(stale '$forbidden')"
            return
        fi
    done
}

# Content-anchored variant of _check_line_has_and_lacks: finds the target
# line by a stable content pattern instead of a hardcoded line number, so it
# doesn't go stale every time an earlier-in-file edit shifts line numbers
# (this exact test drifted 3855->3863->3865->3867 across three separate
# sessions in one day, 2026-07-21 — a hardcoded-line-number test is a
# maintenance trap for any file that isn't append-only).
_check_content_line_has_and_lacks() {
    local file="$1" anchor_pattern="$2" must_have_csv="$3"
    shift 3
    local content
    content="$(grep -i "$anchor_pattern" "$file" | head -1)"
    if [ -z "$content" ]; then
        echo "${file}:(anchor '$anchor_pattern' not found)"
        return
    fi
    # PORTABILITY: match required/forbidden tokens as FIXED STRINGS (-F).
    # These patterns are written with escaped backticks (\`high\`), and in a
    # single-quoted shell argument the backslash survives into the pattern. BSD
    # grep reads \` as a literal backtick; GNU grep reads it as a start-of-buffer
    # ANCHOR (a GNU extension), so the same assertion passed on macOS and could
    # never match on Linux. CI caught this on a file the local suite had just
    # certified 104/104. Strip the escapes and compare literally — none of these
    # tokens are regexes, so -F is what was meant all along.
    local required
    for required in ${must_have_csv//,/ }; do
        if ! printf '%s' "$content" | grep -qiF "${required//\\/}"; then
            echo "${file}:(anchor '$anchor_pattern' missing '$required')"
            return
        fi
    done
    for forbidden in "$@"; do
        if printf '%s' "$content" | grep -qiF "${forbidden//\\/}"; then
            echo "${file}:(anchor '$anchor_pattern' stale '$forbidden')"
            return
        fi
    done
}

test_ai_setup_lanes_reviewer_is_gpt56() {
    local F="$REPO_ROOT/AI_SETUP_LANES.md"
    if [ ! -f "$F" ]; then fail "AI_SETUP_LANES.md not found"; return; fi
    local bad=""
    # "5\.6" AND "Sol" (not just one or the other) so a Sol->Terra swap, or a
    # future GPT-5.7 Sol rename, both fail.
    # (Line numbers re-pinned after the Reliable default-flip shortened
    # Setup A and shifted all Frontier-section lines.
    # Re-pinning is the FIFTH time this check has cost a round to a pure
    # edit above it. Replacing them with content anchors is #659.)
    # The Reliable section (lines 1-32) deliberately uses GPT-5.5 — skip it.
    for n in 41 62 77 79 157 209 213 251 252 255; do
        bad="$bad$(_check_line_has_and_lacks "$F" "$n" "5\.6,Sol" "5\.5")"
    done
    # L161 is the fallback-chain line: must name "5\.6" AND BOTH Sol (primary)
    # and Terra (fallback target) so a Terra->Luna swap also fails.
    bad="$bad$(_check_line_has_and_lacks "$F" 161 "5\.6,Sol,Terra" "5\.5" "5\.4")"
    if [ -z "$bad" ]; then
        pass "AI_SETUP_LANES.md: all reviewer-model lines reference GPT-5.6 Sol/Terra, none reference stale GPT-5.5/5.4"
    else
        fail "AI_SETUP_LANES.md stale reviewer-model reference(s):$bad"
    fi
}

test_readme_reviewer_is_gpt56() {
    local F="$REPO_ROOT/README.md"
    if [ ! -f "$F" ]; then fail "README.md not found"; return; fi
    local bad=""
    # L174 is the fallback-chain line: must name "5\.6" AND BOTH Sol and Terra.
    # (Re-pinned 2026-08-16 by #544's frontier-model banner, twice on
    # 2026-08-26 by the opus-4.6 dist-tag install block, and twice more
    # the same day by the stability-lanes banner and its review repairs —
    # a position pin, not content — see #659, which keeps accumulating
    # evidence.)
    bad="$bad$(_check_line_has_and_lacks "$F" 163 "5\.6,Sol,Terra" "5\.5" "5\.4")"
    # Every OTHER line naming a GPT-5.x reviewer must name 5.6, by CONTENT —
    # EXCEPT the Reliable lane banner which legitimately names GPT-5.5 as its
    # first brain. The Reliable lane uses 5.5; Bleeding edge uses 5.6.
    local stale
    stale="$(grep -n 'GPT-5\.' "$F" | grep -v 'GPT-5\.6' | grep -v 'GPT-5\.5.*Fable 5\.1\|GPT-5\.5 review' || true)"
    [ -n "$stale" ] && bad="$bad$(printf ' stale-GPT-line:%s' "$(printf '%s' "$stale" | cut -d: -f1 | tr '\n' ',')")"
    grep -q 'GPT-5\.6 Sol' "$F" || bad="$bad README.md(no-sol-reference-at-all)"
    if [ -z "$bad" ]; then
        pass "README.md: all reviewer-model lines reference GPT-5.6 Sol/Terra, none reference stale GPT-5.5/5.4"
    else
        fail "README.md stale reviewer-model reference(s):$bad"
    fi
}

# The Vending-Bench line is a historical eval citation (Andon Labs actually ran
# GPT-5.5 at the time) — it must NOT be rewritten to 5.6, or the citation
# becomes factually wrong about what model that benchmark run used. It lived in
# README until the model-selection research moved to AI_SETUP_LANES.md; the
# guard follows the content. Located by CONTENT, not line number, so moving it
# again cannot silently disable this check.
test_vending_bench_citation_untouched() {
    local F="$REPO_ROOT/AI_SETUP_LANES.md"
    if [ ! -f "$F" ]; then fail "AI_SETUP_LANES.md not found"; return; fi
    local line
    line="$(grep -n 'Vending-Bench' "$F" | head -1)"
    if [ -z "$line" ]; then
        fail "Vending-Bench citation not found in AI_SETUP_LANES.md — the historical citation was deleted or moved again"
    elif printf '%s' "$line" | grep -q "GPT-5\.5"; then
        pass "Vending-Bench citation still names GPT-5.5 (historical, untouched)"
    else
        fail "Vending-Bench citation no longer names GPT-5.5 — historical citation was rewritten"
    fi
}

test_wizard_doc_reviewer_is_gpt56() {
    local F="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$F" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    local bad=""
    # Content-anchored (2026-07-24): these two were hardcoded at 1091/1111
    # and broke again when the Opus 5 autocompact fix inserted lines above
    # them — the third such drift. Same failure mode already documented for
    # the fallback-chain pair below; applying the same remedy rather than
    # re-pinning numbers that will drift on the next insertion.
    bad="$bad$(_check_content_line_has_and_lacks "$F" "| Reviewer |" "5\.6,Sol" "5\.5")"
    bad="$bad$(_check_content_line_has_and_lacks "$F" "The Sonnet driver will drop some fine-grained self-review moves" "5\.6,Sol" "5\.5")"
    # Fallback-chain lines: must name "5\.6" AND BOTH Sol and Terra.
    # Content-anchored (not hardcoded line numbers) — this pair drifted
    # 3855->3863->3865->3867 across three separate insertions in one day
    # (2026-07-21) before being switched to anchors, since any earlier-in-
    # file edit shifts hardcoded numbers for content further down.
    # Re-anchored 2026-08-01 (4th drift of this pair): the previous anchor was
    # the sentence's rhetorical opener ("Use the best model at the deepest
    # reasoning"), which was rewritten when the Codex reviewer effort moved from
    # xhigh to high. Anchor on "This is your quality gate" instead — it states
    # the paragraph's PURPOSE rather than its current recommendation, so it
    # survives a change to the recommendation itself. That is the distinction
    # that keeps breaking here: anchor on what the text is FOR, not what it says.
    bad="$bad$(_check_content_line_has_and_lacks "$F" "This is your quality gate" "5\.6,Sol,Terra" "5\.5" "5\.4")"
    bad="$bad$(_check_content_line_has_and_lacks "$F" "Codex CLI picks up your OpenAI account" "5\.6,Sol,Terra" "5\.5" "5\.4")"
    if [ -z "$bad" ]; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md: all reviewer-model lines reference GPT-5.6 Sol/Terra, none reference stale GPT-5.5/5.4"
    else
        fail "CLAUDE_CODE_SDLC_WIZARD.md stale reviewer-model reference(s):$bad"
    fi
}

# The E2E benchmark critique is a historical audit citation — it really did run
# on GPT-5.4 — so a repo-wide model-name sweep must NOT "modernise" it.
#
# Anchored on content, not a line number. This was pinned to `sed -n '113p'` and
# broke the moment an unrelated five-line edit landed earlier in the file, which
# says nothing about the citation and everything about the anchor. A line number
# is not a property of the thing being asserted (GH #491, line-pinned assertions).
test_wizard_doc_e2e_audit_citation_untouched() {
    local F="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    local line
    if [ ! -f "$F" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    line=$(grep -h 'rated the benchmark methodology' "$F" 2>/dev/null)
    if [ -z "$line" ]; then
        fail "the E2E-benchmark audit citation is gone entirely — re-anchor this assertion, do not delete it"
    elif printf '%s' "$line" | grep -q "GPT-5\.4"; then
        pass "wizard doc E2E-audit citation still names GPT-5.4 (historical, untouched)"
    else
        fail "wizard doc E2E-audit citation no longer names GPT-5.4 — a historical citation was rewritten"
    fi
}

# Both copies (canonical + cowork) must move together — this is the exact
# doc-duplication-drift risk documented in project memory (v1.85.0: a
# protocol documented twice, fixed in only one copy).
test_skill_files_reviewer_is_gpt56() {
    local bad=""
    # Content-anchored 2026-07-24 (FOURTH drift of a hardcoded line number
    # in this file — the escalation-ladder codification shifted it again).
    bad="$bad$(_check_content_line_has_and_lacks "$REPO_ROOT/skills/sdlc/SKILL.md" "adversarial diversity" "5\.6,sol" "5\.5")"
    bad="$bad$(_check_content_line_has_and_lacks "$REPO_ROOT/cowork/skills/sdlc/SKILL.md" "adversarial diversity" "5\.6,sol" "5\.5")"
    if [ -z "$bad" ]; then
        pass "skills/sdlc/SKILL.md and cowork/skills/sdlc/SKILL.md both reference GPT-5.6 Sol reviewer"
    else
        fail "skill file(s) stale reviewer-model reference(s):$bad"
    fi
}

test_agents_md_reviewer_is_gpt56() {
    local bad=""
    bad="$bad$(_check_line_has_and_lacks "$REPO_ROOT/AGENTS.md" 16 "5\.6,Sol" "5\.5")"
    if [ -z "$bad" ]; then
        pass "AGENTS.md: lane summary references GPT-5.6 Sol reviewer"
    else
        fail "AGENTS.md stale reviewer-model reference(s):$bad"
    fi
}

test_claude_md_reviewer_is_gpt56() {
    local bad=""
    # Content-anchored, not line-anchored. A hardcoded line number here
    # false-PASSES: Codex demonstrated it by inserting a decoy line carrying
    # "GPT-5.6 Sol" at the pinned line and downgrading the real rule to 5.5 —
    # the assertion stayed green while guarding nothing. Anchor on the unique
    # phrase that identifies the rule itself.
    bad="$bad$(_check_content_line_has_and_lacks "$REPO_ROOT/CLAUDE.md" "cross-model safety check" "5\.6,Sol" "5\.5")"
    if [ -z "$bad" ]; then
        pass "CLAUDE.md: cross-model safety check references GPT-5.6 Sol reviewer"
    else
        fail "CLAUDE.md stale reviewer-model reference(s):$bad"
    fi
}

test_ai_setup_lanes_reviewer_is_gpt56
test_readme_reviewer_is_gpt56
test_vending_bench_citation_untouched
test_wizard_doc_reviewer_is_gpt56
test_wizard_doc_e2e_audit_citation_untouched
test_skill_files_reviewer_is_gpt56
test_agents_md_reviewer_is_gpt56
test_claude_md_reviewer_is_gpt56

# ────────────────────────────────────────────
# ROADMAP #440: unbacked "~5x less quota" claim removed; Sonnet 5 default
# effort is medium (CodeRabbit-tested), not the unsupported "high sweet spot"
# ────────────────────────────────────────────

# The "~5x less Max quota" figure was traced to commit ab6fc9c with zero
# supporting measurement (no source in the commit, CHANGELOG, ROADMAP, or
# review artifacts). It must not appear anywhere in live guidance — repo-wide
# sweep (Fable round-1 root-cause: a fixed file list misses stragglers), with
# variant phrasings ("5x less/lighter/fewer/lower") all caught.
# ROADMAP*.md/CHANGELOG.md/.reviews/ are historical record, intentionally
# excluded.
test_no_unbacked_5x_quota_claim() {
    # Codex round-1 catch: the claim also survives as rewordings — "fraction
    # of the quota cost", "far less quota" — not just the literal "5x". Ban
    # the whole unqualified-multiplier class.
    local hits
    hits=$(grep -rliE "5x (less|lighter|fewer|lower)|fraction of (Setup B's |the )?quota|far less quota" \
        "$REPO_ROOT" \
        --include="*.md" \
        --exclude="ROADMAP.md" --exclude="ROADMAP_ARCHIVE.md" \
        --exclude="CHANGELOG.md" \
        --exclude-dir=".reviews" --exclude-dir="node_modules" \
        --exclude-dir=".git" 2>/dev/null || true)
    if [ -z "$hits" ]; then
        pass "#440: no live-guidance file carries an unqualified quota-multiplier claim (repo-wide)"
    else
        fail "#440: unqualified quota-multiplier claim still present in: $(echo "$hits" | tr '\n' ' ')"
    fi
}

# Sonnet 5's documented default effort is medium — per CodeRabbit's testing
# (the same source already cited for the max-doubles-cost claim), confirmed
# independently by Fable + Codex xhigh 2026-07-12. Each live-guidance file
# must state the medium default in its own idiom.
test_sonnet5_default_effort_is_medium() {
    local bad=""
    grep -q 'medium` default' "$REPO_ROOT/AI_SETUP_LANES.md" \
        || bad="$bad AI_SETUP_LANES.md(driver-row)"
    grep -q 'Start at `medium`' "$REPO_ROOT/AI_SETUP_LANES.md" \
        || bad="$bad AI_SETUP_LANES.md(ladder)"
    grep -q 'Sonnet 5 at `medium` effort' "$REPO_ROOT/README.md" \
        || bad="$bad README.md(default-line)"
    # The per-model effort wall moved from README to AI_SETUP_LANES.md with the
    # rest of the model-selection research; the assertion followed it. README
    # still states the default in its own idiom (default-line, above).
    grep -q 'Sonnet 5: `medium` default' "$REPO_ROOT/AI_SETUP_LANES.md" \
        || bad="$bad AI_SETUP_LANES.md(effort-wall)"
    grep -q 'Sonnet 5: `medium` default' "$REPO_ROOT/SDLC.md" \
        || bad="$bad SDLC.md"
    grep -q 'Sonnet 5 `medium`' "$REPO_ROOT/skills/sdlc/SKILL.md" \
        || bad="$bad skills/sdlc/SKILL.md"
    grep -q 'Sonnet 5 `medium`' "$REPO_ROOT/cowork/skills/sdlc/SKILL.md" \
        || bad="$bad cowork/skills/sdlc/SKILL.md"
    grep -q 'Effort: `medium`' "$REPO_ROOT/skills/setup/SKILL.md" \
        || bad="$bad skills/setup/SKILL.md"
    grep -q 'Sonnet 5 (Simple/One-Off lane) | `medium`' "$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md" \
        || bad="$bad CLAUDE_CODE_SDLC_WIZARD.md(effort-table)"
    # Codex round-1 catch: presence-of-medium alone false-greens while a
    # contradictory high-default ladder survives elsewhere in the same repo
    # (README.md's lane table said "Sonnet 5, `high`→`xhigh`"). Repo-wide
    # absence check for the stale ladder shape.
    local stale
    stale=$(grep -rlE 'Sonnet 5,? .?high.?→' "$REPO_ROOT" \
        --include="*.md" \
        --exclude="ROADMAP.md" --exclude="ROADMAP_ARCHIVE.md" \
        --exclude="CHANGELOG.md" \
        --exclude-dir=".reviews" --exclude-dir="node_modules" \
        --exclude-dir=".git" 2>/dev/null || true)
    [ -n "$stale" ] && bad="$bad stale-high-ladder-in:$(echo "$stale" | tr '\n' ',')"
    if [ -z "$bad" ]; then
        pass "#440: Sonnet 5 default effort is medium in all live-guidance files (no stale high-ladder anywhere)"
    else
        fail "#440: Sonnet 5 medium default missing in:$bad"
    fi
}

# The "high is Sonnet 5's sweet spot" framing had no measurement behind it —
# CodeRabbit (the cited source) actually recommends medium. The two stale
# phrasings must be gone.
test_no_unsupported_sonnet5_sweet_spot() {
    local bad=""
    grep -q 'default and sweet spot' "$REPO_ROOT/AI_SETUP_LANES.md" \
        && bad="$bad AI_SETUP_LANES.md"
    grep -q 'is the tested sweet spot' "$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md" \
        && bad="$bad CLAUDE_CODE_SDLC_WIZARD.md"
    if [ -z "$bad" ]; then
        pass "#440: unsupported 'high sweet spot' framing removed"
    else
        fail "#440: unsupported 'high sweet spot' framing still present in:$bad"
    fi
}

# Guard: Opus 4.6's max-is-the-sweet-spot claim is a DIFFERENT, community-
# supported claim and must survive the #440 cleanup untouched.
test_opus46_max_sweet_spot_guard() {
    if grep -q '4\.6 is the only Opus where `max`' "$REPO_ROOT/AI_SETUP_LANES.md"; then
        pass "#440 guard: Opus 4.6 max sweet-spot claim survives (separate, supported claim)"
    else
        fail "#440 guard: Opus 4.6 max sweet-spot claim was collaterally removed from AI_SETUP_LANES.md"
    fi
}

test_no_unbacked_5x_quota_claim
test_sonnet5_default_effort_is_medium
test_no_unsupported_sonnet5_sweet_spot
test_opus46_max_sweet_spot_guard

# #440 follow-up (maintainer ask 2026-07-13): Setup A's two escalation axes and
# the advisor-failure fallback kept getting re-confused ("sonnet 5 xhigh? or
# high?" / "sometimes advisor fails then we need a sub agent remember").
# Both README and AI_SETUP_LANES must state, explicitly:
#   (a) model escalation SWAPS THE DRIVER (Opus 4.8 xhigh takes over) — it is
#       not a higher rung on Sonnet's effort ladder;
#   (b) when advisor() errors, the fallback is spawning a Fable subagent — the
#       check is never skipped (same rule the /sdlc skill already carries).
test_setup_a_escalation_and_advisor_fallback_explicit() {
    local bad=""
    grep -q 'takes over as driver' "$REPO_ROOT/AI_SETUP_LANES.md" \
        || bad="$bad AI_SETUP_LANES.md:driver-swap"
    grep -q 'spawn a Fable subagent' "$REPO_ROOT/AI_SETUP_LANES.md" \
        || bad="$bad AI_SETUP_LANES.md:advisor-fallback"
    # "Reading Setup A precisely" moved from README to AI_SETUP_LANES.md, so the
    # two prose assertions are made once, above, against the file that now
    # carries them. README keeps a POINTER, and the pointer is asserted here so
    # it cannot rot into a dead reference to prose that lives elsewhere.
    # The two checks must be BOUND TO EACH OTHER, not merely both true. Seat 1
    # (2026-08-17) showed the earlier pair was satisfiable by accident: a bare
    # `grep AI_SETUP_LANES.md README.md` is already true because of an
    # unrelated link elsewhere in the file, so the pointer could lose its link
    # entirely, or link to the wrong file, while the guard stayed green.
    # Requiring both facts in the SAME paragraph is what makes the second one
    # say something about the first.
    # The README pointer guard that lived here is DELETED, routed to #672
    # under the #530 rule: a guard whose review cost exceeds what it guards
    # goes to a follow-up rather than getting patched again. Four consecutive
    # P1 rounds on one sentence. Rounds 1-3 were one defect at narrowing scope
    # — assert a link exists in a REGION, which any sibling link satisfies on
    # the pointer's behalf. Round 4 changed the principle to check the
    # CONSTRUCT, closed that class, and opened a new one: the match ended
    # before the file boundary, so AI_SETUP_LANES.md.bak passed 137/0.
    #
    # The replacement is generic, not bespoke — assert every relative link
    # target in shipped markdown resolves to a file that exists. That is what
    # four rounds of one-sentence regex were reaching for. Deleted whole:
    # a surviving half re-seeds the region concept.

    # Negative half (Codex round-1 P1-3): positive assertions alone false-green
    # while the advisor-outage procedure still offers a "no advisor" path. The
    # outage section must route to the subagent fallback, never to skipping.
    local outage
    outage="$(sed -n '/^## When the Advisor Is Unavailable/,/^## [^W]/p' "$REPO_ROOT/AI_SETUP_LANES.md")"
    if [ -z "$outage" ]; then
        bad="$bad AI_SETUP_LANES.md:outage-section-missing"
    else
        printf '%s' "$outage" | grep -qiE 'no advisor|without the advisor' \
            && bad="$bad AI_SETUP_LANES.md:outage-still-offers-skip-path"
        printf '%s' "$outage" | grep -q 'Fable subagent' \
            || bad="$bad AI_SETUP_LANES.md:outage-missing-subagent-fallback"
    fi
    if [ -z "$bad" ]; then
        pass "Setup A: driver-swap escalation + advisor subagent fallback explicit in README and AI_SETUP_LANES"
    else
        fail "Setup A clarity missing:$bad"
    fi
}

test_setup_a_escalation_and_advisor_fallback_explicit

# #444 regression (repo's first external contribution — thanks @thejesh23):
# argument-hint in SKILL.md frontmatter must parse as a YAML STRING. Bare
# brackets parse as a flow sequence (the feedback skill's hint even parsed as
# an array wrapping a MAPPING, because of the inner colon), which Copilot CLI
# >=1.0.65 rejects — the skill silently vanishes from the command menu.
# Claude Code renders the accident by concatenation, so only a type check
# catches it. Two halves:
#   (a) parse every SKILL.md frontmatter (live skills + cowork copies) with
#       real YAML and assert the type;
#   (b) the wizard doc's example blocks and frontmatter table are copy-source
#       templates consumers inherit — every argument-hint example must show
#       the quoted form, or generated repos re-inherit the bug.
test_argument_hint_frontmatter_is_string() {
    local bad
    bad="$(python3 - "$REPO_ROOT" << 'PYEOF'
import glob, os, re, sys, yaml
root = sys.argv[1]
bad = []
files = sorted(glob.glob(os.path.join(root, 'skills', '*', 'SKILL.md')) +
               glob.glob(os.path.join(root, 'cowork', 'skills', '*', 'SKILL.md')))
for f in files:
    text = open(f).read()
    m = re.match(r'^---\n(.*?)\n---', text, re.S)
    if not m:
        bad.append(os.path.relpath(f, root) + '(no-frontmatter)')
        continue
    fm = yaml.safe_load(m.group(1))
    if 'argument-hint' in fm and not isinstance(fm['argument-hint'], str):
        bad.append(os.path.relpath(f, root) + '(argument-hint-not-string)')
if not files:
    bad.append('no-SKILL.md-files-found')
print(' '.join(bad))
PYEOF
)"
    # [[:space:]]* not a literal single space — Codex round-1 P1: 'argument-hint:['
    # and 'argument-hint:  [' carry the same flow-sequence bug and must not evade.
    local unquoted
    unquoted="$(grep -nE 'argument-hint:[[:space:]]*\[' "$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md" | cut -d: -f1 | tr '\n' ',')"
    [ -n "$unquoted" ] && bad="$bad CLAUDE_CODE_SDLC_WIZARD.md:${unquoted%,}(unquoted-example)"
    if [ -z "${bad// /}" ]; then
        pass "#444: argument-hint parses as a string in every SKILL.md; all wizard-doc examples quoted"
    else
        fail "#444 regression:$bad"
    fi
}

# #374: setup/update skill names collided with opencode-sdlc-wizard's own
# identically-named skills under OpenCode (which reads multiple skill trees
# by `name:`, not by directory) — causing non-deterministic wrong-wizard
# resolution. Fix: namespace the frontmatter name + live dispatch string.
# ROADMAP*.md/CHANGELOG.md/.reviews/ are historical record, intentionally
# excluded.
test_no_bare_setup_update_wizard_collision() {
    local bad=""
    grep -q "^name: claude-setup-wizard$" "$REPO_ROOT/skills/setup/SKILL.md" \
        || bad="$bad skills/setup/SKILL.md:name-not-namespaced"
    grep -q "^name: claude-update-wizard$" "$REPO_ROOT/skills/update/SKILL.md" \
        || bad="$bad skills/update/SKILL.md:name-not-namespaced"
    grep -q 'skill="claude-setup-wizard"' "$REPO_ROOT/hooks/sdlc-prompt-check.sh" \
        || bad="$bad hooks/sdlc-prompt-check.sh:dispatch-not-namespaced"

    local hits
    hits=$(grep -rlE '/(setup|update)-wizard\b' "$REPO_ROOT" \
        --include="*.md" --include="*.sh" --include="*.js" \
        --exclude="ROADMAP.md" --exclude="ROADMAP_ARCHIVE.md" \
        --exclude="CHANGELOG.md" \
        --exclude-dir=".reviews" --exclude-dir="node_modules" \
        --exclude-dir=".git" 2>/dev/null || true)
    [ -n "$hits" ] && bad="$bad bare-invocation-still-present-in:$(echo "$hits" | tr '\n' ',')"

    if [ -z "$bad" ]; then
        pass "#374: setup/update skill names namespaced (claude-setup-wizard / claude-update-wizard), no bare-name collision with opencode-sdlc-wizard remains"
    else
        fail "#374 regression:$bad"
    fi
}

test_no_bare_setup_update_wizard_collision

test_argument_hint_frontmatter_is_string

# Test: the wizard doc warns against the double-backgrounding bug (trailing
# `&` inside a Bash-tool command combined with run_in_background: true) —
# this bug recurred across multiple sessions before being documented here,
# producing a false "review complete" notification for a still-running
# codex process (see ROADMAP for the incident this codifies).
test_wizard_doc_warns_double_backgrounding() {
    local F="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$F" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    if grep -qi "double-backgrounds" "$F" && grep -qi "trailing \`&\`" "$F" && grep -qi "run_in_background" "$F"; then
        pass "wizard doc warns against combining trailing & with run_in_background: true (double-backgrounding bug)"
    else
        fail "wizard doc should warn against the double-backgrounding bug (trailing & + run_in_background: true)"
    fi
}

test_wizard_doc_warns_double_backgrounding

# Test: the wizard doc requires running shellcheck before requesting
# cross-model review — a real gap this repo hit directly 2026-07-21, when
# Codex's own review caught bugs shellcheck would have flagged for free
# (SC2181) that this repo's own mutation-verified test suite had missed.
test_wizard_doc_requires_shellcheck_before_review() {
    local F="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$F" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    if grep -qi "run \`shellcheck\`" "$F" && grep -qi "before requesting review" "$F"; then
        pass "wizard doc requires running shellcheck before requesting cross-model review"
    else
        fail "wizard doc should require running shellcheck on new/modified .sh files before requesting review"
    fi
}

test_wizard_doc_requires_shellcheck_before_review

# ────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────

echo ""
# The escalation ladder is a PROCESS CONTRACT that ships to every consumer
# repo. It was codified 2026-07-24 after the maintainer observed that both
# SKILL.md and the wizard doc encoded the WRONG ladder — the skill said
# "Research or try Codex; if still LOW, ASK USER" (skipping Fable entirely)
# and the wizard doc said plain "ASK USER" for LOW/FAILED/CONFUSED with no
# model rung at all. Agents followed what was written, so the human got
# asked things a model could settle.
#
# Guards ORDER (Fable before Codex before human), not mere presence — a
# ladder listing the right three names in the wrong order is the same bug.
test_escalation_ladder_order_and_threshold() {
    local ok=true
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    local COWORK="$REPO_ROOT/cowork/skills/sdlc/SKILL.md"
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    local HOOK="$REPO_ROOT/hooks/sdlc-prompt-check.sh"

    # TEN bypasses. Denylists failed 8x; a substring "allowlist" failed;
    # exact-equality-on-selected-rows failed too, because (a) the heading
    # match was a PREFIX so a decoy "## Confidence Check (reference table)"
    # got compared instead of the operative one, and (b) I stripped the
    # MEDIUM row before comparing — and MEDIUM covers "some uncertainty",
    # so it was a live direct-to-human route.
    #
    # Now: require EXACTLY ONE literal "## Confidence Check (REQUIRED)"
    # heading, extract only its table, and compare the COMPLETE table
    # (header, separator, and all five rows) by exact equality.
    local EXPECTED
    EXPECTED="| Level | Meaning | Action | Effort |
|-------|---------|--------|--------|
| HIGH (90%+) | Know exactly what to do | Present, proceed after approval | Model default |
| MEDIUM (60-89%) | Solid approach, some uncertainty | Present, highlight uncertainties | Model default |
| LOW (<60%) | Not sure | Escalate, don't ask ↓ | **escalate now** (per model, see above) |
| FAILED 2x | Something's wrong | Escalate, don't ask ↓ | **escalate now** |
| CONFUSED | Can't diagnose | Escalate, don't ask ↓ | **escalate now** |"

    for f in "$SKILL" "$COWORK"; do
        [ -f "$f" ] || { fail "missing $f"; return; }
        local n_head
        n_head=$(grep -cE '^## Confidence Check' "$f")
        [ "$n_head" -eq 1 ] || ok=false
        grep -qxF '## Confidence Check (REQUIRED)' "$f" || ok=false
        local actual
        actual=$(awk '/^## Confidence Check \(REQUIRED\)/{f=1;next} f&&/^\|/{print;s=1;next} f&&s&&!/^\|/{exit}' "$f")
        [ "$actual" = "$EXPECTED" ] || ok=false
    done

    # Global invariants on every shipped surface
    for f in "$SKILL" "$COWORK" "$DOC"; do
        grep -qiE 'Uncertainty ≠ a human question|Never ask the (user|human) what a model can settle|Ask a human only for what no model can settle' "$f" || ok=false
        grep -qiE 'Confidence is not authorization' "$f" || ok=false
        grep -qiE 'merge protections are non-overridable' "$f" || ok=false
    done

    # ---- LIMITS OF THIS TEST (stated, not implied) --------------------
    # What it PROVES: the canonical Confidence Check table is byte-exact in
    # both shipped skill copies (Codex verified even a ↓ -> ⇩ swap fails), and
    # a set of KNOWN direct-to-human regressions is absent.
    #
    # What it CANNOT prove: that no shipped surface anywhere routes generic
    # uncertainty to a human. Codex demonstrated three bypasses of the prose
    # scan across rounds 5-6 — a greedy strip consuming a semicolon-separated
    # instruction, a SECOND table added after the canonical one, and a
    # Cyrillic homoglyph ("АSK USER", U+0410). Its conclusion, and mine: "a
    # growing regex strip/match list cannot certify the semantic universal."
    #
    # So: green here means the canonical table is intact and the known
    # regressions are gone. It does NOT mean the property holds globally.
    # That remainder belongs to cross-model review, not to this regex.
    # -------------------------------------------------------------------
    # Generic uncertainty/failure must never route to a human. The exemption
    # binds to the ACTION LINE ITSELF (deploy/production/approval/authz),
    # NOT to the surrounding window — Codex round 5 defeated a window-wide
    # negation exemption with "rather than continue troubleshooting, ASK
    # USER immediately". Nearby words can no longer launder a real
    # instruction. "Ask the human" is now recognized too.
    for f in "$SKILL" "$COWORK" "$DOC" "$REPO_ROOT/README.md"; do
        [ -f "$f" ] || continue
        if awk '
          { w[NR%3]=$0 }
          {
            cur = w[NR%3]
            # Strip KNOWN-GOOD phrasings out of the line FIRST, then scan the
            # remainder. A line-wide exemption is launderable: Codex round 5
            # hid "ASK USER immediately" on a line that also contained a
            # benign "ask the user only if". Removing the benign phrases and
            # re-scanning means a real instruction beside one still trips.
            gsub(/not\*{0,2} mean[^"]{0,3}"?ask the user[^"]*"?/, "", cur)
            gsub(/ask the user only (if|when|after)[^.;]*/, "", cur)   # [^.;] — a greedy [^.]* swallowed a semicolon-separated real instruction (Codex round 6)
            gsub(/not straight to the user/, "", cur)
            win = w[(NR-2)%3] "\n" w[(NR-1)%3] "\n" cur
            if (cur ~ /(ASK USER|[Aa]sk user|[Aa]sk the user|[Aa]sk the human|Must ask|must ask|STOP and ASK|asks for help|ASKS YOU|asks for clarification)/ &&
                cur !~ /(deploy|production|prod |approval|authoriz)/ &&
                win ~ /(LOW|[Ll]ow confidence|MEDIUM|FAILED|[Ss]till failing|[Ss]tuck|2 failed|2 attempts|uncertain)/ &&
                cur !~ /(≠|non-overridable)/)
              print FILENAME ":" NR
          }' "$f" | grep -q .; then ok=false; fi
    done

    if [ -f "$HOOK" ]; then
        grep -qE 'LOW confidence\? ASK USER' "$HOOK" && ok=false
        grep -qiE 'confidence is not authorization' "$HOOK" || ok=false
    fi

    if $ok; then
        pass "Escalation invariant: canonical Confidence Check table byte-exact in both skills; known direct-to-human regressions absent (see LIMITS in this test — it does NOT certify the global property)"
    else
        fail "Escalation contract broken — each skill must have exactly one '## Confidence Check (REQUIRED)' whose COMPLETE table (header + HIGH + MEDIUM + LOW + FAILED 2x + CONFUSED) matches the canonical table exactly, and no shipped surface may carry a direct-to-human action line on a generic uncertainty/failure trigger (only deploy/approval/authorization actions are exempt)"
    fi
}
test_escalation_ladder_order_and_threshold


# --- Parallel blind dual review (ROADMAP #469) ---
# Two reviewers must run BLIND AND IN PARALLEL, with findings merged afterwards.
# Sequencing them anchors the second reviewer on the first's output: measured
# 2026-07-27, the parallel round produced findings that barely overlapped while
# sequential rounds overlapped heavily.
test_parallel_blind_dual_review() {
    local WIZARD="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    local SECTION
    # Heading DEPTH is not the contract; the section's existence and content are.
    # GH #513 promoted this out of the Step 6 skill template into document-level
    # policy, which nested it one level deeper (### -> ####). Matching a fixed
    # depth would have failed on a change that strictly improved the doc, so the
    # pin now accepts either and terminates on a sibling-or-shallower heading.
    # The title is anchored end-to-end and the terminator depth is DERIVED from
    # whatever depth actually matched, not hardcoded. Without the end anchor a
    # future "### Parallel Blind Dual Review — deprecated" section would satisfy
    # the pin; with a hardcoded `^#{1,4} ` terminator a ##### subsection inside
    # the section would truncate it and the content checks below would pass on a
    # fragment.
    SECTION=$(awk '
        !f && /^#+ Parallel Blind Dual Review[[:space:]]*$/ {
            match($0, /^#+/); depth = RLENGTH; f = 1; next
        }
        f && /^#+ / { match($0, /^#+/); if (RLENGTH <= depth) { f = 0 } }
        f
    ' "$WIZARD")

    if [ -n "$SECTION" ]; then
        pass "wizard doc has a Parallel Blind Dual Review section"
    else
        fail "wizard doc is missing the Parallel Blind Dual Review section"
        return
    fi

    local req
    for req in blind parallel merge; do
        if printf '%s' "$SECTION" | grep -qi "$req"; then
            pass "dual-review section covers '$req'"
        else
            fail "dual-review section never mentions '$req'"
        fi
    done

    # Without the rationale a reader will "optimise" this back into a
    # sequential pipeline to save wall-clock, losing the only property it has.
    if printf '%s' "$SECTION" | grep -qiE "anchor|independen"; then
        pass "dual-review section explains why blindness matters"
    else
        fail "dual-review section omits WHY blindness matters — it will be optimised away"
    fi

    # Most consumers have one model, not two.
    if printf '%s' "$SECTION" | grep -qiE "one model|single|only have"; then
        pass "dual-review section gives a single-model fallback"
    else
        fail "dual-review section assumes two models with no fallback"
    fi
}
test_parallel_blind_dual_review

# ────────────────────────────────────────────
# E2E runbook: ordered lists must actually be ordered
# ────────────────────────────────────────────
# The runbook is not prose — it is a prompt pasted verbatim into another model,
# which then executes each numbered item as a step. A duplicate number is a
# skipped step. Found 2026-08-01: Step 5c ran 1,2,3,4,4,5, and the second "4"
# was the in-flight case — the single check that v1.90.0's Stop-hook fix exists
# to prove, and the one thing no static test can cover.
#
# Deliberately generic (every contiguous run of "N. " lines must count 1..N)
# rather than pinned to Step 5c. Line-number and section-name anchors in this
# file have drifted four times; a structural rule cannot drift.
# The rule, factored out so it can be run against fixtures rather than only
# against the real file. A rule that is only ever pointed at a passing document
# is indistinguishable from one that always passes — see ROADMAP #490.
#
# A run of numbered items ends at a markdown heading and NOWHERE else. Indented
# continuation lines, blank lines and blockquotes all sit INSIDE a list, so they
# must not reset the counter — a first draft reset on every non-matching line
# and reported 10 false positives.
#
# There is deliberately NO "restart at 1" branch. Codex xhigh found that an
# unconditional `n == 1` restart silently certifies `1,2,1,2` under a single
# heading, which is one malformed list in Markdown, not two lists. Since a run
# only ever begins after a heading (where prev is already 0), `n == prev + 1`
# covers the legitimate case on its own and the restart branch bought nothing
# but the hole.
#
# SCOPE, deliberately narrow. This rule models ATX headings, backtick fences,
# and top-level ordered lists — nothing else. It does NOT model blockquotes,
# tilde fences, or setext headings. That is safe ONLY because
# test_e2e_runbook_uses_only_modelled_constructs below fails LOUDLY the moment
# the runbook contains one of them.
#
# Why it was cut back: across three review rounds, every new silent false green
# was a direct child of the previous round's fix — blockquote support introduced
# a fence/quote-ordering bug, whose fix introduced two more (fences don't carry a
# depth). The rule was reimplementing CommonMark block structure to guard ONE
# file whose structure this repo controls. Fable's call, adopted: an allowlist
# converts every unknown parser gap from a silent pass into a loud failure,
# permanently. Generality was the thing given up, and the runbook never needed it.
#
# CommonMark permits up to THREE leading spaces before a list marker, so a
# column-1-only regex silently stops guarding an indented list. Codex found this
# with the fixture "# H / '   1. first' / '   3. skipped'", which produced zero
# output. Four leading spaces is an indented code block in CommonMark, not a
# list, so 0-3 is the correct bound.
#
# Fence-aware. Fable found the decisive false green: a ```bash fence containing a
# column-1 `#` comment made the heading rule fire, resetting the counter and
# silently certifying a malformed restart across the fence. The E2E runbook is
# precisely a document that interleaves numbered steps with bash fences, so that
# was its native failure shape, not a corner case. Content inside a fence is not
# Markdown structure and is skipped entirely.
#
# Both CommonMark ordered-list delimiters are recognised, `.` and `)`. A run is
# keyed by its delimiter so "1." and "1)" are not treated as one sequence.
misnumbered_ordered_items() {
    awk '
        # Track the OPENING fence character and length; close only on a matching
        # run of the same character, at least as long. A blind toggle flips on a
        # ~~~ that is merely CONTENT inside a ``` fence, and then swallows the
        # real document — Fable demonstrated a misnumbered list going silent that
        # way. Same length-matched-backreference lesson as the fence handling in
        # scripts/merge-pr.sh.
        /^ {0,3}(```+|~~~+)/ {
            fl = $0; sub(/^ {0,3}/, "", fl)
            fc = substr(fl, 1, 1); fn = 0
            while (substr(fl, fn + 1, 1) == fc) fn++
            rest = substr(fl, fn + 1)
            # A CLOSING fence carries no info string. "```still-code" inside a
            # fence is CONTENT, not a close — Codex found the blind version
            # desyncing on exactly that and swallowing a misnumbered list.
            has_info = (rest ~ /[^ \t]/)
            if (!infence)                       { infence = 1; fchar = fc; flen = fn }
            else if (fc == fchar && fn >= flen && !has_info) { infence = 0 }
            next
        }
        infence { next }
        /^#/ { prev = 0; delim = ""; next }             # a heading ends the list
        # CommonMark separates the marker from content with a space OR a tab.
        /^ {0,3}[0-9]+[.)][ \t]/ {
            n = $1 + 0                                  # $1 ignores leading whitespace
            d = ($1 ~ /\)/) ? ")" : "."
            if (d != delim) { delim = d; prev = 0 }     # a different marker starts a new run
            if (n == prev + 1) { prev = n; next }
            printf "line %d: expected %d%s but found %d%s\n", NR, prev + 1, d, n, d
            prev = n
        }
    ' "$1"
}

# The runbook is a paste-able PROMPT: every step lives inside one outer ```
# envelope, so feeding the file straight to the rule made fence-skipping swallow
# the whole document — vacuous for three review rounds, caught by Codex mutating
# a real step. The rule stays generic; this knows the guarded file's shape.
runbook_prompt_body() {
    sed '1,/^```/d; /^```/,$d' "$1"
}

# Self-test the rule against fixtures BEFORE trusting its verdict on the runbook.
test_ordered_list_rule_detects_defects() {
    local tmp
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/ordered-list-rule-XXXXXX") || { fail "could not create a temp dir for the ordered-list rule fixtures"; return; }
    # Never fall back to the working tree: a fixture that writes into the repo
    # corrupts real files (this bit us once already).
    case "$tmp" in
        /*) ;;
        *) fail "refusing to run ordered-list fixtures outside an absolute temp dir"; return ;;
    esac

    printf '# H\n1. a\n2. b\n3. c\n' > "$tmp/good.md"
    printf '# H\n1. a\n2. b\n1. restart\n2. after\n' > "$tmp/restart.md"
    printf '# H\n1. a\n2. b\n2. dupe\n' > "$tmp/dupe.md"
    printf '# H\n1. a\n2. b\n# H2\n1. a\n2. b\n' > "$tmp/two-lists.md"
    # Indented lists — CommonMark allows 0-3 leading spaces. Both fixtures added
    # after Codex proved the column-1-only rule accepted the defective one silently.
    printf '# H\n   1. first\n   3. skipped\n' > "$tmp/indented-bad.md"
    printf '# H\n   1. first\n   2. second\n' > "$tmp/indented-good.md"
    # Four spaces is an indented CODE BLOCK, not a list — must NOT be parsed.
    printf '# H\n    1. code\n    9. code\n' > "$tmp/code-block.md"
    # Fable's decisive fixture: a fenced bash comment must NOT reset the counter.
    printf '# H\n1. a\n2. b\n```bash\n# a comment\n```\n1. restart\n2. x\n' > "$tmp/fence-restart.md"
    # Numbered lines INSIDE a fence are code, not list items — must be ignored.
    printf '# H\n```\n1. one\n7. seven\n```\n' > "$tmp/fence-contents.md"
    # `)` is a valid CommonMark ordered-list delimiter.
    printf '# H\n1) a\n3) skipped\n' > "$tmp/paren-bad.md"
    printf '# H\n1) a\n2) b\n' > "$tmp/paren-good.md"
    # Fable round 2: a ~~~ inside a ``` fence is CONTENT. A blind toggle would
    # flip on it and then swallow the rest of the document, hiding real defects.
    printf '# H\n```\ncode\n~~~\ncode\n```\n1. a\n3. skipped\n' > "$tmp/fence-mixed.md"
    # Same class with a longer backtick run closing a shorter opener.
    printf '# H\n````\ncode\n```\ncode\n````\n1. a\n3. skipped\n' > "$tmp/fence-len.md"
    # Codex round 2: a fence line carrying an info string cannot be a CLOSE.
    printf '# H\n```\ncode\n```still-code\ncode\n```\n1. a\n3. skipped\n' > "$tmp/fence-info.md"
    # CommonMark allows a TAB between the marker and the content.
    printf '# H\n1.\tfirst\n3.\tskipped\n' > "$tmp/tab-sep.md"
    # Fable round 3: blockquoted lists were entirely invisible.

    if [ -z "$(misnumbered_ordered_items "$tmp/good.md")" ]; then
        pass "ordered-list rule: accepts a well-formed 1,2,3 list"
    else
        fail "ordered-list rule: false positive on a well-formed list"
    fi

    if [ -n "$(misnumbered_ordered_items "$tmp/restart.md")" ]; then
        pass "ordered-list rule: rejects a 1,2,1,2 restart under one heading (the Codex P1)"
    else
        fail "ordered-list rule: FALSE GREEN — 1,2,1,2 under one heading was accepted"
    fi

    if [ -n "$(misnumbered_ordered_items "$tmp/dupe.md")" ]; then
        pass "ordered-list rule: rejects a duplicated number (the original Step 5c defect)"
    else
        fail "ordered-list rule: FALSE GREEN — a duplicated number was accepted"
    fi

    if [ -z "$(misnumbered_ordered_items "$tmp/two-lists.md")" ]; then
        pass "ordered-list rule: two separate lists split by a heading both start at 1"
    else
        fail "ordered-list rule: false positive on two legitimately separate lists"
    fi

    if [ -n "$(misnumbered_ordered_items "$tmp/indented-bad.md")" ]; then
        pass "ordered-list rule: rejects a misnumbered list indented 3 spaces (the Codex P1)"
    else
        fail "ordered-list rule: FALSE GREEN — a misnumbered indented list was accepted"
    fi

    if [ -z "$(misnumbered_ordered_items "$tmp/indented-good.md")" ]; then
        pass "ordered-list rule: accepts a well-formed list indented 3 spaces"
    else
        fail "ordered-list rule: false positive on a well-formed indented list"
    fi

    if [ -z "$(misnumbered_ordered_items "$tmp/code-block.md")" ]; then
        pass "ordered-list rule: ignores 4-space indentation (a code block, not a list)"
    else
        fail "ordered-list rule: parsed an indented code block as a list"
    fi

    if [ -n "$(misnumbered_ordered_items "$tmp/fence-restart.md")" ]; then
        pass "ordered-list rule: a fenced '#' comment does not reset the counter (the Fable P2)"
    else
        fail "ordered-list rule: FALSE GREEN — a fenced '#' comment reset the run and hid a restart"
    fi

    if [ -z "$(misnumbered_ordered_items "$tmp/fence-contents.md")" ]; then
        pass "ordered-list rule: numbered lines inside a fence are code, not list items"
    else
        fail "ordered-list rule: linted numbered lines inside a fenced code block"
    fi

    if [ -n "$(misnumbered_ordered_items "$tmp/paren-bad.md")" ]; then
        pass "ordered-list rule: rejects a misnumbered ')' -delimited list"
    else
        fail "ordered-list rule: FALSE GREEN — ')' -delimited lists were invisible"
    fi

    if [ -z "$(misnumbered_ordered_items "$tmp/paren-good.md")" ]; then
        pass "ordered-list rule: accepts a well-formed ')' -delimited list"
    else
        fail "ordered-list rule: false positive on a well-formed ')' list"
    fi

    if [ -n "$(misnumbered_ordered_items "$tmp/fence-mixed.md")" ]; then
        pass "ordered-list rule: a '~~~' inside a backtick fence is content, not a close"
    else
        fail "ordered-list rule: FALSE GREEN — mixed fence chars desynced the parser and hid a defect"
    fi

    if [ -n "$(misnumbered_ordered_items "$tmp/fence-len.md")" ]; then
        pass "ordered-list rule: a SHORTER backtick run cannot close a longer fence"
    else
        fail "ordered-list rule: FALSE GREEN — a short run closed a longer fence and desynced the parser"
    fi

    if [ -n "$(misnumbered_ordered_items "$tmp/fence-info.md")" ]; then
        pass "ordered-list rule: a fence line with an info string is not a close (the Codex R2 P1)"
    else
        fail "ordered-list rule: FALSE GREEN — an info-string line closed the fence and desynced the parser"
    fi

    if [ -n "$(misnumbered_ordered_items "$tmp/tab-sep.md")" ]; then
        pass "ordered-list rule: tab-separated list markers are parsed (the Codex R2 P1)"
    else
        fail "ordered-list rule: FALSE GREEN — tab-separated markers were invisible"
    fi

    # Blockquote fixtures deliberately REMOVED, not fixed. The parser no longer
    # models blockquotes at all; test_e2e_runbook_uses_only_modelled_constructs
    # rejects them in the guarded document instead. Attempting to model them is
    # what produced three consecutive rounds of silent false greens.

    rm -rf "$tmp"
}
test_ordered_list_rule_detects_defects

# ────────────────────────────────────────────
# Codex reviewer effort — the value that actually controls the reviewer
# ────────────────────────────────────────────
# Maintainer decision 2026-08-01: run the Codex cross-model reviewer at `high`,
# not `xhigh`. Rationale is cost and review-noise, not capability.
#
# Asserts on `model_reasoning_effort=` ONLY — the flag that actually reaches the
# CLI. Deliberately NOT a prose sweep for the word "xhigh": the wizard doc also
# records past audits that genuinely ran at xhigh (e.g. the GPT-5.4 benchmark
# audit), and rewriting history to match a current default would be worse than
# the drift this guards against.
#
# Note the guidance this replaces claimed "testing showed xhigh caught 3 findings
# that high missed" — added 2026-03-26 against GPT-5.4, two reviewer generations
# ago, with no measurement artifact. It was never evidence.
# Two independent legs, because the first two designs both false-greened:
#
#   v1 checked `model_reasoning_effort=` in 4 .md files. Codex: five shipped
#      surfaces still said xhigh and it passed anyway.
#   v2 added a prose check with an `escalat` exclusion. Fable: README.md
#      shipped "OpenAI/Codex reviewer: `xhigh` default — escalate to `max`" and
#      the exclusion suppressed it. Same defect class, one round later. v2 also
#      globbed only .md, so it could not see scripts/codex-review-with-progress.sh
#      — the ONLY executable reviewer path — which still hardcoded xhigh.
#
# v3 stops trying to exclude legitimate MENTIONS of xhigh. Documenting the change
# means nearly every relevant line now mentions it, so mention-based matching
# cannot discriminate and any exclusion list becomes a hole. Instead:
#
#   Leg A — the executable truth. EVERY model_reasoning_effort= in the repo
#           (any file type, tests and archives excluded) must be "high".
#   Leg B — a denylist of DEFAULT-ASSERTING phrasings. These are the shapes a
#           regression actually takes; "escalate to `xhigh` for risky PRs" is
#           not among them, so the documented exception needs no exclusion.
# DRIVER effort, which is a different decision from reviewer effort and had no
# guard at all until now — `codex review --uncommitted` caught a ROADMAP row
# claiming the driver default had changed when only the reviewer layer had.
#
# Maintainer decision 2026-08-02: "the shipped driver default should be high for
# complex projects, medium for average WebDev stuff." Positive anchors on the two
# lines that DEFINE the default, per Fable's recommendation — assert what the
# defining lines say rather than denylisting phrasings, which is the arms race
# ROADMAP #495 exists to end.
test_driver_effort_default_is_high_not_xhigh() {
    local bad=""
    # Setup A's driver row in the lanes table.
    # POSITIVE anchors only. An earlier version also required the line to LACK
    # 'xhigh' and therefore rejected its own correct replacement, because the line
    # legitimately names xhigh as the ESCALATION path. Denylisting a token that
    # has a valid use is the same mistake ROADMAP #495 exists to end — assert what
    # the defining line must SAY, and a revert to xhigh-as-default fails that.
    bad="$bad$(_check_content_line_has_and_lacks "$REPO_ROOT/AI_SETUP_LANES.md" \
        '| \*\*Builder\*\* | Opus 5' '\`high\`')"
    if ! grep -qE 'Recommended: Opus 4\.6\[1m\] `max`' "$REPO_ROOT/skills/sdlc/SKILL.md"; then
        bad="${bad}${REPO_ROOT}/skills/sdlc/SKILL.md:(Reliable default 'Opus 4.6[1m] max' not found)"
    fi

    # Repo-wide backstop. Codex caught driver-default contradictions in THREE
    # consecutive rounds — README, a lane table, a quota line, then two more in
    # the wizard doc — every time because the guard checked only the anchors I
    # had just edited. Positive anchors alone cannot see a surface nobody
    # thought to list, so this scans every shipped file for the assertion shape
    # itself: "Opus 5" and xhigh adjacent, inside one sentence or table cell,
    # without an escalation qualifier.
    # Per-CELL, not per-line. Four separate exclusion attempts created holes here
    # because the match is cell-scoped while a `grep -v` is line-scoped: one lane's
    # legitimate cell ("Plan Mode", "escalate to xhigh") suppressed the whole table
    # row, hiding a contradiction in a different lane's cell. Awk splits on | and
    # judges each cell on its own, so a qualifier can only exempt the cell it is in.
    local f wide
    for f in README.md AI_SETUP_LANES.md CLAUDE_CODE_SDLC_WIZARD.md SDLC.md CLAUDE.md \
             skills/sdlc/SKILL.md skills/setup/SKILL.md skills/update/SKILL.md; do
        [ -f "$REPO_ROOT/$f" ] || continue
        wide=$(awk -F'|' '
            {
                n = (NF > 1) ? NF : 1
                for (c = 1; c <= n; c++) {
                    cell = (NF > 1) ? $c : $0
                    if (cell !~ /Opus 5/ || cell !~ /xhigh/) continue
                    lc = tolower(cell)
                    if (lc ~ /escalat|only as|not the default|changed 2026|previously|historical|plan mode|opusplan|setup c/) continue
                    printf "%d: %s\n", NR, cell
                }
            }' "$REPO_ROOT/$f" || true)
        [ -n "$wide" ] && bad="$bad
${f}: Opus 5 asserted at xhigh without an escalation qualifier:
$wide"
    done
    bad=$(printf '%s' "$bad" | sed '/^$/d')

    if [ -z "$bad" ]; then
        pass "driver effort default is \`high\` (complex) / \`medium\` (routine), not xhigh"
    else
        fail "driver effort default regressed — the defining lines must say high/medium and not xhigh:
$bad"
    fi
}
test_driver_effort_default_is_high_not_xhigh

# GH #483 — the shipped context guidance must name a WORKING CEILING and must
# require external verification past it. Both are cheap to state and both are
# backed by published work, so shipping neither was the actual defect.
#
# The rule this guards hardest is the external-review one, because it is the
# best-evidenced and the least intuitive: arXiv:2606.09863 measured agents
# asserting completion while environment state showed failure in 75.8% of
# FAILURES THAT CARRIED AN EXPLICIT STATUS CLAIM across two self-assessing
# AppWorld architectures — not of trajectories generally. LLM judges peaked at
# AUROC 0.65 on tau2-bench and ~0.54 on AppWorld, so a second model is a poor
# detector on its own; the paper points at environment-grounded checks AND
# calibrated detectors for triage. Operationally: run the test.
# The predicate, factored out so a COUNTERFEIT document can be run through the
# identical code path. The first version of this test only checked that certain
# tokens appeared somewhere; Codex demonstrated it passing against a document
# that said "Never work below 40%; external review is forbidden" and declared
# every cited paper false. Token presence is not meaning.
# SCOPE, STATED HONESTLY — this guards FIGURES, not MEANING.
#
# Two rounds of review broke the previous attempt in both directions at once: a
# token-complete document asserting the reverse of every rule still passed, and
# an honest paraphrase of a rule was rejected. That is not a bug in the regexes;
# it is what grep is. A text matcher cannot decide whether prose means what it
# says, and pretending otherwise produces a guard that blocks real edits while
# waving through reversed ones — the worst of both.
#
# So this now checks only what a matcher can decide reliably: that each CITED
# FIGURE is the corrected one. Those are exact, factual, and were wrong four
# times in one review round, which makes them worth pinning. Whether the
# surrounding prose still argues the right thing is a REVIEW question, and is
# left to review rather than faked here.
_context_guidance_defects() {   # $1=skill file  $2=wizard file
    local skill="$1" wiz="$2" bad=""

    # The two rules must exist in some form, matched loosely enough that
    # rewording does not break the build. Deliberately NOT anchored to exact
    # prose: an honest paraphrase must survive.
    # Loose enough that a rewording survives: any of several equivalent terms
    # satisfies each rule. Codex round 3 showed the previous version rejecting
    # honest paraphrases that said "context utilization" or "verify by running".
    grep -qiE '350K|occupancy|utilization|context (size|budget|window)' "$skill" \
        || bad="$bad skill:no-context-ceiling-rule"
    grep -qiE 'external review|external verification|run the test|verify by running' "$skill" \
        || bad="$bad skill:no-verification-rule"

    # Citations must carry the CORRECTED figures. Every one of these was wrong
    # in the first draft and found by cross-model review; pinning the numbers is
    # what stops a future edit from silently reintroducing a misquote.
    grep -q '11 of the 13 models evaluated' "$wiz" || bad="$bad wiz:NoLiMa-denominator"
    grep -q '99.3% → 69.7%' "$wiz" || bad="$bad wiz:NoLiMa-gpt4o"
    grep -q 'four families: Claude, GPT-3.5, MPT, LongChat' "$wiz" || bad="$bad wiz:LitM-families"
    grep -q '40-60% utilization depending on task complexity' "$wiz" || bad="$bad wiz:HumanLayer-range"
    # Check the FIGURES and the qualifier, not the sentence around them — the
    # previous version pinned prose and then false-rejected the very rewrite it
    # was guarding. The guarantee is "these numbers, correctly conditioned",
    # not "these words in this order".
    grep -q '45%' "$wiz" && grep -q '48%' "$wiz" || bad="$bad wiz:tau2-figures"
    grep -qiE 'failures?' "$wiz" || bad="$bad wiz:tau2-conditioning"
    grep -qi 'telecom' "$wiz" && grep -q '3%' "$wiz" || bad="$bad wiz:tau2-telecom-counterexample"
    grep -q 'carried an explicit status claim' "$wiz" || bad="$bad wiz:appworld-denominator"

    # DELIBERATELY NOT CHECKED: whether the doc frames the remedy correctly.
    # Two predicates here used to grep for "environment-grounded checks" and
    # "not a validated detector" — policing MEANING, which the scope note above
    # says this guard does not do. They promptly false-rejected an honest
    # rewrite of the very section they guarded. Framing is a review question.
    # What IS pinned: the AUROC figures, so the judge-reliability numbers
    # cannot silently drift.
    grep -q '0.65' "$wiz" && grep -q '0.54' "$wiz" || bad="$bad wiz:auroc-figures"

    # Provenance: ~350K is practitioner-reported, NOT benchmarked.
    grep -q 'practitioner-reported, not benchmarked' "$wiz" || bad="$bad wiz:no-provenance-caveat"

    printf '%s' "$bad"
}

test_context_ceiling_and_external_review_are_shipped() {
    local bad
    bad=$(_context_guidance_defects "$REPO_ROOT/skills/sdlc/SKILL.md" \
                                    "$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md")
    if [ -z "$bad" ]; then
        pass "context guidance: rules anchored, citation figures pinned, provenance honest"
    else
        fail "GH #483 guidance defective:$bad"
    fi
}

# NON-VACUITY CANARY, scoped to what the predicate actually claims to guard.
#
# An earlier version of this canary fed the predicate a document asserting the
# REVERSE of every rule and required rejection. It passed — but only because
# that counterfeit was crude. A reviewer then built a token-complete reversal
# that sailed through, proving the canary was testing its own clumsiness rather
# than the guard's strength. Claiming to detect reversed meaning was the error.
#
# This version tests the guarantee that is actually made: a document whose
# CITED FIGURES are wrong must be rejected. That is checkable, and it is the
# failure that actually occurred — four misquoted figures in one review round.
test_context_guidance_rule_is_not_vacuous() {
    local d; d=$(mktemp -d "${TMPDIR:-/tmp}/ctxguard.XXXXXX")
    # Rules present and correctly worded; only the FIGURES are wrong — the
    # regression this guard exists to catch, and the hardest to spot by eye.
    cat > "$d/skill.md" <<'FAKE'
- **Work under ~40-60% occupancy.** Compact at ~60%; autocompact (~95%) is too late.
- **Past ~50%, self-reported "fixed" needs external review** — agents assert done while state disagrees.
FAKE
    cat > "$d/wiz.md" <<'FAKE'
NoLiMa: 11 of 12 models fall below 50%. GPT-4o: 99.3% → 69.7%.
Lost in the Middle: six model families. HumanLayer: a dumb zone beginning at 40%.
45-48% on tau2-bench and 75.8% of self-assessing trajectories.
The ~350K figure is practitioner-reported, not benchmarked. Use environment-grounded checks.
This is **not** a validated detector.
FAKE
    local bad; bad=$(_context_guidance_defects "$d/skill.md" "$d/wiz.md")
    rm -rf "$d"
    if [ -n "$bad" ]; then
        pass "canary: a document carrying the ORIGINAL misquoted figures is rejected"
    else
        fail "VACUOUS — the guard accepts the exact wrong figures cross-model review caught"
    fi
}

# The other direction: an honest REWORDING of the rules, with correct figures,
# must NOT be rejected. A guard that blocks legitimate edits is a maintenance
# trap, and the previous version was one — it demanded exact prose.
test_context_guidance_allows_honest_rewording() {
    local d; d=$(mktemp -d "${TMPDIR:-/tmp}/ctxok.XXXXXX")
    cat > "$d/skill.md" <<'REAL'
- Keep sessions under ~350K tokens; compact well before autocompact fires.
- Verify by running the tests; a completion claim is not a test result.
REAL
    sed -n '/### Working context ceiling/,/^## /p' "$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md" > "$d/wiz.md"
    local bad; bad=$(_context_guidance_defects "$d/skill.md" "$d/wiz.md")
    rm -rf "$d"
    if [ -z "$bad" ]; then
        pass "reworded rules with correct figures are accepted (guard is not a prose lock)"
    else
        fail "FALSE REJECT — honest rewording refused:$bad"
    fi
}

test_context_ceiling_and_external_review_are_shipped
test_context_guidance_rule_is_not_vacuous
test_context_guidance_allows_honest_rewording

test_codex_reviewer_effort_is_high() {
    local offenders=""

    # Historical records by design — they describe what WAS run, and rewriting
    # them would falsify the record. Same principle as the GPT-5.4 citations.
    local _hist='/ROADMAP.md:|/ROADMAP_ARCHIVE.md:|/CHANGELOG.md:|/.reviews/|/tests/'

    # Leg A: the executable truth. Any invocation, any file type, live surfaces only.
    local flag_hits
    flag_hits=$(grep -rn 'model_reasoning_effort=' \
                    --include='*.md' --include='*.sh' --include='*.json' --include='*.yml' --include='*.yaml' --include='*.js' \
                    "$REPO_ROOT" 2>/dev/null \
                | grep -vE "$_hist" \
                | grep -v 'model_reasoning_effort="\?\(x\)\?high"\?' || true)
    [ -n "$flag_hits" ] && offenders="$offenders
INVOCATION at non-high effort:
$flag_hits"

    # Leg B: prose ASSERTING xhigh as the REVIEWER default. Reviewer keyword must
    # be within 40 chars of the claim, and [^.|] keeps it inside one sentence and
    # one table cell — driver-effort defaults (Opus 5 `xhigh`, Sonnet escalation)
    # live in different sentences and cells and must not trip this.
    # "escalate to `xhigh` for risky PRs" is not a default-assertion, so the
    # documented exception needs no exclusion list — that list was itself the
    # hole Fable found in v2.
    local prose_hits
    prose_hits=$(grep -rniE \
        '(sol|codex|reviewer)[^.|]{0,40}`?xhigh`?[^.|]{0,20}(default|non-negotiable|reasoning effort)|always `?xhigh`?|`?xhigh`? (is|remains) the (evidence-based )?default|`?xhigh`?[^.|]{0,30}non-negotiable|non-negotiable[^.|]{0,30}`?xhigh`?|(sol|codex|reviewer)[^.|]{0,40}(default|standard|baseline|required|mandatory)[^.|]{0,15}`?xhigh`?' \
        --include='*.md' --include='*.sh' --include='*.js' "$REPO_ROOT" 2>/dev/null \
        | grep -vE "$_hist" || true)
    [ -n "$prose_hits" ] && offenders="$offenders
PROSE asserting xhigh as the reviewer default:
$prose_hits"

    if [ -z "$offenders" ]; then
        pass "Codex reviewer runs at \"high\" in every invocation, and no shipped prose asserts xhigh as the default"
    else
        fail "reviewer effort regression:$offenders"
    fi
}
test_codex_reviewer_effort_is_high

# The allowlist that makes the narrow parser safe.
#
# Every silent false green in this guard's history came from a construct the
# parser did not model: blockquoted lists, blockquoted fences, tilde fences,
# info-string closes. Modelling each one in turn produced the next gap. This
# inverts it — the runbook may only use constructs the parser handles, and
# anything else fails LOUDLY here rather than passing silently there.
#
# If a future runbook edit legitimately needs one of these, that is a deliberate
# decision to extend the parser AND its fixtures, not an accident.
test_e2e_runbook_uses_only_modelled_constructs() {
    local runbook="$REPO_ROOT/tests/e2e/codex-cowork-install.md"
    [ -f "$runbook" ] || { fail "E2E runbook not found"; return; }

    local bad=""
    # Blockquoted list markers or fences — the source of rounds 3 and 4.
    bad="$bad$(grep -nE '^ {0,3}> *([0-9]+[.)][ \t]|(\`\`\`|~~~))' "$runbook" || true)"
    # Tilde fences — the parser tracks the opening char, but nothing exercises this.
    bad="$bad$(grep -nE '^ {0,3}~~~' "$runbook" || true)"
    # Setext underlines — would not reset the counter the way an ATX heading does.
    bad="$bad$(grep -nE '^ {0,3}(=+|-{3,}) *$' "$runbook" || true)"
    bad=$(printf '%s' "$bad" | sed '/^$/d')

    if [ -z "$bad" ]; then
        pass "E2E runbook uses only constructs the ordered-list rule models (no silent-gap surface)"
    else
        fail "E2E runbook uses a Markdown construct the ordered-list rule does NOT model — extend the parser and its fixtures, or rewrite these lines:
$bad"
    fi
}
test_e2e_runbook_uses_only_modelled_constructs

# CANARY — the assertion whose absence let the rule go vacuous for three rounds.
#
# Every other assertion here runs against synthetic fixtures, so all of them
# stayed green while the rule silently read NOTHING from the real runbook (its
# steps live inside an outer ``` envelope that fence-skipping swallowed whole).
# Fixtures prove the rule works on documents shaped like the fixtures. Only this
# proves it works on the document it actually guards.
test_e2e_runbook_rule_is_not_vacuous() {
    local runbook="$REPO_ROOT/tests/e2e/codex-cowork-install.md"
    [ -f "$runbook" ] || { fail "E2E runbook not found"; return; }

    local tmp
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/runbook-canary-XXXXXX") || {
        fail "could not create a temp dir for the runbook canary"; return; }
    local mutant="$tmp/mutant.md"

    # Duplicate the SECOND numbered item of the first real step — the same defect
    # class as the original Step 5c bug, injected into the genuine document.
    awk 'BEGIN{done=0} { if (!done && $0 ~ /^2\. /) { sub(/^2\. /, "1. "); done=1 } print }' \
        "$runbook" > "$mutant"

    if ! cmp -s "$runbook" "$mutant"; then
        runbook_prompt_body "$mutant" > "$tmp/body.md"
        if [ -n "$(misnumbered_ordered_items "$tmp/body.md")" ]; then
            pass "ordered-list rule reads the REAL runbook: a mutated step is detected (non-vacuity canary)"
        else
            fail "VACUOUS — the rule reports nothing for a deliberately misnumbered step in the real runbook. It is not reading the document it guards."
        fi
    else
        fail "runbook canary could not inject a mutation — the file shape changed; update this test"
    fi
    rm -rf "$tmp"
}
test_e2e_runbook_rule_is_not_vacuous

test_e2e_runbook_lists_are_sequential() {
    local runbook="$REPO_ROOT/tests/e2e/codex-cowork-install.md"

    if [ ! -f "$runbook" ]; then
        fail "E2E runbook not found at tests/e2e/codex-cowork-install.md"
        return
    fi

    local bad body
    body=$(mktemp "${TMPDIR:-/tmp}/runbook-body-XXXXXX") || { fail "temp file failed"; return; }
    runbook_prompt_body "$runbook" > "$body"
    bad=$(misnumbered_ordered_items "$body")
    rm -f "$body"

    if [ -z "$bad" ]; then
        pass "E2E runbook: every ordered list is sequentially numbered (no step can be silently skipped)"
    else
        fail "E2E runbook has misnumbered steps — a model executing it may skip one:
$bad"
    fi
}
test_e2e_runbook_lists_are_sequential

# ────────────────────────────────────────────
# CLAUDE.md must document every directory the package actually ships
#
# Found by /doctor cross-model review 2026-08-04: CLAUDE.md's "What This Repo
# Contains" listed `.claude/` and `tests/` but omitted `cli/`, `hooks/`, and
# `skills/` — the three directories in package.json's "files" list, i.e. the
# ones consumers actually receive. An agent reading CLAUDE.md would conclude
# the shipping surface was something other than what ships.
#
# Predicate is filesystem-driven, not a hardcoded list: add a directory to
# package.json "files" and this guard demands CLAUDE.md document it.
# ────────────────────────────────────────────

# The "Ships to consumers" block only. Scoping matters: an earlier version
# searched the WHOLE document, so moving `hooks/` into the "Repo-local only"
# list still satisfied it — a false PASS that inverted the very claim being
# guarded. Codex proved that with a fixture; do not widen this back out.
_ships_section() {
    awk '/^Ships to consumers/ {f=1; next} /^Repo-local only/ {f=0} f' "$1"
}

# Emits one line per package.json "files" entry absent from that block.
# Covers FILE entries too, not just directories — CLAUDE.md claims to mirror
# the files list, and an earlier dirs-only predicate could not see that
# CHANGELOG.md was missing. Match is on the backticked form (`cli/`) so
# incidental prose ("**Skills**: provide detailed guidance") does not count.
_shipped_entries_missing_from() {
    local claude_md="$1" pkg="$2" entry section
    [ -f "$claude_md" ] && [ -f "$pkg" ] || return 0

    section=$(_ships_section "$claude_md")
    if [ -z "$section" ]; then
        echo "(no 'Ships to consumers' section found)"
        return
    fi

    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        printf '%s\n' "$section" | grep -qF -- "\`$entry\`" || echo "$entry"
    done < <(jq -r '.files[]?' "$pkg")
}

test_claude_md_documents_shipped_entries() {
    local missing
    missing=$(_shipped_entries_missing_from "$REPO_ROOT/CLAUDE.md" "$REPO_ROOT/package.json")

    if [ -z "$missing" ]; then
        pass "CLAUDE.md's ships-to-consumers list matches package.json \"files\""
    else
        fail "CLAUDE.md omits shipped entries — agents will misread what this repo delivers:
$(echo "$missing" | sed 's/^/  missing: /')"
    fi
}
test_claude_md_documents_shipped_entries

# Non-vacuity canary against the REAL artifact, not a synthetic fixture.
# Mutation: relocate `hooks/` out of the ships block and into the repo-local
# block. The string is still present in the document, so a whole-document
# search would still pass — only correct section scoping catches this.
test_shipped_entries_predicate_is_not_vacuous() {
    local tmpdir mutated detected clean
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/shipped-entries-XXXXXX") || { fail "temp dir failed"; return; }
    mutated="$tmpdir/CLAUDE.md"

    clean=$(_shipped_entries_missing_from "$REPO_ROOT/CLAUDE.md" "$REPO_ROOT/package.json")

    awk '
        /^- `hooks\/`/            { held = $0; next }
        /^Repo-local only/        { print; if (held != "") { print held; held = "" } next }
                                  { print }
    ' "$REPO_ROOT/CLAUDE.md" > "$mutated"

    detected=$(_shipped_entries_missing_from "$mutated" "$REPO_ROOT/package.json")
    rm -rf "$tmpdir"

    if [ -z "$clean" ] && [ "$detected" = "hooks/" ]; then
        pass "ships-list predicate is section-scoped: relocating a shipped entry to the repo-local list is detected"
    else
        fail "ships-list predicate is vacuous or mis-scoped — real file returned '$clean' (want empty), relocated-hooks mutation returned '$detected' (want 'hooks/')"
    fi
}
test_shipped_entries_predicate_is_not_vacuous

# ────────────────────────────────────────────
# GH #486 — align shipped guidance with Anthropic's Opus 5 prompting guide.
#
# Three low-risk items. The fourth (deleting the same-model self-review layer)
# is coupled to the E2E scorer's must-pass list and five other suites, so it
# ships separately.
# ────────────────────────────────────────────

# (1) Concision must be stated ONCE, at CLAUDE.md level — never in SKILL.md or
# hook stdout. tests/test-postmortem-lessons.sh Test 4 already fails CI on
# brevity caps in those surfaces, because per-injection repetition compounds.
# The Opus 5 guide is the reason it belongs somewhere: "Claude Opus 5's default
# user-facing responses run longer than prior Opus models'... To control
# response length, prompt for it explicitly."
test_concision_guidance_shipped_once_at_the_right_level() {
    local doc="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    local bad=""

    grep -qiE 'lead with the outcome|response length|keep responses' "$doc" \
        || bad="$bad\n  wizard doc has no response-length guidance (Opus 5 defaults long; the guide says prompt for it explicitly)"

    # And it must NOT have leaked into the compounding surfaces.
    grep -qiE 'keep (responses|outputs) (focused|brief|concise)' "$REPO_ROOT/skills/sdlc/SKILL.md" 2>/dev/null \
        && bad="$bad\n  brevity cap leaked into skills/sdlc/SKILL.md — compounds per injection (test-postmortem-lessons.sh Test 4)"

    if [ -z "$bad" ]; then
        pass "#486: response-length guidance shipped once at CLAUDE.md level, not in SKILL.md"
    else
        fail "#486 concision guidance misplaced or missing:$(printf '%b' "$bad")"
    fi
}
test_concision_guidance_shipped_once_at_the_right_level

# (2) The per-push cross-model CI-log audit has exactly ONE recorded catch in
# the repo's history (PR #206, pre-existing CI infra). Running it on every push
# stacks a verification layer regardless of risk — the pattern the Opus 5 guide
# names. Scope it; keep the unconditional "read CI logs even on pass", which
# has independent evidence (v1.84.0: 3 real bugs found post-CERTIFIED).
test_ci_log_audit_is_risk_scoped_not_universal() {
    local skill="$REPO_ROOT/skills/sdlc/SKILL.md" line
    line=$(grep -n 'Cross-model audit the CI logs' "$skill" | head -1 | cut -d: -f2-)

    if [ -z "$line" ]; then
        fail "#486: the CI-log audit step vanished entirely — it should be SCOPED, not deleted"
        return
    fi

    if printf '%s' "$line" | grep -qiE 'release|workflow|control-plane|high-stakes'; then
        pass "#486: cross-model CI-log audit is scoped to risk, not run on every push"
    else
        fail "#486: cross-model CI-log audit still applies to every push — one recorded catch does not justify a per-push verification layer"
    fi
}
test_ci_log_audit_is_risk_scoped_not_universal

# (3) Two prompt tightens. The Opus 5 guide: a review prompt saying "only
# report high-severity issues" or "be conservative" makes the model report
# LESS, including real defects. Neither shipped line should read that way.
test_review_prompts_do_not_suppress_findings() {
    local skill="$REPO_ROOT/skills/sdlc/SKILL.md" bad=""

    # Preflight framed FEWER FINDINGS as the goal.
    grep -q 'Reduces reviewer findings to 0-1/round' "$skill" \
        && bad="$bad\n  preflight still frames fewer findings as the goal ('Reduces reviewer findings to 0-1/round')"

    # POSITIVE ANCHOR, not a search for removed wording. The first version
    # grepped for 'Do NOT expand the surface' — the exact phrase the fix
    # DELETES — so after the fix the grep found nothing, `recheck` was empty,
    # and the whole check was skipped. Cross-model review removed 'report every
    # defect' and the test still passed. It guarded nothing.
    #
    # Anchor on the recheck prompt itself (which must exist), then assert the
    # report-everything clause is IN it.
    local recheck
    recheck=$(grep -n 'TARGETED RECHECK' "$skill" | head -1 | cut -d: -f2-)
    if [ -z "$recheck" ]; then
        bad="$bad\n  the TARGETED RECHECK prompt is missing entirely — cannot verify it does not suppress findings"
    else
        printf '%s' "$recheck" | grep -qiE 'report every defect|every defect you see|report all findings' \
            || bad="$bad\n  the recheck prompt has no explicit report-everything clause — a scope limiter alone reads as severity suppression"
    fi

    if [ -z "$bad" ]; then
        pass "#486: no shipped review prompt frames fewer findings as success"
    else
        fail "#486 review prompts can suppress findings:$(printf '%b' "$bad")"
    fi
}
test_review_prompts_do_not_suppress_findings

# Every Markdown surface a consumer actually receives, derived from
# package.json's "files" plus README.md, which npm always packs whether or not
# it is listed. Verified against `npm pack --dry-run` (8 .md files). Derived
# rather than hand-listed for the same reason the hook roster is: a hand-listed
# set silently stops covering whatever nobody remembered to add.
# Sentence-level judge for both #491 doc guards. Line-level was wrong in BOTH
# directions: an affirmative claim appended to the canonical line inherited that
# line's denial credit, while an unrelated systemd watchdog sentence was blocked.
_doc_claim_report() {
    python3 - "$1" "$2" <<'PY'
import re, sys
mode, path = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
base = path.rsplit("/", 1)[-1]
problems = []

# Split into sentence-ish units. Clause boundaries matter: a maintainer-tooling
# qualifier before a semicolon must not bless a consumer instruction after it.
def units(blob, boundary=r'[.;:!?]'):
    # Markdown markup must not weld two sentences together. The splitter used
    # to require punctuation followed by WHITESPACE, so a bold sentence ending
    # `...on your behalf.**` never split, and an affirmative claim appended
    # after it inherited the earlier sentence's denial credit. Same hole let
    # `scripts/audit-session-load.sh;**` shield a later consumer instruction.
    # Emphasis markers are formatting, not meaning: drop them before splitting.
    for raw_line in blob.splitlines():
        flat = re.sub(r'[*_`]+', '', raw_line)
        for piece in re.split(r'(?<=' + boundary + r')[\s)\]"\u2019]*\s+|\s+\u2014\s+', flat):
            if piece.strip():
                yield raw_line, piece.strip()

if mode == "watchdog":
    if re.search(r'STALL_SECONDS', text, re.I):
        problems.append(f"{base} names STALL_SECONDS, a tunable that has never existed")
    # Only sentences about THIS review wrapper are in scope. A consumer's
    # systemd watchdog is none of our business.
    scope = re.compile(r'codex|wrapper|stall watchdog|reviews?\s+(?:are|is)\s+bounded|bounds?\s+(?:every|each|all)\s+reviews?', re.I)
    affirm = re.compile(r'\b(has|have|with|supplies|supply|provides|provide|adds|add|includes|include|contains|carries|bounds|bounded|enforces)\b', re.I)
    negate = re.compile(r'\b(no|not|never|without|nothing|none|false|falsely|wrongly|incorrect|untrue)\b', re.I)
    # Sentence-level here, not clause-level: a semicolon joins related
    # independent clauses, so a correction after it governs the whole
    # sentence — "...includes a stall watchdog; that claim was false" is one
    # honest statement, and splitting it severed the correction. The scripts
    # guard below keeps clause-level splitting, because a qualifier must be
    # local to its reference.
    for _line, unit in units(text, boundary=r'[.!?]'):
        if not re.search(r'watchdog', unit, re.I):
            continue
        if not scope.search(unit):
            continue          # unrelated watchdog — legitimately none of ours
        if affirm.search(unit) and not negate.search(unit):
            problems.append(f"{base} asserts the wrapper HAS a watchdog: {unit[:100]}")
elif mode == "scripts":
    qualifier = re.compile(r'NOT installed|repo-local|maintainer tooling', re.I)
    for _line, unit in units(text):
        for ref in sorted(set(re.findall(r'\bscripts/[A-Za-z0-9_./-]+', unit))):
            ref = ref.rstrip('.,;:)')
            problems.append(("OK", base, ref) if qualifier.search(unit)
                            else ("UNQUALIFIED", base, ref))
    problems = [f"{b} names {r} with no repo-local qualifier in its own clause — scripts/ is not packed, so consumers never receive it"
                for (k, b, r) in problems if k == "UNQUALIFIED"]

if problems:
    print("\n".join(problems))
PY
}

_watchdog_claims_in() { _doc_claim_report watchdog "$1"; }

# Sentinel membership, not a bare non-empty check. Both #491 doc guards iterate
# this list, so a helper that silently returns nothing turns BOTH into no-ops
# that pass loudly — the same vacuity the hook roster was guarded against in the
# very commit that shipped this helper unguarded. Membership also catches a
# partial derivation, which a non-empty check would wave through.
_assert_packed_surfaces_sane() {
    local list
    list=$(_packed_markdown_surfaces)
    printf '%s' "$list" | grep -q 'CLAUDE_CODE_SDLC_WIZARD.md' || return 1
    printf '%s' "$list" | grep -q 'README.md' || return 1
    printf '%s' "$list" | grep -q 'skills/sdlc/SKILL.md' || return 1
    return 0
}

_packed_markdown_surfaces() {
    python3 - "$REPO_ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
with open(os.path.join(root, "package.json")) as fh:
    entries = json.load(fh).get("files", [])
out = []
def add(rel):
    if rel.endswith(".md") and os.path.isfile(os.path.join(root, rel)):
        out.append(rel)
for entry in entries:
    path = os.path.join(root, entry)
    if os.path.isdir(path):
        for dirpath, _dirs, names in os.walk(path):
            for name in names:
                add(os.path.relpath(os.path.join(dirpath, name), root))
    else:
        add(entry)
add("README.md")  # npm packs README.md implicitly
# Release history may legitimately name things that were true at the time.
print("\n".join(os.path.join(root, p) for p in sorted(set(out))
                if os.path.basename(p) != "CHANGELOG.md"))
PY
}

# ---- GH #491 Class 1: phantom script paths in docs ----
#
# CLAUDE_CODE_SDLC_WIZARD.md told every consumer that "the wrapper
# scripts/codex-review.sh already has a 30-min stall watchdog." That file has
# never existed under any name but codex-review-with-progress.sh, so a reader
# following the sentence finds nothing and the stated safety property is
# unverifiable. A named path either resolves or it is a false assurance;
# checking existence is mechanical, so no reviewer should have to catch this.
#
# Scoped to scripts/ deliberately. A generic any-path check would drown in
# consumer-side example paths (src/, tests/foo) that correctly do not exist here.
test_doc_script_references_exist() {
    local bad=""
    local doc ref base line
    # Existence on the maintainer's disk is the WRONG question, and asking it
    # was the first version of this test. `scripts/` is absent from
    # package.json's "files" list, so `npm pack` ships none of it: a path can
    # resolve perfectly here and be a phantom for every consumer. That is the
    # same defect class one level out — which is why a shipped doc naming a
    # repo-local script must say so on the same line.
    # The doc list is the packed set, not a hand-picked one. A hand-picked list
    # omitted README.md (npm ships it implicitly, regardless of "files"),
    # skills/feedback/SKILL.md and skills/update/SKILL.md — a phantom path in
    # README.md passed the whole suite — while wasting effort on the cowork
    # copy, which does not ship at all. CHANGELOG.md is excluded deliberately:
    # it is release history, and history is allowed to name things that were
    # true then.
    _assert_packed_surfaces_sane || { fail "#491: the packed-surface list is broken — both #491 doc guards would pass vacuously"; return; }
    for doc in $(_packed_markdown_surfaces); do
        [ -f "$doc" ] || continue
        base=$(basename "$doc")
        # Phantom paths: judged per reference, anywhere in the file.
        while IFS= read -r ref; do
            [ -n "$ref" ] || continue
            [ -e "$REPO_ROOT/$ref" ] || bad="$bad\n  $base names $ref — no such file anywhere"
        done <<< "$(grep -ohE '\bscripts/[A-Za-z0-9_./-]+' "$doc" 2>/dev/null | sed 's/[.,;:)]*$//' | sort -u)"
        # Availability qualifiers: judged per CLAUSE, so a maintainer-tooling
        # note before a semicolon cannot bless a consumer instruction after it.
        _rep=$(_doc_claim_report scripts "$doc"); [ -n "$_rep" ] && bad="$bad\n  $_rep"
    done
    if [ -z "$bad" ]; then
        pass "#491: no shipped doc points a consumer at a script they do not receive"
    else
        fail "#491: shipped doc names a script the consumer never gets:$(printf '%b' "$bad")"
    fi
}
test_doc_script_references_exist

# ---- GH #491 Class 1, second half: named mechanisms must be real ----
#
# The path check above is necessary but NOT sufficient, and this test exists
# because fixing the path alone was the wrong fix. The wizard doc promised a
# 30-minute stall watchdog governed by STALL_SECONDS=1800. That variable has
# never existed; scripts/codex-review-with-progress.sh loops on `kill -0` until
# codex exits and enforces no timeout whatsoever. Repointing the sentence at
# the wrapper that DOES exist would have satisfied the path check while leaving
# the operational promise just as false — and harder to spot, because the path
# now resolves. A consumer with a hung review had no protection and no knob.
#
# So: if a doc names a control variable, that variable must exist in code.
test_doc_named_control_vars_exist_in_code() {
    local bad="" para
    # This started as "no doc may name a control variable that does not exist,"
    # seeded with the one variable that had burned us. Both reviewers rejected
    # it independently and they were right: it is the unwinnable denylist of
    # ROADMAP #495(a). Rename the phantom (REVIEW_STALL_TIMEOUT), or drop the
    # variable name entirely — "already has a built-in 30-minute stall
    # watchdog" — and the check never fires. It also accepted ANY occurrence in
    # scripts/, so `# TODO: add STALL_SECONDS` would "prove" implementation.
    #
    # Inverted to a positive assertion on the paragraph that DEFINES the
    # behaviour, which is a fixed target rather than an open-ended space of
    # wrong spellings. This is the shape #495(a) recommends.
    para=$(grep -h 'Always launch codex via' "$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md" 2>/dev/null)

    if [ -z "$para" ]; then
        fail "#491: the codex-launch paragraph is gone — this assertion is now vacuous, re-anchor it"
        return
    fi
    printf '%s' "$para" | grep -qiE 'no stall watchdog and no timeout' \
        || bad="$bad\n  it no longer states plainly that the wrapper has no stall watchdog and no timeout"
    printf '%s' "$para" | grep -qiE 'kill -0' \
        || bad="$bad\n  it no longer names the actual mechanism (it loops on kill -0 until codex exits)"
    # The failure mode that shipped for months: asserting a bounded review.
    printf '%s' "$para" | grep -qiE '(has|have|with) an? [0-9]+-?(minute|min| )?[a-z ]*(stall )?watchdog' \
        && bad="$bad\n  it claims a watchdog exists again — no such mechanism is implemented"

    if [ -z "$bad" ]; then
        pass "#491: the codex-timeout paragraph states the real behaviour (no watchdog, no timeout)"
    else
        fail "#491: the codex-timeout paragraph misdescribes what the wrapper does:$(printf '%b' "$bad")"
    fi
}
test_doc_named_control_vars_exist_in_code

# ---- GH #491: the burned tokens, pinned across every shipped surface ----
#
# The paragraph assertion above proves ONE paragraph is honest. Both reviewers
# then walked around it: the verbatim original sentence pasted into the parallel
# codex callout passed, as did re-adding STALL_SECONDS to skills/sdlc/SKILL.md,
# and "a built-in thirty-minute stall watchdog" defeated a digit-based regex.
#
# This is NOT the #495(a) arms race. That failure mode is enumerating unknown
# future spellings. This pins two tokens that have already shipped as lies —
# a regression pin on a known defect, which is what regression tests are for.
# No watchdog exists, so every legitimate mention is a denial or a history note.
test_no_shipped_doc_reasserts_the_phantom_watchdog() {
    local bad="" doc
    # Judged per SENTENCE, and only for sentences actually about this review
    # wrapper. Line-level judging was wrong in both directions at once:
    #
    #   - Too permissive: "Despite that denial, the wrapper has a built-in
    #     thirty-minute stall watchdog" appended to the canonical line PASSED,
    #     because the denial tokens elsewhere on that same line blessed it.
    #   - Too strict: "configure systemd's watchdog to restart a crashed
    #     daemon" in README FAILED, though it has nothing to do with this
    #     wrapper. An over-broad guard that blocks honest future prose is its
    #     own defect, not extra safety.
    _assert_packed_surfaces_sane || { fail "#491: the packed-surface list is broken — this watchdog pin would pass vacuously"; return; }
    for doc in $(_packed_markdown_surfaces); do
        [ -f "$doc" ] || continue
        _rep=$(_watchdog_claims_in "$doc"); [ -n "$_rep" ] && bad="$bad\n  $_rep"
    done
    if [ -z "$bad" ]; then
        pass "#491: no shipped doc re-asserts the stall watchdog or its phantom tunable"
    else
        fail "#491: a shipped surface promises the watchdog again:$(printf '%b' "$bad")"
    fi
}
test_no_shipped_doc_reasserts_the_phantom_watchdog

# ---- Fable is the primary thinker, not a post-hoc reviewer ----
#
# Maintainer, 2026-08-07: "use fable to think... it should be your main brain and
# driving everything, ur just the coder....that should be clear in our /sdlc".
#
# The shipped guidance framed Fable as a rung to escalate TO when uncertain, and
# as a cadence slot ("Fable during design"). Both read as advisory. The intended
# contract is stronger: Fable DECIDES design, priority and sequencing, and the
# driver implements that decision. Codex is the adversarial check afterwards —
# a different job, not the same one later.
#
# This is codified here rather than in per-user memory on purpose. The skill's own
# Memory Audit Protocol says a process rule saved only to memory is a /sdlc gap:
# memory changes one agent, docs change everyone.
test_fable_framed_as_decider_not_advisor() {
    local bad="" doc="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    [ -f "$doc" ] || { fail "wizard doc missing"; return; }
    # Tolerate markdown emphasis between the words: the doc says
    # "Fable **decides**", and a literal-space pattern missed it. Same
    # markup-weld class as the #491 splitter bug.
    grep -qiE "fable[^A-Za-z]{0,4}(decides|drives)" "$doc" \
        || bad="$bad\n  the wizard doc never says Fable DECIDES — it reads as advisory"
    grep -qiE "implement (its|that|the) (call|decision)|you (are|'re) the coder" "$doc" \
        || bad="$bad\n  it does not say the driver implements Fable's call"
    # Codex must stay distinct, or the fix has collapsed two different jobs.
    grep -qiE "codex.*(adversarial|check)" "$doc" \
        || bad="$bad\n  Codex's adversarial-check role is no longer distinguished from Fable's"
    if [ -z "$bad" ]; then
        pass "shipped guidance frames Fable as deciding, with Codex still the adversarial check"
    else
        fail "Fable is still framed as an advisor rather than the primary thinker:$(printf '%b' "$bad")"
    fi
}
test_fable_framed_as_decider_not_advisor

# ---- README's architecture diagram must not imply consumers get our CI ----
#
# The diagram reads: "GENERATED FILES (in your repo)" -> "validated by" ->
# "CI/CD PIPELINE / E2E: simulate SDLC task -> score 0-10". With one box
# labelled "in your repo" and the next unlabelled, the scoring pipeline reads
# as something that runs in the consumer's repo. It does not: `tests/e2e/` is
# absent from package.json's files, so `npm pack` ships none of it. That
# pipeline validates the harness HERE, before a release goes out.
#
# Same defect class as GH #491's distribution boundary — a shipped doc implying
# the consumer has something they never receive.
test_readme_diagram_scopes_the_ci_pipeline() {
    local f="$REPO_ROOT/README.md" block
    [ -f "$f" ] || { fail "README.md missing"; return; }
    block=$(grep -A4 'CI/CD PIPELINE' "$f" | head -5)
    if [ -z "$block" ]; then
        pass "README no longer shows the CI/CD pipeline box (nothing to mis-scope)"
        return
    fi
    if grep -qE 'CI/CD PIPELINE \((this repo|our repo|meta-repo)[^)]*\)' "$f"; then
        pass "README diagram scopes the CI/CD pipeline to this repo, not the consumer's"
    else
        fail "README's CI/CD PIPELINE box is unscoped — it follows a box labelled '(in your repo)', so it reads as running in the consumer's repo. tests/e2e/ does not ship."
    fi
}
test_readme_diagram_scopes_the_ci_pipeline

# ---- the doc-sync rule must name README ----
#
# The rule listed `*_DOCS.md` and `ROADMAP.md` and stopped there. README was
# never named, and on 2026-08-08 that cost: #486 deleted the same-model
# self-review instruction while README still advertised "Self-review before
# presenting" as an enforced behaviour, and described a flow starting with a
# self-review gate that no longer exists. Both shipped stale for hours, and the
# maintainer noticed before any check did.
#
# README is not an afterthought here — npm packs it whether or not it appears in
# package.json's files list, so it reaches every consumer. A doc-sync rule that
# omits the most-read shipped document is the rule failing at its own job.
test_doc_sync_rule_names_readme() {
    local f="$REPO_ROOT/skills/sdlc/SKILL.md" section
    section=$(awk '/^## Documentation Sync/,/^## [^D]/' "$f")
    if [ -z "$section" ]; then
        fail "Documentation Sync section not found in the skill — this assertion is now vacuous"
    elif printf '%s' "$section" | grep -q "README"; then
        pass "doc-sync rule names README (it ships, and it went stale once)"
    else
        fail "the Documentation Sync rule never names README, so a shipped-doc update is not required by it — this is how README advertised a behaviour that had been deleted"
    fi
}
test_doc_sync_rule_names_readme

# ---- the first-action mandate must name a tool the harness actually has ----
#
# The skill opens with "Your FIRST action must be a TodoWrite". TodoWrite is a
# standard Claude Code tool but is NOT exposed in every configuration — this
# session has TaskCreate/TaskUpdate/TaskList and no TodoWrite. A driver reading
# a mandate for a tool it cannot call either ignores rule 1 or invents a
# substitute, and neither is what the rule wants.
#
# The rubric row already hedges correctly ("Use TodoWrite or TaskCreate"). The
# mandate did not, so the two disagreed about the same requirement.
test_first_action_mandate_names_available_tool() {
    local f="$REPO_ROOT/skills/sdlc/SKILL.md" line
    line=$(grep -m1 "FIRST action must be" "$f")
    if [ -z "$line" ]; then
        fail "the first-action mandate is gone from the skill — this assertion is now vacuous"
    elif printf '%s' "$line" | grep -q "TaskCreate"; then
        pass "first-action mandate names TaskCreate as well as TodoWrite (harnesses differ)"
    else
        fail "the first-action mandate names only TodoWrite, which is not exposed in every harness — a driver without it cannot follow rule 1"
    fi
}
test_first_action_mandate_names_available_tool

# ---- the skill's exempted landmines must stay pinned ----
#
# GH #489 moved the cross-model file mechanics to the wizard doc but EXEMPTED two
# things from the move: the codex invocation flags (#364 — `< /dev/null` and
# background, which prevent a stdin hang and a 70-minute foreground kill) and the
# commit_sha-on-CERTIFIED rule (#437 — what the merge gate checks for staleness).
#
# The exemption was granted on the reasoning that improvising these costs real
# incidents. But the reviewer that granted it noted its own spec was incomplete:
# an exemption justified by "byte pressure deletes exactly the prose no test
# protects" needs a pin test in the same change, or the next trim round deletes
# the very lines the exemption exists to keep.
#
# Before #489 these were partially covered by assertions that have since been
# retargeted to the wizard doc. The multi-line codex-stdin check does not match
# the skill's single-line inline command, so it is silently exempt there. Today
# nothing fails if steps 1-2 disappear. This closes that.
test_skill_keeps_exempted_landmines() {
    local f="$REPO_ROOT/skills/sdlc/SKILL.md" missing=""
    [ -f "$f" ] || { fail "skills/sdlc/SKILL.md missing"; return; }
    # Anchor on the FUNCTIONAL line, not on any mention. Codex broke the first
    # version of this test by deleting `< /dev/null` from the actual command
    # while leaving the explanatory prose — it still passed, because a loose
    # grep cannot tell a working invocation from a sentence about one. My own
    # mutation proof missed it: I deleted every occurrence at once, so the test
    # went red for the wrong reason.
    # Anchor on the BACKTICK-DELIMITED COMMAND SPAN, not the whole markdown line.
    # The line also carries prose ("always append `< /dev/null`", "**Why:** ...")
    # so a line-level grep still matched after the guard was stripped from the
    # actual command — the reviewer's exact mutation evaded two "hardened"
    # versions of this test. The prose mentions live in their own spans, so
    # scoping to the command span is tight.
    local codex_cmd
    codex_cmd=$(grep -oE '`codex exec[^`]+`' "$f" | head -1)
    if [ -z "$codex_cmd" ]; then
        missing="$missing codex-invocation-line(#364)"
    else
        printf '%s' "$codex_cmd" | grep -q -- '< /dev/null' \
            || missing="$missing codex-stdin-guard-ON-THE-COMMAND(#364)"
        printf '%s' "$codex_cmd" | grep -q -- '-s danger-full-access' \
            || missing="$missing danger-full-access-flag(#364)"
    fi
    grep -qi 'run_in_background' "$f" || missing="$missing background-flag(#364)"
    # The RULE, not a passing mention: it must say to WRITE commit_sha on CERTIFIED.
    # Require the RULE with its VALUE, not a co-occurrence of words. The earlier
    # pattern matched "On CERTIFIED mentions commit_sha" — the write instruction
    # gone, the assertion still green. What the gate actually needs written is
    # the resolved HEAD sha, so `rev-parse` is the load-bearing token.
    # NOTE: a commit_sha assertion lived here and was deleted. It grepped this
    # doc for the "on CERTIFIED, write commit_sha" instruction — and was defeated
    # four times, each by prose ABOUT the rule rather than the rule. The behaviour
    # is enforced by hooks/codex-gate-check.sh (exit 2 on missing/stale sha) and
    # tested by running that hook against real fixtures. Grepping a doc to protect
    # a behaviour that already fails closed and has its own executable test is
    # negative ROI. Do not re-add it.
    # The Memory Audit pointer is the only route from the always-loaded skill to
    # the protocol that now lives in the wizard doc. Trim it and the protocol
    # becomes undiscoverable from the surface a driver actually reads.
    # Heading alone is not a pointer. The pointer is the DESTINATION — without it
    # the protocol is undiscoverable from the always-loaded surface.
    grep -qiE 'Memory Audit Protocol' "$f" || missing="$missing memory-audit-heading"
    grep -A4 -i 'Memory Audit Protocol' "$f" | grep -q 'CLAUDE_CODE_SDLC_WIZARD.md' \
        || missing="$missing memory-audit-DESTINATION-pointer"
    if [ -z "$missing" ]; then
        pass "skill retains its #489-exempted landmines and the memory-audit pointer"
    else
        fail "the skill lost content #489 explicitly exempted from the move — improvising these is what #364 and #437 memorialise:$missing"
    fi
}
test_skill_keeps_exempted_landmines

# ---- no shipped surface may present self-review as a GATE ----
#
# GH #486 deleted same-model self-review as an instructed step. Fixing the
# instances by hand missed most of them twice: a first pass fixed 4 of 7 cited
# sites and reported "all", and the residue included a flatly false claim that
# the skill still invokes /code-review.
#
# So this is a sweep, not a line list. It matches the gating PHRASINGS this
# repo has actually shipped — not every conceivable one; a regex cannot judge
# intent, and a guard whose comment claims more than its pattern is the exact
# class that defeated the landmine pin twice. The discriminator: a site FAILS if it
# presents self-review as a gate, a required step, or an instructed loop —
# "self-review passes ->", a numbered protocol step, a phase table naming it as
# the review stage. It PASSES if it describes the still-scored read-back, or
# /code-review as optional preflight input to cross-model review, or is inside
# the explicitly labeled historical reference section.
test_no_shipped_surface_gates_on_self_review() {
    local bad="" doc base line
    for doc in "$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md" "$REPO_ROOT/README.md" \
               "$REPO_ROOT/skills/sdlc/SKILL.md" "$REPO_ROOT/skills/setup/SKILL.md"; do
        [ -f "$doc" ] || continue
        base=$(basename "$doc")
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            # allowed: the labeled history section, and read-back/preflight framing
            printf '%s' "$line" | grep -qiE 'for reference|optional preflight|preflight input|demoted|no longer|removed in|read back' && continue
            bad="$bad\n  $base: $(printf '%s' "$line" | cut -c1-96)"
        # Two passes. Case-INSENSITIVE for the phrase forms; case-SENSITIVE for the
        # all-caps template form, because a bare case-insensitive SELF-REVIEW also
        # matches the soft benefit prose that is explicitly allowed ("Self-review |
        # AI catches its own mistakes"). One pattern could not separate them.
        done <<< "$( { grep -niE 'self-review passes|self.review (step|gate)|already invokes .?/code-review|/code-review self-review|self-review: run|run .?/code-review.{0,24}before' "$doc" 2>/dev/null; grep -nE 'SELF-REVIEW.*code-review' "$doc" 2>/dev/null; } | sort -un)"
    done
    if [ -z "$bad" ]; then
        pass "#486: no shipped surface presents self-review as a gate or required step"
    else
        fail "shipped surface still gates on same-model self-review, deleted in #486:$(printf '%b' "$bad")"
    fi
}
test_no_shipped_surface_gates_on_self_review

# ---- the tutorial hook template must not drift from the shipped hook ----
#
# CLAUDE_CODE_SDLC_WIZARD.md:2655 documents this exact defect from v1.84.0:
# "tutorial hook code silently drifted from the real shipped hook". It recurred
# twice on this branch — the template still emitted a self-review line the hook
# had dropped, and a fix to the template's task-list wording was not applied to
# the hook, so they disagreed about which tool to name and which doc to cite.
#
# Doc-lane consumers copy the template; CLI consumers get the hook. When they
# disagree, one group is following instructions the other group's tooling does
# not implement.
test_hook_template_matches_shipped_hook() {
    local doc="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md" hook="$REPO_ROOT/hooks/sdlc-prompt-check.sh"
    local bad="" line
    [ -f "$doc" ] && [ -f "$hook" ] || { fail "template or shipped hook missing"; return; }
    # Lines the template teaches that the hook must actually emit.
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        grep -qF "$line" "$hook" || bad="$bad\n  template teaches, hook does not emit: $line"
    done <<'TEMPLATE_LINES'
1. Task list FIRST (TodoWrite or TaskCreate) (plan tasks before coding)
Quick refs: SDLC.md | TESTING.md | *_DOCS.md for feature
TEMPLATE_LINES
    if [ -z "$bad" ]; then
        pass "tutorial hook template matches the shipped hook (v1.84.0 drift class)"
    else
        fail "tutorial hook template drifted from hooks/sdlc-prompt-check.sh:$(printf '%b' "$bad")"
    fi
}
test_hook_template_matches_shipped_hook

# ---- the review loop must not hand the turn back per round ----
#
# Observed 2026-08-08 on PR #509: three review rounds, and after EACH one the
# driver fixed the findings then stopped and reported — while findings were
# still landing and the loop had obviously not converged. The maintainer had to
# say "continue" three times.
#
# The mechanism was never missing: a backgrounded reviewer completing re-invokes
# the driver automatically. What was missing was the rule saying that a turn
# ending with no pending work IS a stop decision requiring a stated reason.
test_skill_states_loop_autonomy_rule() {
    local f="$REPO_ROOT/skills/sdlc/SKILL.md" missing=""
    [ -f "$f" ] || { fail "skills/sdlc/SKILL.md missing"; return; }
    grep -qi 'CONVERGED' "$f" || missing="$missing CONVERGED"
    grep -qi 'DEADLOCK'  "$f" || missing="$missing DEADLOCK"
    grep -qi 'BOUND'     "$f" || missing="$missing BOUND"
    # The anti-shopping invariant is the load-bearing half: without it,
    # "always continue" becomes resubmitting until a tired YES.
    grep -qi 'reviewer-shopping' "$f" || missing="$missing anti-shopping-invariant"
    if [ -z "$missing" ]; then
        pass "skill states the loop-autonomy rule (stop only on CONVERGED/DEADLOCK/BOUND)"
    else
        fail "the skill does not state when the review loop may stop, so the driver hands the turn back every round:$missing"
    fi
}
test_skill_states_loop_autonomy_rule

# --- GH #513 ---------------------------------------------------------------
#
# The wizard doc CARRIED a 639-line ````markdown fence introduced by "Step 6:
# Create SDLC Skill / Create `.claude/skills/sdlc/SKILL.md`:". That MADE it a
# SECOND INSTALL PATH for the same destination the CLI writes, and the two had
# diverged: 56,284 bytes against the live skill's 19,356, moving in opposite
# directions inside single PRs (#509 shrank the live skill 856 bytes while
# growing the fence 1,470).
#
# One skill, one install path. The CLI is canonical, and `skills/sdlc/SKILL.md`
# ships in the same npm package as this document — so a reader following the doc
# already has the real file next to the instructions.
test_wizard_doc_ships_no_second_install_path_for_the_skill() {
    local f="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    [ -f "$f" ] || { fail "wizard doc missing"; return; }
    # Length is NOT the discriminator, though the first version of this guard
    # used it (longest ````-fence, fail above 100 lines) and a reviewer proved it
    # wrong in all four directions: a legitimate unrelated 120-line example
    # fails, a 99-line second install path passes, a 639-line copy in an ordinary
    # ```-fence passes with a measured length of zero, and a copy split across
    # two 80-line blocks passes. The property is "this block IS the skill", so
    # `skillcopy` asks that directly, and NOT all of it about fenced blocks:
    # rules A (heading reproduction) and B (frontmatter at real-file size) look at
    # REGIONS — fenced blocks plus indented runs — while rule C measures the RAW
    # DOCUMENT's reproduction of the skill's body prose, with no markup model at
    # all. C is markup-blind because a verbatim copy indented four spaces carries
    # no fence, and because a block-scoped C scored the same copy at 105 or 131
    # lines purely by 3- vs 4-backtick wrapper choice.
    local out
    if out=$(python3 "$SCRIPT_DIR/lib/skillcopy.py" "$REPO_ROOT" 2>&1); then
        pass "wizard doc ships no second install path for the skill"
    else
        fail "wizard doc embeds a copy of the shipped skill — a second install path for a file the CLI already installs. One skill, one source (#513):
$out"
    fi
}
test_wizard_doc_ships_no_second_install_path_for_the_skill

# The invariant that stops this recurring, and the more valuable of the two.
#
# Assertions across this corpus grepped the wizard doc for strings that exist
# ONLY inside that fence — `## Cross-Model Review (REQUIRED`, `### Release Review
# Focus`, `gh pr merge --auto`, `no stall watchdog and no timeout`. They were
# written to check what the DOCUMENT tells a reader, and passed by matching a
# quotation of a draft nobody installs. Guard and artifact pointed at different
# objects.
#
# ONE count, with its method, because an earlier note gave a bare figure that no
# measurement reproduced: `fence-only-assertions.py` run against the `main`
# document, with skill-copy blocks stripped, reports 18 such assertions across 2
# suites (test-doc-consistency.sh, test-self-update.sh) — measured 2026-08-08,
# after the re.M and GREP_STDIN repairs, which recovered assertions the earlier
# count of 15 had been silently missing.
# That is the guard's own reach and the number that regresses if it weakens. It
# is NOT a claim about how many exist: shapes the scanner cannot resolve are
# outside it by construction, which is what the reach-limits section of that
# module documents.
#
# Same defect class as #517's fixture committing dummy files as the "pristine
# gate" while executing the real script: a check that appears to verify X and
# actually verifies Y. Third instance in one week, so it gets a test.
test_no_wizard_doc_assertion_is_satisfied_only_inside_a_fence() {
    local out
    if out=$(python3 "$SCRIPT_DIR/lib/fence-only-assertions.py" "$REPO_ROOT" 2>&1); then
        pass "no test asserts wizard-doc guidance that exists only inside a fenced block"
    else
        fail "assertions satisfied ONLY by text inside a fenced block — they verify a quotation, not the document (#513):
$out"
    fi
}
test_no_wizard_doc_assertion_is_satisfied_only_inside_a_fence

# BOTH guards above are DORMANT while the repo is healthy: with no skill copy in
# the document there is nothing to strip and nothing to flag, so they pass by
# having no work to do. Dormant-by-precondition is legitimate; dormant-by-accident
# is the exact defect (#513, #517) these guards exist to catch, and from the
# outside the two look identical.
#
# The selftests are what tells them apart — each runs its detector against a
# synthetic document that DOES contain a copy, so the machinery is exercised on
# every CI run rather than only on the day the repo is already broken. They
# existed but nothing invoked them, which made the whole dormancy argument
# unevidenced. Every fixture inside them cites the specific review finding it
# came from.
test_guard_selftests_actually_run() {
    local lib out
    for lib in "mdfence.py" "skillcopy.py --selftest" "fence-only-assertions.py --selftest"; do
        # shellcheck disable=SC2086  # the flag is part of the list entry
        if out=$(python3 "$SCRIPT_DIR/lib/"$lib 2>&1); then
            pass "guard selftest green: $lib"
        else
            fail "guard selftest FAILED: $lib — the detector no longer catches a
copy it is supposed to catch, so the guard above may be passing vacuously:
$out"
        fi
    done
}
test_guard_selftests_actually_run

# #476: the wizard documented how to install ITSELF and never how to install
# Claude Code, the thing it runs on. A real machine hit the footgun the official
# setup docs warn about in those words: `sudo npm install -g` left the global
# module dir root-owned, which killed `claude update` ("Insufficient
# permissions"), then killed `npm uninstall -g` (EACCES on a root-owned rename),
# and finally left two `claude` binaries on PATH at once — resolved by PATH
# order, so a reordering would have downgraded the user with no warning.
#
# Scoped to the Prerequisites SECTION on purpose. "the installer is named
# somewhere in a 4,900-line file" is the #493 failure mode — it passes on a doc
# that mentions the installer in an unrelated aside about version pinning, which
# this doc already contains at the version-test benchmark procedure. The claim
# under test is narrower and is the one that matters: a reader standing at the
# install moment is told which installer to use.
#
# The recommendation half exists because round 1 asserted only that the URL
# appeared. Rewriting the prose to "Do not use the native installer" while
# keeping the URL still passed — the guard proved a string, not a stance.
test_wizard_prereqs_recommend_native_claude_install() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    local section tmp negated
    section=$(awk '/^## Prerequisites$/ { f = 1; next } /^## / { f = 0 } f' "$DOC")
    if [ -z "$section" ]; then
        fail "#476: no '## Prerequisites' section in the wizard doc to carry install guidance"
        return
    fi
    tmp=$(mktemp "${TMPDIR:-/tmp}/prereq-XXXXXX")
    printf '%s\n' "$section" > "$tmp"

    if ! grep -qE 'claude\.ai/install\.sh' "$tmp"; then
        fail "#476: wizard Prerequisites gives no Claude Code install command, so a reader at the install moment is never steered off sudo-npm"
        rm -f "$tmp"; return
    fi
    if ! grep -qiE 'recommend' "$tmp"; then
        fail "#476: wizard Prerequisites shows an install command but never says it is the recommended one — a bare command is not a recommendation"
        rm -f "$tmp"; return
    fi
    # A negation reaching the installer without crossing a clause boundary.
    # This is the whole inversion attack that was made against this test: keep
    # the URL, flip the sentence to "Do not use the native installer". One grep
    # closes it, because the negation has to sit right on the phrase.
    #
    # Deliberately NOT a general negation-scope engine. A companion guard that
    # tried to be one cost four review rounds chasing sentence forms and one
    # more chasing spellings of `sudo`, and was dropped for it — see #551. The
    # docs are what #476 asked for; this test guards the stance the docs take,
    # and cross-model review covers what a regex cannot.
    negated=$(grep -inE "(do not|don't|never|avoid)[^.;,]*native install" "$tmp" || true)
    rm -f "$tmp"
    if [ -n "$negated" ]; then
        fail "#476: wizard Prerequisites negates the native installer it is supposed to recommend:
$negated"
        return
    fi
    pass "#476: wizard Prerequisites recommends the native Claude Code installer, unnegated"
}
test_wizard_prereqs_recommend_native_claude_install


# Tests (#530): the standing setup the maintainer kept retyping every session
# must live in the skill, not in a human's muscle memory.
#
# Most of what #530 asked for already shipped: the escalation ladder, the
# model/effort policy, the clearance format, and PROCESS BUDGET are all in
# skills/sdlc/SKILL.md already. Two things were not, and both are retyped:
# Fable's role is to DECIDE, and a guard may not outgrow its change.
#
# Greps run INSIDE the Cross-Model Review section, never against the whole
# file — a keyword that lands anywhere in a 20KB skill proves nothing. #493
# caught three such assertions before they shipped, and that release went out
# without the guard rather than with a vacuous one; #551 is the same story.
#
# `[^.;]*` throughout, not `[^.]*`: a semicolon ends a clause, and both
# reviewers' inversion attacks worked by hopping one. These guards are
# deliberately NOT a semantics engine — they catch drift and deletion, which
# is what a grep can honestly promise. Adversarial prose is what the reviewers
# are for, and chasing it is what cost #476 its last two rounds.
extract_sdlc_cross_model_section() {
    awk '
        /^## Cross-Model Review/ { in_section = 1; print; next }
        in_section && /^## / { in_section = 0 }
        in_section { print }
    ' "$1"
}

# The weak form already shipped: "Cadence: Fable during design". That says WHEN
# Fable is consulted, not that Fable's answer settles the approach. The rule
# being retyped is the strong one — Fable rules on design/priority/sequencing
# BEFORE an approach is committed to.
test_sdlc_skill_makes_fable_the_deciding_role() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    local section
    section=$(extract_sdlc_cross_model_section "$SKILL")
    if [ -z "$section" ]; then
        fail "#530: no '## Cross-Model Review' section in skills/sdlc/SKILL.md to carry the standing setup"
        return
    fi
    # Both halves required, each with its object named, each within one clause.
    # Naming the objects is what defeats the inversion both reviewers found:
    # "Fable decides nothing before lunch; Codex alone chooses every design"
    # hops the semicolon to reach `design`, and its `before` takes `lunch`.
    if ! printf '%s\n' "$section" | grep -qiE 'Fable[^.;]*\b(decides|rules|settles|chooses)\b[^.;]*\b(design|priority|sequencing)\b'; then
        fail "#530: Cross-Model Review section must state that Fable DECIDES design/priority/sequencing — 'Fable during design' only says when to consult, which is why the role kept getting retyped"
        return
    fi
    if ! printf '%s\n' "$section" | grep -qiE '\bbefore\b[^.;]*\b(approach|commit)'; then
        fail "#530: the skill says Fable decides but not that it decides BEFORE an approach is committed to — deciding after the fact is just review, which is the role it already had"
        return
    fi
    pass "#530: skill states Fable DECIDES design/priority/sequencing before an approach is committed to"
}

# #476 spent six review rounds on a twenty-line doc change. Rounds 1-4 bought
# real defects; rounds 5-6 bought spellings of `sudo`.
#
# This is deliberately NOT a second round counter. The skill already has one —
# the Convergence rule, "ONE REVIEW AND ONE VERIFY PER FROZEN SCOPE", which now
# carries the stop condition itself rather than deferring to the driver —
# and #476 burned six rounds with that rule already shipped, because each
# repair re-froze the scope and bought two more passes. A cap was never the
# missing piece; both reviewers said so independently, and the wizard doc
# separately blesses continuation past round 4 for large migrations, where
# v1.84.0's round 8 found a real shipped bug. A narrow cap would have
# suppressed that round.
#
# What was missing is a RATIO: the guard may not outgrow the change. Both
# halves must land in one clause, because three independent greps are
# satisfiable by three unrelated sentences — which is precisely how a reviewer
# broke the first draft of this test.
test_sdlc_skill_caps_guard_cost_by_its_change() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    local section
    section=$(extract_sdlc_cross_model_section "$SKILL")
    if [ -z "$section" ]; then
        fail "#530: no '## Cross-Model Review' section in skills/sdlc/SKILL.md to carry the guard-cost rule"
        return
    fi
    if ! printf '%s\n' "$section" | grep -qiE '\btests?\b[^.;]*\brounds?\b[^.;]*\bchange it guards\b'; then
        fail "#530: Cross-Model Review section does not tie a test's review cost to the change it guards — #476 spent six rounds on twenty doc lines and two of them bought spellings"
        return
    fi
    # An over-budget guard has to go somewhere. Deleting it silently loses the
    # risk it was written for; keeping it is what cost the six rounds.
    if ! printf '%s\n' "$section" | grep -qiE '\bdelete\b[^.;]*\b(guard|test)\b[^.;]*(follow.up|file)'; then
        fail "#530: the rule says a guard can outgrow its change but not what to do about it — deleting it without filing the follow-up loses the risk, keeping it is the six rounds"
        return
    fi
    pass "#530: skill caps a guard's review cost by the change it guards, and routes the deleted guard to a follow-up"
}

test_sdlc_skill_makes_fable_the_deciding_role
test_sdlc_skill_caps_guard_cost_by_its_change


# Tests (#539): the pass budget is cumulative per ROOT TASK, never per frozen
# scope.
#
# "Frozen scope" is redefinable. Re-freeze after every fix and "two passes per
# frozen scope" silently becomes unlimited — which is #520 (20 rounds, 46 lines)
# and #476 (six rounds, twenty doc lines). The count has to survive a re-freeze.
#
# WHAT IS AND IS NOT PROVEN HERE. Both the skill and the wizard define the
# budget, so both are read. What is checked is that each names the `root_task`
# and `base_sha` fields the artifact must record. Whether the surrounding prose
# teaches the CORRECT rule is NOT checked and is not checkable this way — see
# the helper comment below for the four rounds that established that.
#
# NOT a second counter. #530 deleted one for contradicting the first, and #606
# rejected another for the same reason. This amends the surviving counter's
# DEFINITION. The cap lives in that one rule: continue only when the preceding
# completed pass recorded an open in-scope P0/P1, or the first
# verification-evidence invalidation in the root task.
# The wizard states the budget in four places; only ONE of them is the
# authoritative definition, so the wizard's field check reads that section
# rather than the whole file. Historically this scoping also mattered because
# reading the whole file let the definition under
# "When to stop" be reversed to "resets on each re-freeze" while the three
# dependent restatements downstream kept the regex satisfied — 137/137 green
# with the shipped wizard directly contradicting #539. Found by a reviewer, by
# mutating the definition rather than deleting it: deletion-shaped mutation is
# structurally blind to a claim that survives somewhere else in the file.
extract_wizard_when_to_stop_section() {
    awk '
        /^#### When to stop: the scope rule/ { in_section = 1; print; next }
        in_section && /^#{1,4} / { in_section = 0 }
        in_section { print }
    ' "$1"
}

# RECORDS THE FIELDS, PROVES NOTHING ABOUT THE RULE. Read the fail messages
# literally: they say a field NAME is absent, not that the document teaches the
# right rule. That is the whole claim, and it is deliberately small.
#
# The definition assertion that used to live here is DELETED. It was patched in
# four consecutive review rounds and defeated each time, finally by Markdown
# strikethrough: `~~The count is cumulative and never resets~~` leaves the pinned
# string byte-identical while the live sentence teaches the opposite, and the
# suite stayed 137/137 green. Every repair was the same shape — a presence check
# asked to prove a polarity. grep cannot do that; the fifth patch would have
# failed the same way.
#
# The guard-cost rule fired: a guard may not outlive the change it protects, and
# this one had cost more review rounds than the twenty-three lines of rule it was
# written for. It is deleted and the risk is filed, per #530. See the follow-up
# issue for the residual: nothing here detects a document that STATES the fields
# and then contradicts the rule in prose.
assert_names_root_task_artifact_fields() {
    local label="$1" body="$2"
    if ! printf '%s\n' "$body" | grep -qE '\broot_task\b'; then
        fail "#539: $label never names the \`root_task\` field the artifact must record"
        return 1
    fi
    if ! printf '%s\n' "$body" | grep -qE '\bbase_sha\b'; then
        fail "#539: $label never names the \`base_sha\` field — root task is 'verbatim request + base SHA', and without the SHA the root is not pinned"
        return 1
    fi
    return 0
}

test_pass_budget_is_cumulative_per_root_task() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    local WIZ="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$SKILL" ] || [ ! -f "$WIZ" ]; then fail "#539: skill or wizard doc not found"; return; fi
    local wiz_section
    wiz_section=$(extract_wizard_when_to_stop_section "$WIZ")
    if [ -z "$wiz_section" ]; then
        fail "#539: no '#### When to stop: the scope rule' section in CLAUDE_CODE_SDLC_WIZARD.md to carry the budget definition"
        return
    fi
    # `|| return 0`, not `|| return`: the file runs under `set -e`, so a test
    # function returning non-zero kills the whole suite mid-run. The helper
    # already called fail(); the test's own exit status must stay clean.
    assert_names_root_task_artifact_fields "skills/sdlc/SKILL.md" "$(cat "$SKILL")" || return 0
    assert_names_root_task_artifact_fields "CLAUDE_CODE_SDLC_WIZARD.md \"When to stop\"" "$wiz_section" || return 0
    pass "#539: skill and wizard both name the root_task and base_sha fields the artifact records (field names only — the rule's correctness is not asserted)"
}

# A new scope must APPEND, never replace. Without this the cumulative count is
# recorded and then overwritten, which reads identical to never having counted.
#
# Checked in BOTH docs. Checking only the skill let the wizard be reversed to say
# scopes replace prior records while all 137 tests stayed green — the two shipped
# documents could contradict #539 undetected. Found by a reviewer, by mutation.
test_new_scopes_append_rather_than_replace() {
    local f label missing=""
    for f in "skills/sdlc/SKILL.md" "CLAUDE_CODE_SDLC_WIZARD.md"; do
        label="$f"
        if [ ! -f "$REPO_ROOT/$f" ]; then fail "#539: $f not found"; return; fi
        printf '%s\n' "$(cat "$REPO_ROOT/$f")" \
            | grep -qiE '\bappend[^.;]*\b(replac|overwrit|reset)' || missing="$missing $label"
    done
    if [ -n "$missing" ]; then
        fail "#539: no clause containing \`append\` followed by replace/overwrite/reset appears in:$missing — a cumulative count that gets overwritten on re-freeze is not cumulative, and one doc carrying the clause while the other does not is the drift case"
        return
    fi
    pass "#539: skill and wizard each contain an append clause paired with replace/overwrite/reset (the words co-occur in order — the polarity of the sentence is not asserted)"
}

test_pass_budget_is_cumulative_per_root_task
test_new_scopes_append_rather_than_replace


# Tests (#538): the scope card is the artifact that makes CLOSED ALLOWLIST
# checkable.
#
# CLOSED ALLOWLIST says "the issue's requested behaviors are the whole job" but
# never named the thing you compare growth against. That is why nothing fired
# during #520. The card is six fields: one issue, acceptance criteria, allowed
# paths, exclusions, risk tier, estimated diff.
SCOPE_CARD_FIELDS='acceptance:allowed paths:exclusions:risk tier:estimated diff'

test_sdlc_skill_planning_requires_a_scope_card() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    # Scoped to the PLANNING block of the TodoWrite checklist. A scope card
    # named anywhere else in the skill is not a planning-phase requirement,
    # and the issue asks for it BEFORE work starts.
    local planning
    planning=$(awk '/\/\/ PLANNING/ { f = 1; next } /\/\/ TRANSITION/ { f = 0 } f' "$SKILL")
    if [ -z "$planning" ]; then
        fail "#538: no PLANNING block found in the skill's TodoWrite checklist to carry the scope card"
        return
    fi
    if ! printf '%s\n' "$planning" | grep -qi 'scope card'; then
        fail "#538: the words \`scope card\` never appear in the skill's PLANNING block — without the card named there, there is nothing to compare scope growth against, which is why nothing fired during #520"
        return
    fi
    local missing="" f
    local IFS=':'
    for f in $SCOPE_CARD_FIELDS; do
        printf '%s\n' "$planning" | grep -qi "$f" || missing="$missing '$f'"
    done
    unset IFS
    # 'one issue' is the sixth field and is checked HERE ONLY, not via
    # SCOPE_CARD_FIELDS. The templates satisfy it structurally -- a card on an
    # issue is by construction about that one issue -- so folding it into the
    # shared list would fail the template test for the wrong reason. The
    # planning phase has no such structure and must say it. Both reviewers
    # found the gap; this is the fix one of them prescribed after showing the
    # other's would misfire.
    printf '%s\n' "$planning" | grep -qi 'one issue' || missing="$missing 'one issue'"
    if [ -n "$missing" ]; then
        fail "#538: field name(s) absent from the skill's PLANNING block:$missing — a card missing 'estimated diff' or 'allowed paths' cannot trip the breaker, and one missing 'one issue' permits a multi-issue card, which is a scope card that cannot be exceeded"
        return
    fi
    pass "#538: skill's PLANNING phase names a scope card and all six of its fields (the words are present — whether the phase is honoured is not asserted)"
}

# The breaker is what makes the card mechanical rather than decorative. Each
# condition must name its object, so "watch for scope growth" does not satisfy it.
test_scope_card_breaker_conditions_are_named() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    local body
    body=$(cat "$SKILL")
    # All three categories, each checked separately. A single alternation over
    # (subsystem|path|criterion) passed when two of the three were mutated away,
    # so the guard could lose two breaker triggers while reporting all three
    # protected. Found by a reviewer, by mutation.
    local cat missing_cat=""
    for cat in subsystem path criterion; do
        printf '%s\n' "$body" | grep -qiE "\\b(new|another)\\b[^.;]*\\b${cat}" || missing_cat="$missing_cat $cat"
    done
    if [ -n "$missing_cat" ]; then
        fail "#538: breaker does not name the new-X condition for:$missing_cat — each category is a separate trigger and losing one silently disarms it"
        return
    fi
    # The multiplier must sit in the same clause as the estimate. A bare `2x`
    # alternative was a DEAD CHECK: SKILL.md:52 ("max 2x") and :100 ("FAILED
    # 2x") already satisfy it, so that branch could never fail. Caught by
    # mutation, not by reading.
    if ! printf '%s\n' "$body" | grep -qiE '(2x|twice|double)[^.;]*estimate|estimate[^.;]*(2x|twice|double)'; then
        fail "#538: breaker does not name the >2x-estimate condition — the estimated-diff field is inert without it"
        return
    fi
    if ! printf '%s\n' "$body" | grep -qiE 'two corrective rounds|2 corrective rounds'; then
        fail "#538: breaker does not name the two-corrective-rounds condition"
        return
    fi
    pass "#538: all three scope-card breaker conditions are named with their objects"
}

# Issue templates. ALL THREE, per #538's literal "every issue template".
#
# question.md carried an exclusion in the first draft, on the reasoning that a
# question produces no diff so 'estimated diff' and 'allowed paths' are
# meaningless. One reviewer upheld that; the other ruled the acceptance says
# "every issue template" without qualification. The acceptance won -- a question
# that turns out to be a bug or a feature ask becomes work, and the card is
# cheaper to have present than to remember to add. Its card says so in as many
# words and permits N/A while the issue stays a question.
#
# config.yml stays excluded and both reviewers agreed: it is the chooser
# configuration, not a template.
test_issue_templates_carry_a_scope_card() {
    local DIR="$REPO_ROOT/.github/ISSUE_TEMPLATE"
    if [ ! -d "$DIR" ]; then fail "#538: no .github/ISSUE_TEMPLATE/ directory"; return; fi
    local t missing_any=""
    for t in bug_report.md feature_request.md question.md; do
        if [ ! -f "$DIR/$t" ]; then
            fail "#538: expected issue template $t is missing"
            return
        fi
        if ! grep -qi 'scope card' "$DIR/$t"; then
            missing_any="$missing_any $t(no-card)"
            continue
        fi
        local f
        local IFS=':'
        for f in $SCOPE_CARD_FIELDS; do
            grep -qi "$f" "$DIR/$t" || missing_any="$missing_any $t(no:'$f')"
        done
        unset IFS
    done
    if [ -n "$missing_any" ]; then
        fail "#538: issue template(s) missing the scope card or its fields:$missing_any — the card has to exist before work starts, which means on the issue"
        return
    fi
    pass "#538: all three issue templates carry a scope card with every textually-checkable field"
}

test_sdlc_skill_planning_requires_a_scope_card
test_scope_card_breaker_conditions_are_named
test_issue_templates_carry_a_scope_card

echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi

echo "All cross-document consistency tests passed!"
