#!/bin/bash
# Launch a cross-model review leg so it cannot hang, and so its fate is its
# exit status (#590).
#
# Usage:
#   scripts/run-review-leg.sh OUTPUT_FILE PROMPT [EXTRA_CODEX_ARGS...]
#
# Run it as a background task. The task's exit status IS the leg's verdict:
# 0 completed, non-zero failed, nothing by your deadline means inspect and
# relaunch. There is no separate waiter to consult and nothing to poll.
#
# ---------------------------------------------------------------------------
# THE FAILURE
#
# `codex exec` reads stdin to EOF and appends it to the argv prompt — argv and
# stdin are concatenated, not alternatives. Handed a pipe nobody closes, it
# blocks on that read BEFORE contacting the model, forever. On 2026-08-13 two
# review legs were waited on for 51 and 28 minutes; the loop's "still working,
# or done?" decision was made twice against a process that had never started.
#
# ---------------------------------------------------------------------------
# WHY THERE IS NO WAITER HERE, AFTER TWO ATTEMPTS AT ONE
#
# The first attempt watched the output file and the process table from
# outside. Sol (GPT-5.6 high) falsified every signal with running code: `-o`
# output carries no completion marker; `tokens used` appears in codex's echoed
# prompt, so a crashed leg read as complete; an fd reported as PIPE may be at
# EOF and healthy; the hang's byte signature differs per machine (39 here, 143
# on another); and enumerating holders of the file counted readers, so a
# `tail -f` flipped the verdict.
#
# The second attempt recorded the child's pid and exit status in sidecar
# files for a waiter to read. Sol falsified that too: the child exits before
# the status is published, so a successful leg reads as dead; killing only the
# launcher leaves a status that can never arrive while the child pid still
# looks alive; a stale status from a previous run is read as this run's; and a
# reused pid is indistinguishable from the original process.
#
# Both are the same mistake in different clothes — a SECOND OBSERVER trying to
# reconstruct what the first process already knows. The launcher's own exit
# status is that knowledge, delivered by the process that has it. So the
# waiter is gone, and the sidecars with it: with no reader they were only a
# way to be stale.
#
# What remains is the part that actually prevents the failure: the child gets
# /dev/null on stdin, whatever this script inherited. Verified against real
# codex 0.147.0 with this script's own stdin on an unclosed fifo — the shape
# that reproduces a live hang — the leg completed normally.
#
# A leg typed ad hoc, outside this script, has no owner and no status. Its
# fate is unknown immediately; relaunch it through here rather than waiting on
# it. That is the one case detection was ever needed for, and it is prose in
# the skill, not a signal any code can soundly reconstruct.

set -e

