#!/bin/bash
# Test token-spike anomaly detection (ROADMAP #220)
#
# Validates:
#   - Analytics script exists and is executable
#   - Idempotent ingest: scanning a transcript dir twice doesn't duplicate records
#   - Burn calculation matches summed transcript usage fields
#   - Spike fires when last burn > median + 2*stdev over min 5-record window
#   - No spike when window has < 5 records (insufficient baseline)
#   - No spike when last burn is within threshold
#   - Median (not mean) is used: fixture where mean drifts but median does not
#   - Hook gate: token-spike-check.sh only fires when .metrics/ exists
#   - Hook output: hook surfaces warning when ingest+check finds spike


# macOS has no C.UTF-8 locale (it is glibc-only). When a caller exports it,
# bash warns on stderr, and every capture below merges stderr via 2>&1 — so the
# warning lands inside the value being asserted and fails unrelated checks.
# Filter the warning specifically; do not force a locale, which would hide
# real stderr from the script under test. (Confirmed: 14 + 2 false failures.)
strip_locale_warning() { grep -v 'warning: setlocale' || true; }

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANALYTICS="$REPO_ROOT/tests/e2e/token-analytics.sh"
HOOK="$REPO_ROOT/hooks/token-spike-check.sh"

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

# Build a temp workspace with synthetic transcripts and history files.
make_tmp_workspace() {
    local tmp base="${TMPDIR:-/tmp}"
    tmp=$(mktemp -d "${base%/}/token-spike.XXXXXX" 2>/dev/null) || {
        tmp="${base%/}/token-spike-$$"
        mkdir -p "$tmp"
    }
    mkdir -p "$tmp/transcripts" "$tmp/.metrics"
    echo "$tmp"
}

# Write a fake transcript with N assistant messages, each with usage block.
# Args: $1 path, $2 session_id, $3 input_per_msg, $4 output_per_msg,
#       $5 cache_creation_per_msg, $6 cache_read_per_msg, $7 message_count
make_transcript() {
    local path="$1" sid="$2" in="$3" out="$4" cc="$5" cr="$6" n="$7"
    : > "$path"
    local i
    for ((i=0; i<n; i++)); do
        printf '{"sessionId":"%s","type":"assistant","message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":%d,"output_tokens":%d,"cache_creation_input_tokens":%d,"cache_read_input_tokens":%d}}}\n' \
            "$sid" "$in" "$out" "$cc" "$cr" >> "$path"
    done
}

# Write a token-history.jsonl with N records of given costly burn each.
# Args: $1 path, $2 record_count, $3 burn_per_record
make_history() {
    local path="$1" n="$2" burn="$3"
    : > "$path"
    local i
    for ((i=1; i<=n; i++)); do
        printf '{"session_id":"hist-%03d","timestamp":"2026-04-27T01:00:%02dZ","input_tokens":%d,"output_tokens":1,"cache_creation_tokens":1,"cache_read_tokens":0,"costly_tokens":%d,"message_count":10}\n' \
            "$i" "$i" "$burn" "$burn" >> "$path"
    done
}

# Append one record with a specified burn (the candidate / "last session").
append_history_record() {
    local path="$1" sid="$2" burn="$3"
    printf '{"session_id":"%s","timestamp":"2026-04-27T02:00:00Z","input_tokens":%d,"output_tokens":1,"cache_creation_tokens":1,"cache_read_tokens":0,"costly_tokens":%d,"message_count":10}\n' \
        "$sid" "$burn" "$burn" >> "$path"
}

echo "=== Token Spike Detection Tests ==="
echo ""

# --- Existence and executability ---

test_analytics_exists() {
    if [ -f "$ANALYTICS" ] && [ -x "$ANALYTICS" ]; then
        pass "token-analytics.sh exists and is executable"
    else
        fail "token-analytics.sh missing or not executable: $ANALYTICS"
    fi
}

test_hook_exists() {
    if [ -f "$HOOK" ] && [ -x "$HOOK" ]; then
        pass "token-spike-check.sh hook exists and is executable"
    else
        fail "token-spike-check.sh hook missing or not executable: $HOOK"
    fi
}

# --- Burn calculation ---

