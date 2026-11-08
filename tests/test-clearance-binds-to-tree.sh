#!/bin/bash
# A certification must authorize exactly the CONTENT it was issued over (#540).
#
# THE HOLE
#
# The CERTIFIED lane keys staleness on `commit_sha == HEAD`. PreToolUse runs
# BEFORE the commit, so at check time HEAD is still the certified commit and
# the gate allows — then the commit lands with content nobody reviewed. The
# resulting commit is by construction not the one that was reviewed. Sol found
# it at file:line during the enforcement-locus reconciliation; Fable withdrew
# its own recommendation to extend the gate once shown the counter-example.
#
# WHY TREE IDENTITY AND NOT patch-id
#
# An earlier ruling (2026-08-10) chose `git patch-id --stable`. Both advisors
# amended it on 2026-08-11 after two measurements:
#
#   1. Two diffs differing ONLY in the indentation of an added Python line
#      produce the IDENTICAL patch-id — it ignores whitespace by design, and
#      whitespace is semantic in Python, YAML, Makefiles and string literals.
#      A certification bound by patch-id survives a behavior change.
#   2. At the merge boundary the thing merged is the resulting TREE, not the
#      diff. A rebase onto moved upstream keeps patch-id identical while
#      producing final content nobody reviewed.
#
# So the goal was amended, not just the primitive: certification must NOT
# automatically survive a rebase onto a changed base.
#
# WHAT THIS DELIBERATELY KEEPS CHEAP
#
# The old SHA key taxed EVERY commit with a re-pin call — measured at ~10
# wasted tool calls in one PR cycle — and protected nothing a content pin does
# not. Message-only amend, squash, and reorder with no upstream movement all
# produce the same tree, so certification survives them at zero cost. Only a
# change in content invalidates. Rows below pin both directions, because a
# guard that only ever refuses is indistinguishable from a broken one.
#
# WHY THE HOOK DOES NOT PARSE COMMIT FLAGS
#
# `git commit <pathspec>` can commit a tree other than the index's. The fix is
# NOT to inspect flags: modelling git's option grammar in a regex is the #610
# trap, where rounds 1-3 scored 3, 6, 4 — falling — doing exactly that, and
# round 4 deleted all of it. Instead the frozen-index precondition dissolves
# the common case (with no unstaged tracked changes, `git commit` and
# `git commit -a` commit the same tree as the index), and the pathspec case is
# caught at the merge boundary in scripts/merge-pr.sh. Pinned as an ACCEPTED
# LIMIT row, not left implicit.

set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$REPO_ROOT/hooks/codex-gate-check.sh"
PASSED=0
FAILED=0

# Hoisted above every definition: a guard placed after the thing it guards is
# skipped by any early exit landing between them (#598 round 20).
if [ -z "${TREE_SUITE_FORCE_FAILURE:-}" ]; then
    if TREE_SUITE_FORCE_FAILURE=1 "$0" > /dev/null 2>&1; then
        echo "FATAL: a forced failure still exited 0 — this suite cannot report a regression to CI" >&2
        exit 1
    fi
fi

