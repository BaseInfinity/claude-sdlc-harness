#!/bin/bash
# PreCompact hook - block manual /compact mid-git-operation
# Fires on manual /compact only (auto-compact is threshold-driven; blocking
# it could push past 100% context and lose everything). Matcher: "manual"
# in .claude/settings.json.
#
# Requires Claude Code v2.1.105+ (PreCompact event introduced April 13, 2026).
#
# #236(b): the original design also blocked on .reviews/handoff.json being
# PENDING_REVIEW/PENDING_RECHECK (mid cross-model-review-round). Removed —
# every real firing on record over ~2.5 months was a false positive (a
# completed rebase's stale REBASE_HEAD, or an abandoned PENDING handoff),
# never a true positive, and ~150 of this file's 256 lines were self-heal
# machinery mitigating that false-positive rate (3 heal paths + dry-run
# scaffolding). The git-op check below has no such record.
#
# Seam policy: compacting mid-git-operation loses evidence the operation
# needs to finish correctly. Block when a rebase/merge/cherry-pick is in
# progress; allow otherwise.

# Token-bloat fix: when both project + plugin register this hook, plugin yields.
# Use parameter expansion (not `dirname`) so the PATH-restricted gh-missing test
# still works — bash builtin `${var%/*}` is always available.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR="."
# shellcheck disable=SC1091
source "$HOOK_DIR/_find-sdlc-root.sh"
dedupe_plugin_or_project "${BASH_SOURCE[0]}" || { read_stdin_bounded > /dev/null || true; exit 0; }

INPUT=$(read_stdin_bounded) || INPUT=""

# Determine project root: prefer $CLAUDE_PROJECT_DIR, fall back to cwd
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

HOLD_REASONS=""

# #240: SDLC_DRY_RUN_GIT_STATE=rebase|merge|cherry-pick simulates an
# in-flight git operation without needing a real .git/ state, so consumers
# can smoke-test every code path (read-only, no writes).
GITDIR="$ROOT/.git"
# In a linked worktree or a submodule, .git is a file holding
# "gitdir: <path>" (absolute, or relative to $ROOT), and the in-flight
# markers below live under that path, not under $ROOT/.git/. Builtins only,
# like the rest of this hook.
if [ -f "$GITDIR" ]; then
    POINTER=""
    IFS= read -r POINTER < "$GITDIR" 2>/dev/null || true
    POINTER="${POINTER%$'\r'}"
    case "$POINTER" in
        "gitdir: /"*|gitdir:\ [A-Za-z]:*) GITDIR="${POINTER#gitdir: }" ;;
        "gitdir: "?*) GITDIR="$ROOT/${POINTER#gitdir: }" ;;
    esac
fi
# Step 1: when dry-run var matches a known scenario, simulate it.
# Otherwise (unset, empty, or unknown value) fall through to the real
# .git/ checks below — this prevents an unintended safety bypass when
# the user typos the env var (e.g. SDLC_DRY_RUN_GIT_STATE=bogus would
# previously skip real checks entirely; Codex P1 round 1).
DRY_RUN_GIT_HANDLED=0
case "${SDLC_DRY_RUN_GIT_STATE:-}" in
    rebase)
        HOLD_REASONS="${HOLD_REASONS}  - Git rebase in progress. Compacting mid-rebase loses the operation's context.
    Resolve: finish or abort the rebase before /compact."$'\n'
        DRY_RUN_GIT_HANDLED=1
        ;;
    merge)
        HOLD_REASONS="${HOLD_REASONS}  - Git merge in progress. Compacting mid-merge loses the operation's context.
    Resolve: finish or abort the merge before /compact."$'\n'
        DRY_RUN_GIT_HANDLED=1
        ;;
    cherry-pick)
        HOLD_REASONS="${HOLD_REASONS}  - Git cherry-pick in progress. Compacting mid-cherry-pick loses the operation's context.
    Resolve: finish or abort the cherry-pick before /compact."$'\n'
        DRY_RUN_GIT_HANDLED=1
        ;;
esac

# Step 2: real .git/ check fires if dry-run didn't simulate a scenario.
# Empty/unset SDLC_DRY_RUN_GIT_STATE → real check (default behavior).
# Unknown value (e.g. typo "bogus") → also falls through to real check
# rather than silently bypassing safety. The safer-than-the-typo path.
if [ "$DRY_RUN_GIT_HANDLED" -eq 0 ] && [ -d "$GITDIR" ]; then
    # Only the rebase-{merge,apply}/ dir is authoritative for "rebase in progress."
    # .git/REBASE_HEAD is a rebase-related ref (the stopped/replayed commit) that
    # is not authoritative on its own — it can persist as a stale marker after a
    # rebase finishes cleanly: git removes the dir but leaves REBASE_HEAD around
    # for diff/log lookups. Including it in the OR-chain caused false-positive
    # HOLDs that blocked manual /compact for users whose previous rebase had
    # completed (hit live 2026-05-05). `git status` keys on the dirs too.
    if [ -d "$GITDIR/rebase-merge" ] || [ -d "$GITDIR/rebase-apply" ]; then
        HOLD_REASONS="${HOLD_REASONS}  - Git rebase in progress. Compacting mid-rebase loses the operation's context.
    Resolve: finish or abort the rebase before /compact."$'\n'
    fi
    if [ -e "$GITDIR/MERGE_HEAD" ]; then
        HOLD_REASONS="${HOLD_REASONS}  - Git merge in progress. Compacting mid-merge loses the operation's context.
    Resolve: finish or abort the merge before /compact."$'\n'
    fi
    if [ -e "$GITDIR/CHERRY_PICK_HEAD" ]; then
        HOLD_REASONS="${HOLD_REASONS}  - Git cherry-pick in progress. Compacting mid-cherry-pick loses the operation's context.
    Resolve: finish or abort the cherry-pick before /compact."$'\n'
    fi
fi

if [ -n "$HOLD_REASONS" ]; then
    {
        echo "HOLD: manual /compact mid-git-operation."
        echo ""
        echo "$HOLD_REASONS"
        echo "Override: resolve the blocker above, or temporarily disable this hook in .claude/settings.json."
    } >&2
    exit 2
fi

exit 0
