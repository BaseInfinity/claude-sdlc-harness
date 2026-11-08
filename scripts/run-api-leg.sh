#!/bin/bash
# The Fable rung of the review ladder, run on API credit instead of a session.
#
# Usage:
#   scripts/run-api-leg.sh OUTPUT_FILE PROMPT_FILE [--model M] [--base B]
#
# Run from inside the repo under review. One Messages API call: the Review
# Contract (read from skills/sdlc/SKILL.md) is the system prompt, and the user
# turn is PROMPT_FILE plus `git diff B...HEAD` inlined (B defaults to
# origin/main). The structured verdict lands in OUTPUT_FILE.verdict.json, the
# same file and schema as scripts/run-review-leg.sh. Run it as a background
# task. Its exit status is what happened to the leg:
#
#   0   the leg completed and its verdict validated (CERTIFIED or NOT_CERTIFIED)
#   65  the model answered, but the verdict failed the #617 contract
#   70  the API rejected the request itself. This is a launcher or key defect,
#       not a passing outage, so fix it rather than retrying
#   75  leg unavailable: no credit, spend limit hit, 429, 5xx, timeout, network
#       failure, or KEY_CMD failed. NEVER a review finding. Use the existing
#       route instead
#   78  skipped: off by default, or the diff is over the cap. Use the existing
#       route (advisor, or a Fable subagent)
#
# ---------------------------------------------------------------------------
# WHERE THIS SITS ON THE LADDER
#
# Fable rung ONLY. It runs after the driver and Sol fail to reconcile after
# the recheck, or on a second repair to the same component. It never runs
# first, and it never replaces the Sol leg.
#
# OFF BY DEFAULT. Runs only when SDLC_API_LEG_KEY_CMD is set: a command that
# prints the API key on stdout (for example a keychain lookup). This script
# never stores a key, never reads one from a file, and never puts one on a
# command line, where `ps` shows it. The key reaches curl on stdin as a
# `--config` header.
#
# ---------------------------------------------------------------------------
# THE SPEND STOP IS NOT IN THIS FILE. STEFAN SETS IT IN THE CONSOLE.
#
# The money is the monthly subscriber API credit. It covers the Claude API but
# not Claude Code (`claude -p` fails "Credit balance too low"). It expires each
# billing cycle, and once it is spent requests stop rather than being charged
# (platform.claude.com/docs/en/about-claude/api-credits-for-subscribers). There
# is no balance-read endpoint, so nothing here can check a balance first.
#
# REQUIRED before setting KEY_CMD:
#   1. A dedicated Console workspace with a workspace SPEND LIMIT set.
#   2. The key KEY_CMD prints must belong to THAT workspace. A key from any
#      other workspace is not bounded by that limit.
# When the limit or the credit runs out the API returns an error and this
# leg exits 75. That error is the hard stop.
#
# Per-call bounds here are secondary: the diff cap (SDLC_API_LEG_DIFF_CAP
# bytes) bounds input, and MAX_TOKENS bounds output. Thinking tokens count
# toward max_tokens. Each call's `usage` is appended to SDLC_API_LEG_USAGE_LOG
# as ADVISORY telemetry. It never decides whether a leg may run.
#
# ---------------------------------------------------------------------------
# VERIFICATION, STATED HONESTLY (2026-11-08)
#
# - `output_config.effort`: no beta header; claude-fable-5-1 is listed as
#   supported, with `high` as its default. Read verbatim from
#   platform.claude.com/docs/en/build-with-claude/effort.
# - `output_config.format` {type: json_schema}: no beta header; fable-5-1 is
#   supported; `minimum`/`maximum` are NOT supported. Taken from a WebFetch
#   SUMMARY of .../build-with-claude/structured-outputs, not a verbatim read.
# - The credit/billing 400 wording is matched by keyword. Only "credit balance
#   is too low" has been observed, via `claude -p`. The spend-limit wording is
#   inferred.
# - This request has NEVER been sent to the live API. The suite
#   (tests/test-run-api-leg.sh) stubs curl. The first real call is the first
#   test of the request shape. A shape error shows up as exit 70, with the
#   API's own message in OUTPUT_FILE.
#
# No Agent SDK: it would add a dependency to a zero-dependency repo, and a
# review leg needs no tools when the diff is inlined.

