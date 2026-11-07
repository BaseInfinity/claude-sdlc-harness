#!/bin/bash
# Guard skills/conduct/: the Claude adapter must speak the SAME protocol as the
# Codex adapter through the SAME helper. The helper and protocol are vendored
# byte-identical from codex-sdlc-wizard; the pinned hashes are the parity record.
# When Codex changes them, re-vendor and update the pins together.

set -u

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SKILL_DIR="$REPO_ROOT/skills/conduct"
HELPER="$SKILL_DIR/scripts/conduct.cjs"

HELPER_SHA="53ed69e212151d6eddc850e1bc651d1b1b534e4513b1ae3eda95eb9d2cf5d9a6"
PROTOCOL_SHA="0f6f075b02e543944a057b28011e1cc2a39070da4bd281628fa4ddc9c0e01ee9"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

TMPDIR_T=$(mktemp -d "${TMPDIR:-/tmp}/conduct.XXXXXX") || {
    echo "cannot create temp dir"; exit 1
}
trap 'rm -rf "$TMPDIR_T"' EXIT

sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }

echo "=== vendored parity ==="
[ "$(sha "$HELPER")" = "$HELPER_SHA" ] \
    && pass "conduct.cjs matches pinned Codex helper" \
    || fail "conduct.cjs drifted from pinned Codex helper"
[ "$(sha "$SKILL_DIR/references/protocol.md")" = "$PROTOCOL_SHA" ] \
    && pass "protocol.md matches pinned Codex protocol" \
    || fail "protocol.md drifted from pinned Codex protocol"

echo "=== helper behavior ==="
emit() { node "$HELPER" emit --root "$TMPDIR_T" --run t1 "$@" >/dev/null 2>&1; }
REQ_FROM="claude:AAAA"
REQ_TO="codex:BBBB"

emit --box outbox --id req-1 --from "$REQ_FROM" --to "$REQ_TO" --type review --prompt "check" \
    && pass "request emits" || fail "request emits"
emit --box inbox --id res-1 --ref req-1 --from "$REQ_TO" --to "$REQ_FROM" --type result --prompt "ok" \
    && pass "result with reversed addresses emits" || fail "result with reversed addresses emits"

LEDGER="$TMPDIR_T/.brain/runs/t1/turns.jsonl"
[ "$(wc -l < "$LEDGER" 2>/dev/null | tr -d ' ')" = "2" ] \
    && pass "ledger has 2 turns" || fail "ledger has 2 turns"
[ -f "$TMPDIR_T/.brain/runs/t1/inbox/res-1.json" ] \
    && pass "result lands in inbox" || fail "result lands in inbox"

emit --box inbox --id res-2 --ref req-1 --from "$REQ_TO" --to "$REQ_FROM" --type result --prompt "again" \
    && fail "second result on same request rejected" || pass "second result on same request rejected"
emit --box outbox --id req-2 --from "$REQ_FROM" --to "$REQ_TO" --type question --prompt "q" >/dev/null
emit --box inbox --id res-3 --ref req-2 --from "$REQ_FROM" --to "$REQ_TO" --type result --prompt "x" \
    && fail "non-reversed result rejected" || pass "non-reversed result rejected"
emit --box inbox --id res-4 --ref res-1 --from "$REQ_FROM" --to "$REQ_TO" --type result --prompt "x" \
    && fail "result to a result rejected" || pass "result to a result rejected"

emit --box outbox --id req-3 --from "$REQ_FROM" --to "$REQ_TO" --type task --prompt "t" --status answered \
    && fail "emit rejects an invented answered initial status" \
    || pass "emit rejects an invented answered initial status"
[ ! -f "$TMPDIR_T/.brain/runs/t1/outbox/req-3.json" ] \
    && pass "rejected emit leaves no outbox file" || fail "rejected emit leaves no outbox file"

mark() { node "$HELPER" mark --root "$TMPDIR_T" --run t1 "$@" >/dev/null 2>&1; }
mark --id req-2 --status answered \
    && fail "mark answered without a correlated result rejected" \
    || pass "mark answered without a correlated result rejected"
mark --id req-1 --status answered && pass "mark answered after result appends" \
    || fail "mark answered after result appends"
