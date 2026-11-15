#!/bin/bash
# Guard skills/conduct/scripts/handoff.cjs (write/read/list) and
# hooks/handoff-check.sh (once-per-session context reminder).
# Real temp dirs and real git repos; nothing is mocked.

set -u

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$REPO_ROOT/skills/conduct/scripts/handoff.cjs"
HOOK="$REPO_ROOT/hooks/handoff-check.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

T=$(mktemp -d "${TMPDIR:-/tmp}/handoff.XXXXXX") || { echo "cannot create temp dir"; exit 1; }
trap 'rm -rf "$T"' EXIT

REPO="$T/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false \
    commit -q --allow-empty -m init
HEAD_SHA=$(git -C "$REPO" rev-parse HEAD)

h() { node "$HELPER" "$@"; }
jget() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {}, {'d': d}))" "$@"; }

echo "=== write ==="
OUT=$(h write --root "$REPO" --session claude:AAAA --branch feat/x --id h1 2>&1)
F="$REPO/.brain/handoffs/h1.json"
if [ -f "$F" ] && python3 -c "import json; json.load(open('$F'))" 2>/dev/null; then
    pass "write creates valid JSON at .brain/handoffs/<id>.json"
else
    fail "write creates valid JSON at .brain/handoffs/<id>.json ($OUT)"
fi
[ "$(jget "$F" "d['v'], d['id'], d['session'], d['branch'], d['sha']")" = "(1, 'h1', 'claude:AAAA', 'feat/x', '$HEAD_SHA')" ] \
    && pass "skeleton records v, id, session, branch, HEAD sha" \
    || fail "skeleton records v, id, session, branch, HEAD sha"
[ "$(jget "$F" "(d['tasks'], d['next_steps'], d['warnings'], d['worktrees'], d['open_prs'], d['held_items'])")" \
    = "({'completed': [], 'in_progress': [], 'blocked': []}, [], [], [], [], [])" ] \
    && pass "skeleton has empty arrays" || fail "skeleton has empty arrays"
jget "$F" "d['created']" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' \
    && pass "created is an ISO timestamp" || fail "created is an ISO timestamp"

h write --root "$REPO" --session claude:AAAA --branch feat/x --id h1 >/dev/null 2>&1 \
    && fail "write refuses to overwrite an existing id" || pass "write refuses to overwrite an existing id"

for missing in root session branch; do
    args=(--root "$REPO" --session claude:AAAA --branch feat/x)
    case "$missing" in
        root) args=(--session claude:AAAA --branch feat/x) ;;
        session) args=(--root "$REPO" --branch feat/x) ;;
        branch) args=(--root "$REPO" --session claude:AAAA) ;;
    esac
    h write "${args[@]}" >/dev/null 2>&1 \
        && fail "write rejects missing --$missing" || pass "write rejects missing --$missing"
done
h write --root "$REPO" --session nocolon --branch feat/x >/dev/null 2>&1 \
    && fail "write rejects session without a colon" || pass "write rejects session without a colon"
h write --root "$REPO/nope" --session claude:A --branch b >/dev/null 2>&1 \
    && fail "write rejects a root that is not a directory" || pass "write rejects a root that is not a directory"
h write --root "$REPO" --session claude:A --branch b --id ../evil >/dev/null 2>&1 \
    && fail "write rejects an unsafe id" || pass "write rejects an unsafe id"

LINKED="$T/linked"
mkdir -p "$LINKED/.brain" "$T/elsewhere"
ln -s "$T/elsewhere" "$LINKED/.brain/handoffs"
h write --root "$LINKED" --session claude:A --branch b --id s1 >/dev/null 2>&1 \
    && fail "write refuses a symlinked state path" || pass "write refuses a symlinked state path"
[ ! -e "$T/elsewhere/s1.json" ] && pass "nothing written through the symlink" || fail "nothing written through the symlink"

