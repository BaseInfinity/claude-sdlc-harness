#!/bin/bash
# Tests for the review-leg launcher (#590).
#
# WHY THIS SUITE IS SHORT
#
# Two earlier designs put a second process in charge of deciding whether a leg
# was alive — first by reading the output file and the process table, then by
# reading pid/exit sidecars. Sol (GPT-5.6 high) falsified both with running
# code, and the tests for them were elaborate because the subject was
# unsound: fixtures had to simulate blocked reads, publication races, stale
# state and pid reuse.
#
# There is no second observer now. The launcher's own exit status is the
# verdict, delivered by the process that has it. What is left to test is what
# the launcher itself promises: the child gets EOF on stdin no matter what the
# launcher inherited, the child's exit status reaches the caller unchanged,
# and the output lands where it was asked to.
#
# The stub `codex` reads stdin to EOF, exactly as the real one does, so any
# test that finishes at all is proof the launcher supplied that EOF.

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/run-review-leg.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAIL=$((FAIL + 1)); }

check_rc() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$actual" -eq "$expected" ]; then
        pass "$desc"
    else
        fail "$desc (expected exit $expected, got $actual)"
    fi
}

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/run-review-leg-tests.XXXXXX") || {
    echo "FATAL: could not create a temp dir; refusing to run in the caller's repo" >&2
    exit 1
}
trap 'rm -rf "$TMPROOT"' EXIT

# Stub codex on PATH:
#   STUB_EXIT        exit status to return
#   STUB_STDOUT      text to print
#   STUB_READ_STDIN  read stdin to EOF first — the real codex behaviour behind
#                    the hang, so a launcher that fails to supply EOF blocks
#                    here forever instead of quietly passing.
STUBDIR="$TMPROOT/bin"
mkdir -p "$STUBDIR"
#   STUB_NO_VERDICT  skip writing the structured verdict, simulating a leg that
#                    ran but did not answer the #617 contract
#   STUB_VERDICT     verdict JSON to write instead of the conforming default
cat > "$STUBDIR/codex" <<'STUB'
#!/bin/bash
if [ -n "$STUB_READ_STDIN" ]; then
    cat > /dev/null
fi
# The real codex writes the structured verdict to --output-last-message (#617).
# The stub must do the same, or every row here would assert on a launcher whose
# validation step never had input — a test that passes because the thing it
# tests never ran is the defect this repo files as #642.
VERDICT_PATH=""
SCHEMA_ARG=""
MODEL_ARG=""
prev=""
for arg in "$@"; do
    if [ "$prev" = "--output-last-message" ]; then VERDICT_PATH="$arg"; fi
    if [ "$prev" = "--output-schema" ]; then SCHEMA_ARG="$arg"; fi
    if [ "$prev" = "-m" ]; then MODEL_ARG="$arg"; fi
    prev="$arg"
done
[ -n "${STUB_MODEL_FILE:-}" ] && printf '%s' "$MODEL_ARG" > "$STUB_MODEL_FILE"
# Recorded so a row can pin that --output-schema was actually PASSED. Review
# caught that nothing did: the stub ignored the flag, so deleting it from the
# launcher left the whole suite green while every real leg lost the contract
# that makes codex emit these fields at all.
[ -n "${STUB_ARGS_FILE:-}" ] && printf '%s' "$SCHEMA_ARG" > "$STUB_ARGS_FILE"
# Assigned to a variable FIRST. Inlining this as a `${STUB_VERDICT:-...}`
# default requires escaping the closing brace, and the backslash survives into
# the file — which the launcher then correctly refused as malformed JSON.
DEFAULT_VERDICT='{"verdict":"CERTIFIED","shape":"SOUND","confidence":99,"findings":[]}'
if [ -n "$VERDICT_PATH" ] && [ -z "$STUB_NO_VERDICT" ]; then
    printf '%s' "${STUB_VERDICT:-$DEFAULT_VERDICT}" > "$VERDICT_PATH"