set -e

usage() {
    echo "usage: $0 OUTPUT_FILE PROMPT_FILE [--model M] [--base B]" >&2
    exit 64
}

[ $# -ge 2 ] || usage
OUTPUT="$1"
PROMPT_FILE="$2"
shift 2

MODEL="claude-fable-5-1"
BASE="origin/main"
while [ $# -gt 0 ]; do
    case "$1" in
        --model) [ $# -ge 2 ] || usage; MODEL="$2"; shift 2 ;;
        --base)  [ $# -ge 2 ] || usage; BASE="$2"; shift 2 ;;
        *) usage ;;
    esac
done
[ -f "$PROMPT_FILE" ] || { echo "prompt file not found: $PROMPT_FILE" >&2; exit 64; }

# First round runs at high effort. MAX_TOKENS is fixed on purpose, because it
# is the per-call output bound.
EFFORT="high"
MAX_TOKENS=32000
DIFF_CAP="${SDLC_API_LEG_DIFF_CAP:-200000}"
CURL_MAX_TIME="${SDLC_API_LEG_MAX_TIME:-900}"
USAGE_LOG="${SDLC_API_LEG_USAGE_LOG:-.reviews/api-leg-usage.jsonl}"

# Schema and contract are resolved from this script's own location, matching
# run-review-leg.sh. Both are the SHIPPED copies, so no second copy can drift.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA="$SCRIPT_DIR/../skills/sdlc/review-verdict.schema.json"
SKILL="$SCRIPT_DIR/../skills/sdlc/SKILL.md"
VERDICT="$OUTPUT.verdict.json"

: > "$OUTPUT"
# Removed before anything else, so no early exit leaves the PREVIOUS run's
# verdict to be read as this one's (see run-review-leg.sh).
rm -f "$VERDICT"

say() { echo "$*" >> "$OUTPUT"; }

if [ -z "${SDLC_API_LEG_KEY_CMD:-}" ]; then
    say "API LEG SKIPPED: SDLC_API_LEG_KEY_CMD is not set (off by default)."
    say "Use the existing Fable route (advisor, or a Fable subagent)."
    exit 78
fi

DIFF=$(git diff "$BASE...HEAD") || {
    say "API LEG FAILED: git diff $BASE...HEAD did not run."
    exit 70
}
DIFF_BYTES=$(printf '%s' "$DIFF" | wc -c | tr -d ' ')
if [ "$DIFF_BYTES" -gt "$DIFF_CAP" ]; then
    say "API LEG SKIPPED: diff is $DIFF_BYTES bytes, over the $DIFF_CAP-byte cap."
    say "Too large for the API leg. Use the existing Fable route."
    exit 78
fi

# The section from its heading up to the next `## ` heading.
CONTRACT=$(awk '/^## The Review Contract/{on=1} on && /^## / && !/^## The Review Contract/{exit} on' "$SKILL")
if [ -z "$CONTRACT" ]; then
    say "API LEG FAILED: no '## The Review Contract' section in $SKILL."
    exit 70
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/run-api-leg.XXXXXX") || exit 70
trap 'rm -rf "$WORK"' EXIT

printf '%s' "$CONTRACT" > "$WORK/contract.md"
{
    cat "$PROMPT_FILE"
    printf '\n\n## DIFF UNDER REVIEW (git diff %s...HEAD)\n\n```diff\n%s\n```\n' "$BASE" "$DIFF"
} > "$WORK/user.md"

# The shipped schema says minimum/maximum were "proved accepted". That proof
# was against the OpenAI provider (codex --output-schema). Anthropic structured
# outputs reject them, so they are removed from the copy sent here. The reply
# is still validated against the UNSTRIPPED schema below, so the bounds still
# hold.
jq -n \
    --arg model "$MODEL" \
    --argjson max_tokens "$MAX_TOKENS" \
    --arg effort "$EFFORT" \
    --rawfile system "$WORK/contract.md" \
    --rawfile user "$WORK/user.md" \
    --slurpfile schema "$SCHEMA" \
    '{
        model: $model,
        max_tokens: $max_tokens,
        system: $system,
        messages: [{role: "user", content: $user}],
        output_config: {
            effort: $effort,
            format: {
                type: "json_schema",
                schema: ($schema[0] | walk(if type == "object"
                    then del(.minimum, .maximum, ."$schema") else . end))
            }
        }
    }' > "$WORK/request.json"

