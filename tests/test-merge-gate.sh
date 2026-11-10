#!/bin/bash
# Tests for the repo-local merge-safety gate: .claude/hooks/merge-gate-check.sh
# (redirect-only PreToolUse hook) and scripts/merge-pr.sh (verifying wrapper).
#
# Both are intentionally repo-local, not shipped in hooks/hooks.json — see
# ROADMAP.md and CLAUDE_CODE_SDLC_WIZARD.md's CI Feedback Loop section for why.
# Kept in a dedicated file rather than tests/test-hooks.sh (which covers only
# shipped hooks) — mirrors tests/test-cowork-drift.sh's one-file-per-narrow-
# mechanism precedent.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../.claude/hooks/merge-gate-check.sh"
WRAPPER="$SCRIPT_DIR/../scripts/merge-pr.sh"
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

echo "=== Merge Gate Tests ==="
echo ""
echo "--- merge-gate-check.sh (redirect hook) ---"

# Test: hook script exists and is executable
test_hook_exists() {
    if [ -x "$HOOK" ]; then
        pass "merge-gate-check.sh exists and is executable"
    else
        fail "merge-gate-check.sh not found or not executable at $HOOK"
    fi
}

# Test: bare `gh pr merge` redirects
test_hook_redirects_bare_merge() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"gh pr merge 123"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 2 ] && echo "$out" | grep -q "scripts/merge-pr.sh"; then
        pass "bare 'gh pr merge' redirects to scripts/merge-pr.sh"
    else
        fail "bare 'gh pr merge' should redirect (exit 2, mention scripts/merge-pr.sh), got exit=$exit_code out=$out"
    fi
}

# Test: --squash form redirects
test_hook_redirects_squash() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"gh pr merge --squash 123"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 2 ] && echo "$out" | grep -q "scripts/merge-pr.sh"; then
        pass "'gh pr merge --squash' redirects to scripts/merge-pr.sh"
    else
        fail "'gh pr merge --squash' should redirect, got exit=$exit_code out=$out"
    fi
}

# Test: -m (merge commit) form redirects
test_hook_redirects_dash_m() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"gh pr merge -m 123"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        pass "'gh pr merge -m' redirects to scripts/merge-pr.sh"
    else
        fail "'gh pr merge -m' should redirect, got exit=$exit_code out=$out"
    fi
}

# Test: -r/--rebase form redirects (Fable's edge case — rebase must not walk
# around the gate just because the policy prose only mentions --squash)
test_hook_redirects_rebase() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"gh pr merge --rebase 123"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        pass "'gh pr merge --rebase' redirects (not a bypass route)"
    else
        fail "'gh pr merge --rebase' should redirect, got exit=$exit_code out=$out"
    fi
}

# Test: --auto blocks unconditionally, with a distinct message that does NOT
# route to the wrapper (auto-merge stays permanently banned regardless of
# clearance — never presented as something the wrapper can satisfy)
test_hook_blocks_auto_unconditionally() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"gh pr merge --auto 123"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 2 ] && echo "$out" | grep -qi "unconditionally banned" && ! echo "$out" | grep -qi "^BLOCKED: use scripts/merge-pr.sh"; then
        pass "'gh pr merge --auto' blocks unconditionally, distinct from the redirect message"
    else
        fail "'gh pr merge --auto' should block with an auto-specific message, not a redirect, got exit=$exit_code out=$out"
    fi
}

# Test: unrelated command mentioning "merge" in prose only doesn't false-positive
test_hook_no_false_positive_on_prose() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"git commit -m \"fix: merge conflict in gh pr workflow\""}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "prose mentioning 'gh pr merge'-like words in a commit message doesn't false-trigger"
    else
        fail "unrelated command should exit 0, got exit=$exit_code out=$out"
    fi
}

# Test: description field mentioning merge doesn't false-positive (matches
# codex-gate-check.sh's own round-2 lesson: match only the command field)
test_hook_no_false_positive_on_description_field() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"git status","description":"check status before next gh pr merge"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "unrelated command with 'gh pr merge' only in description field doesn't false-trigger"
    else
        fail "should exit 0 when only description mentions merge, got exit=$exit_code out=$out"
    fi
}

# Test: embedded-quote command still extracts and matches correctly
test_hook_handles_embedded_quotes() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"cd \"$dir\" && gh pr merge --squash 123"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        pass "command with embedded quotes still correctly redirects"
    else
        fail "embedded-quote command should still redirect, got exit=$exit_code out=$out"
    fi
}

# Test: the hook has NO env-var escape at all (ROADMAP #479).
#
# This test used to assert the opposite — that MERGE_CLEARANCE_SKIP=1 bypassed
# the redirect. That variable is gone: it was the single lever that disabled
# every check at once, and its docstring claiming "both scripts must set it,
# intentional friction" was false, since both read the same variable name.
# Inverted rather than deleted, so reintroducing any env bypass fails loudly.
test_hook_has_no_env_bypass() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"gh pr merge --squash 123"}}' | MERGE_CLEARANCE_SKIP=1 "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
        pass "the retired env var does not bypass the redirect hook"
    else
        fail "an env var bypassed the redirect hook, got exit=$exit_code out=$out"
    fi
}

# Test: malformed/missing command field doesn't crash
test_hook_handles_missing_command_field() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"foo":"bar"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "missing command field exits 0 cleanly, no crash"
    else
        fail "missing command field should exit 0, got exit=$exit_code out=$out"
    fi
}

test_hook_exists
test_hook_redirects_bare_merge
test_hook_redirects_squash
test_hook_redirects_dash_m
test_hook_redirects_rebase
test_hook_blocks_auto_unconditionally
test_hook_no_false_positive_on_prose
test_hook_no_false_positive_on_description_field
test_hook_handles_embedded_quotes
test_hook_has_no_env_bypass
test_hook_handles_missing_command_field

# Test: `gh -R owner/repo pr merge` (a global flag between gh and pr) still
# redirects — Codex round-1 finding #1: the original regex required "gh"
# immediately followed by "pr", missing this common, non-adversarial form.
test_hook_redirects_with_global_flag() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"gh -R owner/repo pr merge 123 --squash"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        pass "'gh -R owner/repo pr merge' redirects (global flag between gh and pr)"
    else
        fail "'gh -R owner/repo pr merge' should redirect, got exit=$exit_code out=$out"
    fi
}

# Test: a merge command wrapped in a nested shell invocation still redirects
# — Codex round-1 finding #1: the original masking step collapsed the ENTIRE
# single-quoted nested command into a placeholder before matching, hiding
# "gh pr merge" from detection whenever it appeared inside `bash -lc '...'`.
test_hook_redirects_nested_shell_invocation() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"bash -lc '"'"'gh pr merge 123 --squash'"'"'"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        pass "'bash -lc '\''gh pr merge ...'\''' (nested shell invocation) redirects"
    else
        fail "nested shell invocation of gh pr merge should redirect, got exit=$exit_code out=$out"
    fi
}

# Test: hitting the merge REST endpoint directly via `gh api` also blocks —
# Codex round-1 finding #1: this bypasses the `gh pr merge` phrase match
# entirely since it never says those three words.
test_hook_redirects_gh_api_merge_endpoint() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"gh api -X PUT repos/owner/repo/pulls/123/merge"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        pass "'gh api -X PUT .../pulls/N/merge' (raw REST endpoint) redirects"
    else
        fail "gh api merge-endpoint call should redirect, got exit=$exit_code out=$out"
    fi
}

# Test: a merge command structurally embedded inside prose (not at a command
# boundary) does NOT false-trigger — Codex round-1 finding #6 (P2): the
# original matcher fired on ANY occurrence of the phrase anywhere in the
# command string, including inside explanatory text in a heredoc (this
# happened live to this session's own preflight doc). Tightened to require
# the phrase sit at a command boundary (start of string, or after
# ;/&&/||/|/newline/backtick-open), not mid-sentence prose.
test_hook_no_false_positive_on_embedded_prose() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"cat > doc.md << '"'"'EOF'"'"'\nThe policy requires gh pr merge to go through the wrapper.\nEOF"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "'gh pr merge' embedded mid-sentence in heredoc prose does not false-trigger"
    else
        fail "mid-sentence prose mentioning the phrase should not block, got exit=$exit_code out=$out"
    fi
}

# Test: a quoted STRING ARGUMENT to an unrelated command (printf, not a
# shell-exec wrapper) mentioning the phrase does NOT false-trigger — Codex
# round-2 finding #6: removing all quote-masking (to fix round-1's nested
# `bash -lc '...'` bypass) over-corrected, since any quoted text containing
# the phrase now matched unconditionally, including inert printf/echo
# string arguments that were never going to run as a command.
test_hook_no_false_positive_on_quoted_printf_arg() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"printf '"'"'The policy requires gh pr merge to go through the wrapper.'"'"'"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "'gh pr merge' inside a quoted printf argument does not false-trigger"
    else
        fail "phrase inside an inert printf argument should not block, got exit=$exit_code out=$out"
    fi
}

# Test: a quoted commit message mentioning the phrase does NOT false-trigger
# — same class as above, Codex round-2 finding #6's second example.
test_hook_no_false_positive_on_quoted_commit_message() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"git commit -m '"'"'docs: explain gh pr merge policy'"'"'"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "'gh pr merge' inside a quoted commit message does not false-trigger"
    else
        fail "phrase inside a commit message should not block, got exit=$exit_code out=$out"
    fi
}

