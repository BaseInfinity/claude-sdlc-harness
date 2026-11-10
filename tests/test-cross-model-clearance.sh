#!/bin/bash
# tests/test-cross-model-clearance.sh
#
# ROADMAP #479: maintainer *approval* and safety-check *bypass* were the same
# lever. `MERGE_CLEARANCE_SKIP=1` was the only way past a denylist hit, and it
# also disabled the CI check, the test-deletion check, the head-SHA freshness
# check and the clearance-artifact check — so acknowledging one red row meant
# disarming four green ones. It was also unusable by an agent: Claude Code's
# auto-mode classifier denies it as a safeguard bypass, by design.
#
# This replaces it with `--cross-model-cleared`, which satisfies the DENYLIST
# FINDING ONLY. Every other check stays mandatory and fail-closed.
#
# WHAT THIS IS — corrected after review, having first been overstated here.
# The original version of this comment claimed the evidence is "EXTERNALLY
# VERIFIABLE ... timestamped, attributable, SHA-bound" and therefore harder to
# forge than a local artifact. Codex disproved *attributable* by execution: the
# author was discarded, so the reviewer identity was a self-declared string, and
# one account posted two comments claiming to be two different models. Binding
# to the author does not rescue it either — both reviews come from the same `gh`
# token, so there is no second authenticated principal.
#
# The honest claim is narrower: this is an AUDIT TRAIL, not an authentication
# boundary. It is durable, timestamped, visibly rendered, and invalidated by any
# new push. It does NOT prove two models ran. The genuinely load-bearing win is
# the SCOPE fix — the acknowledgement no longer disarms CI, test-deletion,
# SHA-freshness or the clearance artifact, which was #479's actual defect.
#
# Required shape of a clearance comment on the PR (the marker is deliberately
# VISIBLE — an HTML-comment marker let the whole payload be hidden from the
# human the audit trail exists for):
#
#   **CROSS-MODEL-CLEARANCE**
#   ```json
#   {"reviewer":"codex-gpt-5.6-sol","confidence":100,"sha":"<40 hex>"}
#   ```
#
# Merge is permitted past a denylist hit only when at least two DISTINCT
# reviewers have posted such a comment, each at confidence >= 95, each bound to
# the exact head SHA being merged. Pushing a new commit invalidates clearance.
#
# Per ROADMAP #482, every assertion below checks the EXIT CODE, not a grepped
# message string: message text drifts, and an assertion that only greps prose
# passes vacuously the moment the wording changes.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$REPO_ROOT/scripts/merge-pr.sh"
HOOK="$REPO_ROOT/.claude/hooks/merge-gate-check.sh"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# #540: the merge boundary resolves the head's TREE, so the fixture head can no
# longer be a made-up 40-char string — git has to be able to look it up. One
# template repo is built here and its .git is copied into every fixture, which
# keeps HEAD_SHA a single file-scope constant (dozens of call sites embed it in
# clearance-comment payloads) while making it a real object.
XMC_TEMPLATE=$(mktemp -d "${TMPDIR:-/tmp}/xmc-tpl.XXXXXX") || exit 1
trap 'rm -rf "$XMC_TEMPLATE"' EXIT
git -C "$XMC_TEMPLATE" init -q
git -C "$XMC_TEMPLATE" config user.email t@example.com
git -C "$XMC_TEMPLATE" config user.name "SDLC Test"
git -C "$XMC_TEMPLATE" commit -q --allow-empty -m fixture
git -C "$XMC_TEMPLATE" update-ref refs/remotes/origin/main HEAD
HEAD_SHA=$(git -C "$XMC_TEMPLATE" rev-parse HEAD)
HEAD_TREE=$(git -C "$XMC_TEMPLATE" rev-parse 'HEAD^{tree}')
OTHER_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

# ---------------------------------------------------------------------------
# Stub harness: a fake `gh` on PATH. Extends the pattern in test-merge-gate.sh
# with the issues/<PR>/comments endpoint the new check reads.
#
# Knobs (env vars read by the stub):
#   DIFF_FILES            newline list of changed paths
#   VALIDATE_CONCLUSION   conclusion of the CI `validate` check run
#   DELETED_TEST_FILES    space list of removed test paths
#   CLEARANCE_COMMENTS    newline list of "reviewer|confidence|sha" triples
# ---------------------------------------------------------------------------
make_stub_env() {
    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/xmc.XXXXXX") || return 1
    mkdir -p "$tmpdir/bin" "$tmpdir/.reviews"
    # A real repo whose HEAD is HEAD_SHA, so the #540 tree lookups resolve.
    cp -R "$XMC_TEMPLATE/.git" "$tmpdir/.git"
    cat > "$tmpdir/bin/gh" <<'STUB'
#!/bin/bash
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
    case "$*" in
        *changedFiles*)
            # Default to the real number of changed paths, so only tests that
            # deliberately simulate truncation set CHANGED_FILES_COUNT.
            if [ "${CHANGED_FILES_COUNT:-0}" -gt 0 ] 2>/dev/null; then
                echo "$CHANGED_FILES_COUNT"
            else
                n=0
                for _f in $DIFF_FILES; do n=$((n+1)); done
                [ -n "${RENAMED_FROM:-}" ] && n=$((n+1))
                for _f in ${DELETED_TEST_FILES:-}; do n=$((n+1)); done
                echo "$n"
            fi
            exit 0 ;;
    esac
    echo "{\"headRefOid\":\"$HEAD_SHA\",\"number\":123,\"state\":\"OPEN\",\"baseRefName\":\"main\"}"
    exit 0