fi
printf '%s' "${STUB_STDOUT:-}"
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$STUBDIR/codex"
# The `gh` stub is installed HERE, before the FIRST test, not beside the
# tests that drive it. Installed later, every earlier test ran the launcher
# against the REAL `gh` — live API calls from a unit suite, and a result
# that depends on the network and on whether this branch has a PR. Review
# caught it; the suite was non-hermetic for its first six tests.
cat > "$STUBDIR/gh" <<'STUB'
#!/bin/bash
if [ -n "$GH_STUB_READ_STDIN" ]; then
    cat > /dev/null
fi
# GH_STUB_SLEEP: never return. A stalled network call, which is what gh does
# on a hung request — it sets NO overall HTTP timeout (verified against
# cli/cli v2.92 api/http_client.go and go-gh v2.13 client_options.go).
if [ -n "${GH_STUB_SLEEP:-}" ]; then
    # Record our own pid so the test can prove we were actually killed, not
    # merely abandoned. A launcher that walks away from a live process leaks
    # it — reported by review after running the real fixture and finding both
    # this stub and its `sleep` reparented to PID 1 and still running.
    [ -n "${GH_STUB_PIDFILE:-}" ] && echo $$ > "$GH_STUB_PIDFILE"
    sleep "$GH_STUB_SLEEP"
fi
printf '%s' "${GH_STUB_STDOUT:-}"
exit "${GH_STUB_EXIT:-0}"
STUB
chmod +x "$STUBDIR/gh"

export PATH="$STUBDIR:$PATH"
export STUB_READ_STDIN=1

echo "=== review-leg launcher (#590) ==="

new_leg() {
    local d
    d=$(mktemp -d "$TMPROOT/leg.XXXXXX")
    echo "$d/out.md"
}

# ---------------------------------------------------------------------------
# 1. A successful leg exits 0 and its output is in the file we named.
out=$(new_leg)
set +e
STUB_STDOUT=$'VERDICT: CERTIFIED\nNo defects found.\n' STUB_EXIT=0 \
    "$RUNNER" "$out" 'review this' >/dev/null 2>&1
rc=$?
set -e
check_rc "a successful leg exits 0" 0 "$rc"
if grep -qF 'VERDICT: CERTIFIED' "$out"; then
    pass "the leg's output lands in the named file"
else
    fail "the leg's output did not land in $out"
fi

# ---------------------------------------------------------------------------
# 2. The leg's exit status reaches the caller unchanged. This is the whole
# verdict mechanism: run as a background task, this status is what the
# completion notification carries, so nothing else needs to be consulted.
out=$(new_leg)
set +e
STUB_STDOUT='boom' STUB_EXIT=7 "$RUNNER" "$out" 'review this' >/dev/null 2>&1
rc=$?
set -e
check_rc "the leg's exit status reaches the caller unchanged" 7 "$rc"

# ---------------------------------------------------------------------------
# 3. A failing leg's partial output is still readable — the failure is worth
# diagnosing, not discarding.
if grep -qF 'boom' "$out"; then
    pass "a failed leg's partial output is preserved"
else
    fail "a failed leg's output was lost"
fi

# ---------------------------------------------------------------------------
# 4. THE HANG, in the shape reproduced against real codex 0.147.0:
#
#     tail -f /dev/null | codex exec ... 'prompt'
#
# codex reads stdin to EOF and appends it to the argv prompt, so an unclosed
# pipe blocks it before it contacts the model. Here the LAUNCHER inherits that
# never-closing pipe. It must still complete, because it redirects its child's
# stdin rather than passing its own through.
#
# The pipe is a fifo this shell holds open on fd 9 rather than `tail -f`,
# which never exits and would hang the harness rather than the subject.
out=$(new_leg)
fifo="$(dirname "$out")/stdin.fifo"
mkfifo "$fifo"
exec 9<> "$fifo"
set +e
STUB_STDOUT='done' STUB_EXIT=0 "$RUNNER" "$out" 'review this' <"$fifo" >/dev/null 2>&1
rc=$?
set -e
exec 9>&-
rm -f "$fifo"
check_rc "a leg inheriting an unclosed pipe on stdin still completes" 0 "$rc"