# Test: a configured `gh` alias that expands to `pr merge` still redirects —
# Codex round-2 finding #1: literal-text matching alone can't see through
# a user-configured alias (e.g. `gh land` -> `pr merge`), since the
# expansion happens inside gh itself, invisible in the command text. Fixed
# by querying `gh alias list` (confirmed local/instant, ~54ms, no network)
# and treating an invocation of any alias whose expansion contains "pr
# merge" as equivalent to the literal phrase.
test_hook_redirects_configured_alias() {
    local tmpdir out exit_code
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/bin"
    cat > "$tmpdir/bin/gh" <<'STUB'
#!/bin/bash
if [ "$1" = "alias" ] && [ "$2" = "list" ]; then
    echo "land: pr merge"
    exit 0
fi
echo "unstubbed gh invocation in alias test: $*" >&2
exit 1
STUB
    chmod +x "$tmpdir/bin/gh"
    out=$(printf '%s' '{"tool_input":{"command":"gh land 123 --auto"}}' | PATH="$tmpdir/bin:$PATH" "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 2 ]; then
        pass "'gh land' (configured alias for 'pr merge') is blocked like the literal phrase"
    else
        fail "configured alias expanding to 'pr merge' should be blocked, got exit=$exit_code out=$out"
    fi
}

test_hook_redirects_with_global_flag
test_hook_redirects_nested_shell_invocation
test_hook_redirects_gh_api_merge_endpoint
test_hook_no_false_positive_on_quoted_printf_arg
test_hook_no_false_positive_on_quoted_commit_message
test_hook_redirects_configured_alias
test_hook_no_false_positive_on_embedded_prose

echo ""
echo "--- merge-pr.sh (verifying wrapper) ---"

# All wrapper tests run in an isolated tmpdir with a stub `gh` on PATH so no
# real network/GitHub calls happen. The stub reads a small control file to
# decide what to return for each gh subcommand it's asked to fake.

# Fixture clock for the afterhours guard. merge-pr.sh refuses Mon-Fri
# 08:00-16:59, so every wrapper run needs a controlled `date` or the suite's
# result depends on when it runs. FAKE_NOW="<%u> <%H> <%M>" picks the moment;
# the default, Saturday 12:00, is outside the window. The stub expands only
# %u, %H and %M in the format it was ASKED for and fails on any other token, so
# a wrong format in the wrapper goes red instead of getting a canned answer.
# It records the TZ it saw, so a row can prove the caller's TZ never reaches it.
install_fixture_clock() {
    cat > "$1/bin/date" <<'STUB'
#!/bin/bash
printf '%s\n' "${TZ-unset}" > "$(dirname "$0")/../.date-tz"
if [ $# -ne 1 ] || [ "${1#+}" = "$1" ]; then
    echo "date stub: unexpected argv: $*" >&2; exit 2
fi
read -r d h m <<< "${FAKE_NOW:-6 12 00}"
out=${1#+}; out=${out//%u/$d}; out=${out//%H/$h}; out=${out//%M/$m}
case "$out" in *%*) echo "date stub: unsupported format: $1" >&2; exit 2 ;; esac
printf '%s\n' "$out"
STUB
    chmod +x "$1/bin/date"
}

setup_wrapper_fixture() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/bin" "$tmpdir/.reviews" "$tmpdir/tests"
    install_fixture_clock "$tmpdir"
    git init -q "$tmpdir"

    # #540: the merge boundary compares the REMOTE HEAD's TREE against the
    # certified candidate_tree, so the fixture's head can no longer be a
    # made-up string like "abc123" — it has to be an object git can resolve.
    # The fixture therefore makes one real commit and publishes it as both the
    # PR head and origin/<base>. Tests that want a STALE sha still pass a
    # literal; only the "current head" ones read .fixture-sha.
    git -C "$tmpdir" config user.email t@example.com
    git -C "$tmpdir" config user.name "SDLC Test"
    printf 'fixture\n' > "$tmpdir/tests/keep.txt"
    git -C "$tmpdir" add tests/keep.txt
    git -C "$tmpdir" commit -qm fixture
    git -C "$tmpdir" rev-parse HEAD > "$tmpdir/.fixture-sha"
    git -C "$tmpdir" rev-parse 'HEAD^{tree}' > "$tmpdir/.fixture-tree"
    # origin/main must exist: base_tree is compared against the branch the PR
    # actually targets, read from the PR itself rather than assumed.
    git -C "$tmpdir" update-ref refs/remotes/origin/main HEAD

    # #636: A SECOND COMMIT WITH THE IDENTICAL TREE. This is the minimal
    # instance of the ancestry class — the base MOVED, and every field #540
    # enforces still matches, because a tree carries no ancestry.
    #
    # The real-world trigger is a revert: main takes a commit the PR also
    # contains, then reverts it, and main's tree returns byte-for-byte to where
    # the reviewers read it while the merge base advances past it. An empty
    # commit reproduces the same fields (new sha, same tree) in one line
    # instead of four, and the gate cannot tell the two apart — which is the
    # point.
    git -C "$tmpdir" commit -q --allow-empty -m "base moved, tree identical"
    git -C "$tmpdir" rev-parse HEAD > "$tmpdir/.fixture-base-moved-sha"
    # Rewound so this commit is reachable-but-not-current: only rows that
    # deliberately point the live base at it are affected.
    git -C "$tmpdir" reset -q --hard "$(cat "$tmpdir/.fixture-sha")"

    # Control file the stub gh reads: one KEY=VALUE per line.
    # HEAD_SHA, VALIDATE_CONCLUSION, DIFF_FILES (newline-separated, base64
    # would be overkill — use a sentinel-delimited list), DELETED_TEST_FILES,
    # RENAMED_TEST_FILES (space-separated "old->new" pairs, old under tests/,
    # new NOT under tests/ — simulates an effective deletion via rename),
    # PACKAGE_JSON_VERSION_CHANGED (boolean flag — the actual patch text
    # is hardcoded in the stub below, not passed through this sourced
    # config file, since embedding raw diff syntax like `+`/`-`/newlines
    # in a shell-sourced KEY=VALUE line is fragile), and BEYOND_FIRST_PAGE
    # (a filename only returned by the pulls/files stub when the real
    # command includes --paginate — simulates gh's default single-page
    # API behavior). package.json's patch is only available via the
    # pulls/files endpoint — NOT via `gh pr diff`, which has no per-path
    # filter flag.
    cat > "$tmpdir/.gh-stub-config" <<'CONFIG'
HEAD_SHA=__FIXTURE_SHA__
BASE_REF=main
VALIDATE_CONCLUSION=success
EXTRA_VALIDATE_CONCLUSION=
DIFF_FILES=src/foo.js
DELETED_TEST_FILES=
RENAMED_TEST_FILES=
PACKAGE_JSON_VERSION_CHANGED=
BEYOND_FIRST_PAGE=
CLEARANCE_PAYLOADS=
CONFIG
    # Splice the real sha in after the heredoc, which is quoted so it cannot
    # expand.
    sed -i.bak "s/__FIXTURE_SHA__/$(cat "$tmpdir/.fixture-sha")/" "$tmpdir/.gh-stub-config"
    rm -f "$tmpdir/.gh-stub-config.bak"

    cat > "$tmpdir/bin/gh" <<'STUB'
#!/bin/bash
CONFIG="$(dirname "$0")/../.gh-stub-config"
# shellcheck disable=SC1090
[ -f "$CONFIG" ] && source "$CONFIG"

if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
    # The wrapper now asks for changedFiles separately to prove the classified
    # path set is complete; answer with the fixture's real count.
    case "$*" in
        *changedFiles*)
            n=0
            for _f in $DIFF_FILES; do n=$((n+1)); done
            for _f in ${DELETED_TEST_FILES:-}; do n=$((n+1)); done
            [ "$n" -eq 0 ] && n=1
            echo "$n"; exit 0 ;;
    esac
    # baseRefOid is SERVER truth about where the base branch is now. The local
    # refs/remotes/origin/<base> tracking ref is a cache and can be stale or
    # absent; both reviewers broke the gate through it in round 1.
    echo "{\"headRefOid\":\"$HEAD_SHA\",\"number\":${PR_NUM:-123},\"state\":\"OPEN\",\"baseRefName\":\"${BASE_REF:-main}\",\"baseRefOid\":\"${BASE_OID:-$HEAD_SHA}\"}"
    exit 0
elif [ "$1" = "pr" ] && [ "$2" = "diff" ]; then
    printf '%s\n' "$DIFF_FILES"
    exit 0
elif [ "$1" = "api" ]; then
    case "$*" in
        *git/ref/heads/*)
            # WHERE THE BASE BRANCH IS NOW. Deliberately a DIFFERENT knob from
            # BASE_OID, which the pr-view stub still emits as `baseRefOid`.
            # Round 2 read baseRefOid and was wrong: that field is the base
            # commit ASSOCIATED WITH THE PR, a snapshot that does not move when
            # the branch does. Measured live on this repo — PR #615 carried
            # baseRefOid f8ba12b while main was at d0e1c7b. The two knobs are
            # split here so a row can make them disagree the way GitHub does,
            # and so reverting the source to baseRefOid stays red forever.
            echo "{\"object\":{\"sha\":\"${LIVE_BASE_OID:-$HEAD_SHA}\"}}"
            exit 0 ;;
        *check-runs*)
            # REAL envelope: {"total_count":N,"check_runs":[...]}, one such object
            # per page, which is how `gh --paginate` concatenates pages. Codex
            # round 2: this stub emitted bare concatenated objects, exercising
            # NEITHER shape GitHub actually returns — so the extraction was being
            # validated against a payload that does not exist, and a real
            # bare-array page was silently dropped by the unwrap.
            #
            # A SECOND run also named "validate": branch protection requires the
            # check by NAME, so more than one can exist and the wrapper must not
            # stop at the first. `null` is emitted UNQUOTED, as a queued or
            # in-progress run really is, and "name" precedes "conclusion" as it
            # does live (the opposite of the API docs example).
            echo "{\"total_count\":1,\"check_runs\":[{\"name\":\"validate\",\"status\":\"completed\",\"conclusion\":\"$VALIDATE_CONCLUSION\"}]}"
            if [ -n "${EXTRA_VALIDATE_CONCLUSION:-}" ]; then
                if [ "$EXTRA_VALIDATE_CONCLUSION" = "null" ]; then
                    extra='{"name":"validate","status":"in_progress","conclusion":null}'
                else
                    extra="{\"name\":\"validate\",\"status\":\"completed\",\"conclusion\":\"$EXTRA_VALIDATE_CONCLUSION\"}"
                fi
                # EXTRA_VALIDATE_PAGE_SHAPE=bare emits a page as a naked array,
                # the shape the round-2 finding is about.
                case "${EXTRA_VALIDATE_PAGE_SHAPE:-wrapped}" in
                    bare) echo "[$extra]" ;;
                    *)    echo "{\"total_count\":1,\"check_runs\":[$extra]}" ;;
                esac
            fi
            ;;
        *issues*comments*)
            # Cross-model clearance comments. CLEARANCE_PAYLOADS holds one
            # compact JSON object per line; each becomes a PR comment wrapping
            # that object in the required marker + fenced json block.
            printf '['
            _first=1
            while IFS= read -r payload; do
                [ -z "$payload" ] && continue
                [ "$_first" -eq 0 ] && printf ','
                _first=0
                # Escape BACKSLASHES before quotes. Without this a payload
                # containing v was decoded by jq while parsing the comment
                # body, so it reached the parser as a plain literal and the
                # unicode-escape test silently tested nothing. GitHub's API
                # returns a real comment's backslash as \\, which is what this
                # now reproduces.
                # __FIXTURE_SHA__ resolves here rather than in the config,
                # because #540 made the fixture head a real git object and a
                # test cannot know its value at authoring time.
                payload=${payload//__FIXTURE_SHA__/$HEAD_SHA}
                printf '{"user":{"login":"maintainer"},"author_association":"OWNER","body":"**CROSS-MODEL-CLEARANCE**\\n\\n```json\\n%s\\n```"}' \
                    "$(printf '%s' "$payload" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
            done <<< "${CLEARANCE_PAYLOADS:-}"
            printf ']'
            ;;
        *pulls*files*)
            # Tier classification now reads THIS endpoint, not `gh pr diff`
            # (Codex round-2: diff output is display text and caps at 300
            # files). So it must list every changed path, not just deletions.
            for f in $DIFF_FILES; do
                echo "{\"filename\":\"$f\",\"status\":\"modified\"}"
            done
            if [ -n "$DELETED_TEST_FILES" ]; then
                for f in $DELETED_TEST_FILES; do
                    echo "{\"filename\":\"$f\",\"status\":\"removed\"}"
                done
            fi
            if [ -n "$RENAMED_TEST_FILES" ]; then
                for pair in $RENAMED_TEST_FILES; do
                    old="${pair%%->*}"
                    new="${pair##*->}"
                    echo "{\"filename\":\"$new\",\"status\":\"renamed\",\"previous_filename\":\"$old\"}"
                done
            fi
            if [ -n "$PACKAGE_JSON_VERSION_CHANGED" ]; then
                printf '%s\n' '{"filename":"package.json","status":"modified","patch":"@@ -1,3 +1,3 @@\n {\n-  \"version\": \"1.0.0\",\n+  \"version\": \"1.0.1\","}'
            fi
            if [ -n "$BEYOND_FIRST_PAGE" ]; then
                case "$*" in
                    *--paginate*)
                        echo "{\"filename\":\"$BEYOND_FIRST_PAGE\",\"status\":\"removed\"}"
                        ;;
                esac
            fi
            ;;
    esac
    exit 0
elif [ "$1" = "pr" ] && [ "$2" = "comment" ]; then
    # The override record. COMMENT_FAILS=1 simulates the post failing, which
    # must block the merge — an unrecorded override is exactly what
    # --user-approved exists to prevent.
    if [ "${COMMENT_FAILS:-0}" = "1" ]; then
        echo "stub: comment post failed" >&2
        exit 1
    fi
    # The wrapper suppresses gh's stdout, so the posted BODY is invisible to a
    # test that only reads the wrapper's output — which is exactly how the
    # round-1 record tests came to assert on a confirmation phrase instead of on
    # the payload. Persist it so the payload itself can be asserted.
    # Prefix EVERY line: a record body is multi-line, so an unprefixed dump is
    # unassertable with line-based grep — the path would sit on a different line
    # from the marker and a naive assertion would silently never match.
    printf '%s\n' "$*" | sed 's/^/GH_COMMENT_BODY: /' >> "$(dirname "$0")/../.posted-comments"
    echo "GH_COMMENT_POSTED: $*"
    exit 0
elif [ "$1" = "pr" ] && [ "$2" = "merge" ]; then
    echo "GH_MERGE_INVOKED: $*"
    exit 0
fi
echo "unstubbed gh invocation: $*" >&2
exit 1
STUB
    chmod +x "$tmpdir/bin/gh"
    echo "$tmpdir"
}

write_clearance() {
    local tmpdir="$1" pr="$2" status="$3" round="$4" sha="$5" review_file="$6"
    # #540: a clearance names the CONTENT it was issued over, not just the
    # commit it sat on. Both default to the fixture's real trees so existing
    # rows keep testing what they were written to test; pass 7/8 to certify
    # content that is deliberately wrong.
    local cand="${7:-$(cat "$tmpdir/.fixture-tree")}"
    local base="${8:-$(cat "$tmpdir/.fixture-tree")}"
    # #563: arg 9 is a raw `reviewers` array body. DELIBERATELY EMPTY BY
    # DEFAULT, and that default is load-bearing: every artifact written before
    # #563 carries no findings_total at all, and those must keep taking the
    # round >= 2 path unchanged. A default of "two reviewers at zero" would
    # silently hand every existing round-1 row the new exemption and hide the
    # fail-closed behaviour this field exists to have.
    local reviewers="${9:-}"
    # #636: WHERE the base was, not just what it contained. Defaults to the
    # fixture's real base commit so every pre-existing row keeps testing what it
    # was written to test. Deliberately independent of arg 5 — several rows pass
    # a deliberately stale head sha there, and the base is a separate fact.
    local base_sha="${10:-$(cat "$tmpdir/.fixture-sha")}"
    # Round 2 (Sol): arg 11 is raw JSON emitted BEFORE every contract field, so
    # a row can place a NESTED object carrying the same key names ahead of the
    # real ones. Order is the whole point — the reader took the first match in
    # the file, so a nested value only masks a top-level one by preceding it.
    local extra="${11:-}"
    # Arg 12 is the same thing AFTER the reviewers array. Both positions are
    # needed and neither substitutes: `head -1` reads the FIRST occurrence and
    # a greedy `.*` reads the LAST, so a masking value has to be placed on the
    # correct side of the real field to reproduce each defect.
    local extra_after="${12:-}"
    {
        printf '{\n'
        printf '  "pr_number": %s,\n' "$pr"
        [ -n "$extra" ] && printf '  %s,\n' "$extra"
        printf '  "status": "%s",\n' "$status"
        printf '  "round": %s,\n' "$round"
        printf '  "sha": "%s",\n' "$sha"
        printf '  "candidate_tree": "%s",\n' "$cand"
        printf '  "base_tree": "%s",\n' "$base"
        printf '  "base_sha": "%s",\n' "$base_sha"
        [ -n "$reviewers" ] && printf '  "reviewers": [%s],\n' "$reviewers"
        [ -n "$extra_after" ] && printf '  %s,\n' "$extra_after"
        printf '  "review_file": "%s"\n' "$review_file"
        printf '}\n'
    } > "$tmpdir/.reviews/merge-clearance-$pr.json"
}

# #563 helper: a reviewers-array body with N entries, each at findings_total=$2.
# Kept as a function rather than inline JSON so a row states its INTENT ("two
# reviewers, both clean") instead of a wall of braces that has to be re-read.
reviewers_with() {
    local count="$1" total="$2" i out=""
    for i in $(seq 1 "$count"); do
        [ -n "$out" ] && out="$out,"
        out="$out{\"model\":\"r$i\",\"verdict\":\"CERTIFIED\",\"confidence\":97,\"findings_total\":$total}"
    done
    printf '%s' "$out"
}

# Test: wrapper script exists and is executable (guards the tests below —
# without this, a missing-script "No such file or directory" error can
# coincidentally satisfy a loose substring match, e.g. the path itself
# containing "pr" or "merge-pr.sh", and false-PASS before any real code runs)
test_wrapper_exists() {
    if [ -x "$WRAPPER" ]; then
        pass "merge-pr.sh exists and is executable"
    else
        fail "merge-pr.sh not found or not executable at $WRAPPER"
    fi
}

# Test: no PR argument
test_wrapper_requires_pr_arg() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "usage" && ! echo "$out" | grep -q "No such file or directory"; then
        pass "wrapper requires a PR number argument"
    else
        fail "wrapper should fail with a usage message when no PR arg given, got exit=$exit_code out=$out"
    fi
}

# Test: gh failure fails closed
test_wrapper_fails_closed_on_gh_error() {
    local tmpdir out exit_code
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/bin"
    install_fixture_clock "$tmpdir"
    cat > "$tmpdir/bin/gh" <<'STUB'
#!/bin/bash
echo "network error" >&2
exit 1
STUB
    chmod +x "$tmpdir/bin/gh"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "No such file or directory"; then
        pass "wrapper fails closed when gh errors"
    else
        fail "wrapper should fail closed on gh error, got exit=$exit_code out=$out"
    fi
}

# Test: CI validate pending blocks
test_wrapper_blocks_ci_pending() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's/VALIDATE_CONCLUSION=success/VALIDATE_CONCLUSION=pending/' "$tmpdir/.gh-stub-config"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "pending"; then
        pass "wrapper blocks when CI validate is pending"
    else
        fail "wrapper should block on pending validate, got exit=$exit_code out=$out"
    fi
}

# Test: CI validate skipped blocks (not treated as pass)
test_wrapper_blocks_ci_skipped() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's/VALIDATE_CONCLUSION=success/VALIDATE_CONCLUSION=skipped/' "$tmpdir/.gh-stub-config"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "skipped"; then
        pass "wrapper blocks when CI validate is skipped"
    else
        fail "wrapper should block on skipped validate, got exit=$exit_code out=$out"
    fi
}

# Test: CI validate neutral blocks
test_wrapper_blocks_ci_neutral() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's/VALIDATE_CONCLUSION=success/VALIDATE_CONCLUSION=neutral/' "$tmpdir/.gh-stub-config"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "neutral"; then
        pass "wrapper blocks when CI validate is neutral"
    else
        fail "wrapper should block on neutral validate, got exit=$exit_code out=$out"
    fi
}

# Test: missing clearance file blocks, naming the missing file
test_wrapper_blocks_missing_clearance() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "merge-clearance-123"; then
        pass "wrapper blocks and names the missing clearance file"
    else
        fail "wrapper should block naming merge-clearance-123.json, got exit=$exit_code out=$out"
    fi
}

# Test: clearance status != CERTIFIED blocks
test_wrapper_blocks_non_certified_status() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "PENDING_REVIEW" 1 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "PENDING_REVIEW\|CERTIFIED"; then
        pass "wrapper blocks when clearance status isn't CERTIFIED"
    else
        fail "wrapper should block on non-CERTIFIED status, got exit=$exit_code out=$out"
    fi
}

# Test: round-1-only CERTIFIED is treated as suspicious and blocks
test_wrapper_blocks_round_1_only() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "round"; then
        pass "wrapper blocks a round-1-only CERTIFIED as insufficient dialogue"
    else
        fail "wrapper should block round=1 CERTIFIED, got exit=$exit_code out=$out"
    fi
}

# --- #636: a tree carries no ancestry ---
#
# #540 bound certification to CONTENT rather than to a SHA, and that was right.
# But it bound the content at the two ENDPOINTS and modelled the base as a tree.
# The base is a POSITION IN A HISTORY. A PR diff is three-dot, so what actually
# merges depends on the merge base — and the merge base can move while `sha`,
# `candidate_tree` and `base_tree` all stay byte-identical.
#
# Reproduced with real git objects during #521's design review: reviewed base
# tree matched live, candidate tree matched, and `git merge-tree` produced a
# prospective merge containing only HALF the reviewed content.
test_wrapper_blocks_moved_base_with_identical_tree() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # The live base is a DIFFERENT commit with the SAME tree. Every field the
    # gate enforces today matches; only ancestry moved.
    echo "LIVE_BASE_OID=$(cat "$tmpdir/.fixture-base-moved-sha")" >> "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    # Asserting the SPECIFIC refusal. A generic non-zero exit would also be
    # satisfied by the tree-mismatch check further down, which cannot fire here
    # by construction — the trees are equal, that is the whole scenario.
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "base_sha"; then
        pass "wrapper blocks when the base moved to a commit with an identical tree"
    else
        fail "wrapper should block a moved base with an identical tree, got exit=$exit_code out=$out"
    fi
}

# ---------------------------------------------------------------------------
# ROUND 2 (Sol, P1): A NESTED KEY IS NOT A CONTRACT FIELD.
#
# Every contract field was read with `grep -o '"field".."' | head -1` — the
# FIRST occurrence anywhere in the file, at any nesting depth. So an object
# nested ahead of the real field supplies the value the gate compares, and the
# top-level field the certification actually declares is never read.
#
# Sol executed this against base_sha: live base moved to a different commit,
# `"metadata": {"base_sha": "<live>"}` placed before a stale top-level
# `"base_sha": "<old>"`. The nested value matched the live base, so the ancestry
# check passed and it merged at exit 0 — the exact hole #636 exists to close,
# reopened by the parser reading it.
#
# It is a CLASS defect, not one field's: the same read shape backs status,
# round, sha, candidate_tree, base_tree and review_file. Rows below cover the
# two that authorize content and ancestry; fixing only the one Sol demonstrated
# would leave the other five standing.
test_wrapper_blocks_nested_base_sha_masking_a_stale_one() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    echo "LIVE_BASE_OID=$(cat "$tmpdir/.fixture-base-moved-sha")" >> "$tmpdir/.gh-stub-config"
    # Top-level base_sha is the ORIGINAL base — stale, and the gate must refuse
    # on it. The nested one matches the live base and must be invisible.
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" \
        "" "" "" "$(cat "$tmpdir/.fixture-sha")" \
        "\"metadata\": {\"base_sha\": \"$(cat "$tmpdir/.fixture-base-moved-sha")\"}"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "base branch moved"; then
        pass "wrapper ignores a nested base_sha and refuses on the top-level one"
    else
        fail "wrapper should read base_sha only at the top level, got exit=$exit_code out=$out"
    fi
}

test_wrapper_blocks_nested_candidate_tree_masking_a_stale_one() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # Same shape, different field — this is the one that binds CONTENT. The
    # top-level candidate_tree certifies a tree that is not what would merge.
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" \
        "0000000000000000000000000000000000000000" "" "" "" \
        "\"metadata\": {\"candidate_tree\": \"$(cat "$tmpdir/.fixture-tree")\"}"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "not the content that was certified"; then
        pass "wrapper ignores a nested candidate_tree and refuses on the top-level one"
    else
        fail "wrapper should read candidate_tree only at the top level, got exit=$exit_code out=$out"
    fi
}

# ROUND 2 (Sol, P1): the verdict check matched "CERTIFIED" ANYWHERE in the
# entry rather than as the value OF the verdict key. A reviewer declaring
# NOT_CERTIFIED alongside any other field whose value happens to contain the
# word — a note, a filename, a quoted refusal message — was counted as clean.
# Sol executed it: `"verdict":"NOT_CERTIFIED","note":"CERTIFIED"` took the
# round-1 exemption and merged at exit 0.
test_wrapper_blocks_round_1_when_certified_appears_outside_the_verdict() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" \
        "" "" '{"model":"r1","verdict":"CERTIFIED","findings_total":0},{"model":"r2","verdict":"NOT_CERTIFIED","note":"CERTIFIED","findings_total":0}'
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "wrapper reads CERTIFIED as the verdict's value, not as text anywhere in the entry"
    else
        fail "wrapper should block a NOT_CERTIFIED reviewer whose other fields contain 'CERTIFIED', got exit=$exit_code out=$out"
    fi
}

# ---------------------------------------------------------------------------
# ROUND 2 (Fable, P1/P2): THE REVIEWERS SLICE WAS A REGEX, AND AN ARRAY IS NOT
# A REGULAR LANGUAGE.
#
# The block was cut with `sed 's/.*"reviewers"...\[\([^]]*\)\].*/\1/'`. Two
# executed counterexamples merged at exit 0:
#
#   PROBE-A: `[^]]*` stops at the FIRST `]` in the file. A nested array inside
#   an early clean entry (`"tags":[1]`) truncated the block there, so a LATER
#   entry recording five findings was never seen. Two clean reviewers, zero
#   dirty, exemption granted — while a reviewer had findings.
#
#   PROBE-B: the leading `.*` is greedy, so it takes the LAST `"reviewers":[`
#   in the file. A nested `history.round0.reviewers` array of clean entries
#   overrode the real top-level array holding one NOT_CERTIFIED reviewer with
#   four findings.
#
# Round 1's "fail closed by construction" was argued for nested OBJECTS and is
# false for nested ARRAYS and duplicate keys. It is also false for a `]` inside
# a quoted string, which neither probe used and which truncates identically —
# so the block is now extracted by a depth- and string-aware walk rather than
# hardened case by case, and a duplicate top-level key is refused as ambiguous.
test_wrapper_blocks_round_1_when_a_nested_array_hides_a_dirty_reviewer() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" \
        "" "" '{"model":"r1","verdict":"CERTIFIED","findings_total":0},{"model":"r2","verdict":"CERTIFIED","findings_total":0,"tags":[1]},{"model":"r3","verdict":"CERTIFIED","findings_total":5}'
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "a nested array in one entry does not truncate the reviewers block"
    else
        fail "wrapper should see the dirty third reviewer past a nested array, got exit=$exit_code out=$out"
    fi
}

