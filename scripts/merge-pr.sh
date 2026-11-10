#!/bin/bash
# merge-pr.sh <PR_NUMBER> — the only way this repo's own agent should merge
# a PR once .claude/hooks/merge-gate-check.sh redirects a bare `gh pr merge`
# here. Repo-local only (not shipped — see CLAUDE_CODE_SDLC_WIZARD.md's CI
# Feedback Loop section and ROADMAP.md for why).
#
# What this mechanically proves (hard-verified, fail-closed):
#   - The local time is outside Mon-Fri 08:00-16:59. Checked first, before
#     any argument parsing or network call, and no flag lifts it.
#   - CI's `validate` check is success for the PR's REMOTE head SHA (not a
#     cached field — queried fresh every run).
#   - The PR touches no HARD_DENY path — the merge-evidence chain, including
#     this wrapper and its redirect hook themselves (closes the
#     self-referential loophole both Codex and a fresh Fable subagent
#     independently flagged in the original prose-only policy: a PR editing
#     the merge policy/mechanism wasn't excluded by a release-only list) —
#     UNLESS --dual-certified or --user-approved cleared it. Read a clean exit
#     as "no HARD path went uncleared", never as "no HARD path was touched";
#     the success line names which authority applied. Same correction the
#     ACKABLE bullet below already carries (Codex round-2 P2), applied here
#     before it could become false a second time.
#   - Every ACKABLE_DENY path the PR touches carries qualifying, SHA-bound
#     cross-model evidence. NOTE this is deliberately weaker than "touches no
#     denylist at all": a successful --cross-model-cleared run IS allowed to
#     touch the policy-prose files, and logs DENYLIST ACKNOWLEDGED when it
#     does. An auditor reading this contract must not read a clean exit as
#     "no denylisted path was touched" (Codex round-2 P2 — the earlier
#     wording asserted exactly that, and became false when tiering landed).
#   - The PR doesn't net-delete files under tests/.
#   - A per-PR clearance artifact exists, is CERTIFIED, references a round
#     >= 2 dialogue (a round-1-only CERTIFIED is treated as suspicious — see
#     below), is bound to the current remote head SHA (not stale), and
#     points at a non-empty review artifact.
#   - The merge itself is atomically bound to the SHA just checked via
#     `--match-head-commit`, closing the TOCTOU race between the checks
#     above and the actual merge (GitHub rejects the merge if HEAD moved).
#
# What stays fundamentally trust-based, even after all of the above (state
# this honestly, don't oversell it): "Codex reached CERTIFIED via a genuine
# adversarial dialogue" and "the Fable subagent was truly fresh/diff-only"
# can never be confirmed by a local script — an agent willing to forge the
# clearance artifact could equally forge a clearance comment. round >= 2 plus a
# non-empty review file is the best available proxy that review wasn't
# skipped or stale, not proof it wasn't faked. Real fake-resistance needs a
# server-side required check (tracked as a Research Parking Lot row in
# ROADMAP.md, not built here). This is a fast local gate against an honest
# agent under time pressure, not a security boundary against a determined
# adversary.

set -u

# --- AFTERHOURS: NO MERGES MON-FRI 08:00-16:59 LOCAL TIME ---
#
# Fleet rule, 2026-11-09: merges wait for after hours, as pushes already do.
# Same window as the afterhours pre-push hook
# (~/.afterhours/hooks/pre-push), deliberately
# WITHOUT its AFTERHOURS_SKIP / _DOW / _HOUR knobs: a bypass would loosen the
# gate this exists to tighten, and no flag below lifts it either.
#
# One `date` call, so the day and the hour come from the same instant. TZ is
# removed for that call because an inherited TZ=UTC turns 14:00 PST into 22:00
# and walks straight past the window. Output that is not "<1-7> <HH>:<MM>"
# fails closed: a non-numeric day would make `[ -le ]` error, read false, and
# let the merge through.
AFTERHOURS_NOW=$(env -u TZ date '+%u %H:%M')
case "$AFTERHOURS_NOW" in
    [1-7]' '[0-2][0-9]:[0-5][0-9]) ;;
    *)
        echo "FAILED CLOSED: could not read the local day and time for the afterhours guard (date printed '$AFTERHOURS_NOW')." >&2
        exit 1
        ;;