# ---------------------------------------------------------------------------
# 5. A stale output file from a previous run is not mistaken for this run's.
out=$(new_leg)
printf 'OLD RUN: VERDICT CERTIFIED\n' > "$out"
set +e
STUB_STDOUT='fresh output' STUB_EXIT=0 "$RUNNER" "$out" 'review this' >/dev/null 2>&1
rc=$?
set -e
check_rc "a relaunch over an existing output file exits 0" 0 "$rc"
if grep -qF 'OLD RUN' "$out"; then
    fail "the previous run's output survived into this run's file"
else
    pass "the previous run's output is cleared, not appended to"
fi

# ---------------------------------------------------------------------------
# 6. Usage errors are distinguishable from a leg that ran and failed.
set +e
"$RUNNER" >/dev/null 2>&1
rc=$?
set -e
check_rc "no arguments is a usage error, exit 64" 64 "$rc"

set +e
"$RUNNER" "$(new_leg)" >/dev/null 2>&1
rc=$?
set -e
check_rc "an output file with no prompt is a usage error, exit 64" 64 "$rc"

# ---------------------------------------------------------------------------
# 7. CI STATUS IS AN INPUT TO THE REVIEW (#613).
#
# PR #610 ran eight review rounds with two independent reviewers while CI
# `validate` was RED the whole time. Both reviewers ran the suites directly and
# correctly reported them green; the failing guard was one nobody was asked
# about. The merge gate caught it, which is a gate step discovered mid-merge —
# a violation of #593 Rung 1's own stop condition.
#
# Both reviewers independently prescribed the same fix: put the build in front
# of the reviewer, rather than asking for more diff scrutiny. "Seven rounds
# audited the diff; zero audited the build — that is the whole fix."
#
# The `gh` stub these rows drive is defined at the top of this file, beside the
# codex stub, so that every test above runs hermetically too. It mirrors codex's
# in reading stdin to EOF when asked, so a probe that fails to supply EOF hangs
# rather than passing quietly — a launcher that can hang on its own preflight
# has reintroduced #590.

out=$(new_leg)
set +e
GH_STUB_STDOUT='validate	fail	1m	https://example/run' GH_STUB_EXIT=1 \
GH_STUB_READ_STDIN=1 \
STUB_STDOUT='VERDICT: CERTIFIED' STUB_EXIT=0 \
    "$RUNNER" "$out" 'review this' >/dev/null 2>&1
rc=$?
set -e
check_rc "a red build does not fail the leg — it is reported, not fatal" 0 "$rc"

if grep -qiE 'CI STATUS' "$out"; then
    pass "the leg's output carries a CI STATUS block"
else
    fail "no CI STATUS block in the leg output — the reviewer cannot see the build"
fi

if grep -qF 'validate' "$out"; then
    pass "the failing check's name reaches the reviewer"
else
    fail "the failing check's name is absent from the leg output"
fi

# The block must precede the model's own output, or a reviewer reading top-down
# forms its verdict before it ever sees the build.
if [ "$(grep -n 'CI STATUS' "$out" | head -1 | cut -d: -f1)" -lt \
     "$(grep -n 'VERDICT' "$out" | head -1 | cut -d: -f1)" ]; then
    pass "the CI STATUS block precedes the model's output"
else
    fail "the CI STATUS block does not precede the model's output"
fi

# ---------------------------------------------------------------------------
# 8. An unavailable `gh` must not take the leg down with it. The probe is
# preflight, not the payload: no PR, no auth, no network, and the review still
# runs — with the fact recorded rather than silently omitted.
out=$(new_leg)
set +e
GH_STUB_STDOUT='' GH_STUB_EXIT=127 \
STUB_STDOUT='VERDICT: CERTIFIED' STUB_EXIT=0 \
    "$RUNNER" "$out" 'review this' >/dev/null 2>&1
rc=$?
set -e
check_rc "an unavailable gh does not fail the leg" 0 "$rc"

if grep -qiE 'CI STATUS' "$out"; then
    pass "an unavailable gh still records a CI STATUS block"