test_wrapper_blocks_round_1_when_a_string_bracket_hides_a_dirty_reviewer() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # Same truncation, no nesting at all — a `]` inside a quoted value. This is
    # the variant a "refuse blocks containing [" guard would let through.
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" \
        "" "" '{"model":"r1","verdict":"CERTIFIED","findings_total":0},{"model":"r2","verdict":"CERTIFIED","findings_total":0,"note":"see [1] above]"},{"model":"r3","verdict":"CERTIFIED","findings_total":7}'
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "a ']' inside a quoted value does not truncate the reviewers block"
    else
        fail "wrapper should see the dirty third reviewer past a bracket in a string, got exit=$exit_code out=$out"
    fi
}

test_wrapper_blocks_round_1_when_a_nested_reviewers_array_shadows_the_real_one() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # The REAL array is one NOT_CERTIFIED reviewer with findings. A nested
    # history block afterwards holds two clean ones.
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" \
        "" "" '{"model":"sol","verdict":"NOT_CERTIFIED","findings_total":4}' "" "" \
        '"history": {"round0": {"reviewers": [{"model":"a","verdict":"CERTIFIED","findings_total":0},{"model":"b","verdict":"CERTIFIED","findings_total":0}]}}'
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "a nested reviewers array does not shadow the top-level one"
    else
        fail "wrapper should read the top-level reviewers array, got exit=$exit_code out=$out"
    fi
}

test_wrapper_blocks_round_1_on_duplicate_reviewers_keys() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # Two top-level reviewers keys. JSON parsers disagree about which wins, so
    # the gate refuses rather than picking — a certification that cannot be
    # read one way is not a certification.
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" \
        "" "" "$(reviewers_with 2 0)" "" \
        '"reviewers": [{"model":"x","verdict":"NOT_CERTIFIED","findings_total":9}]'
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "more than once"; then
        pass "two top-level reviewers keys are refused as ambiguous"
    else
        fail "wrapper should refuse a duplicated reviewers key, got exit=$exit_code out=$out"
    fi
}

# The counterpart the refusals above would otherwise be satisfied by: a nested
# array in an entry is LEGAL JSON, and a clearance carrying one must still take
# the exemption. Without this row, "block anything containing a bracket" would
# pass every test above while being wrong.
test_wrapper_allows_round_1_two_clean_reviewers_with_a_nested_array() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" \
        "" "" '{"model":"r1","verdict":"CERTIFIED","findings_total":0,"tags":["a","b"]},{"model":"r2","verdict":"CERTIFIED","findings_total":0}'
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ] && echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "two clean reviewers still take the exemption when an entry carries a nested array"
    else
        fail "a legal nested array should not defeat the exemption, got exit=$exit_code out=$out"
    fi
}

# ---------------------------------------------------------------------------
# ROUND 3 (Fable + Sol, converging): AMBIGUITY WAS RESOLVED BY POSITION INSTEAD
# OF REFUSED, AND NEITHER WALK CHECKED WHETHER IT HAD PARSED ANYTHING.
#
# Round 2 established the principle in two places — a duplicated top-level
# `reviewers` key and a duplicated `verdict` inside an entry are REFUSED rather
# than resolved. The principle was right and was applied to exactly those two
# keys; every other key kept reading first-wins, which is the opposite of what
# a JSON parser does. Nine artifacts were executed against that gap and all
# nine merged at exit 0.
#
# These rows are what forced the design escalation: the fix is no longer a
# hand-written walk but a strict parse, so the rows below are the specification
# that parse has to meet.
raw_clearance() {
    cat > "$1/.reviews/merge-clearance-123.json"
    echo "content" > "$1/.reviews/some-review.md"
}

# The entry says zero, then says seven. First-wins read it as clean; a JSON
# parser reads seven. The exemption was granted to an artifact with findings.
test_wrapper_blocks_round_1_on_duplicate_findings_total_in_an_entry() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" \
        "" "" '{"model":"r1","verdict":"CERTIFIED","findings_total":0,"findings_total":7},{"model":"r2","verdict":"CERTIFIED","findings_total":0}'
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "an entry declaring findings_total twice is refused, not resolved first-wins"
    else
        fail "duplicate findings_total in an entry should block, got exit=$exit_code out=$out"
    fi
}

# 0.5 is valid JSON and is not zero. A digit-PREFIX match read it as 0.
test_wrapper_blocks_round_1_on_a_non_integer_findings_total() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" \
        "" "" '{"model":"r1","verdict":"CERTIFIED","findings_total":0.5},{"model":"r2","verdict":"CERTIFIED","findings_total":0.5}'
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "a non-integer findings_total does not parse as its leading digit"
    else
        fail "findings_total 0.5 should not count as zero, got exit=$exit_code out=$out"
    fi
}

# 0.0 is the discriminating case for the TYPE check specifically: it equals
# zero numerically, so a guard that only compares values still clears it. Only
# a guard that requires an INTEGER refuses. Without this row the type check
# survives its own mutation — which is how it shipped untested the first time.
test_wrapper_blocks_round_1_on_a_float_zero_findings_total() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" \
        "" "" '{"model":"r1","verdict":"CERTIFIED","findings_total":0.0},{"model":"r2","verdict":"CERTIFIED","findings_total":0.0}'
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "findings_total 0.0 is not an integer count, even though it equals zero"
    else
        fail "a float zero findings_total should not clear, got exit=$exit_code out=$out"
    fi
}

# A reviewers entry that is not an object at all. It is still a reviewer and
# never a clean one — the same direction as an entry omitting its count.
# Discriminates the "count it anyway" branch, which is otherwise unreachable.
test_wrapper_blocks_round_1_when_a_reviewers_entry_is_not_an_object() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" \
        "" "" '{"model":"r1","verdict":"CERTIFIED","findings_total":0},{"model":"r2","verdict":"CERTIFIED","findings_total":0},"a bare string"'
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "a non-object reviewers entry counts as a reviewer and never as a clean one"
    else
        fail "a bare string in the reviewers array should block, got exit=$exit_code out=$out"
    fi
}

# status CERTIFIED, then status NOT_CERTIFIED. Pre-existing first-wins read,
# swept in rather than deferred because the same commit rewrote this read.
test_wrapper_blocks_duplicate_status_keys() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    raw_clearance "$tmpdir" <<JSON
{
  "pr_number": 123,
  "status": "CERTIFIED",
  "status": "NOT_CERTIFIED",
  "round": 2,
  "sha": "$(cat "$tmpdir/.fixture-sha")",
  "candidate_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_sha": "$(cat "$tmpdir/.fixture-sha")",
  "review_file": ".reviews/some-review.md"
}
JSON
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "more than once"; then
        pass "a duplicated top-level status key is refused as ambiguous"
    else
        fail "duplicate status keys should block, got exit=$exit_code out=$out"
    fi
}

# The same shape on the field #636 exists to bind: live base first, stale base
# second. The gate cleared an ancestry the artifact's JSON meaning does not name.
test_wrapper_blocks_duplicate_base_sha_keys() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    raw_clearance "$tmpdir" <<JSON
{
  "pr_number": 123,
  "status": "CERTIFIED",
  "round": 2,
  "sha": "$(cat "$tmpdir/.fixture-sha")",
  "candidate_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_sha": "$(cat "$tmpdir/.fixture-sha")",
  "base_sha": "0000000000000000000000000000000000000000",
  "review_file": ".reviews/some-review.md"
}
JSON
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "more than once"; then
        pass "a duplicated top-level base_sha key is refused as ambiguous"
    else
        fail "duplicate base_sha keys should block, got exit=$exit_code out=$out"
    fi
}

# The parse is strict; the CHANNEL it writes to was not. Contract fields are
# projected as "key\tvalue" lines and read back with `head -1`, and the three
# derived counts are emitted last. A string value carrying a newline and tabs
# injects earlier count rows that win the `head -1` read, so an artifact
# declaring NO reviewers at all takes the round-1 exemption as "2 reviewers,
# zero findings". Legal JSON throughout — \n and \t are standard escapes, so
# nothing upstream of the projection can see it.
test_wrapper_blocks_tsv_injection_through_a_string_field() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    raw_clearance "$tmpdir" <<JSON
{
  "pr_number": 123,
  "status": "CERTIFIED",
  "round": 1,
  "sha": "$(cat "$tmpdir/.fixture-sha")",
  "candidate_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_sha": "$(cat "$tmpdir/.fixture-sha")\nreviewer_count\t2\nclean_count\t2\ndirty_count\t0",
  "review_file": ".reviews/some-review.md",
  "reviewers": []
}
JSON
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "a control character in a projected string field cannot forge the reviewer counts"
    else
        fail "TSV injection through base_sha should block, got exit=$exit_code out=$out"
    fi
}

# The same seam aimed at ANCESTRY rather than at the counts. `status` is emitted
# first, so rows injected through it win the `head -1` read for every field that
# follows — including the three #636 binds. The artifact's real sha, trees and
# base_sha are all garbage; the injected rows supply live ones.
test_wrapper_blocks_tsv_injection_forging_the_ancestry_binds() {
    local tmpdir out exit_code sha tree
    tmpdir=$(setup_wrapper_fixture)
    sha=$(cat "$tmpdir/.fixture-sha")
    tree=$(cat "$tmpdir/.fixture-tree")
    raw_clearance "$tmpdir" <<JSON
{
  "pr_number": 123,
  "status": "CERTIFIED\nsha\t$sha\ncandidate_tree\t$tree\nbase_tree\t$tree\nbase_sha\t$sha\nreview_file\t.reviews/some-review.md",
  "round": 2,
  "sha": "0000000000000000000000000000000000000000",
  "candidate_tree": "0000000000000000000000000000000000000000",
  "base_tree": "0000000000000000000000000000000000000000",
  "base_sha": "0000000000000000000000000000000000000000",
  "review_file": ".reviews/nonexistent-review.md"
}
JSON
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "a control character in status cannot forge the content and ancestry binds"
    else
        fail "TSV injection through status should block, got exit=$exit_code out=$out"
    fi
}

# The other half of the same seam, and it does not need a row separator. NUL is
# legal JSON (\u0000), python emits it, and the shell DELETES it from a command
# substitution. So every string bind can be written with a NUL in the middle and
# normalize to the live value only after the parse: what a JSON reader sees in
# the artifact is not what the gate compares. Refusing an enumerated set of
# separators misses this; the refusal has to be the whole control-character
# class.
test_wrapper_blocks_nul_normalising_a_string_field() {
    local tmpdir out exit_code sha tree
    tmpdir=$(setup_wrapper_fixture)
    sha=$(cat "$tmpdir/.fixture-sha")
    tree=$(cat "$tmpdir/.fixture-tree")
    raw_clearance "$tmpdir" <<JSON
{
  "pr_number": 123,
  "status": "CERT\u0000IFIED",
  "round": 2,
  "sha": "${sha:0:20}\u0000${sha:20}",
  "candidate_tree": "${tree:0:20}\u0000${tree:20}",
  "base_tree": "${tree:0:20}\u0000${tree:20}",
  "base_sha": "${sha:0:20}\u0000${sha:20}",
  "review_file": ".reviews/some\u0000-review.md"
}
JSON
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "a NUL byte cannot normalise a string field into a live value after the parse"
    else
        fail "NUL normalisation should block, got exit=$exit_code out=$out"
    fi
}

# The row above is NOT sufficient, and this row exists because review proved it.
# That artifact puts a NUL in `sha` as well, so it is refused by the object-name
# grammar and the control-character class refusal is never reached: narrow the
# class back to {tab, newline, CR} and the suite still goes fully green. `status`
# is the only field the class refusal SOLELY guards — no grammar constrains it —
# so the isolation has to be a NUL in status with every other field clean.
# Under the narrowed class this artifact merges at exit 0, which is the round-5
# normalisation exploit intact.
test_wrapper_blocks_nul_in_status_with_every_other_field_clean() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    raw_clearance "$tmpdir" <<JSON
{
  "pr_number": 123,
  "status": "CERT\u0000IFIED",
  "round": 2,
  "sha": "$(cat "$tmpdir/.fixture-sha")",
  "candidate_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_sha": "$(cat "$tmpdir/.fixture-sha")",
  "review_file": ".reviews/some-review.md"
}
JSON
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "contains a control character"; then
        pass "the control-character class refusal is proven on the one field it solely guards"
    else
        fail "a NUL in status alone should block via the class refusal, got exit=$exit_code out=$out"
    fi
}

# The object-name grammar is NOT load-bearing for safety and this row says so
# honestly: a non-hex sha never matched the live head anyway, so the staleness
# comparison already blocked it. What the grammar changes is WHERE and WHY it is
# refused — at the parse, named as malformed, before any comparison runs. That
# is the behaviour asserted here, and it is the only thing about this guard that
# is provable today. Its real value is invariance if one of these values ever
# reaches a different sink; that value cannot be tested until such a sink
# exists, and is disclosed in known_limits rather than claimed.
test_wrapper_refuses_a_malformed_object_name_at_the_parse() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "not-a-real-object-name" ".reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "not a well-formed git object name"; then
        pass "a malformed object name is refused at the parse, not at the comparison"
    else
        fail "malformed sha should be refused as malformed, got exit=$exit_code out=$out"
    fi
}

# POSITIVE ROW, and the only survivor of the deleted path guard (#645). The
# grammar and the realpath containment check that used to run on review_file are
# gone: they bought no security property any test could state, because nothing
# binds this file's CONTENT to anything, and they cost false refusals. This row
# is what stops them coming back. Any path check re-added here fails it, since a
# space is legal in a repository path and every such rule refused it. It asserts
# a criterion-4 property — a legitimate round >= 2 artifact still merges — which
# survives the guard's deletion because it was never about the guard.
test_wrapper_allows_a_review_file_path_containing_a_space() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    echo "content" > "$tmpdir/.reviews/review notes.md"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/review notes.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ] && echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "a legitimate review_file path containing a space still merges"
    else
        fail "a space in a repo-relative review_file should merge, got exit=$exit_code out=$out"
    fi
}

# The object-name grammar was mapped over four fields and only `sha` was rowed,
# so deleting the other three mappings left the suite green. One row per field.
test_wrapper_refuses_a_malformed_candidate_tree() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" "not-a-tree"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "candidate_tree.*not a well-formed"; then
        pass "a malformed candidate_tree is refused at the parse"
    else
        fail "malformed candidate_tree should be refused, got exit=$exit_code out=$out"
    fi
}