esac
AFTERHOURS_HOUR=${AFTERHOURS_NOW#* }
AFTERHOURS_HOUR=${AFTERHOURS_HOUR%%:*}
if [ "${AFTERHOURS_NOW%% *}" -le 5 ] && [ "$((10#$AFTERHOURS_HOUR))" -ge 8 ] && [ "$((10#$AFTERHOURS_HOUR))" -lt 17 ]; then
    echo "BLOCKED: no merges Mon-Fri 08:00-16:59 local time (now: weekday ${AFTERHOURS_NOW%% *} of 7, ${AFTERHOURS_NOW#* }). Merge before 08:00, from 17:00, or on a weekend." >&2
    exit 1
fi

# --- THE REPOSITORY AND HOST THIS GATE ACTS ON ARE PINNED HERE ---
#
# #607 round 3: repository selection in this script was AMBIENT. gh honours
# GH_REPO and GH_HOST, git honours GIT_DIR and GIT_WORK_TREE, and `cd` binds
# neither. The reviewer demonstrated it by running it — with GIT_DIR pointed
# elsewhere, every check below reported success while the requests resolved to
# an unrelated repository. A gate that can be aimed at another repository is
# not a gate.
#
# These exports override whatever the CALLER set. Verified by execution
# against real gh 2.92.0 and real github.com: with GH_HOST=example.invalid,
# GH_REPO=example.invalid/evil/wrong and GIT_DIR=/tmp/nope.git in the parent
# environment, requests still reached Host: api.github.com and this
# repository, including from a call carrying no per-call flags at all.
#
# WHAT THAT DOES AND DOES NOT ESTABLISH — this comment claimed more than was
# true for two rounds, so it is now written narrowly on purpose:
#
#   * It pins calls that do not override it. It is NOT a guarantee about
#     "every present and future invocation". An inline `GH_REPO=x gh …`, a
#     per-call `-R` or `--hostname`, or a literal owner/repo in an API path
#     all take precedence over these lines. Each of those was demonstrated.
#   * It pins the INITIAL request URL. `--paginate` follows the absolute URL
#     a server returns in its Link header and uses it directly, so a server
#     returning a cross-host Link would send the follow-up request there
#     regardless of GH_HOST or --hostname.
#   * BOTH LINES ARE LOAD-BEARING. GH_REPO takes a HOST/OWNER/REPO form and
#     looks like it pins the host too. It does not: with GH_REPO set correctly
#     and a hostile GH_HOST, the request went to Host: example.invalid on the
#     /api/v3/ enterprise path. GH_HOST wins and must be pinned separately.
#
# The per-call `-R` and `--hostname github.com` flags below are kept as a
# second layer. NOT VERIFIED, and previously asserted here as though it were:
# that either layer independently survives deletion of the other at all ten
# call sites. Only the merge call has its exact argv asserted by the suite,
# and the exports were only ever observed as environment values. Treat the two
# layers as belt and braces, not as two independently proven guarantees.
#
# NOT CLOSED BY THIS: GIT_DIR still redirects this script's own `git` calls —
# optionally paired with GIT_WORK_TREE, though GIT_WORK_TREE ALONE does not,
# since it leaves this repository's .git and its origin/main resolution
# intact. Those calls are load-bearing for the self-integrity byte-match and
# for clearance tree binding. Separate channel from gh's, tracked in #681.
#
# There is no test in this repo that proves the pin holds for a call added
# later. Four were written and all four were deleted for reporting a property
# they did not check — see the long note in tests/test-merge-gate.sh.
export GH_HOST=github.com
export GH_REPO=BaseInfinity/claude-sdlc-harness


# --- Two tiers (ROADMAP #479). Codex xhigh (96%) and Fable xhigh (85%),
# consulted independently and blind to each other, both recommended this split.
#
# HARD_DENY is the MERGE-EVIDENCE CHAIN: paths where a PR can alter the meaning
# of the evidence used to merge it. On these, every leg of the evidence stack
# becomes the agent's own say-so simultaneously — branch protection requires the
# check by NAME, so ANY new file under .github/workflows/ can mint a green
# "validate"; the gate that runs is the PR's own working-tree gate; and both
# clearance comments come from the same gh token. Errors in the control plane
# compound, errors in the data plane do not. --cross-model-cleared CANNOT
# satisfy these.
#
# GH #511 — --dual-certified CAN, under a strictly higher bar. The maintainer
# stated it as standing policy: two models that did not write the code, run blind
# to each other, each able to refuse, is a categorically different evidence class
# from "the author says it is fine". Until this flag existed the only way to say
# yes here was --user-approved, so every such merge recorded a per-PR human
# decision for what was actually one standing policy decision — the mechanism was
# forcing a framing lie into the very records that exist to explain why something
# merged.
#
# Two of the three self-produced legs above are answered directly:
#   - "the gate that runs is the PR's own working-tree gate" — the dual path
#     refuses unless this script and its redirect hook byte-match origin/main.
#   - "clearance is a local file the agent wrote" — the dual path additionally
#     requires two distinct reviewers' visible, SHA-bound YES comments on the PR,
#     and does NOT waive the clearance artifact (so round >= 2 still holds).
# The third — a new .github/workflows/ file minting a green "validate" — is NOT
# closed. Nothing local can close it; the compensating layer is that both
# reviewers read that file in the diff. Say so, do not imply otherwise.
HARD_DENY=(
    '^\.github/workflows/'
    '^hooks/'
    '^\.claude/'
    '^scripts/merge-pr\.sh$'
)

# ACKABLE_DENY steers behaviour but does not decide whether THIS PR may merge,
# so visible SHA-bound cross-model evidence is a proportionate gate for it.
ACKABLE_DENY=(
    '^skills/sdlc/SKILL\.md$'
    '^cowork/skills/sdlc/SKILL\.md$'
    '^CLAUDE_CODE_SDLC_WIZARD\.md$'
    '^cowork/hooks/'
)

# Deliberately NOT denylisted:
#   CHANGELOG.md — both reviewers measured it as dead weight: across the last
#     ~25 merged PRs it only ever co-fired with a package.json version bump,
#     which the unconditional content check below already blocks.
#   '^\.github/workflows/release' — redundant now that all of
#     .github/workflows/ is hard-denied.
# package.json is checked for its VERSION FIELD specifically, not any touch (a
# dependency bump shouldn't be release-adjacent) — a content diff below, not a
# path pattern, and unconditional in both tiers.
#
# hooks/ granularity: Fable argued a narrower core (only review-evidence hooks
# hard, advisory ones ackable — 15% vs 26% of PRs needing a human) but said
# plainly that the broad directory is the zero-cleverness option. Broad is used
# here: "advisory vs evidence" is a judgement that drifts as hooks change, and
# it matches the guidance already recorded in ROADMAP #478.

# --- Cross-model clearance, read from the REMOTE PR (ROADMAP #479) ---
#
# WHAT THIS IS, STATED HONESTLY (corrected after Codex round 1):
# This is an AUDIT TRAIL, not an authentication boundary. An earlier version of
# this comment claimed PR comments are harder to forge than a local artifact
# because they are "timestamped, attributable, SHA-bound". Attributable was
# never true: the parser discarded the comment's author. Worse, binding to the
# author does not rescue the claim here, because both reviews are posted by the
# SAME gh token — there is no second authenticated principal to tell them apart.
#
# What it does give you: evidence that is durable, timestamped, readable by a
# human long afterwards, and invalidated by any new push. Against the stated
# threat model — an honest agent that is degraded or under time pressure — that
# is worth having. Against a determined agent it is not, and nothing here
# should be read as claiming otherwise.
#
# Requires: at least two DISTINCT reviewers, each at confidence >= 95 (integer
# 0..100), each bound to the exact head SHA. ACKABLE paths only (GH #784): one
# reviewer at >=95 plus a DISTINCT reviewer whose YES is below 95 and whose
# payload declares "p0_p1": 0 also clears. HARD paths keep the two-at-95 bar.
# The author login of each comment is recorded in the output so an auditor can
# see who actually posted it.
CLEARED_BY=""
verify_cross_model_clearance() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "FAILED CLOSED: jq is required to verify cross-model clearance." >&2
        return 1
    fi
    local comments records who conf sha author verdict blockers line
    local reviewers="" count=0 soft=""
    CLEARED_BY=""
    if ! comments=$(gh api --hostname github.com --paginate "repos/BaseInfinity/claude-sdlc-harness/issues/$PR_NUM/comments" 2>&1); then
        echo "FAILED CLOSED: could not fetch PR comments for #$PR_NUM: $comments" >&2
        return 1
    fi

    # Codex round-1 findings F3 and F4: the previous version pulled reviewer,
    # confidence and sha with three INDEPENDENT `grep | head -1` pipelines over
    # the whole comment body, so the three fields need not have come from the
    # same JSON object — or from any valid object at all. Three unrelated
    # snippets quoted in prose were accepted as clearance. And the confidence
    # regex grabbed leading digits lexically, so the valid JSON number 95e-100
    # (~9.5e-99) read as 95.
    #
    # Both are fixed the same way: extract exactly ONE fenced json payload per
    # comment and let jq parse it as JSON, evaluating all three fields from that
    # single object and comparing confidence numerically. A comment with zero or
    # more than one payload is rejected rather than partially parsed.
    # Fable finding 8: the previous marker was an HTML comment, and the whole
    # payload could be wrapped in one too — rendering as "LGTM, nice work!" in
    # the GitHub UI while still clearing the merge. Since the entire remaining
    # justification is "a human can read this later", evidence a human cannot
    # see is worse than useless. HTML comments are now STRIPPED before scanning,
    # so both the marker and the payload must be visibly rendered.
    #
    # Fable finding 7: comment authorship was not gated at all — any GitHub user
    # who can comment could mint clearance. Now restricted to OWNER/MEMBER/
    # COLLABORATOR. This does not make forgery hard (see the header), it just
    # stops a drive-by.
    records=$(printf '%s' "$comments" | jq -r '
        .[]?
        | select(.body != null)
        | select((.author_association // "") | . == "OWNER" or . == "MEMBER" or . == "COLLABORATOR")
        | . as $c
        | ($c.body | gsub("(?s)<!--.*?-->"; " ")) as $visible
        # POSITIVE VISIBILITY SHAPE (Fable round-3 N4/N5). Blacklisting hiding
        # mechanisms one at a time does not converge: after HTML comments came
        # <details><summary>, then [//]: # link-reference definitions. So the
        # rule is inverted — a clearance comment must have a known-good shape,
        # and anything that could render it invisible disqualifies it.
        #
        # Code spans and fences are removed FIRST, so a reviewer who legitimately
        # quotes `<!--` or <details> while discussing markup is not punished for
        # it (N5: those honest comments were being silently dropped).
        | ($visible
            | gsub("(?s)```.*?```"; " ")
            | gsub("`[^`]*`"; " ")) as $prose
        # No raw HTML outside code: covers <!--, <details>, <summary>, <div>,
        # and anything else that can collapse or hide the payload.
        | select($prose | test("<[a-zA-Z!/]") | not)
        # No link-reference definitions: "[//]: # (...)" renders as nothing.
        | select($prose | test("(?m)^[ \t]*\\[[^]]*\\][ \t]*:") | not)
        # The marker must start its own line — not indented into a list item or
        # blockquote, where it can be visually buried.
        | select($visible | test("(?m)^\\*\\*CROSS-MODEL-CLEARANCE\\*\\*"))
        | ($visible | [scan("(?s)```json\\s*(\\{.*?\\})\\s*```")] ) as $payloads
        | select(($payloads | length) == 1)
        | ($payloads[0][0] | fromjson? // empty) as $p
        # GH #478: `verdict` is REQUIRED. Until it existed, this parser read
        # reviewer/confidence/sha and never asked whether the reviewer actually
        # said the PR was safe to merge — confidence was standing in for a
        # verdict that was never modelled. A payload declaring MERGE_SAFE: NO in
        # its prose, carrying confidence 97, cleared every check and merged.
        # Proven by tests/test-merge-gate.sh: two NO verdicts at 97 and 99 merged.
        #
        # Note on how this survived: this function WAS well covered — 49
        # assertions in tests/test-cross-model-clearance.sh, spanning confidence
        # bounds, SHA binding, authorship and payload visibility. Every one of
        # them fed a fixture that omitted any verdict, so the whole suite tested
        # the shape of the evidence and never the answer inside it. Coverage
        # count is not coverage of the thing that matters.
        # DUPLICATE-KEY SHADOWING — two rounds, two shapes, one lesson.
        #
        # Round 1 (Codex): JSON parsers keep the LAST duplicate key, so a payload
        # carrying `verdict` twice — NO first, YES last — parsed as YES and
        # merged while the rendered comment read as a refusal. I answered by
        # counting `"verdict":` in the raw text.
        # Round 2 (Codex): `verdict` and `verdict` decode to `verdict`,
        # so the raw-text count saw one key and the parser saw two. Counting
        # literal text cannot win against escaping — every escape form I block,
        # another encodes around.
        #
        # So this stops counting and pins the payload instead: EXACTLY the four
        # decision-bearing keys, and no backslash anywhere. A clearance payload
        # is machine-written and every value is a constrained token (an exact
        # verdict, a hex sha, a number, a [A-Za-z0-9._-] reviewer), so no
        # legitimate one needs an escape. Duplicates, escaped keys, and
        # unexamined extra fields all fail by construction rather than by
        # enumeration — the difference between naming what is allowed and
        # chasing what is forbidden.
        | select($payloads[0][0] | test("\\\\") | not)
        # GH #784: one optional fifth key, `p0_p1`: how many P0/P1 findings
        # the reviewer left open. It lets a YES below 95 count as the second
        # reviewer on an ACKABLE path, so it is pinned exactly like the others.
        | select(($p | keys) == ["confidence", "reviewer", "sha", "verdict"]
              or ($p | keys) == ["confidence", "p0_p1", "reviewer", "sha", "verdict"])
        # Raw-text counting is only sound BECAUSE the line above bans
        # backslashes: with no escapes possible, a key in the text is the key
        # the parser sees. It is still needed, since `keys` runs after the
        # decoder has already collapsed a plain duplicate down to one.
        | select([$payloads[0][0] | scan("\"verdict\"[[:space:]]*:")] | length == 1)
        | select([$payloads[0][0] | scan("\"sha\"[[:space:]]*:")] | length == 1)
        | select([$payloads[0][0] | scan("\"confidence\"[[:space:]]*:")] | length == 1)
        | select([$payloads[0][0] | scan("\"reviewer\"[[:space:]]*:")] | length == 1)
        | select([$payloads[0][0] | scan("\"p0_p1\"[[:space:]]*:")] | length <= 1)
        | select(($p | has("p0_p1") | not) or ($p.p0_p1 | type == "number"))
        | select($p.reviewer != null and $p.confidence != null and $p.sha != null)
        | select($p.verdict != null)
        | select($p.verdict | type == "string")
        | select($p.confidence | type == "number")
        | select($p.reviewer | type == "string")
        | select($p.sha | type == "string")
        # NO ascii_upcase. It normalised 'yes' and 'YeS' into YES, so the
        # exact-match check below — documented as strict — was not strict. A
        # verdict is a machine-written field; a reviewer that cannot emit the
        # exact token has not cleared anything.
        # Absent p0_p1 prints "-", never an empty column: tab is IFS
        # whitespace, so `read` would collapse an empty field.
        | [($c.user.login // "unknown"), $p.reviewer, ($p.confidence|tostring), $p.sha, $p.verdict,
           (if $p | has("p0_p1") then ($p.p0_p1 | tostring) else "-" end)]
        | @tsv
    ' 2>/dev/null)

    if [ -z "$records" ]; then
        echo "BLOCKED: no well-formed cross-model clearance comments on PR #$PR_NUM." >&2
        return 1
    fi

    while IFS=$'\t' read -r author who conf sha verdict blockers; do
        [ -z "$who" ] && continue
        # GH #478: the verdict decides; confidence only qualifies a YES. Anything
        # that is not an explicit YES is refused, so a malformed or novel verdict
        # value fails closed rather than being treated as assent.
        if [ "$verdict" != "YES" ]; then
            echo "  ignored: $who returned verdict '$verdict', not YES" >&2; continue
        fi
        # F1: the reviewer identity must be a single safe token. The previous
        # version later ran `set -- $reviewers`, which word-splits on IFS, so a
        # reviewer value of "alice bob" satisfied the two-reviewer threshold
        # from ONE comment.
        case "$who" in *[!A-Za-z0-9._-]*)
            echo "  ignored: reviewer '$who' is not a single [A-Za-z0-9._-] token" >&2; continue ;;
        esac
        # Fable finding 9: honest payloads were silently dropped with no reason
        # given — "the gate refused my valid clearance and won't say why" is the
        # exact frustration loop #479 exists to end. Every rejection now says why,
        # and a SHA differing only in case is accepted.
        if [ "$(printf '%s' "$sha" | tr 'A-F' 'a-f')" != "$(printf '%s' "$HEAD_SHA" | tr 'A-F' 'a-f')" ]; then
            echo "  ignored: $who cleared $sha, not the current head $HEAD_SHA" >&2; continue
        fi
        conf=${conf%.0}                          # jq renders an integer-valued float as 100.0
        case "$conf" in *[!0-9]*)
            echo "  ignored: $who gave a non-integer confidence '$conf'" >&2; continue ;;
        esac
        if [ "$conf" -gt 100 ]; then
            echo "  ignored: $who gave confidence $conf, above 100" >&2; continue
        fi
        # GH #784: a YES below 95 that declares exactly 0 open P0/P1 findings
        # is held as a possible SECOND reviewer, for ACKABLE paths only. The
        # string compare is exact: "-", "0.0", "-1" and "1e-09" do not qualify.
        if [ "$conf" -lt 95 ] && [ "$blockers" = "0" ]; then
            echo "  noted: $who returned YES at confidence $conf with 0 P0/P1 — counts as the second reviewer on ACKABLE paths only" >&2
            soft="$soft$who	$who at $conf with 0 P0/P1 (posted by @$author)
"
            continue
        fi
        if [ "$conf" -lt 95 ]; then
            # GH #478: a YES under the bar means a NAMED RESIDUAL, not a dead
            # end. v1.92.0 got YES/97 and YES/93 — both reviewers agreed it was
            # safe — and the gate simply refused, so the maintainer ran the
            # merge by hand. That is the failure this message exists to stop:
            # say what closes the gap. Re-reviewing until a number improves is
            # NOT the remedy; resolving the reviewer's stated residual is.
            echo "  ignored: $who returned YES at confidence $conf, below the 95 bar" >&2
            echo "    next: run a focused merge-safety round on the residual $who named," >&2
            echo "    fix or refute it, and have $who re-post. Do not re-ask for a higher" >&2
            echo "    number without changing anything — that is shopping, not review." >&2
            continue
        fi
        case " $reviewers " in *" $who "*) continue ;; esac
        reviewers="$reviewers $who"
        CLEARED_BY="$CLEARED_BY${CLEARED_BY:+, }$who (posted by @$author)"
        count=$((count + 1))
    done <<< "$records"

    # F1: count parsed RECORDS, never shell words.
    CLEARANCE_STRICT=$count
    # Distinctness is decided here, after every comment is read, so comment
    # order cannot let one reviewer fill both legs.
    CLEARANCE_SOFT=""
    while IFS=$'\t' read -r who line; do
        [ -z "$who" ] && continue
        case " $reviewers " in *" $who "*) continue ;; esac
        CLEARANCE_SOFT=$line
        break
    done <<< "$soft"
    return 0
}

# Memoised. Both denylist passes can hit clearance, once per matching path, and
# each call re-fetches every comment on the PR. The verdict cannot change within
# a run, so compute it once and reuse it — including the reason text, which must
# print exactly once rather than once per file.
#
# $1 is the tier being cleared. GH #784: `hard` needs 2 distinct reviewers at
# >=95. `ackable` also accepts 1 at >=95 plus a distinct YES below 95 that
# declares "p0_p1": 0. Each tier's refusal exits the run, so its reason prints
# once.
CLEARANCE_CHECKED=0
CLEARANCE_PARSED=0
CLEARANCE_STRICT=0
CLEARANCE_SOFT=""
CLEARANCE_STRICT_BY=""
clearance_ok() {
    if [ "$CLEARANCE_CHECKED" -eq 0 ]; then
        CLEARANCE_CHECKED=1
        if verify_cross_model_clearance; then CLEARANCE_PARSED=1; fi
        CLEARANCE_STRICT_BY=$CLEARED_BY
    fi
    [ "$CLEARANCE_PARSED" -eq 1 ] || return 1
    CLEARED_BY=$CLEARANCE_STRICT_BY
    [ "$CLEARANCE_STRICT" -ge 2 ] && return 0
    if [ "$1" = "ackable" ]; then
        if [ "$CLEARANCE_STRICT" -eq 1 ] && [ -n "$CLEARANCE_SOFT" ]; then
            CLEARED_BY="$CLEARED_BY, $CLEARANCE_SOFT"
            return 0
        fi
        echo "BLOCKED: cross-model clearance needs 2 distinct reviewers at >=95%, or 1 at >=95% plus a distinct YES below 95 declaring \"p0_p1\": 0, bound to $HEAD_SHA; found $CLEARANCE_STRICT at >=95%." >&2
        return 1
    fi
    echo "BLOCKED: cross-model clearance needs 2 distinct reviewers at >=95% bound to $HEAD_SHA; found $CLEARANCE_STRICT. A YES below 95 does not count on a merge-evidence path, whatever its P0/P1 count." >&2
    return 1
}

# --- Gate self-integrity, dual path only (GH #511) ---
#
# HARD_DENY's sharpest objection is that a PR editing the gate is judged by its
# own edited gate. Dual review does not fix that on its own: the reviewers read
# the diff, but the code that actually decides is whatever is in the working
# tree. So on the dual path this script and its redirect hook must byte-match
# origin/main — merge from a clean main checkout, not from the PR branch.
#
# STATE THE LIMIT HONESTLY: a self-check cannot defend against its own deletion.
# Strip these lines from the working-tree copy and nothing here fires. The
# compensating layer is that such a deletion is exactly what two independent
# reviewers are looking at in the diff, and that the same argument applies to
# every local check in this file (an agent that would edit the gate could simply
# not run it). This raises the cost of an honest mistake; it is not a boundary
# against a determined adversary.
#
# Paths are cwd-relative on purpose: `git show` resolves repo-relative, and the
# copy that matters is the one being executed from the repo root.
GATE_CHECKED=0
GATE_OK=0

# Compare one working file against its origin/main blob by OBJECT ID.
#
# Round 1, Codex: the first version was `git show ... | cmp -s - "$f"`, whose
# pipeline status is only cmp's. A producer that emits a prefix equal to the
# local file and THEN fails leaves two equal EOF-terminated streams, so cmp
# returns 0 and a blob that was never successfully read is recorded as matching.
# Object IDs sidestep it: both sides are explicit commands with checked exit
# codes, the comparison is byte-exact, and no temp file or pipeline is involved.
blob_matches_main() {   # $1=repo-relative path in origin/main  $2=file on disk
    local want have
    want=$(git rev-parse --verify --quiet "refs/remotes/origin/main:$1" 2>/dev/null) || return 1
    have=$(git hash-object -- "$2" 2>/dev/null) || return 1
    [ -n "$want" ] && [ "$want" = "$have" ]
}

verify_gate_integrity() {
    # Best-effort refresh. A stale local ref still names a version that was
    # reviewed and merged, so falling back to it is safe in the direction that
    # matters; a hard failure here would make the dual path unusable offline.
    git fetch --quiet origin main >/dev/null 2>&1 || true
    if ! git rev-parse --verify --quiet refs/remotes/origin/main >/dev/null 2>&1; then
        echo "BLOCKED: no refs/remotes/origin/main to compare the gate against, so --dual-certified cannot prove it is running the reviewed gate rather than this branch's edited one. Fetch origin, or use --user-approved \"<reason>\"." >&2
        return 1
    fi

    # THE SCRIPT THAT IS RUNNING, via BASH_SOURCE — not a cwd-relative path.
    #
    # Round 1, found independently by BOTH reviewers, and the sharpest finding of
    # the review: the first version compared `scripts/merge-pr.sh` relative to the
    # working directory and never looked at $0. So the file checked and the file
    # executing could be different files, and the message printed on failure —
    # "run the merge from a clean main checkout" — steered an agent directly into
    # that gap: it re-runs the absolute path it already has, from a clean cwd, and
    # the PR's edited gate decides the merge while the success line reports that
    # the gate matched origin/main.
    #
    # This is NOT the conceded "an agent could edit or delete this check". Nothing
    # was edited; the check simply bound the wrong artifact. That distinction is
    # why it was a real finding and not a restatement of the threat model.
    if ! blob_matches_main "scripts/merge-pr.sh" "${BASH_SOURCE[0]}"; then
        echo "BLOCKED: the merge script now executing (${BASH_SOURCE[0]}) does not match origin/main's scripts/merge-pr.sh. --dual-certified would be letting this branch's own gate decide whether this branch may merge. Check out main and run ITS ./scripts/merge-pr.sh — running a PR-branch copy from a clean directory does not count — or decide it yourself with --user-approved \"<reason>\"." >&2
        return 1
    fi

    # The redirect hook is different: the Claude Code harness loads it from the
    # working directory, so the cwd copy IS the operative one. Checking $0 would
    # be the wrong artifact here for the mirror-image reason.
    if ! blob_matches_main ".claude/hooks/merge-gate-check.sh" ".claude/hooks/merge-gate-check.sh"; then
        echo "BLOCKED: '.claude/hooks/merge-gate-check.sh' in this working directory differs from origin/main, or could not be read. That hook is what redirects a bare merge here, and the harness runs the working-tree copy. Run from a clean main checkout, or use --user-approved \"<reason>\"." >&2
        return 1
    fi
    return 0
}
gate_integrity_ok() {
    if [ "$GATE_CHECKED" -eq 0 ]; then
        GATE_CHECKED=1
        if verify_gate_integrity; then GATE_OK=1; fi
    fi
    [ "$GATE_OK" -eq 1 ]
}

if [ $# -lt 1 ]; then
    echo "Usage: scripts/merge-pr.sh <PR_NUMBER>" >&2
    exit 1
fi

PR_NUM="$1"
shift
CROSS_MODEL_CLEARED=0
DUAL_CERTIFIED=0
USER_APPROVED_REASON=""
WAIVED_PATHS=""
DUAL_PATHS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --cross-model-cleared) CROSS_MODEL_CLEARED=1 ;;
        # Implies --cross-model-cleared rather than replacing it: greater
        # authority covers lesser (same precedent as --user-approved clearing
        # both tiers), and keeping the flags distinct means the audit line can
        # say which authority was actually invoked.
        --dual-certified) DUAL_CERTIFIED=1; CROSS_MODEL_CLEARED=1 ;;
        --user-approved)
            # The reason is REQUIRED. A bare flag would be a silent bypass
            # wearing an audit trail's clothes (ROADMAP #479).
            shift
            if [ $# -eq 0 ] || [ -z "$1" ]; then
                echo "BLOCKED: --user-approved requires a non-empty reason, e.g. --user-approved \"maintainer decision: shipping the hook fix, certified round 3\". An override with no stated reason is unauditable." >&2
                exit 1
            fi
            # A flag is not a reason. `--user-approved --cross-model-cleared`
            # otherwise consumed the NEXT FLAG as the justification and fired a
            # full override whose recorded reason was the literal string
            # "--cross-model-cleared". Found by probing argument shapes before
            # review reported; the two happy-path assertions did not cover it.
            case "$1" in
                -*)
                    echo "BLOCKED: --user-approved's reason cannot start with '-' (got '$1'). That is a flag, not a decision — quote a real reason: --user-approved \"why you are overriding\"." >&2
                    exit 1
                    ;;
            esac
            # Whitespace is not a reason either.
            if [ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]; then
                echo "BLOCKED: --user-approved's reason is only whitespace. An override recorded with a blank reason is unauditable." >&2
                exit 1
            fi
            USER_APPROVED_REASON="$1"
            ;;
        *) echo "Usage: scripts/merge-pr.sh <PR_NUMBER> [--cross-model-cleared] [--dual-certified] [--user-approved \"<reason>\"]" >&2; exit 1 ;;
    esac
    shift