cat > "$T/data.json" <<'JSON'
{
  "id": "spoofed", "session": "codex:spoof", "branch": "spoof", "sha": "spoof", "v": 9,
  "tasks": {"completed": ["did A"], "in_progress": ["doing B"],
            "blocked": [{"task": "C", "reason": "needs key"}]},
  "next_steps": ["First do X", "Then Y"],
  "warnings": ["Don't touch Z"],
  "worktrees": ["/w/one"],
  "open_prs": [786, 785],
  "held_items": [{"item": "release", "waiting_on": "Stefan"}]
}
JSON
h write --root "$REPO" --session codex:BBBB --branch main --id h2 --file "$T/data.json" >/dev/null 2>&1
F2="$REPO/.brain/handoffs/h2.json"
[ "$(jget "$F2" "(d['tasks']['blocked'][0]['reason'], d['next_steps'], d['open_prs'], d['held_items'][0]['waiting_on'], d['worktrees'], d['warnings'])")" \
    = "('needs key', ['First do X', 'Then Y'], [786, 785], 'Stefan', ['/w/one'], [\"Don't touch Z\"])" ] \
    && pass "write --file populates the full schema" || fail "write --file populates the full schema"
[ "$(jget "$F2" "(d['v'], d['id'], d['session'], d['branch'], d['sha'])")" = "(1, 'h2', 'codex:BBBB', 'main', '$HEAD_SHA')" ] \
    && pass "args and generated fields win over --file" || fail "args and generated fields win over --file"
echo '{"tasks": {"completed": "not-a-list"}}' > "$T/bad.json"
h write --root "$REPO" --session claude:A --branch b --id h3 --file "$T/bad.json" >/dev/null 2>&1 \
    && fail "write --file rejects a malformed field" || pass "write --file rejects a malformed field"
for bad in '{"tasks": {"blocked": ["not-an-object"]}}' \
           '{"tasks": {"blocked": [{"task": "C"}]}}' \
           '{"held_items": [{"item": "x"}]}' \
           '{"next_steps": [1]}' \
           '{"open_prs": ["786"]}'; do
    n=$((${n:-0} + 1))
    printf '%s' "$bad" > "$T/bad.json"
    h write --root "$REPO" --session claude:A --branch b --id "bad-$n" --file "$T/bad.json" >/dev/null 2>&1 \
        && fail "write --file rejects $bad" || pass "write --file rejects $bad"
done
[ -z "$(ls "$REPO/.brain/handoffs" | grep -E '^(h3|bad-)')" ] && pass "no malformed handoff was persisted" || fail "no malformed handoff was persisted"

echo "=== read ==="
EMPTY="$T/empty"; mkdir -p "$EMPTY"
ERR=$(h read --root "$EMPTY" 2>&1); RC=$?
[ "$RC" -ne 0 ] && echo "$ERR" | grep -q "no handoffs" \
    && pass "read with no handoffs fails with a clear message" || fail "read with no handoffs fails with a clear message ($RC: $ERR)"

# h1 and h2 were written in that order; force distinct created times so
# "latest" is decided by the created field, not by write order or mtime.
python3 - "$REPO/.brain/handoffs" <<'PY'
import json, os, sys
base = sys.argv[1]
for name, ts in (("h1.json", "2026-11-14T20:00:00.000Z"), ("h2.json", "2026-11-14T19:00:00.000Z")):
    p = os.path.join(base, name)
    d = json.load(open(p)); d["created"] = ts
    open(p, "w").write(json.dumps(d, indent=2) + "\n")
PY
[ "$(h read --root "$REPO" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')" = "h1" ] \
    && pass "read returns the latest handoff by created" || fail "read returns the latest handoff by created"
[ "$(h read --root "$REPO" --id h2 | python3 -c 'import json,sys; print(json.load(sys.stdin)["next_steps"][0])')" = "First do X" ] \
    && pass "read --id returns that handoff" || fail "read --id returns that handoff"