test_wrapper_refuses_a_malformed_base_tree() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" \
        "$(cat "$tmpdir/.fixture-tree")" "not-a-tree"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "base_tree.*not a well-formed"; then
        pass "a malformed base_tree is refused at the parse"
    else
        fail "malformed base_tree should be refused, got exit=$exit_code out=$out"
    fi
}

test_wrapper_refuses_a_malformed_base_sha() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    raw_clearance "$tmpdir" <<JSON
{
  "pr_number": 123,
  "status": "CERTIFIED",
  "round": 2,
  "sha": "$(cat "$tmpdir/.fixture-sha")",
  "candidate_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_sha": "not-a-base",
  "review_file": ".reviews/some-review.md"
}
JSON
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "base_sha.*not a well-formed"; then
        pass "a malformed base_sha is refused at the parse"
    else
        fail "malformed base_sha should be refused, got exit=$exit_code out=$out"
    fi
}

# Round 2's duplicate-reviewers refusal counted only captures that OPEN a
# bracket, so a second `reviewers` whose value is a string was invisible.
# Under a real parser this artifact has no reviewer entries at all.
test_wrapper_blocks_duplicate_reviewers_key_with_a_non_array_value() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    raw_clearance "$tmpdir" <<JSON
{
  "pr_number": 123,
  "status": "CERTIFIED",
  "round": 1,
  "sha": "$(cat "$tmpdir/.fixture-sha")",
  "candidate_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_sha": "$(cat "$tmpdir/.fixture-sha")",
  "reviewers": [{"model":"r1","verdict":"CERTIFIED","findings_total":0},{"model":"r2","verdict":"CERTIFIED","findings_total":0}],
  "reviewers": "superseded",
  "review_file": ".reviews/some-review.md"
}
JSON
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "a duplicated reviewers key is refused even when the second value is not an array"
    else
        fail "a non-array duplicate reviewers key should block, got exit=$exit_code out=$out"
    fi
}

# THE WALKS NEVER CHECKED THEIR OWN END STATE. A stray leading `]` drove depth
# to -1, so every real depth was offset by one and a NESTED base_sha printed
# into the "depth-1" projection ahead of the honest top-level one — Sol's
# round-2 hole, reopened through the code written to close it.
test_wrapper_blocks_a_clearance_whose_braces_do_not_balance() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    echo "LIVE_BASE_OID=$(cat "$tmpdir/.fixture-base-moved-sha")" >> "$tmpdir/.gh-stub-config"
    raw_clearance "$tmpdir" <<JSON
]
{
  "pr_number": 123,
  "status": "CERTIFIED",
  "round": 2,
  "sha": "$(cat "$tmpdir/.fixture-sha")",
  "candidate_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_tree": "$(cat "$tmpdir/.fixture-tree")",
  "metadata": {"base_sha": "$(cat "$tmpdir/.fixture-base-moved-sha")"},
  "base_sha": "$(cat "$tmpdir/.fixture-sha")",
  "review_file": ".reviews/some-review.md"
}
JSON
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "does not parse"; then
        pass "an artifact whose structure does not balance is refused before any field is read"
    else
        fail "unbalanced structure should block, got exit=$exit_code out=$out"
    fi
}

# Same hole, different desync: an unterminated string flips quote parity, the
# nested object's braces read as string data, and its base_sha prints into the
# projection ahead of the honest one.
test_wrapper_blocks_a_clearance_with_an_unterminated_string() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    echo "LIVE_BASE_OID=$(cat "$tmpdir/.fixture-base-moved-sha")" >> "$tmpdir/.gh-stub-config"
    raw_clearance "$tmpdir" <<JSON
{
  "pr_number": 123,
  "status": "CERTIFIED",
  "round": 2,
  "sha": "$(cat "$tmpdir/.fixture-sha")",
  "candidate_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_tree": "$(cat "$tmpdir/.fixture-tree")",
  "pad": "unterminated,
  "metadata": {"base_sha": "$(cat "$tmpdir/.fixture-base-moved-sha")"},
  "base_sha": "$(cat "$tmpdir/.fixture-sha")",
  "review_file": ".reviews/some-review.md"
}
JSON
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "does not parse"; then
        pass "an artifact with an unterminated string is refused before any field is read"
    else
        fail "an unterminated string should block, got exit=$exit_code out=$out"
    fi
}

# Sol, criterion 3: the duplicate-verdict refusal added in round 2 was ASSERTED
# and never tested — replacing it with `if false` left the suite fully green.
# The duplicate-verdict rows that existed belonged to the cross-model COMMENT
# parser, a different mechanism. A guard covered only by another guard's tests
# is untested.
test_wrapper_blocks_round_1_on_duplicate_verdict_keys_in_an_entry() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" \
        "" "" '{"model":"r1","verdict":"CERTIFIED","findings_total":0},{"model":"r2","verdict":"NOT_CERTIFIED","verdict":"CERTIFIED","findings_total":0}'
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "an entry declaring verdict twice is refused, not resolved by position"
    else
        fail "duplicate verdict keys in an entry should block, got exit=$exit_code out=$out"
    fi
}

# ESCAPE-SMUGGLED DUPLICATES. A `base_sha` key IS `base_sha` — JSON
# unescapes key names before they are keys, so any duplicate rule comparing
# raw bytes sees two different keys where a parser sees one key twice.
#
# The live base is deliberately NOT moved: the plain key names it and would be
# accepted on its own, so the escaped duplicate is the only thing that can
# change the verdict. Move the base and the row blocks on the honest key and
# proves nothing about escapes.
test_wrapper_blocks_an_escape_smuggled_duplicate_key() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    raw_clearance "$tmpdir" <<JSON
{
  "pr_number": 123,
  "status": "CERTIFIED",
  "round": 2,
  "sha": "$(cat "$tmpdir/.fixture-sha")",
  "candidate_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_sha": "$(cat "$tmpdir/.fixture-sha")",
  "\u0062ase_sha": "$(cat "$tmpdir/.fixture-base-moved-sha")",
  "review_file": ".reviews/some-review.md"
}
JSON
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "a duplicate key smuggled through a unicode escape is still a duplicate"
    else
        fail "an escaped duplicate key should block, got exit=$exit_code out=$out"
    fi
}

# Everything after the closing brace is not JSON, and a file that is not JSON
# is not a certification — but a reader that only greps for fields never
# notices there is a file left over.
test_wrapper_blocks_a_clearance_with_trailing_garbage() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    raw_clearance "$tmpdir" <<JSON
{
  "pr_number": 123,
  "status": "CERTIFIED",
  "round": 2,
  "sha": "$(cat "$tmpdir/.fixture-sha")",
  "candidate_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_sha": "$(cat "$tmpdir/.fixture-sha")",
  "review_file": ".reviews/some-review.md"
}
not json at all
JSON
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "does not parse"; then
        pass "an artifact with trailing non-JSON is refused"
    else
        fail "trailing garbage should block, got exit=$exit_code out=$out"
    fi
}

# Test: an artifact predating #636 carries no base_sha and must not be grandfathered
test_wrapper_blocks_clearance_without_base_sha() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # Silence about the base is not an assertion about the base. Clearances are
    # per-PR and written fresh each cycle, so nothing live is broken by refusing
    # the old shape — and grandfathering it would leave the hole open forever
    # behind an artifact that simply omits the field.
    cat > "$tmpdir/.reviews/merge-clearance-123.json" <<JSON
{
  "pr_number": 123,
  "status": "CERTIFIED",
  "round": 2,
  "sha": "$(cat "$tmpdir/.fixture-sha")",
  "candidate_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_tree": "$(cat "$tmpdir/.fixture-tree")",
  "review_file": ".reviews/some-review.md"
}
JSON
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    # Asserting the ABSENCE wording specifically, not just "base_sha". Measured:
    # with the absence branch neutered, CL_BASE_SHA is the empty string, which
    # the mismatch check below then rejects anyway — and its message also says
    # "base_sha", so a looser assertion stays GREEN through its own mutation and
    # proves nothing. Same class as the #628 unreadable-base row.
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "declares no 'base_sha'"; then
        pass "wrapper blocks a clearance carrying no base_sha at all"
    else
        fail "wrapper should block a clearance with no base_sha, got exit=$exit_code out=$out"
    fi
}

# --- #563: the round>=2 rule blocks the case where the review was CLEANEST ---
#
# round >= 2 conflates "a dialogue happened" with "the review was adversarial",
# and those come apart in exactly one case: both reviewers certify at round 1
# with nothing to dispute. That happened on PR #562 — Sol zero at every
# severity, Fable zero at every severity, both verifying the evidence against
# primary sources. The only way to satisfy the gate from there was to re-invoke
# both reviewers and ask them to re-verify nothing: ceremony that increments a
# counter and buys no signal.
#
# Two independent clean certifications is STRONGER evidence than one two-round
# dialogue, and the gate read it as weaker.
#
# The exemption is mechanical — it reads integers out of the artifact, never
# prose — and it is deliberately narrow: two or more reviewers, every one of
# them at findings_total 0.

# Test: round 1 with two independently clean reviewers is allowed to merge
test_wrapper_allows_round_1_two_clean_reviewers() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" \
        ".reviews/some-review.md" "" "" "$(reviewers_with 2 0)"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    # Asserting the MERGE actually happened, not merely a zero exit: this is the
    # one row in the #563 set that opens a path, so it has to prove the path
    # reaches the end rather than that nothing errored on the way.
    if [ "$exit_code" -eq 0 ] && echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "wrapper allows round=1 when two reviewers each certified with zero findings"
    else
        fail "wrapper should merge round=1 with two clean reviewers, got exit=$exit_code out=$out"
    fi
}

# Test: one finding at any severity still demands the recheck round
test_wrapper_blocks_round_1_when_a_reviewer_found_something() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # TWO clean reviewers PLUS one carrying a single finding. The two-clean part
    # is deliberate and load-bearing: with only one clean and one dirty, the
    # >= 2 floor blocks the row on its own and the finding-count guard is never
    # exercised — measured, that shape stayed GREEN through its own mutation.
    # Here the floor is satisfied, so the ONLY thing that can refuse this is the
    # recorded finding. That is the RED the issue names: "a clearance with one
    # P3 recorded must still demand round 2".
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" \
        ".reviews/some-review.md" "" "" \
        "{\"model\":\"r1\",\"findings_total\":0},{\"model\":\"r2\",\"findings_total\":0},{\"model\":\"r3\",\"findings_total\":1}"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -qi "round"; then
        pass "wrapper blocks round=1 when any reviewer recorded a finding"
    else
        fail "wrapper should block round=1 with a non-zero findings_total, got exit=$exit_code out=$out"
    fi
}

# Test: a single clean reviewer is not two, and does not earn the exemption
test_wrapper_blocks_round_1_single_clean_reviewer() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" \
        ".reviews/some-review.md" "" "" "$(reviewers_with 1 0)"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -qi "round"; then
        pass "wrapper blocks round=1 with only one clean reviewer"
    else
        fail "wrapper should block round=1 with a single reviewer, got exit=$exit_code out=$out"
    fi
}

# Test: the field being ABSENT is not the field being zero
test_wrapper_blocks_round_1_when_findings_field_absent() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # Two reviewers, both certified, NEITHER carrying findings_total — the exact
    # shape of every clearance artifact written before #563. Silence about
    # findings must never read as an assertion of zero findings, or the
    # exemption retroactively applies to artifacts that never claimed it.
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" \
        ".reviews/some-review.md" "" "" \
        "{\"model\":\"r1\",\"verdict\":\"CERTIFIED\"},{\"model\":\"r2\",\"verdict\":\"CERTIFIED\"}"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -qi "round"; then
        pass "wrapper blocks round=1 when findings_total is absent, not zero"
    else
        fail "wrapper should block round=1 with no findings_total, got exit=$exit_code out=$out"
    fi
}

# --- Round 1 of this PR's own review, P1: the counting was unscoped ---
#
# The first implementation grepped every `findings_total` in the artifact and
# never checked the match belonged to a reviewer. Both rows below were EXECUTED
# against it by the reviewer and both MERGED at exit 0. They are kept as
# permanent rows rather than being folded into the ones above, because they fail
# for a different reason than "wrong count": they fail because the thing being
# counted was never the thing the contract names.

# Test: stray findings_total keys outside any reviewer entry earn nothing
test_wrapper_blocks_round_1_unscoped_findings_totals() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # ZERO reviewer entries. The two zeros sit at top level, where an
    # occurrence-counting implementation happily finds them.
    cat > "$tmpdir/.reviews/merge-clearance-123.json" <<JSON
{
  "pr_number": 123,
  "status": "CERTIFIED",
  "round": 1,
  "sha": "$(cat "$tmpdir/.fixture-sha")",
  "candidate_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_tree": "$(cat "$tmpdir/.fixture-tree")",
  "base_sha": "$(cat "$tmpdir/.fixture-sha")",
  "findings_total": 0,
  "notes_findings_total": 0,
  "review_file": ".reviews/some-review.md"
}
JSON
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "0 reviewer entries"; then
        pass "wrapper blocks round=1 when the zeros belong to no reviewer"
    else
        fail "wrapper should block unscoped findings_total keys, got exit=$exit_code out=$out"
    fi
}

# Test: a reviewer that reports nothing is not a reviewer that reports zero
test_wrapper_blocks_round_1_partially_counted_reviewers() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # Two clean reviewers satisfy the >= 2 floor on their own. The third
    # declares no findings_total at all — so the artifact never claims that
    # reviewer found nothing, and the gate must not infer it.
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" \
        ".reviews/some-review.md" "" "" \
        "{\"model\":\"r1\",\"findings_total\":0},{\"model\":\"r2\",\"findings_total\":0},{\"model\":\"r3\",\"verdict\":\"CERTIFIED\"}"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "3 reviewer entries"; then
        pass "wrapper blocks round=1 when one reviewer records no findings_total"
    else
        fail "wrapper should block a partially-counted reviewer set, got exit=$exit_code out=$out"
    fi
}

# Test: zero findings without a certification is an abandoned review, not a clean one
test_wrapper_blocks_round_1_clean_but_not_certified_reviewer() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # Round 1 P2. Zero findings is what the reviewer SAW; the verdict is what
    # they CONCLUDED. A leg that timed out, or stopped early, or simply refused,
    # can honestly report zero findings — and must not be counted as agreement.
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" \
        ".reviews/some-review.md" "" "" \
        "{\"model\":\"r1\",\"verdict\":\"CERTIFIED\",\"findings_total\":0},{\"model\":\"r2\",\"verdict\":\"NOT_CERTIFIED\",\"findings_total\":0}"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "2 reviewer entries"; then
        pass "wrapper blocks round=1 when a zero-findings reviewer did not certify"
    else
        fail "wrapper should block a NOT_CERTIFIED zero-findings reviewer, got exit=$exit_code out=$out"
    fi
}

# Test: round >= 2 is untouched by any of this
test_wrapper_allows_round_2_without_findings_field() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # No reviewers array at all. #563 adds an alternative route past round >= 2;
    # it must not add a REQUIREMENT to it. Every pre-#563 artifact looks like
    # this one, and every one of them must still merge.
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ] && echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "wrapper still merges round>=2 with no findings_total present"
    else
        fail "wrapper should merge round=2 without the new field, got exit=$exit_code out=$out"
    fi
}

# --- Round cap: past round 3, each extra round carries a recorded reason ---
#
# The gate had a floor (round >= 2) and no ceiling. The shape it now checks,
# READ ONLY PAST ROUND 3 so every round 1-3 clearance stays valid unchanged,
# including older ones that use a top-level "rounds" key for something else:
#
#   "rounds": [{"round": 1, "findings_total": N}, ...]
#       one entry per round, in order, length == round. From round 3 on,
#       findings_total must be strictly below the previous round's.
#   "scope_decisions": [{"round": R, "reason": "<non-blank>"}, ...]
#       for every R in 4..round, at least one entry with a non-blank reason
#       and no decision other than "continue". Other entries are ignored, so
#       the wizard's existing {decision, cost, blame, by} records can coexist.

# "5 4 2" -> "rounds":[{"round":1,"findings_total":5},...]
rounds_json() {
    local i=0 n out=""
    for n in $1; do
        i=$((i + 1))
        [ -n "$out" ] && out="$out,"
        out="$out{\"round\":$i,\"findings_total\":$n}"
    done
    printf '"rounds":[%s]' "$out"
}

# Writes a clearance at round $1 with raw extra fields $2, runs the wrapper,
# and prints "<exit>|<output>".
run_round_cap() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" "$1" "$(cat "$tmpdir/.fixture-sha")" \
        ".reviews/some-review.md" "" "" "" "" "" "$2"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    printf '%s|%s' "$exit_code" "$out"
}

# $1 label, $2 expected text, $3 result of run_round_cap
expect_round_cap_refused() {
    local code="${3%%|*}" out="${3#*|}"
    if [ "$code" -ne 0 ] && ! printf '%s' "$out" | grep -q "GH_MERGE_INVOKED" \
        && printf '%s' "$out" | grep -qF "$2"; then
        pass "round cap refuses: $1"
    else
        fail "round cap should refuse ($1) with '$2', got exit=$code out=$out"
    fi
}