pass() { PASSED=$((PASSED + 1)); printf '\033[0;32mPASS\033[0m: %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf '\033[0;31mFAIL\033[0m: %s\n' "$1"; }

# FAIL CLOSED on a tmpdir we could not create. A fixture that falls back to
# the caller's cwd runs `git commit` in the REAL repo — that happened, and it
# corrupted the working tree (#566).
WORK=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-tree-bind.XXXXXX") || {
    echo "FATAL: could not create a temp dir; refusing to run in $(pwd)" >&2
    exit 1
}
case "$WORK" in
    /*) ;;
    *) echo "FATAL: temp dir '$WORK' is not absolute; refusing to run" >&2; exit 1 ;;
esac
trap 'rm -rf "$WORK"' EXIT

# Run the hook against one Bash command, exactly as Claude Code invokes it.
# Exit 2 is a refusal, 0 an allow. Runs with cwd inside the fixture repo,
# because the hook reads .reviews/handoff.json relative to cwd.
run_hook_in() {
    local dir="$1" cmd="$2"
    ( cd "$dir" && python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$cmd" \
        | "$HOOK" > /dev/null 2>&1; echo $? )
}

expect_refused() {
    local desc="$1" dir="$2" cmd="$3" rc
    rc=$(run_hook_in "$dir" "$cmd")
    if [ "$rc" = "2" ]; then pass "refused: $desc"; else fail "should have REFUSED (got exit $rc): $desc"; fi
}

expect_allowed() {
    local desc="$1" dir="$2" cmd="$3" rc
    rc=$(run_hook_in "$dir" "$cmd")
    if [ "$rc" = "0" ]; then pass "allowed: $desc"; else fail "should have ALLOWED (got exit $rc): $desc"; fi
}

# Build a repo with one baseline commit. Returns nothing; sets REPO.
new_repo() {
    REPO="$WORK/$1"
    mkdir -p "$REPO/.reviews"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email t@example.com
    git -C "$REPO" config user.name "SDLC Test"
    printf 'baseline\n' > "$REPO/file.txt"
    git -C "$REPO" add file.txt
    git -C "$REPO" commit -qm baseline
}

# Write a CERTIFIED handoff. Args: repo, commit_sha, candidate_tree, base_tree.
# An empty tree arg omits the field entirely, which is how the pre-#540 format
# is simulated — the fail-closed rows depend on that distinction.
write_handoff() {
    local repo="$1" sha="$2" cand="$3" base="$4"
    {
        printf '{\n  "status": "CERTIFIED",\n  "branch": "main",\n'
        printf '  "commit_sha": "%s"' "$sha"
        [ -n "$cand" ] && printf ',\n  "candidate_tree": "%s"' "$cand"
        [ -n "$base" ] && printf ',\n  "base_tree": "%s"' "$base"
        printf '\n}\n'
    } > "$repo/.reviews/handoff.json"
}

# ---------------------------------------------------------------------------
# 1. THE HOLE ITSELF. Certify, then stage content the certification never saw.
#    Pre-#540 this ALLOWS, because HEAD has not moved yet — that is the bug.
# ---------------------------------------------------------------------------
new_repo hole
HEAD_SHA=$(git -C "$REPO" rev-parse HEAD)
CERT_TREE=$(git -C "$REPO" rev-parse 'HEAD^{tree}')
write_handoff "$REPO" "$HEAD_SHA" "$CERT_TREE" "$CERT_TREE"
printf 'content nobody reviewed\n' > "$REPO/file.txt"
git -C "$REPO" add file.txt
expect_refused "staged content differs from the certified candidate_tree" "$REPO" "git commit -m x"

# ---------------------------------------------------------------------------
# 2. THE PRESERVED CASE. Index matches the certified tree exactly, so the
#    commit about to be made is the reviewed content. Must ALLOW — this is the
#    re-pin tax the ruling exists to delete, and a guard that refuses here has
#    reintroduced it.
# ---------------------------------------------------------------------------
new_repo preserved
printf 'reviewed change\n' > "$REPO/file.txt"
git -C "$REPO" add file.txt
CAND=$(git -C "$REPO" write-tree)
BASE=$(git -C "$REPO" rev-parse 'HEAD^{tree}')
write_handoff "$REPO" "$(git -C "$REPO" rev-parse HEAD)" "$CAND" "$BASE"
expect_allowed "index tree equals the certified candidate_tree" "$REPO" "git commit -m x"

# ---------------------------------------------------------------------------
# 3. THE PATCH-ID KILLER, as a regression test. Two candidates differing ONLY
#    in the indentation of an added line have the same patch-id and different
#    behavior. Tree identity must tell them apart.
# ---------------------------------------------------------------------------
new_repo whitespace
printf 'def f(x):\n    if x:\n        return 1\n' > "$REPO/f.py"
git -C "$REPO" add f.py
CAND=$(git -C "$REPO" write-tree)
write_handoff "$REPO" "$(git -C "$REPO" rev-parse HEAD)" "$CAND" "$(git -C "$REPO" rev-parse 'HEAD^{tree}')"
# Same diff to patch-id; different program.
printf 'def f(x):\n    if x:\n    return 1\n' > "$REPO/f.py"
git -C "$REPO" add f.py
expect_refused "whitespace-only divergence invalidates (patch-id cannot see this)" "$REPO" "git commit -m x"

# ---------------------------------------------------------------------------
# 4. FROZEN INDEX. Unstaged tracked changes mean the tree that gets committed
#    is not determinable from the index — `git commit -a` would sweep them in.
#    This is what makes flag-parsing unnecessary, so it must actually refuse.
# ---------------------------------------------------------------------------
new_repo dirty
printf 'staged\n' > "$REPO/file.txt"
git -C "$REPO" add file.txt
CAND=$(git -C "$REPO" write-tree)
write_handoff "$REPO" "$(git -C "$REPO" rev-parse HEAD)" "$CAND" "$(git -C "$REPO" rev-parse 'HEAD^{tree}')"
printf 'unstaged on top\n' > "$REPO/file.txt"
expect_refused "tracked worktree diverges from the index" "$REPO" "git commit -m x"

# ---------------------------------------------------------------------------
# 5. FAIL CLOSED on the pre-#540 artifact format. A handoff with commit_sha and
#    no candidate_tree must NOT pass on the old key alone — the same posture
#    #437 took for a missing commit_sha, and #533 for a missing branch. No
#    legacy-compat fallback.
# ---------------------------------------------------------------------------
new_repo legacy
write_handoff "$REPO" "$(git -C "$REPO" rev-parse HEAD)" "" ""
expect_refused "CERTIFIED handoff declaring no candidate_tree" "$REPO" "git commit -m x"

# ---------------------------------------------------------------------------
# 6. BASE MOVED — and this row is deliberately ALLOWED at the commit boundary.
#
#    base_tree exists for the rebase-onto-moved-upstream case: identical diff,
#    different result, the second measurement that killed patch-id. But it is
#    enforced at the MERGE boundary, not here, for a reason worth writing down.
#
#    At the commit boundary "the base" is not observable without knowing what
#    kind of commit is being made. For a normal commit the base is HEAD; for an
#    amend it is HEAD^. Telling those apart means reading `--amend` off the
#    command line — git option grammar in a regex, the #610 trap. And the
#    ruling deliberately preserves message-only amend as a zero-cost case, so a
#    naive `base_tree == HEAD^{tree}` check would refuse exactly the case the
#    whole change exists to keep cheap.
#
#    It costs nothing to defer, because candidate_tree already covers content:
#    if upstream moved and the branch was rebased, the index tree CHANGES, so
#    row 1's check refuses it. What base_tree adds is integration-time
#    knowledge — which base the reviewer actually read — and the merge boundary
#    is where that is both well-defined and enforceable.
#
#    Covered at that boundary by tests/test-merge-gate.sh —
#    test_wrapper_blocks_moved_base.
# ---------------------------------------------------------------------------
new_repo rebased
printf 'candidate\n' > "$REPO/file.txt"
git -C "$REPO" add file.txt
CAND=$(git -C "$REPO" write-tree)
write_handoff "$REPO" "$(git -C "$REPO" rev-parse HEAD)" "$CAND" "0000000000000000000000000000000000000000"
expect_allowed "base_tree is a merge-boundary field; content is already pinned by candidate_tree" "$REPO" "git commit -m x"

# ---------------------------------------------------------------------------
# 7. ACCEPTED LIMIT, pinned so it is a decision and not an oversight.
#    A pathspec commit can still write a tree other than the index's. The hook
#    does not parse flags (the #610 trap), so with a frozen index matching the
#    certification this ALLOWS even though the resulting tree may differ. The
#    backstop is the merge boundary in scripts/merge-pr.sh, which compares the
#    REMOTE head tree. If this row ever starts refusing, someone added flag
#    parsing — read #610 rounds 1-3 before keeping it.
# ---------------------------------------------------------------------------
new_repo pathspec
printf 'a\n' > "$REPO/a.txt"; printf 'b\n' > "$REPO/b.txt"
git -C "$REPO" add a.txt b.txt
CAND=$(git -C "$REPO" write-tree)
write_handoff "$REPO" "$(git -C "$REPO" rev-parse HEAD)" "$CAND" "$(git -C "$REPO" rev-parse 'HEAD^{tree}')"
expect_allowed "ACCEPTED LIMIT: pathspec commit passes the index check (merge boundary is the backstop)" "$REPO" "git commit -m x -- a.txt"

# ---------------------------------------------------------------------------
# 8. The gate still only fires on a git commit. A non-commit command with a
#    stale certification must not be dragged in by the new check.
# ---------------------------------------------------------------------------
new_repo unrelated
write_handoff "$REPO" "deadbeef" "" ""
expect_allowed "unrelated command with a stale certification" "$REPO" "ls -la"

# ---------------------------------------------------------------------------
# 9. THE GATE JUDGES THE REPOSITORY THE COMMIT TARGETS, not the hook's cwd.
#    The hook runs in the session's primary checkout. A commit issued as
#    `git -C <worktree> commit` or `cd <worktree> && git commit` lands in the
#    worktree, so the worktree's own handoff and index are what must agree.
#    Reading the primary checkout's refused certified worktree commits, and
#    worse, let an uncertified worktree commit through whenever the primary
#    happened to be certified.
# ---------------------------------------------------------------------------
new_repo primary
PRIMARY="$REPO"
WT="$WORK/wt"
git -C "$PRIMARY" worktree add -q "$WT" -b wt-branch
mkdir -p "$WT/.reviews" "$WT/sub"
printf 'worktree change\n' > "$WT/file.txt"
git -C "$WT" add file.txt
WT_TREE=$(git -C "$WT" write-tree)
PRIMARY_TREE=$(git -C "$PRIMARY" write-tree)

# Primary certifies some OTHER tree: the live-case shape, where the primary's
# handoff is about different work entirely.
write_handoff "$PRIMARY" "$(git -C "$PRIMARY" rev-parse HEAD)" "$WT_TREE" ""
write_handoff "$WT" "$(git -C "$WT" rev-parse HEAD)" "$WT_TREE" ""
# The primary's index is NOT the certified tree, so a gate reading it refuses.
sed -i.bak "s/$WT_TREE/0000000000000000000000000000000000000000/" "$PRIMARY/.reviews/handoff.json"
expect_allowed "git -C <worktree> commit, worktree certifies its own index" "$PRIMARY" "git -C $WT commit -m x"
expect_allowed "cd <worktree> && git commit, worktree certifies its own index" "$PRIMARY" "cd $WT && git commit -m x"
expect_allowed "cd <worktree>; git commit (semicolon form)" "$PRIMARY" "cd $WT; git commit -m x"
expect_allowed "git -C '<worktree>' commit (single-quoted literal path)" "$PRIMARY" "git -C '$WT' commit -m x"
expect_allowed "git -C \"<worktree>\" commit (double-quoted literal path)" "$PRIMARY" "git -C \"$WT\" commit -m x"
expect_allowed "git -C <worktree>/sub commit resolves to the worktree's toplevel" "$PRIMARY" "git -C $WT/sub commit -m x"
expect_allowed "cd <parent> && git -C <relative> commit chains like the shell does" "$PRIMARY" "cd $WORK && git -C wt commit -m x"
expect_allowed "git commit -C <commit> is commit's own option, not a relocation" "$WT" "git commit -C HEAD"

# Now the primary IS certified for its own index, and the worktree is not.
write_handoff "$PRIMARY" "$(git -C "$PRIMARY" rev-parse HEAD)" "$PRIMARY_TREE" ""
rm -f "$WT/.reviews/handoff.json"
expect_refused "git -C <worktree> commit with no worktree handoff, primary certified" "$PRIMARY" "git -C $WT commit -m x"
expect_refused "cd <worktree> && git commit with no worktree handoff, primary certified" "$PRIMARY" "cd $WT && git commit -m x"
write_handoff "$WT" "$(git -C "$WT" rev-parse HEAD)" "$PRIMARY_TREE" ""
expect_refused "git -C <worktree> commit when the worktree certifies a different tree" "$PRIMARY" "git -C $WT commit -m x"
expect_refused "cd <worktree> && git commit when the worktree certifies a different tree" "$PRIMARY" "cd $WT && git commit -m x"

# Unresolvable targets FAIL CLOSED, whatever the primary says.
expect_refused "git -C <nonexistent> commit" "$PRIMARY" "git -C $WORK/no-such-dir commit -m x"
expect_refused "git -C <dir that is not a repo> commit" "$PRIMARY" "git -C $WORK commit -m x"
expect_refused "cd <nonexistent> && git commit" "$PRIMARY" "cd $WORK/no-such-dir && git commit -m x"
expect_refused "git -C \$VAR commit (unexpanded variable)" "$PRIMARY" "git -C \$WT commit -m x"
expect_refused "git -C \"\$VAR\" commit (quoted variable)" "$PRIMARY" "git -C \"\$WT\" commit -m x"
expect_refused "git -C <worktree>/.git commit (not a work tree)" "$PRIMARY" "git -C $PRIMARY/.git commit -m x"
expect_refused "subshell relocation the gate cannot follow" "$PRIMARY" "(cd $WT && git commit -m x)"
expect_refused "a second commit after a relocated one" "$PRIMARY" "git -C $PRIMARY commit -m x && git -C $WT commit -m y"
expect_refused "a cd after the commit in the same command" "$PRIMARY" "git -C $PRIMARY commit -m x && cd $WT && git commit -m y"
expect_refused "--work-tree= relocation in the CERTIFIED lane" "$PRIMARY" "git --work-tree=$WT commit -m x"

# The local-test-result shortcut binds to the TARGET too: a PASS for the
# primary's tree must not authorize a worktree commit of different content.
printf '%s PASS\n' "$PRIMARY_TREE" > "$PRIMARY/.local-test-result"
expect_refused "primary's local PASS does not authorize a worktree commit" "$PRIMARY" "git -C $WT commit -m x"
rm -f "$PRIMARY/.local-test-result"
# A RELATIVE override is read at the target too, never at the hook's cwd.
printf '%s PASS\n' "$WT_TREE" > "$PRIMARY/.local-test-result"
export SDLC_LOCAL_TEST_RESULT=.local-test-result
expect_refused "relative SDLC_LOCAL_TEST_RESULT is read at the target, not the hook cwd" "$PRIMARY" "git -C $WT commit -m x"
unset SDLC_LOCAL_TEST_RESULT
rm -f "$PRIMARY/.local-test-result"

# Shell semantics of cd, round 1 of review (Sol and Fable). Primary is
# certified for its own index here; the worktree is not.
expect_allowed "a failed cd before ';' leaves the commit in the certified cwd" "$PRIMARY" "cd $WORK/no-such-dir; git commit -m x"
expect_refused "cd <worktree> &&<newline> git commit, uncertified worktree" "$PRIMARY" "cd $WT &&
git commit -m x"
# Logical cd: `cd link/..` lands in the dir HOLDING link, not the target's parent.
mkdir -p "$WT/holder"
ln -s "$PRIMARY/.git" "$WT/holder/link"
expect_refused "cd link/.. is resolved logically (bash), not physically (git -C)" "$WT" "cd ./holder/link/.. && git commit -m x"
# CDPATH can send a relative cd elsewhere.
mkdir -p "$WORK/cdp"; ln -s "$WT" "$WORK/cdp/primary"
export CDPATH="$WORK/cdp"
expect_refused "relative cd with CDPATH set in the hook env" "$WORK" "cd primary && git commit -m x"
unset CDPATH
expect_refused "env --chdir relocation the trigger names" "$PRIMARY" "env --chdir=$WT git commit -m x"

# Same rows, worktree certified: the allow side must survive the fixes.
write_handoff "$WT" "$(git -C "$WT" rev-parse HEAD)" "$WT_TREE" ""
expect_allowed "cd <worktree> &&<newline> git commit, certified worktree" "$PRIMARY" "cd $WT &&
git commit -m x"
expect_allowed "cd <worktree>/sub/.. resolves logically to the worktree" "$PRIMARY" "cd $WT/sub/.. && git commit -m x"

# Round 2 of review. Primary certified, worktree certified.
expect_allowed "git -C '' commit is git's no-op relocation" "$PRIMARY" "git -C '' commit -m x"
# A quoted path holding a tab: the hook's normalisation would read it as a space.
mkdir -p "$WORK/tab dir"; ln -s "$WT" "$WORK/tab dir/r"
mkdir -p "$WORK/tab	dir"; ln -s "$PRIMARY" "$WORK/tab	dir/r"
write_handoff "$PRIMARY" "$(git -C "$PRIMARY" rev-parse HEAD)" "0000000000000000000000000000000000000000" ""
expect_refused "a quoted -C path holding a tab is not read as a space" "$PRIMARY" "git -C '$WORK/tab	dir/r' commit -m x"
# bash refuses `cd nope/..`, so the commit lands in the (uncertified) cwd.
expect_refused "cd <worktree>/nope/..; git commit fails the cd like bash does" "$PRIMARY" "cd $WT/nope/..; git commit -m x"

# Deliberate failure injection for the hoisted self-check above.
if [ -n "${TREE_SUITE_FORCE_FAILURE:-}" ]; then
    fail "forced failure (self-check)"
fi

echo
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ "$FAILED" -eq 0 ] || exit 1