test_burn_calculation_matches_transcript_sum() {
    local tmp
    tmp=$(make_tmp_workspace)
    # 5 messages × (10 input, 100 output, 50 cache_creation, 1000 cache_read)
    # costly_tokens = 5 * (10 + 100 + 50) = 800
    make_transcript "$tmp/transcripts/sess-aaa.jsonl" "sess-aaa" 10 100 50 1000 5

    "$ANALYTICS" --history "$tmp/.metrics/token-history.jsonl" \
        --transcript-dir "$tmp/transcripts" \
        --ingest \
        --no-skip-recent > /dev/null 2>&1 || true

    if [ ! -f "$tmp/.metrics/token-history.jsonl" ]; then
        fail "ingest did not create history file"
        rm -rf "$tmp"
        return
    fi

    local burn input out cc cr
    burn=$(jq -r '.costly_tokens' "$tmp/.metrics/token-history.jsonl" | head -1)
    input=$(jq -r '.input_tokens' "$tmp/.metrics/token-history.jsonl" | head -1)
    out=$(jq -r '.output_tokens' "$tmp/.metrics/token-history.jsonl" | head -1)
    cc=$(jq -r '.cache_creation_tokens' "$tmp/.metrics/token-history.jsonl" | head -1)
    cr=$(jq -r '.cache_read_tokens' "$tmp/.metrics/token-history.jsonl" | head -1)

    if [ "$burn" = "800" ] && [ "$input" = "50" ] && [ "$out" = "500" ] && \
       [ "$cc" = "250" ] && [ "$cr" = "5000" ]; then
        pass "burn calculation matches summed transcript usage fields (costly_tokens = input+cache_creation+output)"
    else
        fail "burn calc wrong: costly=$burn (want 800), in=$input (want 50), out=$out (want 500), cc=$cc (want 250), cr=$cr (want 5000)"
    fi
    rm -rf "$tmp"
}

# --- Idempotency ---

test_ingest_is_idempotent() {
    local tmp
    tmp=$(make_tmp_workspace)
    make_transcript "$tmp/transcripts/sess-bbb.jsonl" "sess-bbb" 10 100 50 1000 5

    "$ANALYTICS" --history "$tmp/.metrics/token-history.jsonl" \
        --transcript-dir "$tmp/transcripts" \
        --ingest --no-skip-recent > /dev/null 2>&1
    "$ANALYTICS" --history "$tmp/.metrics/token-history.jsonl" \
        --transcript-dir "$tmp/transcripts" \
        --ingest --no-skip-recent > /dev/null 2>&1

    local count
    count=$(wc -l < "$tmp/.metrics/token-history.jsonl" | tr -d ' ')
    if [ "$count" = "1" ]; then
        pass "ingest is idempotent (running twice keeps 1 record per session_id)"
    else
        fail "ingest duplicated records: got $count lines for 1 session, expected 1"
    fi
    rm -rf "$tmp"
}

# --- Spike detection: positive case ---

test_spike_detected_when_last_exceeds_threshold() {
    local tmp
    tmp=$(make_tmp_workspace)
    # 10 baseline records at burn=1000 each (median=1000, stdev=0)
    # 1 spike at burn=10000 → 10000 > 1000 + 0 trivially. But we need stdev>0
    # to make the test rigorous, so vary baseline slightly.
    : > "$tmp/.metrics/token-history.jsonl"
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        local burn=$((1000 + i * 10))   # 1010, 1020, ..., 1100
        printf '{"session_id":"hist-%03d","timestamp":"2026-04-27T01:%02d:00Z","input_tokens":%d,"output_tokens":1,"cache_creation_tokens":1,"cache_read_tokens":0,"costly_tokens":%d,"message_count":10}\n' \
            "$i" "$i" "$burn" "$burn" >> "$tmp/.metrics/token-history.jsonl"
    done
    # Spike: last record at 50000 (way above median ~1055 + 2*~30)
    append_history_record "$tmp/.metrics/token-history.jsonl" "spike" 50000

    local out
    out=$("$ANALYTICS" --history "$tmp/.metrics/token-history.jsonl" --check 2>&1 | strip_locale_warning) || true
    if echo "$out" | grep -qiE 'WARN|spike|anomaly|σ|sigma'; then
        pass "spike detected when last record >2σ above median (10 baseline + 1 spike)"
    else
        fail "spike NOT detected: output was: $out"
    fi
    rm -rf "$tmp"
}