expect_round_cap_merges() {
    local code="${2%%|*}" out="${2#*|}"
    if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "round cap allows: $1"
    else
        fail "round cap should allow ($1), got exit=$code out=$out"
    fi
}

test_round_cap() {
    local sd4='"scope_decisions":[{"round":4,"reason":"in-card P1 open after round 3"}]'
    local sd_empty='"scope_decisions":[{"round":4,"reason":""}]'
    local sd_space='"scope_decisions":[{"round":4,"reason":" \t "}]'
    local sd_append='"scope_decisions":[{"round":4,"reason":""},{"round":4,"reason":"re-frozen scope"}]'
    local sd_stop='"scope_decisions":[{"round":4,"decision":"stop","reason":"converged"}]'
    local sd_continue='"scope_decisions":[{"round":4,"decision":"continue","reason":"P1 open"}]'

    expect_round_cap_refused "round 4 with no scope_decisions entry for round 4" \
        "no scope_decisions reason for round 4" \
        "$(run_round_cap 4 "$(rounds_json "5 4 2 1")")"
    expect_round_cap_merges "round 4 with a reasoned entry for round 4" \
        "$(run_round_cap 4 "$(rounds_json "5 4 2 1"), $sd4")"
    expect_round_cap_merges "round 4 with an explicit continue decision" \
        "$(run_round_cap 4 "$(rounds_json "5 4 2 1"), $sd_continue")"
    expect_round_cap_refused "round 4 whose only entry is a stop decision" \
        "no scope_decisions reason for round 4" \
        "$(run_round_cap 4 "$(rounds_json "5 4 2 1"), $sd_stop")"
    expect_round_cap_refused "round 5 with an entry only for round 4" \
        "no scope_decisions reason for round 5" \
        "$(run_round_cap 5 "$(rounds_json "5 4 3 2 1"), $sd4")"
    expect_round_cap_refused "round 4 with an empty reason" \
        "no scope_decisions reason for round 4" \
        "$(run_round_cap 4 "$(rounds_json "5 4 2 1"), $sd_empty")"
    expect_round_cap_refused "round 4 with a whitespace reason" \
        "no scope_decisions reason for round 4" \
        "$(run_round_cap 4 "$(rounds_json "5 4 2 1"), $sd_space")"
    expect_round_cap_merges "a blank entry beside a reasoned one for the same round (scopes append)" \
        "$(run_round_cap 4 "$(rounds_json "5 4 2 1"), $sd_append")"
    expect_round_cap_refused "findings 5,4,4 do not strictly fall after round 2" \
        "findings_total did not fall at round 3" \
        "$(run_round_cap 4 "$(rounds_json "5 4 4 3"), $sd4")"
    expect_round_cap_merges "findings 5,4,2" \
        "$(run_round_cap 4 "$(rounds_json "5 4 2 1"), $sd4")"
    expect_round_cap_merges "findings 4,5,2 (round 2 may rise; the rule starts at round 3)" \
        "$(run_round_cap 4 "$(rounds_json "4 5 2 1"), $sd4")"
    expect_round_cap_refused "findings 5,4,2,2 at round 4" \
        "findings_total did not fall at round 4" \
        "$(run_round_cap 4 "$(rounds_json "5 4 2 2"), $sd4")"
    expect_round_cap_refused "a rounds list shorter than round" \
        "rounds must be a list of 4 entries" \
        "$(run_round_cap 4 "$(rounds_json "5 4 2"), $sd4")"
    expect_round_cap_refused "a rounds list longer than round" \
        "rounds must be a list of 4 entries" \
        "$(run_round_cap 4 "$(rounds_json "6 5 4 2 1"), $sd4")"
    expect_round_cap_refused "rounds entries out of order" \
        "rounds entry 1" \
        "$(run_round_cap 4 '"rounds":[{"round":2,"findings_total":5},{"round":1,"findings_total":4},{"round":3,"findings_total":2},{"round":4,"findings_total":1}],'"$sd4")"
    expect_round_cap_refused "a non-integer findings_total in rounds" \
        "rounds entry 2" \
        "$(run_round_cap 4 '"rounds":[{"round":1,"findings_total":5},{"round":2,"findings_total":true},{"round":3,"findings_total":1},{"round":4,"findings_total":0}],'"$sd4")"
    expect_round_cap_refused "a negative findings_total in rounds" \
        "rounds entry 4" \
        "$(run_round_cap 4 "$(rounds_json "5 4 2 -1"), $sd4")"
    expect_round_cap_refused "round 4 that records no rounds at all" \
        "declares no 'rounds'" \
        "$(run_round_cap 4 "$sd4")"
    expect_round_cap_merges "round 3 with neither field (existing clearances unchanged)" \
        "$(run_round_cap 3 "")"
    expect_round_cap_merges "round 3 whose rounds would fail the rule (not read until round 4)" \
        "$(run_round_cap 3 "$(rounds_json "5 4 4")")"
    # merge-clearance-597.json: a real round-2 clearance whose top-level
    # "rounds" is a dialogue log, not a findings history. It must still merge.
    expect_round_cap_merges "round 2 with a foreign-shaped rounds key (the #597 artifact)" \
        "$(run_round_cap 2 '"rounds":[{"round":1,"reviewer":"sol","verdict":"NOT CERTIFIED","score":6},{"round":2,"reviewer":"sol","verdict":"CERTIFIED"}]')"

    # Malformed JSON: the strict parse already refuses it. Kept as a row so the
    # new fields never get a lenient reader of their own.
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 4 "$(cat "$tmpdir/.fixture-sha")" \
        ".reviews/some-review.md" "" "" "" "" "" "$(rounds_json "5 4 2 1"), \"scope_decisions\":[{\"round\":4,\"reason\":\"x\"}"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    expect_round_cap_refused "malformed JSON" "does not parse as a certification" "$exit_code|$out"
}

# --- #540: the clearance names CONTENT, and the merge boundary checks it ---
#
# The hook can only speak for the index it saw before the commit; PreToolUse
# cannot observe post-command state. This is the other half, and the half that
# sees the object that actually merges.

# Test: certified content is not the content that would merge
test_wrapper_blocks_wrong_candidate_tree() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # A well-formed clearance, current SHA, round 2 — everything the pre-#540
    # gate asked for — but naming a tree that is not the one on the head.
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" \
        "4b825dc642cb6eb9a060e54bf8d69288fbee4904" "$(cat "$tmpdir/.fixture-tree")"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "not the content that was certified"; then
        pass "wrapper blocks when the merging tree is not the certified candidate_tree"
    else
        fail "wrapper should block on candidate_tree mismatch, got exit=$exit_code out=$out"
    fi
}

# Test: the base moved under the certification. Same candidate_tree, different
# base — a rebase onto moved upstream leaves the diff alone and changes the
# result, which is the measurement that killed patch-id as the primitive.
test_wrapper_blocks_moved_base() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" \
        "$(cat "$tmpdir/.fixture-tree")" "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "the base moved since certification"; then
        pass "wrapper blocks when the certified base_tree is not the current base"
    else
        fail "wrapper should block on base_tree mismatch, got exit=$exit_code out=$out"
    fi
}

# Test: the SERVER base moved while the local tracking ref stayed put.
#
# Round 1, found independently by BOTH reviewers and constructed rather than
# argued. The first version of this check read `origin/$BASE_BRANCH^{tree}` — a
# local cache — and skipped the comparison entirely when that ref was absent.
# Sol built a bare server repo, advanced server main, left refs/remotes/origin/
# main at the certified commit, and merged a bogus certification at exit 0.
# Fable reached the same exit 0 by deleting the ref outright.
#
# The base is now read from the PR's baseRefOid, which is server truth. This row
# is the regression: the local ref deliberately still says "unchanged".
test_wrapper_blocks_moved_server_base_with_stale_tracking_ref() {
    local tmpdir out exit_code candidate_sha candidate_tree server_base_sha
    tmpdir=$(setup_wrapper_fixture)
    candidate_sha=$(cat "$tmpdir/.fixture-sha")
    candidate_tree=$(cat "$tmpdir/.fixture-tree")

    printf 'server base moved\n' > "$tmpdir/server-base.txt"
    git -C "$tmpdir" add server-base.txt
    git -C "$tmpdir" commit -qm 'move server base'
    server_base_sha=$(git -C "$tmpdir" rev-parse HEAD)

    # Back to the certified content, and the local tracking ref left lying.
    git -C "$tmpdir" reset -q --hard "$candidate_sha"
    git -C "$tmpdir" update-ref refs/remotes/origin/main "$candidate_sha"
    # The two knobs DISAGREE, exactly as real GitHub does: baseRefOid stays at
    # the snapshot the PR was opened against, while the branch itself has moved.
    # Round 2 read the snapshot and merged; this row is why it cannot again.
    echo "BASE_OID=$candidate_sha" >> "$tmpdir/.gh-stub-config"
    echo "LIVE_BASE_OID=$server_base_sha" >> "$tmpdir/.gh-stub-config"

    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$candidate_sha" ".reviews/some-review.md" \
        "$candidate_tree" "$candidate_tree"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "the base moved since certification"; then
        pass "wrapper blocks when the server base moved despite a stale local tracking ref"
    else
        fail "stale origin/main authorized a merge past a moved server base: exit=$exit_code out=$out"
    fi
}

# Test: the base object named by the PR cannot be read, so nothing can be
# compared. Same posture as the unreadable remote head ten lines above it —
# the first version skipped the check instead, which is fail-OPEN in the one
# situation where the answer is unknown.
test_wrapper_blocks_unreadable_base_object() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    echo "LIVE_BASE_OID=ffffffffffffffffffffffffffffffffffffffff" >> "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    # Asserting the SPECIFIC message, not just a non-zero exit. Neutering the
    # fail-closed branch leaves CUR_BASE_TREE empty, which the mismatch check
    # below it then rejects anyway — so an exit-code-only assertion stays green
    # through the mutation and proves nothing. Measured, not assumed.
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "could not read the tree of the base commit"; then
        pass "wrapper blocks when the PR's base object cannot be read"
    else
        fail "unreadable base object should block on the unreadable-base branch, got exit=$exit_code out=$out"
    fi
}

# Test: the pre-#540 artifact format fails closed. A clearance carrying only a
# sha named no content, and honouring it would be the hole reopened under an
# older key — the same posture #437 took for a missing commit_sha.
test_wrapper_blocks_clearance_without_trees() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # Hand-written in the OLD shape: no candidate_tree, no base_tree.
    cat > "$tmpdir/.reviews/merge-clearance-123.json" <<JSON
{
  "pr_number": 123,
  "status": "CERTIFIED",
  "round": 2,
  "sha": "$(cat "$tmpdir/.fixture-sha")",
  "review_file": ".reviews/some-review.md"
}
JSON
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "declares no 'candidate_tree'"; then
        pass "wrapper fails closed on a pre-#540 clearance that names no content"
    else
        fail "wrapper should block a clearance with no candidate_tree, got exit=$exit_code out=$out"
    fi
}

# Test: stale SHA (clearance doesn't match remote head) blocks
test_wrapper_blocks_stale_clearance() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # A real 40-hex object name that is simply not the head. The old fixture used
    # the placeholder "old-sha-999", which since the field grammar landed is
    # refused as malformed BEFORE the staleness comparison is ever reached — so
    # the row passed while testing a different refusal than the one it names.
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "9999999999999999999999999999999999999999" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "stale"; then
        pass "wrapper blocks stale clearance (SHA mismatch vs remote head)"
    else
        fail "wrapper should block on stale SHA, got exit=$exit_code out=$out"
    fi
}

# Test: empty/missing review artifact file blocks
test_wrapper_blocks_empty_review_artifact() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/missing-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "review"; then
        pass "wrapper blocks when the referenced review artifact is missing/empty"
    else
        fail "wrapper should block on missing review artifact, got exit=$exit_code out=$out"
    fi
}

# Test: denylist match (workflow file) blocks, naming the path
test_wrapper_blocks_denylisted_workflow_touch() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's#DIFF_FILES=src/foo.js#DIFF_FILES=.github/workflows/ci.yml#' "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "ci.yml"; then
        pass "wrapper blocks a PR touching .github/workflows/, naming the path"
    else
        fail "wrapper should block workflow-touching PR, got exit=$exit_code out=$out"
    fi
}

# Test: self-referential denylist — PR touching the wrapper/hook itself blocks
# (closes the exact loophole both Codex and Fable flagged: a PR editing the
# merge policy/mechanism wouldn't otherwise be excluded by a release-only list)
test_wrapper_blocks_self_referential_touch() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's#DIFF_FILES=src/foo.js#DIFF_FILES=scripts/merge-pr.sh#' "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "merge-pr.sh" && ! echo "$out" | grep -q "No such file or directory"; then
        pass "wrapper blocks a PR touching its own wrapper script (self-referential loophole closed)"
    else
        fail "wrapper should block self-referential touch, got exit=$exit_code out=$out"
    fi
}

# Test: net test-file deletion blocks
test_wrapper_blocks_test_deletion() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's#DELETED_TEST_FILES=#DELETED_TEST_FILES=tests/test-foo.sh#' "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "test-foo.sh"; then
        pass "wrapper blocks a PR that net-deletes test files, naming the path"
    else
        fail "wrapper should block test deletion, got exit=$exit_code out=$out"
    fi
}

# Test: renaming a test file OUT of tests/ is an effective deletion and must
# block — Codex round-1 finding #4: the original check only recognized
# status:"removed", missing status:"renamed" with a previous_filename under
# tests/ and a new filename that isn't.
test_wrapper_blocks_test_file_renamed_out_of_tests_dir() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak "s#RENAMED_TEST_FILES=#RENAMED_TEST_FILES='tests/test-foo.sh->archive/test-foo.sh'#" "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "tests/test-foo.sh"; then
        pass "wrapper blocks a test file renamed out of tests/ (effective deletion)"
    else
        fail "wrapper should block a test renamed out of tests/, got exit=$exit_code out=$out"
    fi
}

# Test: pagination — a deleted test file beyond the API's first page must
# still be caught. Codex round-1 finding #3: the pulls/files call lacked
# --paginate, so gh's default single-page response silently hid anything
# past the first page.
test_wrapper_blocks_test_deletion_beyond_first_page() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's#BEYOND_FIRST_PAGE=#BEYOND_FIRST_PAGE=tests/test-late-page.sh#' "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "test-late-page.sh"; then
        pass "wrapper catches a deleted test file beyond the API's first page (--paginate used)"
    else
        fail "wrapper should catch a beyond-first-page deletion, got exit=$exit_code out=$out"
    fi
}

# Test: a package.json version-field change is caught via the pulls/files
# patch content, not an invalid `gh pr diff -- <path>` call — Codex round-1
# finding #2: `gh pr diff <PR> -- package.json` is not valid gh syntax
# ("accepts at most 1 arg"); stderr was suppressed so the check silently
# no-opped, letting every version bump through unblocked.
test_wrapper_blocks_package_json_version_change() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak -e 's#DIFF_FILES=src/foo.js#DIFF_FILES=package.json#' \
        -e 's#PACKAGE_JSON_VERSION_CHANGED=#PACKAGE_JSON_VERSION_CHANGED=1#' "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "package.json"; then
        pass "wrapper blocks a package.json version-field change (patch-content check, not invalid gh pr diff syntax)"
    else
        fail "wrapper should block a package.json version change, got exit=$exit_code out=$out"
    fi
}

# Test: CLAUDE_CODE_SDLC_WIZARD.md is in the denylist — Codex round-1 finding
# #5: it contains the merge-confirmation policy itself, so a PR weakening
# that policy wasn't excluded from the exception it's editing.
test_wrapper_blocks_wizard_doc_touch() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's#DIFF_FILES=src/foo.js#DIFF_FILES=CLAUDE_CODE_SDLC_WIZARD.md#' "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "CLAUDE_CODE_SDLC_WIZARD.md"; then
        pass "wrapper blocks a PR touching CLAUDE_CODE_SDLC_WIZARD.md (contains the policy itself)"
    else
        fail "wrapper should block CLAUDE_CODE_SDLC_WIZARD.md touch, got exit=$exit_code out=$out"
    fi
}

# Test: all conditions pass — wrapper invokes the exact expected merge command
test_wrapper_merges_when_all_conditions_met() {
    local tmpdir out exit_code fixture_sha
    tmpdir=$(setup_wrapper_fixture)
    # Captured BEFORE the fixture is removed. Reading it afterwards substitutes
    # the empty string, which leaves a prefix match that passes without ever
    # checking the SHA — the whole point of this row (Sol, round 1 P2).
    fixture_sha=$(cat "$tmpdir/.fixture-sha")
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$fixture_sha" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    # The -R pin is asserted, not tolerated (#607). Repository selection was
    # ambient: with GIT_DIR redirected, the merge targeted another repository
    # while every check reported success against the wrong target. An unpinned
    # merge call must fail this row rather than pass it.
    if [ "$exit_code" -eq 0 ] && echo "$out" | grep -q "GH_MERGE_INVOKED: pr merge -R github.com/BaseInfinity/claude-sdlc-harness 123 --squash --match-head-commit $fixture_sha"; then
        pass "wrapper merges with the exact expected command, repository pinned, when all conditions are met"
    else
        fail "wrapper should invoke 'gh pr merge -R <this repo> 123 --squash --match-head-commit <fixture sha>', got exit=$exit_code out=$out"
    fi
}

