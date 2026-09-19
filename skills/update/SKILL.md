---
name: claude-update-wizard
description: Smart update for SDLC wizard — shows changelog, compares files, lets you selectively adopt changes while preserving customizations.
argument-hint: "[optional: check-only | force-all]"
effort: high
---
# Update Wizard - Smart SDLC Update

## Task
$ARGUMENTS

## Purpose

Guided update assistant. Check what version the user has, show what changed, walk them through selectively adopting updates while preserving their customizations. **DO NOT blindly overwrite files.** Show diffs and let the user decide.

## MANDATORY FIRST ACTION: Read the Wizard Doc

**Before doing ANYTHING else**, use Read on `CLAUDE_CODE_SDLC_WIZARD.md` — specifically the "Staying Updated (Idempotent Wizard)" section near the end. This contains update URLs, version tracking format, and step registry. Do NOT proceed without reading it first.

## Execution Checklist

Follow steps IN ORDER. Do not skip or combine.

### Step 1: Read Installed Version

Read `SDLC.md` and extract from the metadata comment:
```
<!-- SDLC Harness Version: X.X.X -->
<!-- Completed Steps: ... -->
```
No version comment → treat as `0.0.0` (suggest `/claude-setup-wizard` instead).

### Step 1.5: Check CLI Version (ROADMAP #232)

The wizard files in the user's project are one half of the install. The other half is the **npm CLI** (`agentic-sdlc-wizard`) — the binary powering `npx agentic-sdlc-wizard init`/`check`/`complexity`. If `init` ran months ago, npx cache (or global install) can be stuck on an old version even after `/claude-update-wizard` patches project files in-session. This step closes that gap.

**Detection — try both paths:**

1. **Global install** (rare): `npm ls -g agentic-sdlc-wizard --json --depth=0 2>/dev/null | jq -r '.dependencies["agentic-sdlc-wizard"].version // empty'`

2. **npx cache** (common): find every `package.json` under `~/.npm/_npx` matching `*agentic-sdlc-wizard*`, extract `.version`, pick the largest **by semver** (do NOT use `sort -u | tail -1` — lexicographic treats `1.9.0 > 1.10.0`). Use a Node `cmp()` helper: split on `-` for prerelease tag, compare `major.minor.patch` numerically, then prerelease order. Track max across stdin lines; empty input → empty output.

If both paths return empty, the user may be running from a custom install or never used `npx`. Treat as **undetectable** — note in the report but do not block. Skip the CLI bump prompt; continue to Step 2.

**Registry comparison:**
```bash
curl -fsS "https://registry.npmjs.org/agentic-sdlc-wizard/latest" | jq -r '.version'
```
Cache the result (also used in Step 3).

**Compare with semver-aware logic** — `sort -V` does NOT correctly order prereleases. Reuse the Node `cmp()` helper to produce exit `0` (installed < latest), `1` (installed > latest), `2` (equal).

**Surface the result:**
- `installed == latest` → silent, continue.
- `installed < latest` → show the gap with the upgrade options below.
- `installed > latest` (rare — pre-release/local dev) → silent, continue.

**Upgrade options when behind:**

> Your `agentic-sdlc-wizard` CLI is at **{installed}**, npm has **{latest}**. Step 6 refreshes project files, but `npx` cache keeps the old CLI on disk for `npx agentic-sdlc-wizard check`/`init`/`complexity`.
>
> **A. Refresh just the CLI cache (recommended).** No project changes; Step 6 handles the rest with diffs:
> ```bash
> npx -y agentic-sdlc-wizard@latest --version
> ```
>
> **B. One-shot CLI + project re-init.** Refreshes CLI AND overwrites *non-settings* managed files (skills, hooks, templates) with latest. `settings.json` is smart-merged (custom hooks + permissions preserved); other managed files are NOT smart-merged — local edits are lost unless committed. Use only if no local skill/hook customizations:
> ```bash
> npx -y agentic-sdlc-wizard@latest init --force
> ```
>
> **C. Skip the CLI bump.** Keep stale CLI; this session's file updates apply but `npx ... check` keeps using old drift logic.
>
> Pick A, B, or C: `[A/B/C]` (default A)