done

if ! PR_JSON=$(gh pr view -R github.com/BaseInfinity/claude-sdlc-harness "$PR_NUM" --json headRefOid,number,state,baseRefName 2>&1); then
    echo "FAILED CLOSED: could not fetch PR #$PR_NUM (gh error): $PR_JSON" >&2
    exit 1
fi
HEAD_SHA=$(printf '%s' "$PR_JSON" | grep -o '"headRefOid"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"headRefOid"[[:space:]]*:[[:space:]]*"//; s/"$//')
if [ -z "$HEAD_SHA" ]; then
    echo "FAILED CLOSED: could not determine remote head SHA for PR #$PR_NUM" >&2
    exit 1
fi
# #540's base_tree check compares against the branch this PR actually targets,
# never a hardcoded `main`. A PR stacked on another branch has a different base
# and would otherwise be judged against a base it was never read on.
BASE_BRANCH=$(printf '%s' "$PR_JSON" | grep -o '"baseRefName"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"baseRefName"[[:space:]]*:[[:space:]]*"//; s/"$//')
if [ -z "$BASE_BRANCH" ]; then
    echo "FAILED CLOSED: could not determine the base branch for PR #$PR_NUM" >&2
    exit 1
fi
# WHERE THE BASE BRANCH IS NOW — asked of the server, every run.
#
# Two rounds of #628 got this wrong the SAME way, and the shared mistake is
# worth more than either fix: both read a CACHED value and treated it as
# current.
#
#   Round 1 read `refs/remotes/origin/$BASE_BRANCH`, a local cache. Absent, the
#   comparison was skipped outright; stale, it still held the certified tree and
#   satisfied the check. Both reviewers broke it — one by deleting the ref, one
#   by advancing a bare server's main and leaving the ref behind.
#
#   Round 2 read `baseRefOid` off `gh pr view`, which BOTH reviewers had
#   prescribed. Live data falsified it: that field is the base commit ASSOCIATED
#   WITH THE PULL REQUEST, a snapshot that does not move when the branch does.
#   Measured on this repo — PR #615 carried baseRefOid f8ba12b while main was at
#   d0e1c7b, different trees. So round 2 replaced an indefinitely stale local
#   cache with an indefinitely stale server-side snapshot.
#
# `baseRefOid` is therefore deliberately NOT in the `pr view --json` list above:
# a trap field left parsed is a regression waiting to be reintroduced. The ref
# endpoint below is the branch tip itself.
if ! BASE_REF_JSON=$(gh api --hostname github.com "repos/BaseInfinity/claude-sdlc-harness/git/ref/heads/$BASE_BRANCH" 2>&1); then
    echo "FAILED CLOSED: could not read the current tip of $BASE_BRANCH (gh error): $BASE_REF_JSON" >&2
    exit 1