if [ $# -lt 2 ]; then
    echo "usage: $0 OUTPUT_FILE PROMPT [EXTRA_CODEX_ARGS...]" >&2
    exit 64
fi

# Resolved from this script's own location, never from the caller's cwd: a leg
# is routinely launched from a worktree or a private review copy, and the schema
# it validates against must be the one that ships beside this launcher.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OUTPUT="$1"
shift

: > "$OUTPUT"

# ---------------------------------------------------------------------------
# THE BUILD GOES IN FRONT OF THE REVIEWER (#613)
#
# PR #610 ran EIGHT review rounds with two independent reviewers while CI
# `validate` was red the entire time. Both reviewers ran the test suites
# directly and correctly reported them green — the guard that was failing was
# one nobody was asked about, and the merge gate is what finally caught it.
# That is a gate step discovered mid-merge, which #593 Rung 1's stop condition
# names as a failure in so many words.
#
# Both reviewers then prescribed the same fix independently, and it is not more
# diff scrutiny: "Seven rounds audited the diff; zero audited the build."
#
# So the build is stated where the reviewer reads, BEFORE the model's own
# output. This is preflight, never a gate: a red build is REPORTED and the leg
# proceeds. Deliberately so — a leg must stay launchable against known-red CI
# when that is the point, and a preflight that can refuse to launch is a second
# way for a review to not happen, which is the failure #590 exists to prevent.
#
# Every failure mode of the probe is absorbed. No `gh`, no auth, no network, no
# PR for this branch: each records "unknown" and the review runs. `< /dev/null`
# for the same reason it is on the exec line below, and a timeout because a
# preflight that can hang has reintroduced #590 in the one place nobody would
# look for it.
{
    echo "## CI STATUS (preflight, #613)"
    echo
    # THE DEADLINE IS THIS SCRIPT'S OWN, and it depends on nothing.
    #
    # The first version reached for `timeout`, then fell back to running `gh`
    # bare when neither `timeout` nor `gtimeout` was present — which is stock
    # macOS, including this repo's own machine — on the reasoning that "gh
    # carries its own network timeouts."
    #
    # That was an unverified claim and it is FALSE: gh 2.92 configures no
    # overall HTTP timeout (cli/cli api/http_client.go, go-gh
    # pkg/api/client_options.go). A stalled request would block here forever,
    # before `exec codex` ever ran — #590, the precise failure this launcher
    # exists to prevent, reintroduced by the preflight added to prevent a
    # different one. The suite missed it because its stub always exited.
    #
    # So: no external timeout binary, and no trust in the child's own limits.
    # The probe runs in the background writing its exit status to a marker
    # file, and this loop waits a bounded number of seconds for that marker.
    #
    # A marker file rather than `kill -0` on the pid: a background job of this
    # shell stays a zombie until it is waited on, so `kill -0` reports it alive
    # after it has finished and the loop would never exit early. `wait -n`
    # would do it but needs bash 4, and macOS ships bash 3.2.
    CI_PROBE_TIMEOUT="${SDLC_CI_PROBE_TIMEOUT:-30}"
    CI_RAW="${TMPDIR:-/tmp}/sdlc-ci-probe.$$.out"
    CI_DONE="${TMPDIR:-/tmp}/sdlc-ci-probe.$$.done"
    rm -f "$CI_RAW" "$CI_DONE"
    # `set +e` inside the subshell is load-bearing: this script runs under
    # `set -e`, and a non-zero `gh` (which is exactly what a RED build is)
    # would otherwise kill the subshell before it wrote its marker. The probe
    # would then look stalled and burn the full deadline on every red build —
    # reporting "abandoned" for the one case it most needs to report. Caught by
    # the suite's red-build row regressing, not by reading this back.
    #
    # `set -m` is what makes the timeout path able to CLEAN UP. Without job
    # control a `( … ) &` subshell shares this shell's process group, so the
    # only thing killable by pid is the subshell itself — and killing that
    # leaves `gh` running, reparented to PID 1. Review ran the real fixture and
    # observed exactly that: the leg finished while the probe and its own child
    # stayed alive. An earlier version of this comment claimed the orphan
    # "exits on its own"; that was an unverified claim, and a genuinely stalled
    # `gh` never does. Repeated timeouts would leak processes, descriptors and
    # connections until a later leg could not launch.
    #
    # With job control the subshell becomes a process-group leader, so the
    # negative-pid kill below reaches the whole group: subshell, `gh`, and
    # anything `gh` spawned.
    set -m
    ( set +e; gh pr checks --required > "$CI_RAW" 2>&1 < /dev/null; echo $? > "$CI_DONE" ) &
    CI_PROBE_PID=$!
    set +m
    # `disown` or bash announces the kill in the reviewer's own output file:
    #   ./scripts/run-review-leg.sh: line N: 34945 Terminated: 15  ( set +e; gh …
    # printed by the shell's job-control notice, inside the CI STATUS block —
    # noise, exposing this script's internals, in the one block the PR exists to
    # make readable. Found by review running the real stall repro. The group
    # kill still works after disown (it addresses the process group, not the
    # job table) and the `wait` below absorbs the disowned-job error.
    disown "$CI_PROBE_PID" 2>/dev/null || true
    CI_WAITED=0
    while [ ! -f "$CI_DONE" ] && [ "$CI_WAITED" -lt "$CI_PROBE_TIMEOUT" ]; do
        sleep 1
        CI_WAITED=$((CI_WAITED + 1))
    done
    if [ -f "$CI_DONE" ]; then
        CI_RC=$(cat "$CI_DONE")
        CI_OUT=$(cat "$CI_RAW" 2>/dev/null || true)
    else
        # Kill the whole process GROUP, not the subshell. The negative pid is
        # the point — see the `set -m` note above. TERM first, then KILL for
        # anything that ignores it, then reap so no zombie survives us.
        kill -TERM -- "-$CI_PROBE_PID" 2>/dev/null || kill -TERM "$CI_PROBE_PID" 2>/dev/null || true
        sleep 1
        kill -KILL -- "-$CI_PROBE_PID" 2>/dev/null || kill -KILL "$CI_PROBE_PID" 2>/dev/null || true
        wait "$CI_PROBE_PID" 2>/dev/null || true
        CI_RC=124
        CI_OUT=""
        CI_TIMED_OUT=1
    fi
    rm -f "$CI_RAW" "$CI_DONE"
    if [ "${CI_TIMED_OUT:-0}" = "1" ]; then
        echo "UNKNOWN — the check probe did not return within ${CI_PROBE_TIMEOUT}s and was abandoned."
        echo "The build was NOT verified. Treat it as undetermined, not as green."
    elif [ "$CI_RC" = "0" ]; then
        echo "All required checks reported passing:"
        echo
        echo '```'
        echo "$CI_OUT"
        echo '```'
    else
        if [ -n "$CI_OUT" ]; then
            echo "NOT GREEN, or not determinable (gh exit $CI_RC). Raw output:"
            echo
            echo '```'
            echo "$CI_OUT"
            echo '```'
        else
            echo "UNKNOWN — \`gh pr checks\` produced nothing (exit $CI_RC)."
            echo "No PR for this branch, no auth, no network, or gh unavailable."
        fi
    fi
    echo
    echo "**A certification verdict issued over a build that is not green, or"
    echo "not determinable, is only valid if it says so and says why.** The"
    echo "build is an input to your verdict, not background noise."
    echo
    echo "---"
    echo
} >> "$OUTPUT" 2>&1

# THE STRUCTURED VERDICT (#617)
#
# The leg must answer two questions it kept not being asked: does this code
# deserve to exist (`shape`), and does each defective line trace to the issues
# under review (`target`). Five prose rules in skills/sdlc/SKILL.md each
# independently end rounds 6-8 of PR #646 — :136, :152, :163, :273, :166 — and
# none of them fired. All five addressed the DRIVER, the party with momentum.
# These two are answered by the REVIEWER, who has none, and the schema is what
# makes them unskippable rather than advisory.
#
# The schema lives under skills/, which SHIPS; this validator lives under
# scripts/, which does not (#594). A consumer therefore inherits the CONTRACT
# even though they do not yet inherit the ENFORCER. That asymmetry is
# deliberate and disclosed — it is not an oversight to be fixed by copying the
# rules into this file, which would create a second copy that drifts from the
# one consumers read.
SCHEMA="$SCRIPT_DIR/../skills/sdlc/review-verdict.schema.json"
VERDICT="$OUTPUT.verdict.json"

# TRUNCATED FOR THE SAME REASON THE TRANSCRIPT IS, and it was missed the first
# time. A relaunch whose leg exits 0 without emitting a verdict would otherwise
# validate the PREVIOUS run's answer and report this leg complete — a stale
# certification presented as a fresh one, which is the failure this whole file
# exists to prevent, reintroduced by the file added to prevent it. Found by
# review, not by the suite, because the suite tested the transcript and nobody
# extended that row to the sidecar.
rm -f "$VERDICT"

# `< /dev/null` is the whole prevention: the child gets EOF immediately and
# proceeds to the model. Keep it on this line — it is not incidental.
#
# NO `exec` HERE, AND THAT IS A DELIBERATE REVERSAL. It used to exec so the
# caller saw codex's own exit status with nothing in between. The property that
# mattered was never `exec` itself — it was that THE LAUNCHER'S EXIT STATUS IS
# THE LEG'S FATE, with no second observer reconstructing it. That property is
# preserved below: codex's status is captured and re-raised unchanged, and the
# only other way to exit non-zero is a verdict this script read itself.
# KILLING THIS SCRIPT MUST KILL THE LEG, and dropping `exec` broke that until
# the trap below existed. With `exec`, the launcher's pid WAS codex's, so a
# TERM to the task killed the review. Without it, review found by execution
# that a TERM to the launcher leaves codex ALIVE — still appending to $OUTPUT,
# and still able to write a verdict afterwards. That orphan is the stale-verdict
# channel from the other end: a late write lands in a path a relaunch has since
# truncated, and the next leg validates a verdict no one asked for.
#
# So codex runs in the background and this script waits on it, forwarding TERM
# and INT to the child first. `wait` returns >128 when interrupted by a signal,
# so the status is re-taken after the trap fires to get codex's real one.
# Written for bash 3.2 — macOS ships nothing newer.
set +e
codex exec \
    -m gpt-5.5 \
    -c 'model_reasoning_effort="xhigh"' \
    -s danger-full-access \
    --output-schema "$SCHEMA" \
    --output-last-message "$VERDICT" \
    "$@" \
    >> "$OUTPUT" 2>&1 < /dev/null &
CODEX_PID=$!
trap 'kill -TERM "$CODEX_PID" 2>/dev/null; wait "$CODEX_PID" 2>/dev/null; exit 143' TERM INT
wait "$CODEX_PID"
CODEX_RC=$?
trap - TERM INT
set -e

# A leg that never reached the model is a FAILED leg, not an invalid one. Report
# its own status and say nothing about the verdict, which was never written.
if [ "$CODEX_RC" -ne 0 ]; then
    exit "$CODEX_RC"
fi

# PRESENCE AND ENUM MEMBERSHIP ONLY. The validator must never judge whether a
# tag is CORRECT — that is a reading of the diff against the issues under
# review, which is the reviewer's job. A semantic validator here is how PR #598
# reached 22 rounds chasing regex over prose. A closed enum cannot chase
# synonyms; an English-meaning check can, forever.
if ! python3 "$SCRIPT_DIR/validate-review-verdict.py" "$VERDICT" "$SCHEMA" >> "$OUTPUT" 2>&1; then
    {
        echo
        echo "---"
        echo
        echo "## INCOMPLETE LEG (#617)"
        echo
        echo "The review ran, but its structured verdict did not answer the"
        echo "questions the contract requires — see the validator's reason above."
        echo "A leg that skipped \`shape\`, or returned a finding with no"
        echo "\`target\`, has not said whether the code should exist or whether"
        echo "it traces to the issues under review. Relaunch the leg; do not"
        echo "read the prose and fill the fields in yourself, which puts the"
        echo "answer back with the party that has momentum."
    } >> "$OUTPUT" 2>&1
    # 65 is not provably unique: codex's own status passes through unchanged,
    # so a 65 from codex would be indistinguishable from this one. Nothing
    # observed emits 65 from codex, so the collision is latent. Tracked in #649
    # rather than repaired here — it is out of scope for #617 and the fix is not
    # obviously the launcher's. Until then, the INCOMPLETE LEG block above is
    # what tells the two apart, by artifact rather than by status.
    exit 65
fi