else
    fail "an unavailable gh left no CI STATUS block — silently omitted"
fi

# ---------------------------------------------------------------------------
# 9. The codex exit status still governs, with the probe in front of it. If the
# preflight could mask the verdict, #590's whole mechanism is gone.
out=$(new_leg)
set +e
GH_STUB_STDOUT='validate	pass	1m	url' GH_STUB_EXIT=0 \
STUB_STDOUT='boom' STUB_EXIT=7 \
    "$RUNNER" "$out" 'review this' >/dev/null 2>&1
rc=$?
set -e
check_rc "the leg's exit status still governs, probe notwithstanding" 7 "$rc"

# ---------------------------------------------------------------------------
# 10. A STALLED PROBE MUST NOT HANG THE LEG.
#
# The first version of the CI probe fell back to a bare `gh pr checks` when
# neither `timeout` nor `gtimeout` was present — which is the case on stock
# macOS, including this repo's own machine — and justified it with "gh carries
# its own network timeouts."
#
# That was an unverified claim and it is FALSE. gh 2.92 configures no overall
# HTTP timeout (cli/cli api/http_client.go, go-gh pkg/api/client_options.go).
# A stalled request would therefore block before `exec codex` ever ran: #590,
# the exact failure the launcher exists to prevent, reintroduced by the fix
# for #613 and hidden because the stub always exited.
#
# So the deadline is the launcher's own, enforced with nothing but bash.
out=$(new_leg)
probe_pidfile="$(dirname "$out")/probe.pid"
start=$(date +%s)
set +e
GH_STUB_SLEEP=120 GH_STUB_PIDFILE="$probe_pidfile" SDLC_CI_PROBE_TIMEOUT=2 \
STUB_STDOUT='VERDICT: CERTIFIED' STUB_EXIT=0 \
    "$RUNNER" "$out" 'review this' >/dev/null 2>&1
rc=$?
set -e
elapsed=$(( $(date +%s) - start ))
check_rc "a stalled CI probe does not fail the leg" 0 "$rc"

if [ "$elapsed" -lt 30 ]; then
    pass "the stalled probe is abandoned on a deadline (${elapsed}s), not waited on"
else
    fail "the leg took ${elapsed}s — the probe was waited on, which is #590 all over again"
fi

if grep -qF 'VERDICT: CERTIFIED' "$out"; then
    pass "the review still ran after the probe was abandoned"
else
    fail "the review never ran — the probe blocked it"
fi

if grep -qiE 'UNKNOWN|timed out|deadline' "$out"; then
    pass "the abandoned probe is recorded, not silently omitted"
else
    fail "the probe timed out silently — a reviewer cannot tell the build was never checked"
fi

# The kill must be SILENT in the reviewer's file. Without `disown`, bash prints
# its job-termination notice — "Terminated: 15   ( set +e; gh pr checks …" —
# into this very block, exposing the launcher's internals as noise in the one
# place the PR exists to make readable. Review found it by running the repro;
# the suite could not, because nothing asserted on it. Deleting `disown` now
# turns this row red.
if grep -qE 'Terminated|Killed' "$out"; then
    fail "a shell job notice leaked into the CI STATUS block — the reviewer reads launcher internals"
else
    pass "the kill is silent in the reviewer's output"
fi

# ...and it must be KILLED, not merely walked away from. The first fix killed
# the subshell, which left `gh` itself running, reparented to PID 1. An earlier
# known_limits entry claimed "it exits on its own"; that was an unverified
# claim, and a genuinely stalled `gh` never does. Repeated timeouts would leak
# processes, descriptors and connections until later legs cannot launch.
sleep 1
if [ -f "$probe_pidfile" ]; then
    probe_pid=$(cat "$probe_pidfile")
    if kill -0 "$probe_pid" 2>/dev/null; then
        kill -9 "$probe_pid" 2>/dev/null || true
        fail "the timed-out probe (pid $probe_pid) is still alive — abandoned, not killed"
    else
        pass "the timed-out probe was killed, not left running"
    fi