fi
BASE_SHA=$(printf '%s' "$BASE_REF_JSON" | grep -o '"sha"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"sha"[[:space:]]*:[[:space:]]*"//; s/"$//')
if [ -z "$BASE_SHA" ]; then
    echo "FAILED CLOSED: could not determine the current tip of $BASE_BRANCH for PR #$PR_NUM" >&2
    exit 1
fi

# --- Every check below is UNCONDITIONAL. ROADMAP #479: the old
# ROADMAP #479: the retired bypass disabled all of them at once, so acknowledging one
# denylist row meant disarming CI, test-deletion, SHA-freshness and the
# clearance artifact. There is now no flag that turns any of these off.
    # --- Fetch per-file status/patch data once, with pagination. Codex
    # round-1 finding: without --paginate, gh's API call silently returns
    # only the first page (default 30 entries) — a deleted test outside
    # that page was invisible. Fetched early (before the denylist loop) so
    # the package.json version check below can reuse it instead of an
    # invalid `gh pr diff -- <path>` call (gh pr diff has no per-path
    # filter flag; that call errors with stderr suppressed, so the check
    # silently no-opped — Codex round-1 finding). ---
    if ! PR_FILES=$(gh api --hostname github.com --paginate "repos/BaseInfinity/claude-sdlc-harness/pulls/$PR_NUM/files" 2>&1); then
        echo "FAILED CLOSED: could not fetch file statuses for PR #$PR_NUM: $PR_FILES" >&2
        exit 1
    fi

    # --- Denylist / release-policy-adjacency check (checked first so the
    # self-referential case fails loud and immediately) ---
    if ! DIFF_FILES=$(gh pr diff -R github.com/BaseInfinity/claude-sdlc-harness "$PR_NUM" --name-only 2>&1); then
        echo "FAILED CLOSED: could not fetch diff for PR #$PR_NUM: $DIFF_FILES" >&2
        exit 1
    fi
    # Tier classification reads the FILES API, never `gh pr diff --name-only`
    # (Codex round-2, two proven HARD-tier bypasses):
    #
    #  - `gh pr diff` emits DISPLAY text, preserving core.quotePath quoting and
    #    octal escapes. `".github/workflows/validate-\360\237\230\200.yml"`
    #    begins with a quote, so every column-anchored HARD pattern missed it and
    #    the merge reported "denylist clear". jq decodes the real pathname.
    #  - A PR diff is capped at 300 files, so a HARD path at position 301 was
    #    simply absent from the classified set while a visible ACKABLE hit
    #    cleared normally.
    #
    # Both current and previous names are classified, so renaming a protected
    # file out of a protected directory cannot change its tier.
    if ! command -v jq >/dev/null 2>&1; then
        echo "FAILED CLOSED: jq is required to classify changed paths." >&2
        exit 1
    fi
    CLASSIFY_PATHS=$(printf '%s' "$PR_FILES" \
        | jq -rs 'map(if type == "array" then .[] else . end)
                  | map(select(type == "object"))
                  | map(.filename // empty, .previous_filename // empty)
                  | .[]' 2>/dev/null | grep -v '^$' || true)

    # Completeness: never classify a truncated set. If the API returned fewer
    # files than the PR claims to change, fail closed rather than silently
    # judging a subset (GitHub caps the files endpoint at 3000).
    # Codex round-3: `|| echo ""` turned an API/CLI failure into "skip the
    # check" — precisely the condition that must fail closed. A HARD file past
    # the files-API ceiling was invisible whenever this second query failed.
    if ! CHANGED_COUNT=$(gh pr view -R github.com/BaseInfinity/claude-sdlc-harness "$PR_NUM" --json changedFiles --jq '.changedFiles' 2>/dev/null); then
        echo "FAILED CLOSED: could not read changedFiles for PR #$PR_NUM — cannot prove the classified path set is complete." >&2
        exit 1
    fi
    case "$CHANGED_COUNT" in
        ''|*[!0-9]*)
            echo "FAILED CLOSED: changedFiles for PR #$PR_NUM was '${CHANGED_COUNT:-empty}', not a number." >&2
            exit 1 ;;
    esac
    if [ "$CHANGED_COUNT" -lt 1 ]; then
        echo "FAILED CLOSED: PR #$PR_NUM reports $CHANGED_COUNT changed files." >&2
        exit 1
    fi
    SEEN_COUNT=$(printf '%s' "$PR_FILES" \
        | jq -rs 'map(if type == "array" then .[] else . end)
                  | map(select(type == "object" and has("filename"))) | length' 2>/dev/null || echo 0)
    if [ "${SEEN_COUNT:-0}" -lt "$CHANGED_COUNT" ]; then
        echo "FAILED CLOSED: PR #$PR_NUM changes $CHANGED_COUNT files but only $SEEN_COUNT were retrievable — the tier classifier would be judging a truncated set." >&2
        exit 1
    fi

    if [ -z "$CLASSIFY_PATHS" ]; then
        echo "FAILED CLOSED: could not determine any changed path for PR #$PR_NUM." >&2
        exit 1
    fi

    # PASS 1 — HARD tier, evaluated across EVERY path before anything can be
    # acknowledged, so a PR touching both tiers is blocked by the hard one.
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        for pattern in "${HARD_DENY[@]}"; do
            if printf '%s' "$f" | grep -qiE "$pattern"; then
                if [ -n "$USER_APPROVED_REASON" ]; then
                    # HARD_DENY's own message says "a human decides this one",
                    # and until now offered no way to say so — the maintainer's
                    # only route was the GitHub UI, which bypasses this harness
                    # entirely and leaves NO record in the repo.
                    #
                    # Stated honestly: this does NOT prove a human typed it.
                    # Nothing available to a local script can. What it changes
                    # is that an override becomes explicit, reasoned and logged
                    # instead of silent and out-of-band. Do not describe it as
                    # proof of human authorship.
                    echo "USER-APPROVED OVERRIDE: PR #$PR_NUM touches '$f' ($pattern), a merge-evidence path where self-produced clearance cannot apply. Proceeding on the stated human decision:" >&2
                    echo "  reason:   $USER_APPROVED_REASON" >&2
                    WAIVED_PATHS="$WAIVED_PATHS$f (merge-evidence path)
"
                    continue
                fi
                # GH #511. Checked AFTER --user-approved so an explicit human
                # decision always wins, and gate integrity BEFORE clearance so
                # the first thing reported is the one condition the reviewers
                # themselves cannot vouch for.
                if [ "$DUAL_CERTIFIED" -eq 1 ] && gate_integrity_ok && clearance_ok hard; then
                    echo "DUAL-CERTIFIED: PR #$PR_NUM touches '$f' ($pattern), a merge-evidence path. Cleared by $CLEARED_BY, both bound to $HEAD_SHA, with this gate byte-matching origin/main. ATTESTED, NOT AUTHENTICATED — both clearances were posted by the same gh token, so this records that two reviewers said yes, not that two independent principals did." >&2
                    DUAL_PATHS="$DUAL_PATHS$f (merge-evidence path)
"
                    continue
                fi
                echo "BLOCKED: PR #$PR_NUM touches '$f', part of the merge-evidence chain ($pattern). --cross-model-cleared does NOT apply here: on these paths the PR defines its own CI check, runs its own gate, and posts its own clearance, so every leg of the evidence would be self-produced. Two routes forward: post two distinct reviewers' SHA-bound YES clearances to the PR and re-run with --dual-certified from a clean main checkout, or — if you are the human and have decided — --user-approved \"<reason>\", which merges and records the reason." >&2
                exit 1
            fi
        done
    done <<< "$CLASSIFY_PATHS"

    # PASS 2 — ACKABLE tier.
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        for pattern in "${ACKABLE_DENY[@]}"; do
            if printf '%s' "$f" | grep -qiE "$pattern"; then
                if [ -n "$USER_APPROVED_REASON" ]; then
                    # A human authorised to override the tier that DECIDES
                    # whether a merge is allowed is necessarily authorised to
                    # override the tier that merely steers behaviour. Requiring
                    # a second, different flag for the lesser bar is incoherent
                    # — found live merging PR #494, where --user-approved
                    # cleared six hooks/ paths and then blocked on a doc.
                    echo "USER-APPROVED OVERRIDE: '$f' is guidance this PR changes, normally cleared by posted review. Proceeding on the stated human decision." >&2
                    WAIVED_PATHS="$WAIVED_PATHS$f (guidance path)
"
                    continue
                fi
                if [ "$CROSS_MODEL_CLEARED" -eq 1 ] && clearance_ok ackable; then
                    echo "DENYLIST ACKNOWLEDGED: '$f' matches $pattern, cleared by $CLEARED_BY. Every other check still ran." >&2
                    continue
                fi
                echo "BLOCKED: PR #$PR_NUM changes '$f', a file that steers how future work is done. Clear it either way: post cross-model review to the PR and re-run with --cross-model-cleared, or decide it yourself with --user-approved \"<reason>\"." >&2
                exit 1
            fi
        done
    done <<< "$CLASSIFY_PATHS"

    # Fable round-3 N1: this loop still read $DIFF_FILES — the display-text,
    # 300-file-capped source that classification was moved OFF for exactly this
    # reason. A version bump past position 300 merged as "denylist clear",
    # despite the header calling this check unconditional in both tiers.
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        if [ "$f" = "package.json" ]; then
            PKG_PATCH=$(printf '%s' "$PR_FILES" | grep -oE '"filename"[[:space:]]*:[[:space:]]*"package\.json"[^}]*"patch"[[:space:]]*:.*')
            if printf '%s' "$PKG_PATCH" | grep -qE '[+-][[:space:]]*\\"version\\"'; then
                if [ -n "$USER_APPROVED_REASON" ]; then
                    # This check demands "explicit user confirmation", and
                    # --user-approved with a stated reason IS that confirmation.
                    # Third instance of the same gap: a gate asking for a human
                    # decision while providing no way to express one.
                    echo "USER-APPROVED OVERRIDE: version bump in package.json is release-adjacent and requires explicit confirmation — given, on the stated reason." >&2
                    WAIVED_PATHS="$WAIVED_PATHS package.json version bump (release-adjacent confirmation)
"
                else
                    echo "BLOCKED: PR #$PR_NUM changes package.json's version field — release-adjacent. Explicit user confirmation is required: re-run with --user-approved \"<reason>\"." >&2
                    exit 1
                fi
            fi
        fi
    done <<< "$CLASSIFY_PATHS"

    # --- Test-deletion check: covers both outright deletion (status
    # "removed") and renaming a test OUT of tests/ (status "renamed" with a
    # previous_filename under tests/ but a new filename that isn't) — Codex
    # round-1 finding: the original check only recognized "removed",
    # missing this equally-effective removal path. ---
    DELETED_TESTS=$(printf '%s' "$PR_FILES" | grep -o '"filename"[[:space:]]*:[[:space:]]*"[^"]*"[^}]*"status"[[:space:]]*:[[:space:]]*"removed"' \
        | grep -o '"filename"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | sed 's/.*"filename"[[:space:]]*:[[:space:]]*"//; s/"$//' \
        | grep '^tests/' || true)
    RENAMED_OUT_OF_TESTS=$(printf '%s' "$PR_FILES" | grep -oE '"previous_filename"[[:space:]]*:[[:space:]]*"tests/[^"]*"[^}]*"status"[[:space:]]*:[[:space:]]*"renamed"|"status"[[:space:]]*:[[:space:]]*"renamed"[^}]*"previous_filename"[[:space:]]*:[[:space:]]*"tests/[^"]*"' \
        | grep -o '"previous_filename"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | sed 's/.*"previous_filename"[[:space:]]*:[[:space:]]*"//; s/"$//' || true)
    ALL_REMOVED_TESTS=$(printf '%s\n%s' "$DELETED_TESTS" "$RENAMED_OUT_OF_TESTS" | grep -v '^$' || true)
    if [ -n "$ALL_REMOVED_TESTS" ]; then
        echo "BLOCKED: PR #$PR_NUM net-removes test file(s) (deleted or renamed out of tests/): $ALL_REMOVED_TESTS. NOT WAIVABLE — --user-approved cannot clear this. Restore the tests, or merge in the GitHub UI and own it." >&2
        exit 1
    fi

    # --- CI validate check (must be exactly "success" for the remote head) ---
    # --paginate: without it this reads only the first page, so "every run named
    # validate" meant "every run on page one" and a red duplicate on page two was
    # invisible (Codex round 1). Same defect the files endpoint already carries a
    # comment about.
    if ! CHECK_RUNS=$(gh api --hostname github.com --paginate "repos/BaseInfinity/claude-sdlc-harness/commits/$HEAD_SHA/check-runs" 2>&1); then
        echo "FAILED CLOSED: could not fetch check-runs for $HEAD_SHA: $CHECK_RUNS" >&2
        exit 1
    fi
    # EVERY run named "validate", not the first one found. Branch protection
    # requires the check by NAME, so nothing stops several existing on one SHA —
    # and `head -1` meant a green one ordered ahead of a red one satisfied the
    # gate. Same defect class as reading the shape of evidence and never the
    # answer inside it. Residual, deliberately not chased: this cannot tell a
    # legitimate `validate` from one minted by a workflow the PR itself adds.
    # That is why .github/workflows/ is HARD_DENY.
    # jq, not regex. Round 1, both reviewers: a queued or in-progress run is
    # `"conclusion": null` in real payloads, which a quoted-value pattern cannot
    # match — so a still-running `validate` beside an old green one merged, while
    # the block message claimed pending blocks. Fable also measured that the
    # docs-order pattern never matched a live payload at all (GitHub emits `name`
    # BEFORE `conclusion`), making half the old extraction dead code.
    #
    # jq is already a hard dependency here, so this removes a class of bug rather
    # than adding a dependency: `// "pending"` turns any null into a value that
    # fails the green test, and an empty-string conclusion can no longer read as
    # green by vanishing into a blank line.
    # Codex round 2: the first version unwrapped `{check_runs:[...]}` but sent a
    # BARE ARRAY page through `else .`, where the object filter then dropped it —
    # so a green wrapped page followed by a bare page carrying a red `validate`
    # merged. `gh --paginate` concatenates whatever each page is, so both shapes
    # must be flattened, and neither may be silently discarded.
    #
    # jq's exit status is checked rather than swallowed. A malformed payload used
    # to yield an empty set, which the check below then reported as "no validate
    # check found" — fail-closed, but the message named the wrong cause, and a
    # gate that misdescribes why it blocked sends the next person to fix CI when
    # the real problem is the API response.
    #
    # `"" -> "empty"` because Fable round 2 caught the previous comment here
    # asserting something the code did not do: an empty-string conclusion was
    # claimed to be handled, but it emitted a BLANK LINE, and a blank first
    # non-success match fails the `-n` test below and reads as green. GitHub's
    # conclusion is null or a fixed enum, so the payload is unreachable — but the
    # claim was false, which is this repo's tracked defect class. Mapping it to a
    # non-empty token makes the sentence true instead of deleting it.
    if ! VALIDATE_CONCLUSIONS=$(printf '%s' "$CHECK_RUNS" | jq -rs '
        [ .[]
          | if   (type == "object" and has("check_runs")) then .check_runs[]
            elif (type == "array")                        then .[]
            else . end ]
        | map(select(type == "object" and (.name? == "validate")))
        | .[] | (.conclusion // "pending") | if . == "" then "empty" else . end
    ' 2>/dev/null); then
        echo "FAILED CLOSED: could not parse the check-runs response for $HEAD_SHA as JSON, so CI status is unknown." >&2
        exit 1
    fi
    if [ -z "$VALIDATE_CONCLUSIONS" ]; then
        echo "BLOCKED: no CI 'validate' check found for $HEAD_SHA. NOT WAIVABLE — --user-approved cannot clear this. Fix CI." >&2
        exit 1
    fi
    NOT_GREEN=$(printf '%s\n' "$VALIDATE_CONCLUSIONS" | grep -v '^success$' | head -1 || true)
    if [ -n "$NOT_GREEN" ]; then
        echo "BLOCKED: a CI 'validate' check for $HEAD_SHA concluded '$NOT_GREEN', not green (must be exactly 'success' — pending/skipped/neutral/failure all block; ALL runs of that name must be green, not just the first). NOT WAIVABLE — --user-approved cannot clear this. Fix CI." >&2
        exit 1
    fi

    # --- Clearance artifact check ---
    #
    # WHAT --user-approved MAY AND MAY NOT WAIVE. Every message in this block
    # already says "explicit user confirmation is required" — they are process
    # requirements, and a human is the thing they are asking for. So the flag
    # waives them.
    #
    # It does NOT waive the two checks above: a red CI 'validate' and a
    # net-removal of test files. Those are not paperwork, they are objective
    # statements about whether the code works and whether the evidence that it
    # works still exists. "The tests are failing" and "the tests are gone" are
    # not decisions a human gets to override from a shell flag; fix them or
    # merge in the browser and own it. Keep that split when adding gates.
    CLEARANCE_FILE=".reviews/merge-clearance-$PR_NUM.json"
    if [ -n "$USER_APPROVED_REASON" ]; then
        WAIVED_PATHS="$WAIVED_PATHS clearance-artifact checks (.reviews/merge-clearance-$PR_NUM.json)
"
        echo "USER-APPROVED OVERRIDE: skipping the clearance-artifact checks — they exist to demand a human decision, and one was given. The CI-green and test-removal checks above still ran and passed; those are NOT waivable." >&2
    else
        if [ ! -f "$CLEARANCE_FILE" ]; then
            echo "BLOCKED: no clearance artifact found at $CLEARANCE_FILE. Run the full cross-model review protocol and write this file, or decide it yourself with --user-approved \"<reason>\"." >&2
            exit 1
        fi
        # ROUND 2 (Sol): A NESTED KEY IS NOT A CONTRACT FIELD.
        #
        # Every field below was read as "the first `"name":` anywhere in the
        # file". JSON nesting made that wrong: an object placed ahead of the
        # real field supplies the value the gate compares, and the field the
        # certification actually declares is never read at all.
        #
        # Executed against base_sha: live base moved to a different commit,
        # `"metadata": {"base_sha": "<live>"}` ahead of a stale top-level
        # `"base_sha": "<old>"`. The nested value matched the live base, the
        # ancestry check passed, and it merged at exit 0 — #636's hole reopened
        # by the parser that reads its fix.
        #
        # It backed status, round, sha, candidate_tree, base_tree, base_sha and
        # review_file identically, so this is fixed ONCE, here, rather than
        # seven times: project the artifact down to depth 1 and read every
        # contract field from the projection. A nested object collapses to `{}`
        # and its keys cease to exist as far as the gate is concerned.
        #
        # The walk is string-aware — a brace inside a quoted value is data, not
        # structure — and escape-aware, so a `\"` does not end a string early.
        # awk rather than a regex because nesting is not a regular language;
        # any "strip the inner braces" pattern is defeated by one more level.
        # ROUND 3 (Fable + Sol, converging; DESIGN ESCALATION): STOP
        # REIMPLEMENTING JSON.
        #
        # Rounds 1-3 produced twelve-plus executed artifacts that merged at
        # exit 0, and every single one was a JSON-GRAMMAR case: nesting,
        # greedy matching, a `]` inside a string, duplicate keys, keys
        # smuggled through `\uXXXX` escapes, an unterminated string, trailing
        # garbage, a numeric token read as a digit prefix. Each round patched
        # the case it was shown and the next round found the next one. That is
        # not a hardening backlog, it is the cost curve of hand-writing a JSON
        # parser in awk and sed — there is always one more case, and both
        # reviewers are now hunting specifically here.
        #
        # THE "NO jq AT THE MERGE BOUNDARY" PREMISE THAT FORCED THE HAND
        # PARSER IS FALSE, and it was false in this same file: line 133
        # already refuses to run without jq. This script is repo-local and
        # never ships (see CLAUDE.md) — the zero-dependency rule protects
        # consumers, and this has none. python3 is a documented dependency of
        # this repo's own test suite.
        #
        # python3 rather than jq for one specific reason: jq resolves
        # duplicate keys silently (last wins) and cannot report them, and
        # duplicates were the single largest defect class across rounds 2 and
        # 3. `object_pairs_hook` sees the raw pair list and can refuse.
        #
        # What this deletes, rather than patches:
        #   - depth tracking, and every desync that let a nested key print as
        #     a top-level one (a whole-file parse has no depth counter to
        #     desync, and refuses the file outright if it does not parse)
        #   - first-wins vs last-wins ambiguity, for EVERY key at EVERY depth
        #   - escape smuggling: `reviewers` IS `reviewers` once decoded,
        #     so an escaped duplicate arrives at the hook as a duplicate
        #   - digit-prefix number reads: 0.5 is a float and is refused as a
        #     findings count, rather than parsing as its leading `0`
        #
        # THE CONTRACT IS UNCHANGED. Two or more reviewers, all clean, none
        # dirty; a declared verdict must be CERTIFIED; absence fails closed;
        # round >= 2 remains a route this branch never touches. Only the
        # extraction moved.
        if ! command -v python3 >/dev/null 2>&1; then
            echo "FAILED CLOSED: python3 is required to parse the clearance artifact. A grep fallback is exactly the parser this replaced, so there is not one." >&2
            exit 1
        fi
        CLEARANCE_PARSED=$(python3 -c '
import json, re, sys

path = sys.argv[1]

def no_dupes(pairs):
    seen = set()
    for k, _ in pairs:
        if k in seen:
            # Reported at any depth. A duplicate anywhere means the artifact
            # has two meanings and parsers disagree about which one is the
            # certification — the gate refuses rather than picking.
            raise ValueError("declares the key %r more than once" % k)
        seen.add(k)
    return dict(pairs)

def refuse_constant(c):
    raise ValueError("uses the non-JSON constant %s" % c)

try:
    with open(path) as fh:
        doc = json.load(fh, object_pairs_hook=no_dupes, parse_constant=refuse_constant)
except ValueError as exc:
    # json.JSONDecodeError subclasses ValueError, so an unbalanced structure,
    # an unterminated string and trailing garbage all land here alongside the
    # duplicate-key refusal above.
    sys.stderr.write("%s\n" % exc)
    sys.exit(2)

if not isinstance(doc, dict):
    sys.stderr.write("is not a JSON object\n")
    sys.exit(2)

_HEX = re.compile(r"[0-9a-f]{40}|[0-9a-f]{64}")

def _is_object_name(v):
    # SHA-1 today, SHA-256 accepted so a git object-format migration refuses
    # nothing legitimate. Both are fixed-width lowercase hex.
    return _HEX.fullmatch(v) is not None

# `review_file` HAS NO GRAMMAR HERE, deliberately. See the comment at the
# `[ -s ]` check in the shell for why a path grammar on that field is theatre.
FIELD_GRAMMAR = {
    "sha": _is_object_name,
    "candidate_tree": _is_object_name,
    "base_tree": _is_object_name,
    "base_sha": _is_object_name,
}
FIELD_KIND = {
    "sha": "git object name",
    "candidate_tree": "git object name",
    "base_tree": "git object name",
    "base_sha": "git object name",
}

out = []
def emit(key, value):
    # The projection is a tab-separated channel and the shell reads it back one
    # line at a time with `head -1`. Two different attacks live here and BOTH are
    # closed by refusing the whole control-character class rather than an
    # enumerated set of separators:
    #
    #   tab / newline — inject extra rows. Rows injected through a string field
    #   precede the derived counts emitted at the end, so an artifact declaring
    #   no reviewers at all forged "2 reviewers, zero findings".
    #
    #   NUL — needs no separator. It is legal JSON, python emits it, and the
    #   shell DELETES it from a command substitution, so "CERT\0IFIED" and a
    #   commit sha split by a NUL both normalise to the live value only AFTER
    #   the parse. What a JSON reader sees in the artifact is then not what the
    #   gate compares.
    #
    # An enumerated set missed NUL, which is the same mistake in miniature that
    # the hand-written parser kept making: enumerate the cases and the next case
    # is the one you did not list. Every contract field is a sha, a path, or a
    # status word, so no C0 control character or DEL is ever legitimate in one.
    if isinstance(value, str) and any(ord(c) < 0x20 or ord(c) == 0x7F for c in value):
        sys.stderr.write("field %r contains a control character\n" % key)
        sys.exit(2)
    # THE CLASS REFUSAL ABOVE IS DEFENCE IN DEPTH, NOT THE GUARD. It refuses
    # what is known to be dangerous, so it fails OPEN whenever that knowledge is
    # incomplete — which it was twice, at {tab, newline, CR} and again before
    # NUL was added. The guard proper is below and runs the other way round: a
    # field must MATCH what it is, so anything unanticipated fails CLOSED. It
    # also does not depend on modelling shell byte semantics at all, and stays
    # correct if one of these values later reaches a different sink.
    if isinstance(value, str) and value and key in FIELD_GRAMMAR:
        if not FIELD_GRAMMAR[key](value):
            sys.stderr.write("field %r is not a well-formed %s\n" % (key, FIELD_KIND[key]))
            sys.exit(2)
    out.append("%s\t%s" % (key, value))

for key in ("status", "sha", "candidate_tree", "base_tree", "base_sha", "review_file"):
    value = doc.get(key)
    # A non-string where a string is required is reported as absent: the
    # shell already fails closed on absence with a message naming the field,
    # and inventing a second refusal for "present but wrong type" would say
    # the same thing twice.
    emit(key, value if isinstance(value, str) else "")

# bool is an int in Python and `true` is not a round number.
rnd = doc.get("round")
emit("round", rnd if isinstance(rnd, int) and not isinstance(rnd, bool) else "")

reviewers = doc.get("reviewers")
reviewer_count = clean_count = dirty_count = 0
if isinstance(reviewers, list):
    for entry in reviewers:
        if not isinstance(entry, dict):
            # Still a reviewer, never a clean one — the same direction as an
            # entry that omits its count.
            reviewer_count += 1
            continue
        reviewer_count += 1
        if "verdict" in entry and entry["verdict"] != "CERTIFIED":
            continue
        total = entry.get("findings_total")
        if not isinstance(total, int) or isinstance(total, bool) or total < 0:
            continue
        if total == 0:
            clean_count += 1
        else:
            dirty_count += 1
emit("reviewer_count", reviewer_count)
emit("clean_count", clean_count)
emit("dirty_count", dirty_count)

# ROUND CAP. The gate had a floor and no ceiling. Past round 3 a clearance
# carries a per-round history and a recorded reason for every extra round.
#
#   "rounds": [{"round": 1, "findings_total": N}, ...]  one per round, in
#       order, length == round. From round 3 on, each findings_total is
#       strictly below the one before.
#   "scope_decisions": [{"round": R, "reason": "..."}, ...]  for every R in
#       4..round, at least one entry with a non-blank reason and no decision
#       other than "continue". Scopes append, so other entries are ignored.
#
# BOTH ARE READ ONLY PAST ROUND 3. At rounds 1-3 nothing new is required, and
# older artifacts already use a top-level "rounds" key for other things
# (merge-clearance-597.json is a dialogue log), so reading it there would
# refuse clearances that were valid.
#
# The verdict is decided HERE and crosses the TSV channel as a fixed token. A
# reason is free text and never reaches the shell.
def is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)

round_cap = "ok"
if is_int(rnd) and rnd > 3:
    rounds = doc.get("rounds")
    if rounds is None:
        round_cap = "no_rounds"
    else:
        if not isinstance(rounds, list) or len(rounds) != rnd:
            sys.stderr.write("rounds must be a list of %d entries, one per round\n" % rnd)
            sys.exit(2)
        for i, entry in enumerate(rounds, 1):
            if not (isinstance(entry, dict) and is_int(entry.get("round")) and entry["round"] == i
                    and is_int(entry.get("findings_total")) and entry["findings_total"] >= 0):
                sys.stderr.write("rounds entry %d is not {\"round\": %d, \"findings_total\": <count>}\n" % (i, i))
                sys.exit(2)
        for r in range(3, rnd + 1):
            if rounds[r - 1]["findings_total"] >= rounds[r - 2]["findings_total"]:
                round_cap = "not_falling %d" % r
                break
    if round_cap == "ok":
        decisions = doc.get("scope_decisions")
        if not isinstance(decisions, list):
            decisions = []
        for r in range(4, rnd + 1):
            if not any(isinstance(d, dict) and is_int(d.get("round")) and d["round"] == r
                       and d.get("decision", "continue") == "continue"
                       and isinstance(d.get("reason"), str) and d["reason"].strip()
                       for d in decisions):
                round_cap = "no_reason %d" % r
                break
emit("round_cap", round_cap)

sys.stdout.write("\n".join(out))
' "$CLEARANCE_FILE" 2>&1) || {
            echo "BLOCKED: $CLEARANCE_FILE does not parse as a certification — $CLEARANCE_PARSED. A file the gate cannot read one way is not a clearance. Explicit user confirmation is required: --user-approved \"<reason>\"." >&2
            exit 1
        }
        # One line per key, so the first match is the only match.
        cl_field() {
            printf '%s\n' "$CLEARANCE_PARSED" | sed -n "s/^$1	//p" | head -1
        }
        CL_STATUS=$(cl_field status)
        if [ "$CL_STATUS" != "CERTIFIED" ]; then
            echo "BLOCKED: $CLEARANCE_FILE status is '${CL_STATUS:-missing}', not CERTIFIED. Explicit user confirmation is required: --user-approved \"<reason>\"." >&2
            exit 1
        fi
        CL_ROUND=$(cl_field round)
        if [ -z "$CL_ROUND" ] || [ "$CL_ROUND" -lt 2 ]; then
            # #563: THE ONE CASE WHERE round >= 2 IS BACKWARDS.
            #
            # The round>=2 rule is sound and stays: one round is usually a
            # rubber stamp, and the dialogue is where review actually happens.
            # But it conflates "a dialogue happened" with "the review was
            # adversarial", and those come apart in exactly one place — both
            # reviewers certify at round 1 having found NOTHING to dispute.
            #
            # PR #562 is the measured instance: Sol zero at every severity at
            # 99%, Fable zero at every severity at 97%, both verifying the
            # evidence against primary sources independently. The only way to
            # satisfy the gate from there was to re-invoke both reviewers and
            # ask them to re-verify nothing — ceremony that increments a counter
            # and buys no signal. Two independent clean certifications is
            # STRONGER evidence than one two-round dialogue, and the gate read
            # it as weaker.
            #
            # The exemption is mechanical — it reads integers, never prose — and
            # deliberately narrow: TWO OR MORE reviewers, EVERY one at
            # findings_total 0. One finding at any severity, from any reviewer,
            # and the recheck round is owed as before.
            #
            # ABSENCE IS NOT ZERO. Every artifact written before #563 carries no
            # findings_total, and silence about findings must never read as an
            # assertion that there were none, or the exemption applies
            # retroactively to certifications that never claimed it.
            #
            # Trust boundary unchanged and worth stating: the agent writes this
            # artifact, so the counts are ATTESTED, not authenticated — exactly
            # the standing of `round` itself. This does not widen that gap.
            # COUNTED PER REVIEWER ENTRY, NOT PER OCCURRENCE. Round 1 of this
            # review found the first version grepped every `findings_total` in
            # the file and never checked the match belonged to a reviewer.
            # Two counterexamples were executed against it, both merging at
            # exit 0: an artifact with ZERO reviewer entries and two stray
            # `findings_total: 0` keys elsewhere, and one with two clean
            # reviewers plus a third that omits the field entirely. Counting
            # occurrences answers "are there two zeros in this file", which is
            # not the question.
            #
            # Every entry must carry its own zero. An entry with no
            # `findings_total` counts as a reviewer and NOT as a clean one, so
            # partial absence blocks.
            #
            # ROUND 3: the counting moved into the strict parse above, with the
            # slicing-and-splitting it replaced. Three rounds of executed
            # counterexamples all defeated the EXTRACTION, never the contract —
            # a regex slice truncating at the first `]`, a greedy prefix taking
            # the last `"reviewers":[` in the file, a `]` inside a quoted value,
            # duplicate keys resolved by position, escaped duplicate keys, a
            # float read as its leading digit. The parser answers all of them
            # structurally: entries are entries because the JSON says so, a
            # findings count is an integer or it is not a count, and a verdict
            # is the value of the verdict key.
            REVIEWER_COUNT=$(cl_field reviewer_count)
            CLEAN_COUNT=$(cl_field clean_count)
            DIRTY_COUNT=$(cl_field dirty_count)
            # EVERY reviewer clean, and at least two of them. `CLEAN_COUNT -eq
            # REVIEWER_COUNT` is what closes the partial-absence hole: an entry
            # that says nothing is counted but never cleared, so it can only
            # ever refuse.
            if [ "$CL_ROUND" = "1" ] && [ "$REVIEWER_COUNT" -ge 2 ] \
                && [ "$CLEAN_COUNT" -eq "$REVIEWER_COUNT" ] && [ "$DIRTY_COUNT" -eq 0 ]; then
                echo "NOTE: round=1 accepted — $CLEAN_COUNT reviewers each certified with zero findings at every severity (#563). A recheck round would have nothing to be about." >&2
            else
                echo "BLOCKED: $CLEARANCE_FILE shows round=${CL_ROUND:-missing} — a round-1-only CERTIFIED is treated as an insufficient dialogue (real adversarial review takes at least one recheck round). The one exemption is two or more reviewers each recording findings_total=0; this artifact declares $REVIEWER_COUNT reviewer entries, $CLEAN_COUNT of them recording zero findings and $DIRTY_COUNT recording findings — an entry that records nothing counts toward neither (#563). Explicit user confirmation is required: --user-approved \"<reason>\"." >&2
                exit 1
            fi
        fi
        # ROUND CAP: the ceiling to the floor above. Decided in the parse; see
        # the comment there for the shape. Anything but a known token refuses.
        CL_ROUND_CAP=$(cl_field round_cap)
        case "$CL_ROUND_CAP" in
            ok) ;;
            no_rounds)
                echo "BLOCKED: $CLEARANCE_FILE is at round $CL_ROUND but declares no 'rounds'. Past round 3 a clearance records findings_total per round: \"rounds\": [{\"round\": 1, \"findings_total\": N}, ...]. Explicit user confirmation is required: --user-approved \"<reason>\"." >&2
                exit 1 ;;
            "not_falling "*)
                echo "BLOCKED: $CLEARANCE_FILE findings_total did not fall at round ${CL_ROUND_CAP#not_falling }. After round 2 every round must find strictly fewer than the one before, or the loop is not converging. Explicit user confirmation is required: --user-approved \"<reason>\"." >&2
                exit 1 ;;
            "no_reason "*)
                echo "BLOCKED: $CLEARANCE_FILE has no scope_decisions reason for round ${CL_ROUND_CAP#no_reason }. Past round 3 every extra round needs a recorded continue reason: \"scope_decisions\": [{\"round\": ${CL_ROUND_CAP#no_reason }, \"reason\": \"...\"}]. Explicit user confirmation is required: --user-approved \"<reason>\"." >&2
                exit 1 ;;
            *)
                echo "BLOCKED: $CLEARANCE_FILE produced no round-cap verdict ('${CL_ROUND_CAP}'). Explicit user confirmation is required: --user-approved \"<reason>\"." >&2
                exit 1 ;;
        esac
        CL_SHA=$(cl_field sha)
        if [ "$CL_SHA" != "$HEAD_SHA" ]; then
            echo "BLOCKED: $CLEARANCE_FILE is stale — its sha ($CL_SHA) does not match the current remote head ($HEAD_SHA). New commits landed since certification. Explicit user confirmation is required: --user-approved \"<reason>\"." >&2
            exit 1
        fi
        # #540, THE MERGE BOUNDARY. The hook cannot close this hole alone:
        # PreToolUse cannot observe post-command state, so a pre-commit check
        # can only speak for the index it saw. This is where the object that
        # actually merges is available, and it is checked against the content
        # the reviewers read.
        #
        # WHY THIS AND NOT THE SHA CHECK ABOVE. The sha check is correct and
        # stays — it is what keeps CI freshness honest. But a SHA answers "is
        # this the same commit", and what a review certifies is CONTENT. Those
        # come apart in both directions: a message-only amend changes the SHA
        # while changing nothing reviewable (the ~10-wasted-tool-call re-pin
        # tax), and a rebase onto moved upstream can preserve a diff while
        # producing a tree nobody read.
        #
        # WHY NOT patch-id, which an earlier ruling chose. Measured, then
        # amended by both advisors: two diffs differing only in the indentation
        # of an added Python line produce the IDENTICAL patch-id, because
        # patch-id ignores whitespace by design and whitespace is semantic in
        # Python, YAML, Makefiles and string literals. And the thing merged
        # here is the resulting TREE, not the diff.
        #
        # base_tree is checked too, and this is the half the hook deliberately
        # does NOT do. At the commit boundary "the base" is unobservable
        # without knowing whether the commit is an amend — which means reading
        # git's option grammar off a command line, the #610 trap. Here the base
        # ref is well-defined, so the check lands where it is answerable.
        #
        # Fails closed on a missing field: an artifact naming no content is the
        # pre-#540 format, and honouring it would be the hole reopened under an
        # older key.
        CL_CAND_TREE=$(cl_field candidate_tree)
        if [ -z "$CL_CAND_TREE" ]; then
            echo "BLOCKED: $CLEARANCE_FILE declares no 'candidate_tree'. A certification names the content it was issued over, not just the commit it happened to sit on (#540). Record it with: git rev-parse 'HEAD^{tree}'. Explicit user confirmation is required: --user-approved \"<reason>\"." >&2
            exit 1
        fi
        REMOTE_TREE=$(git rev-parse "$HEAD_SHA^{tree}" 2>/dev/null) || REMOTE_TREE=""
        if [ -z "$REMOTE_TREE" ]; then
            # The object is not local — fetch it rather than guessing. A tree
            # we cannot read is not a tree we can clear.
            git fetch -q origin "$HEAD_SHA" 2>/dev/null || true
            REMOTE_TREE=$(git rev-parse "$HEAD_SHA^{tree}" 2>/dev/null) || REMOTE_TREE=""
        fi
        if [ -z "$REMOTE_TREE" ]; then
            echo "BLOCKED: could not read the tree of the remote head $HEAD_SHA, so the merging content cannot be compared against what was certified. Explicit user confirmation is required: --user-approved \"<reason>\"." >&2
            exit 1
        fi
        if [ "$REMOTE_TREE" != "$CL_CAND_TREE" ]; then
            echo "BLOCKED: the content about to merge is not the content that was certified — remote head tree $REMOTE_TREE, certified candidate_tree $CL_CAND_TREE (#540). Explicit user confirmation is required: --user-approved \"<reason>\"." >&2
            exit 1
        fi
        # base_tree pins WHICH BASE the reviewers read. A rebase onto moved
        # upstream can leave candidate_tree untouched while the integration
        # result changes, which is the second measurement that killed patch-id.
        CL_BASE_TREE=$(cl_field base_tree)
        if [ -z "$CL_BASE_TREE" ]; then
            echo "BLOCKED: $CLEARANCE_FILE declares no 'base_tree'. A certification names the base it was read against, or a rebase onto moved upstream carries it silently (#540). Record it with: git rev-parse \"origin/\$BASE_BRANCH^{tree}\". Explicit user confirmation is required: --user-approved \"<reason>\"." >&2
            exit 1
        fi
        # $BASE_SHA is the base branch's CURRENT tip, read from the server
        # above. Resolved here with the same fetch-fallback and the same
        # fail-closed posture as the remote head. A base we cannot read is not
        # a base we can clear against.
        CUR_BASE_TREE=$(git rev-parse "$BASE_SHA^{tree}" 2>/dev/null) || CUR_BASE_TREE=""
        if [ -z "$CUR_BASE_TREE" ]; then
            git fetch -q origin "$BASE_SHA" 2>/dev/null || true
            CUR_BASE_TREE=$(git rev-parse "$BASE_SHA^{tree}" 2>/dev/null) || CUR_BASE_TREE=""
        fi
        if [ -z "$CUR_BASE_TREE" ]; then
            echo "BLOCKED: could not read the tree of the base commit $BASE_SHA ($BASE_BRANCH), so the base the reviewers read cannot be compared against the base this would merge into. Explicit user confirmation is required: --user-approved \"<reason>\"." >&2
            exit 1
        fi
        if [ "$CUR_BASE_TREE" != "$CL_BASE_TREE" ]; then
            echo "BLOCKED: the base moved since certification — $BASE_BRANCH tree is $CUR_BASE_TREE, certified base_tree is $CL_BASE_TREE. The reviewers read a different base, and the merged result is not what they cleared (#540). Rebase and re-review, or decide it yourself: --user-approved \"<reason>\"." >&2
            exit 1
        fi
        # #636: A TREE CARRIES NO ANCESTRY, AND base_tree IS A TREE.
        #
        # #540 replaced SHA identity with content identity, and that was right.
        # But it bound the content at the two ENDPOINTS and modelled the base as
        # a tree. The base is a POSITION IN A HISTORY. A PR diff is three-dot,
        # so what actually merges depends on the MERGE BASE — and the merge base
        # can move while `sha`, `candidate_tree` and `base_tree` are all still
        # byte-identical.
        #
        # The case, reproduced with real git objects during #521's design
        # review rather than argued: main takes a commit the PR also contains,
        # then REVERTS it. Main's tree returns byte-for-byte to what the
        # reviewers read, so base_tree matches. The PR head never moved, so
        # candidate_tree matches. But the merge base advanced past the reverted
        # commit, so the PR now contributes only the part the revert did not
        # undo. Measured: reviewed base tree == live base tree, candidate tree
        # matched, and `git merge-tree` produced a prospective merge containing
        # HALF the reviewed content. Every check above passed. It merged at
        # exit 0.
        #
        # base_sha is the conservative fix: it subsumes base_tree entirely
        # (same commit implies same tree), so the tree check above is now
        # strictly redundant. It is kept anyway — removing it is contract churn
        # for no safety gain, and its refusal message is the more legible one
        # when a genuine rebase is what moved.
        #
        # Fails closed when absent, for the same reason candidate_tree does: an
        # artifact that says nothing about the base is the pre-#636 format, and
        # honouring it leaves the hole open forever behind an omitted field.
        # Nothing live breaks — clearances are per-PR and written fresh.
        CL_BASE_SHA=$(cl_field base_sha)
        if [ -z "$CL_BASE_SHA" ]; then
            echo "BLOCKED: $CLEARANCE_FILE declares no 'base_sha'. A tree carries no ancestry, so base_tree alone cannot tell a moved base from a still one — a revert returns the base tree to its old value while the merge base advances (#636). Record it with: git rev-parse \"origin/\$BASE_BRANCH\". Explicit user confirmation is required: --user-approved \"<reason>\"." >&2
            exit 1
        fi
        if [ "$CL_BASE_SHA" != "$BASE_SHA" ]; then
            echo "BLOCKED: the base branch moved since certification — $BASE_BRANCH is at $BASE_SHA, certified base_sha is $CL_BASE_SHA. The trees may still match (a revert does exactly that), but the merge base moved, so what merges is not what was reviewed (#636). Rebase and re-review, or decide it yourself: --user-approved \"<reason>\"." >&2
            exit 1
        fi
        CL_REVIEW_FILE=$(cl_field review_file)
        # EXISTENCE AND NON-EMPTINESS IS THE WHOLE CHECK, ON PURPOSE. Nothing
        # binds this file's CONTENT to this PR, this round, or these reviewers,
        # so any non-empty tracked file satisfies it — `README.md` does. That
        # makes every question about the path's PEDIGREE theatre: refusing a
        # path that escapes the repository denies an artifact author nothing,
        # because the identical check is satisfied by a file already inside it.
        #
        # A grammar and a realpath containment check lived here for three review
        # rounds and were deleted (#645). They bought no security property any
        # test could state, and they cost false refusals — a legal `-review.md`,
        # a legitimate in-repo symlink, and any invocation from a subdirectory
        # were all blocked. A false refusal in a merge gate is worse than dead
        # code: it trains `--user-approved` overrides and erodes the gate it
        # lives in. Do not re-add a path check here. The real fix is to bind the
        # CONTENT — a digest in the artifact, or a file that must name the sha
        # and round — and that is #645, not a spelling rule.
        #
        # `review_file`'s in-scope surface is the projection channel, and the
        # control-character class refusal in emit() still covers that.
        if [ -z "$CL_REVIEW_FILE" ] || [ ! -s "$CL_REVIEW_FILE" ]; then
            echo "BLOCKED: $CLEARANCE_FILE's referenced review artifact ('$CL_REVIEW_FILE') is missing or empty — can't verify the dialogue was substantive. Explicit user confirmation is required: --user-approved \"<reason>\"." >&2
            exit 1
        fi
    fi