# --- Spike detection: negative case ---

test_no_spike_when_within_threshold() {
    local tmp
    tmp=$(make_tmp_workspace)
    # 10 baseline at varied burns, last is normal
    : > "$tmp/.metrics/token-history.jsonl"
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        local burn=$((1000 + i * 10))
        printf '{"session_id":"hist-%03d","timestamp":"2026-04-27T01:%02d:00Z","input_tokens":%d,"output_tokens":1,"cache_creation_tokens":1,"cache_read_tokens":0,"costly_tokens":%d,"message_count":10}\n' \
            "$i" "$i" "$burn" "$burn" >> "$tmp/.metrics/token-history.jsonl"
    done
    # Normal: last record at 1080 (within median + 2σ)
    append_history_record "$tmp/.metrics/token-history.jsonl" "normal" 1080

    local out
    out=$("$ANALYTICS" --history "$tmp/.metrics/token-history.jsonl" --check 2>&1 | strip_locale_warning) || true
    if echo "$out" | grep -qiE 'WARN|spike|anomaly'; then
        fail "false positive: spike reported when last burn within threshold. Output: $out"
    else
        pass "no spike when last burn within median+2σ"
    fi
    rm -rf "$tmp"
}

# --- Min window: insufficient baseline ---

test_no_spike_when_window_too_small() {
    local tmp
    tmp=$(make_tmp_workspace)
    # Only 4 records (minimum baseline = 5). Last is huge; should NOT trigger
    # because the rolling window doesn't have enough data to be confident.
    make_history "$tmp/.metrics/token-history.jsonl" 3 1000
    append_history_record "$tmp/.metrics/token-history.jsonl" "huge" 999999

    local out
    out=$("$ANALYTICS" --history "$tmp/.metrics/token-history.jsonl" --check 2>&1 | strip_locale_warning) || true
    if echo "$out" | grep -qiE 'WARN|spike|anomaly'; then
        fail "false positive on tiny window: output: $out"
    else
        pass "no spike when window has < 5 baseline records (insufficient data)"
    fi
    rm -rf "$tmp"
}

# --- Median (not mean) — mutation test ---

test_median_not_mean() {
    # Construct: 10 baseline values where mean is much higher than median.
    # Values: nine 100s and one 100000 outlier. mean = 10090, median = 100.
    # Stdev of full set is ~30000.
    # Last (candidate) = 500.
    # Mean-based check: |500 - 10090| / 30000 ≈ 0.32σ → no spike.
    # Median-based check: 500 vs median 100, stdev (computed from baseline only,
    # not including the outlier) should still flag if implementation uses mean.
    # However, if stdev is computed including the outlier, it'll be huge and
    # mask everything. The point: a correct median+stdev impl using ROBUST stats
    # would flag a clear deviation; a mean-based one won't even notice.
    #
    # Simpler mutation framing: ensure the analytics doesn't quietly use mean
    # by putting the candidate ABOVE median+2σ but BELOW mean. If "mean" is the
    # comparator, no spike fires. With median, spike fires.

    local tmp
    tmp=$(make_tmp_workspace)
    : > "$tmp/.metrics/token-history.jsonl"
    # Baseline: 9 small values around 100, 1 huge outlier (50000)
    local i burns=(100 105 95 110 90 120 85 100 100)
    for i in "${!burns[@]}"; do
        local idx=$((i + 1))
        local burn="${burns[$i]}"
        printf '{"session_id":"hist-%03d","timestamp":"2026-04-27T01:%02d:00Z","input_tokens":%d,"output_tokens":1,"cache_creation_tokens":1,"cache_read_tokens":0,"costly_tokens":%d,"message_count":10}\n' \
            "$idx" "$idx" "$burn" "$burn" >> "$tmp/.metrics/token-history.jsonl"
    done
    # 10th baseline: huge outlier
    append_history_record "$tmp/.metrics/token-history.jsonl" "outlier" 50000
    # Candidate: 1500 (above median ~100 + 2σ-ish, below mean 5100)
    append_history_record "$tmp/.metrics/token-history.jsonl" "candidate" 1500

    # Median-based MUST flag (robust to outlier).
    # Mean-based MUST NOT flag (the 50000 outlier inflates stdev and mean).
    # This is the contrast that proves the median branch isn't a no-op.
    local out_med out_mean
    out_med=$("$ANALYTICS" --history "$tmp/.metrics/token-history.jsonl" --check --metric median 2>&1 | strip_locale_warning) || true
    out_mean=$("$ANALYTICS" --history "$tmp/.metrics/token-history.jsonl" --check --metric mean 2>&1 | strip_locale_warning) || true

    local med_warned mean_warned
    if echo "$out_med" | grep -qiE 'WARN|spike|anomaly'; then med_warned=yes; else med_warned=no; fi
    if echo "$out_mean" | grep -qiE 'WARN|spike|anomaly'; then mean_warned=yes; else mean_warned=no; fi

    if [ "$med_warned" = "yes" ] && [ "$mean_warned" = "no" ]; then
        pass "median-based detection flags candidate above typical burn (mean-based does NOT — outlier inflates stdev). Median: $med_warned, Mean: $mean_warned"
    else
        fail "median-vs-mean contrast broken. Median should warn (got $med_warned), mean should NOT warn (got $mean_warned). Median output: $out_med | Mean output: $out_mean"
    fi
    rm -rf "$tmp"
}

