# Antigravity CLI (`agy`) Setup Guide

Researched 2026-11-15 from the official docs at `antigravity.google/docs`.
`agy` is **not installed on this machine**, so nothing below has been run here.
Every item is tagged:

- **[doc]** — stated on an official docs page (linked in Sources).
- **[inferred]** — pattern read from doc examples, not stated. Confirm before relying on it.
- **[unknown]** — the docs do not say. Probe it.

## 1. Install

macOS / Linux **[doc]**:

```bash
curl -fsSL https://antigravity.google/cli/install.sh | bash
agy --version
```

- Binary lands at `~/.local/bin/agy` **[doc]**.
- Installer flags: `--skip-aliases` (leave existing `agy`/`antigravity` aliases),
  `--skip-path` (do not edit shell profile `PATH`) **[doc]**.
- No `agy update` subcommand appears in the CLI reference **[unknown]**. Re-running
  the installer is the safe assumption **[inferred]**.

Windows PowerShell **[doc]**: `irm https://antigravity.google/cli/install.ps1 | iex`

## 2. Sign in

There is no `agy login` subcommand. Launching `agy` signs you in **[doc]**:

| Situation | Behavior |
|---|---|
| Local, token in OS keyring | Silent sign-in |
| Local, no token | Opens default browser |
| Remote SSH | Prints an auth URL; paste the code back into the terminal |
| API key | Set `"modelProvider": "gemini"` in `~/.gemini/antigravity-cli/settings.json`, export `GEMINI_API_KEY` |
| ADC | `gcloud auth application-default login --project P` then `export AGY_ADC_AUTH=true` |

- Only `GEMINI_API_KEY` is read. `GOOGLE_API_KEY` and `.env` are ignored **[doc]**.
- Sign out: `/logout` in the TUI **[doc]**.
- First launch asks for color scheme, rendering mode and workspace trust **[doc]**.
  Workspace trust persists in `trustedWorkspaces` in `settings.json` **[doc]**.

## 3. Models: Hydrogen medium builds, Argon high reviews

### What the docs say

| Model | Effort levels | Plan |
|---|---|---|
| Gemini 4 Hydrogen | low, medium, high, Extra (= `xhigh`); default High | Free and up |
| Gemini 4 Argon | low, medium, high | Google AI Pro (paid or eligible trial) and Ultra |

Both **[doc]**. Argon needs a paid plan; Hydrogen does not.

### Selecting model and effort

```bash
agy models                                   # list slugs your account can use [doc]
agy --model "<slug>" --effort medium         # interactive session [doc]
agy -p "<prompt>" --model "<slug>" --effort high   # headless [doc]
```

- `/model` in the TUI picks a model and **persists it** as `model` in
  `~/.gemini/antigravity-cli/settings.json`, saved by label **[doc]**.
- `/effort <level>` switches and persists. `--effort` applies to that run only
  and does not change the saved default **[doc]**.
- No `effort` key is documented in `settings.json` **[unknown]**.
- An unknown `--model` exits `1`. It does not fall back to another model **[doc]**.
  That is the behavior we want in a gate.

**Slugs.** The docs show `gemini-4-hydrogen-xhigh` and `gemini-3.8-flash-medium`.
That suggests a `<model>-<effort>` slug form, so `gemini-4-hydrogen-medium` and
`gemini-4-argon-high` are likely **[inferred]**. Run `agy models` and use what
it prints. Pass `--effort` explicitly as well, so the run does not depend on the
slug carrying the effort.

### Recommended setup

- **Builder (interactive):** `agy`, then `/model` → Gemini 4 Hydrogen,
  `/effort medium`. Both persist as the default.
- **Reviewer (headless, per review):** Argon high is an **experimental A/B arm**,
  not the default. Hydrogen and Argon are both Google, which fails the
  cross-vendor rule; the current default reviewer stays Sol via Codex (see
  `docs/model-brain-audit.md`). For an agy review leg, always pin on the command
  line, never rely on the persisted default:

```bash
agy -p "$REVIEW_PROMPT" \
  --model "<argon slug from agy models>" --effort high \
  --output-format json --json-schema review-schema.json \
  --print-timeout 15m --sandbox
```

`--json-schema` puts parsed output in `.structured_output`; `.status` is
`SUCCESS` on success **[doc]**.