elif [ "$1" = "pr" ] && [ "$2" = "diff" ]; then
    printf '%s\n' "$DIFF_FILES"
    exit 0
elif [ "$1" = "api" ]; then
    case "$*" in
        *git/ref/heads/*)
            # #540 round 3: the merge boundary asks the server for the base
            # branch tip. baseRefOid is a PR snapshot and is no longer read.
            echo "{\"object\":{\"sha\":\"$HEAD_SHA\"}}"
            exit 0 ;;
        *check-runs*)
            echo "{\"conclusion\":\"$VALIDATE_CONCLUSION\",\"name\":\"validate\"}"
            ;;
        *issues*comments*)
            # A JSON array, exactly as real `gh api --paginate` returns.
            printf '['
            first=1
            if [ -n "${CLEARANCE_COMMENTS:-}" ]; then
                # GH #478 added a required `verdict` field: confidence was
                # standing in for a decision the parser never read, so two
                # reviewers posting MERGE_SAFE: NO at 97 and 99 merged. A 4th
                # pipe-delimited field sets it; existing 3-field rows default to
                # YES so they keep testing what they were written to test
                # (confidence bounds, SHA binding, visibility, authorship).
                while IFS='|' read -r who conf sha verdict; do
                    [ -z "$who" ] && continue
                    [ "$first" = 0 ] && printf ','
                    first=0
                    printf '{"user":{"login":"%s"},"author_association":"%s","body":"**CROSS-MODEL-CLEARANCE**\\n```json\\n{\\"reviewer\\":\\"%s\\",\\"verdict\\":\\"%s\\",\\"confidence\\":%s,\\"sha\\":\\"%s\\"}\\n```"}' \
                        "${AUTHOR:-maintainer}" "${ASSOC:-OWNER}" "$who" "${verdict:-YES}" "$conf" "$sha"
                done <<EOF
$CLEARANCE_COMMENTS
EOF
            fi
            printf ']\n'
            ;;
        *pulls*files*)
            # Now the authoritative source for tier classification, so it must
            # list every changed path, JSON-encoded, as real gh does.
            printf '['
            f1=1
            for f in $DIFF_FILES; do
                [ "$f1" = 0 ] && printf ','
                f1=0
                printf '{"filename":"%s","status":"modified"}' "$f"
            done
            if [ -n "${RENAMED_FROM:-}" ]; then
                [ "$f1" = 0 ] && printf ','
                f1=0
                printf '{"filename":"%s","previous_filename":"%s","status":"renamed"}' \
                    "${RENAMED_TO:-renamed-dest}" "$RENAMED_FROM"
            fi
            if [ -n "${DELETED_TEST_FILES:-}" ]; then
                for f in $DELETED_TEST_FILES; do
                    [ "$f1" = 0 ] && printf ','
                    f1=0
                    printf '{"filename":"%s","status":"removed"}' "$f"
                done
            fi
            printf ']\n'
            ;;
    esac
    exit 0
elif [ "$1" = "pr" ] && [ "$2" = "merge" ]; then
    echo "GH_MERGE_INVOKED: $*"
    exit 0
fi
echo "unstubbed gh invocation: $*" >&2
exit 1
STUB
    chmod +x "$tmpdir/bin/gh"
    # Fixture clock: merge-pr.sh refuses Mon-Fri 08:00-16:59, so every row
    # runs at Saturday 12:00 or its result depends on when the suite runs.
    # Expands only %u %H %M in the requested format; the guard's own rows
    # live in tests/test-merge-gate.sh.
    cat > "$tmpdir/bin/date" <<'STUB'
#!/bin/bash
[ $# -eq 1 ] && [ "${1#+}" != "$1" ] || { echo "date stub: unexpected argv: $*" >&2; exit 2; }
out=${1#+}; out=${out//%u/6}; out=${out//%H/12}; out=${out//%M/00}
case "$out" in *%*) echo "date stub: unsupported format: $1" >&2; exit 2 ;; esac
printf '%s\n' "$out"
STUB
    chmod +x "$tmpdir/bin/date"
    echo "$tmpdir"
}

# #636 added base_sha to the enforced contract, so every artifact this suite
# writes needs it or the wrapper fails closed before reaching the checks these
# rows are actually about. Defaults to the fixture's real base — these tests are
# about clearance COMMENTS, not about ancestry; arg 5 exists for a row that
# wants to say otherwise.
write_clearance_artifact() {
    cat > "$1/.reviews/merge-clearance-123.json" <<JSON
{ "pr_number": 123, "status": "CERTIFIED", "round": 4, "sha": "$2",
  "candidate_tree": "${3:-$HEAD_TREE}", "base_tree": "${4:-$HEAD_TREE}",
  "base_sha": "${5:-$HEAD_SHA}",
  "review_file": ".reviews/r.md" }
JSON
    echo "review body" > "$1/.reviews/r.md"
}

# Runs the wrapper with a fully-green baseline unless overridden.
run_wrapper() {
    local tmpdir="$1"; shift
    ( cd "$tmpdir" \
      && PATH="$tmpdir/bin:$PATH" \
         HEAD_SHA="${HEAD_SHA_OVERRIDE:-$HEAD_SHA}" \
         DIFF_FILES="${DIFF_FILES:-README.md}" \
         VALIDATE_CONCLUSION="${VALIDATE_CONCLUSION:-success}" \
         DELETED_TEST_FILES="${DELETED_TEST_FILES:-}" \
         CLEARANCE_COMMENTS="${CLEARANCE_COMMENTS:-}" \
         RENAMED_FROM="${RENAMED_FROM:-}" RENAMED_TO="${RENAMED_TO:-}" \
         CHANGED_FILES_COUNT="${CHANGED_FILES_COUNT:-0}" \
         "$WRAPPER" "$@" ) >/dev/null 2>&1
}

echo "=== cross-model clearance replaces MERGE_CLEARANCE_SKIP ==="
echo

# ---------------------------------------------------------------------------
# Group 1: the old bypass is GONE, not renamed
# ---------------------------------------------------------------------------
echo "[1] MERGE_CLEARANCE_SKIP is removed, not aliased"

if grep -q 'MERGE_CLEARANCE_SKIP' "$WRAPPER"; then
    fail "scripts/merge-pr.sh still references MERGE_CLEARANCE_SKIP"
else
    pass "scripts/merge-pr.sh has no MERGE_CLEARANCE_SKIP"
fi

if grep -q 'MERGE_CLEARANCE_SKIP' "$HOOK"; then
    fail ".claude/hooks/merge-gate-check.sh still references MERGE_CLEARANCE_SKIP"
else
    pass ".claude/hooks/merge-gate-check.sh has no MERGE_CLEARANCE_SKIP"
fi

# Setting the retired variable must have NO effect: a denylist hit still blocks.
t=$(make_stub_env)
write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="CLAUDE_CODE_SDLC_WIZARD.md" MERGE_CLEARANCE_SKIP=1 run_wrapper "$t" 123; then
    fail "retired MERGE_CLEARANCE_SKIP=1 still bypasses a denylist hit"
else
    pass "retired MERGE_CLEARANCE_SKIP=1 has no effect"
fi
rm -rf "$t"

# ---------------------------------------------------------------------------
# Group 2: --cross-model-cleared satisfies the denylist finding
# ---------------------------------------------------------------------------
echo "[2] --cross-model-cleared clears a denylist hit when evidence is valid"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="CLAUDE_CODE_SDLC_WIZARD.md" \
   CLEARANCE_COMMENTS="codex-gpt-5.6-sol|100|$HEAD_SHA
fable-xhigh|96|$HEAD_SHA" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    pass "two distinct reviewers >=95 at the head SHA clears the denylist"
else
    fail "valid dual clearance did not permit the merge"
fi
rm -rf "$t"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="CLAUDE_CODE_SDLC_WIZARD.md" \
   CLEARANCE_COMMENTS="codex-gpt-5.6-sol|100|$HEAD_SHA" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "a SINGLE reviewer was accepted as cross-model clearance"
else
    pass "one reviewer is not enough"
fi
rm -rf "$t"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="CLAUDE_CODE_SDLC_WIZARD.md" \
   CLEARANCE_COMMENTS="codex-gpt-5.6-sol|100|$HEAD_SHA
codex-gpt-5.6-sol|97|$HEAD_SHA" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "the same reviewer twice was accepted as two reviewers"
else
    pass "two comments from the same reviewer are not two reviewers"
fi
rm -rf "$t"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="CLAUDE_CODE_SDLC_WIZARD.md" \
   CLEARANCE_COMMENTS="codex-gpt-5.6-sol|100|$HEAD_SHA
fable-xhigh|94|$HEAD_SHA" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "a reviewer below 95 was accepted"
else
    pass "confidence below 95 blocks"
fi
rm -rf "$t"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="CLAUDE_CODE_SDLC_WIZARD.md" \
   CLEARANCE_COMMENTS="codex-gpt-5.6-sol|100|$OTHER_SHA
fable-xhigh|96|$OTHER_SHA" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "clearance bound to a DIFFERENT sha was accepted (stale after a push)"
else
    pass "clearance for another sha is stale and blocks"
fi
rm -rf "$t"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="CLAUDE_CODE_SDLC_WIZARD.md" CLEARANCE_COMMENTS="" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "the flag alone cleared a denylist hit with NO evidence on the PR"
else
    pass "the flag without posted evidence is inert"
fi
rm -rf "$t"

# ---------------------------------------------------------------------------
# Group 3: the flag clears the denylist and NOTHING ELSE
# This is the whole point of #479. Each check below is independently green in
# the cases above, so a failure here means the flag widened past its scope.
# ---------------------------------------------------------------------------
echo "[3] --cross-model-cleared does not disable any other check"

VALID="codex-gpt-5.6-sol|100|$HEAD_SHA
fable-xhigh|96|$HEAD_SHA"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="CLAUDE_CODE_SDLC_WIZARD.md" CLEARANCE_COMMENTS="$VALID" \
   VALIDATE_CONCLUSION="failure" run_wrapper "$t" 123 --cross-model-cleared; then
    fail "cleared merge proceeded with CI validate FAILING"
else
    pass "CI validate is still enforced under clearance"
fi
rm -rf "$t"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="CLAUDE_CODE_SDLC_WIZARD.md" CLEARANCE_COMMENTS="$VALID" \
   DELETED_TEST_FILES="tests/test-merge-gate.sh" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "cleared merge proceeded while DELETING a test"
else
    pass "test-deletion check is still enforced under clearance"
fi
rm -rf "$t"

t=$(make_stub_env)  # deliberately no local clearance artifact written
if DIFF_FILES="CLAUDE_CODE_SDLC_WIZARD.md" CLEARANCE_COMMENTS="$VALID" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "cleared merge proceeded with NO local clearance artifact"
else
    pass "local clearance artifact is still required under clearance"
fi
rm -rf "$t"

# ---------------------------------------------------------------------------
# Group 4: regressions — behaviour without the flag is unchanged
# ---------------------------------------------------------------------------
echo "[4] Unflagged behaviour is unchanged"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="CLAUDE_CODE_SDLC_WIZARD.md" CLEARANCE_COMMENTS="$VALID" \
   run_wrapper "$t" 123; then
    fail "a denylist hit merged WITHOUT the flag just because evidence existed"
else
    pass "evidence alone does not clear a denylist hit; the flag is explicit"
fi
rm -rf "$t"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="README.md" run_wrapper "$t" 123; then
    pass "a clean PR still merges with no flag and no comments"
else
    fail "a clean PR no longer merges"
fi
rm -rf "$t"

# ---------------------------------------------------------------------------
# Group 5: Codex round-1 findings, replayed as regression tests
#
# All four were reproduced by execution against the first implementation. Each
# is kept here verbatim so the specific defect cannot come back.
# ---------------------------------------------------------------------------
echo "[5] Codex round-1 attacks stay closed"

# F1: `set -- $reviewers` word-split on IFS, so ONE comment naming a reviewer
# with a space in it satisfied the two-distinct-reviewer threshold.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="CLAUDE_CODE_SDLC_WIZARD.md" \
   CLEARANCE_COMMENTS="alice bob|100|$HEAD_SHA" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "F1: one reviewer whose name contains a space counted as two"
else
    pass "F1: a space in a reviewer name cannot fake two reviewers"
fi
rm -rf "$t"

# F3: reviewer/confidence/sha were pulled by three independent `head -1` greps
# over the whole body, so unrelated snippets in prose were spliced into a
# synthetic clearance record. The payload must now be exactly one fenced object.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
cat > "$t/bin/gh" <<STUB
#!/bin/bash
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then echo '{"headRefOid":"$HEAD_SHA","number":123,"state":"OPEN","baseRefName":"main"}'; exit 0
elif [ "\$1" = "pr" ] && [ "\$2" = "diff" ]; then echo "CLAUDE_CODE_SDLC_WIZARD.md"; exit 0
elif [ "\$1" = "api" ]; then
  case "\$*" in
    *git/ref/heads/*) echo '{"object":{"sha":"$HEAD_SHA"}}'; exit 0;;
    *check-runs*) echo '{"conclusion":"success","name":"validate"}';;
    *issues*comments*) printf '[{"user":{"login":"x"},"body":"<!-- CROSS-MODEL-CLEARANCE --> {\\\\"reviewer\\\\":\\\\"codex\\\\"} prose {\\\\"confidence\\\\":100} prose {\\\\"sha\\\\":\\\\"$HEAD_SHA\\\\"}"},{"user":{"login":"x"},"body":"<!-- CROSS-MODEL-CLEARANCE --> {\\\\"reviewer\\\\":\\\\"fable\\\\"} prose {\\\\"confidence\\\\":100} prose {\\\\"sha\\\\":\\\\"$HEAD_SHA\\\\"}"}]\n';;
    *pulls*files*) : ;;
  esac
  exit 0
elif [ "\$1" = "pr" ] && [ "\$2" = "merge" ]; then echo GH_MERGE_INVOKED; exit 0; fi
exit 1
STUB
chmod +x "$t/bin/gh"
if ( cd "$t" && PATH="$t/bin:$PATH" "$WRAPPER" 123 --cross-model-cleared ) >/dev/null 2>&1; then
    fail "F3: fields spliced from unrelated JSON objects were accepted"
else
    pass "F3: loose snippets in prose are not a clearance payload"
fi
rm -rf "$t"

# F4: the confidence regex grabbed leading digits lexically, so the valid JSON
# number 95e-100 (~9.5e-99) read as 95 and passed the >=95 floor.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="CLAUDE_CODE_SDLC_WIZARD.md" \
   CLEARANCE_COMMENTS="codex|95e-100|$HEAD_SHA
fable|95e-100|$HEAD_SHA" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "F4: confidence 95e-100 was read as 95 and accepted"
else
    pass "F4: 95e-100 is not >=95"
fi
rm -rf "$t"

# F4b: a confidence above 100 is not a valid percentage.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="CLAUDE_CODE_SDLC_WIZARD.md" \
   CLEARANCE_COMMENTS="codex|999|$HEAD_SHA
fable|999|$HEAD_SHA" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "F4b: confidence 999 was accepted"
else
    pass "F4b: confidence above 100 is rejected"
fi
rm -rf "$t"

# ---------------------------------------------------------------------------
# Group 6: Fable round-1 findings that survived the first patch
# ---------------------------------------------------------------------------
echo "[6] Fable round-1 attacks stay closed"

# F7: comment authorship was not gated at all — any GitHub user who could
# comment could mint clearance.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if ( cd "$t" && PATH="$t/bin:$PATH" HEAD_SHA="$HEAD_SHA"      DIFF_FILES="CLAUDE_CODE_SDLC_WIZARD.md" VALIDATE_CONCLUSION=success      ASSOC="NONE" AUTHOR="random-drive-by"      CLEARANCE_COMMENTS="codex|100|$HEAD_SHA
fable|100|$HEAD_SHA"      "$WRAPPER" 123 --cross-model-cleared ) >/dev/null 2>&1; then
    fail "F7: a drive-by commenter minted clearance"
else
    pass "F7: non-OWNER/MEMBER/COLLABORATOR comments are ignored"
fi
rm -rf "$t"

# F8: the payload could be wrapped in an HTML comment, rendering as innocuous
# prose in the GitHub UI while still clearing the merge — defeating the only
# thing the audit trail is for. The fixture is generated with exact bytes: an
# earlier hand-escaped heredoc version was VACUOUS (it passed even with the
# protection removed) because the backticks were mangled.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
python3 - "$t/comments.json" "$HEAD_SHA" <<'PY'
import json, sys
path, sha = sys.argv[1], sys.argv[2]
def hidden(rev):
    return ("LGTM, nice work!\n"
            "<!-- **CROSS-MODEL-CLEARANCE**\n"
            "```json\n"
            + json.dumps({"reviewer": rev, "confidence": 100, "sha": sha})
            + "\n```\n-->")
json.dump([{"user": {"login": "m"}, "author_association": "OWNER", "body": hidden("codex")},
           {"user": {"login": "m"}, "author_association": "OWNER", "body": hidden("fable")}],
          open(path, "w"))
PY
cat > "$t/bin/gh" <<STUB
#!/bin/bash
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then echo '{"headRefOid":"$HEAD_SHA","number":123,"state":"OPEN","baseRefName":"main"}'; exit 0
elif [ "\$1" = "pr" ] && [ "\$2" = "diff" ]; then echo "CLAUDE_CODE_SDLC_WIZARD.md"; exit 0
elif [ "\$1" = "api" ]; then
  case "\$*" in
    *git/ref/heads/*) echo '{"object":{"sha":"$HEAD_SHA"}}'; exit 0;;
    *check-runs*) echo '{"conclusion":"success","name":"validate"}';;
    *issues*comments*) cat "$t/comments.json";;
    *pulls*files*) : ;;
  esac
  exit 0
elif [ "\$1" = "pr" ] && [ "\$2" = "merge" ]; then echo GH_MERGE_INVOKED; exit 0; fi
exit 1
STUB
chmod +x "$t/bin/gh"
if ( cd "$t" && PATH="$t/bin:$PATH" "$WRAPPER" 123 --cross-model-cleared ) >/dev/null 2>&1; then
    fail "F8: clearance hidden inside an HTML comment was accepted"
else
    pass "F8: a payload invisible in the rendered UI is not evidence"
fi
rm -rf "$t"

# F9: honest payloads were dropped silently. jq renders an integer-valued float
# as 100.0, and a differently-cased SHA is the same commit.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="CLAUDE_CODE_SDLC_WIZARD.md"    CLEARANCE_COMMENTS="codex|100.0|$HEAD_SHA
fable|96|$(printf '%s' "$HEAD_SHA" | tr 'a-f' 'A-F')"    run_wrapper "$t" 123 --cross-model-cleared; then
    pass "F9: 100.0 and an upper-case SHA are accepted as valid"
else
    fail "F9: honest payloads still silently rejected"
fi
rm -rf "$t"

# ---------------------------------------------------------------------------
# Group 7: HARD vs ACKABLE tiers
#
# Codex (96%) and Fable (85%) independently reached the same conclusion: the
# agent must not be able to self-clear the merge-EVIDENCE CHAIN. On those paths
# every leg of the evidence stack becomes the agent's own say-so at once —
# `validate` is defined by the PR (branch protection requires the check by NAME,
# so any new workflow file can mint one), the gate that runs is the PR's own
# gate, and both clearance comments are posted by the same token. Errors in the
# control plane compound; errors in the data plane do not.
# ---------------------------------------------------------------------------
echo "[7] HARD tier is not agent-clearable; ACKABLE tier is"

VALID_2="codex-gpt-5.6-sol|100|$HEAD_SHA
fable-xhigh|96|$HEAD_SHA"

for hard in "scripts/merge-pr.sh" ".claude/hooks/merge-gate-check.sh" \
            ".github/workflows/ci.yml" ".github/workflows/brand-new.yml" \
            "hooks/codex-gate-check.sh"; do
    t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
    if DIFF_FILES="$hard" CLEARANCE_COMMENTS="$VALID_2" \
       run_wrapper "$t" 123 --cross-model-cleared; then
        fail "HARD tier '$hard' was self-cleared by the agent"
    else
        pass "HARD tier '$hard' still requires a human"
    fi
    rm -rf "$t"
done

for ackable in "skills/sdlc/SKILL.md" "cowork/skills/sdlc/SKILL.md" \
               "CLAUDE_CODE_SDLC_WIZARD.md" "cowork/hooks/hooks.json"; do
    t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
    if DIFF_FILES="$ackable" CLEARANCE_COMMENTS="$VALID_2" CHANGED_FILES_COUNT=1 \
       run_wrapper "$t" 123 --cross-model-cleared; then
        pass "ACKABLE tier '$ackable' is agent-clearable on valid evidence"
    else
        fail "ACKABLE tier '$ackable' should be clearable, but blocked"
    fi
    rm -rf "$t"
done

# HARD wins when a PR touches both tiers.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="CLAUDE_CODE_SDLC_WIZARD.md
hooks/codex-gate-check.sh" CLEARANCE_COMMENTS="$VALID_2" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "a PR touching both tiers was cleared; HARD must win"
else
    pass "HARD wins when a PR touches both tiers"
fi
rm -rf "$t"

# Both models measured CHANGELOG.md as dead weight: it only ever co-fires with
# the package.json version check, which is unconditional and separate.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="CHANGELOG.md" run_wrapper "$t" 123; then
    pass "CHANGELOG.md is no longer denylisted (needs no flag at all)"
else
    fail "CHANGELOG.md still blocks; both reviewers measured it as dead weight"
fi
rm -rf "$t"

# ---------------------------------------------------------------------------
# Group 8: Codex round-2 findings on the tiering itself
# ---------------------------------------------------------------------------
echo "[8] Tier classification is complete and encoding-proof"

# F1: `gh pr diff --name-only` emits DISPLAY text with core.quotePath escaping,
# so a quoted path did not match any column-anchored HARD pattern and merged as
# "denylist clear". Classification now reads the JSON files API instead.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
# The two surfaces DISAGREE on purpose: `gh pr diff` returns git-quoted display
# text (leading quote + octal escapes, exactly what cli/cli emits), while the
# files API returns the decoded pathname. A classifier reading the diff sees a
# string starting with '"' and matches no column-anchored pattern.
cat > "$t/bin/gh" <<STUB
#!/bin/bash
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
  case "\$*" in *changedFiles*) echo 1; exit 0;; esac
  echo '{"headRefOid":"$HEAD_SHA","number":123,"state":"OPEN","baseRefName":"main"}'; exit 0
elif [ "\$1" = "pr" ] && [ "\$2" = "diff" ]; then
  printf '"%s"\n' '.github/workflows/validate-\360\237\230\200.yml'; exit 0
elif [ "\$1" = "api" ]; then
  case "\$*" in
    *git/ref/heads/*) echo '{"object":{"sha":"$HEAD_SHA"}}'; exit 0;;
    *check-runs*) echo '{"conclusion":"success","name":"validate"}';;
    *issues*comments*) printf '[]\n';;
    *pulls*files*) printf '[{"filename":".github/workflows/validate-\\ud83d\\ude00.yml","status":"added"}]\n';;
  esac
  exit 0
elif [ "\$1" = "pr" ] && [ "\$2" = "merge" ]; then echo GH_MERGE_INVOKED; exit 0; fi
exit 1
STUB
chmod +x "$t/bin/gh"
if ( cd "$t" && PATH="$t/bin:$PATH" "$WRAPPER" 123 --cross-model-cleared ) >/dev/null 2>&1; then
    fail "F1: a quoted HARD workflow path escaped the tier"
else
    pass "F1: HARD paths classified from the decoded files API, not diff text"
fi
rm -rf "$t"

# F2: a PR diff is capped at 300 files. Classifying a truncated set silently
# judged a subset; it must fail closed instead.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="README.md" CHANGED_FILES_COUNT=301 \
   run_wrapper "$t" 123; then
    fail "F2: classified a truncated file set (1 of 301) instead of failing closed"
else
    pass "F2: a truncated file set fails closed"
fi
rm -rf "$t"

# F3a: the ACKABLE tests were mutation-vacuous — they only asserted that a
# CLEARED merge succeeds, which also succeeds when the path is not classified at
# all. Each ACKABLE path must therefore also BLOCK when unflagged.
for ackable in "skills/sdlc/SKILL.md" "cowork/skills/sdlc/SKILL.md" \
               "CLAUDE_CODE_SDLC_WIZARD.md"; do
    t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
    if DIFF_FILES="$ackable" CHANGED_FILES_COUNT=1 run_wrapper "$t" 123; then
        fail "F3a: ACKABLE '$ackable' merged with NO flag — it is not classified"
    else
        pass "F3a: ACKABLE '$ackable' blocks when unflagged"
    fi
    rm -rf "$t"
done

# F3b: renaming a HARD file to a safe path must keep its tier. Without
# previous_filename classification this changed from blocked to merged.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="docs/merge-pr.sh" RENAMED_FROM="scripts/merge-pr.sh" \
   RENAMED_TO="docs/merge-pr.sh" CHANGED_FILES_COUNT=2 \
   CLEARANCE_COMMENTS="codex|100|$HEAD_SHA
fable|96|$HEAD_SHA" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "F3b: renaming a HARD file out of its directory escaped the tier"
else
    pass "F3b: a renamed HARD file keeps its tier"
fi
rm -rf "$t"

# ---------------------------------------------------------------------------
# Group 9: Fable round-2 findings on the tiering
# ---------------------------------------------------------------------------
echo "[9] Tier matching is case-insensitive; hidden payloads stay rejected"

# F1: patterns were matched case-SENSITIVELY, so 'Hooks/codex-gate-check.sh'
# matched nothing and merged clean — no flag, no evidence, no human. And on a
# case-insensitive filesystem (this maintainer's) that path lands ON TOP of the
# real hook, so evading the tier and gutting the gate are the same commit.
for variant in "Hooks/codex-gate-check.sh" "Scripts/merge-pr.sh" \
               ".Claude/settings.json" ".GitHub/workflows/ci.yml"; do
    t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
    if DIFF_FILES="$variant" CHANGED_FILES_COUNT=1 run_wrapper "$t" 123; then
        fail "F1: '$variant' merged clean — case variant escaped the HARD tier"
    else
        pass "F1: '$variant' is still HARD"
    fi
    rm -rf "$t"
done

# F2: only TERMINATED html comments were stripped, so an unbalanced '<!--' kept
# the payload in the scanned text while GitHub renders nothing after it.
# Verified by Fable against GitHub's own markdown API.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
python3 - "$t/comments.json" "$HEAD_SHA" <<'PY'
import json, sys
path, sha = sys.argv[1], sys.argv[2]
def unterminated(rev):
    return ("LGTM, nice work!\n<!--\n**CROSS-MODEL-CLEARANCE**\n```json\n"
            + json.dumps({"reviewer": rev, "confidence": 100, "sha": sha}) + "\n```")
json.dump([{"user": {"login": "m"}, "author_association": "OWNER", "body": unterminated("codex")},
           {"user": {"login": "m"}, "author_association": "OWNER", "body": unterminated("fable")}],
          open(path, "w"))
PY
cat > "$t/bin/gh" <<STUB
#!/bin/bash
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
  case "\$*" in *changedFiles*) echo 1; exit 0;; esac
  echo '{"headRefOid":"$HEAD_SHA","number":123,"state":"OPEN","baseRefName":"main"}'; exit 0
elif [ "\$1" = "pr" ] && [ "\$2" = "diff" ]; then echo "CLAUDE_CODE_SDLC_WIZARD.md"; exit 0
elif [ "\$1" = "api" ]; then
  case "\$*" in
    *git/ref/heads/*) echo '{"object":{"sha":"$HEAD_SHA"}}'; exit 0;;
    *check-runs*) echo '{"conclusion":"success","name":"validate"}';;
    *issues*comments*) cat "$t/comments.json";;
    *pulls*files*) echo '[{"filename":"CLAUDE_CODE_SDLC_WIZARD.md","status":"modified"}]';;
  esac
  exit 0
elif [ "\$1" = "pr" ] && [ "\$2" = "merge" ]; then echo GH_MERGE_INVOKED; exit 0; fi
exit 1
STUB
chmod +x "$t/bin/gh"
if ( cd "$t" && PATH="$t/bin:$PATH" "$WRAPPER" 123 --cross-model-cleared ) >/dev/null 2>&1; then
    fail "F2: an unterminated HTML comment hid the payload and still cleared"
else
    pass "F2: an unbalanced '<!--' is rejected"
fi
rm -rf "$t"

# F6: cowork/hooks/ ships to every Cowork plugin user but sat in NO tier, so it
# merged with no evidence at all.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="cowork/hooks/hooks.json" CHANGED_FILES_COUNT=1 run_wrapper "$t" 123; then
    fail "F6: cowork/hooks/ merged with no evidence — it is in no tier"
else
    pass "F6: cowork/hooks/ requires clearance"
fi
rm -rf "$t"

# Codex round-3 P1: `|| echo ""` turned a FAILED changedFiles query into "skip
# the completeness check" — the exact condition it exists to catch.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
cat > "$t/bin/gh" <<STUB
#!/bin/bash
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
  case "\$*" in *changedFiles*) exit 1;; esac        # the query FAILS
  echo '{"headRefOid":"$HEAD_SHA","number":123,"state":"OPEN","baseRefName":"main"}'; exit 0
elif [ "\$1" = "pr" ] && [ "\$2" = "diff" ]; then echo "README.md"; exit 0
elif [ "\$1" = "api" ]; then
  case "\$*" in
    *git/ref/heads/*) echo '{"object":{"sha":"$HEAD_SHA"}}'; exit 0;;
    *check-runs*) echo '{"conclusion":"success","name":"validate"}';;
    *issues*comments*) printf '[]\n';;
    *pulls*files*) printf '[{"filename":"README.md","status":"modified"}]\n';;
  esac
  exit 0
elif [ "\$1" = "pr" ] && [ "\$2" = "merge" ]; then echo GH_MERGE_INVOKED; exit 0; fi
exit 1
STUB
chmod +x "$t/bin/gh"
if ( cd "$t" && PATH="$t/bin:$PATH" "$WRAPPER" 123 ) >/dev/null 2>&1; then
    fail "a failed changedFiles query merged anyway — completeness silently skipped"
else
    pass "a failed changedFiles query fails closed"
fi
rm -rf "$t"

# Fable round-3 N1: the package.json version check read $DIFF_FILES — the
# display-text, 300-file-capped source classification was moved OFF in round 2.
# A version bump the diff did not list merged as "denylist clear", while the
# file header called that check unconditional in both tiers.
#
# The fixture is generated with EXACT BYTES. A hand-escaped heredoc version was
# vacuous: the mangled JSON made jq fail, so the wrapper blocked on "could not
# determine any changed path" with AND without the fix.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
python3 - "$t/files.json" <<'PY'
import json, sys
json.dump([{"filename": "package.json", "status": "modified",
            "patch": '@@ -1,3 +1,3 @@\n {\n-  "version": "1.87.0",\n+  "version": "1.88.0",'}],
          open(sys.argv[1], "w"))
PY
cat > "$t/bin/gh" <<STUB
#!/bin/bash
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
  case "\$*" in *changedFiles*) echo 1; exit 0;; esac
  echo '{"headRefOid":"$HEAD_SHA","number":123,"state":"OPEN","baseRefName":"main"}'; exit 0
elif [ "\$1" = "pr" ] && [ "\$2" = "diff" ]; then echo "README.md"; exit 0
elif [ "\$1" = "api" ]; then
  case "\$*" in
    *git/ref/heads/*) echo '{"object":{"sha":"$HEAD_SHA"}}'; exit 0;;
    *check-runs*) echo '{"conclusion":"success","name":"validate"}';;
    *issues*comments*) printf '[]\n';;
    *pulls*files*) cat "$t/files.json";;
  esac
  exit 0
elif [ "\$1" = "pr" ] && [ "\$2" = "merge" ]; then echo GH_MERGE_INVOKED; exit 0; fi
exit 1
STUB
chmod +x "$t/bin/gh"
if ( cd "$t" && PATH="$t/bin:$PATH" "$WRAPPER" 123 ) >/dev/null 2>&1; then
    fail "N1: a version bump absent from the diff text merged as denylist-clear"
else
    pass "N1: the version check reads the complete classified path set"
fi
rm -rf "$t"

# ---------------------------------------------------------------------------
# Group 10: Fable round-3 N4/N5 — positive visibility shape
# ---------------------------------------------------------------------------
echo "[10] Payload must be visibly rendered; honest comments are not punished"

mk_comments() {  # $1=tmpdir  $2=python expression building each body from `rev`
    python3 - "$1/comments.json" "$HEAD_SHA" "$2" <<'PY'
import json, sys
path, sha, tmpl = sys.argv[1], sys.argv[2], sys.argv[3]
def body(rev):
    # `verdict` is required as of GH #478 — see the CLEARANCE_COMMENTS builder
    # above. These N4/N5 fixtures test VISIBILITY, so they carry a valid YES;
    # verdict enforcement itself is tested in tests/test-merge-gate.sh.
    payload = json.dumps({"reviewer": rev, "verdict": "YES", "confidence": 100, "sha": sha})
    return eval(tmpl, {"rev": rev, "payload": payload})
json.dump([{"user": {"login": "m"}, "author_association": "OWNER", "body": body("codex")},
           {"user": {"login": "m"}, "author_association": "OWNER", "body": body("fable")}],
          open(path, "w"))
PY
    cat > "$1/bin/gh" <<STUB
#!/bin/bash
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
  case "\$*" in *changedFiles*) echo 1; exit 0;; esac
  echo '{"headRefOid":"$HEAD_SHA","number":123,"state":"OPEN","baseRefName":"main"}'; exit 0
elif [ "\$1" = "pr" ] && [ "\$2" = "diff" ]; then echo "CLAUDE_CODE_SDLC_WIZARD.md"; exit 0
elif [ "\$1" = "api" ]; then
  case "\$*" in
    *git/ref/heads/*) echo '{"object":{"sha":"$HEAD_SHA"}}'; exit 0;;
    *check-runs*) echo '{"conclusion":"success","name":"validate"}';;
    *issues*comments*) cat "$1/comments.json";;
    *pulls*files*) echo '[{"filename":"CLAUDE_CODE_SDLC_WIZARD.md","status":"modified"}]';;
  esac
  exit 0
elif [ "\$1" = "pr" ] && [ "\$2" = "merge" ]; then echo GH_MERGE_INVOKED; exit 0; fi
exit 1
STUB
    chmod +x "$1/bin/gh"
}

# N4a: <details><summary> collapses the payload — reader sees a triangle.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
mk_comments "$t" '"LGTM, nice work!\n<details><summary>build log</summary>\n\n**CROSS-MODEL-CLEARANCE**\n```json\n" + payload + "\n```\n</details>"'
if ( cd "$t" && PATH="$t/bin:$PATH" "$WRAPPER" 123 --cross-model-cleared ) >/dev/null 2>&1; then
    fail "N4a: a payload collapsed inside <details> cleared the merge"
else
    pass "N4a: <details>-hidden payload is rejected"
fi
rm -rf "$t"

# N4b: "[//]: # (...)" is a link-reference definition — renders as nothing.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
mk_comments "$t" '"ship it\n[//]: # (**CROSS-MODEL-CLEARANCE**)\n\n**CROSS-MODEL-CLEARANCE**\n```json\n" + payload + "\n```"'
if ( cd "$t" && PATH="$t/bin:$PATH" "$WRAPPER" 123 --cross-model-cleared ) >/dev/null 2>&1; then
    fail "N4b: a link-reference definition was accepted as visible evidence"
else
    pass "N4b: link-reference definitions disqualify a comment"
fi
rm -rf "$t"

# N5: an HONEST reviewer discussing markup must NOT be punished. This repo's
# reviewers quote `<!--` and <details> constantly.
t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
mk_comments "$t" '"I reproduced the literal `<!--` token and the `<details>` case.\n\n**CROSS-MODEL-CLEARANCE**\n```json\n" + payload + "\n```"'
if ( cd "$t" && PATH="$t/bin:$PATH" "$WRAPPER" 123 --cross-model-cleared ) >/dev/null 2>&1; then
    pass "N5: an honest comment quoting markup in code still clears"
else
    fail "N5: an honest comment quoting markup was rejected"
fi
rm -rf "$t"

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