# --- Durable override record, BEFORE the merge ---
#
# The reason used to go to stderr only, so it evaporated with the session. That
# made the flag's entire justification false: it was sold as replacing a
# browser click that "leaves no record in the repo" with a logged override, and
# PR #494 was merged with it leaving exactly zero durable trace — no comment, no
# artifact, indistinguishable from any token merge. Found by cross-model review.
#
# Posted BEFORE the merge deliberately: if the comment fails, the merge does not
# happen. An unrecorded override is the thing this exists to prevent, so failing
# to record it must block rather than proceed silently.
if [ -n "$USER_APPROVED_REASON" ]; then
    OVERRIDE_BODY=$(printf '**USER-APPROVED MERGE OVERRIDE**\n\n**Reason:** %s\n\n**Waived** (would otherwise have blocked):\n%s\n\n**Still verified, not waivable:** CI `validate` green, no net-removed test files.\n\nHead: `%s`\n\n_Posted by `scripts/merge-pr.sh --user-approved` before merging. This flag does not prove a human authored it; it makes an override explicit and durable instead of silent._' \
        "$USER_APPROVED_REASON" \
        "$(printf '%s\n' "$WAIVED_PATHS" | sed '/^$/d' | sed 's/^/- `/; s/$/`/')" \
        "$HEAD_SHA")
    if ! gh pr comment -R github.com/BaseInfinity/claude-sdlc-harness "$PR_NUM" --body "$OVERRIDE_BODY" >/dev/null 2>&1; then
        echo "BLOCKED: could not post the override record to PR #$PR_NUM. Refusing to merge — an unrecorded override is precisely what --user-approved exists to prevent." >&2
        exit 1
    fi
    echo "Override recorded on PR #$PR_NUM." >&2