**Headless permission trap [doc]:** with no TTY, any action that needs approval is
denied, the run continues, and it **exits 0**. A review leg that silently could not
read files looks like a clean review. Mitigations: grant read tools in
`permissions.allow`, or check stderr for the denial notice. Avoid
`--dangerously-skip-permissions` for reviewers.

### Subagent model pinning is coarse

Subagent files (`.agents/agents/<name>.md`) accept `model: inherit | flash | pro`
**[doc]**. They do not accept a named model or effort. A subagent cannot be pinned to
"Argon high", so the reviewer must be a separate headless `agy -p` process, not a
subagent.

## 4. Hooks: `.agents/hooks.json`

### Locations [doc]

- Project: `<repo>/.agents/hooks.json`
- Global: `~/.gemini/config/hooks.json`
- Plugin: `hooks.json` inside an installed plugin
- `~/.gemini/antigravity-cli/settings.json` is **not** read for hooks.
- Inspect what loaded: `/hooks` in the TUI.

### Schema [doc]

Top level is a map of **named hook groups**. Each group holds event arrays.

```json
{
  "tdd-guard": {
    "PreToolUse": [
      {
        "matcher": "write_file|run_command",
        "hooks": [
          { "type": "command", "command": "./.agents/hooks/tdd-check.sh", "timeout": 10 }
        ]
      }
    ]
  },
  "sdlc-baseline": {
    "SessionStart": [
      { "type": "command", "command": "./.agents/hooks/session-start.sh" }
    ]
  }
}
```

- `enabled: false` on a group disables it. Default `true`.
- `type` is only `"command"`. `timeout` is in seconds, default `30`.
- `matcher` is a regex on the tool name. It applies only to `PreToolUse` /
  `PostToolUse`.
- The docs' example places the handler directly in the event array for
  `PreInvocation` and `SessionStart` (no `matcher`/`hooks` wrapper), but uses the
  wrapper for tool events. Confirmed against the raw page HTML, not only a
  summary. Copy that shape exactly.

### Events [doc]

`SessionStart`, `PreToolUse`, `PostToolUse`, `PreInvocation`, `PostInvocation`, `Stop`.

### Input (stdin JSON, camelCase) [doc]

- All events: `conversationId`, `workspacePaths`, `transcriptPath`,
  `artifactDirectoryPath`, `modelName`, `lastUserInput`.
- `PreToolUse`: `toolCall.name`, `toolCall.args`, `stepIdx`.
- `PostToolUse`: same plus `error`.
- `Stop`: `executionNum`, `terminationReason`, `error`, `fullyIdle`.

The keys inside `toolCall.args` for each tool (e.g. which key holds the shell
command for `run_command`) are **[unknown]**. Log one payload before writing a
guard.

### Output (stdout JSON) — this is how you block [doc]

| Event | Field | Values |
|---|---|---|
| `PreToolUse` | `decision` (required) | `allow`, `auto_approve`, `deny`, `ask`, `force_ask`, `deny_unless_prior_grant` |
| `PreToolUse` | `reason`, `overwrite` (merge into args), `permissionOverrides` | optional |
| `PreInvocation` | `injectSteps`, `terminationBehavior: "terminate"` | optional |
| `PostInvocation` | `injectSteps`, `terminationBehavior: "force_continue" \| "terminate"` | optional |
| `Stop` | `decision: "continue"` keeps going; `reason` becomes a system message | |
| `SessionStart` | `injectSteps` | optional |

`injectSteps` items: `systemMessage`, `userMessage`, `ephemeralMessage`,
`errorMessage`. In `-p` mode an `errorMessage` makes the run exit non-zero **[doc]**.

**Exit-code semantics are not documented [unknown].** Do not assume Claude Code's
"exit 2 blocks". Block with `{"decision":"deny"}`. Timeout behavior is also
undocumented, so a hung hook may fail open.

## 5. Skills: `.agents/skills/<name>/SKILL.md`

### Locations (CLI) [doc]

| Path | Scope |
|---|---|
| `<repo>/.agents/skills/<name>/` (and each parent up to repo root) | Workspace |
| `~/.gemini/config/skills/<name>/` | Global, shared with App and IDE |
| `~/.gemini/config/plugins/<plugin>/skills/` | Plugin |
| `~/.gemini/antigravity-cli/skills/`, `~/.gemini/skills/` | CLI only |