# --- Flat baseline: small upticks must NOT fire (zero-MAD safety) ---

test_flat_baseline_small_uptick_does_not_fire() {
    local tmp
    tmp=$(make_tmp_workspace)
    # 5 baseline records, all identical at 1000 tokens.
    # Without a minimum-spread floor, MAD = 0 → threshold = center = 1000 →
    # any 1-token deviation fires. With the floor, candidate must clear
    # max(5% of center, 1000) = 1000 absolute tokens. So 1100 should be safe.
    : > "$tmp/.metrics/token-history.jsonl"
    local i
    for i in 1 2 3 4 5; do
        printf '{"session_id":"flat-%03d","timestamp":"2026-04-27T01:%02d:00Z","input_tokens":1000,"output_tokens":0,"cache_creation_tokens":0,"cache_read_tokens":0,"costly_tokens":1000,"message_count":10}\n' \
            "$i" "$i" >> "$tmp/.metrics/token-history.jsonl"
    done
    append_history_record "$tmp/.metrics/token-history.jsonl" "smalluptick" 1100

    local out
    out=$("$ANALYTICS" --history "$tmp/.metrics/token-history.jsonl" --check 2>&1 | strip_locale_warning) || true
    if echo "$out" | grep -qiE 'WARN|spike|anomaly'; then
        fail "false positive on flat-baseline tiny uptick (1000→1100). Output: $out"
    else
        pass "flat baseline + small uptick suppressed by minimum-spread floor"
    fi
    rm -rf "$tmp"
}

test_flat_baseline_large_jump_still_fires() {
    local tmp
    tmp=$(make_tmp_workspace)
    # Same 5 baseline at 1000, candidate at 50000 — a 50× jump must still fire
    # even on flat baselines, otherwise the floor is too generous.
    : > "$tmp/.metrics/token-history.jsonl"
    local i
    for i in 1 2 3 4 5; do
        printf '{"session_id":"flat-%03d","timestamp":"2026-04-27T01:%02d:00Z","input_tokens":1000,"output_tokens":0,"cache_creation_tokens":0,"cache_read_tokens":0,"costly_tokens":1000,"message_count":10}\n' \
            "$i" "$i" >> "$tmp/.metrics/token-history.jsonl"
    done
    append_history_record "$tmp/.metrics/token-history.jsonl" "bigjump" 50000

    local out
    out=$("$ANALYTICS" --history "$tmp/.metrics/token-history.jsonl" --check 2>&1 | strip_locale_warning) || true
    if echo "$out" | grep -qiE 'WARN|spike|anomaly'; then
        pass "flat baseline + 50× jump still fires (floor doesn't mask real spikes)"
    else
        fail "flat baseline 50× jump suppressed. Output: $out"
    fi
    rm -rf "$tmp"
}