fi

# Same treatment for the dual path (Fable round 1). Its conclusions — the gate
# byte-matched origin/main, the artifact was CERTIFIED at round >= 2, these two
# reviewers cleared this SHA — were stdout only, so they evaporated with the
# session. That is the defect already fixed once for --user-approved after PR
# #494 merged traceless, re-introduced on the new path. #511's whole argument is
# that the RECORD is the deliverable, so a dual merge that leaves none fails on
# its own terms. Posted BEFORE the merge, failing closed, for the same reason.
if [ -n "$DUAL_PATHS" ]; then
    DUAL_BODY=$(printf '**DUAL CROSS-MODEL CERTIFIED MERGE**\n\n**Cleared by:** %s — both bound to `%s`\n\n**Merge-evidence path(s) this authorised:**\n%s\n\n**Verified:** CI `validate` green across every run of that name; no net-removed test files; no `package.json` version bump; clearance artifact CERTIFIED at round >= 2 bound to this SHA; the executing merge script and its redirect hook byte-match `origin/main`.\n\n**ATTESTED, NOT AUTHENTICATED.** Both clearances were posted by the same `gh` token, so this records that two distinct reviewers returned YES at >=95 — not that two independent principals did. A new workflow file can still mint a green required check; the compensating layer is that both reviewers read this diff.\n\n_Posted by `scripts/merge-pr.sh --dual-certified` before merging._' \
        "$CLEARED_BY" \
        "$HEAD_SHA" \
        "$(printf '%s' "$DUAL_PATHS" | sed '/^$/d' | sed 's/^/- `/; s/$/`/')")
    if ! gh pr comment -R github.com/BaseInfinity/claude-sdlc-harness "$PR_NUM" --body "$DUAL_BODY" >/dev/null 2>&1; then
        echo "BLOCKED: could not post the dual-certification record to PR #$PR_NUM. Refusing to merge — a merge-evidence path cleared without a durable record is the exact gap #511 exists to close." >&2
        exit 1
    fi
    echo "Dual certification recorded on PR #$PR_NUM." >&2