h read --root "$REPO" --id missing >/dev/null 2>&1 \
    && fail "read --id of a missing handoff fails" || pass "read --id of a missing handoff fails"

echo "=== list ==="
h write --root "$REPO" --session claude:CCCC --branch feat/y --id h4 >/dev/null 2>&1
LIST=$(h list --root "$REPO")
[ "$(printf '%s\n' "$LIST" | python3 -c 'import json,sys; print(",".join(json.loads(l)["id"] for l in sys.stdin))')" = "h4,h1,h2" ] \
    && pass "list returns handoffs newest first" || fail "list returns handoffs newest first ($LIST)"
[ "$(printf '%s\n' "$LIST" | head -1 | python3 -c 'import json,sys; print(sorted(json.load(sys.stdin)))')" \
    = "['branch', 'created', 'id', 'session', 'sha']" ] \
    && pass "list rows carry id, created, session, branch, sha" || fail "list rows carry id, created, session, branch, sha"
[ "$(h list --root "$REPO" --limit 1 | wc -l | tr -d ' ')" = "1" ] \
    && pass "list --limit caps the rows" || fail "list --limit caps the rows"
LE=$(h list --root "$EMPTY" 2>&1) && [ -z "$LE" ] && pass "list with no handoffs prints nothing" || fail "list with no handoffs prints nothing"

echo "=== handoff-check.sh ==="
TR="$T/transcript.jsonl"
HT="$T/hooktmp"; mkdir -p "$HT"
head -c 2048 /dev/zero > "$TR"
payload() { printf '{"session_id":"%s","transcript_path":"%s","tool_name":"Bash"}' "$1" "$TR"; }
run_hook() { printf '%s' "$(payload "$1")" | TMPDIR="$HT" SDLC_HANDOFF_THRESHOLD_BYTES=1024 "$HOOK" 2>&1; }

OUT1=$(run_hook sess-1); RC1=$?
[ "$RC1" -eq 0 ] && echo "$OUT1" | grep -q "Consider running /conduct handoff" \
    && pass "hook reminds when the transcript exceeds the threshold" || fail "hook reminds when over threshold ($RC1: $OUT1)"
echo "$OUT1" | grep -q '"additionalContext"' \
    && pass "hook surfaces the reminder as additionalContext" || fail "hook surfaces the reminder as additionalContext"
OUT2=$(run_hook sess-1); RC2=$?
[ "$RC2" -eq 0 ] && [ -z "$OUT2" ] \
    && pass "hook fires only once per session (marker file)" || fail "hook fires only once per session ($OUT2)"
run_hook sess-2 | grep -q "Consider running /conduct handoff" && pass "a new session gets its own reminder" || fail "a new session gets its own reminder"

head -c 100 /dev/zero > "$TR"
OUT3=$(run_hook sess-3); RC3=$?
[ "$RC3" -eq 0 ] && [ -z "$OUT3" ] && [ -z "$(ls "$HT" | grep sess-3)" ] \
    && pass "hook stays silent and leaves no marker under the threshold" || fail "hook silent under threshold ($OUT3)"
head -c 2048 /dev/zero > "$TR"
for i in $(seq 1 40); do
    run_hook race-1 > "$HT/race.$i" &
done
wait
RACE=$(grep -l "Consider running /conduct handoff" "$HT"/race.* | wc -l | tr -d ' ')
[ "$RACE" = "1" ] && pass "40 concurrent calls in one session emit exactly one reminder" \
    || fail "40 concurrent calls in one session emit exactly one reminder (got $RACE)"
OUT4=$(printf '{"session_id":"../x","transcript_path":"%s/none"}' "$T" | TMPDIR="$HT" "$HOOK" 2>&1); RC4=$?
[ "$RC4" -eq 0 ] && [ -z "$OUT4" ] \
    && pass "hook is silent when the transcript is missing" || fail "hook silent on missing transcript ($OUT4)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