else
    fail "the probe never recorded its pid — cannot prove it was killed"
fi

# ---------------------------------------------------------------------------
# THE #617 WIRING. The schema and validator have their own suite
# (tests/test-review-verdict-schema.sh). These two rows prove the LAUNCHER
# actually consults them — a validator nobody calls is the same defect as a
# guard nobody tests.

# A leg that ran but answered nothing is INCOMPLETE, not successful. This is the
# case rounds 6-8 of PR #646 lived in: the reviews happened, and the two
# questions that would have ended them were never put.
out=$(new_leg)
set +e
STUB_NO_VERDICT=1 STUB_STDOUT=$'VERDICT: CERTIFIED\n' STUB_EXIT=0 \
    "$RUNNER" "$out" 'review this' >/dev/null 2>&1
rc=$?
set -e
check_rc "a leg that wrote no structured verdict is refused" 65 "$rc"
if grep -q 'INCOMPLETE LEG' "$out"; then
    pass "the reviewer's file says why the leg was refused"
else
    fail "the leg was refused with nothing in the output explaining it"
fi

# VOLUNTEERED + REPAIR is the combination this whole change exists to forbid.
# It must be refused THROUGH THE LAUNCHER, not only in the schema suite.
out=$(new_leg)
set +e
STUB_VERDICT='{"verdict":"NOT_CERTIFIED","shape":"CONCERN","confidence":80,"findings":[{"severity":"P1","target":"VOLUNTEERED","disposition":"REPAIR","claim":"a false refusal from a guard nobody asked for"}]}' \
STUB_STDOUT=$'VERDICT: NOT CERTIFIED\n' STUB_EXIT=0 \
    "$RUNNER" "$out" 'review this' >/dev/null 2>&1
rc=$?
set -e
check_rc "a leg prescribing REPAIR on volunteered code is refused" 65 "$rc"

# ...and the same finding marked DELETE goes through, or the rule reads as
# "never report volunteered findings" and hides what it exists to surface.
out=$(new_leg)
set +e
STUB_VERDICT='{"verdict":"NOT_CERTIFIED","shape":"WRONG_SHAPE","confidence":80,"findings":[{"severity":"P1","target":"VOLUNTEERED","disposition":"DELETE","claim":"a guard tracing to neither issue under review"}]}' \
STUB_STDOUT=$'VERDICT: NOT CERTIFIED\n' STUB_EXIT=0 \
    "$RUNNER" "$out" 'review this' >/dev/null 2>&1
rc=$?
set -e
check_rc "a leg prescribing DELETE on volunteered code completes" 0 "$rc"

# The launcher must PASS --output-schema, not merely validate afterwards. The
# schema is what makes codex emit shape/target in the first place; without it a
# leg returns prose, the verdict file is absent or unconforming, and every leg
# fails closed for the wrong reason.
out=$(new_leg)
argsfile="$(dirname "$out")/schema-arg"
set +e
STUB_ARGS_FILE="$argsfile" STUB_STDOUT='ok' STUB_EXIT=0 \
    "$RUNNER" "$out" 'review this' >/dev/null 2>&1
rc=$?
set -e
check_rc "the leg completes" 0 "$rc"
if [ -s "$argsfile" ] && grep -q 'review-verdict.schema.json' "$argsfile"; then
    pass "the launcher passes --output-schema pointing at the shipped schema"
else
    fail "--output-schema was not passed — codex is never told to emit shape or target"
fi

# THE STALE VERDICT (found by review, P0). The transcript is truncated at
# launch and row 5 proves it. The verdict sidecar was NOT, so a relaunch whose
# leg exits 0 without emitting a verdict validated the PREVIOUS run's answer and
# reported the leg complete. Same defect as row 5, one file over — which is why
# the row exists here rather than the fix landing quietly.
out=$(new_leg)
set +e
STUB_VERDICT='{"verdict":"CERTIFIED","shape":"SOUND","confidence":99,"findings":[]}' \
STUB_STDOUT='first run' STUB_EXIT=0 "$RUNNER" "$out" 'review this' >/dev/null 2>&1
set -e
if [ -s "$out.verdict.json" ]; then
    pass "the first leg wrote a verdict"
