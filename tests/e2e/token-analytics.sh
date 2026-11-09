#!/bin/bash
# token-analytics.sh — token-spike anomaly detection (ROADMAP #220)
#
# Catches silent CC-side regressions (caching bugs, prompt-inflation defaults)
# by tracking per-session token burn over time. Anthropic's 2026-04-23
# post-mortem documented a caching bug that "continuously dropped thinking
# blocks from subsequent requests" — invisible until the invoice arrived.
# Token-burn deviation from a rolling baseline catches it earlier.
#
# Usage:
#   ./token-analytics.sh                         # print stats summary
#   ./token-analytics.sh --report                # markdown report
#   ./token-analytics.sh --ingest                # scan transcripts, append history
#   ./token-analytics.sh --check                 # emit warning if last burn >2σ
#   ./token-analytics.sh --ingest --check        # combined (hook usage)
#
# Options:
#   --history PATH         History file (default: $REPO/.metrics/token-history.jsonl)
#   --transcript-dir PATH  Transcript scan dir (default: ~/.claude/projects/<sanitized-cwd>)
#   --metric median|mean   Spike comparator (default: median)
#   --window N             Rolling window size for baseline (default: 20)
#   --threshold-sigma N    Sigma multiplier (default: 2)
#   --min-baseline N       Minimum baseline records before flagging (default: 5)
#   --no-skip-recent       Don't skip transcripts modified in last 5 min (test mode)
#
# Records appended to history file (one JSON object per line):
#   {
#     "session_id": "<uuid>",
#     "timestamp": "<ISO>",
#     "input_tokens": N,
#     "output_tokens": N,
#     "cache_creation_tokens": N,
#     "cache_read_tokens": N,
#     "costly_tokens": <input + cache_creation + output>,
#     "message_count": N
#   }
#
# costly_tokens excludes cache_read on purpose: cache reads bill at ~10% of
# normal input rate ($1.50/M vs $15/M on Opus). The Anthropic April-23 bug
# manifested as cache_read DOWN + cache_creation UP — exactly what costly
# captures.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

HISTORY_FILE="$REPO_ROOT/.metrics/token-history.jsonl"
TRANSCRIPT_DIR=""
INGEST=false
CHECK=false
REPORT=false
METRIC="median"
WINDOW=20
SIGMA=2
MIN_BASELINE=5
SKIP_RECENT=true

while [ $# -gt 0 ]; do
    case "$1" in
        --history)            HISTORY_FILE="$2"; shift 2;;
        --transcript-dir)     TRANSCRIPT_DIR="$2"; shift 2;;
        --ingest)             INGEST=true; shift;;
        --check)              CHECK=true; shift;;
        --report)             REPORT=true; shift;;
        --metric)             METRIC="$2"; shift 2;;
        --window)             WINDOW="$2"; shift 2;;
        --threshold-sigma)    SIGMA="$2"; shift 2;;
        --min-baseline)       MIN_BASELINE="$2"; shift 2;;
        --no-skip-recent)     SKIP_RECENT=false; shift;;
        *)                    shift;;
    esac
done

if ! command -v jq > /dev/null 2>&1; then
    echo "Error: jq is required" >&2
    exit 1
fi

mkdir -p "$(dirname "$HISTORY_FILE")"

# --- Derive default transcript dir from CWD ---
default_transcript_dir() {
    # CC stores per-project transcripts at ~/.claude/projects/<sanitized-cwd>/
    # Sanitization replaces / with - and prefixes with -.
    local cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
    local sanitized
    sanitized=$(echo "$cwd" | sed 's|/|-|g')
    echo "$HOME/.claude/projects/$sanitized"
}

if [ -z "$TRANSCRIPT_DIR" ]; then
    TRANSCRIPT_DIR=$(default_transcript_dir)
fi