If A: prompt the user to run the one-liner, then re-invoke `/claude-update-wizard`. If B: same with the warning. If C: log the choice and continue.

**`check-only` precedence:** if passed, Step 1.5 runs report-only — print the gap if found, but do NOT prompt or run `init --force`. Fallback when CLI undetectable: skip the bump prompt, surface unknown-state in the report, continue to Step 2.

**Why Step 1.5, not later:** subsequent steps shell out to `npx agentic-sdlc-wizard check` (Step 4). If the CLI is stale, Step 4 reports based on the OLD definition of managed files and may miss new templates entirely.

### Step 2: Fetch Latest CHANGELOG

WebFetch:
```
https://raw.githubusercontent.com/BaseInfinity/claude-sdlc-harness/main/CHANGELOG.md
```
Extract latest version from the first `## [X.X.X]` line.

### Step 3: Compare Versions and Show What Changed

**Resolve "latest installable" from npm registry (#405):** Compare the npm registry version (Step 1.5 cache) to the CHANGELOG heading version (Step 2). Use the **lower** of the two as "latest installable" — avoids showing a version not yet published to npm during the publish window. If CHANGELOG is ahead, note it's on GitHub but not yet published.

Parse CHANGELOG entries between the user's installed version and the resolved latest installable. Present a clear summary:

```
Installed: 1.42.0
Latest:    1.99.2

What changed:
- [1.92.0] Cowork `Stop` hook REMOVED — it fired 12 times in one session and was wrong 11; Cowork now has no completion enforcement (documented in cowork/README.md).
- [1.91.0] TDD hook fixed for monorepos — it had been silently dead since Claude Code 2.1.214 for any repo whose source is not at root `src/`; driver effort default is now `high` (complex) / `medium` (routine web/CRUD).
- [1.90.0] Stop hook no longer blocks on in-flight background work; the documented Cowork install URL is corrected (it could not have worked); review-loop, convergence and TDD RED-per-assertion guidance added
- [1.89.0] Stop hook can no longer block a turn forever — it honours stop_hook_active, judges the current turn only, and blocks solely on code changed with no verification attempted; a suite with known explained failures no longer blocks. Merge approval no longer means merge bypass: the all-or-nothing escape is deleted, the denylist is tiered, and cross-model clearance satisfies the denylist finding only. Parallel blind dual review documented.
- [1.88.0] Opus 5 becomes the Setup A default driver (requires CC v2.1.219+); autocompact fix — Setup A no longer writes a stale CLAUDE_AUTOCOMPACT_PCT_OVERRIDE into consumer settings; escalation ladder codified (Fable → Codex → human last, confidence is not authorization).
- [1.87.0] First external contribution (@thejesh23, #444): argument-hint frontmatter quoted so Copilot CLI ≥1.0.65 loads skills, plus regression test; GPT-5.6 Sol reviewer sweep; Sonnet 5 default effort → medium (unbacked 5x quota claim removed, hook floor matched).
- [1.86.0] Fix #437: codex-gate-check.sh now blocks stale certifications — a CERTIFIED handoff.json no longer sails through forever; it records commit_sha at cert time and blocks once HEAD moves past it without a re-cert.
- [1.85.0] Post-ship retrospective: CI Feedback Loop synced to SKILL.md's stronger version, CERTIFIED≠CI lesson, Policy Migration Inventory checklist, stale round-count correction.
- [1.84.0] Hook enforcement fix: cross-model review gate + TDD RED gate now actually block (#436); model-aware effort docs replace blanket max recommendation.
- [1.83.0] Model config batch: multi-model hook recommendation (#403), global [1m] pin detection (#391), version race fix (#405), effort config check (#384).
- [1.82.0] Usage diagnostics: fix /usage row, Reading Usage Signals guide, advisor fallback procedure, Fable effort guidance, autocompact cross-reference.
... (older entries omitted — read the full CHANGELOG.md for anything pre-1.59.0)
```

Read the actual entries from the fetched CHANGELOG; don't paraphrase. The user wants to see exactly what shipped.

**If versions match:** Step 7.7 (global plugin-registration cleanup) is independent of wizard file versions — it must run even when the user is up-to-date. The `check-only` flag still gates whether cleanup is *applied*:

- **Without `check-only`**: Run Step 7.7 and Step 7.9 in normal mode (detect, prompt, apply) before stopping. Then say "You're up to date! (version X.X.X)" and stop. Do not run Steps 4–10; only Steps 7.7 and 7.9 fire on match.
- **With `check-only`**: Run Step 7.7 and Step 7.9 in detection-only mode — report findings but do NOT prompt and do NOT mutate settings. Then say "You're up to date! (version X.X.X)" and stop.

**If user passed `check-only` and versions don't match:** Stop after showing what changed. Do not apply anything.

### Step 4: Run Drift Detection

```bash
npx agentic-sdlc-wizard check
```
Reports each managed file as MATCH, CUSTOMIZED, MISSING, or DRIFT.

### Step 5: Fetch Latest Wizard Doc

WebFetch:
```
https://raw.githubusercontent.com/BaseInfinity/claude-sdlc-harness/main/CLAUDE_CODE_SDLC_WIZARD.md
```
Source of truth for all templates, hooks, skills, step registry.

### Step 6: Per-File Update Plan

| Status | Action |
|--------|--------|
| MATCH | Skip — already current |
| MISSING | Recommend install — explain what the file does |
| CUSTOMIZED | Show what changed in latest vs user's version. Ask: adopt, skip, or merge? |
| DRIFT | Flag the issue (e.g., missing executable permission). Offer to fix |

Read both the installed file and the latest template. Present a human-readable summary of differences — what was added/changed/removed and why, NOT a raw diff.

**If user passed `force-all`:** skip per-file approval, apply all updates.

### Step 7: settings.json (Smart Merge Only)

NEVER overwrite. Read user's current settings.json, compare to latest template's hook definitions, describe what changed (added/updated/removed), offer to merge: update wizard hooks while preserving all custom hooks, permissions, and other settings.

CLI's `init --force` already has smart-merge logic. If manual merge gets complicated, suggest: `npx agentic-sdlc-wizard init --force` (preserves custom hooks).

### Step 7.5: Model Pin Migration (Issue #198)

Wizard 1.31.0–1.33.x unconditionally wrote `"model": "opus[1m]"` and `"env": { "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "30" }` to `.claude/settings.json`. Issue #198 flipped that to opt-in because a top-level `model` disables Claude Code's auto-mode.

Check user's `.claude/settings.json`:

1. **`model: "opus[1m]"` AND `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: "30"`** — likely the old wizard-installed pair, not an intentional choice. Ask:
   > Your `.claude/settings.json` pins `model: "opus[1m]"` with `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=30`. This pair was the wizard default in 1.31.0–1.33.x, but it disables Claude Code's auto-mode (issue #198).
   > - **Remove the pin** (recommended) — keeps auto-mode enabled
   > - **Keep the pin** — guaranteed 1M on whichever Opus `opus[1m]` currently resolves to (now Opus 5, as of 2026-07-24 — swap to `claude-opus-4-6` or `claude-opus-4-8` if you want an earlier version specifically), OK with no auto-selection. Note: the paired `30%` override is **not** documented to take effect on a current-Opus local session (no Opus-5 proactive threshold is published) — see the wizard doc's Autocompact Tuning → "Opus 5 specifics". If you also set `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, the override *does* apply and the two compound (#207).
   > Remove, keep, or decide later? `[r/k/l]`

2. **Only one of the two fields matches** — treat as intentional customization. Do not prompt.
3. **`model: "sonnet[1m]"`** — ⚠️ warn: "sonnet[1m] draws from usage credits, not Max subscription (#390). Consider switching to `opusplan` (Opus plans, Sonnet executes, both Max-bundled) or plain `sonnet` (200K, Max-bundled)."
4. **`model: "opusplan"`** or other value (`sonnet`, `opus`) — explicit user choice. Do not touch.
5. **Neither field set** — already on new default.

When removing: drop `model` (and `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` if `env` becomes empty). Never touch other keys.

### Step 7.6: `allowedTools` → `permissions.allow` Migration (Issue #197)

Pre-#197 wizard guided users to write a top-level `allowedTools` array. Claude Code silently disables auto-mode when that key is present, even with `defaultMode: "auto"`.

If user's `.claude/settings.json` has top-level `allowedTools`, offer migrate:

1. **Only `allowedTools`** (no `permissions.allow`) — ask:
   > Your `.claude/settings.json` has top-level `allowedTools` (silently disables auto-mode, issue #197). Successor: `permissions.allow`.
   > - **Migrate** (recommended): move all entries into `permissions.allow`, remove the legacy key
   > - **Keep** — specific reason for legacy key
   > - **Later** — don't touch now
   > `[m/k/l]`

2. **Both `allowedTools` AND `permissions.allow` present** — flag: lists may have diverged. Show both arrays. On migrate, append every entry from `allowedTools` to the end of `permissions.allow` (preserve order), then drop `allowedTools`. **Do NOT dedup.** Duplicates are a no-op for CC, but removing them could silently lose user intent — explicit dedup request only, as a separate edit.

3. **Only `permissions.allow`** — already on new shape.
4. **Neither** — no action.

Preserve every entry byte-for-byte; only the container key changes. Do not reorder, dedup, or expand wildcards. Other top-level keys never touched.

### Step 7.7: Dead Plugin Registration Cleanup (Global Settings)

Wizard installs sometimes leave dead plugin registrations in **global** `~/.claude/settings.json` after the plugin directory is renamed/disabled/removed. Symptom: every CC session emits a harmless `Plugin directory does not exist` hook error that bleeds into every prompt until cleaned up.

This step is **global-settings-only** (`~/.claude/settings.json`, not project's). Update normally avoids global; this is the one exception, only when the marketplace name matches an exact wizard-owned identifier.

**Wizard-owned marketplace allowlist** (exact match — wildcards risk eating third-party `sdlc-wizard-tools` if such a thing ships):

- `sdlc-wizard-local`
- `sdlc-wizard-wrap`

If `cli/init.js` later adds wizard marketplace names, append verbatim.

**Detection:**

1. Read `~/.claude/settings.json`, parse as JSON.
2. For each `extraKnownMarketplaces[key]` where `key` is in the allowlist:
   - Verify `entry.source.source === "directory"` AND `typeof entry.source.path === "string"`. Either guard fails → skip (not the wizard's shape).
   - Resolve `source.path` (expand `~`). If the resolved path **does not exist**, mark **dead**.
3. For every dead marketplace `<name>`, look for `enabledPlugins["sdlc-wizard@<name>"]` — also flag for removal.
4. Repeat for all allowlist entries; collect dead pairs before prompting.

**Cleanup:** List all dead pairs, ask `[y/N]`. If yes: `cp ~/.claude/settings.json ~/.claude/settings.json.bak.$(date +%Y%m%dT%H%M%S)`, then single `jq` filter: `del(.enabledPlugins["sdlc-wizard@<name>"]) | del(.extraKnownMarketplaces["<name>"])` for each dead key. Write to temp, validate with `jq empty`, then `mv`. If no: skip.

**Guards:** Idempotent (no-op after clean). Scope: only allowlist matches. Runs regardless of version match. `check-only`: detect only, no mutations.

### Step 7.8: advisorModel Migration + Model Setup Guidance (v2.1.170+, #452)

If CC < v2.1.170: skip. Resolve the live driver from the `model` pin, or — unpinned — your self-reported model name (`/model` without saving persists nothing).

1. **Live driver is Fable** (pin `"fable"`/`"claude-fable-5"`, or unpinned + live identity Fable) — fires even with `advisorModel` already set (`/setup` 9.5 never offers Fable as driver, always a misconfig). Show:

> **Model Setup** — Fable-as-driver isn't recommended; it can trigger safeguard auto-switches on medical/legal/bio content mid-session. **Reliable:** Opus 4.6[1m] + GPT-5.5 + Fable (recommended default). **Setup A:** Opus 5 + Fable (bleeding edge, requires CC v2.1.219+ — unproven by field data yet, accepted-risk pick). **Setup B:** Sonnet 5 driver + Fable advisor (Simple/One-Off, generally lower quota than Opus 5, narrows at high effort). `[r/a/S]`?

`[r]` writes `model: "claude-opus-4-6[1m]"`, `advisorModel: "fable"` (no effortLevel — use `/effort max` per session). `[a]` writes `model: "opus"`, `advisorModel: "fable"`, `effortLevel: "high"` (bleeding edge; requires CC v2.1.219+). `[S]` (default): no change.

2. **Pin exists (non-Fable), no `advisorModel`:** suggest per driver (`sonnet`/`opus`/`claude-opus-4-6`/`claude-opus-4-8` → `advisorModel: "fable"`, `opusplan` → `fable`). `[a/S]`; `[a]` writes **only** `advisorModel`, driver untouched.
3. **No pin, live driver not Fable, or `advisorModel` set:** skip.

### Step 7.9: Effort Configuration Check (#384)

Runs regardless of version match (like Step 7.7). `check-only`: report only. Effort is model-aware (v1.84.0+, see `AI_SETUP_LANES.md`), not blanket `max` — this step detects the anti-pattern, doesn't push everyone toward `max`.

1. Read `model` from the settings cascade. **No pin** = auto-mode, no fixed model — skip effort checks entirely (CC picks per turn). `claude-opus-4-6` = Opus 4.6 (Reliable, `max`). `opus` = Opus 5 (bleeding edge, `high`; `medium` for routine work). `sonnet` = Sonnet 5 (Setup B, `medium`). `opusplan` = mixed (Opus 5 planner `xhigh`, Sonnet 5 execution driver `medium`) — check the execution-driver effort, not the planner's. `claude-opus-4-8` = Opus 4.8.
2. **Opus 4.6 driver:** `CLAUDE_CODE_EFFORT_LEVEL=max` in `env` → pass (silent, 4.6's sweet spot). Only `effortLevel: "max"` in `settings.json` → warn: CC ignores session-only settings, only the env var persists — suggest moving it. Unset/below `max` → suggest `/effort max` + env entry.
3. **Opus 5 driver (bleeding edge):** unset or `xhigh` pinned as a standing default → suggest `/effort high` (complex work) or `medium` (routine web/CRUD); `xhigh` is an escalation trigger for genuinely hard/long runs, not the default (changed 2026-08-02).
4. **Sonnet 5 driver (Setup B, or `opusplan`'s execution phase) or Opus 4.8 driver:** `CLAUDE_CODE_EFFORT_LEVEL=max` anywhere → warn (stale env var silently overrides `/effort high` post-switch). Recommend removing, use `/effort` per-session. Unset → pass (silent, `medium`/`xhigh` respectively are the model's own defaults).
5. Never suggest a shell-rc export — only the project's `env` block, only for Opus 4.6.

### Step 8: Apply Selected Changes

For each approved file: Edit (existing) or Write (MISSING). For settings.json, apply the merge from Step 7.

### Step 9: Bump Version Metadata

Update `SDLC.md`:
```
<!-- SDLC Harness Version: X.X.X -->
<!-- Completed Steps: step-0.1, step-0.2, ..., step-update-wizard -->
```
Set to latest version. Update completed steps if new ones applied.

### Step 10: Verify

```bash
npx agentic-sdlc-wizard check
```
All updated files should show MATCH. User-skipped files still show CUSTOMIZED — that's fine.

## Rules

1. **NEVER modify CLAUDE.md.** Fully custom to user's project. Wizard never touches it.
2. **NEVER auto-apply without showing what will change first** (unless `force-all`).
3. **Offline fallback:** WebFetch fails → tell user "Cannot reach GitHub. Run `npx agentic-sdlc-wizard init --force` to update from your locally installed CLI."
4. **First-time users:** SDLC.md missing or no version metadata → suggest `/claude-setup-wizard`.
5. **Respect customizations.** CUSTOMIZED files are intentional — show what's different, let them decide. Don't pressure.
6. **Reference the wizard doc** for full protocol details (step registry, URLs, version tracking) rather than hardcoding.