Legacy `.agent/skills/` (singular) still works.

### Format [doc]

```markdown
---
name: sdlc
description: Runs the plan, TDD, review and commit workflow. Use when implementing, fixing, refactoring, testing or releasing code.
---

# SDLC
...
```

- `description` is **required**. `name` is optional and defaults to the folder name.
- Optional folders: `scripts/`, `examples/`, `resources/`.
- Invocation: the agent sees every name+description each turn and loads matching
  skills itself. In the CLI each skill is also a `/<name>` slash command.
  After adding one mid-session, run `/skills reload`.
- No size or count limit is documented **[unknown]**.

### Rules (the CLAUDE.md / AGENTS.md slot) [doc]

`agy` reads `AGENTS.md` **or** `GEMINI.md` at the repo root (and `.agents/`), plus
`.agents/rules/*.md` with required frontmatter `trigger: always_on | model_decision
| glob | manual`. Rules stack; none overrides another. Each file truncates at
24,000 bytes. A rules file with bad frontmatter is **silently dropped**.

## 6. Comparison

| Concern | Claude Code | Codex CLI (as `codex-sdlc-wizard` uses it) | Antigravity `agy` |
|---|---|---|---|
| Instructions file | `CLAUDE.md` | `AGENTS.md` (repo root) | `AGENTS.md` or `GEMINI.md`, `.agents/rules/*.md` |
| Project hooks file | `.claude/settings.json` `hooks` (plugin: `hooks/hooks.json`) | `.codex/hooks.json` | `.agents/hooks.json` |
| Hook file shape | `{hooks: {Event: [{matcher, hooks:[…]}]}}` | `{hooks: {Event: [{matcher, hooks:[…]}]}}` (read from `.codex/hooks.json`) | `{groupName: {Event: […]}}` — extra named-group level |
| Events used | `UserPromptSubmit`, `PreToolUse`, `SessionStart`, `InstructionsLoaded`, `PreCompact`, `Stop` | `PreToolUse`, `SessionStart`, `PreCompact`, `PostCompact` | `SessionStart`, `PreToolUse`, `PostToolUse`, `PreInvocation`, `PostInvocation`, `Stop` available |
| Prompt-submit event | `UserPromptSubmit` | not used | none; `PreInvocation` fires before each model call and carries `lastUserInput` |
| How a hook blocks | exit 2 + stderr | stdout JSON `{decision: "block", reason}` (`git-guard.cjs:42`) | stdout JSON `decision: "deny"` |
| Shell tool name | `Bash` | `Bash` (matcher `^Bash$`) | `run_command` |
| Skills dir | `.claude/skills/<n>/SKILL.md` | `setup.sh` installs `.agents/skills/sdlc/SKILL.md` in the consumer repo | `.agents/skills/<n>/SKILL.md` — the same path |
| Skill frontmatter | `name`, `description` (+ more) | `name`, `description` (read from `skills/codex-sdlc-wizard/SKILL.md`) | `description` required, `name` optional |
| Subagents | `.claude/agents/*.md`, named model | repo `agents/` dir is empty; Codex support **[unknown]** | `.agents/agents/*.md`, `model: inherit\|flash\|pro` only |
| Headless | `claude -p` | `codex exec` (here: only via `scripts/run-review-leg.sh`) | `agy -p --output-format json --json-schema` |
| Model + effort pin | `--model`, `effortLevel` | `-m` plus a `-c` effort override (see `scripts/run-review-leg.sh:275-276`) | `--model <slug>`, `--effort` |

The Codex column reflects files in `codex-sdlc-wizard` and this repo's launcher,
not a fresh read of Codex docs.

## Sources

- [Getting started](https://antigravity.google/docs/getting-started)
- [Install / authenticate](https://antigravity.google/docs/install/)
- [Models](https://antigravity.google/docs/models/)
- [`/effort`](https://antigravity.google/docs/cli/commands/effort/)
- [Headless mode](https://antigravity.google/docs/cli/headless/)
- [CLI reference](https://antigravity.google/docs/cli/reference/)
- [Settings](https://antigravity.google/docs/settings/)
- [Hooks](https://antigravity.google/docs/hooks/)
- [Skills](https://antigravity.google/docs/skills/)
- [Rules](https://antigravity.google/docs/rules/)
- [Subagents](https://antigravity.google/docs/subagents/)
