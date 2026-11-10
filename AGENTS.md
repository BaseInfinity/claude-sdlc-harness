# Codex Review Guidelines

## Project Overview

Meta-repository — SDLC Harness documentation, automation, and a zero-dep Node.js CLI (`cli/`). Primary codebase is bash scripts + YAML workflows. The CLI distributes hooks, skills, and settings via `npx agentic-sdlc-wizard init`.

- `CLAUDE_CODE_SDLC_WIZARD.md` — The main wizard document
- `.github/workflows/` — CI, PR review, weekly/monthly automation
- `.claude/hooks/` — SDLC enforcement hooks (fire every interaction, ~100 tokens each)
- `.claude/skills/` — Detailed guidance invoked by Claude (sdlc, setup)
- `tests/` — Bash test scripts (Layer 1 logic + Layer 5 E2E)
- `cli/` — npx distribution CLI (zero-dep Node.js)

## AI Setup Lanes

This repo recommends four setup lanes — Setup A (Opus 5 + Fable advisor, GPT-5.6 Sol high reviewer, recommended default, trial as of 2026-07-24), Setup B (Sonnet 5 Simple/One-Off: Fable advisor, Sonnet 5 medium driver, GPT-5.6 Sol high reviewer), Setup C (OpusPlan Hybrid: Opus 5 plan mode + Sonnet 5 execute, GPT-5.6 Sol high reviewer), and Setup D (Claude Lite: Sonnet driver, no reviewer). See [`AI_SETUP_LANES.md`](AI_SETUP_LANES.md) for the full pick list.

The lanes are guidance, not a hard rule — maintainer override is always allowed.

## Review Focus Areas

### 1. SDLC Compliance
- Does the change follow SDLC principles (plan, test, review)?
- Is there evidence of planning for complex changes?
- Are tests included or updated?

### 2. Security
- Shell injection in bash scripts (unquoted variables, eval, backtick expansion)
- YAML injection in workflow files (untrusted `${{ }}` in `run:` blocks)
- Secrets exposure (API keys, tokens in logs or comments)
- Unsafe variable interpolation (use `env:` blocks for LLM-generated content)

### 3. Code Quality
- Simple and readable?
- Over-engineered? (KISS principle — this project deletes legacy code aggressively)
- Follows existing patterns? (check similar files before suggesting new approaches)

### 4. Testing
- New features tested?
- Tests are meaningful (not just for coverage)?
- Testing diamond: integration > unit with mocks
- Test scripts use `set -e`, `pass()`/`fail()` helpers, exit 1 on failure

### 5. Blast Radius — know what SHIPS before weighting a finding

`package.json`'s `files` lists: `cli/`, `skills/`, `hooks/`, `.claude-plugin/`, `CLAUDE_CODE_SDLC_WIZARD.md`, `AI_SETUP_LANES.md`, `CHANGELOG.md`.

**`files` is NOT the whole answer — npm always includes `README.md` and `package.json` regardless.** Verify with `npm pack --dry-run` rather than reading `files`; that is the authority. This exact omission caused a real miss: stale effort guidance in `README.md` was treated as repo-local and shipped anyway.

**Ships to every consumer — weight findings here highest:**
- `hooks/` → SDLC enforcement in every installed repo. A silently-inert hook here is a P0-class defect: it looks installed and does nothing.
- `skills/` → SDLC guidance everywhere. Must stay byte-identical to `cowork/skills/` (see `tests/test-cowork-drift.sh`). **There is no byte ceiling — do not flag one.** The 20,000-byte build gate was deleted in #489 because the number was never measured (`THRESHOLD_TOKENS` 5,000 × a chars-per-token rule of thumb from another vendor, and env-tunable). `skills/sdlc/SKILL.md` has been well over 40,000 bytes since #489 — deliberately, and no exact figure is quoted here because it changes with every edit and a stale number is the defect this section exists to remove. The audit still *reports* sizes and still raises TRIM; that is observability, not a gate, and a TRIM line is not a finding.
- `cli/` → the installer. A defect here breaks setup for new users.
- `CLAUDE_CODE_SDLC_WIZARD.md`, `AI_SETUP_LANES.md`, **`README.md`** → the shipped guidance consumers act on. README ships despite its absence from `files`.

**Repo-local, ships to nobody — real, but lower stakes:**
- `.claude/hooks/`, `.claude/skills/`, `.claude/settings.json`, `scripts/`, `tests/`, `ROADMAP.md`, `AGENTS.md`

An earlier version of this section listed only the `.claude/` paths and omitted the shipping ones entirely, which inverted the priority. Do not restore that.

If a change affects SDLC behavior, check whether a relevant scenario exists in `tests/e2e/scenarios/`.

### 6. Merge evidence — tiers, and what each one actually proves

A clearance is not a mood. `scripts/merge-pr.sh` accepts specific evidence, and the tiers are not interchangeable. Rank findings about them accordingly.