# Test: fail-fast ordering — when two conditions fail at once, the FIRST
# checked (denylist/self-reference) surfaces, not a later one, per the
# documented check order (denylist -> test-deletion -> CI -> clearance -> merge)
test_wrapper_fail_fast_ordering() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # Fails BOTH denylist (workflow touch) AND CI (pending) simultaneously.
    sed -i.bak -e 's#DIFF_FILES=src/foo.js#DIFF_FILES=.github/workflows/ci.yml#' \
        -e 's/VALIDATE_CONCLUSION=success/VALIDATE_CONCLUSION=pending/' "$tmpdir/.gh-stub-config"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "ci.yml" && ! echo "$out" | grep -qi "pending"; then
        pass "wrapper surfaces the denylist failure first, not the later CI check (documented fail-fast order)"
    else
        fail "wrapper should report the denylist match first when multiple conditions fail, got exit=$exit_code out=$out"
    fi
}

# Test: no env var can make the wrapper merge past a RED CI check (#479).
#
# This test used to assert that MERGE_CLEARANCE_SKIP=1 merged anyway while
# logging BYPASSED. That is precisely the defect #479 names: acknowledging one
# denylist row also disarmed CI, test-deletion, SHA-freshness and the clearance
# artifact. CI is pending in this fixture, so a merge here would be a merge on
# unverified code. Inverted rather than deleted: it now guards the property.
test_wrapper_has_no_env_bypass() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's/VALIDATE_CONCLUSION=success/VALIDATE_CONCLUSION=pending/' "$tmpdir/.gh-stub-config"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" MERGE_CLEARANCE_SKIP=1 "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "no env var merges past a red CI check"
    else
        fail "an env var merged past red CI, got exit=$exit_code out=$out"
    fi
}

test_wrapper_requires_pr_arg
test_wrapper_fails_closed_on_gh_error
test_wrapper_blocks_ci_pending
test_wrapper_blocks_ci_skipped
test_wrapper_blocks_ci_neutral
test_wrapper_blocks_missing_clearance
test_wrapper_blocks_non_certified_status
test_wrapper_blocks_round_1_only
test_wrapper_blocks_moved_base_with_identical_tree
test_wrapper_blocks_nested_base_sha_masking_a_stale_one
test_wrapper_blocks_nested_candidate_tree_masking_a_stale_one
test_wrapper_blocks_round_1_when_certified_appears_outside_the_verdict
test_wrapper_blocks_round_1_when_a_nested_array_hides_a_dirty_reviewer
test_wrapper_blocks_round_1_when_a_string_bracket_hides_a_dirty_reviewer
test_wrapper_blocks_round_1_when_a_nested_reviewers_array_shadows_the_real_one
test_wrapper_blocks_round_1_on_duplicate_reviewers_keys
test_wrapper_allows_round_1_two_clean_reviewers_with_a_nested_array
test_wrapper_blocks_round_1_on_duplicate_findings_total_in_an_entry
test_wrapper_blocks_round_1_on_a_non_integer_findings_total
test_wrapper_blocks_round_1_on_a_float_zero_findings_total
test_wrapper_blocks_round_1_when_a_reviewers_entry_is_not_an_object
test_wrapper_blocks_duplicate_status_keys
test_wrapper_blocks_duplicate_base_sha_keys
test_wrapper_blocks_tsv_injection_through_a_string_field
test_wrapper_blocks_tsv_injection_forging_the_ancestry_binds
test_wrapper_blocks_nul_normalising_a_string_field
test_wrapper_blocks_nul_in_status_with_every_other_field_clean
test_wrapper_refuses_a_malformed_object_name_at_the_parse
test_wrapper_allows_a_review_file_path_containing_a_space
test_wrapper_refuses_a_malformed_candidate_tree
test_wrapper_refuses_a_malformed_base_tree
test_wrapper_refuses_a_malformed_base_sha
test_wrapper_blocks_duplicate_reviewers_key_with_a_non_array_value
test_wrapper_blocks_a_clearance_whose_braces_do_not_balance
test_wrapper_blocks_a_clearance_with_an_unterminated_string
test_wrapper_blocks_round_1_on_duplicate_verdict_keys_in_an_entry
test_wrapper_blocks_an_escape_smuggled_duplicate_key
test_wrapper_blocks_a_clearance_with_trailing_garbage
test_wrapper_blocks_clearance_without_base_sha
test_wrapper_allows_round_1_two_clean_reviewers
test_wrapper_blocks_round_1_when_a_reviewer_found_something
test_wrapper_blocks_round_1_single_clean_reviewer
test_wrapper_blocks_round_1_when_findings_field_absent
test_wrapper_blocks_round_1_unscoped_findings_totals
test_wrapper_blocks_round_1_partially_counted_reviewers
test_wrapper_blocks_round_1_clean_but_not_certified_reviewer
test_wrapper_allows_round_2_without_findings_field
test_round_cap
test_wrapper_blocks_stale_clearance
test_wrapper_blocks_wrong_candidate_tree
test_wrapper_blocks_moved_base
test_wrapper_blocks_moved_server_base_with_stale_tracking_ref

# ---------------------------------------------------------------------------
# FOUR GUARDS WERE WRITTEN FOR THE PIN AND ALL FOUR WERE DELETED. ONE ROW
# SURVIVES, AND IT IS NOT THE ONE THAT PROVES THE PIN.
#
# The gate pins its forge target in `scripts/merge-pr.sh` itself, by exporting
# GH_HOST and GH_REPO and by passing `-R` / `--hostname github.com` per call.
# That is the fix, and it is verified by execution against real gh — see the
# handoff. What kept failing review was every attempt to PROVE the property
# from this file.
#
#   Round 1 took the substring `-R ` anywhere on a line as proof of a pin, so
#   a trailing comment satisfied it, and it saw only three call prefixes.
#
#   Round 2 blanked quotes and comments first, then checked the surviving
#   `gh` tokens. It ERASED real calls — `X="$(gh pr list)"` disappears with the
#   quotes around it — and the count row added to catch that could not, since
#   an erased addition leaves the count unchanged.
#
#   Round 3 checked that the exports precede the first call and that every
#   `repos/` line names this repository. Ruled WRONG_SHAPE at confidence 99.
#   Both rows passed a later `unset`, a per-command override, and a wrong
#   literal target on a line that also mentioned the right one.
#
#   Round 4 replaced them with a BEHAVIOURAL row: the stub logged the pin
#   environment each call saw, and the gate ran under a hostile environment.
#   Ruled WRONG_SHAPE too. It passed vacuously when the gate exited after one
#   correctly pinned call, and its unanchored grep accepted a wrong record
#   whenever the expected substring appeared later in the argv it also logged.
#
# Four rewrites, four false-PASS failures, in four different mechanisms. The
# stopping rule was written down before round 4 ran and is honoured here: the
# guard is optional, the fix is not. A row that reports a property it does not
# check is worse than no row, because the suite then certifies the absence of
# evidence.
#
# WHAT IS ACTUALLY GUARDED, AND WHAT IS NOT:
#
#   Guarded here — no ambient placeholder token, below.
#   Guarded elsewhere — `test_wrapper_merges_when_all_conditions_met` asserts
#     the exact argv of the merge call, including its `-R`. That is one call
#     site of ten, and it is an assertion about the merge command rather than
#     about the pin as a property.
#   NOT guarded — that a call added later carries the pin. Nothing in this
#     file establishes that, and four attempts to make something establish it
#     were each wrong in a way that read as green. It rests on the exports in
#     `scripts/merge-pr.sh`, which apply to any call that does not override
#     them, and on review.
#
# Do not add a fifth guard without a way to make it fail first on a real
# defect. That is what all four lacked.

# The one surviving row: no ambient owner/repo placeholder token.
#
# `:owner`, `:repo`, `{owner}` and `{repo}` are resolved by gh from the current
# directory or GH_REPO. Round 2's review found an earlier version enumerated
# only the two matched PAIRS, so the mixed form `repos/{owner}/:repo` was
# invisible — and gh resolves that form perfectly well, verified by running it.
# Banning the TOKENS rather than the pairs removes the combinatorics.
#
# THIS ROW SURVIVED BECAUSE IT ERRS TOWARD FALSE-FAIL. A stray `:repo` in a
# trailing comment fails it loudly. That is a nuisance. All four deleted rows
# erred the other way.
test_no_ambient_repo_placeholder_in_the_gate() {
    local placeholders
    placeholders=$(grep -nE ':owner|:repo|\{owner\}|\{repo\}' "$WRAPPER" \
        | grep -vE '^[0-9]+:[[:space:]]*#' || true)
    if [ -z "$placeholders" ]; then
        pass "no ambient owner/repo placeholder token remains anywhere in the gate"
    else
        fail "ambient placeholder token(s) in the gate: $(echo "$placeholders" | tr '\n' ' ' | cut -c1-300)"
    fi
}

test_no_ambient_repo_placeholder_in_the_gate
test_wrapper_blocks_unreadable_base_object
test_wrapper_blocks_clearance_without_trees
test_wrapper_blocks_empty_review_artifact
test_wrapper_blocks_denylisted_workflow_touch
test_wrapper_blocks_self_referential_touch
test_wrapper_blocks_test_deletion
test_wrapper_blocks_test_file_renamed_out_of_tests_dir
test_wrapper_blocks_test_deletion_beyond_first_page
test_wrapper_blocks_package_json_version_change
test_wrapper_blocks_wizard_doc_touch
test_wrapper_merges_when_all_conditions_met
test_wrapper_fail_fast_ordering
test_wrapper_has_no_env_bypass

# --- Cross-model clearance payloads (GH #478) --------------------------------
#
# A missing VERDICT field survived here despite verify_cross_model_clearance
# being well covered — 49 assertions in tests/test-cross-model-clearance.sh over
# confidence bounds, SHA binding, authorship and payload visibility. Every one
# fed a fixture that omitted a verdict, so the suite tested the SHAPE of the
# evidence and never the ANSWER inside it: a payload asserting MERGE_SAFE: NO in
# its prose while carrying confidence 97 satisfied every check and merged.
# Confidence was standing in for a decision nobody had modelled.
#
# Helper: run the wrapper against a fixture whose PR comments carry $1 (one
# compact JSON payload per line), touching an ACKABLE_DENY path so clearance
# is actually consulted, and echo "exit=<n> <output>".
run_with_clearance() {
    local payloads="$1" tmpdir out code
    tmpdir=$(setup_wrapper_fixture)
    printf 'DIFF_FILES=CLAUDE_CODE_SDLC_WIZARD.md\n' >> "$tmpdir/.gh-stub-config"
    printf 'CLEARANCE_PAYLOADS=%s\n' "$(printf '%q' "$payloads")" >> "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "review body" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 --cross-model-cleared 2>&1) && code=0 || code=$?
    rm -rf "$tmpdir"
    printf 'exit=%s %s' "$code" "$out"
}

# Assert the merge DID NOT HAPPEN, not merely that the exit code was nonzero.
# Codex found the first version of these tests checking exit status and message
# text — the SHAPE of the refusal — while the stub's GH_MERGE_INVOKED line proved
# the merge had actually fired in some cases. That is the identical defect this
# whole change exists to fix: 49 assertions checked the shape of the clearance
# evidence and never the answer inside it. The side effect is the ground truth.
refute_merge() {  # $1=result  $2=what was being attempted
    if printf '%s' "$1" | grep -q "GH_MERGE_INVOKED"; then
        fail "$2 — the merge ACTUALLY FIRED: $1"
    elif printf '%s' "$1" | grep -q "^exit=0"; then
        fail "$2 — wrapper exited 0: $1"
    else
        pass "$2"
    fi
}

test_clearance_requires_verdict_field() {
    # Two reviewers, both >=95, both bound to the head SHA, NEITHER declaring a
    # verdict. Confidence alone must not clear a merge.
    refute_merge "$(run_with_clearance '{"reviewer":"gpt-5.6-sol","confidence":97,"sha":"__FIXTURE_SHA__"}
{"reviewer":"fable-5","confidence":96,"sha":"__FIXTURE_SHA__"}')" \
        "clearance with no verdict field does not merge"
}

test_clearance_rejects_negative_verdict() {
    # THE DEFECT, stated as a test: a reviewer who says NO, at high confidence,
    # must never clear. Before the fix this merged.
    refute_merge "$(run_with_clearance '{"reviewer":"gpt-5.6-sol","verdict":"NO","confidence":97,"sha":"__FIXTURE_SHA__"}
{"reviewer":"fable-5","verdict":"NO","confidence":99,"sha":"__FIXTURE_SHA__"}')" \
        "two confident NO verdicts do not merge"
}

test_clearance_rejects_lowercase_verdict() {
    # Codex: `ascii_upcase` in the jq projection normalised 'yes' and 'YeS' into
    # YES, so the exact-match check I had documented as strict was not strict.
    # A verdict is a machine-written field in a machine-written payload; a
    # reviewer that cannot emit the exact token has not cleared anything.
    refute_merge "$(run_with_clearance '{"reviewer":"gpt-5.6-sol","verdict":"yes","confidence":97,"sha":"__FIXTURE_SHA__"}
{"reviewer":"fable-5","verdict":"YeS","confidence":96,"sha":"__FIXTURE_SHA__"}')" \
        "case-variant verdicts (yes / YeS) do not merge"
}

test_clearance_rejects_duplicate_verdict_keys() {
    # Codex: a payload carrying `verdict` TWICE — NO first, YES last — merged,
    # because JSON parsers keep the last duplicate key. The rendered comment can
    # be made to read as a refusal while the parsed object says YES.
    refute_merge "$(run_with_clearance '{"reviewer":"gpt-5.6-sol","verdict":"NO","confidence":97,"sha":"__FIXTURE_SHA__","verdict":"YES"}
{"reviewer":"fable-5","verdict":"NO","confidence":96,"sha":"__FIXTURE_SHA__","verdict":"YES"}')" \
        "a duplicated verdict key (NO then YES) does not merge"
}

test_clearance_rejects_unicode_escaped_duplicate_key() {
    # Codex round 2: `verdict` and `verdict` decode to `verdict`, so
    # the raw-text duplicate scan never saw a second key while the JSON parser
    # did — and kept the last one, YES. Counting literal text cannot win against
    # escaping, which is why the fix stopped counting text and instead pins the
    # payload to an exact key set with no escapes permitted anywhere.
    refute_merge "$(run_with_clearance '{"reviewer":"gpt-5.6-sol","verdict":"NO","confidence":97,"sha":"__FIXTURE_SHA__","\u0076erdict":"YES"}
{"reviewer":"fable-5","verdict":"NO","confidence":96,"sha":"__FIXTURE_SHA__","ver\u0064ict":"YES"}')" \
        "unicode-escaped duplicate keys do not merge"
}

test_clearance_rejects_unknown_extra_key() {
    # Consequence of the positive anchor: the payload carries exactly the four
    # decision-bearing keys. An unrecognised field is refused rather than
    # ignored, so nothing can ride along unexamined.
    refute_merge "$(run_with_clearance '{"reviewer":"gpt-5.6-sol","verdict":"YES","confidence":97,"sha":"__FIXTURE_SHA__","note":"x"}
{"reviewer":"fable-5","verdict":"YES","confidence":96,"sha":"__FIXTURE_SHA__","note":"x"}')" \
        "a payload with an unexpected extra key does not merge"
}

