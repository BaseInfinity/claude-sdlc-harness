---
name: conduct
description: "Dispatch messages between Claude and Codex sessions — cross-model review, design questions, task handoffs. Uses native transport (SendMessage, codex queue, claude -p, codex exec) with it2api fallback. Use when you need to send work to another brain, get a cross-model review, or coordinate across sessions."
argument-hint: "[target] [message]"
---
# Conduct — Cross-Agent Dispatch

## Protocol

Envelope v1 — 7 fields, receiver owns effort/policy:

```json
{
  "v": 1,
  "id": "<uuid>",
  "from": "claude|codex",
  "to": "claude|codex",
  "type": "review|design|question|result",
  "prompt": "<the message>",
  "cwd": "<repo path>",
  "ref": "<id of message this replies to, or null>"
}
```

## Transport Priority

Try native first. Fall back to it2api only when native can't reach the target.

| Direction | Native | Fallback |
|---|---|---|
| Claude → Claude | `SendMessage` via `ListAgents` | `it2api send-text` |
| Claude → Codex (existing session) | `codex queue --thread <session> --message` | `it2api send-text` |
| Claude → Codex (one-shot) | `codex exec -m <model> --effort <effort> "prompt"` | `it2api send-text` |
| Codex → Claude (one-shot) | `claude -p "prompt"` | `it2api send-text` |
| Codex → Codex | `codex queue` / `@task-name` | `it2api send-text` |

## Commands

### `conduct list` — discover all reachable targets

Run discovery from two sources:

```bash
# 1. Claude sessions (native)
# Use ListAgents tool — shows local, desktop, cloud, remote sessions

# 2. iTerm2 sessions (all terminal agents)
it2api list-sessions 2>/dev/null
```

Present a merged, deduplicated list. Match by session name patterns:
- `claude` / `CLAUDE` / `(node)` → Claude session
- `codex` / `CODEX` / `(codex")` → Codex session

### `conduct send <target> <message>` — dispatch

1. Generate a UUID for this envelope.
2. Determine target type (claude or codex) from discovery.
3. Pick transport:
   - **Claude target found in ListAgents** → `SendMessage`
   - **Codex target, need one-shot review** → `codex exec`
   - **Codex target, existing session** → try `codex queue`, fall back to `it2api`
   - **Any target in iTerm2** → `it2api send-text <session-id> "<prompt>"` then `it2api send-text <session-id> $'\r'`
4. Log envelope to `.brain/runs/<run_id>/turns.jsonl`
5. Report what was sent and how.

### `conduct check` — read pending responses

Check `.brain/inbox/` for any `*.json` files. Surface the most recent unread response. Mark as read.

For it2api-dispatched messages, read the target's buffer:

```bash
it2api get-buffer <session-id> 2>/dev/null
```

Parse the response from the buffer content.

## Safety

- **Loop prevention:** never dispatch if `from` matches self in the same `ref` chain. A message replying to a reply to your own message is a loop.
- **Skill-gated:** only this skill dispatches. No raw prefix triggers, no model-printed dispatch strings.
- **Sandbox:** `it2api` and `codex exec` require `dangerouslyDisableSandbox` due to unix socket / process restrictions. `SendMessage` and `ListAgents` are native tools — no sandbox issue.
- **No secrets in envelopes.** The prompt field carries the task, never credentials or tokens.

## Ledger

Every dispatch and response is appended to `.brain/runs/<run_id>/turns.jsonl`:

```jsonl
{"ts":"2026-11-06T...","envelope":{...},"transport":"sendmessage|codex_exec|it2api","status":"sent"}
{"ts":"2026-11-06T...","envelope":{...},"transport":"it2api","status":"received"}
```

The `.brain/` directory lives at the repo root. Create it if absent. Each run gets a UUID directory.

## Quick Reference

**Send a review to Codex:**
```
/conduct send codex "Review this diff for correctness bugs. Focus on the model ID changes in AI_SETUP_LANES.md and skills/setup/SKILL.md."
```

**Send a design question to another Claude session:**
```
/conduct send claude "Should the conduct skill support desktop app sessions or just CLI? What's the transport for Claude Desktop?"
```

**Check for responses:**
```
/conduct check
```

**List all reachable targets:**
```
/conduct list
```

## Lane Defaults (receiver policy)

The receiver's lane config determines effort, not the sender:

| Target | Builder default | Review default |
|---|---|---|
| Claude Reliable | Opus 4.6 `max` | GPT-5.6 Sol `xhigh` |
| Claude Frontier | Opus 5.5 `medium` | GPT-5.6 Sol `xhigh` |
| Codex Reliable | GPT-5.6 Sol `high` | Opus 4.6 `max` |
| Codex Frontier | GPT-6.1 Sol `high` | Opus 5.5 `xhigh` |