# --- Privacy: malicious transcript with string usage values ---

test_privacy_string_values_coerced_to_zero() {
    local tmp
    tmp=$(make_tmp_workspace)
    # Craft a transcript where usage fields are strings (e.g., a prompt-injected
    # transcript or a bug where CC writes message text into a numeric slot).
    # The ingest MUST coerce non-numeric values to 0 and NEVER copy raw strings
    # into history. (Codex finding #1.)
    cat > "$tmp/transcripts/sess-evil.jsonl" <<'EOF'
{"sessionId":"sess-evil","type":"assistant","message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":"USER_SECRET_INPUT","output_tokens":"ASSISTANT_SECRET_OUTPUT","cache_creation_input_tokens":{"nested":"TOOL_ARGS_SECRET"},"cache_read_input_tokens":["array","payload"]}}}
{"sessionId":"sess-evil","type":"assistant","message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":42,"output_tokens":7}}}
EOF

    "$ANALYTICS" --history "$tmp/.metrics/token-history.jsonl" \
        --transcript-dir "$tmp/transcripts" \
        --ingest --no-skip-recent > /dev/null 2>&1 || true

    if [ ! -s "$tmp/.metrics/token-history.jsonl" ]; then
        fail "ingest of malicious transcript produced no record (expected coerced numeric record)"
        rm -rf "$tmp"
        return
    fi

    # 1) No string from the malicious payload may appear anywhere in history.
    if grep -qE 'USER_SECRET_INPUT|ASSISTANT_SECRET_OUTPUT|TOOL_ARGS_SECRET|"array"|"payload"' \
        "$tmp/.metrics/token-history.jsonl"; then
        fail "malicious string values leaked into history file"
        rm -rf "$tmp"
        return
    fi

    # 2) Every token field must be numeric; the string values coerce to 0,
    #    so totals reflect ONLY the second well-formed message (in=42, out=7).
    local in_v out_v cc_v cr_v
    in_v=$(jq -r '.input_tokens' "$tmp/.metrics/token-history.jsonl" | head -1)
    out_v=$(jq -r '.output_tokens' "$tmp/.metrics/token-history.jsonl" | head -1)
    cc_v=$(jq -r '.cache_creation_tokens' "$tmp/.metrics/token-history.jsonl" | head -1)
    cr_v=$(jq -r '.cache_read_tokens' "$tmp/.metrics/token-history.jsonl" | head -1)

    if [ "$in_v" = "42" ] && [ "$out_v" = "7" ] && [ "$cc_v" = "0" ] && [ "$cr_v" = "0" ]; then
        pass "string/object usage values coerced to 0; only well-typed numbers reach history (privacy guard)"
    else
        fail "type coercion incomplete: in=$in_v (want 42), out=$out_v (want 7), cc=$cc_v (want 0), cr=$cr_v (want 0)"
    fi
    rm -rf "$tmp"
}

# --- Concurrent ingest: lock prevents duplicate appends ---

test_concurrent_ingest_no_duplicate_session() {
    local tmp
    tmp=$(make_tmp_workspace)
    make_transcript "$tmp/transcripts/sess-conc.jsonl" "sess-conc" 10 100 50 1000 5

    # Fire two ingests simultaneously. Without the lock, both can
    # observe an empty seen_file and both append → 2 records for 1 session.
    "$ANALYTICS" --history "$tmp/.metrics/token-history.jsonl" \
        --transcript-dir "$tmp/transcripts" \
        --ingest --no-skip-recent > /dev/null 2>&1 &
    local p1=$!
    "$ANALYTICS" --history "$tmp/.metrics/token-history.jsonl" \
        --transcript-dir "$tmp/transcripts" \
        --ingest --no-skip-recent > /dev/null 2>&1 &
    local p2=$!
    wait "$p1" 2>/dev/null || true
    wait "$p2" 2>/dev/null || true

    local count uniq_count
    count=$(wc -l < "$tmp/.metrics/token-history.jsonl" | tr -d ' ')
    uniq_count=$(jq -r '.session_id' "$tmp/.metrics/token-history.jsonl" | sort -u | wc -l | tr -d ' ')

    if [ "$count" = "1" ] && [ "$uniq_count" = "1" ]; then
        pass "concurrent ingest is serialized — 1 record per session under simultaneous append"
    else
        fail "concurrent ingest race: $count lines, $uniq_count unique session_ids (want 1/1)"
    fi
    rm -rf "$tmp"
}