test_clearance_accepts_two_yes_verdicts() {
    # Non-vacuity control. If this fails, the two tests above prove nothing —
    # they would pass against a gate that rejects everything.
    local r
    r=$(run_with_clearance '{"reviewer":"gpt-5.6-sol","verdict":"YES","confidence":97,"sha":"__FIXTURE_SHA__"}
{"reviewer":"fable-5","verdict":"YES","confidence":96,"sha":"__FIXTURE_SHA__"}')
    if printf '%s' "$r" | grep -q "GH_MERGE_INVOKED"; then
        pass "two YES verdicts at >=95 bound to the head SHA do clear the merge"
    else
        fail "valid clearance failed to merge — the negative tests above are vacuous without this: $r"
    fi
}

test_sub_threshold_message_prescribes_next_action() {
    # A YES under 95 means a named residual concern, not a dead end. The gate
    # must say what to do next; tonight it just refused and the human ran the
    # merge by hand (GH #478).
    local r
    r=$(run_with_clearance '{"reviewer":"gpt-5.6-sol","verdict":"YES","confidence":97,"sha":"__FIXTURE_SHA__"}
{"reviewer":"fable-5","verdict":"YES","confidence":93,"sha":"__FIXTURE_SHA__"}')
    if printf '%s' "$r" | grep -qi "focused merge-safety round"; then
        pass "a sub-threshold YES prescribes the next action instead of dead-ending"
    else
        fail "sub-95 rejection gave no next action: $r"
    fi
}


test_clearance_requires_verdict_field
test_clearance_rejects_negative_verdict
test_clearance_rejects_lowercase_verdict
test_clearance_rejects_duplicate_verdict_keys
test_clearance_rejects_unicode_escaped_duplicate_key
test_clearance_rejects_unknown_extra_key
test_clearance_accepts_two_yes_verdicts
test_sub_threshold_message_prescribes_next_action

echo ""
# --- --user-approved: the human decision HARD_DENY demands (ROADMAP #479) -----
#
# HARD_DENY says "a human decides this one" and then provides no way for the
# human to say so. The maintainer hit this three times in one session; the last
# time the only route left was clicking merge in a browser, which bypasses the
# hook harness entirely and leaves no record in the repo.
#
# This flag does NOT prove a human typed it — nothing available here can. What
# it changes is that an override becomes EXPLICIT, REASONED and LOGGED instead
# of silent and out-of-band. That is the honest claim; the header comment in
# merge-pr.sh must not overstate it.

# Args are passed through as SEPARATE PARAMETERS, never as one string. An
# earlier version took a single string and word-split it unquoted, so
# `--user-approved ""` arrived as the literal two-character token `""` (which
# is non-empty, and merged) and a multi-word reason split into a usage error.
# Both failures were the harness, not the wrapper.
run_hard_deny() {   # "$@" = extra args, already separated
    local tmpdir out code
    tmpdir=$(setup_wrapper_fixture)
    printf 'DIFF_FILES=hooks/codex-gate-check.sh\n' >> "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "review body" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 "$@" 2>&1) && code=0 || code=$?
    printf 'exit=%s %s' "$code" "$out"
    rm -rf "$tmpdir"
}

test_hard_deny_still_blocks_without_the_flag() {
    refute_merge "$(run_hard_deny)" \
        "HARD_DENY path still blocks with no --user-approved"
}
test_hard_deny_still_blocks_without_the_flag

test_hard_deny_blocks_when_reason_is_missing() {
    # A bare flag is not a decision. If the reason can be omitted, the flag
    # becomes a silent bypass wearing an audit trail's clothes.
    refute_merge "$(run_hard_deny --user-approved)" \
        "--user-approved with no reason does not merge"
}
test_hard_deny_blocks_when_reason_is_missing

test_hard_deny_blocks_when_reason_is_blank() {
    refute_merge "$(run_hard_deny --user-approved "")" \
        "--user-approved with an empty reason does not merge"
}
test_hard_deny_blocks_when_reason_is_blank

test_cross_model_cleared_still_cannot_clear_hard_deny() {
    # The whole point of the tier: self-produced evidence never clears it.
    refute_merge "$(run_hard_deny --cross-model-cleared)" \
        "--cross-model-cleared still cannot clear a HARD_DENY path"
}
test_cross_model_cleared_still_cannot_clear_hard_deny

test_user_approved_with_reason_merges_and_logs() {
    local result
    result=$(run_hard_deny --user-approved "maintainer decision: gate fix, certified round 3")

    if ! printf '%s' "$result" | grep -q "GH_MERGE_INVOKED"; then
        fail "--user-approved with a reason did not merge: $result"
    elif ! printf '%s' "$result" | grep -qi "USER-APPROVED OVERRIDE"; then
        fail "--user-approved merged but logged no override record — a silent bypass: $result"
    elif ! printf '%s' "$result" | grep -q "maintainer decision: gate fix"; then
        fail "--user-approved merged but did not record the stated reason: $result"
    else
        pass "--user-approved with a reason merges AND logs an auditable override"
    fi
}
test_user_approved_with_reason_merges_and_logs

test_user_approved_records_the_path_it_overrode() {
    # The record has to name WHAT was overridden. "Approved" without the path
    # is unauditable after the fact.
    local result
    result=$(run_hard_deny --user-approved "shipping the hook fix")
    if printf '%s' "$result" | grep -q "hooks/codex-gate-check.sh"; then
        pass "--user-approved names the HARD_DENY path it overrode"
    else
        fail "override record does not name the path it cleared: $result"
    fi
}
test_user_approved_records_the_path_it_overrode

test_user_approved_also_clears_the_weaker_ackable_tier() {
    # Design gap found live merging PR #494: --user-approved cleared HARD_DENY
    # (the STRICTER tier) and then blocked on ACKABLE_DENY (the WEAKER one).
    # A human authorised to override the merge-evidence chain is necessarily
    # authorised to override the tier that only steers behaviour. Requiring a
    # second, different flag for the lesser bar is incoherent.
    local tmpdir out code
    tmpdir=$(setup_wrapper_fixture)
    # Both tiers at once: a hooks/ path (HARD) and the wizard doc (ACKABLE).
    # Quoted multi-line value: the stub does `printf '%s\n' "$DIFF_FILES"`, so
    # two separate config lines would leave the second as a bare token the
    # sourced file cannot assign — which fails closed on a truncated file set.
    printf 'DIFF_FILES=%s\n' "'hooks/codex-gate-check.sh
CLAUDE_CODE_SDLC_WIZARD.md'" >> "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "review body" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 --user-approved "maintainer decision" 2>&1) && code=0 || code=$?
    rm -rf "$tmpdir"

    if printf '%s' "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "--user-approved clears BOTH tiers, not just the stricter one"
    else
        fail "--user-approved cleared HARD_DENY but still blocked on the weaker ACKABLE tier (exit=$code): $out"
    fi
}
test_user_approved_also_clears_the_weaker_ackable_tier

# The two things --user-approved must NEVER waive. These are not paperwork:
# they are objective statements about whether the code works and whether the
# evidence that it works still exists. If a human can wave those away from a
# shell flag, the gate is decoration.
test_user_approved_cannot_waive_red_ci() {
    local tmpdir out code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's#VALIDATE_CONCLUSION=success#VALIDATE_CONCLUSION=failure#' "$tmpdir/.gh-stub-config"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 --user-approved "ship it anyway" 2>&1) && code=0 || code=$?
    rm -rf "$tmpdir"
    refute_merge "$(printf 'exit=%s %s' "$code" "$out")" \
        "--user-approved cannot merge over a red CI validate check"
}
test_user_approved_cannot_waive_red_ci

test_user_approved_cannot_waive_deleted_tests() {
    local tmpdir out code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's#DELETED_TEST_FILES=#DELETED_TEST_FILES=tests/test-merge-gate.sh#' "$tmpdir/.gh-stub-config"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 --user-approved "removing a flaky suite" 2>&1) && code=0 || code=$?
    rm -rf "$tmpdir"
    refute_merge "$(printf 'exit=%s %s' "$code" "$out")" \
        "--user-approved cannot merge a PR that net-removes test files"
}
test_user_approved_cannot_waive_deleted_tests

# Argument shaping. Found by probing before the reviewers reported:
# `--user-approved --cross-model-cleared` made the NEXT FLAG the reason, firing
# a full override whose stated justification was the string "--cross-model-cleared".
# A reason that is actually a flag is not a reason.
test_user_approved_rejects_a_flag_as_its_reason() {
    refute_merge "$(run_hard_deny --user-approved --cross-model-cleared)" \
        "--user-approved does not accept the next flag as its reason"
}
test_user_approved_rejects_a_flag_as_its_reason

test_user_approved_rejects_whitespace_only_reason() {
    refute_merge "$(run_hard_deny --user-approved "   ")" \
        "--user-approved does not accept a whitespace-only reason"
}
test_user_approved_rejects_whitespace_only_reason

# The audit record must not claim verification that did not happen. The first
# version printed "clearance CERTIFIED round>=2 fresh ... denylist clear"
# unconditionally, so an override that skipped both still produced a record
# saying both were checked. Cross-model review reproduced the contradiction.
test_override_audit_record_does_not_claim_false_verification() {
    local result
    result=$(run_hard_deny --user-approved "maintainer decision")

    if ! printf '%s' "$result" | grep -q "GH_MERGE_INVOKED"; then
        fail "fixture did not merge, cannot check the audit line: $result"
    elif printf '%s' "$result" | grep -q "clearance CERTIFIED round>=2 fresh"; then
        fail "audit record claims clearance was verified when the override SKIPPED it: $result"
    elif printf '%s' "$result" | grep -q "denylist clear"; then
        fail "audit record claims the denylist was clear when the override WAIVED it: $result"
    elif ! printf '%s' "$result" | grep -q "OVERRIDDEN by --user-approved"; then
        fail "audit record does not say which checks were waived: $result"
    elif ! printf '%s' "$result" | grep -q "VERIFIED (not waivable)"; then
        fail "audit record does not separate what WAS verified from what was waived: $result"
    else
        pass "override audit record states what was verified vs what was waived"
    fi
}
test_override_audit_record_does_not_claim_false_verification

test_override_posts_a_durable_record_to_the_pr() {
    local result
    result=$(run_hard_deny --user-approved "maintainer decision")
    # The wrapper suppresses gh's own output, so assert on its confirmation.
    # That line only prints when the post succeeded — proven by the
    # COMMENT_FAILS test below, which shows a failed post blocks the merge.
    if printf '%s' "$result" | grep -q "Override recorded on PR"; then
        pass "override posts a durable record to the PR, not just stderr"
    else
        fail "override merged with no durable record — the reason evaporates with the session: $result"
    fi
}
test_override_posts_a_durable_record_to_the_pr

test_override_refuses_to_merge_if_the_record_cannot_be_posted() {
    local tmpdir out code
    tmpdir=$(setup_wrapper_fixture)
    printf 'DIFF_FILES=hooks/codex-gate-check.sh\n' >> "$tmpdir/.gh-stub-config"
    printf 'COMMENT_FAILS=1\n' >> "$tmpdir/.gh-stub-config"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 --user-approved "maintainer decision" 2>&1) && code=0 || code=$?
    rm -rf "$tmpdir"
    refute_merge "$(printf 'exit=%s %s' "$code" "$out")" \
        "an override that cannot be recorded does not merge"
}
test_override_refuses_to_merge_if_the_record_cannot_be_posted

echo ""
# --- --dual-certified: dual cross-model agreement AS merge authority (#511) ---
#
# The maintainer stated it as standing policy: "if fable and codex agree with the
# merge then you don't need me". The gate could not express that. HARD_DENY said
# "a human decides" and the only way to say yes was --user-approved, so every
# merge on 2026-08-07/08 recorded a per-PR human decision that had actually been
# made once, months earlier, as policy. The mechanism was forcing a framing lie
# into the audit trail — worse than an inconvenience, because these records are
# the durable evidence of WHY something merged.
#
# What makes this different from self-review, and therefore admissible where
# --cross-model-cleared is not: two models that did not write the code, run blind
# to each other, each able to refuse. PR #497 took five rounds before both
# certified and every round found real defects.
#
# What it still is not: authentication. Both clearance comments are posted by the
# same gh token. The success line must say ATTESTED, NOT AUTHENTICATED.

# The fixture's gate files must byte-match its own origin/main for the dual
# path's self-integrity check to have anything honest to compare against.
# The fixture must install the REAL wrapper and REAL hook and execute the
# fixture's own copy. Round 1, both reviewers independently: the first version
# committed two-line `echo gate` dummies as the "pristine" gate while
# `run_dual_in` executed the real repo's script by absolute path — so integrity
# passed against files that had nothing to do with the code deciding the merge.
# The fixture was demonstrating the very hole it was supposed to guard.
make_gate_pristine() {   # $1=tmpdir
    local d="$1"
    mkdir -p "$d/scripts" "$d/.claude/hooks"
    cp "$WRAPPER" "$d/scripts/merge-pr.sh"
    cp "$HOOK" "$d/.claude/hooks/merge-gate-check.sh"
    chmod +x "$d/scripts/merge-pr.sh" "$d/.claude/hooks/merge-gate-check.sh"
    git -C "$d" add -A >/dev/null 2>&1
    git -C "$d" -c user.email=t@example.com -c user.name=t commit -qm fixture >/dev/null 2>&1
    git -C "$d" update-ref refs/remotes/origin/main HEAD
    # This commit MOVES the head, so everything keyed on it must move with it.
    # Before #540 only the sha mattered and the stub's HEAD_SHA was a constant,
    # so nothing here needed refreshing; now the clearance also names the tree
    # that merges, and a stale one reads as "the base moved since
    # certification" — a true statement about a fixture artifact, not about
    # anything under test.
    git -C "$d" rev-parse HEAD > "$d/.fixture-sha"
    git -C "$d" rev-parse 'HEAD^{tree}' > "$d/.fixture-tree"
    printf 'HEAD_SHA=%s\n' "$(cat "$d/.fixture-sha")" >> "$d/.gh-stub-config"
}

DUAL_YES_PAYLOADS='{"reviewer":"gpt-5.6-sol","verdict":"YES","confidence":97,"sha":"__FIXTURE_SHA__"}
{"reviewer":"fable-5","verdict":"YES","confidence":96,"sha":"__FIXTURE_SHA__"}'

# Everything a HARD-tier dual-certified merge is supposed to need, all valid.
# Individual tests then break exactly one thing.
setup_dual_fixture() {   # echoes tmpdir
    local tmpdir
    tmpdir=$(setup_wrapper_fixture)
    printf 'DIFF_FILES=hooks/codex-gate-check.sh\n' >> "$tmpdir/.gh-stub-config"
    printf 'CLEARANCE_PAYLOADS=%s\n' "$(printf '%q' "$DUAL_YES_PAYLOADS")" >> "$tmpdir/.gh-stub-config"
    echo "review body" > "$tmpdir/.reviews/some-review.md"
    make_gate_pristine "$tmpdir"
    # AFTER make_gate_pristine, never before: it commits, so it is the last
    # thing that moves the head and the trees the clearance has to name.
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "$tmpdir"
}

# Executes the FIXTURE'S copy, by the relative path the redirect hook trains
# agents to use — not the real repo's script. Anything else makes the integrity
# assertion meaningless.
run_dual_in() {   # $1=tmpdir, rest=wrapper args
    local tmpdir="$1"; shift
    local out code
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" ./scripts/merge-pr.sh 123 "$@" 2>&1) && code=0 || code=$?
    # Fold in what was actually POSTED, not just what the wrapper said it did.
    local posted=""
    [ -f "$tmpdir/.posted-comments" ] && posted=$(cat "$tmpdir/.posted-comments")
    rm -rf "$tmpdir"
    printf 'exit=%s %s %s' "$code" "$out" "$posted"
}

# THE POINT OF THE WHOLE CHANGE. If this fails, every refusal test below is
# vacuous — they would all pass against a gate that refuses everything.
test_dual_certified_clears_hard_deny() {
    local r
    r=$(run_dual_in "$(setup_dual_fixture)" --dual-certified)
    if ! printf '%s' "$r" | grep -q "GH_MERGE_INVOKED"; then
        fail "two SHA-bound YES verdicts did not clear a HARD_DENY path — the gate still cannot express the standing policy: $r"
    elif ! printf '%s' "$r" | grep -q "DUAL-CERTIFIED"; then
        fail "merged but did not name the authority it merged under: $r"
    else
        pass "--dual-certified clears a HARD_DENY path on two SHA-bound YES verdicts"
    fi
}
test_dual_certified_clears_hard_deny

# The audit record is the deliverable, not a nicety. #511 exists because the
# records were misattributing a standing policy to a per-PR judgement; a record
# that overstates what was proven repeats that failure in the other direction.
test_dual_certified_record_says_attested_not_authenticated() {
    local r
    r=$(run_dual_in "$(setup_dual_fixture)" --dual-certified)
    if ! printf '%s' "$r" | grep -q "GH_MERGE_INVOKED"; then
        fail "fixture did not merge, cannot inspect the audit line: $r"
    elif ! printf '%s' "$r" | grep -qi "ATTESTED, NOT AUTHENTICATED"; then
        fail "the dual-certified audit record does not state that both clearances came from the same token: $r"
    elif ! printf '%s' "$r" | grep -q "gpt-5.6-sol"; then
        fail "the audit record does not name which reviewers cleared it: $r"
    else
        pass "the dual-certified record names its reviewers and does not oversell them as authenticated"
    fi
}
test_dual_certified_record_says_attested_not_authenticated

test_dual_certified_needs_two_distinct_reviewers() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    printf 'CLEARANCE_PAYLOADS=%s\n' "$(printf '%q' '{"reviewer":"gpt-5.6-sol","verdict":"YES","confidence":97,"sha":"__FIXTURE_SHA__"}')" \
        >> "$tmpdir/.gh-stub-config"
    refute_merge "$(run_dual_in "$tmpdir" --dual-certified)" \
        "one reviewer alone does not dual-certify a HARD_DENY path"
}
test_dual_certified_needs_two_distinct_reviewers

test_dual_certified_refuses_a_no_verdict() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    printf 'CLEARANCE_PAYLOADS=%s\n' "$(printf '%q' '{"reviewer":"gpt-5.6-sol","verdict":"YES","confidence":97,"sha":"__FIXTURE_SHA__"}
{"reviewer":"fable-5","verdict":"NO","confidence":96,"sha":"__FIXTURE_SHA__"}')" >> "$tmpdir/.gh-stub-config"
    refute_merge "$(run_dual_in "$tmpdir" --dual-certified)" \
        "one YES and one NO does not dual-certify — disagreement is the human's case, not a merge"
}
test_dual_certified_refuses_a_no_verdict