# --- Ingest: scan transcripts, append new session records ---
ingest_transcripts() {
    [ -d "$TRANSCRIPT_DIR" ] || return 0

    # Lock to serialize concurrent ingests against shared $HISTORY_FILE. Two
    # CC sessions starting simultaneously both call this hook; without a lock
    # they race the seen-file → append window and can double-write the same
    # session_id (Codex finding #4). noclobber makes bash itself open the
    # lock file with O_EXCL, so the kernel decides. Do not use `mkdir`: uutils
    # mkdir 0.10.0 (Ubuntu 26.04) reports success when the directory already
    # exists after a lost race, so two writers both took the lock.
    local lock_file lock_acquired=false
    lock_file="$HISTORY_FILE.lock"
    local lock_attempts=0
    while [ "$lock_attempts" -lt 50 ]; do
        if (set -C; : > "$lock_file") 2>/dev/null; then
            lock_acquired=true
            break
        fi
        # Stale lock detection: if the lock file is older than 5 minutes,
        # something crashed mid-ingest. Take it over.
        if [ -f "$lock_file" ]; then
            local lock_mtime
            if stat -f %m "$lock_file" > /dev/null 2>&1; then
                lock_mtime=$(stat -f %m "$lock_file")
            else
                lock_mtime=$(stat -c %Y "$lock_file" 2>/dev/null || echo 0)
            fi
            if [ "$(($(date +%s) - lock_mtime))" -gt 300 ]; then
                rm -f "$lock_file" 2>/dev/null || true
            fi
        fi
        sleep 0.1
        lock_attempts=$((lock_attempts + 1))
    done
    if [ "$lock_acquired" != "true" ]; then
        # Couldn't get the lock after 5s — bail silently rather than risk a race
        return 0
    fi
    # shellcheck disable=SC2064
    trap "rm -f '$lock_file' 2>/dev/null || true" RETURN

    # Existing session_ids in history (idempotency keys)
    local seen_file
    seen_file=$(mktemp "${TMPDIR:-/tmp}/token-seen.XXXXXX")
    if [ -s "$HISTORY_FILE" ]; then
        jq -r '.session_id' "$HISTORY_FILE" 2>/dev/null > "$seen_file" || true
    fi

    local now skip_threshold
    now=$(date +%s)
    skip_threshold=$((now - 300))   # 5 minutes ago

    local transcript sid mtime
    for transcript in "$TRANSCRIPT_DIR"/*.jsonl; do
        [ -f "$transcript" ] || continue
        sid=$(basename "$transcript" .jsonl)

        # Idempotency: skip if already in history
        if grep -qxF "$sid" "$seen_file" 2>/dev/null; then
            continue
        fi

        # Skip recent (likely active) transcripts
        if [ "$SKIP_RECENT" = "true" ]; then
            if stat -f %m "$transcript" > /dev/null 2>&1; then
                mtime=$(stat -f %m "$transcript")
            else
                mtime=$(stat -c %Y "$transcript" 2>/dev/null || echo 0)
            fi
            if [ "$mtime" -gt "$skip_threshold" ]; then
                continue
            fi
        fi

        # Sum usage fields across all assistant messages with a usage block.
        # Type-safe coercion: `(. | numbers // 0)` keeps numeric values and
        # discards strings/objects/arrays. Without this, a transcript with
        # `usage.input_tokens: "USER_SECRET"` would copy the string verbatim
        # into history (Codex finding #1 — privacy/type leak).
        local record
        record=$(jq -c -s --arg sid "$sid" '
            def num: if type == "number" then . else 0 end;
            map(select(.message.usage)) as $msgs
            | ($msgs | length) as $count
            | if $count == 0 then empty else
                ($msgs | map(.message.usage.input_tokens | num) | add) as $in
                | ($msgs | map(.message.usage.output_tokens | num) | add) as $out
                | ($msgs | map(.message.usage.cache_creation_input_tokens | num) | add) as $cc
                | ($msgs | map(.message.usage.cache_read_input_tokens | num) | add) as $cr
                | ($msgs | last | .timestamp) as $rawts
                | (if ($rawts | type) == "string" then $rawts else "" end) as $ts
                | {
                    session_id: $sid,
                    timestamp: $ts,
                    input_tokens: ($in | floor),
                    output_tokens: ($out | floor),
                    cache_creation_tokens: ($cc | floor),
                    cache_read_tokens: ($cr | floor),
                    costly_tokens: (($in + $cc + $out) | floor),
                    message_count: $count
                }
              end
        ' "$transcript" 2>/dev/null) || record=""

        if [ -n "$record" ] && [ "$record" != "null" ]; then
            echo "$record" >> "$HISTORY_FILE"
            echo "$sid" >> "$seen_file"
        fi
    done

    rm -f "$seen_file"
}

# --- Stats helpers ---

extract_burns() {
    [ -s "$HISTORY_FILE" ] || return 0
    jq -r '.costly_tokens' "$HISTORY_FILE"
}

# Median over stdin (one number per line). Empty input → 0.
calc_median() {
    sort -n | awk '
        { a[NR] = $1 }
        END {
            if (NR == 0) { print 0; exit }
            if (NR % 2 == 1) print a[(NR + 1) / 2]
            else printf "%.4f\n", (a[NR/2] + a[NR/2+1]) / 2
        }
    '
}

calc_mean() {
    awk '
        { s += $1; n++ }
        END { if (n == 0) print 0; else printf "%.4f\n", s / n }
    '
}

# Population stdev. Empty/single-item → 0.
calc_stdev() {
    awk '
        { s += $1; ss += $1 * $1; n++ }
        END {
            if (n < 2) { print 0; exit }
            m = s / n
            v = (ss / n) - (m * m)
            if (v < 0) v = 0
            printf "%.4f\n", sqrt(v)
        }
    '
}

# MAD (median absolute deviation): robust spread measure. Pairs with median
# the way stdev pairs with mean. Single outlier in the baseline doesn't
# inflate MAD the way it inflates stdev. Args: $1 = median (already computed).
calc_mad() {
    local center="$1"
    awk -v c="$center" '
        { v = $1 - c; if (v < 0) v = -v; print v }
    ' | calc_median
}

# --- Check: detect spike in last record ---
check_spike() {
    [ -s "$HISTORY_FILE" ] || return 0

    local total
    total=$(wc -l < "$HISTORY_FILE" | tr -d ' ')
    if [ "$total" -lt $((MIN_BASELINE + 1)) ]; then
        return 0   # not enough data
    fi

    # Last record = candidate
    local candidate
    candidate=$(tail -n 1 "$HISTORY_FILE" | jq -r '.costly_tokens')
    [ -n "$candidate" ] && [ "$candidate" != "null" ] || return 0

    # Baseline = last $WINDOW records EXCLUDING the candidate
    local baseline_burns center stdev threshold
    baseline_burns=$(head -n -1 "$HISTORY_FILE" 2>/dev/null \
        | tail -n "$WINDOW" \
        | jq -r '.costly_tokens')
    if [ -z "$baseline_burns" ]; then
        # `head -n -1` differs on macOS — fall back: take all but last
        baseline_burns=$(awk -v total="$total" 'NR < total' "$HISTORY_FILE" \
            | tail -n "$WINDOW" \
            | jq -r '.costly_tokens')
    fi

    local baseline_count
    baseline_count=$(echo "$baseline_burns" | grep -c .) || baseline_count=0
    if [ "${baseline_count:-0}" -lt "$MIN_BASELINE" ]; then
        return 0
    fi

    if [ "$METRIC" = "mean" ]; then
        center=$(echo "$baseline_burns" | calc_mean)
        stdev=$(echo "$baseline_burns" | calc_stdev)
    else
        center=$(echo "$baseline_burns" | calc_median)
        # MAD pairs with median — robust to single baseline outliers.
        # For ~normal data, MAD * 1.4826 ≈ stdev, so SIGMA σ ≈ (SIGMA*1.4826)*MAD.
        # We absorb the constant and pass the user's SIGMA through directly,
        # treating the threshold as "k MADs above median" (k=2 ≈ 1.35σ; close
        # enough for anomaly detection where false-positives are cheap).
        local mad
        mad=$(echo "$baseline_burns" | calc_mad "$center")
        # Scale MAD to a stdev-equivalent so SIGMA stays interpretable
        # consistently across --metric values. 1.4826 is the MAD→stdev
        # constant for normal distributions.
        stdev=$(awk -v m="$mad" 'BEGIN { printf "%.4f", m * 1.4826 }')
    fi

    # threshold = center + sigma * spread, with a minimum-spread floor.
    # Without the floor, a flat baseline (all identical values) yields
    # spread=0 → threshold=center → any 1-token uptick fires (Codex finding
    # #2). Floor: max(SIGMA * spread, 5% of center, 1000 absolute tokens).
    # The 5% / 1000 numbers are heuristic — large enough to avoid noise on
    # boring sessions, small enough that real cache regressions still trip.
    threshold=$(awk -v c="$center" -v s="$stdev" -v sig="$SIGMA" '
        BEGIN {
            margin = sig * s
            rel_floor = c * 0.05
            abs_floor = 1000
            if (margin < rel_floor) margin = rel_floor
            if (margin < abs_floor) margin = abs_floor
            printf "%.4f", c + margin
        }')

    local is_spike
    is_spike=$(awk -v cand="$candidate" -v thr="$threshold" \
        'BEGIN { print (cand + 0 > thr + 0) ? "yes" : "no" }')

    if [ "$is_spike" = "yes" ]; then
        local sid
        sid=$(tail -n 1 "$HISTORY_FILE" | jq -r '.session_id')
        cat <<MSG
WARNING: token-burn spike detected (ROADMAP #220)
  Last session: $sid
  Costly tokens: $candidate (input + cache_creation + output)
  Baseline ${METRIC}: $center over last $baseline_count sessions
  Threshold: $threshold (${METRIC} + ${SIGMA}σ)
  This may indicate a CC-side caching regression or prompt-inflation default.
  Review: tail -1 "$HISTORY_FILE" | jq
MSG
    fi
}

# --- Report: markdown summary ---
print_report() {
    local total
    if [ ! -s "$HISTORY_FILE" ]; then
        echo "# Token Burn History"
        echo ""
        echo "No sessions recorded yet. Run with \`--ingest\`."
        return
    fi
    total=$(wc -l < "$HISTORY_FILE" | tr -d ' ')
    local burns median mean stdev_v latest
    burns=$(extract_burns)
    median=$(echo "$burns" | calc_median)
    mean=$(echo "$burns" | calc_mean)
    stdev_v=$(echo "$burns" | calc_stdev)
    latest=$(tail -n 1 "$HISTORY_FILE" | jq -r '.costly_tokens')

    echo "# Token Burn History"
    echo ""
    echo "| Metric | Value |"
    echo "|--------|-------|"
    echo "| Sessions | $total |"
    echo "| Median costly tokens | $median |"
    echo "| Mean costly tokens | $mean |"
    echo "| Stdev | $stdev_v |"
    echo "| Latest session burn | $latest |"
    echo ""
    echo "_Costly tokens = input + cache_creation + output (cache_read excluded; bills at ~10%)._"
}

# --- Default summary ---
print_summary() {
    if [ ! -s "$HISTORY_FILE" ]; then
        echo "No token history yet. Run with --ingest to populate."
        return
    fi
    local total burns median mean stdev_v latest
    total=$(wc -l < "$HISTORY_FILE" | tr -d ' ')
    burns=$(extract_burns)
    median=$(echo "$burns" | calc_median)
    mean=$(echo "$burns" | calc_mean)
    stdev_v=$(echo "$burns" | calc_stdev)
    latest=$(tail -n 1 "$HISTORY_FILE" | jq -r '.costly_tokens')

    echo "=== Token Burn History ==="
    echo "  Sessions:           $total"
    echo "  Median costly:      $median"
    echo "  Mean costly:        $mean"
    echo "  Stdev:              $stdev_v"
    echo "  Latest burn:        $latest"
    echo ""
    echo "  Spike threshold (${METRIC} + ${SIGMA}σ over last $WINDOW): $(awk -v c="$median" -v s="$stdev_v" -v sig="$SIGMA" 'BEGIN { printf "%.0f", c + sig * s }')"
}

# --- Main ---

if [ "$INGEST" = "true" ]; then
    ingest_transcripts
fi

if [ "$CHECK" = "true" ]; then
    check_spike
elif [ "$REPORT" = "true" ]; then
    print_report
elif [ "$INGEST" = "false" ]; then
    print_summary
fi