else
    fail "the first leg wrote no verdict — fixture is not exercising the case"
fi
set +e
STUB_NO_VERDICT=1 STUB_STDOUT='second run, no verdict' STUB_EXIT=0 \
    "$RUNNER" "$out" 'review this' >/dev/null 2>&1
rc=$?
set -e
check_rc "a relaunch emitting no verdict is refused, not passed on the stale one" 65 "$rc"
if [ -s "$out.verdict.json" ]; then
    fail "the previous run's verdict survived into this run — it is being re-validated"
else
    pass "the previous run's verdict is cleared, not reused"
fi

# KILLING THE LAUNCHER MUST KILL THE LEG (found by review, P2). Dropping `exec`
# broke this: the launcher's pid was no longer codex's, so a TERM left codex
# alive, appending to the transcript and able to write a verdict into a path a
# relaunch had since truncated. The stale-verdict channel from the other end.
out=$(new_leg)
pidfile="$(dirname "$out")/codex.pid"
cat > "$STUBDIR/codex-slow" <<'SLOWSTUB'
#!/bin/bash
echo $$ > "$CODEX_PIDFILE"
sleep 60
SLOWSTUB
chmod +x "$STUBDIR/codex-slow"
slowdir="$(dirname "$out")/slowbin"
mkdir -p "$slowdir"
cp "$STUBDIR/codex-slow" "$slowdir/codex"
set +e
CODEX_PIDFILE="$pidfile" PATH="$slowdir:$PATH" "$RUNNER" "$out" 'review this' >/dev/null 2>&1 &
launcher_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    [ -s "$pidfile" ] && break
    sleep 1
done
kill -TERM "$launcher_pid" 2>/dev/null
wait "$launcher_pid" 2>/dev/null
sleep 1
set -e
if [ -s "$pidfile" ]; then
    codex_pid=$(cat "$pidfile")
    if kill -0 "$codex_pid" 2>/dev/null; then
        kill -9 "$codex_pid" 2>/dev/null || true
        fail "killing the launcher left codex (pid $codex_pid) alive — it can still write a late verdict"
    else
        pass "killing the launcher kills the leg"
    fi
else
    fail "the stub never recorded its pid — cannot prove the kill reached it"
fi

# ---------------------------------------------------------------------------
# MODEL CONFIGURABILITY. The launcher defaults to gpt-5.5 but must accept
# REVIEW_MODEL to run Sol or any other model without script copies.

out=$(new_leg)
modelfile="$(dirname "$out")/model-arg"
set +e
STUB_MODEL_FILE="$modelfile" STUB_STDOUT='ok' STUB_EXIT=0 \
    "$RUNNER" "$out" 'review this' >/dev/null 2>&1
rc=$?
set -e
check_rc "default model leg completes" 0 "$rc"
if [ -s "$modelfile" ] && grep -qF 'gpt-5.5' "$modelfile"; then
    pass "the default model is gpt-5.5"
else
    fail "default model is not gpt-5.5 (got: $(cat "$modelfile" 2>/dev/null))"
fi

out=$(new_leg)
modelfile="$(dirname "$out")/model-arg-sol"
set +e
REVIEW_MODEL=gpt-5.6-sol STUB_MODEL_FILE="$modelfile" STUB_STDOUT='ok' STUB_EXIT=0 \
    "$RUNNER" "$out" 'review this' >/dev/null 2>&1
rc=$?
set -e
check_rc "REVIEW_MODEL override leg completes" 0 "$rc"
if [ -s "$modelfile" ] && grep -qF 'gpt-5.6-sol' "$modelfile"; then
    pass "REVIEW_MODEL=gpt-5.6-sol is passed to codex as -m gpt-5.6-sol"
else
    fail "REVIEW_MODEL override not passed (got: $(cat "$modelfile" 2>/dev/null))"
fi

echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "Some review-leg launcher tests failed"
    exit 1
fi
echo "All review-leg launcher tests passed!"