fi

# --- Execute: always squash, no passthrough flags, atomically bound to the
# checked SHA. Only the PR number is accepted as input, closing the
# flag-smuggling surface entirely. ---
MERGE_OUTPUT=$(gh pr merge -R github.com/BaseInfinity/claude-sdlc-harness "$PR_NUM" --squash --match-head-commit "$HEAD_SHA" 2>&1)
MERGE_EXIT=$?
if [ "$MERGE_EXIT" -ne 0 ]; then
    echo "FAILED: gh pr merge did not succeed (possibly a race — head moved after checks passed): $MERGE_OUTPUT" >&2
    exit 1
fi

echo "$MERGE_OUTPUT"

# The success line must state what ACTUALLY happened. The first version printed
# "clearance CERTIFIED round>=2 fresh, denylist clear" unconditionally — so an
# override that skipped clearance and waived every denylist hit still produced
# an audit record claiming both were verified. A false claim in the audit trail
# is worse than no audit trail: it is the same defect class as a gate that reads
# evidence structure and never the verdict inside it. Found by cross-model
# review, 2026-08-05.
if [ -n "$USER_APPROVED_REASON" ]; then
    echo "MERGED: PR #$PR_NUM at $HEAD_SHA (squash, match-head-commit)."
    echo "  VERIFIED (not waivable): no test deletions, CI validate green."
    echo "  OVERRIDDEN by --user-approved: denylist tiers, version-bump confirmation, and the clearance-artifact checks were NOT verified — they were waived on the stated human decision."
    echo "  reason: $USER_APPROVED_REASON"
