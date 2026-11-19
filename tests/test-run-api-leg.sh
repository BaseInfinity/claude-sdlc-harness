#!/bin/bash
# Tests for the credit-funded Fable review leg (scripts/run-api-leg.sh).
#
# NO REAL API CALL IS EVER MADE HERE. A stub `curl` sits first on PATH; it
# records what the launcher sent and replays a canned HTTP status and body.
# The key is a fake string, and one row fails if it ever reaches curl's argv
# (visible in `ps`) instead of curl's stdin config.

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/run-api-leg.sh"

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

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/run-api-leg-tests.XXXXXX") || {
    echo "FATAL: could not create a temp dir; refusing to run in the caller's repo" >&2
    exit 1
}
trap 'rm -rf "$TMPROOT"' EXIT

FAKE_KEY="sk-test-fake-not-a-key"
CAP="$TMPROOT/cap"

# Stub curl:
#   STUB_CODE       HTTP status printed for -w '%{http_code}'
#   STUB_BODY       file whose bytes are written to the -o path
#   STUB_CURL_EXIT  curl's own exit status (28 = timed out); skips the body
# Captures argv, the request body (--data-binary @FILE) and the stdin config.
STUBDIR="$TMPROOT/bin"
mkdir -p "$STUBDIR"
cat > "$STUBDIR/curl" <<'STUB'
#!/bin/bash
mkdir -p "$CAP"
printf '%s\n' "$@" > "$CAP/argv"
OUTF=""; WFMT=""; prev=""; READ_CONFIG=""
for arg in "$@"; do
    case "$prev" in
        -o) OUTF="$arg" ;;
        -w) WFMT="$arg" ;;
        --data-binary) cp "${arg#@}" "$CAP/body.json" ;;
        --config) [ "$arg" = "-" ] && READ_CONFIG=1 ;;
    esac
    prev="$arg"
done
if [ -n "$READ_CONFIG" ]; then cat > "$CAP/config"; fi
if [ -n "$STUB_CURL_EXIT" ]; then exit "$STUB_CURL_EXIT"; fi
cp "$STUB_BODY" "$OUTF"
[ "$WFMT" = '%{http_code}' ] && printf '%s' "$STUB_CODE"
exit 0
STUB
chmod +x "$STUBDIR/curl"

# A throwaway repo with two commits, so `git diff BASE...HEAD` has content.
FIX="$TMPROOT/repo"
mkdir -p "$FIX"
git -C "$FIX" init -q
echo "one" > "$FIX/a.txt"
git -C "$FIX" add a.txt
git -C "$FIX" -c user.name=t -c user.email=t@t commit -q -m one
BASE_SHA=$(git -C "$FIX" rev-parse HEAD)
echo "DIFF_MARKER_LINE" >> "$FIX/a.txt"
git -C "$FIX" -c user.name=t -c user.email=t@t commit -q -am two

PROMPT_FILE="$TMPROOT/prompt.md"
echo "PROMPT_MARKER review the diff against the design" > "$PROMPT_FILE"

VALID_VERDICT='{"verdict":"CERTIFIED","shape":"SOUND","confidence":90,"findings":[]}'

# Response body with a thinking block FIRST: the verdict must be read by block
# type, never by index.
body_ok() {
    jq -n --arg t "$1" '{
        id: "msg_test", type: "message", role: "assistant",
        model: "claude-fable-5-1", stop_reason: "end_turn",
        content: [{type: "thinking", thinking: "hmm", signature: "x"},
                  {type: "text", text: $t}],
        usage: {input_tokens: 1200, output_tokens: 340}
    }' > "$TMPROOT/body.json"
}
body_err() {
    jq -n --arg ty "$1" --arg m "$2" \
        '{type: "error", error: {type: $ty, message: $m}}' > "$TMPROOT/body.json"
}

# run_leg OUT [extra args...]; env is passed by the caller. Returns the exit.
run_leg() {
    local out="$1"; shift
    rm -rf "$CAP"
    set +e
    (cd "$FIX" && PATH="$STUBDIR:$PATH" CAP="$CAP" STUB_BODY="$TMPROOT/body.json" \
        SDLC_API_LEG_USAGE_LOG="$TMPROOT/usage.jsonl" \
        "$RUNNER" "$out" "$PROMPT_FILE" --base "$BASE_SHA" "$@" < /dev/null)
    RC=$?
    set -e
}

if [ ! -x "$RUNNER" ]; then
    fail "scripts/run-api-leg.sh exists and is executable"
fi

echo "=== off by default ==="
OUT="$TMPROOT/off.out"
run_leg "$OUT"
check_rc "KEY_CMD unset -> 78 skipped" 78 "$RC"
if [ ! -e "$CAP/argv" ]; then pass "KEY_CMD unset -> curl never invoked"; else fail "KEY_CMD unset -> curl was invoked"; fi
if grep -qi "skipped" "$OUT" 2>/dev/null; then pass "skip is stated in OUT"; else fail "skip is not stated in OUT"; fi

export SDLC_API_LEG_KEY_CMD="echo $FAKE_KEY"

echo "=== 200 with a valid verdict ==="
body_ok "$VALID_VERDICT"
OUT="$TMPROOT/ok.out"
rm -f "$TMPROOT/usage.jsonl"
STUB_CODE=200 run_leg "$OUT"
check_rc "200 + valid verdict -> 0" 0 "$RC"
if [ "$(jq -r .verdict "$OUT.verdict.json" 2>/dev/null)" = "CERTIFIED" ]; then
    pass "verdict JSON written to OUT.verdict.json (text block, not thinking block)"