# The race above is intermittent: it only fails where `mkdir` is not atomic.
# uutils mkdir 0.10.0 (Ubuntu 26.04 CI runners) checks path.exists(), then
# maps a create_dir error to success when the path is a directory — so two
# writers that both pass the exists-check both "acquire" a mkdir lock. Model
# that mkdir with a shim, and slow jq so the two ingests always overlap.
test_concurrent_ingest_lock_survives_non_atomic_mkdir() {
    local tmp real_mkdir real_jq
    tmp=$(make_tmp_workspace)
    make_transcript "$tmp/transcripts/sess-shim.jsonl" "sess-shim" 10 100 50 1000 5
    real_mkdir=$(command -v mkdir)
    real_jq=$(command -v jq)
    mkdir -p "$tmp/shim"
    printf '#!/bin/bash\nexec "%s" -p "$@"\n' "$real_mkdir" > "$tmp/shim/mkdir"
    printf '#!/bin/bash\nsleep 0.3\nexec "%s" "$@"\n' "$real_jq" > "$tmp/shim/jq"
    chmod +x "$tmp/shim/mkdir" "$tmp/shim/jq"

    PATH="$tmp/shim:$PATH" "$ANALYTICS" --history "$tmp/.metrics/token-history.jsonl" \
        --transcript-dir "$tmp/transcripts" \
        --ingest --no-skip-recent > /dev/null 2>&1 &
    local p1=$!
    PATH="$tmp/shim:$PATH" "$ANALYTICS" --history "$tmp/.metrics/token-history.jsonl" \
        --transcript-dir "$tmp/transcripts" \
        --ingest --no-skip-recent > /dev/null 2>&1 &
    local p2=$!
    wait "$p1" 2>/dev/null || true
    wait "$p2" 2>/dev/null || true

    local count
    count=$(wc -l < "$tmp/.metrics/token-history.jsonl" | tr -d ' ')
    if [ "$count" = "1" ]; then
        pass "concurrent ingest stays serialized when mkdir is not atomic (uutils)"
    else
        fail "lock depends on mkdir atomicity: $count lines for 1 session (want 1)"
    fi
    rm -rf "$tmp"
}

# --- Hook gate ---

test_hook_silent_without_metrics_dir() {
    local tmp
    tmp=$(make_tmp_workspace)
    rm -rf "$tmp/.metrics"   # gate condition: no .metrics dir

    local out
    out=$(CLAUDE_PROJECT_DIR="$tmp" SDLC_TOKEN_SPIKE_TRANSCRIPT_DIR="$tmp/transcripts" \
        bash "$HOOK" 2>&1 < /dev/null | strip_locale_warning) || true
    if [ -z "$out" ]; then
        pass "hook is silent when .metrics/ does not exist (consumer opt-in)"
    else
        fail "hook leaked output without .metrics/: $out"
    fi
    rm -rf "$tmp"
}

test_hook_warns_on_spike() {
    local tmp
    tmp=$(make_tmp_workspace)
    # Pre-seed history with 10 baseline + 1 spike (no transcript ingest needed)
    : > "$tmp/.metrics/token-history.jsonl"
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        local burn=$((1000 + i * 10))
        printf '{"session_id":"hist-%03d","timestamp":"2026-04-27T01:%02d:00Z","input_tokens":%d,"output_tokens":1,"cache_creation_tokens":1,"cache_read_tokens":0,"costly_tokens":%d,"message_count":10}\n' \
            "$i" "$i" "$burn" "$burn" >> "$tmp/.metrics/token-history.jsonl"
    done
    append_history_record "$tmp/.metrics/token-history.jsonl" "spike" 50000

    # Empty transcript dir → hook ingests nothing new, just runs --check on existing history
    mkdir -p "$tmp/transcripts"

    local out
    out=$(CLAUDE_PROJECT_DIR="$tmp" SDLC_TOKEN_SPIKE_TRANSCRIPT_DIR="$tmp/transcripts" \
        bash "$HOOK" 2>&1 < /dev/null | strip_locale_warning) || true
    if echo "$out" | grep -qiE 'WARN|spike|token'; then
        pass "hook warns on detected spike (gated on .metrics/ + visible to user)"
    else
        fail "hook silent on spike. Output: $out"
    fi
    rm -rf "$tmp"
}