| tier | what it requires | what it proves |
|---|---|---|
| **dual-certified** | 2 **distinct** reviewers at ≥95%, each bound to the head SHA | the strongest evidence available here |
| **cross-model-cleared** (ACKABLE paths only) | the same as dual-certified, **or** 1 reviewer at ≥95% plus a **distinct** `YES` below 95 whose payload declares `"p0_p1": 0` (#784) | two reviewers said yes; only one cleared the number. HARD paths never accept this |
| **user-approved** | a maintainer reason string | **zero independent reviewers.** Honest, visible degradation — never equivalent to the above |

Three failure modes worth flagging on sight:

- **A verdict held in a session is not evidence.** If a clearance was never posted, the gate cannot see it. Reaching for `--user-approved` when a real dual clearance exists but went unposted launders a strong result into a weak one.
- **Clearance binds to content, not to a branch.** A certification whose `candidate_tree` does not match the index tree is stale, and a re-review is owed the moment the tree moves. Flag any flow that re-uses a clearance across a tree change.
- **The gate is identity-blind.** It accepts any two *distinct* reviewer strings — it does not verify provider, model, effort, or mode. So "two reviewers agreed" is a weaker claim than it reads as. Do not treat a passing gate as proof that two independent models actually looked.

### 7. Unbounded reads and silent child failures

This class does not announce itself: nothing errors, and the run simply produces nothing. All four of these were observed in this repo, not theorized.

- **Buffered output hides a hang.** `--output-format json` buffers to completion, so a slow child and a dead one look identical. Observed: **zero bytes for ten minutes** before a kill. `stream-json` showed live activity within seconds. Flag any long-running child whose output cannot be observed while it runs.
- **A process with no owner has no fate.** A hand-rolled review leg died with zero-byte output, no status, and no process — nobody noticed until someone went looking. Any spawned child needs an owner that propagates its exit status; that is what `scripts/run-review-leg.sh` exists for, and why bare `codex exec` is refused by `hooks/codex-gate-check.sh`.
- **Inherited stdin hangs forever.** A child that inherits a terminal stdin and then reads from it blocks with no output and no timeout. Give children `/dev/null` unless they genuinely need input.
- **Children inherit more than you passed them.** Observed: a nominally-blind reviewer child called `advisor()` and consulted Fable, despite `--safe-mode --strict-mcp-config --no-chrome` and a four-tool allowlist — it inherited `advisorModel` from user settings. Flag any claim of isolation that rests on flags alone rather than on an observed transcript.

## Code Review Rules

Durable standards for `codex review`. Codex loads this section automatically — everything above applies too, this is what has bitten us repeatedly and is worth stating as rules.

1. **A test that greps for text is not a test of behavior.** This repo has shipped guards that assert on a script's source rather than executing it. Across one 2026-08 session, reviewers found nine assertions passing against broken code, a rule that accepted `1,2,1,2` silently, and a guard that read *nothing* from the file it guarded while all 15 of its fixture assertions stayed green. Flag any new assertion that greps where it could execute.

2. **Fixtures prove a rule works on documents shaped like the fixtures.** Require at least one assertion against the real artifact — mutate it and confirm the rule reports it. Absence of that canary is what let the vacuous guard above survive three review rounds.

3. **Prefer positive anchors to denylists.** Asserting "the defining line says X" is winnable. Asserting "no bad phrasing appears anywhere" is not — the synonym space is unbounded, and three rounds of adding alternations each ended with a reviewer naming another. Flag new denylists that guard an open-ended vocabulary.

4. **A guard must not be able to damage what it protects.** One cleanup guard deleted a real artifact while testing that real artifacts are not deleted. Prefer a temp directory over narrowing the blast radius of an operation on live paths.

5. **Docs are code.** `.md` changes break tests, and shipped docs are the product. A claim in shipped guidance about a mechanism that does not exist is a defect, not a typo — verify cited scripts, flags, and env vars actually exist.

6. **No unbacked recommendations.** If a shipped doc states a default, an effort level, or a performance claim, it needs a source or an explicit "not measured." This repo has shipped confident claims traced to commits with zero supporting measurement.

7. **Match effort to blast radius.** Do not demand release-gate rigor on a repo-local test fixture, and do not wave through a one-word change to `hooks/`.

## Review Exceptions

Read `CODE_REVIEW_EXCEPTIONS.md` before flagging findings. If your finding matches a documented exception, skip it — it has already been evaluated and explicitly accepted.

## Severity

- **P0 (Critical):** Security vulnerabilities, data loss, CI breakage, silent failures
- **P1 (Must fix):** Logic bugs, missing tests for new behavior, broken E2E coverage
- **P2 (Suggestion):** Style, readability, minor improvements

## Meta-Repo Awareness

- Docs ARE code — changes to `.md` files can break tests (tests validate doc content)
- `.github/workflows/` is the most execution-critical path
- `continue-on-error: true` and `|| echo "fallback"` patterns mask real failures — always flag these
- `${{ }}` in bash `run:` blocks with LLM/user content → command injection risk (use `env:` block instead)
- macOS ships bash 3.x — no `declare -A`, no `head -n -1`