# The staleness bar #511 asked for: round-1-only CERTIFIED is a rubber stamp.
# --user-approved waives the artifact checks; --dual-certified must NOT, because
# the artifact is the only evidence that a dialogue happened at all.
test_dual_certified_still_requires_round_2_artifact() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    refute_merge "$(run_dual_in "$tmpdir" --dual-certified)" \
        "a round-1-only clearance artifact still blocks under --dual-certified"
}
test_dual_certified_still_requires_round_2_artifact

# Self-integrity. A PR that edits the gate would otherwise be judged by its own
# edited gate — the exact circularity HARD_DENY exists to prevent, and the one
# thing dual review alone does not fix (the reviewers read the diff; the running
# code is what actually decides).
#
# Fable round 2: after the fixture rework this test became vacuous — it clobbered
# the EXECUTING script with two words of prose, so the run died at exit 127
# ("command not found") and verify_gate_integrity never ran. It was asserting
# that garbage does not merge. The tamper must stay FUNCTIONAL to reach the check
# at all, which is also the only shape that matters: a PR branch whose gate still
# works but no longer says what origin/main's says.
test_dual_certified_blocks_a_modified_gate() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    printf '\n# functional, but no longer the reviewed gate\n' >> "$tmpdir/scripts/merge-pr.sh"
    local r
    r=$(run_dual_in "$tmpdir" --dual-certified)
    if printf '%s' "$r" | grep -q "command not found\|exit=127"; then
        fail "the tampered gate did not even execute — this test would pass against no check at all: $r"
    else
        refute_merge "$r" \
            "an executing gate that differs from origin/main does not dual-certify"
    fi
}
test_dual_certified_blocks_a_modified_gate

test_dual_certified_blocks_a_modified_redirect_hook() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    echo "hook, but disarmed" > "$tmpdir/.claude/hooks/merge-gate-check.sh"
    refute_merge "$(run_dual_in "$tmpdir" --dual-certified)" \
        "a working-tree redirect hook that differs from origin/main does not dual-certify"
}
test_dual_certified_blocks_a_modified_redirect_hook

# THE ROUND-1 P0/P1, found independently by both reviewers. The check compared
# cwd-relative paths and never looked at $0, so the executed script was never the
# verified one — and the gate's OWN error message ("run the merge from a clean
# main checkout") steers an agent straight into the gap: it re-runs the absolute
# path it already knows, from a clean cwd, and the PR's edited gate decides while
# the audit line says the gate matched origin/main.
#
# Not the conceded "an agent could edit the script": nothing is edited or
# deleted here. The check simply binds the wrong artifact.
test_dual_certified_verifies_the_executing_script_not_the_cwd_copy() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    # cwd copy stays pristine; a DIFFERENT copy — byte-different, behaviourally
    # identical (a comment) — is what actually runs.
    mkdir -p "$tmpdir/pr-branch"
    cp "$tmpdir/scripts/merge-pr.sh" "$tmpdir/pr-branch/merge-pr.sh"
    printf '\n# tampered on the PR branch\n' >> "$tmpdir/pr-branch/merge-pr.sh"
    chmod +x "$tmpdir/pr-branch/merge-pr.sh"
    local out code
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$tmpdir/pr-branch/merge-pr.sh" 123 --dual-certified 2>&1) && code=0 || code=$?
    rm -rf "$tmpdir"
    refute_merge "$(printf 'exit=%s %s' "$code" "$out")" \
        "the RUNNING script must match origin/main, not just the cwd copy"
}
test_dual_certified_verifies_the_executing_script_not_the_cwd_copy

# Fable round 1: the dual path asserted "gate byte-matches origin/main" and
# "artifact CERTIFIED at round>=2" nowhere durable — stdout only, gone with the
# session. Exactly the defect fixed once already for --user-approved after PR
# #494 merged traceless, re-introduced on the new path. #511's whole framing is
# that the RECORD is the deliverable.
test_dual_certified_posts_a_durable_record() {
    local r
    r=$(run_dual_in "$(setup_dual_fixture)" --dual-certified)
    if ! printf '%s' "$r" | grep -q "GH_MERGE_INVOKED"; then
        fail "fixture did not merge, cannot check for a durable record: $r"
    elif printf '%s' "$r" | grep -q "Dual certification recorded on PR"; then
        pass "the dual path posts a durable record to the PR, not just stdout"
    else
        fail "dual-certified merged leaving no durable record of what was verified: $r"
    fi
}
test_dual_certified_posts_a_durable_record

test_dual_certified_refuses_to_merge_if_the_record_cannot_be_posted() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    printf 'COMMENT_FAILS=1\n' >> "$tmpdir/.gh-stub-config"
    refute_merge "$(run_dual_in "$tmpdir" --dual-certified)" \
        "a dual-certified merge whose record cannot be posted does not merge"
}
test_dual_certified_refuses_to_merge_if_the_record_cannot_be_posted

# Fable round 1, pre-existing but on-theme: with a clearance flag and NO
# denylisted path, clearance never runs, so CLEARED_BY is empty and the audit
# line read "...and denylist acknowledged by ." — an acknowledgement by nobody.
test_clearance_flag_on_a_clean_pr_does_not_claim_a_phantom_acknowledgement() {
    local tmpdir r
    tmpdir=$(setup_dual_fixture)
    printf 'DIFF_FILES=src/foo.js\n' >> "$tmpdir/.gh-stub-config"
    r=$(run_dual_in "$tmpdir" --dual-certified)
    if ! printf '%s' "$r" | grep -q "GH_MERGE_INVOKED"; then
        fail "fixture did not merge, cannot inspect the audit line: $r"
    elif printf '%s' "$r" | grep -qE "acknowledged by[[:space:]]*\.?$|acknowledged by[[:space:]]*$"; then
        fail "audit line claims a denylist acknowledgement by nobody: $r"
    else
        pass "a clearance flag on a clean PR reports 'denylist clear', not an empty acknowledgement"
    fi
}
test_clearance_flag_on_a_clean_pr_does_not_claim_a_phantom_acknowledgement

# The three things NO amount of model agreement clears. Red CI and missing tests
# are objective statements about whether the code works and whether the evidence
# it works still exists. A version bump is a release, and releases stay human.
test_dual_certified_cannot_waive_red_ci() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    printf 'VALIDATE_CONCLUSION=failure\n' >> "$tmpdir/.gh-stub-config"
    refute_merge "$(run_dual_in "$tmpdir" --dual-certified)" \
        "--dual-certified cannot merge over a red CI validate check"
}
test_dual_certified_cannot_waive_red_ci

test_dual_certified_cannot_waive_test_deletion() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    printf 'DELETED_TEST_FILES=tests/test-something.sh\n' >> "$tmpdir/.gh-stub-config"
    refute_merge "$(run_dual_in "$tmpdir" --dual-certified)" \
        "--dual-certified cannot merge a PR that net-removes test files"
}
test_dual_certified_cannot_waive_test_deletion

test_dual_certified_cannot_waive_a_version_bump() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    printf 'PACKAGE_JSON_VERSION_CHANGED=1\n' >> "$tmpdir/.gh-stub-config"
    refute_merge "$(run_dual_in "$tmpdir" --dual-certified)" \
        "--dual-certified cannot publish a release — a version bump still needs --user-approved"
}
test_dual_certified_cannot_waive_a_version_bump

# Greater authority covers lesser: a PR touching both tiers must not need two
# flags. Merging PR #494 hit the mirror-image of this bug, where --user-approved
# cleared six hooks/ paths and then blocked on a doc.
test_dual_certified_covers_the_ackable_tier_too() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    # Quoted: the stub config is `source`d, so an unquoted second word is run as
    # a command, and its "not found" lands on stderr — which the wrapper folds
    # into the API payload with 2>&1 and then fails closed on. The failure looked
    # like a gate bug and was a harness bug.
    printf "DIFF_FILES='hooks/codex-gate-check.sh CLAUDE_CODE_SDLC_WIZARD.md'\n" >> "$tmpdir/.gh-stub-config"
    local r
    r=$(run_dual_in "$tmpdir" --dual-certified)
    if printf '%s' "$r" | grep -q "GH_MERGE_INVOKED"; then
        pass "--dual-certified clears both tiers, not just the stricter one"
    else
        fail "--dual-certified cleared HARD_DENY but still blocked on the weaker ACKABLE tier: $r"
    fi
}
test_dual_certified_covers_the_ackable_tier_too

# The block message has to name the new route or the gate is a dead end again —
# which is the failure mode #478 and #511 are both about.
test_hard_deny_block_message_offers_the_dual_route() {
    local r
    r=$(run_hard_deny)
    if printf '%s' "$r" | grep -q -- "--dual-certified"; then
        pass "the HARD_DENY refusal names --dual-certified as a route, not just --user-approved"
    else
        fail "the HARD_DENY refusal still offers only a human override: $r"
    fi
}
test_hard_deny_block_message_offers_the_dual_route

echo ""
# --- CI validate: a second check-run of the same name must not be shadowed ----
#
# Branch protection requires the check by NAME, so nothing stops more than one
# run called "validate" existing on a SHA. The conclusion lookup stopped at the
# first match, so a green one ordered ahead of a red one satisfied the gate.
# This is the same defect class as reading evidence structure and never the
# answer inside it.
test_wrapper_blocks_a_shadowed_red_validate() {
    local tmpdir out code
    tmpdir=$(setup_wrapper_fixture)
    printf 'EXTRA_VALIDATE_CONCLUSION=failure\n' >> "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "review body" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && code=0 || code=$?
    rm -rf "$tmpdir"
    refute_merge "$(printf 'exit=%s %s' "$code" "$out")" \
        "a red second check-run named validate is not shadowed by a green first one"
}
test_wrapper_blocks_a_shadowed_red_validate

# Both reviewers, round 1: "ALL runs of that name must be green" was only true
# for runs carrying a STRING conclusion. GitHub represents a queued or
# in-progress run as `"conclusion": null`, which the quoted-value regex could not
# see — so a still-running `validate` alongside an old green one merged, while
# the block message claimed pending blocks and the ROADMAP claimed every run of
# that name was green. The extraction is jq now, which sees the null.
test_wrapper_blocks_an_in_progress_duplicate_validate() {
    local tmpdir out code
    tmpdir=$(setup_wrapper_fixture)
    printf 'EXTRA_VALIDATE_CONCLUSION=null\n' >> "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "review body" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && code=0 || code=$?
    rm -rf "$tmpdir"
    refute_merge "$(printf 'exit=%s %s' "$code" "$out")" \
        "a second 'validate' still in progress (conclusion null) blocks the merge"
}
test_wrapper_blocks_an_in_progress_duplicate_validate

# Codex round 2: the jq unwrap handled the {check_runs:[...]} envelope but a
# BARE ARRAY page fell through `else .` and was dropped by the type filter, so a
# green wrapped page followed by a bare page carrying a red validate merged. The
# round-1 stub emitted neither real shape, so nothing could have caught it.
test_wrapper_blocks_a_red_validate_on_a_bare_array_page() {
    local tmpdir out code
    tmpdir=$(setup_wrapper_fixture)
    printf 'EXTRA_VALIDATE_CONCLUSION=failure\n' >> "$tmpdir/.gh-stub-config"
    printf 'EXTRA_VALIDATE_PAGE_SHAPE=bare\n' >> "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "review body" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && code=0 || code=$?
    rm -rf "$tmpdir"
    refute_merge "$(printf 'exit=%s %s' "$code" "$out")" \
        "a red validate on a bare-array page is not dropped by the envelope unwrap"
}
test_wrapper_blocks_a_red_validate_on_a_bare_array_page

# Codex round 2: the record tests asserted only on the wrapper's own
# confirmation line and never on what was actually POSTED, so a body that
# rendered empty or truncated would still have passed. Assert the payload.
test_dual_record_body_names_the_authorized_path() {
    local r
    r=$(run_dual_in "$(setup_dual_fixture)" --dual-certified)
    if ! printf '%s' "$r" | grep -q "GH_MERGE_INVOKED"; then
        fail "fixture did not merge, cannot inspect the posted body: $r"
    elif ! printf '%s' "$r" | grep -q "GH_COMMENT_BODY:.*hooks/codex-gate-check.sh"; then
        fail "the posted dual-certification body does not name the merge-evidence path it authorised: $r"
    elif ! printf '%s' "$r" | grep -q "GH_COMMENT_BODY:.*gpt-5.6-sol"; then
        fail "the posted body does not name the reviewers who cleared it: $r"
    else
        pass "the posted dual-certification body names the authorised path and the reviewers"
    fi
}
test_dual_record_body_names_the_authorized_path

echo ""
echo "--- afterhours guard (no merges Mon-Fri 08:00-16:59) ---"

# Runs the wrapper at FAKE_NOW with a gh that only records that it was called
# and then fails. "gh=called" therefore means the run got PAST the guard;
# "gh=uncalled" means it stopped before any network call.
# Echoes "exit=<n> gh=<called|uncalled> tz=<what date saw> <output>".
run_at_clock() {   # $1=FAKE_NOW "<%u> <%H> <%M>", rest=wrapper args
    local now="$1"; shift
    local tmpdir out code gh tz
    tmpdir=$(setup_wrapper_fixture)
    cat > "$tmpdir/bin/gh" <<'STUB'
#!/bin/bash
touch "$(dirname "$0")/../.gh-called"
exit 1
STUB
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" FAKE_NOW="$now" "$WRAPPER" 123 "$@" 2>&1) && code=0 || code=$?
    gh=uncalled; [ -f "$tmpdir/.gh-called" ] && gh=called
    tz=$(cat "$tmpdir/.date-tz" 2>/dev/null || echo never)
    rm -rf "$tmpdir"
    printf 'exit=%s gh=%s tz=%s %s' "$code" "$gh" "$tz" "$out"
}

assert_refused_in_window() {   # $1=label, $2=run_at_clock result
    case "$2" in
        exit=0*) fail "$1: exited 0 inside the window: $2" ;;
        *gh=called*) fail "$1: reached gh inside the window: $2" ;;
        *"Mon-Fri 08:00-16:59"*) pass "$1: refused before any gh call, message names the window" ;;
        *) fail "$1: refused, but the message does not name the window: $2" ;;
    esac
}

assert_past_guard() {   # $1=label, $2=run_at_clock result
    case "$2" in
        *"Mon-Fri 08:00-16:59"*) fail "$1: the afterhours guard refused it: $2" ;;
        *gh=called*) pass "$1: proceeds past the afterhours guard" ;;
        *) fail "$1: never reached gh: $2" ;;
    esac
}

assert_refused_in_window "weekday 10:00 (Mon)" "$(run_at_clock '1 10 00')"
assert_refused_in_window "weekday 08:00 (Mon), first refused minute" "$(run_at_clock '1 08 00')"
assert_refused_in_window "weekday 16:59 (Fri), last refused minute" "$(run_at_clock '5 16 59')"
assert_refused_in_window "weekday 10:00 with --user-approved, no flag lifts it" \
    "$(run_at_clock '1 10 00' --user-approved "maintainer decision: ship it")"
assert_refused_in_window "weekday 10:00 with --dual-certified, no flag lifts it" \
    "$(run_at_clock '1 10 00' --dual-certified)"
# The pre-push hook's knobs must not reach this guard: the wrapper reads none.
assert_refused_in_window "weekday 10:00 with the pre-push hook's AFTERHOURS_* knobs set" \
    "$(AFTERHOURS_SKIP=1 AFTERHOURS_DOW=6 AFTERHOURS_HOUR=20 run_at_clock '1 10 00')"
assert_past_guard "weekday 17:00 (Mon)" "$(run_at_clock '1 17 00')"
assert_past_guard "weekday 07:59 (Wed)" "$(run_at_clock '3 07 59')"
assert_past_guard "Saturday 12:00" "$(run_at_clock '6 12 00')"
assert_past_guard "Sunday 12:00" "$(run_at_clock '7 12 00')"

# Fail closed on a clock it cannot parse. Without this a non-numeric day made
# the `[ -le ]` comparison error out, the condition read false, and the merge
# went ahead.
test_afterhours_fails_closed_on_unparseable_clock() {
    local r
    r=$(run_at_clock 'x 10 00')
    case "$r" in
        exit=0*|*gh=called*) fail "an unparseable clock got past the guard: $r" ;;
        *"FAILED CLOSED"*) pass "an unparseable clock fails closed before any gh call" ;;
        *) fail "an unparseable clock was refused without saying it failed closed: $r" ;;
    esac
}
test_afterhours_fails_closed_on_unparseable_clock

# The caller's TZ must not move the clock. TZ=UTC turns 14:00 PST into 22:00,
# outside the window, so an inherited TZ would be a bypass. The stub records
# the TZ it was given; the wrapper must have removed it.
test_afterhours_ignores_caller_tz() {
    local r
    r=$(TZ=UTC run_at_clock '6 12 00')
    case "$r" in
        *"tz=unset "*) pass "the caller's TZ never reaches the guard's date call" ;;
        *) fail "the guard's date call saw the caller's TZ: $r" ;;
    esac
}
test_afterhours_ignores_caller_tz

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi


echo ""
echo "All merge gate tests passed!"