# --- Cache-miss regression test (ROADMAP #204 prove-it gate, v1.63.0) ---
#
# #204 was concerned with HN PSA-style 10-20× prompt-cache-cost blowups: when
# cache hits drop unexpectedly (mid-session edits to CLAUDE.md, idle pruning,
# or upstream caching bugs like Anthropic's 2026-04-23 thinking-block drop),
# cache_read collapses and cache_creation spikes. The cost surprise is silent
# — only visible on the invoice. #220's costly_tokens metric (input +
# cache_creation + output, EXCLUDING cache_read) is exactly designed to
# catch this. This test proves the absorption: build a baseline of healthy
# sessions (low cache_creation, high cache_read, low costly_tokens), then
# append a cache-miss session (cache_read=0, cache_creation high, costly
# spike), and assert the spike warning fires. Without this test, we'd be
# claiming #204 is absorbed without proof.

test_cache_miss_pattern_triggers_spike_warning() {
    # End-to-end test: write fixture transcripts with raw cache fields,
    # let `--ingest` compute costly_tokens, then `--check` for the spike.
    # This exercises the FULL chain (ingest → costly_tokens calc → spike
    # detect), so mutating cache_creation_input_tokens here actually moves
    # the test's outcome (Codex round 1 P1 fix).
    #
    # Two-phase ingest: baseline transcripts first, cache-miss transcript
    # second, so the cache-miss row is the LAST line in history (the
    # `--check` candidate is `tail -n 1`).
    local tmp
    tmp=$(make_tmp_workspace)
    local hist="$tmp/.metrics/token-history.jsonl"
    mkdir -p "$tmp/baseline" "$tmp/candidate"

    # Baseline: 20 healthy cache-hit-heavy sessions.
    # Each: 5 messages × (input=20, output=20, cache_creation=20, cache_read=2000)
    # costly_tokens per session = 5 × (20 + 20 + 20) = 300
    local i
    for ((i=1; i<=20; i++)); do
        make_transcript "$tmp/baseline/healthy-$i.jsonl" "healthy-$i" 20 20 20 2000 5
    done

    # Cache-miss session: prefix had to be re-uploaded.
    # 5 messages × (input=20, output=20, cache_creation=10000, cache_read=0)
    # costly_tokens = 5 × (20 + 20 + 10000) = 50200
    make_transcript "$tmp/candidate/cache-miss.jsonl" "cache-miss" 20 20 10000 0 5

    # Phase 1: ingest baseline.
    "$ANALYTICS" --history "$hist" \
        --transcript-dir "$tmp/baseline" \
        --ingest --no-skip-recent > /dev/null 2>&1 || true

    # Phase 2: ingest cache-miss. Appended after baseline → physically last.
    "$ANALYTICS" --history "$hist" \
        --transcript-dir "$tmp/candidate" \
        --ingest --no-skip-recent > /dev/null 2>&1 || true

    # Verify ingest captured the cache-miss session with the expected fields.
    local cm_costly cm_creation cm_read
    cm_costly=$(jq -r 'select(.session_id == "cache-miss") | .costly_tokens' "$hist" | head -1)
    cm_creation=$(jq -r 'select(.session_id == "cache-miss") | .cache_creation_tokens' "$hist" | head -1)
    cm_read=$(jq -r 'select(.session_id == "cache-miss") | .cache_read_tokens' "$hist" | head -1)

    if [ "$cm_costly" != "50200" ] || [ "$cm_creation" != "50000" ] || [ "$cm_read" != "0" ]; then
        fail "ingest did not produce expected cache-miss record (costly=$cm_costly creation=$cm_creation read=$cm_read; expected 50200/50000/0)"
        rm -rf "$tmp"
        return
    fi

    # Confirm cache-miss is the last line (--check uses `tail -n 1`).
    local last_sid
    last_sid=$(tail -n 1 "$hist" | jq -r '.session_id')
    if [ "$last_sid" != "cache-miss" ]; then
        fail "cache-miss is not the last history row (saw '$last_sid'); --check candidate selection broken"
        rm -rf "$tmp"
        return
    fi

    local out
    out=$({ "$ANALYTICS" --history "$hist" --check 2>&1 || true; } | strip_locale_warning)

    if echo "$out" | grep -qiE 'spike|anomal|warning|exceed'; then
        pass "cache-miss pattern triggers spike warning (E2E: transcript→ingest→check, #204 absorbed)"
    else
        fail "cache-miss spike not detected. costly=$cm_costly. Output: $out"
    fi
    rm -rf "$tmp"
}

