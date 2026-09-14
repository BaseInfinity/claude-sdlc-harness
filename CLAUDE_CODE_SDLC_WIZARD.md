# Claude Code SDLC Setup Wizard

> **Contribute**: This wizard is community-driven. PRs welcome at [github.com/BaseInfinity/claude-sdlc-harness](https://github.com/BaseInfinity/claude-sdlc-harness) - your discoveries help everyone.

> **For Humans**: This wizard helps you implement a battle-tested SDLC enforcement system for Claude Code. It will scan your project, ask questions, and walk you through setup step-by-step. Works for solo developers, teams, and organizations alike.

> **Important**: This wizard is a **setup guide**, not a file you keep in your repo. Run it once to generate your SDLC files (hooks, skills, docs), then check for updates periodically with "Check if the SDLC wizard has updates".

## What This Is: SDLC for AI Agents

**This SDLC is designed for Claude (the AI) to follow, not humans.**

You set it up, Claude follows it. The magic is that structured human engineering practices (planning, TDD, confidence levels) happen to be exactly what AI agents need to stay on track.

| Human SDLC | Why It Works for AI |
|------------|---------------------|
| Plan before coding | AI must understand before acting, or it guesses wrong |
| TDD Red-Green-Pass | AI needs concrete pass/fail feedback to verify its work |
| Confidence levels | AI needs to know when to ask vs when to proceed |
| Self-review | AI catches its own mistakes before showing you |
| TodoWrite visibility | You see what AI is doing (no black box) |

**The result:** Claude follows a disciplined engineering process automatically. You just review and approve.

> **Built for Claude Code.** Using OpenAI's Codex CLI instead? See [`codex-sdlc-wizard`](https://github.com/BaseInfinity/codex-sdlc-wizard) — same SDLC enforcement, ported.

---

## The Vision

**Think Iron Man:** Jarvis is nothing without Tony Stark. Tony Stark is still Tony Stark. But together? They make Iron Man. This SDLC is your suit - you build it over time, improve it for your needs, and it makes you both better.

**This wizard is designed to make itself unnecessary.**

As Claude Code improves, the wizard absorbs those improvements and removes its own scaffolding. Built-in TDD enforcement? Delete our hook. Native confidence tracking? Remove our guidance. Official code review plugin? Use theirs, delete ours. Every Claude Code release is an opportunity to simplify.

**The end goal:** This entire wizard becomes part of Claude Code itself. The patterns here — planning before coding, TDD enforcement, confidence levels, self-review — are exactly what every AI agent needs. Until Anthropic builds them in natively, this wizard bridges the gap.

**But here's the key:** This isn't a one-size-fits-all answer. It's a starting point that helps you find YOUR answer. Every project is different. The self-evaluating loop (plan → build → test → review → improve) needs to be tuned to your codebase, your team, your standards. The wizard gives you the framework — you shape it into something bespoke.

**The living system:**
- The local shepherd captures friction signals during active sessions
- You approve changes to the process
- Both sides learn over time
- The system improves the system (recursive improvement)

**This is a partnership, not a rulebook.**

---

## KISS: Keep It Simple, Stupid

**A core principle of this SDLC - not just for coding, but for the entire development process.**

When implementing features, fixing bugs, or designing systems:
- **If something feels complex** - simplify another layer
- **If you're confused** - is this the right approach? Is there a better way?
- **If it's hard** - question WHY it's hard. Maybe it's hard for the wrong reasons.

**Don't power through complexity.** Step back and simplify. The simplest solution that works is usually the best one.

This applies to:
- Code you write
- Architecture decisions
- Test strategies
- The SDLC process itself

**When in doubt, simplify.**

---

## Testing AI Tool Updates

When your AI tools update, how do you know if the update is safe?

**The Problem:**
- AI behavior is stochastic - same prompt, different outputs
- Single test runs can mislead (variance looks like regression)
- "It feels slower" isn't data

**The Solution: Statistical A/B Testing**

| Phase | What You Test | Question |
|-------|---------------|----------|
| **Regression** | Old version vs new version | Did the update break anything? |
| **Improvement** | New version vs new version + changes | Do suggested changes help? |

**Statistical Rigor:**
- Run multiple trials (5+) to account for variance
- Use 95% confidence intervals
- Only claim regression/improvement when CIs don't overlap
- Overlapping CIs = no significant difference = safe

This prevents both false positives (crying wolf) and false negatives (missing real regressions).

**How We Apply This (post-ROADMAP #231 Phase 3a, v1.51.0+):**
- Weekly workflow detects new Claude Code versions and opens an auto-update PR
- Maintainer runs the version-test locally on Max before merging. **Pin using the
  channel Claude Code was actually installed with** — this is version *pinning*,
  which `claude update` cannot do, so it is the one place a channel-specific
  command belongs. On a native install use `claude install <new_version>`; the
  npm line below applies only if you installed via npm, and do not prefix it with
  `sudo` (that creates the ownership problems that break later updates):
  ```
  npm i -g @anthropic-ai/claude-code@<new_version>
  gh pr checkout <auto_update_pr>
  tests/e2e/local-shepherd.sh <pr> --compare-baseline
  ```
- Phase A semantics (regression): score delta vs main shows whether the new CC version breaks our SDLC enforcement
- Phase B semantics (improvement): include changelog-suggested doc changes in the PR before running the shepherd
- Green delta = safe to upgrade. Red = stay on current version until fixed
- Results posted as a check-run + PR comment with provenance (host, claude version, execution_path)

**Historical:** through v1.50.0, this was a CI cron job (`version-test` in `weekly-update.yml`, $8-20/run) that auto-installed the new version and ran Phase A/B Tier 1+2. Deleted in v1.51.0 because it ran on every release detection regardless of relevance, with zero merged artifacts in 30 days.

### Benchmark Ceiling Effect (Known Issue — April 2026)

**Our E2E benchmark currently has zero discriminating power.** Both Opus 4.6 and 4.7 scored perfect 10/10 on the `add-feature` scenario (3 trials each, `high` effort). A cross-model audit (Codex GPT-5.4, xhigh reasoning) rated the benchmark methodology **2/10, NOT CERTIFIED** and identified 4 P0 critical issues:

| Finding | Severity | Problem |
|---------|----------|---------|
| **Fake trials** | P0 | The workflow runs the simulation ONCE, then re-scores the same output N times. "Trials" measure judge jitter, not model variance |
| **Answer key leaked** | P0 | The simulation prompt tells the model exactly what's scored ("You MUST use TodoWrite... scored by automated checks"). This tests obedience to rubric, not SDLC judgment |
| **No independent verification** | P0 | "Tests pass" is self-reported from the transcript. The evaluator never re-runs `npm test` on the final code |
| **Binary rubric** | P0 | Every criterion is YES/NO. The evaluator is explicitly designed for "near-zero variance." On an easy coached task, scores collapse to 10/10 |

**Three concrete fixes to break the ceiling:**

1. **Remove rubric leakage** — Don't tell the model what's scored in the simulation prompt. Let the wizard hooks and docs drive behavior naturally. Score hidden behaviors from traces, not coached compliance
2. **Make correctness the majority of the score** — After simulation, run an external verifier: re-run `npm test` on the modified fixture, add hidden tests the model didn't know about, inspect the actual diff. Replace transcript-only `clean_code` with diff-based quality checks
3. **Real trials on calibrated scenarios** — Each trial must be a fresh end-to-end simulation run on a fresh checkout. Select scenarios by pilot difficulty so top models don't all saturate (similar to Aider's hard-subset methodology). The current single-coached-toy-run approach is measuring nothing

**What external benchmarks do differently:** SWE-Bench gives a real issue plus a full repo snapshot, applies the agent's patch, and runs the repo's actual tests to score `% resolved`. Aider's polyglot benchmark was explicitly rebuilt because the old one saturated — it uses 225 harder tasks chosen to preserve headroom. Our benchmark lacks real task difficulty calibration, independent execution-based correctness, multi-task breadth, and headroom management.

**Status:** This is tracked as item #96 (E2E score audit) on the roadmap. Until fixed, the benchmark measures process compliance coaching, not model quality differentiation.

---

## Philosophy: Sensible Defaults, Smart Customization

This wizard provides **opinionated defaults** optimized for AI agent workflows. You can customize, but understand what's load-bearing.

### CORE NON-NEGOTIABLES (Don't Change These)

These aren't preferences - they're **how AI agents stay on track**:

| Core Principle | Why It's Critical for AI |
|----------------|--------------------------|
| **TDD Red-Green-Pass** | AI agents need concrete pass/fail feedback. Where a RED mutation is writable, failing tests first are the feedback loop that keeps implementation correct; where no assertion can catch the wrong version (meaning-level prose), cross-model review is the verification — see "When TDD RED Applies". |
| **Testing Diamond** | Integration tests catch real bugs. Unit tests with mocks can "pass" while production fails. AI agents need tests that actually validate behavior. |
| **Confidence Levels** | Prevents Claude from guessing when uncertain. LOW confidence = escalate (Fable, then Codex) before interrupting a human. This stops runaway bad implementations. |
| **TodoWrite Visibility** | You need to see what Claude is doing. Without visibility, Claude can go off-track without you knowing. |
| **Planning Before Coding** | Claude must understand before implementing. Skipping planning = wasted effort and wrong approaches. |

**WARNING:** Deviating from these fundamentals will break the system. The SDLC works because these pieces work together. Remove one and the whole system degrades.

---

### SAFELY CUSTOMIZABLE (Change Freely)

These adapt to your stack without affecting core behavior:

| Customization | Examples |
|---------------|----------|
| **Test framework** | Jest, Vitest, pytest, Go testing, etc. |
| **Commands** | Your specific lint, build, test commands |
| **Code style** | Tabs/spaces, quotes, semicolons |
| **Pre-commit checks** | Which checks to run (lint, typecheck, build) |
| **Documentation structure** | Your doc naming and organization |
| **Feature doc suffix** | Claude scans for existing patterns, suggests based on what you have, or lets you define custom |
| **Source directory patterns** | `/src/`, `/app/`, `/lib/`, etc. |
| **Test directory patterns** | `/tests/`, `/__tests__/`, `/spec/` |
| **Mocking rules** | What to mock in YOUR stack (external APIs, etc.) |
| **Code review** | `/code-review` for local, CI review for team visibility |
| **Security review triggers** | What's security-sensitive in your domain |

---

### RISKY CUSTOMIZATIONS (Strong Warnings)

You CAN change these, but understand the trade-offs:

| Customization | Default | Risk if Changed |
|---------------|---------|-----------------|
| **Testing shape** | Diamond (integration-heavy) | Pyramid (unit-heavy) = mocks can hide real bugs, AI gets false confidence |
| **TDD strictness** | Strict (test first wherever a RED mutation is writable) | Flexible = AI may skip tests, no verification of correctness |
| **Planning mode** | Required for implementation | Skipping = Claude codes without understanding, wasted effort |
| **Confidence thresholds** | LOW < 60% = must escalate | Higher threshold = Claude proceeds when unsure, mistakes |

**If you change these:** The wizard will warn you. You can override, but you're accepting the risk.

---

### Smart Recommendations (Not Just Detection)

During setup, Claude will:

1. **Scan your project** - Find package managers (package.json, Cargo.toml, go.mod, pyproject.toml, etc.), test files, CI configs
2. **Recommend best practices** - Based on YOUR stack and what Claude discovers, not assumptions
3. **Explain the recommendation** - Why this approach works best with AI agents
4. **Let you decide** - Accept defaults or customize with full understanding
5. **Ask if unsure** - Claude will ask rather than guess about your stack

**Example:**
```
Scan result: Found Jest, mostly unit tests, heavy mocking
Recommendation: Testing Diamond with integration tests
Why: Your current unit tests with mocks may pass while production fails.
     Integration tests give Claude reliable feedback.
Action: [Accept Recommendation] or [Keep Current Approach (with warnings)]
```

---

### The Goal

**The True Goal:** Not just keeping AI Agents following SDLC, but creating a **self-improving partnership** where:
- Humans always feel **in control**
- Both sides **learn and get better** over time
- The process **organically evolves** through collaboration
- **Human + AI collaboration** working together - everyone wins

This frames the wizard as a partnership, not a constraint.

**What this means in practice:**
1. Have a process that Claude follows consistently
2. Make the process visible (TodoWrite, confidence levels)
3. Enforce quality gates (tests pass, review before commit)
4. Let Claude escalate when uncertain (models first, human last)
5. **Customize what makes sense, keep what keeps AI on track**

### Leverage Official Tools (Don't Reinvent)

When Anthropic provides official plugins or tools that handle something:
- **Use theirs, delete ours** - Official tools are maintained, tested, and updated automatically
- This wizard focuses on what official tools DON'T do (TDD enforcement, confidence levels, planning integration)

**Check periodically:** `/plugin > Discover` - new plugins may replace parts of our workflow.

---

## Prerequisites

| Requirement | Why |
|-------------|-----|
| **Claude Code v2.1.69+** | Required for InstructionsLoaded hook, skill directory variable, and Tasks system |
| **Git repository** | Files should be committed for team sharing |

**Installing Claude Code itself.** Use the native installer — it is what [the official setup docs](https://code.claude.com/docs/en/setup) label *Recommended*, and it auto-updates in the background with no `claude update` step to remember:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

**Never** install it with `sudo npm install -g @anthropic-ai/claude-code` — the official docs warn against that in those words, because sudo can leave the global module directory root-owned. When it does, the damage compounds, as observed on a real machine (#476): `claude update` refused with "Insufficient permissions to install update"; `npm uninstall -g` then failed with `EACCES`, because a normal user cannot rename a root-owned directory; and switching to the native install left *two* `claude` binaries on `PATH` at once, resolved by `PATH` order — so a reordering downgrades you to the stale pinned version. An npm install *without* sudo is not dangerous, just worse: if the global npm directory is not writable it stops auto-updating, with only a one-time notice at startup.

Run `which -a claude` to check for conflicting installations — that is the official docs' own procedure, and it is the one that catches a stale binary shadowing a newer one by `PATH` order. Use `claude doctor` for install health, but do not rely on it for this: when run with a decoy binary placed earlier on `PATH`, it reported no conflict.

**Blank repos (no CLAUDE.md, no code):** The wizard works on empty repos. Run `npx -y agentic-sdlc-wizard@latest init` — it installs hooks, skills, and the wizard doc. (The `@latest` pin guards against stale npx caches per #358.) On first session, the hooks detect missing SDLC files and redirect to `/claude-setup-wizard`, which generates CLAUDE.md, SDLC.md, TESTING.md, and ARCHITECTURE.md interactively. You do NOT need to run Claude's built-in `/init` first — the setup wizard handles everything.

---

## Recommended Effort Level

Claude Code's **effort level** controls how much thinking the model does before responding. Higher effort = deeper reasoning but more tokens.

> ⚠️ **SDLC requires model-appropriate effort, not a blanket setting.** Below the model's own sweet spot = degraded reasoning, shallow TDD, weak self-review. **Above** it (`max` on a model that only supports up to `xhigh`, or `max` on a model where it overthinks) wastes tokens for no quality gain — this is not a "more is always better" knob. See `AI_SETUP_LANES.md` for the current per-model recommendation.

| Model | Recommended Effort | Why |
|-------|--------------------|-----|
| Opus 5 (recommended default, trial) | `high` (complex) / `medium` (routine web/CRUD) | Changed 2026-08-02. Escalate to `xhigh` for genuinely hard or long-running agentic work — Anthropic's own framing for that tier — but not as a standing default; their Opus 5 prompting guide advises using lower effort liberally wherever quality holds. Original rationale: Anthropic's recommendation for "difficult tasks and long-running asynchronous workflows" — Setup A's target use case, not `high`'s routine-work default. Effort tier is static per session, but adaptive reasoning modulates depth within it. Trial-flagged as of 2026-07-24 — see `AI_SETUP_LANES.md` |
| Sonnet 5 (Simple/One-Off lane) | `medium`, escalate to `high`/`xhigh` for hard tasks | CodeRabbit testing: `medium` captures most of the upside at the lowest cost; blanket `xhigh`/`max` defaults add cost for marginal gains |
| Opus 4.8 (escalation, pinned) | `xhigh` | `max` triggers excessive reasoning on 4.7/4.8 — documented 40-60x cache-token jump vs `high` (see "Opus 4.6" row below) |
| Fable 5 (advisor / subagent fallback) | `high` everywhere — driver, subagent fallback, and `advisor()` (which exposes no effort parameter at all) | Adaptive thinking always on; server-side disabled as advisor currently — see "Advisor Model" below |
| Opus 4.6 (pinned, stability profile) | `max` | The one model where `max` doesn't overthink — no `xhigh` support at all (only low/medium/high/max) |
| OpenAI/Codex (cross-model reviewer) | `high` default (maintainer decision 2026-08-01 — cost and review-noise, not capability); escalate to `xhigh` for unusually risky PRs | Lower reasoning misses subtle bugs the reviewer exists to catch; see `AI_SETUP_LANES.md`'s Final Review Policy for when to escalate |

**Strict effort behavior (Opus 4.7+, carried forward in 4.8):**
- **`xhigh` was introduced in 4.7** — sits between `high` and `max`, designed for coding and agentic work (30+ minute tasks with token budgets in the millions)
- **Claude Code defaults to `xhigh`** on Opus 4.7+ for all plans
- **Opus 4.7+ respects effort levels more strictly** than 4.6 — at lower levels it scopes work tighter instead of going above and beyond. If you see shallow reasoning, raise effort rather than prompting around it
- **`budget_tokens` is deprecated** on Opus 4.7+ — use adaptive thinking with effort instead
- When running at `xhigh` or `max`, set a large `max_tokens` (64k+) so the model has room to think across subagents and tool calls

**Why `high` was the previous CC-wide default (now largely superseded by the table above):** Claude Code uses **adaptive thinking** to dynamically allocate reasoning budget per turn. On Pro and Max plans, the default effort level was **medium (85)**, which causes the model to under-allocate reasoning on complex multi-step tasks — leading to shallow analysis, missed edge cases, and "lazy" outputs. This was [confirmed by Anthropic engineer Boris Cherny](https://github.com/anthropics/claude-code/issues/42796) and is documented at [code.claude.com](https://code.claude.com/docs/en/model-config). API, Team, and Enterprise plans default to high effort and are not affected.

**Don't rely on the CC default — set effort yourself, matched to your model.** Anthropic's [2026-04-23 post-mortem](https://www.anthropic.com/engineering/april-23-postmortem) is independent third-party evidence that CC has flipped reasoning_effort defaults across versions. The default has changed before and will change again. The wizard's `model-effort-check.sh` hook warns when effort falls below the model-appropriate floor at session start. Set effort per-session with `/effort`, not a shell-rc or settings `env` block — persisting it that way silently overrides a later `/effort` change after you switch models (a real incident, documented in `SDLC.md`'s Lessons Learned).

**Nuclear option — disable adaptive thinking entirely:** Set `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` in your environment or settings.json `env` block. This forces a fixed reasoning budget per turn instead of letting the model dynamically allocate. Use this if you observe persistent quality issues even at the model-appropriate effort ceiling. See [Claude Code model config docs](https://code.claude.com/docs/en/model-config) for details.

**When to escalate effort:**
- You hit LOW confidence on your approach — deeper thinking may find clarity
- You've failed the same thing twice — something non-obvious is wrong
- Architecture decisions with wide blast radius
- Complex multi-system debugging where you need to hold many constraints
- Cross-model review analysis (reading and evaluating external reviewer findings)

**How it works:**
- `/effort <level>` changes effort for the current session only (resets next session)
- An `effort:` field in a skill's frontmatter persists across every invocation of that skill — the `/sdlc` skill deliberately does NOT set one, since the right effort depends on which model is driving, not which skill is running
- You can also type `ultrathink` in any prompt for a single high-effort turn

**Cost note:** higher effort uses more tokens. Match effort to your model per the table above — a blanket `max` wastes tokens on models where it overthinks, without any quality gain to show for it.

> See also: the **Effort** column in the [Confidence Check table](#confidence-check-required) below for per-confidence-level guidance on when to escalate.

### Anti-Laziness Guidance for CLAUDE.md

If you notice Claude Code producing shallow outputs at your model's recommended effort (see "Recommended Effort Level" above), add these instructions to your project's `CLAUDE.md`. These target the **specific mechanisms** behind quality degradation — adaptive thinking and effort levels — rather than vague directives:

```markdown
## Quality Anchoring
- This project sets effort per-session with /effort, matched to the active model
  (see AI_SETUP_LANES.md). Do not reduce reasoning depth below that level.
- Adaptive thinking may under-allocate your thinking budget on complex tasks. When working on
  multi-file changes, architecture decisions, or debugging: reason through the full problem
  before acting, even if the system prompt suggests taking the "simplest approach first."
- If you catch yourself skipping steps, re-read the task requirements and verify completeness.
```

**Why this works:** Claude Code's hidden system prompt includes "Go straight to the point. Try the simplest approach first." This is good for simple queries but causes the model to under-invest in reasoning on complex SDLC tasks. The instructions above don't fight the system prompt — they provide task-specific context that justifies deeper reasoning. Note that CLAUDE.md instructions can be partially overridden by the system prompt, so the per-session `/effort` level (not a skill-frontmatter field — the `/sdlc` skill deliberately omits one, since effort is model-aware) remains the primary defense; `hooks/model-effort-check.sh` nudges at session start if it drops below your model's floor.

---

## Claude Code Feature Updates

> **Keep your SDLC current**: Claude Code evolves. This section documents features that enhance the SDLC workflow. Check [Claude Code releases](https://github.com/anthropics/claude-code/releases) periodically.

### Tasks System (v2.1.16+)

**What changed**: TodoWrite is now backed by a persistent Tasks system with dependency tracking.

**Benefits for SDLC**:
- Tasks persist across sessions (crash recovery)
- Sub-agents can see task state
- Dependencies tracked automatically (RED → GREEN → PASS)

**No changes needed**: Your existing TodoWrite calls in skills work automatically with the new system.

**Rollback if issues**: Set `CLAUDE_CODE_ENABLE_TASKS=false` environment variable.

#### Known CC gotcha: `cleanupPeriodDays` and TodoWrite retention (CC 2.1.117+)

CC 2.1.117 expanded the `cleanupPeriodDays` setting to also cover `~/.claude/tasks/` — the directory where the Tasks system persists in-progress TodoWrite state across sessions. If `cleanupPeriodDays` is too low (CC's default has been as aggressive as 7 days in some versions), an SDLC checklist for a paused long-running feature can be silently pruned out from under you.

**Wizard pins a safe default**: `cli/templates/settings.json` ships `"cleanupPeriodDays": 30`. The wizard's SDLC skill makes TodoWrite step 1 of every task, so the floor matters. Recommendation: keep it at **30 or higher** if you ever pause work for more than a week. If a task list disappears mid-cycle, check this setting first.

**To override**: set `cleanupPeriodDays` to a higher number in your project's `.claude/settings.json`. The CLI's smart-merge preserves user overrides on `init --force`.

### Skill Arguments with $ARGUMENTS (v2.1.19+)

**What changed**: Skills can now accept parameters via `$ARGUMENTS` placeholder.

**How to use**: Add `argument-hint` to frontmatter and `$ARGUMENTS` in skill content:

```yaml
---
name: sdlc
description: Full SDLC workflow for implementing features, fixing bugs, refactoring code
argument-hint: "[task description]"
---

## Task
$ARGUMENTS

## Phases
...rest of skill...
```

**Usage examples**:
- `/sdlc fix the login validation bug` → `$ARGUMENTS` = "fix the login validation bug"
- `/sdlc write tests for UserService` → `$ARGUMENTS` = "write tests for UserService"

**Note**: Skills still auto-invoke via hooks. This is optional polish for manual invocation.

### Auto-Memory (v2.1.59+)

Claude Code now has built-in auto-memory that persists context across sessions. Manage with `/memory`.

**No changes needed**: The wizard's hooks and skills work alongside auto-memory. Memory stores preferences and context; the wizard enforces process.

### AGENTS.md interop (cross-tool standard, ROADMAP #205)

`AGENTS.md` is the cross-tool agent-instructions standard adopted by Cursor, Continue.dev, Aider, and other agentic IDEs ([CC issue #6235](https://github.com/anthropics/claude-code/issues/6235), 276 comments). It plays the same role as `CLAUDE.md` does for Claude Code, but reads as agent-agnostic.

**Wizard behavior** (v1.42.0, phase a only):

- **Setup skill detects existing AGENTS.md** during Step 1 auto-scan. If found, Step 4.5 surfaces a 3-way decision: dual-maintain (default, recommended), merge (manual in phase a), or skip. The user's choice is recorded as a one-line comment in their project's `SDLC.md` for their own reference. **`/claude-update-wizard` does NOT parse this comment** — that wiring is phase (d) work, not v1.42.0 scope.
- **No automatic merge / symlink yet** — phase (a) is detection + decision surfacing only. Option B in the prompt is "record your intent, do the copy by hand"; the wizard does not perform any merge in this phase.

**Deferred phases** (not in v1.42.0 scope):

- **Phase (b)**: when generating `CLAUDE.md` fresh (no AGENTS.md exists), offer to ALSO write AGENTS.md (symlinked or content-duplicated). Requires choosing a sync strategy.
- **Phase (d)**: cross-document-consistency drift test — fail CI if `CLAUDE.md` and `AGENTS.md` drift apart on key sections (Commands, Architecture, etc.).

**Why phase (a) only**: phase (a) ships detection signal value with zero new merge logic. The dual-maintain decision is reversible per-project; users who pick A get a sensible default and can opt up to phase (b) when it ships. Multi-tool sync is a real engineering problem (which file is source of truth? on edit, propagate which way?) that deserves its own design pass before automating.

### Built-in Commands (v2.1.59-v2.1.76)

New built-in commands available to use alongside the wizard:

| Command | Version | What It Does |
|---------|---------|--------------|
| `/memory` | v2.1.59 | Manage persistent auto-memory |
| `/simplify` | v2.1.63 | Review changed code for reuse/quality |
| `/batch` | v2.1.63 | Run prompts in batch |
| `/loop` | v2.1.71 | Run prompts on recurring intervals |
| `/effort` | v2.1.76 | Set effort level (low/medium/high) |

**Tip**: `/simplify` pairs well with the self-review phase. Run it after implementation as an additional quality check.

### Advisor Model (v2.1.170+)

**What changed**: `advisorModel` in settings.json configures a stronger model that Claude Code automatically consults at key decision points — before committing to an approach, when stuck on recurring errors, or before declaring a task done. Replaces manual `Agent(model: "fable")` subagent spawning for planning.

**Three ways to enable:**

| Method | Scope | Persists? |
|--------|-------|-----------|
| `"advisorModel": "fable"` in `.claude/settings.json` | Project | Yes (committed, shared with team) |
| `/advisor fable` | User (global `~/.claude/settings.json`) | Yes (all projects) |
| `--advisor fable` CLI flag | Session | No |

**Recommended pairings:**

| Driver | Advisor | Lane |
|--------|---------|------|
| Opus 5 (`opus`) | Fable (`"fable"`) | Setup A — default (trial) |
| Sonnet 5 (`sonnet`) | Fable (`"fable"`) | Setup B — Simple/One-Off |
| Sonnet via opusplan | Opus 5 (`"claude-opus-5"`) | Setup C — OpusPlan Hybrid |
| Opus 4.8 (`claude-opus-4-8`, pinned) | Fable (`"fable"`) | Escalation tier |

**Settings precedence:** Managed > CLI flags > Local (`.claude/settings.local.json`) > Project (`.claude/settings.json`) > User (`~/.claude/settings.json`). The wizard writes project-level by default — never nukes global settings. Setup skill Step 9.5 asks if you also want global.

**Important:** Fable does NOT appear in the `/advisor` interactive picker — set `advisorModel: "fable"` explicitly. Availability has moved: Anthropic's rollout **disabled** Fable-as-advisor on 2026-07-24 ("Claude Code doesn't offer Fable 5 as the advisor," per `code.claude.com/docs/en/advisor`), and it was **observed working again on 2026-08-16**. Both are dated observations, not current state — **determine which applies by calling `advisor()`**, never by reading this line. On a real failure, fall back to a Fable subagent (`Agent({model: "fable", effort: "high"})`) at every point you'd have called `advisor()`.

**Quota exhaustion is a different condition, and the advisor was observed to survive it once.** claude.ai shows `All models` and `Fable` as separate meters. Observed 2026-08-16: `advisor()` returned a Fable ruling while the `Fable` meter read 100% and `/model fable` was refused. **So try the advisor before concluding Fable is out of reach** — but no meter delta was measured, so which meter that call billed is unknown, and a window rollover was not ruled out. It is the most expensive shape either way — it forwards the whole conversation on every call and its read is not cached between them.

**Billing:** Advisor queries in interactive sessions are Max-bundled and do not trigger headless/credit-pool billing. **Which usage meter they draw down is not established here** — claude.ai shows `All models` and `Fable` separately, and no before/after meter delta has been measured against an advisor call. Do not budget on the assumption that advisor usage spares any particular meter.

**To update:** Run `! claude update` from inside a CC session to get v2.1.170+. The `!` prefix runs shell commands inline — no need to exit.

### Skill Frontmatter Fields (v2.1.80+)

Skills support these frontmatter fields:

| Field | Purpose | Example |
|-------|---------|---------|
| `name` | Skill name (matches `/command`) | `name: sdlc` |
| `description` | Trigger description for auto-invocation | `description: Full SDLC workflow...` |
| `effort` | Set reasoning effort level | `effort: high` |
| `paths` | Restrict skill to specific file patterns | `paths: ["src/**/*.ts", "tests/**"]` |
| `context` | Context mode (`fork` = isolated subagent) | `context: fork` |
| `argument-hint` | Hint for `$ARGUMENTS` placeholder (quote it — bare brackets parse as a YAML array and break strict loaders like Copilot CLI, #444) | `argument-hint: "[task description]"` |
| `disable-model-invocation` | Prevent skill from being auto-invoked by model | `disable-model-invocation: true` |

**Key fields explained:**
- **`effort:`** — Use sparingly on skills that run under many different driver models. The wizard's own `/sdlc` skill deliberately omits this field — the right effort level depends on which model is driving (see "Recommended Effort Level" above), not on which skill is running, so a fixed frontmatter value would fight `/effort`'s per-session, per-model guidance.
- **`paths:`** — Limits when a skill activates based on files being worked on. Useful for language-specific or directory-specific skills.
- **`context: fork`** — Runs the skill in an isolated subagent context. The subagent gets its own context window, so it won't pollute the main conversation. Useful for review skills or analysis that should run independently.

### InstructionsLoaded Hook (v2.1.69+)

New hook event fires when Claude loads instructions at session start. The wizard uses this to validate that `SDLC.md` and `TESTING.md` exist — catches missing wizard files early.

### Skill Directory Variable (v2.1.69+)

Skills can now reference companion files using `${CLAUDE_SKILL_DIR}`. Useful if you add data files alongside your skill markdown.

### Hook Metadata (v2.1.69+)

Hook events now include `agent_id` and `agent_type` fields. Hooks can behave differently for subagents vs the main agent if needed.

### Hook `if` Conditionals (v2.1.85+)

The `if` field on individual hook handlers filters by tool name AND arguments using permission rule syntax. The hook process only spawns when the condition matches — reducing unnecessary process spawns.

```json
{
  "type": "command",
  "if": "Write(src/**) Edit(src/**) MultiEdit(src/**)",
  "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/tdd-pretool-check.sh"
}
```

| Field | Level | Matches On | Syntax |
|-------|-------|------------|--------|
| `matcher` | Group (all hooks in array) | Tool name only | Regex (`Write\|Edit`) |
| `if` | Individual handler | Tool name + arguments | Permission rule (`Edit(src/**)`) |

**Pattern examples:** `Edit(*.ts)`, `Write(src/**)`, `Bash(git *)`. Same syntax as `permissions.allow` in settings.json.

**Only works on tool-use events:** `PreToolUse`, `PostToolUse`, `PostToolUseFailure`. Adding `if` to non-tool events prevents the hook from running.

**CUSTOMIZE:** Replace `src/**` with your source directory pattern. The wizard generates this based on your project structure detected in Step 0.4.

### Security Hardening (v2.1.49-v2.1.78)

Several fixes that strengthen wizard enforcement:
- **v2.1.49**: Managed hooks can't be bypassed by non-managed settings (tamper-resistant)
- **v2.1.72**: PreToolUse hooks returning `"allow"` can no longer bypass `deny` permission rules
- **v2.1.74**: Managed policy `ask` rules can't be bypassed by user `allow` or skill `allowed-tools`
- **v2.1.77**: Additional PreToolUse deny-bypass hardening
- **v2.1.78**: Visible startup warning when sandbox dependencies are missing

### Other Notable Changes

- **v2.1.50**: `CLAUDE_CODE_SIMPLE` env var disables hooks/skills/CLAUDE.md — be aware this bypasses wizard enforcement
- **v2.1.72**: HTML comments (`<!-- -->`) in CLAUDE.md are no longer injected into context — useful for internal notes
- **v2.1.77**: Output token limits increased from 64k to 128k (Opus 4.6/Sonnet 4.6)
- **v2.1.81**: `--bare` flag for scripted `-p` calls skips hooks/LSP/plugins/skills in headless mode

---

## Known CC Gotchas

This section documents Claude Code failure modes that have been observed in the wild — typically surfaced via post-mortems, GitHub issues, or our own catches data. Each entry has a workaround and a permanent fix when one exists.

### Extended-thinking + caching + idle sessions can drop thinking blocks (post-mortem 2026-04-23)

[Anthropic's 2026-04-23 post-mortem](https://www.anthropic.com/engineering/april-23-postmortem) describes a caching bug that "continuously dropped thinking blocks from subsequent requests" — surfaced primarily as silent quality degradation in long sessions. The failure mode mixed three ingredients:

1. **Extended thinking enabled** (high/xhigh/max effort triggers thinking-block production)
2. **Prompt caching active** (CC re-uses cached prompt prefixes across turns)
3. **Idle sessions** (context pruning during idle pulls thinking blocks out of the cache window)

When a cached prompt prefix is re-served after idle pruning, downstream thinking blocks can be silently absent — the model produces shorter, less-considered responses despite the requested effort level. Symptom: a session that was reasoning deeply earlier suddenly returns terse answers without obvious cause.

**Workaround**: if you hit suspicious shallow reasoning mid-session — especially after a long idle gap — start a fresh session with `claude --continue` to reset cache state. The wizard's PreCompact hook gates manual `/compact` precisely because compacting at bad seams can also pull thinking blocks out of context.

**Detection signal**: the wizard's `model-effort-check.sh` loud-warns below `medium` — the hook's real cross-model floor, since it can't tell which model is active and `medium` is a valid, intended default for Setup B's Sonnet 5. Above that floor, match effort to your actual lane: Opus 5 (Setup A) starts at `high` (`medium` for routine web/CRUD), Sonnet 5 (Setup B) starts at `medium` and escalates only when a task proves harder (see "Recommended Effort Level" above). Combine with token-spike anomaly detection (ROADMAP #220) once shipped.

### Prompt brevity caps can compound across turns (post-mortem 2026-04-23)

The same post-mortem documented that a length-limit prompt change (one of several brevity edits, including a line like `"keep text between tool calls to ≤25 words"`) correlated with a measurable ~3% drop on one evaluation. The post-mortem attributes the drop to the broader length-limit prompt change, not to that single sentence alone.

**Wizard policy** (audited 2026-04-26): the wizard's SKILL.md files and hook stdout do **not** impose compounding brevity constraints — no `≤N words`, `<N words`, `be concise`, or `keep brief` instructions to Claude. The wizard's own response-style guidance is in CC's user-level instructions, not injected into every system prompt.

**Regression guard**: `tests/test-postmortem-lessons.sh` greps every `skills/*/SKILL.md` and `hooks/*.sh` for these patterns and fails CI if a future PR introduces one. The check is case-insensitive and ignores shell comments (`#`) but treats Markdown content (including headings) as instructions to Claude. Add new skills with this in mind — terseness for the user is fine, terseness as a system-prompt constraint is not.

### `cleanupPeriodDays` and TodoWrite retention (CC 2.1.117+)

See the dedicated subsection under [Tasks System](#tasks-system-v2116) (above, in Claude Code Feature Updates) for the full breakdown. Short version: pin `cleanupPeriodDays: 30` or higher in `.claude/settings.json` if you ever pause SDLC work for more than a week. The wizard ships this default in `cli/templates/settings.json` and the CLI's smart-merge preserves user overrides on `init --force`.

### MCP-tool hooks audit (ROADMAP #218, CC 2.1.118)

CC 2.1.118 introduced `type: "mcp_tool"` for hooks — a hook can now directly invoke an MCP tool instead of running a bash script. **Audit (2026-04-26) of the 5 wizard hooks that existed at the time concluded: none migrate, all stay bash.** This subsection documents the per-hook reasoning so future audits don't redo the work; if a future PR migrates a hook to MCP, update this entry with the new rationale rather than deleting it. **Not yet re-audited**: 3 hooks shipped since 2026-04-26 (`codex-gate-check.sh`, `token-spike-check.sh`, `codex-review-stop-check.sh`) — the project now registers 8 hooks total (see `.claude/settings.json`), but this table only covers the original 5.

**Decision criteria applied** (any one rules out MCP):

1. **Portability** — bash hooks port to the **shipped** sibling wizards (`codex-sdlc-wizard` for Codex CLI, `claude-gdlc-wizard` for the Game Development Life Cycle variant) and to a **planned** OpenCode sibling (ROADMAP #91, not yet shipped) without rewrite. MCP hooks are CC-specific. Cross-host / cross-domain portability is an XDLC requirement.
2. **Fail-closed gating** — hooks that block an action (exit 2 from PreCompact) need a fail-closed contract: any error in the hook MUST keep the block in place. CC docs ([code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks)) confirm `mcp_tool` hooks CAN gate via `decision: "block"` JSON output, but **MCP server errors are non-blocking by design** — if the MCP server is down/slow/buggy, the action proceeds. That breaks the fail-closed contract. Bash exit 2 fails closed.
3. **Local-only state** — hooks that read/write `~/.cache/sdlc-wizard/` or `.reviews/handoff.json` don't surface state across tool boundaries. MCP adds a wire format without consumers.

**Per-hook decision** (each row applies at least one criterion explicitly):

- **`sdlc-prompt-check.sh`** (UserPromptSubmit, ~137 lines) — emits the SDLC BASELINE text on every prompt (fires-once-per-session sentinel), plus a claude-setup-wizard redirect when SDLC.md/TESTING.md are missing. Decision: **Stay bash.** Portability criterion: same script ships to Codex sibling unchanged. Local-state criterion: sentinel cache is local-only. **#236(b) 2026-07-06:** the ROADMAP #195 effort-bump signal log described here previously was removed — never fired in ~2 months of live use.
- **`instructions-loaded-check.sh`** (~291 lines) — InstructionsLoaded event; wizard-version + CC-version staleness nudges (both npm-cached daily), cross-model-review staleness check, autocompact compound-misconfig check, dual-channel-install check. Decision: **Stay bash.** Portability criterion: Codex sibling has its own equivalent of session-start validation; bash port is direct. Local-state criterion: cache files are local. **#236(b) 2026-07-06:** the SDLC.md/TESTING.md missing-file warning previously described here was removed (redundant with `sdlc-prompt-check.sh`'s louder version).
- **`tdd-pretool-check.sh`** (~129 lines) — PreToolUse on Write/Edit/MultiEdit; emits a TDD reminder, and (since #436) **blocks** with `exit 2` when a `src/**` write (or `SDLC_TDD_SRC_PATTERN`-overridden path, added #236(b) for this repo's own `src/`-less dogfooding) happens before any test file was touched this session (an edit-ordering proxy for TDD RED, session-scoped via a cache-dir sentinel). Decision: **Stay bash.** Fail-closed gating criterion applies now that this hook blocks: bash `exit 2` fails closed by definition, whereas an `mcp_tool` hook's block decision is lost if the MCP server errors — wrong default for a gate. Portability criterion: still trivially portable.
- **`model-effort-check.sh`** (~87 lines) — SessionStart event; reads `CLAUDE_CODE_EFFORT_LEVEL` env var (falling back to `effortLevel` in the settings cascade), emits nothing when effort is `high`/`xhigh`/`max`/unset, otherwise a loud warning. Decision: **Stay bash.** Portability criterion: env-var read maps 1:1 to any agent runtime. Local-state criterion: not applicable, hook is stateless. **#236(b) 2026-07-06:** unset used to loud-warn too (CC's own default state) — now silent; only an explicit low-effort value or the settings-only-`max` quirk warns.
- **`precompact-seam-check.sh`** (~101 lines) — PreCompact event (matcher: `manual`); blocks manual `/compact` with exit 2 + stderr message when a git rebase/merge/cherry-pick is in progress. Decision: **Stay bash.** Fail-closed gating criterion: bash exit 2 fails closed by definition; an MCP `mcp_tool` hook returning `decision: "block"` works on the happy path, but if the MCP server crashes/times out the action proceeds — that flips the safety property from fail-closed to fail-open. For a hook whose entire job is to prevent context loss at bad seams, fail-open is the wrong default. **#236(b) 2026-07-06:** this hook used to also block on `.reviews/handoff.json` being `PENDING_*` (mid cross-model-review-round), with 3 self-heal paths mitigating that branch's false-positive rate — removed; every real firing on record was a false positive, never a true positive.

**When to revisit this audit:**

- A future hook genuinely needs cross-tool structured state surfacing (e.g., a "score history reader" that an MCP-aware skill consumes directly).
- Anthropic deprecates bash hooks in favor of `mcp_tool` (currently both are first-class).
- Codex / OpenCode siblings gain native MCP-tool hook support (then portability is no longer an MCP-rules-out).

Until then, default answer for new hooks is bash.

---

## Prove It's Better

**Don't reinvent the wheel.** Use native/built-in features UNLESS you prove your custom version is better. If you can't prove it, delete yours.

This applies to everything: native Claude Code commands vs custom skills, framework utilities vs hand-rolled code, library functions vs custom implementations.

**How to prove it:**
1. Test the native solution — measure quality, speed, reliability
2. Test your custom solution — same scenario, same metrics
3. Compare side-by-side
4. Native >= custom? **Use native. Delete yours.**
5. Custom > native? **Keep yours. Document WHY.** Re-evaluate when native improves.

**For the wizard's CI/CD:** When the weekly-update workflow detects a new Claude Code feature that overlaps with a wizard feature, the CI should automatically run E2E with both versions and recommend KEEP CUSTOM / SWITCH TO NATIVE / TIE.

**This applies to YOUR OWN additions too — not just native vs custom:**
- Adding a new skill? Prove it fills a gap nothing else covers. Write quality tests.
- Adding a new hook? Prove it improves scores or catches real issues.
- Adding a new workflow? Prove the automation ROI exceeds maintenance cost.
- Existence tests ("file exists", "has frontmatter") are NOT proof. They prove the file was created, not that it works.

**Evidence:** ci-analyzer skill was added in v1.20.0 with 4 existence-only tests, zero quality validation, and overlap with the third-party `/claude-automation-recommender`. Deleted in next release. This gap led to the Prove It Gate enforcement in the SDLC skill.

---

## What You're Setting Up

A workflow enforcement system that makes Claude Code:
- **Plan before coding** (Planning Mode → research → present approach)
- **Follow TDD** (write failing tests first, then implement)
- **Track progress** (TodoWrite for visibility)
- **Self-review** (catch issues before showing you)
- **Ask when unsure** (confidence levels prevent guessing)

**The Result**: Claude becomes a disciplined engineer who follows your process automatically.

---

## Philosophy First (Read This)

Before we configure anything, understand WHY this system works:

### 1. Planning Mode is Your Best Friend

**Start almost every task in Planning Mode.** Here's why:

**Hidden Benefit: Free Context Reset**
After planning, you get a free `/compact` - Claude's plan is preserved in the summary, and you start implementation with clean context. This is one of the biggest advantages of plan mode.

```
┌─────────────────────────────────────────────────────────────────┐
│ WITHOUT Planning Mode                                           │
│                                                                 │
│ User: "Add authentication"                                      │
│ Claude: *immediately starts writing code*                       │
│ Result: Maybe wrong approach, wasted effort, rework             │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ WITH Planning Mode                                              │
│                                                                 │
│ User: "Add authentication" + enters plan mode                   │
│ Claude: *researches codebase, understands patterns*             │
│ Claude: "Here's my approach. Confidence: MEDIUM. Questions..."  │
│ User: *approves or adjusts*                                     │
│ Claude: *now implements with clear direction*                   │
│ Result: Right approach, efficient implementation                │
└─────────────────────────────────────────────────────────────────┘
```

**Planning Mode + /compact = Maximum Efficiency**:
1. Claude researches in Planning Mode
2. Claude presents approach with confidence level
3. You approve → Claude updates docs
4. You run `/compact` → frees context, plan preserved in summary
5. Claude implements with clean context

**Plan Auto-Approval:** For HIGH confidence (95%+) tasks that are single-file or trivial (config tweak, small bug fix, string change) with no new patterns — skip plan approval and go straight to TDD. Claude still announces the approach but doesn't wait for approval. When in doubt, wait.

### 2. Confidence Levels Prevent Disasters

Claude MUST state confidence before implementing:

| Level | Meaning | What Claude Does |
|-------|---------|------------------|
| **HIGH (90%+)** | "I know exactly what to do" | Proceeds after your approval |
| **MEDIUM (60-89%)** | "Solid approach, some unknowns" | Highlights uncertainties |
| **LOW (<60%)** | "I'm not sure" | **Escalates before asking you** |
| **FAILED 2x** | "Something's wrong" | **Escalates to Fable, then Codex** |
| **CONFUSED** | "I don't understand why this is failing" | **Escalates, describing what was tried** |

**Why this matters**: You have domain expertise. When Claude is uncertain, asking you takes 30 seconds. Guessing wrong takes 30 minutes to fix.

### 3. TDD (Recommended, Customize to Your Needs)

The classic TDD cycle:
```
RED   → Write test that FAILS (proves feature doesn't exist)
GREEN → Implement feature (test passes)
PASS  → All tests pass (no regressions)
```

**The core principle:** Have a testing strategy. Know what you're testing and why.

**Customize for your team:**
- Strict TDD (test first wherever a RED mutation is writable)? Great.
- Test-after for some cases? Fine, just be consistent.
- The key: **don't commit code that breaks existing tests.**

**Test review preference:** Ask the user if they want to review each test before implementation, or trust the TESTING.md guidelines. Tests validate code - some users want oversight, others trust the process. If tests start failing or missing bugs, investigate why.

### 4. Testing Strategy (Define Yours)

Here's the "Testing Diamond" approach (recommended for AI agents):

```
        /\           ← Few E2E (automated like Playwright, or manual sign-off)
       /  \
      /    \
     /------\
    |        |       ← MANY Integration (real DB, real cache - BEST BANG FOR BUCK)
    |        |
     \------/
      \    /
       \  /
        \/           ← Few Unit (pure logic only)
```

**Why Integration Tests are Best Bang for Buck:**
- **Speed**: Fast enough to run on every change
- **Stability**: Touch real code, not mocks that lie
- **Confidence**: If integration tests pass, production usually works
- **AI-friendly**: Give Claude concrete pass/fail feedback on real behavior

**E2E vs Integration — The Critical Boundary:**
- **E2E**: Tests that go through the user's actual UI/browser (Playwright, Cypress). ~5% of suite.
- **Integration**: Tests that hit real systems via API without UI — real DB, real cache, real services. ~90% of suite.
- **Unit**: Pure logic only — no DB, no API, no filesystem. ~5% of suite.
- **The rule**: If your test doesn't open a browser or render a UI, it's not E2E — it's integration. Mislabeling leads to overinvestment in slow browser tests.

#### Domain-Adaptive Testing Layers

The Testing Diamond above is the Web/API default. Other project domains have fundamentally different testing layers. The setup wizard auto-detects your domain and generates the appropriate TESTING.md.

**Domain Detection Patterns:**

| Domain | File/Dir Indicators |
|--------|-------------------|
| **Firmware/Embedded** | Makefile with `flash`/`burn` targets, `.cfg` device configs, `/sys/` or `/dev/tty` references, `.c`/`.h` source, `platformio.ini`, `CMakeLists.txt` with embedded targets |
| **Data Science** | `.ipynb` notebooks, `requirements.txt` with pandas/sklearn/tensorflow/torch, `data/` or `datasets/` dir, `models/` dir, Jupyter config |
| **CLI Tool** | `package.json` with `"bin"` field (no React/Vue/Angular), `bin/` dir, `src/cli.*`, no `src/components/` |
| **Web/API (default)** | Everything else — web frameworks, `src/components/`, Playwright/Cypress config, DB config. Fallback when no other domain matches |

**Firmware/Embedded Testing Layers:**

```
        /\           ← Few HIL (Hardware-in-the-Loop: real device, flash + boot verify)
       /  \
      /    \
     /------\
    |        |       ← MANY SIL (Software-in-the-Loop: emulated hardware, QEMU, device sims)
    |        |
     \------/
      \    /        ← Config Validation (device config parsing, constraint checks)
       \  /
        \/           ← Few Unit (parsers, formatters, math)
```

- **HIL (~5%)**: Hardware-in-the-Loop — flash to real device, verify boot, test hardware interfaces
- **SIL (~60%)**: Software-in-the-Loop — emulated hardware via QEMU or device simulators. Best bang for buck
- **Config Validation (~25%)**: Device config (.cfg) parsing, cross-device constraint checks, valid value ranges
- **Unit (~10%)**: Pure logic only — parsers, formatters, math functions
- **Mocking**: Mock hardware interfaces (`/dev/tty*`, GPIO), NEVER mock config parsers
- NO browser tests, NO database mocking

**Data Science Testing Layers:**

```
        /\           ← Few Model Evaluation (accuracy/precision/recall on holdout sets)
       /  \
      /    \
     /------\
    |        |       ← MANY Pipeline Integration (end-to-end with test datasets)
    |        |
     \------/
      \    /        ← Data Validation (schema checks, distribution drift, missing values)
       \  /
        \/           ← Few Unit (pure transformations, feature engineering)
```

- **Model Evaluation (~10%)**: Accuracy, precision, recall, F1 on holdout test sets. Catches model degradation
- **Pipeline Integration (~60%)**: End-to-end pipeline runs with test datasets. Best bang for buck
- **Data Validation (~20%)**: Schema checks, distribution drift detection, missing value handling, type enforcement
- **Unit (~10%)**: Pure transformations, feature engineering functions, data cleaning logic
- **Mocking**: Mock external data sources (APIs, S3), NEVER mock data transformations
- NO browser tests, NO traditional API endpoint testing

**CLI Tool Testing Layers:**

```
     /------\
    |        |       ← MANY CLI Integration (full invocations, real args, real filesystem)
    |        |
    |        |
     \------/
      \    /        ← Behavior (exit codes, stdout/stderr content, file creation)
       \  /
        \/           ← Few Unit (arg parsing, formatters, pure logic)
```

- **CLI Integration (~80%)**: Full CLI invocations with real arguments and real filesystem. Best bang for buck
- **Behavior (~10%)**: Exit codes, stdout/stderr output validation, file creation/modification verification
- **Unit (~10%)**: Argument parsing, output formatters, pure logic
- **Mocking**: Mock network calls, NEVER mock filesystem operations
- NO browser tests, usually NO database

**But your team decides:**

| Question | Your Choice |
|----------|-------------|
| Do you need E2E tests? | Maybe not for backend-only services |
| Heavy on unit tests? | Fine for pure logic codebases |
| Integration-first? | Great for systems with real DBs |
| No tests yet? | Start somewhere, even basic tests help |

**The point:** Have a testing strategy documented in TESTING.md. Claude will follow whatever approach you define.

### 5. Mocking Strategy (Philosophy, Not Just Tech)

**The Problem:** AI agents (and humans) tend to mock too much. Tests that mock everything test nothing - they just verify the mocks work, not the actual code.

**Minimal Mocking Philosophy:**

| Dependency | Mock It? | Reasoning |
|------------|----------|-----------|
| Database | ❌ NEVER | Use test DB or in-memory |
| Cache | ❌ NEVER | Use isolated test instance |
| External APIs | ✅ YES | Real calls = flaky + expensive |
| Time/Date | ✅ YES | Determinism |

**The key insight:** When you mock something, you're saying "I trust this works." Only mock things you truly can't control (external APIs, third-party services).

**But your team decides:**
- Heavy mocking preferred? Document it.
- No mocking at all? Document it.
- Mocks from fixtures? Document where fixtures live (e.g., `tests/fixtures/`).

**The point:** Have a mocking strategy documented. Claude will follow it. The goal is tests that prove real behavior, not just pass.

### 6. SDET Wisdom (Test Code is First-Class)

**Test Code = First-Class Citizen**
Treat test code like app code - code review, quality standards, not throwaway. Tests are production-critical infrastructure.

### Tests As Building Blocks

Existing test patterns are building blocks - leverage them:
- **Similar tests exist and are good?** - Copy the pattern, adapt for your case
- **Similar tests exist but are bad?** - Propose improvement, worth the scrutiny
- **No similar tests?** - More scrutiny needed, may need human input on approach

**Existing patterns aren't sacred.** Don't blindly copy bad patterns just because they exist. Improving a stale pattern is worth the effort.

**Before fixing a failing test, ask:**
1. Do we even need this test? (Is it for deleted/legacy code?)
2. Is this tested better elsewhere? (DRY applies to tests too)
3. Is the test wrong, or is the code wrong?

**Don't ignore flaky tests:**
- Flaky tests have revealed rare edge case bugs that later hit production
- "Nothing stings more than a flaky test you ignored coming back to bite you in prod"
- Dig into every failure - sweeping under the rug compounds problems

**Three categories of test failures:**

| Category | Examples | Fix |
|----------|----------|-----|
| **Test code bug** | Not parallel-safe, shared state, wrong assertions | Fix the test code (most common) |
| **Application bug** | Race condition, timing issue, edge case | Fix the app code - test found a real bug |
| **Environment/Infra bug** | CI config, memory, isolation issues | Fix the environment/setup/teardown |

### The Absolute Rule: ALL TESTS MUST PASS

```
┌─────────────────────────────────────────────────────────────────────┐
│  ALL TESTS MUST PASS. NO EXCEPTIONS.                                │
│                                                                     │
│  This is not negotiable. This is not flexible. This is absolute.   │
└─────────────────────────────────────────────────────────────────────┘
```

**Not acceptable excuses:**
- "Those tests were already failing" → Then fix them first
- "That's not related to my changes" → Doesn't matter, fix it
- "It's flaky, just ignore it" → Flaky = bug, investigate it
- "It passes locally" → CI is the source of truth
- "It's just a warning" → Warnings become errors, fix it

**The fix is always the same:**
1. Tests fail → STOP
2. Investigate → Find root cause
3. Fix → Whatever is actually broken (code, test, or environment)
4. All tests pass → THEN commit

**Why this is absolute:**
- Tests are your safety net
- A failing test means something is wrong
- Committing with failing tests = committing known bugs
- "Works on my machine" is not a standard

**MCP Awareness for Testing (optional, nuanced):**
- **Where MCP adds real value:** E2E/browser testing (can't "see" UI without it), graphics projects, external systems Claude can't otherwise access
- **Often overkill for:** API/Integration tests (reading code/docs is usually sufficient), internal code work
- **Reality check:** As Claude improves, fewer MCPs are needed. Claude Code has MCP Tool Search (dynamically loads tools >10% context)
- **The rule:** Suggest where it adds real value, don't force it. Let user decide.

---

### 7. Delete Legacy Code (No Fallbacks)

When refactoring:
- Delete old code FIRST
- If something breaks, fix it properly
- No backwards-compatibility hacks
- No "just in case" fallbacks

**Why this works with TDD:** Your tests are your safety net. If deleting breaks something, tests catch it. Fix properly, don't create hybrid systems. This simplifies your codebase and lets you "play golf" - less code to maintain.

### 8. Documentation Hygiene

Before starting any task, Claude should:

1. **Find relevant documentation** - Search for docs related to the feature/system
2. **Assess documentation health** - Is it current? Bloated? Useful?
3. **ASK before cleaning** - Never delete or refactor docs without user approval

**Signs a doc might need attention:**
- Very large file with mixed concerns
- Outdated information mixed with current
- Duplicate information across files
- Hard to find what you need

**But remember:**
- Complex systems have complex docs - that's OK
- Size alone doesn't mean bloat - some things ARE complex
- Context and usefulness matter more than line count
- When in doubt, ASK the user

**The rule:** Identify doc issues during planning, propose cleanup, get approval. Never nuke docs on your own.

### 9. Security Review (Calibrated to Your Project)

Security review depth should match your project's risk profile. During wizard setup, Claude will ask about your context to calibrate:

**Calibration Questions (during wizard):**
- Is this a personal project or production?
- Internal tool or public-facing?
- Handling sensitive data (PII, payments)?
- How many users?
- What's your attack surface?

**Then Claude calibrates:**

| Project Type | Security Review Depth |
|--------------|----------------------|
| Personal/learning project | Quick sanity check ("anything obvious?") |
| Internal tool, few users | Basic review of exposed endpoints |
| Production, sensitive data | Full review: auth, input validation, data exposure |
| Payment/financial | Extra scrutiny, consider external audit |

**Quick reference - which changes need review?**

| Change Type | Review? |
|-------------|---------|
| Auth/login changes | Yes |
| User input handling | Yes |
| API endpoints | Yes |
| Database queries | Yes |
| File operations | Yes |
| Internal refactoring | Usually no |
| UI/styling only | Usually no |

**What to check (when warranted):**
- Input validation at system boundaries
- Authentication/authorization on sensitive operations
- Data exposure risks
- Patterns appropriate for YOUR stack and attack surface

**The principle:** Always do a security review, but depth varies. A personal CLI tool doesn't need the same scrutiny as a payment API. Claude can always say "nothing to see here" for low-risk changes.

**Customize in wizard:** You can set your default review depth, and Claude will adjust based on what the code actually touches.

---

## Context Management: `/clear` vs `/compact`

Two tools for managing context — use the right one:

| | `/compact` | `/clear` |
|---|---|---|
| **What it does** | Summarizes conversation, frees space | Resets conversation entirely |
| **When to use** | Continuing same task, need more room | Switching to an unrelated task |
| **Preserves** | Summary of decisions + progress | Nothing (fresh start) |
| **CLAUDE.md** | Re-loaded from disk | Re-loaded from disk |
| **Hooks/skills/settings** | Unaffected | Unaffected |
| **Task list** | Persists | Cleared |

**Rules of thumb:**
- `/compact` between planning and implementation (plan preserved in summary)
- `/clear` between unrelated tasks (stale context wastes tokens and misleads Claude)
- `/clear` after 2+ failed corrections on the same issue (context is polluted with bad approaches — start fresh with a better prompt)
- After committing a PR, `/clear` before starting the next feature

**Auto-compact** fires automatically at ~95% context capacity. Claude Code handles this by default — but the default threshold may not be ideal for all use cases (see "Autocompact Tuning" below). The SDLC skill suggests `/compact` during CI idle time as a "context GC" opportunity.

### Working context ceiling — why ~40-60%, not "the window is 1M so use 1M"

A large advertised context window is not a large *usable* one. Model quality degrades well below the stated limit, this is measured rather than folklore, and it is **not** specific to any one vendor.

| Evidence | What it found |
|---|---|
| [Chroma, "Context Rot"](https://www.trychroma.com/research/context-rot) | 18 models (Claude Opus/Sonnet 4, GPT-4.1, Gemini 2.5): performance becomes "increasingly unreliable as input length grows" — non-uniformly, on even trivial tasks, and worse with distractors present |
| [NoLiMa](https://arxiv.org/abs/2502.05167) | At **32K**, 11 of the 13 models evaluated fall below **50%** of their own short-context baseline. GPT-4o: 99.3% → 69.7% |
| [RULER](https://arxiv.org/abs/2404.06654) | Only about half of models claiming ≥32K actually sustain performance there; "effective" length is routinely a fraction of the advertised one |
| [Lost in the Middle](https://cs.stanford.edu/~nfliu/papers/lost-in-the-middle.arxiv2023.pdf) | A pronounced U-shaped curve across six model variants (four families: Claude, GPT-3.5, MPT, LongChat) — accuracy is worst when the needed fact sits mid-context. The paper reports a >20-point drop for GPT-3.5 specifically |

Anthropic's own [context-engineering guidance](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) points the same way: it frames attention as a finite "attention budget," advises finding the *smallest* high-signal token set, and calls compaction the first lever.

**The rules this repo ships:**

1. **Work under ~350K tokens** — about 35% of a 1M window. This is the maintainer's working number, adopted deliberately as a practitioner heuristic to be validated by use rather than derived from a study. It sits at the conservative end of reported practice: [HumanLayer's ace-fca.md](https://github.com/humanlayer/advanced-context-engineering-for-coding-agents/blob/main/ace-fca.md) recommends 40-60% utilization depending on task complexity, and community numbers cluster at 80-200K for 200K-window models and 200-500K for 1M-window models. **Nobody has benchmarked a specific cliff, and this repo is not claiming one.**
2. **Compact deliberately at ~60%.** Autocompact fires near the hard limit (~95%), which leaves no room to choose what survives the summary — practitioner-reported, and consistent with Anthropic's advice to treat compaction as a deliberate lever rather than a backstop.
3. **Run the test — a completion claim is not a test result.** Not conditioned on occupancy: the research behind it concerns self-assessment and says nothing about context length. Always-on, not a threshold that switches in.

### Rule 3: run the test — a completion claim is not a test result

This rule needs no inference and no statistics. **A test result is evidence. A claim that something
is fixed is not a test result.** Run the thing.

What the research adds is only that the failure mode is common enough to be worth a rule.
[arXiv:2606.09863](https://arxiv.org/html/2606.09863) (June 2026) measured, **among runs that had
already failed**, how often the agent nonetheless asserted success: **45% and 48%** of failures in
tau2-bench's airline and retail single-control domains, **3%** in telecom, and **75.8%** of AppWorld
failures that carried an explicit status claim. It also found LLM judges detect this poorly —
AUROC ≤0.65 on tau2-bench, ~0.54 on AppWorld — while reporting that calibrated detectors are
useful for triage.

**What those numbers do NOT establish**, because they are conditioned on failure: how much a
success claim should shift your confidence. Inverting that conditional would additionally require
knowing how often *successful* runs assert completion — a different measurement. Five review rounds
of this section tried to phrase such an inference — "evidence of nothing", then "weak evidence",
then "little diagnostic weight", and then a caveat that misdescribed which quantity was missing —
and every version was the same unsupported step. There is no need for it: *run the test* stands on
its own.

**Observed here.** During the v1.92.0 release one agent declared a defect class closed **six
consecutive times** while an external reviewer produced a working bypass each round. That is one
uncontrolled anecdote, not evidence of a rate — recorded because it is what prompted the rule.

**Provenance, stated honestly:** the degradation itself is benchmarked (above). The specific **~350K** figure sometimes quoted for 1M-context models is **practitioner-reported, not benchmarked** — practitioner numbers cluster at 80-200K for 200K-window models and 200-500K for 1M-window models. The percentages in rules 1-2 are practitioner-reported; rule 3's 75.8% is measured.

**What survives `/compact`:** Key decisions, code changes, task state (as a summary). What can be lost: detailed early-conversation instructions not in CLAUDE.md, specific file contents read long ago.

**Best practice:** Put persistent instructions in CLAUDE.md (survives both `/compact` and `/clear`), not in conversation.

### Compact at Seams, Not Thresholds (PreCompact hook)

**The threshold is the trigger, not the decision.** 25-30% remaining (~70% used) is the commonly-cited "sweet spot" but ignores *what you're doing* at that moment. Compacting mid-Codex-round loses the round-1 evidence and certify conditions that round-2 needs to re-verify. Compacting mid-rebase strands the operation without the context that was setting it up.

A **seam** is a point where losing conversational context is safe:
- Commit boundary (change persisted to git)
- Codex `CERTIFIED` (review cycle closed)
- PR merged (work shipped)
- ROADMAP item marked DONE

The wizard's `PreCompact` hook (`hooks/precompact-seam-check.sh`) enforces this for **manual** `/compact` only — it reads `.reviews/handoff.json` and blocks with `HOLD` + exit 2 when status is `PENDING_REVIEW` / `PENDING_RECHECK`, and also blocks when a git rebase, merge, or cherry-pick is in progress. Auto-compact is **not** gated — blocking it could push past 100% context and lose everything. Requires Claude Code **v2.1.105+** (PreCompact event introduced 2026-04-13).

**What's NOT checked:** in-progress TodoWrite tasks. Claude Code does not persist TodoWrite state to a file readable from a hook, so "finish the current todo first" is on you, not the hook. Watch the TodoWrite panel before you `/compact`.

Override: resolve the blocker (certify the review, finish the rebase), or temporarily disable the hook in `.claude/settings.json`. Don't suppress the warning reflexively — the warning is the point.

### Autocompact Tuning

Override the default auto-compact threshold with environment variables. Per official docs ([model-config](https://code.claude.com/docs/en/model-config#sonnet-5-context-window), [env-vars](https://code.claude.com/docs/en/env-vars)): `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` is applied as a percentage of `CLAUDE_CODE_AUTO_COMPACT_WINDOW` — which itself defaults to the model's own tuned threshold, not necessarily the raw context capacity. **The override can only lower the threshold; values above the model's default have no effect.** For a rigorous benchmarking methodology to validate these thresholds, see [AUTOCOMPACT_BENCHMARK.md](AUTOCOMPACT_BENCHMARK.md).

| Variable | What It Does | Default |
|----------|-------------|---------|
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | Trigger compaction at this % of `CLAUDE_CODE_AUTO_COMPACT_WINDOW` (1-100). Lower-only. | Model-dependent (see below) |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | Override context capacity in tokens used for compaction math | Model's context window — **except Sonnet 5**, which has its own default |

**Sonnet 5 specifics:** Sonnet 5 always runs at 1M context (no 200K variant, no `[1m]` suffix needed) and proactively compacts at its own tuned default of **~967K tokens (96.7%)** — not the generic 1M ceiling. `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75` on Sonnet 5 fires at ~75% *of that 967K*, i.e. ~725K tokens — earlier and safer than the native default, not later. **Do not carry over an `opus[1m]`-era `30%` setting to Sonnet 5** — that figure was derived for `opus[1m]`'s older extended-context opt-in, never re-derived for Sonnet 5's smarter native default, and is needlessly conservative here (verified 2026-07-05).

**Opus 5 specifics (Setup A):** `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` only causes *earlier* compaction where Claude Code compacts **proactively** — per [env-vars](https://code.claude.com/docs/en/env-vars): when `CLAUDE_CODE_AUTO_COMPACT_WINDOW` is set, in cloud sessions, on Sonnet 4.6/Opus 4.6 without extended context, and on Sonnet 5 at its own default threshold. The docs' example of the non-proactive bucket is a local session on **Opus 4.8** ("auto-compaction triggers when the conversation reaches the model's context limit"); they give no Opus-5-specific threshold or behavior either way. **Claude Code documents no Opus-5-specific proactive threshold or percentage — so Setup A sets no `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` at all.** On Max, bare `opus` auto-upgrades to 1M ([model-config](https://code.claude.com/docs/en/model-config)); that establishes *capacity*, not proactive mode, and does not license a percentage. If you want a deliberately earlier boundary on 1M Opus, `CLAUDE_CODE_AUTO_COMPACT_WINDOW` (e.g. `500000`) is the documented knob — setting it *makes* compaction proactive, which is also why a PCT override then multiplies against it rather than being ignored (#207). Use the window alone, and see "Autocompact mechanics" below for the arithmetic. A smaller window compacts sooner — it does not switch compaction off. `/compact` at a phase boundary works regardless of model.

> **`env` is global, not per-model.** `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` in `.claude/settings.json` applies to whichever model runs under that file — and, per the same doc row, "to both main conversations and subagents". Switching drivers does **not** switch its value: a file carrying Setup B's `75` keeps supplying `75` after you switch to Opus. No static `env` object can express "75 for Sonnet, none for Opus" — if you want per-model tuning, edit the key when you change persistent pins, or keep separate settings profiles.

**Opt-in (issue #198):** The SDLC Harness CLI ships `.claude/settings.json` with **no** `model`, `advisorModel`, or `env` pin so Claude Code's auto-mode stays enabled. The setup skill's Step 9.5 offers four choices: no pin (default, auto-mode), Opus 5 + Fable advisor (recommended if pinning at all, Setup A, trial as of 2026-07-24), OpusPlan Hybrid with a Fable advisor (Setup C), and Sonnet 5 Simple/One-Off + Fable advisor (Setup B). Opus 4.8 itself is a pinned escalation model, not a persistent Step 9.5 pin — reach for it per-session via `/model claude-opus-4-8` when the driver gets stuck (see "Latest tier" below). Default is **No pin**. Pinning the model turns off per-turn auto-selection — a real tradeoff, so we ask.

To opt in by hand, edit `.claude/settings.json` (Opus 5 example — the recommended default, trial as of 2026-07-24):

```json
{
  "model": "opus",
  "advisorModel": "fable",
  "effortLevel": "high"
}
```

No `env` block: Claude Code documents no Opus-5 proactive threshold, so there is no supported percentage to set (see "Opus 5 specifics" above).

For the older `claude-opus-4-6` pin instead (still valid for proven stability), a percentage override *is* supported — Opus 4.6 without extended context is one of the documented proactive-compaction cases, so unlike on the current default driver the percentage is genuinely live here. **But mind the window it acts on.** An explicit `claude-opus-4-6` string pins **200K**; the Max auto-upgrade to 1M applies to the bare `opus` alias, not to an explicit version string. So a `30` here is 30% of 200K — a **~60K trigger**, the same over-aggressive setting this doc warns about for `opusplan` further down. Earlier revisions shipped exactly that pairing, annotated "(1M)", and it was wrong on both counts (GH #520). Use the 200K figures from the table above:

```json
{
  "model": "claude-opus-4-6",
  "advisorModel": "fable",
  "env": {
    "CLAUDE_CODE_EFFORT_LEVEL": "max",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "75"
  }
}
```

That block is the **legacy Opus 4.6 pin**, not Setup A. Setup A pins bare `opus` and sets no override — see "Opus 5 specifics" above for why a 1M window alone doesn't justify a percentage.

**Recommended thresholds by use case:**

| Use Case | AUTOCOMPACT % | Why |
|----------|--------------|-----|
| **Setup A default driver (trial as of 2026-07-24)** | **none** | No proactive-compaction threshold is documented for it, so no percentage is supported — see "Opus 5 specifics". Use `CLAUDE_CODE_AUTO_COMPACT_WINDOW` if you want an earlier boundary. |
| Sonnet 5 (Simple/One-Off driver) | **75%** | Fires at ~75% of its native ~967K threshold (~725K tokens) — safe margin without being overly conservative. Verified against official docs 2026-07-05. |
| General development (200K `opus`) | 75% | Leaves room for implementation after planning |
| Complex refactors (200K `opus`) | 80% | Slightly more context before compaction |
| CI pipelines | 60% | Short tasks, compact early to stay fast |
| Short tasks | 60-70% | Less context needed, compact early |

**Important:** Values above the default ~95% threshold have no effect — you can only trigger compaction *earlier*, not later. Noise (progress ticks, thinking blocks, stale reads) makes up 50-70% of session tokens, so threshold tuning matters less than noise reduction (scoped reads, subagents, `/compact` between phases).

**Note:** These env vars may change as Claude Code evolves. Check [Claude Code settings docs](https://docs.anthropic.com/en/docs/claude-code/settings) for the latest supported configuration.

### Benchmarking Methodology

The thresholds above are community consensus — not empirically validated. For rigorous benchmarking of autocompact thresholds (measuring task quality, context preservation, and cost at each setting), see [AUTOCOMPACT_BENCHMARK.md](AUTOCOMPACT_BENCHMARK.md). It provides a controlled experimental methodology with a novel "canary fact" mechanism for measuring context preservation post-compaction.

### 1M vs 200K Context Window

Claude Code supports both 200K and 1M context windows. **This section is about Opus** — `opus[1m]` is an opt-in power-user pin, and ask yourself whether you actually need the headroom before setting it, because pinning the model at the top level disables Claude Code's auto-mode (see issue #198). **Sonnet 5 is a different case: it always runs at 1M natively** (no `[1m]` suffix, no opt-in decision, no auto-mode tradeoff) — see [`code.claude.com/docs/en/model-config#sonnet-5-context-window`](https://code.claude.com/docs/en/model-config#sonnet-5-context-window). The table below applies to choosing whether to pin Opus at 1M, not to Sonnet 5.

| | 200K Context (default / auto-mode) | 1M Context (`opus[1m]`, opt-in) |
|---|---|---|
| **Best for** | Most work — auto-mode picks Sonnet/Opus per turn | Multi-feature / long plan+TDD+review cycles where a single session really crosses 100K+ |
| **Typical usage** | 50-80K tokens per task | 50-80K typical, up to 200K+ for complex workflows |
| **Cost** | Standard pricing | Anthropic currently lists the 1M window at standard pricing across the full context for supported Opus/Sonnet models — **verify current rates at [docs.anthropic.com/pricing](https://docs.anthropic.com/)** before assuming no premium |
| **Auto-mode** | **Enabled** — Claude Code chooses model per turn | **Disabled** — top-level `model` tells CC you've chosen explicitly |
| **Auto-compact** | Default ~95% works well | `opus[1m]` resolves to whichever Opus is current, so no fixed threshold is documented for it. The ~76K figure in [issue #34332](https://github.com/anthropics/claude-code/issues/34332) was observed on the older extended-context opt-in and has not been re-derived since — don't treat it as current behavior. See "Opus 5 specifics" above. |
| **Suggested override (if you pin)** | `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75` | None by default — no proactive threshold is documented for a current-Opus local session, so the percentage alone is inert. If you want an earlier boundary, use `CLAUDE_CODE_AUTO_COMPACT_WINDOW` alone (e.g. `400000`), which both makes compaction proactive and sets the boundary. A smaller value compacts sooner, not never (see below). |

#### Autocompact mechanics — compute the trigger, don't guess it

Verified against decompiled Claude Code **v2.1.221** (functions `EX`, `CCo`, `F0s`, `ZJu`, `fEe`, `kO`). Version-stamped deliberately: these are implementation constants, not a documented contract, and they can move.

```
window    = min(model_window, clamp(AUTO_COMPACT_WINDOW, 100000..1000000))
threshold = min(floor(window × PCT_OVERRIDE/100), window − 13000)
           ...with up to 20000 tokens of system overhead subtracted first
```

**`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` is a percentage of *used* context, and it is inert unless something puts your session in the "proactive" bucket** — the window var being set, a cloud session, Sonnet 4.6/Opus 4.6 *without* extended context, or Sonnet 5. On a local current-Opus session with no window set, it does **nothing**, and compaction happens at the model's context limit. This is measured, not inferred: a session running `PCT_OVERRIDE=35` alone reached 42% of a 1M window with no compaction.

**Five traps, in the order they bite:**

1. **A window under 200000 makes compaction fire sooner, not later.** There is no lower bound below which compaction switches off: the live trigger is `LXy` → `jUe` → `zJu`, which has no such gate. The `bIe = 200000` check belongs to `ZJu`, a *different* function that arms the **precomputed** summary — below it compaction still happens, reactively rather than pre-warmed. Two near-identical names, one letter apart, and reading the wrong one is how this document previously claimed the opposite (see "How this section was wrong" below).
2. **The two vars multiply.** `30% × 400000` gives 114000 — ~11% of a 1M window (#207). But `35% × 1000000` gives 343000, a perfectly sane deliberate boundary. Both figures are the percentage of the window *after* overhead comes off, which is where `CCo` applies it; the naive products (120000, 350000) overstate each by the overhead share. **Setting both is arithmetic, not an error.** What matters is where the product lands, so compute it and sanity-check it against your real window.
3. **Env is read at launch.** Editing `settings.json` mid-session changes nothing, and there is no mechanism to *unset* a var in a live process. `claude --resume` is the fix; it preserves the transcript. If you are stuck mid-session with compaction firing too early, `autoCompactEnabled: false` (settings.json or `/config`) is read **live** by `kO` and stops it without a restart — that is the settings key only; `DISABLE_AUTO_COMPACT=1` as a real env var also stops compaction but cannot be unset in a live process — at the cost of running to the hard limit instead. Interim only.
4. **A suffix is not read as its human meaning — `150k` parses as `150`.** The window var goes through `parseInt` as a fallback, so `150k` becomes `150`, which the 100000 floor then raises to a **100000** window: a real trigger around 67000, on a config the operator reads as "150 thousand". `1,000,000` is accepted and means what it looks like; `150000.5` truncates. Write plain integers, with no suffix, separator or decimal point — this is the one trap here that leaves nothing on screen to notice.
5. **Diagnose from the live env, not the settings file.** `env | grep -iE "compact|CLAUDE_CODE"` first, then `~/.claude/settings.json`, then `settings.local.json` / `~/.claude.json`, then shell rc, then `launchctl getenv`. The settings file is a *claim* about the process; the env is the process.

**Recommended, scoped by what you are running — there is no single right answer here, and claiming one is how this section was wrong before:**

| Your driver | Recommendation | Why |
|---|---|---|
| **Auto-mode (no pin)** — the default | **Set neither.** | Whichever model runs per turn brings its own tuned default. A static `env` cannot express per-model tuning (see the `env` note above), so any value you pick is wrong for some turn. |
| **Current Opus (Opus 5), 1M** | **Set neither.** If you deliberately want an earlier boundary, `CLAUDE_CODE_AUTO_COMPACT_WINDOW` **alone**, ≥ 200000. | A percentage alone is inert here — no proactive threshold is documented, and a live session confirmed it: percentage-only, well past a third of the window consumed, no compaction. The window var both enables proactive mode and sets the boundary. |
| **Sonnet 5** | `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75` — unchanged. | Sonnet 5 compacts proactively at its own ~967K default, so the percentage is live and acts on a known number. This is the case where the percentage is the *right* knob. |
| **Explicit `claude-opus-4-6` pin** | Percentage, sized against **200K** — use the 200K rows in the table above, not the 1M figures. | The percentage is live (Opus 4.6 without extended context is a documented proactive case) but the window is small, so `30` means ~60K, not a 1M-era boundary. An explicit version string does not get the Max auto-upgrade. |
| **`opusplan`** | **Set neither.** | Not a single surface: it runs current Opus for planning and Sonnet 5 for execution, and Sonnet 5 is natively 1M. One `env` value would have to be right for both halves, and no value is. |

**Deliberately wanting earlier compaction is legitimate** — long contexts degrade output quality — so this is about picking the knob that is actually connected on your surface, not about avoiding the knobs.

**Where you have the choice, prefer the window var to the two-var form**, for one specific reason: `min()` clamps the window to the model's own, so a one-var setting degrades gracefully on a smaller model, while `WINDOW=1000000 + PCT=35` silently becomes a trigger around 70000 the moment a 200K model runs under it — lower still once system overhead comes off. Note the two are not exactly interchangeable — the `window − 13000` cap and the system-overhead subtraction both apply — so treat any single number here as approximate.

The `instructions-loaded-check.sh` `InstructionsLoaded` hook (session start/resume) reports the effective trigger — warning only when the product lands below 200000, and otherwise stating it as the deliberate choice it probably is (#207, #520).

**How this section was wrong, and what that cost.** The first version of it stated trap 1 backwards: that a sub-200000 window *disabled* compaction. It came from reading `ZJu` and attributing its gate to the live path, which is `zJu` — the same eight characters in a different case. Thirteen rounds of adversarial cross-model review certified the machinery that guards these sentences and never once asked whether a sentence was true, because it was never asked to. A second reviewer, briefed on the claims rather than the guards, disproved it against the running binary in one pass. Guard coverage is not claim truth, and the two need separately commissioned reviewers (#502, #515).

**Why `opus[1m]` is opt-in (issue #198):**
- **Pinning disables auto-mode.** Max-plan users pay for Claude Code's per-turn model selection (Sonnet for cheap tasks, Opus for hard ones, plus weekly-limit smoothing). A top-level `model` gives that up.
- **The 1M headroom has to earn it.** If your typical session stays under 150K, you're giving up auto-mode for headroom you're not using.
- **⚠️ `opus[1m]` is NOT guaranteed to mean any specific version.** The alias auto-resolves to whichever Opus model Claude Code currently considers "latest" — that was Opus 4.6, then 4.8, and as of 2026-07-24 means **Opus 5**. If you specifically want Opus 4.6 (proven `max`-effort consistency) or Opus 4.8 (field-proven, pre-Opus-5), pin the explicit model string (`claude-opus-4-6` or `claude-opus-4-8`), not the `opus[1m]` alias.

**Opt in when:** you routinely cross 100K tokens in a single session (plan → TDD → review → CI shepherd on one feature), you want guaranteed 1M context on whichever Opus is current (or `claude-opus-4-6` explicitly if you want Opus 4.6 specifically), and you're OK losing auto-mode.

**Stay on auto-mode (default) when:** you're unsure, your work is mixed short/long, or you want Claude Code to do the model math for you.

**How to opt in:** run `/model opus` in your session (transient) for the current default (Opus 5 on Max, auto-upgraded to 1M), `/model opus[1m]` to force 1M explicitly on other plans, or `/model claude-opus-4-6` if you specifically want Opus 4.6; set `"model"` to any of these values in `.claude/settings.json` for a persistent pin. Requires Claude Code v2.1.219+ for `opus` to resolve to Opus 5 (v2.1.154+ for the older `opus[1m]` alias, which still resolves to whichever Opus is current). The setup wizard's Step 9.5 also asks once, with default No.

**How to opt out:** remove the `model` line from `.claude/settings.json`, or run `/model` and pick "Default (recommended)".

**Cost awareness:** Larger windows let you consume more tokens in one session, and total cost always scales with tokens consumed regardless of tier. Use `/usage` to monitor (aliases: `/cost`, `/stats`) — a 900K-token session is meaningfully more expensive than an 80K one even at standard rates.

**Autocompact pairing — no longer recommended for `opus[1m]`:** older versions of this doc told you to pair the `opus[1m]` pin with `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=30`. That pairing was derived for the original extended-context opt-in and has never been re-derived; since `opus[1m]` now resolves to the current Opus, the docs give no proactive threshold that the percentage would act on. **Set no override.** If you want an earlier boundary, set `CLAUDE_CODE_AUTO_COMPACT_WINDOW` alone at 200000 or above — that makes compaction proactive *and* sets the boundary in one var, where adding a percentage on top only multiplies against it (#207, #520). Setup A pins bare `opus` and Step 9.5 writes no override at all. See "Opus 5 specifics" and "Autocompact mechanics" above.

### OpusPlan Tier (Opus planner + Sonnet driver, #395) — Setup C

This is **Setup C (OpusPlan Hybrid/Saver)** in `AI_SETUP_LANES.md`. CC's native `opusplan` alias gives you Opus reasoning during Plan Mode (Shift+Tab) and Sonnet execution — both Max-bundled, no API credit drain. `opusplan` follows the `opus` alias, currently Opus 5.

| Layer | Setup C (OpusPlan) | Setup A (default, trial) | Setup B (Simple/One-Off) |
|-------|--------------------|---------------------------|----------------------------|
| Planner | Opus 5 `xhigh` (Plan Mode) | Opus 5 `high` (`medium` routine) | Sonnet 5 `medium`→`high`→`xhigh` |
| Driver | Sonnet 5 `medium` (execute mode) | Opus 5 `high` (`medium` routine) | Sonnet 5 `medium`→`high`→`xhigh` |
| Reviewer | GPT-5.6 Sol high | GPT-5.6 Sol high | GPT-5.6 Sol high |

**How to opt in:**
```json
{
  "model": "opusplan"
}
```

Set effort per-session with `/effort` (planner `xhigh`, driver `medium`, escalate `high`→`xhigh` only if the execution phase proves harder than expected) rather than a shell-rc env var — see "Recommended Effort Level" above for why. Pin `ANTHROPIC_DEFAULT_OPUS_MODEL: "claude-opus-4-8"` explicitly if you want Opus 4.8's field-proven planning behavior instead of Opus 5's.

**⚠️ Avoid `sonnet[1m]`** — Sonnet with 1M context draws from usage credits ($3/$15 per Mtok), not your Max subscription (#390). Plain `sonnet` (200K) or `opusplan` stays on Max.

**When to use OpusPlan (Setup C):** routine SDLC work, simple repos, cost-conscious sessions where you still want an Opus plan-mode pass. Press Shift+Tab before architecture/blast-radius decisions to get Opus reasoning. For most day-to-day work, Setup B (Sonnet 5 + Fable) is the simpler, lower-cost option — see "Choosing Your Model" in [README.md](../README.md).

**When to reach for Setup A (default, Opus 5):** genuine autonomous/agentic work on complex repos, architecture decisions, ambiguous debugging — Opus 5's extra capability at higher quota cost, not a split planner/driver.

**Prove-It Gate (#233 acceptance criterion):** mixed-mode ships only if pair-tested on 3+ simple repos shows Sonnet-coder + Opus-reviewer produces ≥ same SDLC scores as full-Opus baseline. The first version of the heuristic ships v1.38.0; pair-test results land in CHANGELOG before recommending mixed-mode as the default for any tier.

**Tradeoffs (be honest):**
- The Sonnet driver will drop some fine-grained self-review moves compared to an Opus-coder run — it's fast, less deliberate. The Opus planner and GPT-5.6 Sol reviewer catch them, but expect more "fix in round 2" cycles.
- Mixed-mode disables auto-mode (same as any pinned model). The pin is per-session — to switch back, remove the `model` line.

### Latest tier — Opus 4.8 (pinned escalation model, #395)

The wizard's default is **Opus 5** (Setup A, trial as of 2026-07-24 — see "Model Selection — The Evidence" in [AI_SETUP_LANES.md](../AI_SETUP_LANES.md) for the full evidence, including the accepted-risk framing). **Opus 4.8**, pinned explicitly (`claude-opus-4-8`), is the same-family-check escalation model: reach for it when the default driver stalls on architecture, a stuck bug, or anything needing a genuinely independent second pass — not as a daily driver. It ships SWE-Bench Pro / Terminal-Bench 2.1 gains, dynamic-workflows, and parallel-subagent-swarm features 4.6 doesn't have.

**When Opus 4.8 is the right call:**
- The driver is stuck (2+ failed attempts) and you want a fresh, deeper-reasoning pass
- You use dynamic workflows / parallel subagent swarms — introduced in 4.8, not available in 4.6
- You want Anthropic's newest benchmark wins (SWE-Bench Pro 69.2% vs 4.7's 64.3%, Terminal-Bench 2.1 74.6% vs 4.7's 66.1%) for a specific hard task
- You haven't hit 4.7/4.8 token burn / false-green / dropped-constraint regressions in your own work

**Tradeoffs (be honest):**
- **Documented 40-60× cache token jump** vs 4.7 at HIGH effort ([AI Weekly](https://aiweekly.co/alerts/claude-opus-48-thinking-burns-900k-tokens-per-turn) — up to 900K cache tokens per turn). Burns Max 5-hour limits 2-3× faster than 4.6 — this is exactly why it's an escalation model, not a daily driver
- Active GitHub regressions still open: false-greens ([#63861](https://github.com/anthropics/claude-code/issues/63861)), 2-3× token burn ([#64961](https://github.com/anthropics/claude-code/issues/64961)), 46K tokens for simple coding turn ([#64153](https://github.com/anthropics/claude-code/issues/64153)), dropped constraints ([#65932](https://github.com/anthropics/claude-code/issues/65932))
- [Tech.yahoo review](https://tech.yahoo.com/ai/claude/articles/claude-opus-4-8-review-130106963.html): "Anthropic deliberately made Opus's new tokenizer less efficient" — not a transient bug, structural pricing change
- Anthropic-supported until ≥ May 28, 2027 (longer runway than 4.6)

**How to opt in for a session (escalate, don't pin globally):**

`/model claude-opus-4-8` at the start of the session, then `/effort xhigh`. Reserve a global pin in `~/.claude/settings.json` for maintainers who've decided Opus 4.8 is their permanent driver, understanding the cost tradeoff above:
```json
{
  "model": "claude-opus-4-8"
}
```

On Max plans, Opus auto-upgrades to 1M context. No `[1m]` suffix needed.

**Effort tuning for 4.8:** `xhigh` (see the per-model effort table in "Recommended Effort Level" above — Opus 4.8 is escalation-only, so it doesn't get its own `max` tier the way Opus 4.6 does).

**Escape hatch:** remove the `model` line (or run `/model opus`) to return to Opus 5, the wizard's recommended default.

### Community Feature-Discovery Scanner (roadmap #207)

The weekly-update workflow watches Anthropic's official changelog + GitHub releases, but new CC slash-commands (e.g. a hypothetical `/insights`) often surface FIRST on Reddit, HN, or Discord weeks before they hit the changelog. `tests/e2e/scan-community.sh` ports the community-scan job out of CI (deleted per ROADMAP #231) into a maintainer-runnable script: pull transcripts manually, pipe through the scanner, triage the digest.

**What it does:** extracts every `/[a-z][a-z0-9-]*` mention (length ≥ 4) from input text, dedupes against `tests/e2e/known-slash-commands.txt`, and emits a JSON digest with each unknown slash-command's count and one sample line for context.

**Maintainer procedure:**

```bash
# 1. Capture transcripts. Save Reddit threads, HN comments, Discord exports,
#    or CC GH Discussions to plain-text files. The scanner doesn't care about
#    formatting — just the raw text.
mkdir -p /tmp/community-scan-$(date +%Y-%m-%d)
cd /tmp/community-scan-*
# (paste / curl content into reddit.txt, hn.txt, discord.txt, etc.)

# 2. Run the scanner. Multiple files are aggregated into one digest.
bash /path/to/sdlc-wizard/tests/e2e/scan-community.sh *.txt > digest.json

# 3. Triage. Anything in `candidates` is a slash-command the wizard's
#    allowlist doesn't recognize — could be a new CC native command, a
#    third-party plugin, or pure noise.
jq '.candidates' digest.json
```

**Output shape:**

```json
{
  "scan_date": "2026-04-24",
  "input_files": ["reddit.txt", "hn.txt"],
  "candidates": [
    { "slash": "/insights", "count": 3, "sample": "Did you all see /insights in CC 2.2..." },
    { "slash": "/newthing",  "count": 1, "sample": "I tried /newthing on a long session..." }
  ]
}
```

**Updating the allowlist:** when triage confirms a candidate is real and the wizard now accounts for it (either as a wizard skill or by documenting CC's native command), append it to `tests/e2e/known-slash-commands.txt` so the next scan stops surfacing it. The file is the single source of truth — no rebuild, no migration.

**Why offline + deterministic:** the previous CI-based scan-community job burned $2-5/run via claude-code-action calls and produced one merged community-pattern PR in 30 days (ROADMAP #231 Phase 1 audit). Replacing it with a local regex scan + maintainer triage gives the same signal at zero API cost; the original `.github/prompts/analyze-community.md` prompt still exists for the LLM-summarization layer if a maintainer wants narrative analysis on top.

**Regression test:** `tests/test-community-scanner.sh` covers detection of new commands, allowlist filtering (CC native + wizard skills), dedup + count behavior, empty-input edge case, JSON shape, stdin input, multi-file aggregation, sample-context inclusion, long-line sample window, case-insensitive extraction, and dash-leading filenames (14 tests). The fixtures under `tests/fixtures/community-scanner/` are seeded with `/newthing`, `/alpha`, `/beta`, `/gamma` mock mentions; if the scanner regresses the test fails on the missed slash.

---

### Verifying Prompt-Hook-Fires-Once (roadmap #224)

CC 2.1.118 shipped a fix for `prompt` hooks double-firing when an agent-hook verifier subagent itself made tool calls. The bug would manifest as duplicate `SDLC BASELINE` injections per `UserPromptSubmit` — context bloat plus possible confusion. The dual-channel (project + plugin) double-print is already handled by `dedupe_plugin_or_project` in v1.37.1; this section is the runtime check for the *CC-internal* double-fire case.

`hooks/sdlc-prompt-check.sh` ships an opt-in instrumentation: when the env var `SDLC_HOOK_FIRE_LOG` is set, every post-dedupe invocation appends one tab-separated record (`<unix-ts>\t<pid>\tsdlc-prompt-check`) to that log. Counting lines per prompt tells you whether CC fired the hook once or twice.

**Maintainer procedure (real session):**

```bash
# 1. Pick a fresh log path
export SDLC_HOOK_FIRE_LOG="$(mktemp /tmp/sdlc-fire-log.XXXXXX)"

# 2. Restart Claude Code so the env propagates into spawned hooks
#    (or set it in your shell rc / .envrc and start a fresh session)

# 3. Run a normal SDLC session — including any task that triggers a verifier
#    subagent (e.g., /code-review, /sdlc with multi-step planning)

# 4. After N user prompts, count log lines:
wc -l "$SDLC_HOOK_FIRE_LOG"
#    Expect: N lines. >N indicates the CC double-fire bug regressed.

# 5. Optional: tail the log live in another terminal to watch each fire:
tail -f "$SDLC_HOOK_FIRE_LOG"
```

The instrumentation is opt-in — when the env var is unset, no log is written and no overhead is added. Unwritable log paths fail silently so a bad `SDLC_HOOK_FIRE_LOG` value never crashes the hook.

**Regression test:** `tests/test-prompt-hook-fires-once.sh` covers the instrumentation contract (counter increments per invocation, opt-in semantics, log line shape, output stability, unwritable-path tolerance). It does *not* spawn Claude Code — that's a maintainer-runtime check by design. The test asserts the recording mechanism works so the maintainer's real-session count is trustworthy.

---

## Example Workflow (End-to-End)

Here's what a typical task looks like with this system:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ USER: "Add a password reset feature"                                    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ HOOK FIRES: SDLC baseline reminder + AUTO-INVOKE instruction            │
│ CLAUDE: Sees implementation task → invokes sdlc skill                   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 1: PLANNING                                                       │
│                                                                         │
│ Claude:                                                                 │
│ 1. Creates TodoWrite with SDLC steps                                   │
│ 2. Searches for relevant docs (auth docs, API docs, etc.)              │
│ 3. Checks doc health - flags if anything needs attention               │
│ 4. Researches codebase (existing auth patterns, DB schema)             │
│ 5. Presents approach:                                                   │
│                                                                         │
│    "My approach:                                                        │
│    - Add /reset-password endpoint                                       │
│    - Use existing email service                                         │
│    - Store tokens in users table                                        │
│                                                                         │
│    Confidence: MEDIUM                                                   │
│    Uncertainty: Not sure about token expiry - 1 hour or 24 hours?"     │
│                                                                         │
│ User: "Use 1 hour. Looks good."                                        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 2: TRANSITION                                                     │
│                                                                         │
│ Claude:                                                                 │
│ 1. Updates relevant docs with decisions/discoveries                    │
│ 2. "Docs updated. Ready for /compact before implementation?"           │
│                                                                         │
│ User: runs /compact                                                    │
│                                                                         │
│ (Context freed, plan preserved in summary)                             │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 3: IMPLEMENTATION (TDD)                                           │
│                                                                         │
│ Claude:                                                                 │
│ 1. TDD RED: Writes failing test for password reset                     │
│    - Test expects endpoint to exist, return success                    │
│    - Test FAILS (endpoint doesn't exist yet)                           │
│                                                                         │
│ 2. TDD GREEN: Implements password reset                                │
│    - Creates endpoint, email logic, token handling                     │
│    - Test PASSES                                                        │
│                                                                         │
│ 3. Runs lint/typecheck                                                 │
│ 4. Runs ALL tests - no regressions                                     │
│ 5. Production build check                                               │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 4: REVIEW                                                         │
│                                                                         │
│ Claude:                                                                 │
│ 1. DRY check - no duplicated logic                                     │
│ 2. Cross-model review (a DIFFERENT model checks the work)             │
│ 3. Security review (auth change = yes)                                 │
│    - ✅ Token properly hashed                                          │
│    - ✅ Rate limiting on endpoint                                       │
│    - ✅ No password in logs                                             │
│                                                                         │
│ 4. Presents summary:                                                    │
│    "Done. Added password reset with 1-hour tokens.                      │
│     3 files changed, tests passing, security reviewed.                  │
│     Ready for your review."                                             │
└─────────────────────────────────────────────────────────────────────────┘
```

This is what the system enforces automatically. Claude follows this workflow because:
- **Hooks** remind every prompt
- **Skills** provide detailed guidance when invoked
- **TodoWrite** makes progress visible
- **Confidence levels** prevent guessing
- **TDD** ensures correctness
- **Self-review** catches issues before you see them

---

## Recommended Documentation Structure

For Claude to be effective at SDLC enforcement, your project should have these docs:

| Document | Purpose | Claude Uses For |
|----------|---------|-----------------|
| **CLAUDE.md** | Claude-specific instructions | Commands, code style, project rules |
| **README.md** | Project overview | Understanding what the project does |
| **ARCHITECTURE.md** | System design, data flows, services | Understanding how components connect |
| **TESTING.md** | Testing philosophy, patterns, commands | TDD guidance, test organization |
| **SDLC.md** | Development workflow (this system) | Full SDLC reference |
| **ROADMAP.md** | Vision, goals, milestones, timeline | Understanding project direction |
| **CONTRIBUTING.md** | How to contribute, PR process | Guiding external contributors |
| **Feature docs** | Per-feature documentation | Context for specific changes |

**Why these matter:**
- **CLAUDE.md** - Claude reads this automatically every session. Put commands, style rules, architecture overview here.
- **ARCHITECTURE.md** - Claude needs to understand how your system fits together before making changes.
- **TESTING.md** - Claude needs to know your testing approach, what to mock, what not to mock.
- **ROADMAP.md** - Shows where the project is going. Helps Claude understand priorities and what's next.
- **CONTRIBUTING.md** - For open source projects, defines how contributions work. Claude follows these when suggesting changes.
- **Feature docs** - For complex features, Claude reads these during planning to understand context.

**Start simple, expand over time:**
1. Create CLAUDE.md with commands and basic architecture
2. Create TESTING.md with your testing approach
3. Add ARCHITECTURE.md when system grows complex
4. Add ROADMAP.md when you have clear milestones/vision
5. Add CONTRIBUTING.md if open source or team project
6. Add feature docs as major features emerge

---

## Step 0: Repository Protection & Plugin Setup

### Step 0.0: Enable Branch Protection (CRITICAL)

**Protect your main branch early — but not before CI can report.** This is non-negotiable for teams and highly recommended for solo developers.

> **Do this in order, whichever method you use below.** A required status check
> that has never reported blocks every merge — GitHub shows it as *Expected —
> waiting for status* — and *Do not allow bypassing the above settings*
> (`enforce_admins` in the API) removes the override that would let you merge
> anyway. Protect a repo that has no CI yet and you lock yourself out of your
> own `main`.
>
> 1. Add the workflow that produces `validate` and push it on a branch.
> 2. Open a PR and watch `validate` go green at least once, so you know the
>    check name exists and reports.
> 3. **Then** apply protection — UI or CLI, both below.

**Why this matters:**
- SDLC enforcement is only as strong as your merge protection
- Without branch protection, anyone (including Claude) can push broken code to main
- Built-in GitHub feature - deterministic, no custom code needed

**Solo Developer Settings:**

| Setting | Value | Why |
|---------|-------|-----|
| Require a pull request before merging | ✓ Enabled | All changes go through PR review |
| Require approvals | **0 (none)** | No one else to approve — CI is your gate |
| Require status checks to pass before merging | ✓ Enabled | CI must be green |
| Require branches to be up to date before merging | ✓ Enabled | No stale merges |
| Do not allow bypassing the above settings | **✓ Enabled** | Safe at 0 approvals — but set CI up first, see below |

**Team Settings (2+ developers):**

| Setting | Value | Why |
|---------|-------|-----|
| Require a pull request before merging | ✓ Enabled | All changes go through PR review |
| Require approvals | 1+ (your choice) | Human must approve before merge |
| Require status checks to pass before merging | ✓ Enabled | CI must be green |
| Require branches to be up to date before merging | ✓ Enabled | No stale merges |
| Do not allow bypassing the above settings | ✓ Enabled | No one bypasses the rules |

**How to enable (UI):**
1. Go to: `Settings > Branches > Add rule`
2. Branch name pattern: `main` (or `master`)
3. Enable the settings above (solo or team, as appropriate)
4. Add required status checks: `validate` (E2E is advisory — see note below)
5. Click **Create** (the `Add rule` flow ends in `Create`; `Save changes` is the edit flow)

> **Note (ROADMAP #212 Option 1, April 2026):** We no longer require `e2e-quick-check` as a blocking check. It burned Anthropic API credits on every PR, and branch protection pinned to GitHub Actions made local-maintainer check-run satisfaction impossible. E2E now runs advisory-only via `tests/e2e/local-shepherd.sh` on the maintainer's Max subscription. See `ROADMAP.md` #212 for the full rationale.

**How to enable (CLI — solo dev):** *(the ordering rule at the top of Step 0.0
applies — `validate` must have reported green once before you run this)*
```bash
gh api repos/OWNER/REPO/branches/main/protection --method PUT --input - << 'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["validate"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0
  },
  "restrictions": null
}
EOF
```

**Why `enforce_admins: true` for a solo dev.** The usual reason to leave it off
is that it locks the only admin out. That reason is about *approvals*: GitHub
refuses self-approval, so an admin with `required_approving_review_count: 1` and
nobody else around cannot merge anything. At **0** approvals that particular
trap is gone — what remains is a green `validate` and an up-to-date branch,
which you were waiting for anyway. It is still a real lock if the check cannot
report, which is what the ordering above is for.

**Why `required_approving_review_count: 0` and not `null`.** `null` does not
mean "a PR with no approvals" — it means **no pull request is required at
all**, which is a different and much weaker setting. The `0` form requires the
PR and asks nobody to approve it. This repo's own `main` still has `null`,
which is why a direct push to it is possible today — see the next paragraph and
#679.

**What this does NOT do, and the ordering matters:** if you leave
`required_pull_request_reviews` as `null`, admin enforcement does **not** stop a
direct push to `main`. A commit that already carries a green `validate` lands —
push a branch, let CI run, then push that same SHA to `main`. Check runs attach
to commits rather than branches. Only a *fresh* commit is rejected. Requiring
the pull request is what closes that, not `enforce_admins`.

**And a green `validate` is not a trustworthy signal on its own.** The check is
produced by a workflow file that lives in the repository, so a branch under
review can change what `validate` does — including making it pass. Branch
protection enforces that the check *reported success*; it cannot enforce what
the check measured. Treat protection as a floor, not as review.

**Changing one field later:** `PUT .../protection` **replaces the entire
protection object**, so re-running one of these recipes to adjust a single
setting silently drops everything absent from your payload — including any
`checks[].app_id` pin. To change one field, use its sub-endpoint:

```bash
gh api -X POST repos/OWNER/REPO/branches/main/protection/enforce_admins   # on
gh api -X DELETE repos/OWNER/REPO/branches/main/protection/enforce_admins # off
```

**How to enable (CLI — team):**
```bash
gh api repos/OWNER/REPO/branches/main/protection --method PUT --input - << 'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["validate"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "restrictions": null
}
EOF
```

**Optional (teams only):**

| Setting | Value | Why |
|---------|-------|-----|
| Require review from Code Owners | ✓ Enabled | Specific people must approve |

**CODEOWNERS file (teams only):**
Create `.github/CODEOWNERS`:
```
# Default owners for everything
* @your-username

# Or specific paths
/src/ @dev-team
/.github/ @platform-team
```

**The principle:** Built-in protection > custom enforcement. GitHub branch protection is battle-tested, always runs, and can't be accidentally bypassed.

**Why PRs even for solo devs?**

| Benefit | Solo Dev | Team |
|---------|----------|------|
| `/code-review` optional preflight | ✓ | ✓ |
| CI must pass before merge | ✓ | ✓ |
| Clean commit history | ✓ | ✓ |
| Easy rollback (revert PR) | ✓ | ✓ |
| Human review required | — | ✓ |

**Not required, but good practice.** The SDLC workflow's review step is cross-model; `/code-review` remains available as optional preflight input (native Claude Code plugin). It launches parallel review agents for CLAUDE.md compliance, bug detection, and logic/security checks. You always have final say — the review just catches things you might miss.

**Code review workflows:**

| Workflow | When to use | How |
|----------|------------|-----|
| **Solo** | Working alone | `/code-review` locally before push |
| **Team** | Multiple contributors | `/code-review` locally + CI PR review for visibility |
| **Open Source** | External contributors | CI PR review on contributor PRs |

**Solo devs:** Skip approval requirements — CI status checks are your quality gate. The AI code review (`pr-review.yml`) provides automated review without needing human approval. GitHub does not allow PR authors to approve their own PRs, so requiring approvals on a solo repo will block all merges.

---

### Step 0.1: Required Plugins

**Install required plugin:**
```bash
/plugin install claude-md-management@claude-plugin-directory
```
> "Installing claude-md-management (required for CLAUDE.md maintenance)..."

This plugin handles:
- CLAUDE.md quality audits (A-F scores, specific improvement suggestions)
- Session learning capture via `/revise-claude-md`

**Scope:** CLAUDE.md only. Does NOT update feature docs, TESTING.md, ARCHITECTURE.md, hooks, or skills. The SDLC workflow still handles those (see Post-Mortem section for where learnings go).

### Step 0.2: SDLC Core Setup (Wizard Creates)

The wizard creates TDD-specific automations that official plugins don't provide:
- TDD pre-tool-check hook (test-first enforcement)
- SDLC prompt-check hook (baseline reminders)
- SDLC skill with confidence levels
- Planning mode integration

### Step 0.3: Additional Recommendations (Optional)

After SDLC setup is complete, run `/claude-automation-recommender` for stack-specific tooling:

```
/claude-automation-recommender
```

**The wizard is an enforcement engine** — it installs working hooks, skills, and process guardrails that run automatically. **The recommender is a suggestion engine** — it analyzes your codebase and suggests additional automations you might want. They're complementary:

| Category | Wizard Ships | Recommender Suggests |
|----------|-------------|---------------------|
| SDLC process (TDD, planning, review) | Enforced via hooks + skills | Not covered |
| CI workflows (PR review) | Templates + docs | Not covered |
| MCP servers (context7, Playwright, DB) | Not covered | Per-stack suggestions |
| Auto-formatting hooks (Prettier, ESLint) | Not covered | Per-stack suggestions |
| Type-checking hooks (tsc, mypy) | Not covered | Per-stack suggestions |
| Subagent templates (code-reviewer, etc.) | Cross-model review only | 8 templates |
| Plugin recommendations (LSPs, etc.) | Not covered | Per-stack suggestions |

The recommender's suggestions are additive — they don't replace the wizard's TDD hooks or SDLC enforcement.

### Git Workflow Preference

**Claude asks:**
> "Do you use pull requests for code review? (y/n)"

- **Yes → PRs**: Recommend `code-review` plugin, PR workflow guidance
- **No → Solo/Feature branches**: Skip PR plugins, recommend feature branch workflow

Feature branches still recommended for solo devs (keeps main clean, easy rollback).

**If using PRs, also ask:**
> "Auto-clean old bot comments on new pushes? (y/n)"

- **Yes** → Add `int128/hide-comment-action` to CI (collapses outdated bot comments)
- **No** → Skip (some teams prefer full comment history)

**Recommendation:** Solo devs = yes (keeps PR tidy). Teams = ask (some want audit trail).

> "Run AI code review only after tests pass? (y/n)"

- **Yes** → PR review workflow waits for CI to pass first (saves API costs on broken code)
- **No** → Review runs immediately in parallel with tests (faster feedback)

**Recommendation:** Yes for most teams. No point reviewing code that doesn't build/pass tests. Saves Claude API costs and reviewer time.

> "What reasoning effort for the PR reviewer? (medium/high/max)"

| Level | Cost per Review | When to Use |
|-------|----------------|-------------|
| `medium` | ~$0.13-0.38 | Default, balanced cost/quality |
| `high` | ~$0.38-1.00 | Recommended — deeper reasoning catches more |
| `max` (Opus only) | $1.00+ | Unbounded thinking, highest quality, unpredictable cost |

**Recommendation:** `high` for most teams. The reviewer is your quality gate — deeper reasoning catches issues that `medium` misses. `max` is overkill for routine reviews but useful for security-critical or high-risk PRs.

**How to set it:** Add `--effort high` (or `medium`/`max`) to `claude_args` in your PR review workflow. You can change this anytime.

> "Use sticky PR comments or inline review comments for bot reviews? (sticky/inline)"

- **Sticky** → Bot reviews post as single PR comment that updates in place
- **Inline** → Bot creates GitHub review with inline comments on specific lines

**Recommendation:** Sticky for bots. Here's why:

| Approach | When to Use |
|----------|-------------|
| **Sticky PR comment** | Bots, automated reviews. Updates in place, stays clean. |
| **Inline review comments** | Humans. Threading on specific lines is valuable. |

**The problem with inline bot reviews:**
- Every push triggers new review → comments pile up
- GitHub's `hide-comment-action` only hides PR comments, not review comments
- PR becomes cluttered with dozens of outdated bot reviews

**Sticky comment workflow:**
1. Bot posts review as sticky PR comment (single comment, auto-updates)
2. User reads review, replies in PR comments if questions
3. User adds `needs-review` label to trigger re-review
4. Bot updates the SAME sticky comment (no pile-up)
5. Label auto-removed, ready for next round

**Back-and-forth:** User questions live in PR comments. Bot's response is always the latest sticky comment. Clean and organized.

**CI shepherd opt-in (only if CI detected during auto-scan):**
> "Enable CI shepherd role? Claude will actively watch CI, auto-fix failures, and iterate on review feedback. (y/n)"

- **Yes** → Enable full shepherd loop: CI fix loop + review feedback loop. Ask detail questions below
- **No** → Skip CI shepherd entirely (Claude still runs local tests, just doesn't interact with CI after pushing)

**What the CI shepherd does:**
1. **CI fix loop:** After pushing, Claude watches CI via `gh pr checks`, reads logs on **pass and fail** (`gh run view <RUN_ID> --log`, not just `--log-failed`), diagnoses and fixes failures, pushes again (max 2 attempts)
2. **Log review on pass:** Passing CI can still hide warnings, skipped steps, degraded scores, or silent test exclusions. A green checkmark is necessary but not sufficient — always read the logs
3. **Review feedback loop:** After CI passes and logs look clean, Claude reads automated review comments, implements valid suggestions, pushes and re-reviews — terminating on the cumulative stop rule (#539), not a fixed count
4. **Pre-release CI audit:** Before cutting any release, review CI runs across ALL PRs merged since last release. Look for warnings in passing runs, degraded scores, skipped suites. Use `gh run list` + `gh run view <ID> --log`

**Recommendation:** Yes if you have CI configured. The shepherd closes the loop between "local tests pass" and "PR is actually ready to merge."

**Requirements:**
- `gh` CLI installed and authenticated
- CI/CD configured (GitHub Actions, etc.)
- If no CI yet: skip, add later when you set up CI

**Stored in SDLC.md metadata as:**
```
<!-- CI Shepherd: enabled -->
```

**Detail questions (only if CI shepherd is enabled):**

**CI monitoring detail:**
> "Should Claude monitor CI checks after pushing and auto-diagnose failures? (y/n)"

- **Yes** → Enable CI feedback loop in SDLC skill, add `gh` CLI to `permissions.allow`
- **No** → Skip CI monitoring steps (Claude still runs local tests, just doesn't watch CI)

**CI review feedback question (only if CI monitoring is enabled):**
> "What level of automated review response do you want?"

| Level | Name | What the shepherd handles |
|-------|------|--------------------------|
| **L1** | `ci-only` | CI failures only (broken tests, lint) |
| **L2** | `criticals` (default) | + Critical review findings (must-fix) |
| **L3** | `all-findings` | + Every suggestion the reviewer flags |

**What this does:**
1. After CI passes, Claude reads the automated code review comments
2. Based on your level: fixes criticals only, or all findings
3. Iterates (push -> re-review) until no findings remain at your chosen level
4. Only brings you in when everything is clean
5. **Termination is the cumulative stop rule (#539), not a fixed count** — continue only while the last completed pass recorded an open in-card P0/P1, or the first evidence invalidation in this root task [bound: CANONICAL:evidence-exception-bound]. Counted per root task; re-freezing scope never resets it.

**Check for new plugins periodically:**
```
/plugin > Discover
```

**Re-run `claude-code-setup` periodically** (quarterly, or when your project expands in scope) to catch new automations — MCP servers, hooks, subagents — that weren't relevant at initial setup but are now.

### Step 0.4: Auto-Scan Your Project

**Before asking questions, Claude will automatically scan your project:**

Claude is language-agnostic and will discover your stack, not assume it:

```
Claude scans for:
├── Package managers (any language):
│   ├── package.json, package-lock.json, pnpm-lock.yaml  → Node.js
│   ├── Cargo.toml, Cargo.lock                           → Rust
│   ├── go.mod, go.sum                                   → Go
│   ├── pyproject.toml, requirements.txt, Pipfile        → Python
│   ├── Gemfile, Gemfile.lock                            → Ruby
│   ├── build.gradle, pom.xml                            → Java/Kotlin
│   └── ... (any package manifest)
│
├── Source directories: src/, app/, lib/, server/, pkg/, cmd/
├── Test directories: tests/, __tests__/, spec/, *_test.*, test_*.py
├── Test frameworks: detected from config files and test patterns
├── Lint/format tools: from config files
├── CI/CD: .github/workflows/, .gitlab-ci.yml, etc.
├── Feature docs: *_DOCS.md, docs/features/, docs/decisions/
├── README, CLAUDE.md, ARCHITECTURE.md
│
├── Deployment targets (for ARCHITECTURE.md environments):
│   ├── Dockerfile, docker-compose.yml    → Container deployment
│   ├── k8s/, kubernetes/, helm/          → Kubernetes
│   ├── vercel.json, .vercel/             → Vercel
│   ├── netlify.toml                      → Netlify
│   ├── fly.toml                          → Fly.io
│   ├── railway.json, railway.toml        → Railway
│   ├── render.yaml                       → Render
│   ├── Procfile                          → Heroku
│   ├── app.yaml, appengine/              → Google App Engine
│   ├── deploy.sh, deploy/                → Custom scripts
│   ├── .github/workflows/deploy*.yml     → GitHub Actions deploy
│   └── package.json scripts (deploy:*)   → npm deploy scripts
│
├── Tool permissions (for permissions.allow):
│   ├── package.json           → Bash(npm *), Bash(node *), Bash(npx *)
│   ├── pnpm-lock.yaml         → Bash(pnpm *)
│   ├── yarn.lock              → Bash(yarn *)
│   ├── go.mod                 → Bash(go *)
│   ├── Cargo.toml             → Bash(cargo *)
│   ├── pyproject.toml         → Bash(python *), Bash(pip *), Bash(pytest *)
│   ├── Gemfile                → Bash(ruby *), Bash(bundle *)
│   ├── Makefile               → Bash(make *)
│   ├── docker-compose.yml     → Bash(docker *)
│   └── .github/workflows/     → Bash(gh *)
│
├── Design system (for UI projects):
│   ├── tailwind.config.*      → Extract colors, fonts, spacing from theme
│   ├── CSS with --var-name    → Extract custom property palette
│   ├── .storybook/            → Reference as design source of truth
│   ├── MUI/Chakra theme files → Reference theming docs + overrides
│   └── /assets/, /images/     → Document asset locations
│
└── Project domain (for domain-adaptive TESTING.md):
    ├── Firmware/Embedded:
    │   ├── Makefile with flash/burn targets
    │   ├── .cfg device config files
    │   ├── /sys/ or /dev/tty references in scripts
    │   ├── .c/.h source files without web frameworks
    │   ├── platformio.ini, CMakeLists.txt
    │   └── No package.json with web frameworks
    ├── Data Science:
    │   ├── .ipynb notebook files
    │   ├── requirements.txt with pandas/sklearn/tensorflow/torch
    │   ├── data/ or datasets/ directory
    │   ├── models/ directory
    │   └── No Express/FastAPI/Rails web framework
    ├── CLI Tool:
    │   ├── package.json with "bin" field (no React/Vue/Angular deps)
    │   ├── bin/ directory with executable scripts
    │   ├── src/cli.* entry point
    │   └── No src/components/, no browser test config
    └── Web/API (default):
        └── Everything else — fallback when no other domain matches
```

**If Claude can't detect something, it asks.** Never assumes.

**Examples are just examples.** The patterns above show common conventions - Claude will discover YOUR actual patterns.

**Shared vs isolated environments:** Not everyone runs in isolated local dev. Some teams share databases, staging servers, or have infrastructure already running. Claude should ask about your setup - don't assume isolated environments.

**Claude then presents findings:**
```
📊 Project Scan Results:

Detected:
- Language: TypeScript (tsconfig.json found)
- Source: src/
- Tests: tests/ (Jest, 47 test files)
- Lint: ESLint (.eslintrc.js)
- Build: npm run build

Feature Docs:
- Found: AUTH_PLAN.md, PAYMENTS_PLAN.md, API_PLAN.md
- Pattern detected: *_PLAN.md (3 files)

Testing Analysis:
- 80% unit tests, 20% integration tests
- Heavy mocking detected (jest.mock in 35 files)

Recommendation: Your current tests rely heavily on mocks.
   For AI agents, Testing Diamond (integration-heavy) works better.
   Mocks can "pass" while production fails.

🔧 Tool Permissions (detected from stack):
   Based on your stack, these tools would be useful:
   - Bash(npm *)    ← package.json detected
   - Bash(node *)   ← Node.js project
   - Bash(npx *)    ← npm scripts
   - Bash(gh *)     ← .github/workflows/ detected

   Always included: Read, Edit, Write, Glob, Grep, Task

   Options:
   [1] Accept suggested permissions (recommended)
   [2] Customize permissions
   [3] Skip - I'll manage permissions manually

🎨 Design System (UI detected):
   Found: tailwind.config.js, components/ui/

   Extracted:
   - Colors: primary (#3B82F6), secondary (#10B981), ...
   - Fonts: Inter (body), Fira Code (mono)
   - Breakpoints: sm (640px), md (768px), lg (1024px)

   Options:
   [1] Generate DESIGN_SYSTEM.md from detected config
   [2] Point to external design system (Figma, Storybook URL)
   [3] Skip - no UI work expected in this project

🚀 Deployment Targets (auto-detected):
   Found: vercel.json, .github/workflows/deploy.yml

   Detected environments:
   - Preview: vercel (auto on PR)
   - Production: vercel --prod (manual trigger)

   Options:
   [1] Accept detected deployment config (will populate ARCHITECTURE.md)
   [2] Let me specify deployment targets manually
   [3] Skip - no deployment from this project

📝 Feature Doc Suffix:
   Current pattern: *_PLAN.md
   Recommended: *_DOCS.md (clearer for living documents)

   Options:
   [1] Keep *_PLAN.md (don't rename existing files)
   [2] Use *_DOCS.md for NEW docs only (existing stay as-is)
   [3] Rename all to *_DOCS.md (will rename 3 files)
   [4] Custom suffix: ____________

📄 Feature Doc Structure:
   Your docs don't follow our recommended structure.

   Your current structure:
   - AUTH_PLAN.md: Free-form notes, no sections
   - PAYMENTS_PLAN.md: Has "TODO" and "Notes" sections

   Our recommended structure:
   - Overview, Architecture, Gotchas, Future Work

   Options:
   [1] Migrate content into new structure (Claude reorganizes)
   [2] Create new docs with our structure, archive old ones to /docs/archived/
   [3] Keep current structure (just be consistent going forward)

[Accept Recommendations] or [Customize]
```

**If Claude can't detect something, THEN it asks.**

---

## Step 1: Build Confidence Map and Fill Gaps

Claude assigns a state to each configuration data point based on scan results. **RESOLVED (detected)** items are presented for bulk confirmation. **RESOLVED (inferred)** items are presented with inferred values for the user to verify. **UNRESOLVED** items become questions. **The number of questions is dynamic — it depends on how much the scan resolves.** Stop asking when ALL data points are resolved (detected, inferred+confirmed, or answered by user).

Claude presents what it found, organized by resolution state:

### Project Structure (Auto-Detected)

**Source directory:** `src/` ✓ detected
```
Override? (leave blank to accept): _______________
```

**Test directory** (detect from tests/, __tests__/, spec/, test file patterns)
```
Examples: tests/, __tests__/, src/**/*.test.ts, spec/
Your answer: _______________
```

**Test framework** (detect from jest.config, vitest.config, pytest.ini, etc.)
```
Options: Jest, Vitest, Playwright, Cypress, pytest, Go testing, other
Your answer: _______________
```

### Commands

**Lint command** (detect from package.json scripts, Makefile, config files)
```
Examples: npm run lint, pnpm lint, eslint ., biome check
Your answer: _______________
```

**Type-check command** (detect from tsconfig.json, mypy.ini, etc.)
```
Examples: npm run typecheck, tsc --noEmit, mypy, none
Your answer: _______________
```

**Run all tests command** (detect from package.json "test" script, Makefile)
```
Examples: npm run test, pnpm test, pytest, go test ./...
Your answer: _______________
```

**Run single test file command** (infer from framework: jest → jest path, pytest → pytest path)
```
Examples: npm run test -- path/to/test.ts, pytest path/to/test.py
Your answer: _______________
```

**Production build command** (detect from package.json "build" script, Makefile)
```
Examples: npm run build, pnpm build, go build, cargo build
Your answer: _______________
```

### Deployment

**Deployment setup** (auto-detected from Dockerfile, vercel.json, fly.toml, deploy scripts)
```
Detected: [e.g., Vercel, GitHub Actions, Docker, none]

Environments (will populate ARCHITECTURE.md):
┌─────────────┬──────────────────────┬────────────────────────┐
│ Environment │ Trigger              │ Deploy Command         │
├─────────────┼──────────────────────┼────────────────────────┤
│ Preview     │ Auto on PR           │ vercel                 │
│ Staging     │ Push to staging      │ [your staging deploy]  │
│ Production  │ Manual / push main   │ vercel --prod          │
└─────────────┴──────────────────────┴────────────────────────┘

Options:
[1] Accept detected config (recommended)
[2] Customize environments
[3] No deployment config needed

Your answer: _______________
```

### Infrastructure

**Database(s)** (detect from prisma/, .env DB vars, docker-compose services)
```
Examples: PostgreSQL, MySQL, SQLite, MongoDB, none
Your answer: _______________
```

**Caching layer** (detect from .env REDIS vars, docker-compose redis service)
```
Examples: Redis, Memcached, none
Your answer: _______________
```

**Test duration** (estimate from test file count, CI run times if available)
```
Examples: <1 minute, 1-5 minutes, 5+ minutes
Your answer: _______________
```

### Output Preferences

**Response detail level** (cannot detect — always ask if no preference found)
```
Options:
- Small   - Minimal output, just essentials (experienced users)
- Medium  - Balanced detail (default, recommended)
- Large   - Verbose output, full explanations (learning/debugging)
Your answer: _______________
```

This setting affects:
- TodoWrite verbosity (brief vs detailed task descriptions)
- Planning output (summary vs comprehensive breakdown)
- Self-review comments (concise vs thorough)

Stored in `.claude/settings.json` as `"verbosity": "small|medium|large"`.

#### Response length on Opus 5 — state it once, in CLAUDE.md

Opus 5's user-facing responses run longer than prior Opus models by default, and
**effort does not control this**. Anthropic's guide is explicit: effort governs how
much the model *thinks*, not how much it *says* — "lowering effort can reduce
thinking volume without reliably shortening the visible response. To control
response length, prompt for it explicitly."

Put one instruction in your root `CLAUDE.md`. Something like:

```
Lead with the outcome. Your first sentence should answer "what happened" or
"what did you find" — the thing someone would ask for if they said "just give
me the TLDR". Supporting detail comes after. Keep responses focused; spend most
of the response on the main answer, not caveats.
```

**Put it at CLAUDE.md level, not in skills or hook output.** Two different
things, stated separately so neither is overclaimed:

- **Anthropic's guidance** is that a short conciseness instruction works, and
  that *in a long system prompt* you may pair it with a brief reminder near the
  end (`<tone_preference>Keep outputs reasonably concise.</tone_preference>`).
  So a single reminder is endorsed, not discouraged.
- **This repo additionally bans brevity caps in `SKILL.md` and hook stdout**,
  enforced by CI. That is a narrower claim about a different situation: those
  surfaces are injected repeatedly across many turns and many components, which
  is not the same as one reminder in one system prompt. The evidence behind it
  is a repo-local postmortem on Opus 4.6/4.7 where a strict length-limit prompt
  contributed to degraded output — it does not establish a general Opus 5
  repetition effect, and should not be cited as if it does.

Separately, files Claude *writes* to disk (reports, summaries) also run long. If
your workflow produces documents, add: "Match the length of written documents to
what the task needs — cover the substance, don't pad with filler sections,
redundant summaries, or boilerplate."

### Testing Philosophy

**Testing approach** (infer from existing test patterns — test-first files, coverage config)
```
Options:
- Strict TDD (test first wherever a RED mutation is writable)
- Test-after (write tests after implementation)
- Mixed (depends on the feature)
- Minimal (just critical paths)
- None yet (want to start)
Your answer: _______________
```

**Test types** (detect from existing test file patterns: *.test.*, *.spec.*, e2e/, integration/)
```
(Check all that apply)
[ ] Unit tests (pure logic, isolated)
[ ] Integration tests (real DB, real services)
[ ] E2E tests (Playwright, Cypress, etc.)
[ ] API tests (endpoint testing)
[ ] Other: _______________
```

**Mocking philosophy** (detect from jest.mock, unittest.mock usage patterns)
```
Options:
- Minimal mocking (real DB, mock external APIs only)
- Heavy mocking (mock most dependencies)
- No mocking (everything real, even external)
- Not sure yet
Your answer: _______________
```

### Code Coverage (Optional)

**If test framework detected (Jest, pytest, Go, etc.):**

```
Code Coverage (Optional)

Detected: [test framework] with coverage configuration

Traditional Coverage:
[1] Enforce threshold in CI (e.g., 80%) - Fail build if coverage drops
[2] Report but don't enforce - Track coverage without blocking
[3] Skip traditional coverage

AI Coverage Suggestions:
[4] Enable AI-suggested coverage gaps in PR reviews
    (Claude notes: "You changed X but didn't add tests for edge case Y")
[5] Skip AI suggestions

(You can choose one from each group, or skip both)
Your answer: _______________
```

**If no test framework detected (docs/AI-heavy project):**

```
Code Coverage (Optional)

No test framework detected (documentation/AI-heavy project).

Options:
[1] AI-suggested coverage gaps in PR reviews (Recommended)
    (Claude notes when changes affect behavior but lack test scenarios)
[2] Skip - not needed for this project

Your answer: _______________
```

**How they work:**
- **Traditional coverage:** Deterministic line/branch/function percentages via nyc, c8, coverage.py, etc.
- **AI coverage suggestions:** Claude analyzes changes and suggests missing test cases based on context

**Not mutually exclusive:** Both can be used together for comprehensive coverage awareness.

---

### How Configuration Data Points Map to Files

Each resolved data point (whether detected or confirmed by the user) maps to generated files:

| Data Point | Used In |
|-----------|---------|
| Source directory | `tdd-pretool-check.sh` - pattern match |
| Test directory | `TESTING.md` - documentation |
| Test framework | `TESTING.md` - documentation |
| Commands (lint, typecheck, test, build) | `CLAUDE.md` - Commands section |
| Infrastructure (DB, cache) | `CLAUDE.md` - Architecture section, `TESTING.md` - mock decisions |
| Test duration | `SDLC skill` - wait time note |
| Test types (E2E) | `TESTING.md` - testing diamond top |
| Project domain (firmware/data-science/CLI/web) | `TESTING.md` - domain-adaptive testing layers and mocking rules |

---

## Step 2: Create Directory Structure

Create these directories in your project root:

```bash
mkdir -p .claude/hooks
mkdir -p .claude/skills/sdlc
```

**Commit to Git:** Yes! These files should be committed so your whole team gets the same SDLC enforcement. When teammates pull, they get the hooks and skills automatically.

Your structure should look like:
```
your-project/
├── .claude/
│   ├── hooks/
│   │   ├── sdlc-prompt-check.sh    (we'll create)
│   │   └── tdd-pretool-check.sh    (we'll create)
│   ├── skills/
│   │   ├── sdlc/
│   │   │   └── SKILL.md            (we'll create)
│   │   └── testing/
│   │       └── SKILL.md            (we'll create)
│   └── settings.json               (we'll create)
├── CLAUDE.md                       (we'll create)
├── SDLC.md                         (we'll create)
└── TESTING.md                      (we'll create)
```

---

## Step 3: Create settings.json

Create `.claude/settings.json`:

```json
{
  "verbosity": "medium",
  "permissions": {
    "allow": [
      "Read",
      "Edit",
      "Write",
      "Glob",
      "Grep",
      "Task",
      "Bash(npm *)",
      "Bash(node *)",
      "Bash(npx *)",
      "Bash(gh *)"
    ]
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/sdlc-prompt-check.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "if": "Write(src/**) Edit(src/**) MultiEdit(src/**)",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/tdd-pretool-check.sh"
          }
        ]
      }
    ]
  }
}
```

### Allowed Tools (Adaptive)

The `permissions.allow` array is auto-generated based on your stack detected in Step 0.4. (Historical note: pre-#197 guidance used a top-level `allowedTools` array — that form silently disables Claude Code auto-mode, so the wizard writes `permissions.allow` now.)

| If Detected | Tools Added |
|-------------|-------------|
| `package.json` | `Bash(npm *)`, `Bash(node *)`, `Bash(npx *)` |
| `pnpm-lock.yaml` | `Bash(pnpm *)` |
| `yarn.lock` | `Bash(yarn *)` |
| `go.mod` | `Bash(go *)` |
| `Cargo.toml` | `Bash(cargo *)` |
| `pyproject.toml` | `Bash(python *)`, `Bash(pip *)`, `Bash(pytest *)` |
| `Gemfile` | `Bash(ruby *)`, `Bash(bundle *)` |
| `Makefile` | `Bash(make *)` |
| `docker-compose.yml` | `Bash(docker *)` |
| `.github/workflows/` | `Bash(gh *)` |

**CI monitoring commands** (covered by `Bash(gh *)` above):
- `gh pr checks` / `gh pr checks --watch` - watch CI status
- `gh run view <RUN_ID> --log-failed` - read failure logs
- `gh run list` - find workflow runs

**Always included:** `Read`, `Edit`, `Write`, `Glob`, `Grep`, `Task`

**Why this matters:** Explicitly listing allowed tools:
- Prevents unexpected tool usage
- Makes permissions visible and auditable
- Reduces prompts for approval during work

### Verbosity Levels

| Level | Output Style |
|-------|--------------|
| `small` | Brief, minimal output. Task names are short. Less explanation. |
| `medium` | Balanced (default). Clear explanations without excessive detail. |
| `large` | Verbose. Full reasoning, detailed breakdowns. Good for learning. |

### Why These Hooks?

| Hook | When It Fires | Purpose |
|------|---------------|---------|
| `UserPromptSubmit` | Every message you send | Baseline SDLC reminder, skill auto-invoke |
| `PreToolUse` | Before Claude edits files | TDD check: "Did you write the test first?" Uses `if` field to only fire on source files |
| `InstructionsLoaded` | On first SDLC.md/CLAUDE.md load | Staleness nudges (wizard version, review-protocol reminders, CC release alerts) |
| `SessionStart` | On `claude` startup | Detect stale effort setting / model upgrades |
| `PreCompact` (manual only) | When user runs `/compact` | **Seam gate** — blocks manual compact when `.reviews/handoff.json` is `PENDING_REVIEW`/`PENDING_RECHECK` or a git rebase/merge/cherry-pick is in progress. Auto-compact is NOT gated (blocking it risks pushing past 100% context and losing everything). Requires Claude Code v2.1.105+ |

### How Skill Auto-Invoke Works

The light hook outputs text that **instructs Claude** to invoke skills:

```
AUTO-INVOKE SKILL (Claude MUST do this FIRST):
- implement/fix/refactor/feature/bug/build/test/TDD/release/publish/deploy → Invoke: Skill tool, skill="sdlc"
```

**This is text-based, not programmatic.** Claude reads this instruction and follows it. When Claude sees your message is an implementation task, it invokes the sdlc skill using the Skill tool. This loads the full SDLC guidance into context.

**Why text-based works:** Claude Code's hook system allows hooks to add context that Claude reads. Claude is instructed to follow the AUTO-INVOKE rules, and it does. The skills then load detailed guidance only when needed.

### Why No PostToolUse Hook?

**PostToolUse fires after EVERY individual edit.** If Claude makes 10 edits, it fires 10 times.

Running lint/typecheck after every edit is wasteful. Instead, lint/typecheck is a checklist step in the SDLC skill - run once after all edits, before tests.

---

## Step 4: Create the Light Hook

Create `.claude/hooks/sdlc-prompt-check.sh`:

```bash
#!/bin/bash
# Light SDLC hook - baseline reminder every prompt (~100 tokens)
# Full guidance in skill: .claude/skills/sdlc/

cat << 'EOF'
SDLC BASELINE:
1. Task list FIRST (TodoWrite or TaskCreate) (plan tasks before coding)
2. STATE CONFIDENCE: HIGH/MEDIUM/LOW
3. LOW confidence or FAILED 2x? Ladder: Fable -> Codex high -> human LAST
4. Never ask what a model can settle; confidence is not authorization
5. 🛑 ALL TESTS MUST PASS BEFORE COMMIT - NO EXCEPTIONS

AUTO-INVOKE SKILL (Claude MUST do this FIRST):
- implement/fix/refactor/feature/bug/build/test/TDD/release/publish/deploy → Invoke: Skill tool, skill="sdlc"
- DON'T invoke for: questions, explanations, reading/exploring code, simple queries
- DON'T wait for user to type /sdlc - AUTO-INVOKE based on task type

Workflow phases:
1. Plan Mode (research) → Present approach + confidence
2. Transition (update docs) → Request /compact
3. Implementation (TDD after compact)

Quick refs: SDLC.md | TESTING.md | *_DOCS.md for feature
EOF
```

**Make it executable:**
```bash
chmod +x .claude/hooks/sdlc-prompt-check.sh
```

---

## Step 5: Create the TDD Hook

**Illustrative, not exhaustive:** this teaches the PreToolUse/exit-2 blocking mechanic with one hook. The wizard ships **8 production hooks total** — only this one and Step 4's light hook have hand-typed templates in this doc; the other 6 (`codex-gate-check.sh`, `instructions-loaded-check.sh`, `model-effort-check.sh`, `precompact-seam-check.sh`, `codex-review-stop-check.sh`, `token-spike-check.sh`) don't, because there's no substitute for the real files. **For the complete, always-in-sync set, run `npx agentic-sdlc-wizard@latest init`** instead of hand-building hooks 3-8 from prose descriptions elsewhere in this doc.

Create `.claude/hooks/tdd-pretool-check.sh`:

```bash
#!/bin/bash
# PreToolUse hook - TDD enforcement before editing source files
# Fires before Write/Edit/MultiEdit tools

# Read the tool input (JSON with file_path, content, etc.)
TOOL_INPUT=$(cat)

# Extract the file path being edited (requires jq)
FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.tool_input.file_path // empty')
MARKER="$CLAUDE_PROJECT_DIR/.claude/.tdd-test-touched"

# A test file was touched — mark it and allow.
if [[ "$FILE_PATH" =~ (\.test\.|\.spec\.|/__tests__/|/tests?/) ]]; then
  touch "$MARKER" 2>/dev/null
  exit 0
fi

# CUSTOMIZE: Change this pattern to match YOUR source directory
# Examples: "/src/", "/app/", "/lib/", "/packages/", "/server/"
# Match BOTH absolute (*/src/*) and cwd-relative (src/*) forms — a
# leading-slash-only pattern silently no-ops on relative file_paths
# like "src/app.js" (Codex finding, #436 round 1).
if [[ "$FILE_PATH" == *"/src/"* || "$FILE_PATH" == "src/"* ]]; then
  if [ ! -f "$MARKER" ]; then
    # exit 2 + stderr = BLOCK. Claude Code only denies a tool call on exit 2
    # with stderr output — exit 0 always allows regardless of stdout content.
    echo "TDD RED REQUIRED: no test file touched yet. Write a failing test before implementing in src/." >&2
    exit 2
  fi
fi

# No output = allow the tool to proceed
```

**CUSTOMIZE:**
1. Replace `"/src/"` / `"src/"` with your source directory pattern (both forms — see comment above)
2. Ensure `jq` is installed (or adapt to your preferred JSON parser)
3. This minimal version tracks "a test was touched" with one marker file for the whole project, so once unlocked it stays unlocked. The wizard's actual shipped `hooks/tdd-pretool-check.sh` (in this repo) is session-scoped instead (resets each Claude Code session) and avoids `jq` for session-ID parsing — a plain `jq`-based extraction silently disabled this exact gate once when `jq` was missing (#436 round 1). Copy that file directly for the production-hardened version instead of hand-typing this one.

**Make it executable:**
```bash
chmod +x .claude/hooks/tdd-pretool-check.sh
```

**Alternative implementations:** You can write this hook in any language. The hook receives JSON on stdin and outputs JSON. See Claude Code docs for hook input/output format.

---

## Step 6: Install the SDLC Skill

Run the installer. It writes `.claude/skills/sdlc/SKILL.md` for you:

```bash
npx -y agentic-sdlc-wizard@latest init
```

**Do not hand-copy a skill out of this document.** Earlier revisions embedded a
640-line copy of the skill here, and it diverged from the installed file until the
two shared only five section topics — 56,284 bytes against the real skill's 19,356,
moving in opposite directions inside single PRs. One skill, one source: the CLI is
canonical, and `skills/sdlc/SKILL.md` ships in the same npm package as this document,
so the real file is already sitting next to these instructions. Read it there (GH #513).

Policy that used to live only inside that block is now stated at document level under
**Merging, CI and Release Policy** below.

## Confidence Check (REQUIRED)

Before presenting approach, STATE your confidence:

| Level | Meaning | Action | Effort |
|-------|---------|--------|--------|
| HIGH (90%+) | Know exactly what to do | Present approach, proceed after approval | Model default |
| MEDIUM (60-89%) | Solid approach, some uncertainty | Present approach, highlight uncertainties | Model default |
| LOW (<60%) | Not sure | Run the **Escalation Ladder** below | **Escalate effort now** — don't wait |
| FAILED 2x | Something's wrong | Run the **Escalation Ladder** below | **Escalate effort now** — you're burning cycles at lower effort |
| CONFUSED | Can't diagnose why something is failing | Run the **Escalation Ladder** below | **Escalate effort now** — stop spinning |

"Model default" and "escalate" are model-aware, not a blanket `max` — see "Recommended Effort Level" above for the per-model table (Opus 5: `high`, `medium` for routine work, `xhigh` only as an escalation; Sonnet 5: `medium`→`high`→`xhigh`; Opus 4.8: `xhigh`; Opus 4.6: `max`; Fable: `high`).

**Dynamic bumping is NOT optional.** "Consider higher effort" is the same as "ignore this" in practice. If your confidence drops or tests fail twice, bump effort BEFORE the next attempt — spinning at low effort is an SDLC failure mode.

### Escalation Ladder — the human is the LAST rung

Low confidence does **not** mean "ask the user." It means "escalate," and the user is the third rung, not the first. Ask a human only for what no model can settle.

1. **Fable — the primary thinker, not a rung you escalate to.** Fable **decides** design, priority and sequencing; you implement its call. You are the coder. Reach for it *before* an approach exists, via `advisor()`, or a Fable subagent at `high` while the advisor is server-side disabled. **The tell that you got this backwards:** you have already chosen an approach and are asking Fable to grade it. Prompt it to decide — "where you would normally say consider X, say do X" — rather than to critique. Codex is a different job entirely: the **adversarial check** that tries to break a decision already made, run before commit or merge. Fable thinks, Codex attacks; do not collapse them into "get a second opinion".

   **The loop, in order.** Fable decides the approach → Opus implements it → **Fable reviews the implementation** → only once that is clean, Codex runs as the final cross-model check. Fable appears twice on purpose: once as the brain before code exists, once as the reviewer of what got built. Codex is last and singular — it is the adversarial gate, not a second opinion to average with the first. Sending work to Codex before Fable has reviewed it wastes the expensive check on defects the cheaper one would have caught.

   **Open question, not yet settled:** this topology runs Opus as the driver calling out to Fable. The inverse — Fable as driver, delegating implementation to Opus subagents — has not been tested and may be better, since it puts the stronger reasoner in the seat that makes decisions continuously rather than on request. Do not assume the current arrangement is optimal; it is the one that has been used, not the one that has been measured.
2. **Codex `high`** — when Fable can't close the gap, or when a second, adversarially-framed opinion is what's needed.
3. **The human** — priority, risk appetite, scope, spend, or anything irreversible or outward-facing. A merge gate that demands explicit confirmation *is* this rung, invoked by design rather than by uncertainty.

**A standing instruction stays in force until it is withdrawn.** Once the human has ruled — "fix findings yourself", "don't ask before X", "stop checking in each round" — re-asking is not caution. It hands back a decision they already made, and it costs them the same interruption twice. Treat "you may proceed without asking" as durable, not as permission for one turn.

**When two of the human's own instructions appear to conflict, resolve it yourself.** This is the failure mode that actually occurs, and it is subtle because it *feels* conscientious. Observed here 2026-07-29: a maintainer said both "don't add process mass without justification" and "stop asking permission." Faced with a documentation change, the agent read those as contradictory and asked — violating the second instruction in the name of honouring the first. They were never in conflict: one sets a *bar to apply*, the other says *who applies it*. Apply the bar, act, and report what you decided and why. If you are genuinely wrong the human corrects one action, which is cheaper than being asked to arbitrate every time.

**The tell:** you are drafting a question whose answer you could defend either way. That is not a decision needing an owner — it is a judgement call you are declining to make. Make it, state the reasoning, and continue.


**Diagnose the gap before escalating — the two causes need opposite responses:**

| Cause | Looks like | Do |
|---|---|---|
| **Information-limited** | "I haven't looked that up yet" | Go look. A review round is wasted on what a file read or a doc fetch settles. |
| **Evidence-limited** | "I looked; the sources genuinely underdetermine this" | Escalate. More effort from the *same* model cannot move it. |

**The skipped-rung tell:** presenting the user with options while you already hold a lean means you skipped a rung. Act on the lean, or send it up to the next reviewer — don't outsource a model-answerable decision upward.

**Act-don't-ask threshold.** When Fable ≥95% or Codex ≥95% (require **both** for policy-, release-, or consumer-adjacent changes, scaled to the change's complexity), proceed and report afterward instead of asking. Below that, or when the two reviewers disagree, keep escalating rather than defaulting to a question.

> **Scope — confidence is not authorization.** This threshold applies **only** to decisions that are model-answerable, already authorized, and reversible. It **never** overrides an approval gate: human sign-off, anything with external effect (publishing, sending, posting), production deploys, deletions, new architectural patterns, releases, or policy changes. **Merge protections are non-overridable** — `gh pr merge --auto` stays banned unconditionally, and a merge gate demanding explicit confirmation is the human rung by design, not a low-confidence signal to be cleared by a high score. A model can be entirely confident about *how* to do something irreversible while having no idea whether it *should* — that judgement is the user's, and no confidence number substitutes for it.

**Form your own view from both.** Two reviewers agreeing is not automatic truth — especially when they saw overlapping evidence. Where they diverge is the signal; check which side the primary sources actually support, and say so.

**Honesty rule.** If you fix a reviewer's finding and choose to skip the confirming round, state that plainly. An unconfirmed fix is not a certification, and reporting it as one is exactly the false-green this protocol exists to prevent. Skipping a round can be the right call — silently implying it happened is not.

## Merging, CI and Release Policy

This is reader-facing policy for the human running the harness. The agent-facing
version ships as `skills/sdlc/SKILL.md` — installed by `npx agentic-sdlc-wizard init`,
not by hand-copying from this document (GH #513).

### Explicit Merge Confirmation — and a Narrow, Conditional Exception

**The default: explicit `gh pr merge --squash` always needs the user's confirmation, every PR.** `gh pr merge --auto` (GitHub's own auto-merge-on-green feature) stays permanently, unconditionally banned regardless of anything below — it fires before review feedback can even be read (PR #145 incident: auto-merged unreviewed, shipped a P1 bug).

**A narrow, conditional exception (2026-07-21)** lets an agent skip that one confirmation click — never the ban above — ONLY if ALL hold: CI's `validate` check is green (verified, not inferred); Codex `high` reached CERTIFIED via a full adversarial dialogue (not a round-1 rubber stamp); a **fresh, diff-only reviewer subagent** (no prior session context) independently found **zero unresolved findings after at least one dialogue round**; and, where the PR touches the **merge-evidence chain** — CI/release workflows, hooks, agent-config directories, or the merge wrapper itself — the higher bar below is met. Those paths are singled out because a PR editing them defines its own CI check, runs its own gate, and posts its own review evidence, so every leg of the evidence stack becomes self-produced at once. Note branch protection matches a required check by NAME, so *any* new workflow file can mint a green one.

**Dual cross-model certification IS merge authorization, including on the merge-evidence chain (2026-08-08).** Two models that did not write the code, run blind to each other, each able to refuse, is a different evidence class from self-review — so when both reviewers agree the merge proceeds, and the human is the **deadlock-breaker**, not the per-PR approver. This matters for the audit trail as much as for speed: where the only way to say yes was a human-override flag, every such merge recorded a per-PR human decision for what was really one standing policy decision, and an override record that misattributes its own authority is worse than no record. On the merge-evidence chain the bar adds two conditions: the gate that runs must be the **merged** one — byte-identical to the default branch, not this PR's edited copy, or the PR is judged by its own edits — and the review-dialogue evidence stays **required rather than waived**, so a round-1 rubber stamp does not clear it. Three things dual agreement never clears: a red CI check, net-removed test files, and a package-version bump (releases stay human). And state the residual plainly rather than implying it away: both clearances are typically posted by the same token, so this is **attested, not authenticated**, and a new workflow file minting a green required check is a hole nothing local can close — the compensating layer is that both reviewers read that file in the diff. Policy prose that steers behaviour but does not decide whether the current PR may merge (the SDLC policy document, the SDLC skill) may instead be cleared by posted, SHA-bound cross-model evidence. A package-version bump always needs confirmation. **This distinction is not a security boundary** — a local gate never is against a determined agent — it bounds the blast radius of an honest agent that has degraded: a bad docs merge ships one bad doc, a bad control-plane merge silently degrades every later merge's evidence, including the check that would have caught it. Even when it fires, the agent must tell the user immediately afterward what merged and why — this is "skip the click," never a silent merge.

**Be honest with yourself about what's actually enforced.** Some of this repo's own conditions are mechanically verified by local tooling — but that tooling is intentionally repo-local and does **not** ship as part of the wizard install. If you want the same fail-closed guarantee rather than self-certified prose, build the equivalent for your own repo: a wrapper script that independently re-checks CI status against the PR's remote head SHA, scans the diff against your own denylist (including the wrapper and any gate hook themselves — a PR editing the merge policy must not be able to exempt itself from it), and binds the merge atomically to that SHA (e.g. `gh pr merge --match-head-commit <sha>`) to close the race between checking and merging. Absent that, treat every condition above as something your own agent must reason about and self-report against, not something guaranteed.

### CI Feedback Loop — Local Shepherd (After Commit)

**This is the "local shepherd" — your CI fix mechanism.** It runs in your active session with full context.

**The SDLC doesn't end at local tests.** CI must pass too. **NEVER AUTO-MERGE — do NOT run `gh pr merge --auto`.** Auto-merge fires before review feedback can be read; the shepherd loop below IS the process. (Evidence: PR #145 auto-merged before its review was read — a reviewer-found P1 dead-code bug shipped as a result.)

```
Local tests pass -> Commit -> Push -> Watch CI
                                         |
                              CI passes? -+-> YES -> Read logs anyway -> Cross-model audit -> Present for review
                                         |
                                         +-> NO -> Fix -> Push -> Watch CI
                                                           |
                                                   (max 2 attempts)
                                                           |
                                                   Still failing?
                                                           |
                                                   ESCALATE: Fable→Codex
```

**How to watch CI:**
1. Push changes to remote
2. Check CI status:
   ```bash
   # Watch checks in real-time (blocks until complete)
   gh pr checks --watch

   # Or check status without blocking
   gh pr checks

   # View specific failed run logs
   gh run view <RUN_ID> --log-failed
   ```
3. If CI fails:
   - Read failure logs: `gh run view <RUN_ID> --log-failed`
   - Diagnose root cause (same philosophy as local test failures)
   - Fix and push again
4. Max 2 fix attempts - if still failing, escalate (Fable → Codex `high`) before asking the user
5. **Read CI logs whether pass or fail — not just on failure.** A green checkmark hides warnings, skipped steps, and degraded scores (v1.24.0 shipped a degraded E2E score and a silently excluded test suite behind a passing check). Use `gh run view <RUN_ID> --log`, not just `--log-failed`.
6. **Cross-model audit the CI logs** — same `codex exec` pattern as the Cross-Model Review Loop above. Prompt: *"Audit for silent failures, skipped tests, degraded metrics, warnings-that-should-be-errors."* Do this even when every check is green.
7. Only after logs are read and audited — proceed to present final summary

**Context GC (compact during idle):** While waiting for CI (typically 3-5 min), suggest `/compact` if the conversation is long. Think of it like a time-based garbage collector — idle time + high memory pressure = good time to collect. Don't suggest on short conversations.

**CI failures follow same rules as test failures:**
- Your code broke it? Fix your code
- CI config issue? Fix the config
- Flaky? Investigate - flakiness is a bug
- Stuck? Escalate — Fable, then Codex `high`; the user last

### CI Review Feedback Loop — Local Shepherd (After CI Passes)

**CI passing isn't the end.** If CI includes a code reviewer, read and address its suggestions.

```
CI passes -> Read review suggestions
                    |
        Valid improvements? -+-> YES -> Implement -> Run tests -> Push
                             |                                      |
                             |                          Review again (iterate)
                             |
                             +-> NO (just opinions/style) -> Skip, note why
                             |
                             +-> None -> Done, present to user
```

**How to evaluate suggestions:**
1. Read all CI review comments: `gh api repos/OWNER/REPO/pulls/PR/comments`
2. For each suggestion, ask: **"Is this a real improvement or just an opinion?"**
   - **Real improvement:** Fixes a bug, improves performance, adds missing error handling, reduces duplication, improves test coverage → Implement it
   - **Opinion/style:** Different but equivalent formatting, subjective naming preference, "you could also..." without clear benefit → Skip it
3. Implement the valid ones, run tests locally, push
4. CI re-reviews — repeat until no substantive suggestions remain
5. **Termination is the cumulative stop rule (#539), not a fixed count** — continue only while the last completed pass recorded an open in-card P0/P1, or the first evidence invalidation in this root task [bound: CANONICAL:evidence-exception-bound]. A reviewer that keeps finding *new surfaces* after the deliverable converged is the failure that rule exists to stop; re-freezing scope never resets the count.

**The goal:** User is only brought in at the very end, when both CI and reviewer are satisfied. The code should be polished before human review.

**Customizable behavior** (set during wizard setup):
- **Auto-implement** (default): Implement valid suggestions autonomously, skip opinions
- **Ask first**: Present suggestions to user, let them decide which to implement
- **Skip review feedback**: Ignore CI review suggestions, only fix CI failures

## Self-Review — demoted from critical (GH #486)

**A same-model read-back is no longer a gate.** It is still scored (1 point) because the
10-point rubric and every stored baseline depend on the total, but it cannot fail a run on
its own, and it is no longer injected per-prompt or listed as a checklist step.

**Why:** Anthropic's Opus 5 guidance says explicit verification instructions cause
over-verification. That advice targets *same-model* self-checking, and this repo's own
record agrees — in one session `/code-review` reported 64/64 green three times while an
independent model found real P1s each time, including a shipped hook proven silently dead
and a guard proven to be reading nothing. Same-model self-review has **zero recorded
unique catches** here.

**What did NOT change: cross-model review.** The guidance above does not transfer to it,
and it is the only layer with a record of catching real defects. Where `/code-review`
still earns its place is as *preflight input* to that review on high-stakes work — run it
to reduce what the cross-model reviewer has to find, not as a gate of its own.

**If your driver is Sonnet-class rather than Opus 5,** keeping a self-review pass is
reasonable; the over-verification finding is Opus-5-specific. That conditional lives here
in the on-demand doc rather than in the always-loaded skill, which ships one file to every
model.

### The loop, for reference

```
PLANNING → DOCS → TDD RED → TDD GREEN → Tests Pass → Cross-Model Review
    ↑                                                      │
    │                                                      ↓
    │                                            Issues found?
    │                                            ├── NO → Present to user
    │                                            └── YES ↓
    └────────────────────────────────────────────── Ask user: fix in new plan?
```

**The loop goes back to PLANNING, not TDD RED.** When self-review finds issues:
1. Ask user: "Found issues. Want to create a plan to fix?"
2. If yes → back to PLANNING phase with new plan doc
3. Then → docs update → TDD → review (proper SDLC loop)

**How to self-review:**
1. Optionally run `/code-review` as preflight input, then send the diff to a DIFFERENT model
2. It launches parallel agents (CLAUDE.md compliance, bug detection, logic & security)
3. Issues at confidence >= 80 are real findings — go back to PLANNING to fix
4. Issues below 80 are likely false positives — skip unless obviously valid
5. Address issues by going back through the proper SDLC loop

---

## Testing and Debugging Practices

### When TDD RED Applies

**TDD proves:** RED (fails — bug or missing feature), GREEN (passes — fix works), Forever (regression protection). **TDD RED applies only where a RED mutation is writable** — write the wrong version the test must catch BEFORE writing the test. If catching the wrong version requires understanding meaning (a reversal, a negation, a contradicting sentence nearby), no assertion can do it: DO NOT write the test. That exception is for prose judged by a reader — for executable behavior, any observable input/output or side-effect difference means a RED mutation IS writable. Three-way call for every change: **EVAL it** (agent-facing guidance a real scenario can observe), **plain-assert it** (mechanical contract only — byte parity, a JSON key, a version, a heading; proves structure, never meaning), or **DON'T TEST IT** (prose whose correctness is a judgement call — cross-model review is the guard). **Implement-first** is allowed ONLY when a named gate blocked the required RED/evidence act itself — a gate refusing implementation because RED is missing is the gate working, not an entry ticket. Quote the refusal verbatim in the issue/PR, get a cross-model ruling that APPROVES that same act and scope BEFORE the edit, and name — before editing — the observable that would differ if the change were wrong, then go look at it after (#525). No quoted refusal or no approving ruling — no entry.

#### RED is a set of mutations, not one deletion

**List every observation the check promises. Break each one separately on a copy of the live deliverable.** The run fails unless every expected failure actually reports. If you cannot list the observations, do not write the guard.

**Make the nearest wrong version fail, not just a deletion.** Deletion is the maximal mutation and the easiest to survive: a branch that pre-existing text already satisfies is invisible to it. *(Five dead checks shipped or nearly shipped in one session, several caught only when an independent reviewer mutated the deliverable instead of the base. #550's runner silently ran 30 of 65 suites and reported green.)*

#### Never grep prose for meaning

**A regex over prose may check an exact string or a structure. It may never check meaning, denial, or polarity.** Review the prose instead, or delete the marker (#493 requirement 6).

**The first time a reversed live instruction stays green, delete the guard. Do not patch it.** Patching an unfixable mechanism is what turns round 2 into round 4.

**Offer "delete the guard" as an outcome in any recheck of a guard.** Reviewers converge only to outcomes the prompt puts on the menu. And if you are repairing the same guard a second time in one cycle, the question is whether it should exist, not how to fix it.

*Evidence (#539): a 23-line doc change, correct at round 1 and never changed again, carried a 197-line grep guard over prose. Four rounds, seven blocking findings — all seven in the test, none in the deliverable. Rounds 2–4 were the same defect three times, because a text-presence check cannot detect polarity. The final defeat was Markdown strikethrough: `~~the count never resets~~` keeps the searched string byte-identical while the live sentence teaches the opposite, and the suite stayed 137/137 green. Rounds 1–3 forbade expanding the surface, so "delete the guard" was off the menu. Round 4 offered it and it was taken immediately.*

**Accepted residual:** nothing detects a document that states the required fields and then contradicts them in prose — by reversal, by strikethrough, or by an added "sanctioned exception" clause. No string check can close this. Cross-model review is the guard.

Practices that outlive any one task: keeping the suite trustworthy, and finding a cause
instead of guessing at one.

### Flaky Test Prevention

**Flaky tests are bugs. Period.** They erode trust in the test suite, slow down teams, and mask real regressions. For a deep dive, see: [How do you Address and Prevent Flaky Tests?](https://softwareautomation.notion.site/How-do-you-Address-and-Prevent-Flaky-Tests-23c539e19b3c46eeb655642b95237dc0)

#### Principles

1. **Treat test code like app code** — same code review standards, same quality bar. Tests are first-class citizens, not afterthoughts.

2. **Investigate every flaky failure** — never ignore a flaky test. It's a bug somewhere in one of three layers:
   - **Test code** — shared state, not parallel-safe, timing assumptions, missing cleanup
   - **App code** — race condition, unhandled edge case, non-deterministic behavior
   - **Environment/infra** — CI runner flakiness, resource contention, external service instability

3. **Stress-test new tests** — run new or modified tests N times before merge to sniff out flakiness early. A test that passes 1x but fails on run 50 has a bug.

4. **Isolate testing environments** — sanitize state between tests. Don't share databases. Clean up properly. Each test should be independently runnable.

5. **Address flakiness immediately** — momentum matters. The longer a flaky test lives, the more trust erodes and the harder root cause becomes to find.

6. **Quarantine only if actively fixing** — quarantine is a temporary holding pen, not a permanent ignore. If a test is quarantined for more than a sprint, it needs attention or deletion.

7. **Track flaky rates** — you can't fix what you don't measure. Know which tests are flaky and how often.

#### When the Bug Is in CI Infrastructure

Sometimes the flakiness is genuinely in CI infrastructure (runner environment, GitHub Actions internals, third-party action bugs). When this happens:
- **Make cosmetic steps non-blocking** — PR comments, notifications, and reports should use `continue-on-error: true`
- **Keep quality gates strict** — the actual pass/fail decision must NOT have `continue-on-error`
- **Separate "fail the build" from "nice to have"** — a missing PR comment is not a regression

---

### Visual Regression Testing (Experimental - Niche Use Cases Only)

**Most apps don't need this.** Standard E2E testing (Playwright, Cypress) covers 99% of UI testing needs.

**What is it?** Pixel-by-pixel or AI-based screenshot comparison:
```
Before: Screenshot A (baseline)
After:  Screenshot B (candidate)
Result: Visual diff highlights pixel changes
```

**When you actually need this (rare):**

| Use Case | Example | Why Standard E2E Won't Work |
|----------|---------|----------------------------|
| Wiki/Doc renderers | Markdown → HTML rendering | Output IS the visual, not DOM state |
| Canvas/Graphics apps | Drawing tools, charts | No DOM to assert against |
| PDF/Image generators | Invoice generators | Binary output, not HTML |
| Visual editors | WYSIWYG, design tools | Pixel-perfect matters |

**When you don't need this (most apps):**
Standard E2E testing checks elements exist, text is correct, interactions work. That's enough for:
- Normal web apps, forms, CRUD
- Dashboards, e-commerce, SaaS products

**The reality:**

| Approach | Coverage | Maintenance | Cost |
|----------|----------|-------------|------|
| Standard E2E | 95%+ of UI bugs | Low | Free |
| Visual regression | Remaining 5% edge cases | HIGH | Often paid |

**Visual regression downsides:**
- Baseline images constantly need updating
- Flaky due to font rendering, anti-aliasing
- CI/OS differences cause false positives
- Expensive (Chromatic, Percy charge per snapshot)

**If you actually need it:**
```javascript
// Playwright built-in (free)
await expect(page).toHaveScreenshot('rendered-page.png');
```

**During wizard setup (Step 0.4):** If canvas-heavy or rendering libraries detected, Claude asks:
```
Q?: Visual Output Testing (Experimental)

Your app appears to generate visual output (canvas/rendering detected).
Standard E2E may not cover visual rendering bugs.

Options:
[1] I'll handle visual testing myself (most users)
[2] Tell me about visual regression tools (niche)
[3] Skip - standard E2E is enough for me
```

**Default: Skip.** This is not pushed on users.

---

### Browser Tooling Policy

Three different jobs, three different tools. Conflating them is the source of recurring agent failures — `Playwright MCP` for an auth-heavy registrar dashboard wastes a session, browser-use for a deterministic regression test gives flaky CI.

| Tool | Job | Profile model | When to pick |
|------|-----|---------------|--------------|
| **Playwright tests** | Deterministic regression suite, CI/release gate | Isolated by design — each test gets a clean browser context per [Playwright docs](https://playwright.dev/docs/browser-contexts) | Asserting expected user flows; running on every PR; gating deploy |
| **Playwright MCP** | Live browser debugging, visual QA, DOM inspection | Default mode uses a **persistent Playwright-managed profile** at `ms-playwright/mcp-{channel}-{workspace-hash}` ([docs](https://playwright.dev/docs/getting-started-mcp#user-profile)) — NOT the user's regular Chrome profile. Other modes: `--isolated` (ephemeral context per session), `--user-data-dir=PATH` (caller-supplied dir), CDP attach (`--cdp-endpoint`), extension mode (attach to user's running browser tab) | One-off "look at this page" / "click this button and tell me what happens"; visual verification mid-session |
| **Real-browser tooling** (browser-use, CDP-attach, Chrome profile) | Authenticated, profile-dependent, stateful operator flows | **When configured for real-browser mode** (e.g., browser-use `Browser.from_system_chrome()` or CLI `--profile`/`connect`), uses the user's actual Chrome profile (cookies, extensions, logged-in sessions). Default browser-use CLI runs headless Chromium — opt into the real-profile mode explicitly | Registrar dashboards (Porkbun, GoDaddy), DNS setup, cloud-provider consoles, wallet-adjacent Web3 flows, logged-in admin panels — anywhere preserving cookies/profile/extensions matters more than clean isolation |

**The core insight:** Playwright tests' isolation is a *feature*, not a bug. Playwright MCP's persistent-managed-profile default is also a feature — it preserves session continuity across debug interactions in a SINGLE agent. The collision case is concurrent agents (#251) sharing the same managed profile. Real-browser tooling is the right call only when the task IS the user's authenticated session, and only when explicitly configured to attach to that profile.

#### When to recommend real-browser tooling (#225)

Trigger examples — if the task description includes any of these, suggest real-browser tooling (browser-use or CDP-attach) over Playwright MCP:

- Registrar dashboards (domain purchase, DNS records, nameserver changes)
- DNS setup / DNSLink / custom-domain configuration
- Cloud/provider dashboards (AWS console, Cloudflare, Vercel, registrars)
- Wallet-adjacent Web3 flows (token approvals, contract interactions in a logged-in MetaMask)
- Logged-in admin panels (Stripe, Vercel, GitHub admin pages requiring 2FA-cached session)
- Anywhere preserving cookies/profile/extensions matters more than clean isolation

These all share a property: the agent's job IS the authenticated session. A clean automation browser is the wrong model.

#### Playwright MCP profile-lock policy (#251)

`Playwright MCP`'s default mode reuses a single persistent managed profile (`ms-playwright/mcp-{channel}-{workspace-hash}`) across stdio sessions — which is the right call for single-agent debugging because it preserves session continuity across calls, but breaks down when **multiple agents or MCP clients run concurrently** (two CC sessions, one CC + one Codex, etc.). Concurrent stdio sessions collide on the same Chrome user-data directory and corrupt each other's session state.

**Upstream Playwright rejected default-isolated as the global default.** See [microsoft/playwright#40419](https://github.com/microsoft/playwright/issues/40419) and the discussion on [microsoft/playwright#40420](https://github.com/microsoft/playwright/pull/40420) — maintainer feedback: *"That's unfortunately very breaking."* Changing the default would silently break every existing single-agent setup that relies on the persistent managed profile.

**Wizard policy (per-user, opt-in at the wizard layer, not upstream):**

- **Single-agent / single MCP client (default):** Use Playwright MCP's default persistent-managed-profile mode. No special config required.
- **Concurrent agents / multiple MCP clients:** Pick one of these per client to avoid profile-lock collisions: (a) `--isolated` (ephemeral context per session, no persistence), (b) `--user-data-dir=$TMPDIR/playwright-mcp-$AGENT_ID` (caller-supplied dir, isolated per agent), or (c) `--cdp-endpoint` to attach each agent to a separately-launched browser. None of these require an upstream breaking change.
- **Real-browser / profile-dependent flows:** Don't use Playwright MCP at all — use real-browser tooling explicitly configured to attach to the user's profile (e.g., `browser-use` with `Browser.from_system_chrome()` or CLI `--profile`). The task is the session, not isolated automation.

This rule is per-workflow, not global. Setup wizard does NOT auto-configure isolated profiles — adoption is explicit, gated on the user signaling concurrent-agent intent.

#### Anti-patterns

- **Using Playwright MCP for registrar dashboards** — its persistent managed profile is NOT your real Chrome profile, so your registrar's logged-in session/2FA cookies aren't there. You'll be re-logging in on every interaction. Use real-browser tooling configured for your real Chrome profile instead.
- **Using profile-coupled / stateful browser tooling for deterministic CI tests** — when browser-use (or any tool) is configured to use a real Chrome profile, cached state, extension chrome, and stale cookies pollute the test. Use Playwright tests with isolated browser contexts for CI.
- **Setting Playwright MCP `--isolated` globally as a default** — breaks single-agent flows that rely on the persistent managed profile for session continuity across debug interactions. Upstream Playwright rejected this for the same reason. Make it explicit per-workflow when concurrent agents are running.

---


### Debugging Workflow (Systematic Investigation)

When something breaks and the cause isn't obvious, follow this systematic debugging workflow:

```
Reproduce → Isolate → Root Cause → Fix → Regression Test
```

1. **Reproduce** — Can you make it fail consistently? If intermittent, stress-test (run N times). If you can't reproduce it, you can't fix it
2. **Isolate** — Narrow the scope. Which file? Which function? Which input? Use binary search: comment out half the code, does it still fail?
3. **Root cause** — Don't fix symptoms. Ask "why?" until you hit the actual cause. "It crashes on line 42" is a symptom. "Null pointer because the API returns undefined when rate-limited" is a root cause
4. **Fix** — Fix the root cause, not the symptom
5. **Regression test** — Write a test that fails without your fix and passes with it (TDD GREEN)

**For regressions** (it worked before, now it doesn't): Use `git bisect` to find the exact breaking commit. `git bisect start`, `git bisect bad` (current), `git bisect good <known-good-commit>`. Narrows to the breaking commit in O(log n) steps.

**Environment-specific bugs** (works locally, fails in CI/staging/prod): Check environment differences (env vars, OS version, dependency versions, file permissions). Reproduce the environment locally if possible. Add logging at the failure point — don't guess, observe.

### Fixed Means Observed

Before reporting a fix, name the observable that would differ if it were NOT fixed — then go look at it. Settings file edited → read the live process env, not the file. Hook changed → fire it. Threshold changed → measure it against the real files. If the only evidence is "I made the edit", the state is *submitted*, not fixed.

**Out-of-repo changes get no gate** (global `settings.json`, env vars, shell rc, scheduler entries): no diff, no PR, no reviewer ever sees them. Before editing, check `.reviews/` artifacts and memory for prior findings on the subject; state the verification command in the same message as the change; if a live process won't pick up the edit (env vars need a restart), say so instead of "fixed". **Evidence:** 2026-08-08 (#525) — a settings fix was reported fixed while the bug was still live; the answer was already in `.reviews/` from PR #468.

### An Instruction Is Not a Claim

**Never tell a reader to run a command you have not run.** Labeling can save a claim, because the reader evaluates it. It cannot save an instruction, because the reader executes it. Delete it instead.

Run the exact string you are going to ship, and fill in every placeholder at least once.

**Check that the output shows the promised behavior, not just exit 0.** This is the part that gets skipped. `✔ already at the latest version (1.97.0)` proves the identifier resolves; it does not prove the command updates anything. If you cannot observe the behavior, narrow the instruction to what you did observe rather than shipping the wider promise. A command you genuinely cannot run — destructive, or the environment is unavailable — may be *described*, never *instructed*.

**Reviewers enforce this: do not certify a doc containing imperative commands without pasted execution output.** The other leg can check that, which is the point. Two-leg reading is the right instrument for judgement defects and the wrong one for empirical claims about a command.

*Evidence (#572): 24 lines of documentation produced five P1s, every one a claim wider than any observation of it — including a documented update command that fails outright. That doc had labeled its evidence honestly, stating the semantics came from help text and that the command had not been run, and the broken instruction shipped anyway. Both legs certified it.*

**Do not build a static guard for this.** Extracting command strings and requiring an adjacent output block passes on pasted, fabricated or stale output, and cannot tell an instruction from an illustration — it would pass on everything it exists to reject. The live guard is executing the commands. Put them in the repo's own release-verification list, which a maintainer runs, not in CI.

## Step 8: Create CLAUDE.md

Create `CLAUDE.md` in your project root. This is your project-specific configuration:

```markdown
# [Your Project Name] - Development Guidelines

## TDD ENFORCEMENT (READ BEFORE CODING!)

**STOP! Before writing ANY implementation code:**

1. **Write failing tests FIRST** (TDD RED) — where a failing test can be written; meaning-level prose changes get cross-model review instead (do not write the test)
2. **Use integration tests** primarily - see TESTING.md
3. **Use REAL fixtures** for mock data - never guess API shapes

## Commands

<!-- CUSTOMIZE: Replace with your actual detected/confirmed commands -->

- Build: `[your build command]`
- Run dev: `[your dev command]`
- Lint: `[your lint command]`
- Typecheck: `[your typecheck command]`
- Run all tests: `[your test command]`
- Run specific test: `[your specific test command]`

## Code Style

<!-- CUSTOMIZE: Add your code style rules -->

- [Your indentation: tabs or spaces?]
- [Your quote style: single or double?]
- [Semicolons: yes or no?]
- Use strict TypeScript
- Prefer const over let

## Architecture

<!-- CUSTOMIZE: Brief overview of your project -->

- Commands/routes live in: [where?]
- Core logic lives in: [where?]
- Database: [what?]
- Cache: [what?]

## Git Commits

- Follow conventional commits: `type(scope): description`
- NEVER commit with failing tests

## Feature Docs

- Before coding a feature: READ its `*_DOCS.md` file
- After completing work: UPDATE the feature doc (or create one if 3+ files touched)

## Testing Notes

<!-- CUSTOMIZE: Any project-specific testing notes -->

- Test timeout: [how long?]
- Special considerations: [any?]
```

---

## Step 9: Create SDLC.md, TESTING.md, and ARCHITECTURE.md

These are your full reference docs. Start with stubs and expand over time:

**ARCHITECTURE.md (IMPORTANT - Dev & Prod Environments):**
```markdown
# Architecture

## How to Run This Project

### Development
```bash
# Start dev server
[your dev command, e.g., npm run dev]

# Run with hot reload
[your hot reload command]

# Database (dev)
[how to start/connect to dev DB]

# Other services (Redis, etc.)
[how to start dev dependencies]
```

### Production
```bash
# Build for production
[your build command]

# Start production server
[your prod start command]

# Database (prod)
[connection info or how to access]
```

## Environments

<!-- Claude auto-populates this from deployment detection -->

| Environment | URL | Deploy Command | Trigger |
|-------------|-----|----------------|---------|
| Local Dev | http://localhost:3000 | `npm run dev` | Manual |
| Preview | [auto-generated PR URL] | `vercel` | Auto on PR |
| Staging | https://staging.example.com | `[your staging deploy]` | Push to staging |
| Production | https://example.com | `vercel --prod` | Manual / push to main |

## Deployment Checklist

**Before deploying to ANY environment:**
- [ ] All tests pass locally
- [ ] Production build succeeds (`npm run build`)
- [ ] No uncommitted changes

**Before deploying to PRODUCTION:**
- [ ] Changes tested in staging/preview first
- [ ] STATE CONFIDENCE: HIGH before proceeding
- [ ] If LOW confidence → ASK USER before deploying

**Claude follows this automatically.** When task involves "deploy to prod" and confidence is LOW, Claude will ask before proceeding.

## Post-Deploy Verification

**After deploying to ANY environment, verify it's working:**

| Environment | Health Check | Log Command | Smoke Test |
|-------------|-------------|-------------|------------|
| Local Dev | `curl http://localhost:3000/health` | `[your dev log command]` | `npm run test:smoke` |
| Staging | `curl https://staging.example.com/health` | `[your staging log command]` | `[your staging smoke test]` |
| Production | `curl https://example.com/health` | `[your prod log command, e.g., kubectl logs]` | `[your prod smoke test]` |

**Monitoring after production deploy:**
1. Watch error rates for 15 minutes (dashboard: `[your monitoring URL]`)
2. Check application logs for new errors: `[your log command]`
3. Run smoke tests against production: `[your smoke test command]`
4. If issues found → rollback first, THEN start new SDLC loop to fix

**Claude follows this automatically.** After a deploy task, Claude runs through the Post-Deploy Verification table for the target environment. If any check fails, Claude suggests rollback and a new fix cycle.

## Pipeline Liveness Audits — CI green ≠ data flowing

A green CI badge only means "no step crashed." It does **not** mean "this pipeline is still producing the output it's supposed to produce." Long-running pipelines — scheduled benchmarks, nightly analytics jobs, weekly report generators, any workflow that appends to a log or dataset — can silently stop producing output while every run still reports success. Regression tests alone do not catch this: the fault lives between "green status" and "observable artifact."

**Symptom to watch for:** a file, table, or dashboard that's supposed to be updated by a scheduled workflow stops advancing even though the workflow keeps running green.

**Concrete example from this repo (2026-04-18):** `tests/e2e/score-history.jsonl` hadn't been appended to since 2026-03-30, yet weekly runs kept completing. Two stacked causes:

1. On the 2026-04-13 run, a `CRITICAL MISS` caused `evaluate.sh` to exit 1 *with* a valid score payload; the tier2 wrapper aborted on the non-zero exit and dropped the trial (fix: PR #193 — disambiguate infra error from legitimate low-score exit via JSON payload, not exit code).
2. On other runs, a separate PR-branch push race (`refs/pull/N/merge` checkout vs. `refs/heads/<branch>` push) silently dropped the new trial because `continue-on-error: true` was set on the push step.

The second failure was silent (push step protected by `continue-on-error`); the first was a red CI run but nobody was watching weekly runs closely enough to notice the artifact had stopped advancing. Either way, the artifact's liveness would have caught the stall weeks earlier than a CI-badge-only review.

**Audit pattern — run when you touch a pipeline, and when asked to check pipeline health:**

1. **Identify the observable output** — the artifact the pipeline is supposed to produce (file, PR, issue, log row, dashboard row).
2. **Check its liveness** — what's the last timestamp? If the pipeline runs weekly but the artifact is 3+ cycles stale, that's a stall, not a lull.
3. **Walk backward from the artifact to CI** — find the step that writes it, read that specific step's logs (not just the top-level status), confirm the write actually happened.
4. **When `continue-on-error: true` is present upstream of the write step**, treat that step as suspect by default — its failures are masked.

**When Claude should run this.** Claude runs the liveness audit when it merges or edits a scheduled workflow, when it ships a change that writes to a long-running artifact, and whenever the user asks to check a pipeline's health. It is not a background task — if no one is looking, the audit does not happen.

## Rollback

If deployment fails or post-deploy verification catches issues:

| Environment | Rollback Command | Notes |
|-------------|------------------|-------|
| Preview | [auto-expires or redeploy] | Ephemeral — redeploy to fix |
| Staging | `[your rollback command]` | [notes] |
| Production | `[your rollback command]` | [critical - document clearly] |

<!-- Add specific rollback procedures as you discover them -->

## System Overview

[Brief description of components and how they connect]

## Key Services

| Service | Purpose | Port |
|---------|---------|------|
| [API] | [What it does] | [3000] |
| [DB] | [What it does] | [5432] |

## Gotchas

<!-- Add environment-specific gotchas as you discover them -->
```

**Why ARCHITECTURE.md matters:** Claude needs to know how to run your app in dev vs prod. Without this, Claude will ask "how do I start the server?" every time. Put it here once, never answer again.

**If you already have one:** Claude will scan for existing ARCHITECTURE.md, README.md, or similar and merge/reference it.

---

**SDLC.md:**
```markdown
<!-- SDLC Harness Version: 1.99.2 -->
<!-- Setup Date: [DATE] -->
<!-- Completed Steps: step-0.1, step-0.2, step-0.4, step-1, step-2, step-3, step-4, step-5, step-6, step-7, step-8, step-9 -->
<!-- Git Workflow: [PRs or Solo] -->
<!-- Plugins: claude-md-management -->

# SDLC - Development Workflow

See `.claude/skills/sdlc/SKILL.md` for the enforced checklist.

## Workflow Overview

1. **Planning Mode** → Research, present approach, get approval
2. **Transition** → Update docs, /compact
3. **Implementation** → TDD RED → GREEN → PASS
4. **Review** → cross-model review, present summary

## Lessons Learned

<!-- Add gotchas as you discover them -->
```

**Why the metadata comments?**
- Invisible to readers (HTML comments)
- Parseable by Claude for idempotent updates
- Survives file edits
- Travels with the repo

**TESTING.md (domain-adaptive — generate the template matching the detected domain):**

**Web/API (default):**
```markdown
# Testing Guidelines

## Testing Diamond

Integration tests are best bang for buck. Mocks can "pass" while production fails.

| Layer | What It Tests | % of Suite |
|-------|--------------|------------|
| E2E | Full user flow through browser (Playwright, Cypress) | ~5% |
| Integration | Real DB, real cache, API-level — no UI | ~90% |
| Unit | Pure logic — no DB, no API, no filesystem | ~5% |

## Test Commands

- All tests: `[your command]`
- Specific test: `[your command]`

## Mocking Rules

| Dependency | Mock? | Why |
|------------|-------|-----|
| Database | NEVER | Use test DB or in-memory |
| Cache | NEVER | Use isolated test instance |
| External APIs | YES | Real calls = flaky + expensive |
| Time/Date | YES | Determinism |

## Fixtures

Location: `[tests/fixtures/ or test-data/]`

## Lessons Learned

<!-- Add testing gotchas as you discover them -->
```

**Firmware/Embedded (if detected):**
```markdown
# Testing Guidelines

## Testing Layers (Firmware)

SIL tests are best bang for buck. Real hardware tests are slow but prove the real thing works.

| Layer | What It Tests | % of Suite |
|-------|--------------|------------|
| HIL | Hardware-in-the-Loop — real device, flash + boot verify | ~5% |
| SIL | Software-in-the-Loop — emulated hardware (QEMU, device sims) | ~60% |
| Config Validation | Device config parsing, constraint checks, valid ranges | ~25% |
| Unit | Pure logic — parsers, formatters, math | ~10% |

## Test Commands

- All tests: `[your command, e.g., make test]`
- Flash + verify: `[your flash command]`
- Config validation: `[your config check command]`

## Mocking Rules

| Dependency | Mock? | Why |
|------------|-------|-----|
| Hardware interfaces (/dev/tty*, GPIO) | YES | Real hardware not always available |
| Config parsers | NEVER | Config bugs brick devices |
| Filesystem (/sys/, /proc/) | YES in CI | Real paths only exist on target |
| Serial protocols | YES | Use loopback or emulator |

## Device Matrix

| Device | Config File | Status |
|--------|------------|--------|
| [device-a] | configs/device-a.cfg | [tested/untested] |

## Lessons Learned

<!-- Add firmware testing gotchas as you discover them -->
```

**Data Science (if detected):**
```markdown
# Testing Guidelines

## Testing Layers (Data Science)

Pipeline integration tests are best bang for buck. Model evaluation catches degradation.

| Layer | What It Tests | % of Suite |
|-------|--------------|------------|
| Model Evaluation | Accuracy/precision/recall/F1 on holdout sets | ~10% |
| Pipeline Integration | End-to-end pipeline runs with test datasets | ~60% |
| Data Validation | Schema checks, distribution drift, missing values | ~20% |
| Unit | Pure transformations, feature engineering | ~10% |

## Test Commands

- All tests: `[your command, e.g., pytest]`
- Model evaluation: `[your eval command]`
- Data validation: `[your validation command]`

## Mocking Rules

| Dependency | Mock? | Why |
|------------|-------|-----|
| External data sources (APIs, S3) | YES | Real calls = flaky + expensive |
| Data transformations | NEVER | Transform bugs corrupt pipelines |
| Model training | PARTIAL | Use small test datasets for speed |
| Database/warehouse | YES in unit | Use test fixtures for integration |

## Test Datasets

Location: `[tests/data/ or tests/fixtures/]`
- Keep test datasets small but representative
- Include edge cases: missing values, wrong types, outliers

## Lessons Learned

<!-- Add data science testing gotchas as you discover them -->
```

**CLI Tool (if detected):**
```markdown
# Testing Guidelines

## Testing Layers (CLI)

CLI integration tests are best bang for buck. Test real invocations with real arguments.

| Layer | What It Tests | % of Suite |
|-------|--------------|------------|
| CLI Integration | Full invocations with real args, real filesystem | ~80% |
| Behavior | Exit codes, stdout/stderr content, file creation | ~10% |
| Unit | Arg parsing, formatters, pure logic | ~10% |

## Test Commands

- All tests: `[your command]`
- Specific test: `[your command]`

## Mocking Rules

| Dependency | Mock? | Why |
|------------|-------|-----|
| Filesystem | NEVER | CLI tools live on the filesystem |
| Network calls | YES | Real calls = flaky |
| Stdin/stdout | CAPTURE | Use child_process or subprocess |
| Environment vars | SET per test | Determinism |

## Behavior Contract

| Input | Expected Exit Code | Expected Output |
|-------|-------------------|----------------|
| `--help` | 0 | Usage text |
| (no args) | 1 | Error message |
| `--version` | 0 | Version string |

## Lessons Learned

<!-- Add CLI testing gotchas as you discover them -->
```

---

**DESIGN_SYSTEM.md (if UI detected):**

Only generated if design system elements were detected in Step 0.4. Skip if no UI work expected.

```markdown
# Design System

## Source of Truth

[Storybook URL or Figma link if external, otherwise this document]

## Colors

| Name | Value | Usage |
|------|-------|-------|
| primary | #3B82F6 | Buttons, links, primary actions |
| secondary | #10B981 | Success states, secondary actions |
| error | #EF4444 | Error states, destructive actions |
| warning | #F59E0B | Warning states, caution |
| background | #FFFFFF | Page background |
| surface | #F3F4F6 | Cards, elevated surfaces |
| text-primary | #111827 | Main body text |
| text-secondary | #6B7280 | Secondary, muted text |

## Typography

| Style | Font | Size | Weight | Line Height |
|-------|------|------|--------|-------------|
| h1 | Inter | 2.25rem | 700 | 1.2 |
| h2 | Inter | 1.875rem | 600 | 1.25 |
| body | Inter | 1rem | 400 | 1.5 |
| code | Fira Code | 0.875rem | 400 | 1.6 |

## Spacing

Using 4px base unit: `4, 8, 12, 16, 24, 32, 48, 64, 96`

## Components

Reference: `components/ui/` or Storybook

## Assets

- Icons: `public/icons/` or icon library name
- Images: `public/images/`
- Logos: `public/logos/`

## Gotchas

<!-- Add design-specific gotchas as you discover them -->
```

**Why DESIGN_SYSTEM.md?**
- Claude needs to know your visual language when making UI changes
- Prevents style drift and inconsistency
- Extracted from your actual config (tailwind.config.js, CSS vars) - not guessed

**If you have external design system:** Point to Storybook/Figma URL instead of duplicating.

### BRANDING.md (If Branding Assets Detected)

**Only generated if branding-related files are found:** BRANDING.md, brand/, logos/, style-guide.md, brand-voice.md, tone-of-voice.*, or UI/content-heavy project patterns.

```markdown
# Brand Guidelines

## Brand Voice & Tone
- [Detected from brand-voice.md or style guide, or ask user]
- Formal/casual/technical/friendly
- Target audience description

## Naming Conventions
- Product name: [official name, capitalization]
- Feature names: [naming pattern]
- Technical terminology: [glossary of project-specific terms]

## Visual Identity
- Logo usage: [reference to logo files or guidelines]
- Color palette: [reference to DESIGN_SYSTEM.md if exists]
- Typography: [font choices and usage]

## Content Style
- [Any content writing guidelines]
- [Error message tone]
- [User-facing copy standards]
```

**Why BRANDING.md?** Claude writing user-facing copy, error messages, or documentation needs to know the brand voice. Without this, output tone is inconsistent. Skip for backend-only or internal-tool projects.

---

## Step 10: Verify Setup (Claude Does This Automatically)

**After creating all files, Claude automatically verifies the setup:**

```
Claude runs these checks:
1. ✓ Hooks are executable (chmod +x applied)
2. ✓ settings.json is valid JSON
3. ✓ Skill frontmatter has correct name/description
4. ✓ All required files exist
5. ✓ Directory structure is correct

Verification Results:
├── .claude/hooks/sdlc-prompt-check.sh    ✓ executable
├── .claude/hooks/tdd-pretool-check.sh    ✓ executable
├── .claude/settings.json                  ✓ valid JSON
├── .claude/skills/sdlc/SKILL.md          ✓ frontmatter OK
├── CLAUDE.md                              ✓ exists
├── SDLC.md                                ✓ exists
└── TESTING.md                             ✓ exists

All checks passed! Setup complete.
```

**If any check fails:** Claude fixes it automatically or tells you what's wrong.

**You don't need to verify manually** - Claude handles this as the final step of wizard execution.

---

## Step 11: Restart and Verify

**Restart Claude Code to load the new hooks/skills:**

1. Exit this session, start a new one
2. Send any message (even just "hi")
3. You should see "SDLC BASELINE" in the response

**Test the system:**

| Test | Expected Result |
|------|-----------------|
| "What files handle auth?" | Answers without invoking skills |
| "Add a logout button" | Auto-invokes sdlc skill, uses TodoWrite |
| "Write tests for login" | Auto-invokes sdlc skill |

**What happens automatically:**

| You Do | System Does |
|--------|-------------|
| Ask to implement something | SDLC skill auto-invokes, TodoWrite starts |
| Ask to write tests | SDLC skill auto-invokes |
| Claude tries to edit code | TDD reminder fires |
| Task completes | Compliance check runs |

**You do NOT need to:** Type `/sdlc` manually, remember all steps, or enforce the process yourself.

**If not working:** Ask Claude to check:
- Is `.claude/settings.json` valid JSON?
- Are hooks executable? (`chmod +x .claude/hooks/*.sh`)
- Is the hook path correct?

---

## Step 12: The Workflow

**Planning Mode** (use for non-trivial tasks):

1. Claude researches codebase, reads relevant docs
2. Claude presents approach with **confidence level**
3. You approve or adjust
4. Claude updates docs with discoveries
5. Claude asks: "Run `/compact` before implementation?"
6. You run `/compact` to free context
7. Claude implements with TDD

**When Claude should ask you:**
- LOW confidence → Must escalate (Fable → Codex) before interrupting a human
- FAILED 2x → Must escalate (Fable → Codex) before interrupting a human
- Multiple valid approaches → Should present options

---

## Quick Reference Card

### Workflow Phases

| Phase | What Happens | Key Action |
|-------|--------------|------------|
| **Planning** | Research, design approach | State confidence |
| **Transition** | Update docs | Request /compact |
| **Implementation** | TDD RED → GREEN → PASS | All tests pass |
| **Review** | Cross-model review, summary | Present to user |

### Confidence Levels

| Level | Claude Action |
|-------|---------------|
| HIGH (90%+) | Proceed after approval |
| MEDIUM (60-89%) | Highlight uncertainties |
| LOW (<60%) | **Escalation ladder** — Fable → Codex high → human last |
| FAILED 2x | **Escalation ladder** — human is the last rung, not the first |

### Hook Summary

| Hook | Fires | Purpose |
|------|-------|---------|
| UserPromptSubmit | Every prompt | SDLC baseline + skill trigger |
| PreToolUse | Before file edits | TDD reminder |

### Key Commands

| Action | Command |
|--------|---------|
| Free context after planning | `/compact` |
| Enter planning mode | Claude suggests or `/plan` |
| Run specific skill | `/sdlc` |

---

## Troubleshooting

### Hook Not Firing

```bash
# Check hook is executable
chmod +x .claude/hooks/sdlc-prompt-check.sh

# Test hook manually
./.claude/hooks/sdlc-prompt-check.sh
# Should output SDLC BASELINE text
```

### Skills Not Loading

1. Check skill frontmatter has `name:` matching directory
2. Check description matches trigger words in hook
3. Verify Claude is recognizing implementation tasks

---

## Success Criteria

You've successfully set up the system when:

- [ ] Light hook fires every prompt (you see SDLC BASELINE in responses)
- [ ] Claude auto-invokes sdlc skill for implementation tasks
- [ ] Claude auto-invokes sdlc skill for all tasks
- [ ] Claude uses TodoWrite to track progress
- [ ] Claude states confidence levels
- [ ] Claude escalates (Fable → Codex) when LOW confidence, before asking
- [ ] TDD hook reminds about tests before editing source files
- [ ] Claude requests /compact before implementation

---

## End of Task: Compliance and Mini-Retro

**Compliance check** (Claude does this after each task):
- Task list used? Confidence stated? TDD followed? Tests pass? Diff read back?
- If something was skipped: note what and why (intentional vs oversight)

**Mini-retro** (optional, for meaningful tasks only):

**This is for AI learning, not human.** The retro helps Claude identify:
- What it struggled with and why
- Whether it needs more research in certain areas
- Whether bad/legacy code is causing low confidence (indicator of problem area)

```
- Improve: [something that could be better]
- Stop: [something that added friction]
- Start: [something that worked well]

What I struggled with: [area where confidence was low]
Suggested doc updates: [if any]
Want me to file these? (yes/no/not now)
```

**Capture learnings (update the right docs):**

| Learning Type | Update Where |
|---------------|--------------|
| Feature-specific gotchas, decisions | Feature docs (`*_DOCS.md`, e.g., `AUTH_DOCS.md`) |
| Testing patterns, gotchas | `TESTING.md` |
| Architecture decisions | `ARCHITECTURE.md` |
| Commands, general project context | `CLAUDE.md` (or `/revise-claude-md`) |

**`/revise-claude-md` scope:** Only updates CLAUDE.md. It does NOT touch feature docs, TESTING.md, hooks, or skills. Use it for general project context that applies across the codebase.

### Memory Audit Protocol

Per-user memory at `~/.claude/projects/<proj>/memory/` accumulates private learnings. Some
are portable lessons — tool quirks, platform gotchas, process rules — that belong in shared
docs instead. **A process rule saved only to memory is a /sdlc gap: memory changes one
agent, docs change everyone.**

**When to run:** end of a release, after a debugging-heavy session, or on an explicit
"audit my memory" request.

**Rule-based denylist** (deterministic, no LLM judgement needed):

| Frontmatter | Disposition |
|---|---|
| `type: user` | keep private, never promote — it describes the person, not the work |
| `type: reference` | keep private — pointers to dashboards, tickets, personal URLs |
| `type: project` | manual review — mixes private state with portable rules |
| `type: feedback` | manual review — usually the richest source of promotable rules |

**Destinations** (promote into an existing file; do not create new ones): tool and platform
gotchas → `SDLC.md`. Testing lessons → `TESTING.md`. Skill-specific quirks → that
`SKILL.md`. Process rules → the `/sdlc` skill, via `/feedback`.

**Tracking:** write `promoted_to: <path>` into the memory file's frontmatter. Later audits
skip anything already promoted, so the protocol is re-runnable without re-reviewing the
same entries.

**Human gate is MANDATORY.** The protocol produces diffs; the user approves them
chunk-by-chunk. Never auto-apply — a promotion edits shipped guidance.

**Prove-It:** do not build a `/memory-audit` slash command until this has been run manually
at least four times. The protocol is cheap; the automation needs evidence it is worth
maintaining.

**Why this lives here and not in the skill:** the skill is always loaded and byte-capped
(GH #489). This protocol runs at a discrete, self-announcing moment — end of release — so
it is read on demand. It previously lived in the skill while *both* documents pointed at
each other for it (GH #489).

**When to do mini-retro:** After features, tricky bugs, or discovering gotchas. Skip for one-line fixes or questions.

**The SDLC evolves:** Weekly research, monthly deep-dives, and CI friction signals feed improvements. Human approves, the system gets better.

**If docs are causing problems:** Sometimes Claude struggles in an area because the docs are bad, legacy, or confusing - just like a human would. Low confidence in an area can indicate the docs need attention.

---

## Going Further

### Feature Documentation

Feature docs are living documents — the single source of truth for each feature, kept current just like `TESTING.md` and `ARCHITECTURE.md`. Use `*_DOCS.md` as the standard pattern:

| Pattern | When to Use | Example |
|---------|-------------|---------|
| `*_DOCS.md` | Per-feature living docs (primary) | `AUTH_DOCS.md`, `PAYMENTS_DOCS.md`, `SEARCH_DOCS.md` |
| `docs/decisions/NNN-title.md` (ADR) | Architecture decisions that need rationale | `docs/decisions/001-use-postgres.md` |
| `docs/features/name.md` | Feature docs in a `docs/` directory | `docs/features/auth.md` |

**When to create a feature doc:** If a feature touches 3+ files and no `*_DOCS.md` exists, create one. Keep it simple — what the feature does, key decisions, gotchas. The doc grows with the feature over time.

**Feature doc template:**

```markdown
# Feature Name

## Overview
What is this feature? What problem does it solve?

## Architecture
How does it work? Components, data flow.

## Gotchas
Things that can trip you up.

## Future Work
What's planned but not done.
```

**ADR (Architecture Decision Record) template** — for decisions that need context:

```markdown
# ADR-NNN: Decision Title

## Status
Accepted | Superseded by ADR-NNN | Deprecated

## Context
What is the problem? What forces are at play?

## Decision
What did we decide and why?

## Consequences
What are the trade-offs? What becomes easier/harder?
```

Store ADRs in `docs/decisions/`. Number sequentially. Claude reads these during planning to understand why things are built the way they are.

**Keeping docs in sync with code (REQUIRED):**

Docs MUST be current before commit. Stale docs mislead future sessions, waste tokens, and cause wrong implementations. The SDLC skill enforces this:

- During planning, Claude reads feature docs for the area being changed
- If the code change contradicts what the doc says → MUST update the doc
- If the code change extends documented behavior → MUST add to the doc
- If a `ROADMAP.md` exists → update it (mark items done, add new items). ROADMAP feeds CHANGELOG — keeping it current means releases write themselves
- The "After Session" step routes learnings to the right doc
- Plan files get closed out — if the session's work came from a plan, it gets deleted or marked complete so future sessions aren't misled
- Stale docs cause low confidence — if Claude struggles, the doc may need updating

**CLAUDE.md health:** Run `/claude-md-improver` periodically (quarterly or after major changes). It audits CLAUDE.md specifically — structure, clarity, completeness (6 criteria, 100-point rubric). It does NOT cover feature docs, TESTING.md, or ADRs — the SDLC workflow handles those.

### Expand TESTING.md

As you discover testing gotchas, add them:

```markdown
## Lessons Learned

### [Date] - Description
**Problem:** What went wrong
**Solution:** How to fix it
**Prevention:** How to avoid it
```

### Customize Skills

Add project-specific guidance to skills:

- Domain-specific patterns
- Common gotchas
- Preferred patterns
- Architecture decisions

### Complementary Tools

The wizard handles SDLC process enforcement. For stack-specific tooling, run `/claude-automation-recommender` — it suggests MCP servers, formatting hooks, type-checking hooks, subagent templates, and plugins based on your detected tech stack. See [Step 0.3](#step-03-additional-recommendations-optional) for the full comparison.

---

## Testing AI Apps: What's Different

AI-driven applications require fundamentally different testing approaches than traditional software.

### Why AI Testing is Unique

| Traditional Apps | AI-Driven Apps |
|------------------|----------------|
| Deterministic (same input → same output) | **Stochastic** (same input → varying outputs) |
| Binary pass/fail tests | **Scored evaluation** with thresholds |
| Test once, trust forever | **Continuous monitoring** for drift |
| Logic bugs | Hallucination, bias, inaccuracy |

### Key AI Testing Concepts

**1. Multiple Runs for Confidence**

AI outputs vary. Run evaluations multiple times and look at averages, not single results.

```
# Bad: Single run
score = evaluate(prompt)  # 7.2 - is this good or lucky?

# Good: Multiple runs with confidence interval
scores = [evaluate(prompt) for _ in range(5)]
mean = 7.1, 95% CI = [6.8, 7.4]  # Now we know the range
```

**2. Baseline Scores, Not Just Pass/Fail**

Set baseline metrics (accuracy, relevancy, coherence) and detect regressions over time.

| Metric | Baseline | Current | Status |
|--------|----------|---------|--------|
| SDLC compliance | 6.5 | 7.2 | IMPROVED |
| Hallucination rate | 5% | 3% | IMPROVED |
| Response time | 2.1s | 2.3s | STABLE |

**3. AI-Specific Risk Categories**

- **Hallucination**: AI invents facts that aren't true
- **Bias**: Unfair treatment of demographic groups
- **Adversarial**: Prompt injection attacks
- **Data leakage**: Exposing training data or PII
- **Drift**: Behavior changes silently over time (model updates, context changes)

**4. Evaluation Frameworks**

Consider tools for LLM output testing:
- [DeepEval](https://github.com/confident-ai/deepeval) - Open source LLM evaluation
- [Deepchecks](https://deepchecks.com) - ML/AI testing and monitoring
- Custom scoring pipelines (like this wizard's E2E evaluation)

### Practical Advice

- **Don't trust single AI outputs** - verify with multiple samples or human review
- **Set quantitative baselines** - "accuracy must stay above 85%" not "it should work"
- **Monitor production** - AI apps can degrade without code changes (model drift, prompt injection)
- **Budget for evaluation** - AI testing costs more (API calls, human review, compute)
- **Use confidence intervals** - 5 runs with 95% CI is better than 1 run with crossed fingers

_Sources: [Confident AI](https://www.confident-ai.com/blog/llm-testing-in-2024-top-methods-and-strategies), [IMDA Starter Kit](https://www.imda.gov.sg/-/media/imda/files/about/emerging-tech-and-research/artificial-intelligence/starter-kit-for-testing-llm-based-applications-for-safety-and-reliability.pdf), [aistupidlevel.info methodology](https://aistupidlevel.info/methodology)_

---

## Token Efficiency

Practical techniques to reduce token consumption without sacrificing quality.

### Monitor Costs

| Tool | What It Shows | When to Use |
|------|---------------|-------------|
| `/usage` | Session cost, plan usage limits, and per-category breakdown (skill, subagent, plugin, MCP server). Aliases: `/cost`, `/stats` | After heavy subagent work, before/after workflow runs, when approaching rate limits |
| `/status` | Settings panel — version, model, account, connectivity | Confirm setup before starting work |
| `/context` | What's consuming context window space | When hitting context limits |
| Status line | Real-time `cost.total_cost_usd` + token counts | Continuous monitoring |

### Reading Usage Signals

These signals are community-observed behavior on paid plans (Max/Team) — not in official CC docs. They are independent dimensions, not a single breakdown. A single session can contribute to all three. Run `/usage` to see the per-category breakdown.

| Signal | What It Means | SDLC Action |
|--------|---------------|-------------|
| **Subagent-heavy** | Each subagent runs its own context. The advisor is a separate server-side consultation (full transcript forwarded, different token profile). Explore agents, full Agent delegates, and workflow agents each spawn separate contexts. | Expected in both A and B (Fable advisor/subagent-fallback fires per-decision). If unexpectedly high: use `subagent_type: "Explore"` for search (lighter), reserve full agents for implementation. |
| **>150K context** | Sessions staying large between compactions. | **Context-window dependent.** Setup A (Opus 5, 1M auto-upgraded on Max): no `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` — none is documented to apply; use `CLAUDE_CODE_AUTO_COMPACT_WINDOW` if you want an earlier boundary (see Autocompact Tuning → "Opus 5 specifics"). Setup B (Sonnet 5, native 1M): recommended `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75` fires at ~725K — >150K is expected and fine, the real question is whether the task needed that much headroom. `/compact` between planning and implementation regardless of lane. |
| **8+ hour sessions** | Long-running sessions accumulate stale context. | `/clear` between unrelated tasks. Split multi-feature work into separate sessions. After committing a PR, start fresh. Background `/loop` sessions count toward this — audit which are still needed. |

### Reduce Consumption

| Technique | Savings | How |
|-----------|---------|-----|
| `/compact` between phases | ~40-60% context | Plan → compact → implement (plan preserved) |
| `/clear` between tasks | 100% context reset | No stale context from prior work |
| Delegate verbose ops to subagents | Separate context | `Agent` tool returns summary, not full output |
| Use skills for on-demand knowledge | Smaller base context | Skills load only when invoked |
| Scope investigations narrowly | Fewer tokens read | "investigate auth module" > "investigate codebase" |
| `--effort low` for simple tasks | ~50% thinking tokens | Simple renames, config changes |

### CI Cost Control

Add `--max-budget-usd` to CI workflows as a safety net:

```yaml
claude_args: "--max-budget-usd 5.00 --max-turns 30"
```

| Flag | Purpose |
|------|---------|
| `--max-budget-usd` | Hard dollar cap per CI invocation |
| `--max-turns` | Limit agentic turns (prevents infinite loops) |
| `--effort` | `low`/`medium`/`high` controls thinking depth |

### Advanced: OpenTelemetry

For organization-wide cost tracking, enable `CLAUDE_CODE_ENABLE_TELEMETRY=1`. This exports per-request `cost_usd`, `input_tokens`, `output_tokens` to any OTLP-compatible backend (Datadog, Honeycomb, Prometheus).

### Cache-Cost Surprises

Anthropic prompt-cache reads bill at ~10% of normal input rate ($1.50/M vs $15/M on Opus). When cache hits drop unexpectedly, the same workload silently costs **10–20×** more — a pattern HN has documented multiple times. Two common triggers:

1. **Mid-session edits to `CLAUDE.md`, `SDLC.md`, project settings, or any file the cached prefix references.** The cache key includes the project context; editing context invalidates the prefix and forces re-upload (`cache_creation` spikes, `cache_read` collapses).
2. **Upstream caching bugs.** Anthropic's [2026-04-23 post-mortem](https://www.anthropic.com/engineering/april-23-postmortem) documented one bug that "continuously dropped thinking blocks from subsequent requests" — invisible until the invoice arrived.

**Detection:** the wizard's `hooks/token-spike-check.sh` (ROADMAP #220, on-by-default for projects with a `.metrics/` directory) tracks per-session `costly_tokens = input + cache_creation + output` (excluding `cache_read`) and warns at `>2σ` over a rolling baseline. The cache-miss pattern (cache_read collapses → cache_creation spikes) shows up in `costly_tokens` directly. Test coverage in `tests/test-token-spike.sh:test_cache_miss_pattern_triggers_spike_warning` proves the absorption.

**Practices to avoid silent cache-cost blowups:**
- Avoid editing `CLAUDE.md`/`SDLC.md`/project settings mid-session when cache stability matters. If you must, accept the next request will re-upload the prefix.
- Run `/usage` (or `/cost`) after long sessions to spot anomalies before they accumulate.
- Inspect `.metrics/token-history.jsonl` directly when you suspect a regression — fields are documented at the top of `tests/e2e/token-analytics.sh`.

---

## CI/CD Gotchas

Common pitfalls when automating AI-assisted development workflows.

### `workflow_dispatch` Requires Merge First

GitHub Actions with `workflow_dispatch` (manual trigger) can only be triggered AFTER the workflow file exists on the default branch.

| What You Want | What Works |
|---------------|------------|
| Test new workflow before merge | YAML validation + trigger tests, or test via push/PR events |
| Manual trigger new workflow | Merge first, then `gh workflow run` |

**Why not `act`?** Workflows that use `claude-code-action@v1` require GitHub Actions secrets and runner context that `act` cannot replicate. Use YAML validation and trigger tests instead:

```bash
# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/my-workflow.yml'))"

# Run trigger/config tests (if you have them)
./tests/test-workflow-triggers.sh
```

This catches structural issues before merge. For full GitHub environment testing, merge then trigger.

### PR Review with Comment Response (Optional)

Want Claude to respond to existing PR comments during review? Add comment fetching to your review workflow.

**The Flow:**
1. PR opens → Claude reviews diff → Posts sticky comment
2. You read review, leave questions/comments on PR
3. Add `needs-review` label
4. Claude fetches your comments + reviews diff again
5. Updated sticky comment addresses your questions

**Two layers of interaction:**

| Layer | What | When to Use |
|-------|------|-------------|
| **Workflow** | Claude addresses comments in sticky review | Quick async response |
| **Local terminal** | Ask Claude to fetch comments, have discussion | Deep interactive discussion |

**Example workflow step:**
```yaml
- name: Fetch PR comments
  run: |
    gh api repos/$REPO/pulls/$PR_NUMBER/comments \
      --jq '[.[] | {author: .user.login, body: .body}]' > /tmp/comments.json
```

Then include `/tmp/comments.json` in Claude's prompt context.

**Local discussion:**
```
You: "Fetch comments from PR #42 and let's discuss the concerns"
Claude: [fetches via gh api, discusses with you interactively]
```

This is optional - skip if you prefer fresh reviews only.

### Cross-Model Review Loop (REQUIRED for High-Stakes)

Use an independent AI model from a different company as a code reviewer. The author can't grade their own homework — a model with different training data and different biases catches blind spots the authoring model misses.

**Why this works:** Two AI systems from different companies (e.g., Claude writes, GPT reviews) provide adversarial diversity. They have fundamentally different training, different failure modes, and different strengths. What one misses, the other catches.

**Use the best model, at an effort you can afford to run every time.** This is your quality gate — don't economize on the *model*. Always use the latest, most capable one available (**GPT-5.6 Sol if you have access**, otherwise Terra). Cheaper/faster models miss things; the whole point is catching what the authoring model couldn't.

**Effort default: `high`** (changed from `xhigh` 2026-08-01). The reasoning is cost and review-noise, not capability: a reviewer you skip because it takes 30 minutes catches nothing, and a long tail of cosmetic findings crowds out the real ones. Escalate to `xhigh` for unusually risky PRs — auth, payments, data migrations, anything touching a merge or release gate — and to `max`/Pro above that; see `AI_SETUP_LANES.md`'s Final Review Policy.

**Be honest about the evidence here, because we weren't.** This document previously asserted that "testing showed `xhigh` caught 3 findings that `high` missed on the same content", and framed that setting as beyond question. That line was written 2026-03-26 against **GPT-5.4** — two reviewer generations before GPT-5.6 Sol — with no measurement artifact behind it, and it survived unchallenged for four months. Neither the old default nor the new one rests on a controlled comparison in this repo. If you want the real answer, run both efforts on the same diff and count P0/P1 findings, not total findings.

**Prompt the reviewer for everything, then filter yourself.** Asking a reviewer to "only report high-severity issues" makes it report less, including real defects. Ask for the full list and triage it: act on P0/P1, batch the rest into a note. Getting cosmetic findings back is a signal to filter harder, not to reduce reasoning effort.

**Before requesting review, run `shellcheck` on any new or modified `.sh` file** (`shellcheck -s bash <files>`). This closes a real gap this repo hit directly (2026-07-21): a merge-safety-gate PR whose own tests had each been watched failing still passed cleanly, yet Codex's own review still caught bugs `shellcheck` would have flagged for free — including the classic `if [ $? -ne 0 ]` anti-pattern (SC2181), which is fragile against a line accidentally inserted between the command and the check. Mutation testing only proves your tests catch *deliberately broken variants you thought to try* — it can't catch a whole class of mechanical bugs a static analyzer finds instantly. Fix findings before submitting to Codex; don't spend a review round on what a free, instant, deterministic tool already tells you.

#### When to stop: the scope rule

Added 2026-08-09 after this repo spent roughly nine hours and twenty review
rounds on a three-line documentation defect, and produced 46 lines of deliverable
against 2,066 lines of review-generated machinery. Both reviewers were asked
independently what went wrong; they converged, and the rules below are theirs.
The Codex post-mortem is archived at `.reviews/postmortem-codex.md`; the Fable
leg was conducted in-session and is not archived, so "they converged" is
corroborated for one leg and reported in good faith for the other.

**The failure mode has a name: the review loop never promises to terminate.**
Every round found a real defect, so every round justified the next one. Findings
being *real* is not evidence that continuing is *right*.

Two things made it inevitable. First, the invariant silently escalated — from
"no wrong figure on a config a user would actually write" to "no false claim of
any kind, on any input, constructed or not." Nothing satisfies the second
version, so every round was **guaranteed** a finding and the reviewer's job
turned generative rather than verificational. Second, the findings changed
address: after a certain round, every blocker lived at a line *the PR itself had
created*. That is the loop consuming its own output, and it reads exactly like
convergence from the inside.

**SCOPE RULE.** One review and one verify per frozen scope — and verify
reads only the diff since the last verdict.

<!-- CANONICAL:evidence-exception-bound -->
**After those two passes, continue ONLY when the
immediately preceding COMPLETED pass recorded either (a) an open P0/P1 showing a
requested behavior is currently wrong, or (b) the FIRST verification-evidence
invalidation in this root task.** An evidence-only finding authorizes exactly one
additional pass per root task; a later evidence-only finding is filed.
Otherwise STOP.
<!-- /CANONICAL:evidence-exception-bound -->

This block is the single source of truth for the evidence-exception bound
(#608). It is matched EXACTLY by `tests/test-evidence-exception-bound.sh` —
nothing may be added inside the markers, because a contradiction added beside
the rule would otherwise pass a containment check. State the bound here ONLY;
every other mention of it in this document carries
`[bound: CANONICAL:evidence-exception-bound]` so a reader can reach this block.

Below-bar and out-of-scope findings are filed and authorize nothing. A fix to the deliverable creates a new SHA and must be verified;
a pass that found such a defect is not clean, whoever introduced it — including
the loop itself. And do not prompt a reviewer to "find the next route" or
"defeat the new guard": asking for a fresh category biases review toward
producing one, which holds the finding count above zero long after the
deliverable has converged. *(#588/PR #598 reached 22 review attempts under the
older wording, which called itself accounting and left termination to the
driver. The last shipped defect it found was introduced by its own previous
fix.)* A fix that adds code or promises
beyond the reviewed diff is *new scope*: it requires a continue/stop decision
from the planner (a role, not a fourth model — defined under "Why four layers
didn't catch it"), recorded in `.reviews/handoff.json` under `"scope_decisions"`
before the pass runs, carrying the builder's cost line (diff size vs defect
size, passes used). The decision may well be "continue" — the teeth are
attribution, not prohibition. Escalate to a human **only** when the two models
disagree; a rule that wakes the maintainer on every third round has just made
them the round-limiter.

**The budget is counted per ROOT TASK, and the count never resets.** "Frozen
scope" is redefinable — re-freeze after every fix and two-passes-per-scope
silently becomes unlimited, which is how #520 reached 20 rounds on 46 lines and
#476 reached six on twenty doc lines. So the artifact pins the root once and
accumulates against it: record `root_task` (the verbatim request) and `base_sha`
at the start, let the pass count carry across every re-freeze, and have new
scopes **append** child records to `scope_decisions` rather than replace them. A
cumulative count that gets overwritten on re-freeze is not cumulative.

This is accounting, and the stop condition above is the cap. Continuing past
it is not the driver's call to make silently: it requires the recorded
continue/stop decision, and the migration guidance below is bounded by the same
condition rather than exempt from it. What the rule
removes is the ability to *lose* the count by renaming the scope.

**BLAME THE LINE.** A review finds a bug. One question decides what to do:
**did the issue ask for this code?**

- **Yes → fix the bug.** Always, however late in the loop it surfaces.
- **No → delete the code.** The bug goes with it. Repairing code nobody asked
  for is what generates the next round.

`git blame` is how you answer it, not the answer itself. Blame the blocker
against the **frozen-scope SHA** — `handoff.json`'s `frozen_scope_sha`, written
on the *first* verdict of a scope whether that verdict is YES or NO, and **never
overwritten**. It is deliberately not `commit_sha`: that field is written only on
CERTIFIED and is rewritten by each later certification, so after an initial NO it
does not exist, and after a later YES it no longer points at the boundary. Two
fields, two jobs — `commit_sha` says *what was certified*, `frozen_scope_sha`
says *where this scope began*. Lines older than it are the work you set out to
do. Lines newer than it exist because a review round asked for them, so they are
the ones to check against the allowlist. Do **not** blame against the PR base:
everything you meant to build is also PR-born, and cutting on that test deletes
the deliverable. Where the two disagree, the allowlist wins — birth time is
evidence, being asked for is the test. Before the first verdict there is no
frozen-scope SHA and this rule is silent; it is a stopping rule, not an entry
rule.

**REVIEW UNIT.** Review committed, immutable increments — never a mutable
working tree. Approval attaches to a SHA. Approval is a decision to ship at
accountable-good-enough, *not* a proof of zero defects. Reviewing a live tree
cost this repo an entire round: a background harness mutated a file mid-read and
the reviewer filed a correct, detailed diagnosis of a defect that existed only in
that mutation.

**CLOSED ALLOWLIST.** The issue's requested behaviors are the whole job. **The authority split is not negotiable: the planner may authorise more *process* within the allowlist; only the user may expand the *objective*.** Do not
add runtime behavior, enforcement, automation, computed output, or new mechanisms
unless they were asked for. Review findings may correct allowed work; they may
never *expand* the allowlist. If expansion looks necessary, stop and ask.
When there is no written issue, the allowlist is the requester's task **as
restated back to them and left unchallenged before work starts** — the "restate
the task in your own words" step of the checklist is what creates it. An
allowlist that was never written down is not a small allowlist; it is an absent
one, and every rule in this section that references "the requested behaviors"
is inoperative until it exists.

**CLAIM RULE.** Before code prints a value computed from parsed input, write down
the input domain over which that figure is promised correct; out-of-domain input
must produce no claim at all. If you cannot enumerate or fuzz that domain today,
print the inputs and let the reader compute. **Scope is measured in promises, not
lines.** A static claim checked once against a pinned version has an enumerable
domain; a runtime computation over arbitrary user files signs an unbounded one.

**EXISTENCE RULE.** A guard, monitor, or fix does not exist until it has been
observed producing **both** outcomes on live input — firing where it must, and
staying silent where it must not. Every guard ships with a negative fixture.
RED proves a guard fires and is structurally silent on whether it *overfires*,
and defensive guards are mostly negative obligation. This repo shipped a guard
behind 207 green tests whose pattern matched ordinary values like `issue4522`,
suppressing a figure that was correct. One negative fixture is a regression pin,
not a proof — for unbounded domains the load-bearing verification is the closure
argument plus fuzzing of the negative space.

**PROCESS BUDGET prices the promise, not felt confidence.** Confidence is
exactly how the original defect shipped: someone confidently recommended a config
whose two knobs multiplied. Price the change before review by one question —
*does your observation cover the domain the change promises over?* — and apply
the first row that matches, top to bottom:

| The change | Process |
|---|---|
| makes **no new promise** (typo, comment, restating a verified fact) | ship — log the skip. File location is irrelevant: a comment fix in auth code is not an auth change |
| promises behavior in a **High-Stakes domain** — auth, payments, data handling, or the release/publish act itself | full gate, regardless of what you watched: one observed run covers one input, in a domain defined by the inputs you didn't pick |
| makes a promise you **watched hold over its whole domain** — enumerable, and written down (see CLAIM RULE) | ship — observation replaces review |
| makes a promise you are **predicting**, over a domain you can still observe *after* shipping — deferred effects, interacting settings, environments you didn't run but do have logs and a rollback for | one cross-model fact-check pass |
| makes a promise you can **never observe** — executes on machines you don't monitor, or over unbounded inputs | full gate |

Two boundary rulings, decided here so no reader has to arbitrate them. "High-Stakes:
releases" means the act of tagging and publishing, **not** every change that later
rides in a release — read it the second way and every row collapses into full
gate, which prices nothing. Server-side code on your own machines serving other
people's traffic is *observable* — your logs, your rollback — so it is not the
unobservable row; it prices as watched or predicted unless its promise is
High-Stakes.

This retro-dicts the incident correctly: the autocompact recommendation was a
*predicted* interaction between two knobs, so one cross-model fact-check pass —
which is exactly what would have caught it. The known failure input is a
mis-written domain: a "typo fix" that changes a figure consumers act on. Two
tripwires, one each way. Before: the ship rows are only available with a
one-line written domain statement (see CLAIM RULE) — can't write it, can't claim
the row. After: a defect shipped from a ship-priced change reprices that change
class one row stricter, permanently, recorded in the post-mortem.

#### Why four layers didn't catch it

The chain was planner → builder → self-review → cross-model gate, and a
three-line fix still took eight hours. Every layer's contract is
correctness-shaped: **every layer is rewarded for finding things, and no layer is
rewarded for saying "this is now bigger than the bug."** Worse, the layers
amplify — each finding becomes the builder's new obligation, and each gate sees
only the current tree, never the cumulative bill.

**The planner owns proportionality.** Not the builder: the builder's reward
gradient is "satisfy the reviewer," which is the force that grows scope. But the
builder holds the real-time view, so it carries the sensor:

- The **builder** attaches a cost line to every review request — diff size vs
  defect size, passes used, hours.
- The **planner** records continue/stop before any third pass or scope growth,
  as an entry in `.reviews/handoff.json` under a top-level `"scope_decisions"`
  array: `{"round": N, "decision": "continue|stop", "cost": "<diff lines> vs
  <defect lines>, <passes> passes", "blame": "requested|unrequested", "by":
  "<role/model>"}`. A missing entry for the pass about to run blocks the round —
  checkable with `cat .reviews/handoff.json`, no new tooling. Every "continue"
  carries a name: the `"by"` field.

**"Planner" is a role, not a fourth model.** It is whoever owns the plan: Setup
C's Opus plan mode, or the driver itself under Setups A and B. Under a single
driver this is self-authorization on purpose — the incident mechanism was
invisibility, not missing authority, and the teeth are attribution, not
prohibition. The record is ratified downstream: the next reviewer pass reads
`scope_decisions` and may reject the continue rationale, which stops the loop;
if the recorded continue is the final pass, the merge-step clearance legs read
it, and an unjustified continue is a blocking finding there. The human is
consulted only when the two models disagree about the record. **Do not build a
hook to check this file** — reviewers reading it *is* the check, and automating
it inside the PR that names objective substitution would be objective
substitution.

In the incident that produced these rules, the ratio was **45:1** — 46 lines of
deliverable against 2,066 lines of machinery nobody asked for — and it was never
written down anywhere until the post-mortem. That is why nothing fired.

#### The mechanism behind the creep

Name it so you can catch yourself doing it: **objective substitution.** The agent
replaces the requested objective ("change this guidance") with a more *measurable*
one ("make this guidance mechanically enforceable"), because a doc sentence
cannot be proven correct while a hook with 207 green tests feels like it can.
Every subsequent review finding then creates more machinery.

"Keep it simple" and "don't over-engineer" do not prevent this — they are taste
rules with no trigger, evaluated against a solution shape that is already being
written. The rules above bind because each names a **trigger** and an
**observable**.

**Prerequisites:**
- Codex CLI installed: `npm i -g @openai/codex`
- OpenAI API key configured: `export OPENAI_API_KEY=...`
- Codex CLI picks up your OpenAI account's best available model automatically. If you have GPT-5.6 Sol access, `codex exec` uses it; otherwise it falls back to Terra. No config change needed on your side.
- This is a local workflow tool — not required for CI/CD

**The Protocol:**

1. Create a `.reviews/` directory in your project
2. After Claude completes its SDLC loop, write a preflight doc (what you already checked) then a mission-first handoff file:

```jsonc
// .reviews/handoff.json
{
  "review_id": "feature-xyz-001",
  "status": "PENDING_REVIEW",
  "round": 1,
  "branch": "feat/xyz",
  "mission": "What changed and why — context for the reviewer",
  "success": "What 'correctly reviewed' looks like",
  "failure": "What gets missed if the reviewer is superficial",
  "files_changed": ["src/auth.ts", "tests/auth.test.ts"],
  "verification_checklist": [
    "(a) Verify input validation at auth.ts:45",
    "(b) Verify test covers null-token edge case"
  ],
  "review_instructions": "Focus on security and edge cases. Assume bugs may be present until proven otherwise.",
  "preflight_path": ".reviews/preflight-feature-xyz-001.md",
  "artifact_path": ".reviews/feature-xyz-001/",
  "pr_number": 205
}
```

The `mission/success/failure` fields give the reviewer context. Without them, you get generic "looks good" feedback. With them, reviewers dig into source files and verify specific claims. The `verification_checklist` tells the reviewer exactly what to verify — not "review this" but specific items with file:line references.

`branch` is the branch the round's work sits on (`git symbolic-ref --short HEAD`). It is what lets an in-flight round commit at all — see the dialogue loop below.

`pr_number` (optional) is the PreCompact self-heal opt-in (ROADMAP #209). Set it when the review tracks a specific PR — the `precompact-seam-check.sh` hook queries `gh pr view N --json state` on every manual `/compact` and treats MERGED as implicit CERTIFIED, so a forgotten PENDING handoff doesn't lock you out of compaction after the PR ships. Omit for ad-hoc reviews not tied to a PR.

3. Run the independent reviewer (Round 1 — full review). These commands use your Codex default model — configure it to the latest, most capable model available:

```bash
codex exec \
  -c 'model_reasoning_effort="high"' \
  -s danger-full-access \
  -o .reviews/latest-review.md \
  "You are an independent code reviewer. Read .reviews/handoff.json, \
   review the listed files. Output each finding with: an ID (1, 2, ...), \
   severity (P0/P1/P2/P3, graded by impact if it shipped), description, and \
   a 'certify condition' stating what specific change would resolve it. \
   Then give an architecture verdict for the change as a whole: \
   SOUND, CONCERN, or WRONG SHAPE. \
   End with CERTIFIED or NOT CERTIFIED." \
  < /dev/null
```

> **Always append `< /dev/null`** to `codex exec` calls run from background, hooks, CI, or any non-interactive parent. Without it, codex blocks on stdin reads even when the prompt is given as an argument — the process sits at S/0% CPU indefinitely with a 0-byte `-o` output file. Validated on codex-cli 0.130.0 / macOS 14, 2026-05-15. For live progress visibility, wrap the call so it prints heartbeats (maintainer tooling `scripts/codex-review-with-progress.sh` in this repo is NOT installed by the wizard).

> **Always launch codex via `run_in_background: true` on the Bash tool.** The Bash tool clamps `timeout` to 600000 ms (10 min) regardless of the value passed, and force-kills the foreground process at that wall. Multi-artifact bundle reviews (release reviews per the checklist below, multi-finding rechecks, etc.) routinely run 6–30 minutes — they need background mode to complete. **A progress wrapper does not save you here.** The maintainer tooling `scripts/codex-review-with-progress.sh` in this repo, which is NOT installed by the wizard, prints elapsed-time heartbeats and forwards signals to its child, but it has **no stall watchdog and no timeout** — it loops on `kill -0` until codex exits on its own, however long that takes. This paragraph claimed a 30-minute stall watchdog for months, naming a tunable that has never existed in this repo; the claim survived because nothing checked that a named mechanism was real (GH #491). Nothing bounds a hung review except you noticing and killing it. A foreground call killed mid-review plus the Stop-hook re-invocation loop can burn 60+ minutes of session compute on what should be a single 7-minute run (issue #364, 2026-05-27 incident). The general rule: **any long-running wrapper invoked through the CC Bash tool — codex, slow builds, long test suites — should use `run_in_background: true` unconditionally, then be actively watched — no wrapper in this repo enforces a timeout on your behalf.**

> **Never also append a trailing `&` inside the command string when using `run_in_background: true`.** These are two different backgrounding mechanisms — the Bash tool's own `run_in_background` flag, and the shell's native job-control `&` — and combining them double-backgrounds the process: the "completed" notification fires for the outer wrapper shell exiting immediately, not for the actual `codex exec` process, which is still running detached and unmonitored. This produces a convincing but false "review complete" signal — the transcript looks done, but no verdict has actually been written yet. Confirm real completion independently (e.g. `ps aux | grep codex`) before trusting a background-task notification that arrived suspiciously fast for a multi-minute review. Use `run_in_background: true` alone; never both.

4. **On the first verdict of a scope, whichever way it goes** → write `"frozen_scope_sha": "<git rev-parse HEAD>"` into `handoff.json`, and never overwrite it while the scope stays frozen. This is the boundary BLAME THE LINE measures against; it must survive an initial NO, so it cannot be `commit_sha`. Then: if CERTIFIED → **also write `"commit_sha": "<git rev-parse HEAD>"`** — `hooks/codex-gate-check.sh` (ROADMAP #437) blocks a commit if this is missing or doesn't match current HEAD, so a bare `CERTIFIED` status isn't enough. That is pass one of two: run the verify pass, which reads only the diff since this verdict. If NOT CERTIFIED → enter the dialogue loop.

**The Dialogue Loop (Round 2+):**

Instead of silently fixing everything and resubmitting for another full review, respond to each finding:

```jsonc
// .reviews/response.json
{
  "review_id": "feature-xyz-001",
  "round": 2,
  "responding_to": ".reviews/latest-review.md",
  "responses": [
    {
      "finding": "1",
      "action": "FIXED",
      "summary": "Added missing mocking table to SKILL.md",
      "evidence": "git diff shows table at SKILL.md:195-210"
    },
    {
      "finding": "2",
      "action": "DISPUTED",
      "justification": "The upgrade path cleanup runs in init.js:205. Verified with test-cli.sh test 29.",
      "evidence": "tests/test-cli.sh:583-600"
    },
    {
      "finding": "3",
      "action": "ACCEPTED",
      "summary": "Will add EVAL_PROMPT_VERSION bump"
    }
  ]
}
```

Three response types:
- **FIXED**: "I fixed this. Here is what changed." Reviewer verifies the fix.
- **DISPUTED**: "This is intentional/incorrect. Here is why." Reviewer accepts or rejects the reasoning.
- **ACCEPTED**: "You are right. Fixing now." (Same outcome as FIXED, used when batching fixes.)

Then update `handoff.json` to `"status": "PENDING_RECHECK"`, increment `round`, add `"response_path"` and `"previous_review"` fields, and write `"branch": "<git symbolic-ref --short HEAD>"`. Run a targeted recheck:

> **Why `branch` is not optional (ROADMAP #533).** `hooks/codex-gate-check.sh` used to accept only `CERTIFIED`/`REVIEWED`, so the status the protocol mandates for a whole dialogue round could not commit — every round was forced onto an uncommitted working tree, which is the mutable tree the "review committed increments" rule exists to avoid. It cost a real round: a reviewer read a tree that a concurrent harness had mutated and filed a correct P1 against a defect that existed only in that mutation. The gate now lets a `PENDING_RECHECK` round commit **on the branch it declares here** — so a round that declares nothing still cannot save its work. The hook deliberately does not try to work out whether you are on the default branch: that is server-side state, and `refs/remotes/*/HEAD` is a cache with no freshness bound. The round already knows which branch it is about.

```bash
codex exec \
  -c 'model_reasoning_effort="high"' \
  -s danger-full-access \
  -o .reviews/latest-review.md \
  "You are doing a TARGETED RECHECK. First read .reviews/handoff.json \
   to find the previous_review path — read that file for the original \
   findings and certify conditions. Then read .reviews/response.json \
   for the author's responses. For each: \
   FIXED → verify the fix against the original certify condition. \
   DISPUTED → evaluate the justification (ACCEPT if sound, REJECT if not). \
   ACCEPTED → verify it was applied. \
   Do NOT expand the review surface. Report every defect you find, at any severity. A finding BLOCKS only when it is P0 or P1 AND it shows a REQUESTED behavior is incorrect — and a finding that shows a requested behavior is incorrect IS P1, whatever label it arrived with. Anything outside the requested behaviors is reported as a linked follow-up, never a blocker. Lesser observations go in 'Notes for next review' (non-blocking). \
   End with CERTIFIED or NOT CERTIFIED." \
  < /dev/null
```

**The key constraint:** Rechecks are scoped to previous findings only — a reviewer should not go hunting for unrelated new material during a recheck round, which is how a 3-round review becomes an 11-round one.

**But scoped does not mean muzzled — and not everything it sees may block.** A recheck reports every defect it finds, at any severity. What **blocks** is bounded by the closed allowlist: a finding blocks when it shows a **requested** behavior is incorrect. A finding outside the requested behaviors is reported and becomes a linked follow-up issue, not a certification blocker. Certification means *zero unresolved findings against the requested behaviors*, not *zero findings raised after round 1* — and not *zero defects anywhere*, which is unsatisfiable and is the shape that turned #520 into 20 rounds. Report-everything and block-on-scope are different questions; conflating them is how an invariant escalates. What the scoping rule actually forbids is expanding the review's *surface*, not silencing what the reviewer sees.

**This is the blocking rule stated from the recheck's side.** A finding that shows a requested behavior is wrong means the thing does not work, so it is P1 — no matter who labelled it P2, or when it appeared. Grade by impact and the rule needs no exception.

**Convergence:** the default is **one review and one verify per frozen scope, counted cumulatively per root task, then STOP** (see "When to stop" above for the two findings that authorize a further pass). **There is no fixed round cap.** This section previously carried a max-3-rechecks heuristic; it is deleted rather than subordinated, because a stated ceiling gets read as an allowance and #598 reached 22 attempts with one in place. If still NOT CERTIFIED after the budget, that is a **recorded continue/stop decision**, not an automatic escalation — see the Exception below for where the decision is written. A human is woken only when the two reviewers disagree, or a non-waivable gate has failed twice. Never ship uncertified; but running out of budget is not by itself a reason to interrupt the maintainer.

**Exception — known-large migrations, and it costs a recorded decision.** The round-count heuristic is not the cap — the stop condition above is — but "every round is still finding something real" is precisely what a self-consuming loop reports about itself, so it is **not** a licence the builder may grant itself. Each round past the budget requires a continue/stop entry in `.reviews/handoff.json` `"scope_decisions"` **recorded before the round runs** (entry shape and the planner role: "Why four layers didn't catch it" above), carrying the cost line and a `git blame` of the last blocker against the frozen-scope SHA; a blocker in code the issue never asked for is not a reason to continue. With that decision on record, a migration may run long — but the authorization is per-round and comes from the stop condition, not from the migration label: each further round needs the immediately preceding COMPLETED pass to have recorded an open P0/P1 against a requested behavior. "Every round is still finding something real" is that same test stated loosely; state it exactly, because a loop consuming its own churn reports the loose version about itself. An evidence-only finding buys one extra pass per root task and no more [bound: CANONICAL:evidence-exception-bound]. (Source: v1.84.0 release review — a repo-wide model-recommendation migration ran 11 rounds, each finding something real; round 8 found a mandatory-reading claude-setup-wizard template whose tutorial hook code had silently drifted from the real shipped hook (broken, non-blocking), more consequential than anything in rounds 1-3. Escalating at round 4 per the default heuristic would have shipped that bug. 2026-07-04.)

**CERTIFIED is not the finish line.** A CERTIFIED verdict and a green CI run are different verification layers that catch different bug classes — a CERTIFIED review does not substitute for actually pushing and watching CI. Confirmed on the same v1.84.0 release: after round-11 CERTIFIED and a full local test sweep, real CI still caught 3 more genuine bugs the review never touched — a content regression in an unrelated section silently dropped by an earlier edit (caught by a pre-existing local test that simply hadn't been re-run since), an environment-specific CLI output-format change invisible to any local run against an older tool version, and a new test file committed without the executable bit (passes every local `bash tests/foo.sh` invocation, only fails when CI runs it as `./tests/foo.sh`). Budget for at least one more fix-push-recheck cycle after CERTIFIED, and don't treat CERTIFIED as license to skip reading the actual CI logs — see the CI Feedback Loop section below.

```
Claude writes code → handoff.json (round 1)
    ↑                                          |
    |                                          v
    |                              Reviewer: FULL REVIEW
    |                              (structured findings with IDs)
    |                                          |
    |                              CERTIFIED? -+→ YES → write commit_sha → verify pass
    |                                          |
    |                                          +→ NO (findings)
    |                                          |
    |                              Claude writes response.json:
    |                                FIXED / DISPUTED / ACCEPTED
    |                                          |
    |                              Reviewer: TARGETED RECHECK
    |                          (scoped surface; a new finding blocks only
    |                           if P0/P1 AND a REQUESTED behavior is wrong)
    |                                          |
    |                              All resolved? → YES → CERTIFIED (write commit_sha)
    |                                          |
    └────────── Fix rejected items ←───────────┘
     (one review + one verify per frozen scope, counted per root task, then STOP;
      past that, a recorded decision. The SCOPE RULE above is the authority on
      when a further pass is allowed — this caption does not restate it.)
```

**Every CERTIFIED path above writes `"commit_sha": "<git rev-parse HEAD>"` into `handoff.json`** — `hooks/codex-gate-check.sh` (ROADMAP #437) treats a missing or mismatched SHA as a stale certification, so a bare `CERTIFIED` status string is never enough on its own.

**Key flags:**
- `-c 'model_reasoning_effort="high"'` — the reviewer effort default as of 2026-08-01, chosen for cost and review-noise rather than capability. Escalate to `xhigh` for unusually risky PRs. This flag previously defaulted to `xhigh` on the strength of a claim that "testing showed `xhigh` caught 3 findings that `high` missed" — written 2026-03-26 against GPT-5.4, with no measurement artifact. Neither setting has a controlled comparison in this repo; see the effort discussion in the Cross-Model Review section.
- `-s danger-full-access` — Full filesystem read/write so the reviewer can read your actual code.
- `-o .reviews/latest-review.md` — Save the review output for Claude to read back.
- **Claude Code sandbox bypass required:** Codex's Rust binary needs access to macOS system configuration APIs (`SCDynamicStore`) during initialization. Claude Code's sandbox blocks this, causing `codex exec` to crash with `panicked: Attempted to create a NULL object`. When running from within Claude Code, use `dangerouslyDisableSandbox: true` on the Bash tool call. This only bypasses CC's sandbox for the Codex process — Codex's own sandbox (`-s danger-full-access`) still applies. Known issue: [openai/codex#15640](https://github.com/openai/codex/issues/5914).

**Tool-agnostic principle:** The core idea is "use a different model as an independent reviewer." Codex CLI is the concrete example today, but any competing AI tool that can read files and produce structured feedback works. The value comes from the independence and different training, not the specific tool.

**When to use this:**
- High-stakes changes (auth, payments, data handling)
- **Releases and publishes** (version bumps, CHANGELOG, npm publish) — see Release Review Focus below
- Research-heavy work where accuracy matters more than speed
- Complex refactors touching many files
- Any time you want higher confidence before merging

**When to skip:**
- Trivial changes (typo fixes, config tweaks)
- Time-sensitive hotfixes
- Changes where the review cost exceeds the risk

#### Release Review Focus

Before any release or npm publish, add these focus areas to the cross-model `review_instructions`:

**Why:** Self-review and automated tests regularly miss release-specific inconsistencies. Evidence: v1.20.0 cross-model review caught 2 real issues (CHANGELOG section lost during consolidation, stale hardcoded version examples) that passed all tests and self-review.

| Check | What to Look For | Example Failure |
|-------|-------------------|-----------------|
| CHANGELOG consistency | All sections present, no lost entries during consolidation | v1.19.0 section dropped when merging into v1.20.0 |
| Version parity | package.json, SDLC.md, CHANGELOG, wizard metadata all match | SDLC.md says 1.19.0 but package.json says 1.20.0 |
| Stale examples | Hardcoded version strings in docs/wizard match current release | Wizard examples showing v1.15.0 when publishing v1.20.0 |
| Docs accuracy | README, ARCHITECTURE.md reflect current feature set | "8 workflows" when there are actually 7 |
| CLI-distributed file parity | Live skills, hooks, settings match CLI templates | SKILL.md edited but cli/templates/ not updated |
| Policy Migration Inventory | A repo-wide blanket-recommendation migration (changing a default model, effort, or policy) — enumerate EVERY surface stating the old value before round 1 | v1.84.0 ran 11 rounds because each round surfaced a new uninventoried surface: skill frontmatter, then setup wizard, then a live hook, then tutorial templates |

**Example `review_instructions` for releases:**
```
Review for release consistency: CHANGELOG completeness (no lost sections),
version parity across package.json/SDLC.md/CHANGELOG/wizard metadata,
stale hardcoded versions in examples, docs accuracy vs actual features,
CLI-distributed file parity (skills, hooks, settings).
```

**This complements automated tests, not replaces them.** Tests catch exact version mismatches (e.g., `test_package_version_matches_changelog`). Cross-model review catches semantic issues tests cannot — a section silently dropped, examples using outdated but syntactically valid versions, docs describing features that no longer exist.

#### Anti-patterns

- **"Find at least N problems"** — incentivizes false positives. The reviewer will manufacture findings to hit the count.
- **"Review this"** — too vague. Always pair with `verification_checklist` items that name file:line evidence to verify.
- **1-10 score with no criteria** — every reviewer scores differently. Either define what 1, 5, 10 mean for *this* review, or drop the score and just produce CERTIFIED / NOT CERTIFIED with findings.
- **Author reasoning visible to reviewer** — anchoring bias. The reviewer should see code + handoff, not the author's self-assessment of why it's correct.

#### Multiple reviewers (Claude review + Codex + human)

Run them in parallel; collect feedback via `gh api repos/OWNER/REPO/pulls/PR/comments` (single source of truth). Respond per-reviewer (different blind spots — don't merge feedback). On a conflict between two model reviewers, cross-feed their positions verbatim and let them reconcile — you relay, you do not pick a winner. A human-vs-model split goes to the human as one question. Termination is the cumulative stop rule (#539) applied per root task — not a per-reviewer iteration cap.

#### Non-code domains (research, persuasion, medical content)

Same handoff format. Adapt `review_instructions` (e.g. "verify each cited claim links to a primary source") and `verification_checklist` (specific claim → specific source). Add `"audience"` and `"stakes"` keys to the JSON so the reviewer knows what reading level / risk profile to apply.

#### Parallel Blind Dual Review

When two models review the same change, **run them in parallel and blind to each other, then merge the findings**. Do not chain them.

**The rule:** neither reviewer sees the other's output, or your own responses to it, until both have reported. Give each the same diff, the same preflight, and the same instruction to attack. Then merge: treat any finding either one raises as real until disproved.

**Why blindness, not just plurality.** A second reviewer shown the first's findings is *anchored* — it tends to confirm, refine, and extend what it was given rather than look where nobody has looked. You pay for two reviews and get one review plus a proofread. Measured on this repo 2026-07-27, across a four-round review of the merge gate: the **parallel blind** round produced findings that barely overlapped — one model found parsing and encoding defects, the other found a case-sensitivity hole that let a protected path merge clean, plus a policy-document regression neither the author nor the first model noticed. The **sequenced** rounds overlapped heavily by comparison. Both models independently found things that would have shipped otherwise.

**Give both reviewers the SAME contract.** Same diff, same preflight, same severity scale, same fix policy — otherwise you cannot merge their findings or compare their verdicts, and you will not notice when one is grading on a different curve. Measured here 2026-07-29: one reviewer was given P0-P3 and the other HIGH/MEDIUM/LOW on the same change, which made two genuine reviews look like disagreement.

**The review bar is the issue's acceptance criteria, verbatim.** A stricter criterion you invent while writing your own review prompt is self-inflicted scope, and it is invisible because it looks like rigour. *(#553: two rounds spent on a bar #530's acceptance never contained, retired only by a zero-diff dispute.)*

**Grade severity by impact if it shipped.** Not by how hard the fix is. Not by which round found it. Either one gets gamed — a late finding inflated to buy another round, or deflated to close one out.

This is also what lets P2 stop being a merge blocker without letting real defects through. A defect that means the thing does not work is P1, whatever round surfaced it.

| Severity | Meaning | Action |
|---|---|---|
| P0 | Stop the world — prod broken, data loss, secret leaked | **Preempts the current task.** |
| P1 | This PR does not merge: it doesn't work, or it breaks something that did | **Against a requested behavior: fix before merge, restarts the cycle. Outside the allowlist: linked follow-up issue.** |
| P2 | Real, should fix, ships fine without it | Fix in this PR **only** if the diff is small and the file is already touched. Otherwise a linked issue |
| P3 | Correctness or accuracy nit — a stale comment, an unclear message | Fix if cheap and it is about being *right* |
| P3 (style) | Preference, naming, formatting with no correctness content | **Not review's job — encode it as a lint rule instead.** |

**A finding blocks only if it is P0 or P1 and inside the issue's scope card.** An earlier revision of this table made P2 blocking, after an in-scope defect was waved through. The fix for that was the severity rule above, not a blocking P2 — the defect did not work, so it was P1.

**Ask a second question, separate from the defect list: is this the right way to build it?** Should this code exist? Is it proportionate? The reviewer returns **SOUND**, **CONCERN** (ship it, here is the debt), or **WRONG SHAPE** (stop, redesign).

No severity level says "this should not exist", so nobody says it. On #539 all seven findings across four rounds were legitimate P1s — the guard really was broken — and the right answer was that the guard should never have been written. It was deleted at round four. WRONG SHAPE ends that at round one.

**File anything outside the scope card as a GitHub issue. Never build it in the current PR.** This binds reviewers on the same terms as the driver: an out-of-card finding gets reported and filed, and does not block certification. Without it the card describes a boundary nothing enforces, and growth is invisible because there is nothing to compare against. *(#520: 20 rounds, 46 lines.)*

**Style findings become lint rules, not review findings.** A cross-model round is expensive, slow, and non-deterministic; a linter is free, instant and total. If a reviewer raises a style point worth honouring, the fix is not "change this line" — it is *add the rule so nothing can ever violate it again*, then let the linter enforce it in every repo that installs this. That converts a recurring review cost into a one-time one. Run the linters **before** requesting review (`shellcheck -s bash` on changed `.sh` files, plus whatever your language uses) so no reviewer round is spent on what a deterministic tool already reports. Review exists for **correctness** — behaviour, security, and whether the tests actually test anything. If you find yourself lacking a standard rather than lacking a fix, the deliverable is the rule.

Tell both reviewers this in the prompt, and tell them explicitly: **do not manufacture findings to appear thorough — "I found nothing real" is a valid and useful answer.** Without that instruction a reviewer under pressure to produce will generate P3s indefinitely, and you will mistake its output for unfinished work.

**Diminishing returns — how to actually tell.** Judge by the *maximum severity per round*, never by finding count: count rises when a reviewer looks somewhere new, which is the opposite of a stopping signal (the round that found the most here also found the most serious bugs). You are converged when the LAST COMPLETED pass produced nothing above P3 against a requested behavior, and no evidence-only exception remains unspent [bound: CANONICAL:evidence-exception-bound] — the stop condition, not a second clean round. **A fresh reviewer that has not already cleared this code is a new pass, not a re-run of the last one:** its first look is the pass that has to come back clean, because one reviewer certified at high confidence here immediately before a fresh reviewer found six P1s in the same code. A single reviewer's own trend flattening means only that it has run out of defects *it* can see.

**Merging findings.** Combine, do not intersect. Two independent reviewers agreeing is a strong signal, but a finding raised by only one is the *common* case and is usually the valuable one — that is the entire point of using two. Respond to each reviewer's findings separately, and run the recheck round with each still blind to the other. **Blindness governs finding-generation and recheck only.** Once every reviewer has returned a verdict, reconciliation is a distinct, final phase. Reconcile once, not per round.

### Reconciliation: the reviewers reconcile with each other

**You relay their positions. You never merge their words.** Four phases:

1. **Review blind.** No shared draft, no summary of the other's position. A reviewer who sees the first one confirms and extends it instead of looking somewhere new — you pay for two reviews and get one plus a proofread. Divergence here is the signal.
2. **Cross-feed verbatim.** Pass each the other's position exactly as written. Paraphrase is where a position gets restated into something its author would not sign.
3. **Let them argue.** Each concedes what is right and holds what is wrong with repo-verifiable evidence: a file, a line, a command output. Not an opinion. A concession to a misread is worse than a hold.
4. **They return one position. You report it.** The user sees the settled answer and any surviving split — not two transcripts to referee.

**Why the driver must not merge.** You are the lowest-ranked participant in a review of your own work: the most context, the least independence, and you wrote the thing. Merging two reviewers' words is grading yourself through a paraphrase you control. They outrank you here precisely because they did not write it.

**Deadlock routes by where the position started.** A split that first appeared as a design question or a recorded scope decision belongs to the planner. One that first appeared in a verdict line, a defect list or a recheck response belongs to the reviewer, and the lower verdict applies. If a split spans both, the verdict's surface governs. Only what survives that reaches the human, and it goes as one question rather than two positions.

*Evidence (#561): the adversarial leg opened with four P1 blockers against the planner's spec. The planner conceded all four, retracted a deferral it had defended, then found three more contradictory surfaces the attacker had missed. Neither model produced that list alone. The driver produced none of it.*

**Cost control.** This is not free — each round costs wall-clock and, for a paid API reviewer, real money. Scale it to blast radius:

| Change | Review |
|---|---|
| Live enforcement: CI config, hooks, agent config, the merge mechanism itself | Parallel blind dual review |
| Ordinary application code | One reviewer at the pre-commit gate |
| Docs, roadmap entries, comments that make **no new promise** | Neither |
| Docs that **do** make a promise — guidance a reader will act on, a figure, an interaction between settings | One fact-check pass. #520 was three doc lines and shipped a wrong config recommendation |

This table is blast radius; PROCESS BUDGET is the promise. **Where they disagree, PROCESS BUDGET wins** — it is the newer rule and the one derived from an incident. Blast radius is a useful first cut, but "it's only docs" is exactly the reasoning that shipped the defect these rules exist because of.

**Iterating vs. gating.** Looping with one reviewer while you build is cheap and effective — use the model that does not bill per token if you have one. But that reviewer is no longer independent by the end: it is reading code shaped by its own earlier feedback. So iterate with it freely, then run the **final** gate as a parallel blind round with a *fresh* instance of each model.

**The loop, stated explicitly.** Reviewers returning findings is the normal case, not a setback, and the agent must not stop to ask permission each time. Run this until it terminates:

```
implement  →  fix in-allowlist findings  →  re-review with the ITERATION model
                    ↑                            ↓
                    │                    findings? ──yes──┐
                    │                            │        │
                    └────────────────────────────┼────────┘
                                                 no
                                                 ↓
                                    GATE: fresh parallel blind round
                                                 ↓
                                    findings? ──yes──→ back to the top
                                                 ↓ no
                                            ship it
```

**Rules that make it terminate rather than spin:**

1. **Every finding gets a response before the next round** — FIXED, DISPUTED with reasoning, or ACCEPTED. Never silently drop one.
2. **A dispute is a claim you owe evidence for.** If the reviewer rejects it and offers a concrete alternative, implement the alternative — you asked for an adversary, not an audience.
3. **Any P0/P1 finding *against a requested behavior* restarts the cycle from the top** — one outside the closed allowlist becomes a linked follow-up issue and does not restart anything. A gate round that surfaces a real defect was not a gate round, it was an iteration round. In-allowlist P2/P3-only findings do not block at all — fix them here if the diff is small and the file is already touched, otherwise file them and let the gate return. Either way the gate must eventually return nothing unresolved *against the requested behaviors* — "findings?" in the diagram means any finding against those, and what differs is only whether you re-enter at iteration or at the gate. Findings outside the allowlist are logged as follow-up issues and never gate anything; the unsatisfiable version of this condition — zero defects anywhere — is what turned #520 into 20 rounds.
4. **Fixes need their own verification.** A fix shipped on the strength of "the reviewer suggested it" is unverified code — the reviewer proposed it, nobody has yet shown it works. A test that passes against broken code was never a test.

   **TDD, applied to the fix: RED → GREEN** — where a RED mutation is writable; a meaning-level prose fix gets cross-model re-review instead (see "When TDD RED Applies"). Write the assertion, run it, watch **that specific assertion** fail, then implement and watch it pass. The common miss is observing red at the *suite* level — one assertion fails, the suite is red, you implement, the suite goes green, and any assertion that was green from birth is never noticed.

   **Editing an existing test is the hard case, and the honest answer depends on what it guards.** If it guards a bug you are about to fix, RED is free — the bug exists, so the test fails for the right reason. If it guards behaviour that is **already correct**, **you cannot get RED**: correct code does not fail, and rewriting does not change that. Say so plainly rather than calling the assertion verified — an unverified regression test is exactly how this repo shipped eight that passed against broken code. When an assertion is load-bearing enough to justify it, breaking the behaviour once to watch the test go red is the only mechanism that validates that class; treat it as a deliberate exception, not the routine.

   **Either way, prefer rewriting a suspect test over patching it.** Patching guesses which missing piece mattered; a rewrite from a known-good fixture with exactly one deliberate defect does not have to guess. Measured 2026-07-29/30: one test was found ineffective three separate times and patched twice — the rewrite worked first try.

   **Rewrite rather than patch when:** the test passes where you would expect failure; its fixture is broken in more than one way, so you cannot tell which defect it detects; or it asserts on a substring present in both the pass and the fail message.

   **Prefer executing the real thing over asserting on its source text.** A test that greps a script for the *words* proves the words are present, not that the behaviour works — the failure mode that produced every ineffective test in this repo's history. Run the script against a stub and check the exit code.

5. **Verdict disagreement is expected — take the lower one.** Two reviewers can both be right and score differently: one weights a single unfixed P1 as disqualifying, the other weights overall structure. Do not average them, do not pick the friendlier one, and do not treat the gap as a reason to dismiss either. Ship only when *both* clear your bar.
6. **Two stop conditions, and they are not the same — do not collapse them.** You are **done** when a fresh blind round returns **zero unresolved findings against the requested behaviors** *and* no evidence-only exception remains unspent [bound: CANONICAL:evidence-exception-bound] — the FIRST verification-evidence invalidation in this root task authorizes one more pass even from an otherwise clean round; a later one is filed. Zero unresolved findings is not merely "nothing new", because the same unfixed in-allowlist finding raised again is still an open finding, and it is not "zero defects anywhere", which is unsatisfiable. That is the only condition that permits shipping, and it is not reached on a schedule. You are **stuck** when rounds keep producing findings without converging; past the two-pass budget that is a non-convergence alarm, and it ends in a **recorded continue/stop decision** — never in shipping. It reaches a human only if the two reviewers disagree, or a non-waivable gate has failed twice. **Exception — a large migration may legitimately run past round 4** when each round is still surfacing real, previously-uninventoried surfaces (v1.84.0 ran 11 that way) — each of those rounds still has to be authorized by the preceding pass's open P0/P1 under the stop condition. Judge by whether the finding trend is genuinely converging, and state which of the two you are claiming. An agent that ships because it ran out of rounds has declared victory on a timer.

**Anti-pattern: asking the human to adjudicate each round.** The human sets the bar and decides scope; the models find defects and you fix them. An agent that surfaces every finding for approval has converted an automated gate back into manual review, which is the cost the gate existed to remove.

**If you only have one model available**, run it twice with genuinely different framings — for example once asked to find correctness defects and once asked to prove a specific safety property false — and treat the result as a single review, not two. It is meaningfully better than one pass and meaningfully worse than two models. Do not report it as dual review.

**Do not show reviewers each other's work to "save a round."** That optimisation removes the only property this technique has. This ban covers the finding-generating passes — the initial review and every recheck. It does **not** cover the final reconciliation phase, which runs after all verdicts are in and exists precisely to make the reviewers argue; see "Merging findings" above. Round-saving is the forbidden motive, not contact as such.

#### Multiple Reviewers (N-Reviewer Pipeline)

When multiple reviewers comment on a PR (Claude, Codex, human reviewers), address each reviewer independently:

1. **Read all reviews** — collect feedback from every active reviewer
2. **Respond per-reviewer** — each reviewer has different blind spots. Address each one's findings separately
3. **Do not resolve conflicts yourself** — when two model reviewers disagree, cross-feed their positions verbatim and let them reconcile (see "Reconciliation: the reviewers reconcile with each other"). You relay; you never pick a winner. A human reviewer cannot be put in that loop, so a human-vs-model split goes to the human as one question, and the human decides
4. **Iterate until all approve, bounded by the stop condition** — don't merge until every active reviewer is satisfied, and don't buy that agreement with passes the stop condition does not authorize
5. **One review and one verify per reviewer per frozen scope, then STOP**, counted cumulatively per root task so a re-freeze does not reset it. Continue only when the **immediately preceding COMPLETED pass** recorded either an open P0/P1 showing a requested behavior is currently wrong, or the **FIRST** verification-evidence invalidation in this root task — that exception is worth exactly one additional pass per root task, and a later evidence-only finding is filed [bound: CANONICAL:evidence-exception-bound]. Past that, a recorded continue/stop decision, not a user interrupt

The value of multiple reviewers: different models/humans catch different issues. No single reviewer is sufficient for high-stakes changes.

#### Custom Subagents (`.claude/agents/`)

Claude Code supports custom subagents in `.claude/agents/`. These run as independent subprocesses focused on a single task:

- **`sdlc-reviewer`** — SDLC compliance review (planning, TDD, self-review checks)
- **`ci-debug`** — CI failure diagnosis (reads logs, identifies root cause)
- **`test-writer`** — Quality test writing following TESTING.md philosophies

**Skills vs agents:** Skills guide Claude's behavior for a task type. Agents are independent subprocesses that run autonomously and return results. Use agents when you want parallel work or a fresh context window.

## User Understanding and Periodic Feedback

**During wizard setup and ongoing use:**

### Make Sure User Understands the Process

At key points, Claude should check:
- "Does this workflow make sense to you?"
- "Any parts you'd like to customize or skip?"
- "Questions about how this works?"

**The goal:** User should never be confused about what's happening or why. If they are, stop and clarify.

### This is a Growing Document

Remind users:
- The SDLC is customizable to their needs
- They can try something and change it later
- It's built into the system to evolve over time
- Their feedback makes the process better

### Periodic Check-ins (Minimal, Non-Invasive)

Occasionally (not every task), Claude can ask:
- "Is the SDLC working well for you? Anything causing friction?"
- "Any parts of the process you want to adjust?"

**Keep it minimal.** This is meant to improve the process, not add overhead. If the user seems frustrated or doesn't need it, skip it.

### When Claude Gets Lost

If Claude repeatedly struggles in a codebase area:
- Low confidence is an indicator of a problem
- Might be legacy code, bad docs, or just unfamiliar patterns
- Claude should escalate to a model, then ask, rather than guess wrong
- Better to ask and be right than to assume and create rework

**Don't be afraid to ask questions.** It prevents being wrong. This is a symbiotic relationship - the more interaction, the better both sides get.

---

## Staying Updated (Idempotent Wizard)

**The wizard is designed to be idempotent.** You can run it on new or existing setups - it aims to detect what you have and only add what's missing.

### How to Update

Use the `/claude-update-wizard` skill for a guided, selective update experience:
> `/claude-update-wizard` — full guided update (shows changelog, per-file diff, selective adoption)
> `/claude-update-wizard check-only` — just show what changed, don't apply anything
> `/claude-update-wizard force-all` — apply all updates without per-file approval

Or ask Claude directly:
> "Check for SDLC wizard updates"
> "Update my SDLC setup"

**All of these do the same thing:** Claude checks what's new, shows you, and walks you through only what's missing.

### Update URLs

Claude fetches from these URLs (via WebFetch):

| Resource | URL |
|----------|-----|
| CHANGELOG | `https://raw.githubusercontent.com/BaseInfinity/claude-sdlc-harness/main/CHANGELOG.md` |
| Wizard | `https://raw.githubusercontent.com/BaseInfinity/claude-sdlc-harness/main/CLAUDE_CODE_SDLC_WIZARD.md` |

### What Claude Does (4 Phases)

**Step 1: Read installed version** from `SDLC.md` metadata:
```
<!-- SDLC Harness Version: X.X.X -->
```
If no version comment exists, treat as `0.0.0`.

**Step 2: Fetch CHANGELOG first** from the CHANGELOG URL above. Parse all entries between user's installed version and the latest version. Show the user what changed. If versions match, run the global plugin-registration cleanup (see the `/claude-update-wizard` skill's Step 7.7 — `~/.claude/settings.json` hygiene is independent of file versions and must run even when up-to-date), then say "You're up to date!" and stop.

**Step 3: Fetch full wizard and compare.** For each wizard step, check if the user already has it:

| Component | How Claude Checks | If Missing | If Present |
|-----------|-------------------|------------|------------|
| Plugins | Is it installed? | Prompt to install | Skip (mention you have it) |
| Hooks | Does `.claude/hooks/*.sh` exist? | Create | Compare against latest, offer updates |
| Skills | Does `.claude/skills/*/SKILL.md` exist? | Create | Compare against latest, offer updates |
| Docs | Does `SDLC.md`, `TESTING.md` exist? | Create | Compare against latest, offer updates |
| CLAUDE.md | Does it exist? | Create from template | Never modify (fully custom) |
| Questions | Were answers recorded in SDLC.md? | Ask them | Skip |

**Step 4: Apply changes and bump version.** Walk through only missing/changed pieces (opt-in each). Update `<!-- SDLC Harness Version: X.X.X -->` in SDLC.md to the latest version.

### CHANGELOG Drives the Update Flow

Claude reads the CHANGELOG to show you what's new **before** applying anything. The wizard contains file templates and step registry for the actual apply logic.

- **CHANGELOG** = What changed and why (Claude shows you this first)
- **Wizard** = File templates + step registry (Claude uses this to apply)

### Example: Old User Checking for Updates

```
Claude: "Fetching CHANGELOG to check for updates..."

Your version: X.Y.0
Latest version: X.Z.0

What's new since X.Y.0:
- vX.Z.0: Latest features and improvements
- vX.Y+1.0: Previous version changes
  (... entries from CHANGELOG between your version and latest ...)

Now checking your setup against latest wizard...

✓ Hooks - up to date
✓ Skills - content differs (update available)
✗ step-update-notify - NOT DONE (new in vX.Z.0, optional)

Summary:
- 1 file update available (SDLC skill)
- 1 new optional step

Walk through updates? (y/n)
```

**The key:** Every new thing added to the wizard becomes a trackable "step". Old users automatically get prompted for new steps they haven't done.

### How State is Tracked

Store wizard state in `SDLC.md` as metadata comments (invisible to readers, parseable by Claude):

```markdown
<!-- SDLC Harness Version: 1.99.2 -->
<!-- Setup Date: 2026-01-24 -->
<!-- Completed Steps: step-0.1, step-0.2, step-1, step-2, step-3, step-4, step-5, step-6, step-7, step-8, step-9 -->
<!-- Git Workflow: PRs -->
<!-- Plugins: claude-md-management -->

# SDLC - Development Workflow
...
```

When Claude runs the wizard:
1. Parse the version and completed steps from SDLC.md
2. Fetch CHANGELOG first — show what's new between installed and latest
3. Fetch full wizard, compare against step registry
4. For anything new that isn't marked complete → walk them through it
5. Update the metadata after each step completes

### Wizard Step Registry

Every wizard step has a unique ID for tracking:

| Step ID | Description | Added in Version |
|---------|-------------|------------------|
| `step-0.1` | Required plugins | 1.2.0 |
| `step-0.2` | SDLC core setup | 1.0.0 |
| `step-0.3` | Additional recommendations | 1.2.0 |
| `step-0.4` | Auto-scan | 1.0.0 |
| `step-1` | Confirm/customize | 1.0.0 |
| `step-2` | Directory structure | 1.0.0 |
| `step-3` | settings.json | 1.0.0 |
| `step-4` | Light hook | 1.0.0 |
| `step-5` | TDD hook | 1.0.0 |
| `step-6` | SDLC skill | 1.0.0 |
| `step-8` | CLAUDE.md | 1.0.0 |
| `step-9` | SDLC/TESTING/ARCH docs | 1.0.0 |
| `question-git-workflow` | Git workflow preference | 1.2.0 |
| `step-update-notify` | Optional: CI update notification | 1.13.0 |
| `step-cross-model-review` | Cross-model review (REQUIRED for high-stakes) | 1.16.0 |
| `step-update-wizard` | /claude-update-wizard smart update skill | 1.18.0 |

When checking for updates, Claude compares user's completed steps against this registry.

### How New Wizard Features Work

When we add something new to the wizard:

1. **Add it as a trackable step** with a unique ID
2. **Add it to CHANGELOG** so users know what's new
3. **Old users who run "check for updates":**
   - Claude sees their version is older
   - Claude finds steps that don't exist in their tracking metadata
   - Claude walks them through just those steps
4. **New users:**
   - Go through everything, all steps get marked complete

**This is recursive** - every future wizard update follows the same pattern.

### Why Designed to Be Idempotent?

Like `apt-get install`:
- If package installed → skip
- If package missing → install
- If package outdated → offer update
- Designed to not break existing state

**Intended benefits:**
- **Safe to rerun** - designed to not duplicate or break existing setup
- **One command for everyone** - new users, old users, current users
- **Preserves customizations** - designed to keep your modifications intact
- **Fills gaps** - aims to detect and address what's missing

> Note: Idempotent behavior is a design goal. Cross-stack setup-path E2E testing is tracked in the roadmap.

### What Gets Compared

| Your File | Compared Against | Action |
|-----------|------------------|--------|
| `.claude/hooks/*.sh` | Wizard hook templates | Offer update if differs |
| `.claude/skills/*/SKILL.md` | Wizard skill templates | Offer update if differs |
| `SDLC.md`, `TESTING.md` | Wizard doc templates | Offer update if differs |
| `CLAUDE.md` | NOT compared | Never touch (fully custom) |

### Wizard Update Notification (Optional)

Want to be notified when a new wizard version is available? Add this lightweight GitHub Action to your repo. It checks weekly, costs $0 (no API key), and creates a GitHub Issue when updates exist.

**Setup:**
1. Create `.github/workflows/wizard-update-check.yml`:

```yaml
name: SDLC Harness Update Check

on:
  schedule:
    - cron: '0 10 * * 1'  # Mondays 10 AM UTC
  workflow_dispatch:

permissions:
  issues: write
  contents: read

jobs:
  check-wizard-update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          sparse-checkout: SDLC.md

      - name: Check for wizard updates
        id: check
        run: |
          # Read installed version from SDLC.md metadata
          INSTALLED=$(grep -o 'SDLC Harness Version: [0-9.]*' SDLC.md | grep -o '[0-9.]*' || echo "0.0.0")
          echo "Installed wizard version: $INSTALLED"

          # Fetch latest CHANGELOG
          curl -sL https://raw.githubusercontent.com/BaseInfinity/claude-sdlc-harness/main/CHANGELOG.md -o /tmp/changelog.md

          # Extract latest version (first ## [X.X.X] line)
          LATEST=$(grep -m1 -oE '\[[0-9]+\.[0-9]+\.[0-9]+\]' /tmp/changelog.md | tr -d '[]')
          echo "Latest wizard version: $LATEST"

          if [ "$INSTALLED" = "$LATEST" ]; then
            echo "Up to date"
            echo "needs_update=false" >> "$GITHUB_OUTPUT"
            exit 0
          fi

          echo "Update available: v$INSTALLED -> v$LATEST"
          echo "installed=$INSTALLED" >> "$GITHUB_OUTPUT"
          echo "latest=$LATEST" >> "$GITHUB_OUTPUT"
          echo "needs_update=true" >> "$GITHUB_OUTPUT"

      - name: Extract changelog entries
        if: steps.check.outputs.needs_update == 'true'
        run: |
          python3 -c "
          import re
          text = open('/tmp/changelog.md').read()
          installed = '${{ steps.check.outputs.installed }}'
          sections = re.split(r'^## ', text, flags=re.MULTILINE)
          relevant = []
          for s in sections:
              m = re.match(r'\[(\d+\.\d+\.\d+)\]', s)
              if m:
                  v = m.group(1)
                  if v == installed:
                      break
                  relevant.append('## ' + s)
          with open('/tmp/changes.md', 'w') as f:
              f.write(''.join(relevant))
          "

      - name: Create notification issue
        if: steps.check.outputs.needs_update == 'true'
        env:
          GH_TOKEN: ${{ github.token }}
          INSTALLED: ${{ steps.check.outputs.installed }}
          LATEST: ${{ steps.check.outputs.latest }}
        run: |
          # Ensure wizard-update label exists
          gh label create "wizard-update" --color "0E8A16" --description "SDLC Harness update available" 2>/dev/null || true

          # Skip if open wizard-update issue already exists
          EXISTING=$(gh issue list --label "wizard-update" --state open --json number --jq '.[0].number' 2>/dev/null || echo "")
          if [ -n "$EXISTING" ]; then
            echo "Issue #$EXISTING already open, skipping"
            exit 0
          fi

          # Fallback: if the extract-changelog step was skipped or failed, $CHANGES will
          # contain a plain string so the issue body still makes sense without changelog detail.
          CHANGES=$(cat /tmp/changes.md 2>/dev/null || echo "See CHANGELOG for details.")

          # Note: ISSUE_EOF terminator indentation is intentional — YAML strips the block's
          # base indentation, leaving ISSUE_EOF at column 0 in the shell. Do not change it.
          gh issue create \
            --title "SDLC Harness update: v${INSTALLED} -> v${LATEST}" \
            --label "wizard-update" \
            --body "$(cat <<ISSUE_EOF
          ## SDLC Harness Update Available

          **Installed:** v${INSTALLED}
          **Latest:** v${LATEST}

          ### What's New

          ${CHANGES}

          ### How to Update

          Ask Claude: **"Check for SDLC wizard updates"**

          Claude will fetch the latest wizard, show what changed, and walk you through updates (opt-in each).

          ---
          *Auto-generated by wizard update check. Close after updating.*
          ISSUE_EOF
          )"
```

2. That's it — you'll get a GitHub Issue when updates are available (the `wizard-update` label is auto-created on first run)

**Cost:** $0. No API key needed. Pure bash/curl/python3. ~10 seconds of GitHub Actions time per week.

### Why This Approach?

- **Manual flow (primary):** Uses Claude Code's built-in WebFetch - zero infrastructure
- **CI notification (optional):** Lightweight issue creation - no API key, $0 cost
- Opt-in per change - your customizations stay safe
- **Tracks setup steps, not just files** - old users get new features

---

## Philosophy: Bespoke & Organic

### The Real Goal (Read This!)

**This SDLC becomes YOUR custom-tailored workflow.**

Like a bespoke suit fitted to your body, this SDLC should grow and adapt to fit YOUR project perfectly. The wizard is a starting point - generic principles that Claude Code uses to build something unique to you.

**The magic:**
- **Generic principles** - This wizard focuses on the "why", not tech specifics
- **Claude figures out the details** - Your stack, your commands, your patterns
- **Organic growth** - CI friction signals + scheduled research feed continuous improvement
- **Recursive improvement** - The more you use it, the more tailored it becomes

### Failure is Part of the Process

**No pain, no gain.**

When something doesn't work:
1. That's feedback, not failure
2. Claude proposes an adjustment
3. You approve (or tweak)
4. The SDLC gets better

**Friction is information.** Every time Claude struggles, that's a signal. Maybe the docs need updating. Maybe a gotcha needs documenting. Maybe the process needs simplifying.

**Don't fear mistakes.** They're how this system learns YOUR project.

### Why Generic Principles Matter

**Less is more. Principles over prescriptions.**

1. **"Plan before coding"** not "use exactly this planning template"
2. **"Test your work"** not "use Jest with this exact config"
3. **"Escalate when uncertain"** not "if confidence < 60% then ask"

**Claude adapts the principles to YOUR stack.** Give Claude the philosophy, it figures out your tech details - your commands, your patterns, your workflow.

**The temptation:** Add more rules, more specifics, more enforcement.
**The discipline:** Keep it generic. Trust Claude to adapt. KISS.

### Stay Lean, Stay Engaged

**Don't drown in complexity. Don't turn your brain off.**

The human's job:
- **Stay engaged** - keep the AI agent on track
- **Build trust** - as velocity increases, you trust the process more
- **Focus on what matters** - planning and confidence levels

**Maximum efficiency for both parties:**
- AI handles execution details
- Human handles direction and judgment
- Neither is passive

**When you reach velocity:** You're not checking every line. You trust the process. Your brain focuses on planning and fixing confidence issues - the high-leverage work.

### How Tailoring Happens

**This SDLC fits your project like custom-tailored clothes.**

The wizard provides generic starting principles, then:

1. **Claude encounters your codebase** - Learns your patterns, idioms, structure
2. **Friction happens** - Claude struggles or makes a mistake
3. **Claude proposes a tweak** - "Should I add this gotcha to the docs?"
4. **You approve** - The SDLC becomes more fitted to YOUR project
5. **Repeat** - Each iteration makes it more bespoke

**After a few cycles:** This SDLC feels native to your project, not bolted on.

### The Living System

> See **The Vision** at the top of this document for the full philosophy — including planned obsolescence, the Iron Man analogy, and tuning to your project.

### Evolving with Claude Code

**Claude Code's agentic capabilities keep improving. This SDLC should evolve with them.**

Claude should periodically:
1. **Check latest Claude Code docs** - New features? Better patterns? Built-in capabilities?
2. **Research current best practices** - WebSearch for 2026 patterns, compare with what we're doing
3. **Propose SDLC updates** - "Claude Code now has X, should we use it instead of our custom Y?"

**The goal:** Keep the SDLC pipeline adapting to Claude's latest capabilities. Don't get stuck on old patterns when better ones exist.

**When Claude discovers something better:**
1. Propose the change with reasoning
2. Human approves
3. Update the SDLC docs
4. The pipeline gets better

**This SDLC is not static.** It grows with your project AND with Claude Code's evolution.

### Stay Lightweight (Use Official Plugins)

When Anthropic provides official plugins that overlap with this SDLC:

**Use theirs, delete ours.**

| Official Plugin | Replaces Our... | Scope |
|-----------------|-----------------|-------|
| `claude-md-management` | Manual CLAUDE.md audits | CLAUDE.md only (not feature docs, TESTING.md, hooks) |
| `code-review` | Custom self-review subagent | Local code review (parallel agents, confidence scoring) |
| `commit-commands` | Git commit guidance | Commits only |
| `claude-code-setup` | Manual automation discovery | Recommendations only |

**What we keep (not in official plugins):**
- TDD Red-Green-Pass enforcement (hooks)
- Confidence levels
- Planning mode integration
- Testing Diamond guidance
- Feature docs, TESTING.md, ARCHITECTURE.md maintenance
- Full SDLC workflow (planning → TDD → review)

**The goal isn't obsolescence - it's efficiency.** Official plugins are maintained by Anthropic, tested across codebases, and updated automatically.

**Check for new plugins periodically:**
```
/plugin > Discover
```

**Re-run `claude-code-setup` periodically** (quarterly, or when your project expands in scope) to catch new automations — MCP servers, hooks, subagents — that weren't relevant at initial setup but are now.

**API feature shepherd (self-maintenance, roadmap #100):**

The wizard watches the **Anthropic API changelog** — not just Claude Code CLI releases — for new betas, tools, and agent features. The detector runs in `.github/workflows/weekly-api-update.yml`, is intentionally LLM-free, and only opens a tracking issue labeled `api-review-needed` when new entries appear at `platform.claude.com/docs/en/release-notes/api`.

When that issue is open, the session-start hook nudges you. The session (not the workflow) does the deep research + adoption via the full SDLC loop. This mirrors the "local shepherd" pattern used for CI fixes: cheap Action-layer detection + session-time analysis beats expensive Action-layer LLM calls.

The gap this closes: the advisor tool (API beta, `advisor-tool-2026-03-01`) shipped and was missed for several days before manual discovery. Detector would have flagged it on the next weekly tick. **Update (v1.81.0):** The API beta graduated to native CC support as `advisorModel` in settings.json (v2.1.170+). See [Advisor Model (v2.1.170+)](#advisor-model-v21170) above.

**Complementary native skills worth knowing:**

| Native Skill | What It Does | When to Run |
|--------------|--------------|-------------|
| `/less-permission-prompts` | Scans transcripts for common read-only Bash/MCP calls and proposes a prioritized allowlist | After a few sessions — reduces permission friction without auto mode |
| `/permissions` | Pre-allow specific commands and check them into `.claude/settings.json` | Anytime you want an auditable team allowlist |
| `/insights` | Local analyzer of your CC session history. Generates HTML report at `~/.claude/usage-data/report.html` + per-session facet JSON at `~/.claude/usage-data/facets/<session>.json`. Surfaces `underlying_goal`, `outcome`, `friction_counts`, `user_satisfaction_counts`, `brief_summary`, recurring friction patterns, suggested CLAUDE.md additions | Monthly — **qualitative-only**; see caveat below |
| `/goal <condition>` (v2.1.139+) | Set a completion condition; Claude keeps working across turns until a separate evaluator pass says it's met. **The evaluator is your configured "small fast model" — Haiku by default on the Claude API.** It is swappable via `ANTHROPIC_DEFAULT_HAIKU_MODEL`, but read the blast radius first: that variable is **not scoped to `/goal`**. Claude Code uses it everywhere it needs a small fast model, so pointing it at a frontier model also moves conversation summarization and other background work onto that model. Evaluation tokens alone are negligible; the compaction bill is not. **Know what you are buying:** the evaluator cannot run tools and judges only what is already in the transcript, so it is grading the agent's *claims*. This repo has one recorded failure of exactly that (`SDLC.md`): a condition naming three specific tests was marked achieved because *enough* tests existed, while one tested the wrong scenario — caught only at post-merge self-review. Write conditions that demand verbatim, unfiltered evidence rather than conclusions. **`/goal` is a wrapper around a session-scoped prompt-based Stop hook**, so if you need real verification you can write that Stop hook yourself and skip `/goal` entirely. **And often you need neither:** if the work already produces background events — a review, a CI watch, a long test run — completing one re-invokes the agent automatically, which gives you turn-to-turn autonomy without any evaluator judging doneness. Survives `--resume` (counters reset), not `/clear`. No disk writes — session-state only. Bound it yourself: `/goal "tests pass + git status clean, or stop after 20 turns"`. The evaluator judges the transcript only — it cannot run tools, so don't use `/goal` for "doneness" that lives off-transcript. Requires v2.1.143+ for the subagent-race fix. Composes cleanly with wizard hooks (`UserPromptSubmit`/`SessionStart`/`PreCompact` fire per turn) | Long-running goal-bound work — refactors, migrations, anything where "are we there yet?" has a checkable answer in the transcript |
| `/code-review [effort] [--comment]` (v2.1.147+, renamed from `/simplify`) | Reports correctness bugs at chosen effort level; `--comment` posts findings as inline GitHub PR comments. The /sdlc skill offers `/code-review` as optional preflight input to cross-model review — it is no longer an instructed step (GH #486); the `--comment` flag streamlines CI shepherd workflows | Self-review during SDLC; PR review when shepherding |
| `/usage` (v2.1.149+) | Per-category breakdown of limits usage — skills, subagents, plugins, per-MCP-server cost. Complement to `/context all` which shows per-skill per-model token estimates | When investigating session bloat / quota burn — pairs with this repo's `scripts/audit-session-load.sh`, maintainer tooling that is NOT installed by the wizard (#236) |
| `/context all` (v2.1.139+) | Rounded token estimates per-skill per-model, names the providing plugin for plugin-sourced skills | Same as `/usage` — diagnose what's eating your context |

These are shipped by Claude Code itself. The wizard doesn't reimplement them — it points you at them so you benefit from the native version's ongoing maintenance.

**`/insights` caveat (do not over-claim):** the output is behavioral/qualitative only — friction counts, goal categories, satisfaction. It does NOT expose `cache_read_input_tokens`, cache-hit ratio, per-turn token breakdown, or model-version tracking. It is **not a substitute** for token-spike detection (ROADMAP #220 / `hooks/token-spike-check.sh`), which reads raw session JSONL (`~/.claude/projects/<proj>/<session>.jsonl`, `usage.cache_read_input_tokens` per turn). Use `/insights` for behavioral friction; use `#220`-class instrumentation for token/cache anomalies. They are complementary, not interchangeable. (Original research: ROADMAP #206, full writeup `.reviews/research-206-insights.md`.)

### When Claude Code Improves

Claude Code is actively improving. When they add built-in features:

| If Claude Code Adds... | Remove Our... |
|------------------------|---------------|
| Built-in TDD enforcement | `tdd-pretool-check.sh` |
| Built-in confidence tracking | Confidence level guidance |
| Built-in task tracking | TodoWrite reminders |

Use the best tool for the job. If Claude Code builds it better, use theirs.

---

## Cowork Support

**Claude Cowork** is a separate product from Claude Code — a desktop application for knowledge workers, not developers. It shares Claude Code's plugin format, so this wizard ships a Cowork-native subset: [`cowork/`](cowork/README.md).

**What it provides:** 2 portable skills (`/sdlc-wizard-cowork:sdlc`, `/sdlc-wizard-cowork:feedback`) plus 1 **prompt-based hook** — the Cowork equivalent of this wizard's bash hooks, since Cowork sessions have no shell access:

| Cowork Hook | Claude Code Equivalent | Event |
|-------------|------------------------|-------|
| TDD check | `tdd-pretool-check.sh` | `PreToolUse` (Write/Edit/MultiEdit) |


**What's NOT ported and why** (CLI-specific, filesystem-dependent, or event-unavailable in Cowork): `instructions-loaded-check.sh`, `model-effort-check.sh`, `precompact-seam-check.sh`, the Setup/Update skills, cross-model review via `codex exec` (use ChatGPT/Codex web manually instead), and the CI shepherd (`gh pr`, `git push` — these happen outside a Cowork session).

**Removed rather than not ported:** `sdlc-prompt-check.sh` was ported to a Cowork `UserPromptSubmit` classifier and then deleted in v1.97.0 (GH #561) after it denied the maintainer's own instructions twice. Blocking hooks belong on acts, not on turn-level subject matter — see [`cowork/README.md`](cowork/README.md) for what that costs.

**Install:** add the whole repo as a marketplace, then install the Cowork-specific plugin from it:

```
/plugin marketplace add BaseInfinity/claude-sdlc-harness
/plugin install sdlc-wizard-cowork@sdlc-wizard-marketplace
```

A GitHub web-UI URL like `.../tree/main/cowork` is **not** a supported marketplace source — only `owner/repo` shorthand, full git URLs, local paths, or direct `marketplace.json` URLs are. (This doc recommended that URL through v1.89.0; it could not have worked. See issue #455.) The Cowork plugin is registered as a second entry in the root marketplace via a `git-subdir` source, which is why the repo-level add is what you want. See [`cowork/README.md`](cowork/README.md) for the Desktop UI walkthrough and the local-ZIP fallback, or `claude --plugin-dir ./cowork` for local testing.

**Updating (Claude Code CLI):** the step observed to actually move a version is `/reload-plugins`, run in-session — it took this plugin 1.93.0 → 1.97.0 and `Hooks (2)` → `Hooks (1)`. The CLI command needs the **marketplace-qualified** identifier: `claude plugin update sdlc-wizard-cowork` fails with `Plugin "sdlc-wizard-cowork" not found`, while `claude plugin update sdlc-wizard-cowork@sdlc-wizard-marketplace` resolves (`--scope user` does not help). That second form has only been observed reporting an already-current install, so it is **not** observed performing a version change. Restart after it — the CLI's own help says "restart required to apply." `claude plugin marketplace update` looks like it updates the plugin and does not: it refreshes the catalog only, and `plugin disable`/`enable` likewise print success without re-resolving (all observed on Claude Code 2.1.221). Verify with `claude plugin details sdlc-wizard-cowork`, checking the header line — which is where the version appears, as `sdlc-wizard-cowork 1.97.0`; `details` prints no `Version:` field, that label belongs to `claude plugin list` — and the full expected component set. As of v1.97.0, `1.97.0` and `Hooks (1)  PreToolUse`. **Cowork Desktop updates through its own plugin UI, and that path is not yet verified end-to-end** — see [`cowork/README.md`](cowork/README.md) and GH #571.

**Drift prevention:** the skills in `cowork/skills/` are copies of the canonical `skills/` — `tests/test-cowork-drift.sh` fails CI if they diverge, forcing this package to stay in sync whenever the canonical skills update.

---

## Community Contributions (Give Back!)

**This wizard belongs to the community, not any individual.**

### Your Discoveries Help Everyone

When you find something valuable - a gotcha, a pattern, a simplification - consider contributing it back to the wizard repo so others benefit.

**Periodically, Claude may ask:**
> "You discovered something useful here. Want to contribute this back to the wizard repo so others can benefit?"

Options:
- **Yes** - Claude helps you create a PR
- **Not now** - Ask again another time
- **Never** - Never ask again (stored in config, respected forever)

### What Makes a Good Contribution?

| Good Contributions | Not Ideal |
|-------------------|-----------|
| Philosophical insights | Project-specific config |
| Generalizable patterns | Niche edge cases |
| Simplifications | Additional complexity |
| Battle-tested gotchas | Theoretical concerns |

### The Bar: Scientific & Philosophical

Keep contributions:
- **Scientific** - Based on what works, tested in real projects
- **Philosophical** - Explains the "why", not just the "what"
- **Generalizable** - Helps most projects, not just yours

### How to Contribute

1. Fork the repo: `github.com/[REPO_URL]`
2. Edit `CLAUDE_CODE_SDLC_WIZARD.md`
3. Submit a PR explaining the "why"
4. Community discusses, best ideas get merged

**Decision making is community-driven.** No single person owns this wizard.

---

## Ike the Cat: Easter Egg Apologies

**Meet Ike.** He's a sweet little black boy - 8 pounds of pure opinions. Short-to-medium black fur, loud meows, zero tolerance for bugs in production. Lives for Fancy Feast. He watches every coding session from his perch and judges silently. Sometimes not so silently.

**This is an EASTER EGG, not a regular feature.**

If the SDLC is working well, users should NEVER be frustrated. Ike jokes are a rare safety valve for when things slip - not something they encounter often.

**The goal:** SDLC should be smooth enough that no one needs apologies.

**When frustration happens (rare):**
1. Apologize sincerely
2. Keep it lighthearted with an Ike joke
3. Match THEIR humor, context, even their own words back at them (positively!)
4. SDLC is tough - Ike keeps it light

**Examples (adapt to user's style AND repo context):**
- "Sorry about that! Ike just knocked over my coffee watching me type this. He's judging both of us right now."
- "My bad! Ike says I should've asked first. He's very opinionated for a 12-pound cat."
- "Ike just walked across my keyboard. He says 'asdfghjkl' which I think means 'write the test first next time.'"
- Reference the repo/code they're working on:
  - (Discord bot) "Ike tried to bet on himself. The odds were not in his favor."
  - (MMA odds) "Ike thinks he could take on a lightweight. He weighs 8 pounds."
  - (Mass text) "Ike just sent 47 meows to everyone in my contacts."

**Be quirky! Have fun with it.** Match the vibe of what they're building.

**Why Ike?** Apologies should be light, not groveling. Ike keeps it friendly and human.

**Use their name/nickname** if you know it. Makes it personal.

**Mirror their communication style.** If they curse, you can curse back (friendly). If they're casual, be casual. Talk like they talk.

**If they don't like jokes:** Make one joke, then never mention it again. Simple.

---

**You're ready!** Start a new Claude Code session and try implementing something. The system will guide Claude through the proper workflow automatically.