MARK_CHECK=$(python3 - "$LEDGER" "$TMPDIR_T/.brain/runs/t1/outbox/req-1.json" <<'PY'
import json, sys
turns = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
req = [t for t in turns if t["envelope"]["id"] == "req-1"]
on_disk = json.load(open(sys.argv[2]))
ok = (len(turns) == 4 and len(req) == 2 and req[-1]["status"] == "answered"
      and req[0]["envelope"] == req[-1]["envelope"] == on_disk)
print("ok" if ok else "mismatch")
PY
)
[ "$MARK_CHECK" = "ok" ] && pass "mark appends without rewriting envelopes" \
    || fail "mark appends without rewriting envelopes"

echo "=== SKILL.md speaks the protocol ==="
SKILL="$SKILL_DIR/SKILL.md"
[ "$(grep -c 'conduct.cjs emit' "$SKILL")" -ge 2 ] \
    && pass "SKILL.md routes both send and reply through conduct.cjs emit" \
    || fail "SKILL.md routes both send and reply through conduct.cjs emit"

ENVELOPE_CHECK=$(python3 - "$SKILL" <<'PY'
import json, re, sys
text = open(sys.argv[1]).read()
m = re.search(r"```json\n(.*?)```", text, re.S)
if not m:
    print("no json block"); sys.exit()
env = json.loads(m.group(1))
if set(env) != {"v", "id", "from", "to", "type", "prompt", "cwd", "ref"}:
    print("keys", sorted(env)); sys.exit()
for k in ("from", "to"):
    if not re.match(r"^(claude|codex):\S+$", env[k]):
        print("bare address", env[k]); sys.exit()
print("ok")
PY
)
[ "$ENVELOPE_CHECK" = "ok" ] && pass "SKILL.md envelope has exactly eight keys with stable addresses" \
    || fail "SKILL.md envelope has exactly eight keys with stable addresses ($ENVELOPE_CHECK)"
grep -qiE -- '--effort|reasoning_effort|"effort"' "$SKILL" && fail "SKILL.md sets no sender effort" \
    || pass "SKILL.md sets no sender effort"
grep -q 'codex queue --thread' "$SKILL" && pass "SKILL.md documents codex queue transport" \
    || fail "SKILL.md documents codex queue transport"
grep -qE -- '--(prompt|message) "<' "$SKILL" \
    && fail "SKILL.md never interpolates raw text into a double-quoted shell arg" \
    || pass "SKILL.md never interpolates raw text into a double-quoted shell arg"
grep -q '^## Peer supervision during active work' "$SKILL" \
    && pass "SKILL.md mirrors Codex peer supervision policy" \
    || fail "SKILL.md mirrors Codex peer supervision policy"
grep -q "Never type approval into either agent's permission prompt" "$SKILL" \
    && pass "peer supervision never self-approves dialogs" \
    || fail "peer supervision never self-approves dialogs"
grep -q 'Do not repeatedly nudge the same unanswered request' "$SKILL" \
    && pass "peer supervision allows one recovery nudge only" \
    || fail "peer supervision allows one recovery nudge only"
grep -qE '\$TMPDIR/conduct-(msg|delivery)\.txt' "$SKILL" \
    && fail "SKILL.md scratch files are scoped per run and request" \
    || pass "SKILL.md scratch files are scoped per run and request"
grep -qF 'mktemp -d "${TMPDIR:-/tmp}/conduct.XXXXXX"' "$SKILL" \
    && pass "SKILL.md scratch dir is a private mktemp dir with /tmp fallback" \
    || fail "SKILL.md scratch dir is a private mktemp dir with /tmp fallback"
grep -q '<<' "$SKILL" && fail "SKILL.md writes message files without a shell heredoc" \
    || pass "SKILL.md writes message files without a shell heredoc"
grep -q 'Write tool' "$SKILL" && pass "SKILL.md writes message files with the Write tool" \
    || fail "SKILL.md writes message files with the Write tool"
grep -q 'outbox/<req-id>.json' "$SKILL" && pass "SKILL.md transports the outbox file, not helper stdout" \
    || fail "SKILL.md transports the outbox file, not helper stdout"
grep -qi 'agent input' "$SKILL" && pass "SKILL.md requires an agent input before it2api send" \
    || fail "SKILL.md requires an agent input before it2api send"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