elif [ -n "$DUAL_PATHS" ]; then
    # GH #511. Says exactly what was proven and exactly what was not — the whole
    # point of the issue was that the previous records claimed the wrong thing.
    echo "MERGED: PR #$PR_NUM at $HEAD_SHA (squash, match-head-commit)."
    echo "  VERIFIED: no test deletions, CI validate green, no package.json version bump, clearance artifact CERTIFIED at round>=2 bound to this SHA, and this gate byte-matches origin/main."
    echo "  DUAL-CERTIFIED by $CLEARED_BY over merge-evidence path(s):"
    printf '%s' "$DUAL_PATHS" | sed '/^$/d; s/^/    - /'
    echo "  ATTESTED, NOT AUTHENTICATED: both clearances were posted by the same gh token. This proves two distinct reviewers returned YES at >=95 bound to $HEAD_SHA — not that two independent principals did."
else
    # Gate on CLEARED_BY, not on the FLAG. Passing a clearance flag on a PR that
    # touches no denylisted path never runs clearance, so CLEARED_BY is empty and
    # this line read "...and denylist acknowledged by ." — an acknowledgement by
    # nobody, in the audit record. Pre-existing, and exactly the failure mode this
    # change is about (Fable round 1).
    echo "MERGED: PR #$PR_NUM at $HEAD_SHA (squash, match-head-commit). Verified: no test deletions, CI validate green, clearance CERTIFIED round>=2 fresh, and $([ -n "$CLEARED_BY" ] && echo "denylist acknowledged by $CLEARED_BY" || echo 'denylist clear')."
fi
exit 0