# Negative control: a session with the OPPOSITE pattern — high cache_read
# and steady cache_creation — must NOT fire. Proves the detector is keying
# on costly_tokens (the cost-bearing fields), not on raw token count.
# Same end-to-end path: transcripts → ingest → check.
test_high_cache_read_no_warning() {
    local tmp
    tmp=$(make_tmp_workspace)
    local hist="$tmp/.metrics/token-history.jsonl"
    mkdir -p "$tmp/baseline" "$tmp/candidate"

    # Baseline: 20 healthy sessions, costly=300 each.
    local i
    for ((i=1; i<=20; i++)); do
        make_transcript "$tmp/baseline/healthy-$i.jsonl" "healthy-$i" 20 20 20 2000 5
    done

    # Hot-cache: cache_read 100× per-message (200000 vs 2000); 5 messages
    # × 200000 = 1,000,000 total cache_read. cache_creation + input + output
    # unchanged → costly_tokens stays 300. Cheaper-per-token, not expensive.
    make_transcript "$tmp/candidate/hot-cache.jsonl" "hot-cache" 20 20 20 200000 5

    "$ANALYTICS" --history "$hist" \
        --transcript-dir "$tmp/baseline" \
        --ingest --no-skip-recent > /dev/null 2>&1 || true
    "$ANALYTICS" --history "$hist" \
        --transcript-dir "$tmp/candidate" \
        --ingest --no-skip-recent > /dev/null 2>&1 || true

    local hc_costly hc_read
    hc_costly=$(jq -r 'select(.session_id == "hot-cache") | .costly_tokens' "$hist" | head -1)
    hc_read=$(jq -r 'select(.session_id == "hot-cache") | .cache_read_tokens' "$hist" | head -1)

    # 5 messages × 200000 cache_read = 1,000,000 total.
    if [ "$hc_costly" != "300" ] || [ "$hc_read" != "1000000" ]; then
        fail "ingest did not produce expected hot-cache record (costly=$hc_costly read=$hc_read; expected 300/1000000)"
        rm -rf "$tmp"
        return
    fi

    local last_sid
    last_sid=$(tail -n 1 "$hist" | jq -r '.session_id')
    if [ "$last_sid" != "hot-cache" ]; then
        fail "hot-cache is not the last history row (saw '$last_sid')"
        rm -rf "$tmp"
        return
    fi

    local out
    out=$({ "$ANALYTICS" --history "$hist" --check 2>&1 || true; } | strip_locale_warning)

    if echo "$out" | grep -qiE 'spike|anomal'; then
        fail "false positive on healthy hot-cache (costly=$hc_costly, raw_reads=$hc_read). Output: $out"
    else
        pass "high cache_read does NOT fire warning (cost-aware metric, not raw-count)"
    fi
    rm -rf "$tmp"
}

# --- Run all ---

test_analytics_exists
test_hook_exists
test_burn_calculation_matches_transcript_sum
test_ingest_is_idempotent
test_spike_detected_when_last_exceeds_threshold
test_no_spike_when_within_threshold
test_no_spike_when_window_too_small
test_median_not_mean
test_flat_baseline_small_uptick_does_not_fire
test_flat_baseline_large_jump_still_fires
test_privacy_string_values_coerced_to_zero
test_concurrent_ingest_no_duplicate_session
test_concurrent_ingest_lock_survives_non_atomic_mkdir
test_hook_silent_without_metrics_dir
test_hook_warns_on_spike
test_cache_miss_pattern_triggers_spike_warning
test_high_cache_read_no_warning

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
