# Conduct protocol v1

## Scope

One logical Conductor can coordinate all **registered and reachable** Claude and Codex sessions. A session is reachable only when at least one adapter can address it unambiguously. The Conductor does not gain access to arbitrary dormant sessions merely because they belong to the same user.

Use one logical controller per run. The v1 filesystem helper serializes individual ledger writes; a long-running broker and Unix socket registry are a later transport optimization, not part of the protocol.

## Envelope

The envelope has exactly eight keys, commonly written as `{v, id, from, to, type, prompt, cwd, ref}`:

```json
{
  "v": 1,
  "id": "req-001",
  "from": "codex:primary",
  "to": "claude:reviewer",
  "type": "review",
  "prompt": "Review the proposed change.",
  "cwd": "/absolute/repository/path",
  "ref": null
}
```

- `from` and `to` are stable session addresses such as `codex:<uuid>` or `claude:<agent-id>`.
- Request types are `task`, `review`, `design`, or `question` and have `ref: null`.
- A response has `type: result` and `ref` equal to its request ID.
- The receiver owns model selection, reasoning effort, permissions, and local policy. Those values never belong in the envelope.

## Durable layout

```text
.brain/
  runs/<run_id>/
    outbox/<message_id>.json
    inbox/<message_id>.json
    turns.jsonl
```

Each line of `turns.jsonl` wraps an envelope with a timestamp, transport, and status. The helper rejects duplicate IDs, unsafe run/message IDs, unmatched responses, reversed addresses that do not match the request, and a response that references another response.

`emit` creates each message once. `mark` appends an observation for an existing message without changing its envelope. Multiple ledger lines may therefore share an ID; count unique message IDs when counting requests/results. The latest observation for an ID supplies its status. `answered` requires an existing correlated result. Transport acceptance means `sent`, not proof of receiver execution.

The per-run `.write-lock/owner.json` identifies the current writer PID and timestamp. A crash may leave the lock behind. Inspect the owning process/tool handle and remove only a verified stale lock; no automatic lock removal or peer restart is based on time alone.

## Bounded flow

The automatic unit is one request and one response:

1. The controller emits a request to `outbox` and records it.
2. The selected adapter delivers it.
3. The receiver performs the work under its own policy.
4. The receiver emits one `result` referencing the request.
5. The controller records the result in `inbox` and stops.

No response automatically creates another request. A human or controller may begin an explicit new request with a new ID after inspecting the result. This keeps ref chains acyclic and makes repeated same-class findings an escalation decision rather than a model-to-model loop.

## Adapter contract

Adapters implement discovery, send, and read while preserving the envelope unchanged:

- Codex session: native session tool when exposed, otherwise `codex queue --thread <uuid-or-exact-name> --message <text>`.
- Codex one-shot: `codex exec`.
- Claude teammate: Claude's native agent messaging when invoked from Claude.
- Claude one-shot: `claude -p`.
- Visible iTerm2 session: `it2api` is the universal local fallback.
- Codex Desktop: use its native session/thread adapter when exposed.
- Claude Desktop: requires a Claude plugin/MCP adapter that registers the session; do not claim reachability until that adapter exists.

Prefer UUIDs to display names. If discovery finds duplicate names, require a stable ID rather than guessing.

An inactive Codex session needs `codex queue --resume` and a reachable daemon/server to begin work. A successful queue operation alone is not proof of execution; inspect target status or wait for the correlated result. A resume warning leaves the request queued.

## Safety

- Dispatch happens only through the `$conduct` skill or its helper. There are no raw prefix triggers and model output never executes itself.
- Never put credentials, tokens, or secret values in an envelope or ledger.
- Validate the target and working directory before delivery.
- Treat terminal text injection as input to an already authorized agent session, not as shell execution.
- Do not recursively dispatch a `result` or silently broaden the requested task.