set +e
KEY=$(sh -c "$SDLC_API_LEG_KEY_CMD" < /dev/null 2>/dev/null)
KEY_RC=$?
set -e
if [ "$KEY_RC" -ne 0 ] || [ -z "$KEY" ]; then
    say "API LEG UNAVAILABLE: SDLC_API_LEG_KEY_CMD failed or printed nothing."
    exit 75
fi

say "## API LEG ($MODEL, effort $EFFORT, max_tokens $MAX_TOKENS, diff $DIFF_BYTES bytes)"
say ""

# A deadline on every call. A stalled POST with none is #590 again.
set +e
HTTP_CODE=$(printf 'header = "x-api-key: %s"\n' "$KEY" | curl -sS \
    --config - \
    --connect-timeout 20 \
    --max-time "$CURL_MAX_TIME" \
    -X POST https://api.anthropic.com/v1/messages \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    --data-binary "@$WORK/request.json" \
    -o "$WORK/response.json" \
    -w '%{http_code}' 2>> "$OUTPUT")
CURL_RC=$?
set -e
unset KEY

if [ "$CURL_RC" -ne 0 ]; then
    say "API LEG UNAVAILABLE: curl exit $CURL_RC (network or timeout). Not a finding."
    exit 75
fi

if [ "$HTTP_CODE" != "200" ]; then
    say "HTTP $HTTP_CODE"
    cat "$WORK/response.json" >> "$OUTPUT" 2>/dev/null || true
    say ""
    MSG=$(jq -r '.error.message // ""' "$WORK/response.json" 2>/dev/null || true)
    case "$HTTP_CODE" in
        429|5??) UNAVAILABLE=1 ;;
        400) echo "$MSG" | grep -qiE 'credit|billing|spend' && UNAVAILABLE=1 ;;
    esac
    if [ "${UNAVAILABLE:-0}" = "1" ]; then
        say "API LEG UNAVAILABLE (HTTP $HTTP_CODE). Not a finding. Use the existing route."
        exit 75
    fi
    say "API LEG REQUEST REJECTED (HTTP $HTTP_CODE). Launcher or key defect; fix it, do not retry."
    exit 70
fi

# Advisory only. A failed write never fails the leg.
mkdir -p "$(dirname "$USAGE_LOG")" 2>/dev/null || true
jq -c --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{ts: $ts, model: .model, stop_reason: .stop_reason, usage: .usage}' \
    "$WORK/response.json" >> "$USAGE_LOG" 2>/dev/null || true

say "stop_reason: $(jq -r '.stop_reason' "$WORK/response.json")"
say "usage: $(jq -c '.usage' "$WORK/response.json")"
say ""
# By block type, never by index: with thinking on, the first block may be a
# thinking block.
jq -r '[.content[] | select(.type == "text") | .text] | join("")' \
    "$WORK/response.json" > "$VERDICT"
cat "$VERDICT" >> "$OUTPUT"
say ""

# A max_tokens cut-off or a refusal fails here and exits 65. There is no
# separate branch for either.
if ! python3 "$SCRIPT_DIR/validate-review-verdict.py" "$VERDICT" "$SCHEMA" >> "$OUTPUT" 2>&1; then
    say ""
    say "## INCOMPLETE LEG (#617)"
    say "The model answered, but its verdict did not satisfy the contract (reason"
    say "above). Relaunch. Do not fill the fields in yourself."
    exit 65
fi