else
    fail "verdict JSON not written to OUT.verdict.json"
fi
B="$CAP/body.json"
[ "$(jq -r .model "$B" 2>/dev/null)" = "claude-fable-5-1" ] \
    && pass "default model is claude-fable-5-1" || fail "default model is not claude-fable-5-1"
[ "$(jq -r .output_config.effort "$B" 2>/dev/null)" = "high" ] \
    && pass "output_config.effort is high" || fail "output_config.effort is not high"
[ "$(jq -r '.max_tokens | type' "$B" 2>/dev/null)" = "number" ] \
    && pass "max_tokens is fixed in the request" || fail "max_tokens missing"
jq -r '.system' "$B" 2>/dev/null | grep -q "Grade severity by impact" \
    && pass "system prompt carries the Review Contract" || fail "system prompt lacks the Review Contract"
jq -r '.messages[0].content' "$B" 2>/dev/null | grep -q "PROMPT_MARKER" \
    && pass "user message carries the prompt file" || fail "user message lacks the prompt file"
jq -r '.messages[0].content' "$B" 2>/dev/null | grep -q "DIFF_MARKER_LINE" \
    && pass "user message carries the inlined diff" || fail "user message lacks the diff"
[ "$(jq -r '.output_config.format.type' "$B" 2>/dev/null)" = "json_schema" ] \
    && pass "structured output requested" || fail "structured output not requested"
if [ "$(jq '[.output_config.format.schema | .. | objects | select(has("minimum") or has("maximum") or has("$schema"))] | length' "$B" 2>/dev/null)" = "0" ]; then
    pass "schema sent without keywords the API rejects"
else
    fail "schema sent with minimum/maximum/\$schema"
fi
if grep -qF "$FAKE_KEY" "$CAP/argv"; then fail "key appeared on curl argv"; else pass "key never on curl argv"; fi
grep -qF "$FAKE_KEY" "$CAP/config" 2>/dev/null \
    && pass "key reached curl via stdin config" || fail "key did not reach curl via stdin config"
[ "$(jq -r .usage.output_tokens "$TMPROOT/usage.jsonl" 2>/dev/null)" = "340" ] \
    && pass "usage appended to the advisory log" || fail "usage not appended to the log"

echo "=== --model override ==="
STUB_CODE=200 run_leg "$TMPROOT/model.out" --model claude-opus-5-5
[ "$(jq -r .model "$CAP/body.json" 2>/dev/null)" = "claude-opus-5-5" ] \
    && pass "--model overrides the default" || fail "--model ignored"

echo "=== invalid verdict ==="
body_ok '{"verdict":"CERTIFIED","confidence":90,"findings":[]}'
STUB_CODE=200 run_leg "$TMPROOT/bad.out"
check_rc "200 + verdict missing shape -> 65 incomplete" 65 "$RC"

echo "=== leg unavailable: never a finding ==="
body_err invalid_request_error "Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits."
OUT="$TMPROOT/credit.out"
echo "$VALID_VERDICT" > "$OUT.verdict.json"
STUB_CODE=400 run_leg "$OUT"
check_rc "400 credit too low -> 75" 75 "$RC"
[ ! -e "$OUT.verdict.json" ] && pass "stale verdict removed on an unavailable leg" || fail "stale verdict survived"
grep -q "credit balance is too low" "$OUT" && pass "error body recorded in OUT" || fail "error body not in OUT"

body_err rate_limit_error "Number of request tokens has exceeded your rate limit."
STUB_CODE=429 run_leg "$TMPROOT/429.out"
check_rc "429 -> 75" 75 "$RC"

body_err api_error "Internal server error"
STUB_CODE=500 run_leg "$TMPROOT/500.out"
check_rc "500 -> 75" 75 "$RC"

body_err overloaded_error "Overloaded"
STUB_CODE=529 run_leg "$TMPROOT/529.out"
check_rc "529 overloaded -> 75" 75 "$RC"

STUB_CURL_EXIT=28 run_leg "$TMPROOT/timeout.out"
check_rc "curl timeout (28) -> 75" 75 "$RC"

SDLC_API_LEG_KEY_CMD="false" run_leg "$TMPROOT/keyfail.out"
check_rc "KEY_CMD fails -> 75" 75 "$RC"
[ ! -e "$CAP/argv" ] && pass "KEY_CMD fails -> curl never invoked" || fail "KEY_CMD fails -> curl invoked"

echo "=== request defect is not transient ==="
body_err invalid_request_error "output_config.format.schema: unsupported keyword"
STUB_CODE=400 run_leg "$TMPROOT/defect.out"
check_rc "other 400 -> 70 request defect" 70 "$RC"

echo "=== diff over the cap ==="
SDLC_API_LEG_DIFF_CAP=10 run_leg "$TMPROOT/cap.out"
check_rc "diff over cap -> 78" 78 "$RC"
[ ! -e "$CAP/argv" ] && pass "diff over cap -> curl never invoked" || fail "diff over cap -> curl invoked"

echo "=== not shipped ==="
if jq -e '.files | map(select(startswith("scripts"))) | length == 0' "$REPO_ROOT/package.json" > /dev/null; then
    pass "scripts/ stays out of package.json files"
else
    fail "scripts/ is in package.json files"
fi

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
