# Claude Code SDLC Harness

A **self-evolving Software Development Life Cycle (SDLC) enforcement system for AI coding agents**. Makes Claude plan before coding, test before shipping, and escalate when uncertain. Measures itself getting better over time.

**Built on 15+ years of software engineering and founding engineering experience** — battle-tested patterns from real production systems, baked into an AI agent that follows tried-and-true software quality practices so you don't have to enforce them manually.

> **The Reliable lane is the recommended default.** Opus 4.6[1m] max + GPT-5.5 xhigh + Fable 5.1 high — field-proven, actively dogfooded.
>
> The Bleeding edge lane (`@frontier`, not yet published) uses Opus 5 + GPT-5.6 Sol + Fable 5.1 and has cycle data from v1.88.0–v1.99.2 but is experimental.

> **Built for Claude Code.** Using OpenAI's Codex CLI instead? Check out [`codex-sdlc-wizard`](https://github.com/BaseInfinity/codex-sdlc-wizard). Need privacy-first / any-backend (local Ollama, Azure OpenAI, hosted OSS)? See [`opencode-sdlc-wizard`](https://github.com/BaseInfinity/opencode-sdlc-wizard). ([Full ecosystem](#xdlc-ecosystem-sibling-projects).)

> **Two lanes.** Pick at install time:
> ```bash
> npm install -g agentic-sdlc-wizard              # Reliable (default, @latest)
> # npm install -g agentic-sdlc-wizard@frontier   # Bleeding edge (not yet published)
> ```
> **Reliable** (`@latest`) — Opus 4.6[1m] max + GPT-5.5 xhigh + Fable 5.1 high.
> Field-proven, stable. Use `/model claude-opus-4-6[1m]` (`/effort max`).
> The bare `claude-opus-4-6` pin (without `[1m]`) gives only 200K.
> **Bleeding edge** (`@frontier`, not yet published) — Opus 5 high + GPT-5.6 Sol high + Fable 5.1 high.
> Latest models, less field data. See [AI_SETUP_LANES.md](AI_SETUP_LANES.md)
> for full details.
> Known defect on **both** lanes: setup does not auto-invoke on a brand-new
> project ([#698](https://github.com/BaseInfinity/claude-sdlc-harness/issues/698))
> — run it manually on first launch: type `/` plus the skill name.

## Install

**Requires [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)** (Anthropic's CLI for Claude). Install it with the native installer — `curl -fsSL https://claude.ai/install.sh | bash` — which the [official setup docs](https://code.claude.com/docs/en/setup) label *Recommended* and which keeps it auto-updating in the background. **Never** use `sudo npm install -g @anthropic-ai/claude-code`: sudo can leave the global module directory root-owned, which then breaks `claude update` *and* `npm uninstall -g`. Check for conflicting installs with `which -a claude`.

Run from your terminal or from inside Claude Code (`!` prefix):
```bash
npx -y agentic-sdlc-wizard@latest init
```
The `@latest` pin forces npm to fetch the newest version. Without it, `npx` may serve a stale CLI from your local cache (#358); `init` also nudges if it detects a gap. Since v1.100.0, `@latest` is the **Reliable** lane (Opus 4.6 + GPT-5.5 + Fable 5.1).
Then start (or restart) Claude Code — type `/exit` then `claude` to reload hooks. Setup is meant to auto-invoke on first prompt — Claude reads the wizard doc, scans your project, and generates bespoke CLAUDE.md, SDLC.md, TESTING.md, and ARCHITECTURE.md. **Known defect:** on a brand-new project the auto-invoke does not fire ([#698](https://github.com/BaseInfinity/claude-sdlc-harness/issues/698)) — run the setup skill manually: type `/` plus the skill name.

<details>
<summary>Alternative install methods</summary>

**curl (no npm install needed):**
```bash
curl -fsSL https://raw.githubusercontent.com/BaseInfinity/claude-sdlc-harness/main/install.sh | bash
```

**Homebrew:**
```bash
brew install BaseInfinity/sdlc-wizard/sdlc-wizard
sdlc-wizard init
```

**GitHub CLI extension:**
```bash
gh extension install BaseInfinity/gh-sdlc-wizard
gh sdlc-wizard init
```

**From GitHub (no npm registry needed):**
```bash
npx github:BaseInfinity/claude-sdlc-harness init
```

**Install CLI globally:**
```bash
npm install -g agentic-sdlc-wizard
sdlc-wizard init
```

**Stable lane — the last pre-Opus-5 release:**
```bash
npm install -g agentic-sdlc-wizard@opus-4.6
```
The `opus-4.6` dist-tag currently points at **v1.87.0** (2026-07-14), the
last release cut before Opus 5 entered this repo, from the era when the
recommended lanes were built around Opus 4.6 / Sonnet 5. The published
v1.87.0 package contents are immutable; the dist-tag itself is a mutable
registry pointer, so to guarantee that exact version regardless of where the
tag may later point, pin it directly: `agentic-sdlc-wizard@1.87.0`.
**Honest label:** its
known-goodness is the maintainer's recollection of daily use, not a recorded
end-to-end test — a lifecycle canary is tracked in
[#689](https://github.com/BaseInfinity/claude-sdlc-harness/issues/689), and
this label upgrades to "verified" only when that canary's verdict is recorded
there. Verified on 2026-08-26: `npm install agentic-sdlc-wizard@opus-4.6`
resolves and installs 1.87.0.

**Manual (advanced — partial, not an escape hatch):** Download `CLAUDE_CODE_SDLC_WIZARD.md` to your project and tell Claude `Run the SDLC wizard setup`. This skips the live-session auto-invoke and generates your bespoke `CLAUDE.md`, `SDLC.md`, `TESTING.md` and `ARCHITECTURE.md`. **It does not give you a working install.** The document no longer contains the SDLC skill — Step 6 installs it by running the CLI (GH #513) — and only 2 of the 8 hooks have hand-typed templates here. So this path still needs `npx`; there is no npx-free route to a complete install. The default human path is `npx init` → restart CC → first-prompt auto-setup.
</details>

<details>
<summary>Health check & updates</summary>

```bash
npx agentic-sdlc-wizard check        # Human-readable
npx agentic-sdlc-wizard check --json  # Machine-readable (CI-friendly)
```

Reports MATCH / CUSTOMIZED / MISSING / DRIFT for every installed file. Exits non-zero on MISSING or DRIFT — use in CI to catch setup regressions.

**Check for content updates:** Tell Claude `Check if the SDLC wizard has updates` — it reads [CHANGELOG.md](CHANGELOG.md), shows what's new, and offers to apply changes.
</details>

## Why Use This

You want Claude Code to follow engineering discipline automatically:
- **Plan before coding** (not guess-and-check)
- **Write tests first** (TDD enforced via hooks)
- **State confidence** (LOW = escalate to a model first, don't guess)
- **Track work visibly** (TaskCreate)
- **Cross-model review before shipping** (a *different* model checks the work — same-model self-review was removed in #486 after it reported all-green while an independent model found real P1s)
- **Prove it's better** (use native features unless you prove custom wins)

The wizard auto-detects your stack (package.json, test framework, deployment targets) and generates bespoke hooks + skills + docs. CI validates the generated assets; cross-stack setup-path E2E is on the [roadmap](ROADMAP.md).

## What This Actually Is

Five layers working together:

```
Layer 5: SELF-IMPROVEMENT
  Weekly/monthly workflows detect changes, test them
  statistically, create PRs. Baselines evolve organically.

Layer 4: STATISTICAL VALIDATION
  E2E scoring with 95% CI (5 trials, t-distribution).
  SDP normalizes for model quality. CUSUM catches drift.

Layer 3: SCORING ENGINE
  Multi-criteria scoring, 10/11 points. Claude evaluates Claude.
  Before/after wizard A/B comparison in CI.

Layer 2: ENFORCEMENT
  Hooks fire every interaction (~100 tokens).
  PreToolUse reminds Claude to write tests first.

Layer 1: PHILOSOPHY
  The wizard document. KISS. TDD. Confidence levels.
  Run the CLI; setup reads it and writes a bespoke SDLC.
```

## What Makes This Different

| Capability | What It Does |
|---|---|
| **E2E scoring in CI** | Every PR gets an automated SDLC compliance score (0-10) — measures whether Claude actually planned, tested, and reviewed |
| **Before/after A/B testing** | Compares wizard changes against a baseline with 95% confidence intervals to prove improvements aren't noise |
| **SDP normalization** | Separates "the model had a bad day" from "our SDLC broke" by cross-referencing external benchmarks |
| **CUSUM drift detection** | Catches gradual quality decay over time — borrowed from manufacturing quality control |
| **Pre-tool TDD hooks** | Before source edits, a hook reminds Claude to write tests first. CI scoring checks whether it actually followed TDD |
| **Self-evolving loop** | Weekly/monthly external research + local CI shepherd loop — you approve, the system gets better |

## Cross-Model Review (Codex) — REQUIRED for High-Stakes

Claude can't grade its own homework. Have a **different AI from a different company** review Claude's work — different training, different blind spots, different biases. We use OpenAI's Codex CLI, and it's **three commands to set up**:

```bash
npm i -g @openai/codex
export OPENAI_API_KEY=sk-...
codex --version   # confirm ready
```

That's it. Codex picks up your OpenAI account's best available model automatically — **if you have GPT-5.6 Sol, it uses Sol; otherwise it falls back to Terra**. No model config needed.

**How to use it:** when the change is high-stakes, write a one-file mission brief and run:

```bash
codex exec -c 'model_reasoning_effort="high"' -s danger-full-access \
  -o .reviews/latest-review.md \
  "Read .reviews/handoff.json and review per the checklist. Output findings + CERTIFIED or NOT CERTIFIED." \
  < /dev/null
```

**Always append `< /dev/null`** when running `codex exec` from a non-interactive parent (background, hooks, CI, Claude Code Bash tool). Without it, codex blocks on stdin reads even when the prompt is an argument — the process sits at S/0% CPU indefinitely with a 0-byte `-o` output file. Validated on codex-cli 0.130.0 / macOS 14, 2026-05-15.

Reviewer effort is `high` (changed from `xhigh` 2026-08-01, for cost and review-noise — not capability); escalate to `xhigh` for unusually risky PRs. See [CLAUDE_CODE_SDLC_WIZARD.md](CLAUDE_CODE_SDLC_WIZARD.md#cross-model-review-loop-required-for-high-stakes) for the full protocol (handoff format, round-2 dialogue loop, preflight docs). Real-world: this catches P0/P1 issues in 2-3 out of 10 reviews that Claude's self-review rated as clean.

## Choosing Your Model

The wizard ships a **default recommendation**, not a mandate. Swap to any Claude
model at any time — `/model` per session, or pin in `.claude/settings.json`.

**Default (Reliable): Opus 4.6[1m] at `max` effort** — the maintainer's daily driver.
**Bleeding edge: Opus 5 at `high`** — install via `@frontier` when that dist-tag ships.
**Sonnet 5 at `medium` effort** (Setup B) for simple or one-off work.

**What has actually been exercised on this harness.** The Reliable lane — Opus 4.6
driving, GPT-5.5 reviewing, Fable 5.1 escalating — is the actively dogfooded
configuration. The Bleeding edge lane (Opus 5 + GPT-5.6 Sol + Fable 5.1) has
cycle data from v1.88.0–v1.99.2 but is experimental.

### Switch any time

```bash
/model claude-opus-4-6[1m]  # Reliable default — Opus 4.6, 1M context, `max` effort
/model opus                # Bleeding edge (Setup A) — Opus 5, requires CC v2.1.219+
/model sonnet              # Simple/one-off lane (Setup B) — native 1M context, lower cost
/model opusplan            # Opus 5 plans (Shift+Tab), Sonnet executes — both Max-bundled (Setup C)
/model claude-opus-4-8     # pin explicitly for Opus 4.8's field-proven behavior
```

Or pin in `.claude/settings.json`:

```json
{ "model": "claude-opus-4-6[1m]", "advisorModel": "fable" }
```

Set effort per session with `/effort max` — don't persist it in settings (the effort hook warns on a settings-only pin).

Set effort per session with `/effort`, not a shell-rc or settings env var —
persisting it that way silently overrides a later `/effort` change once you
switch models.

### Four Setup Lanes

The wizard defines four AI coding setups in [`AI_SETUP_LANES.md`](AI_SETUP_LANES.md):

| Lane | Advisor | Driver | Reviewer | Escalation |
|------|---------|--------|----------|------------|
| **Reliable (default)** | Fable 5.1 (`advisor()`) | Opus 4.6[1m], `max` | GPT-5.5 xhigh | Fable 5.1 high |
| **A — Bleeding edge** | Fable 5.1 (`advisor()`) | Opus 5, `high` | GPT-5.6 Sol high | Fable 5.1 high |
| **B — Simple/One-Off** | Fable 5 (advisorModel, fallback subagent) | Sonnet 5, `medium`→`high`→`xhigh` | GPT-5.6 Sol high | Opus 4.8 xhigh or Fable review |
| **C — Saver** | Fable 5 or Opus 5 (advisorModel) | Opus 5 plans, Sonnet 5 executes | GPT-5.6 Sol high | None |
| **D — Lite** | None | Sonnet 5, `medium` | None | None |

Setup D's whole point: **the discipline of knowing when NOT to use discipline.** When blast radius is low and you just need fast cheap hands, skip the SDLC overhead.

### Going deeper

[`AI_SETUP_LANES.md`](AI_SETUP_LANES.md) carries the rest, so this section stays
short: the per-model effort table,
[how to read Setup A precisely](AI_SETUP_LANES.md), the evidence behind the
4.6 / 4.8 / Sonnet 5 positions, and
[how billing works](AI_SETUP_LANES.md#how-billing-works--1m-context-max-plan-and-the-june-15-split)
(1M context is GA at standard pricing; the June 15, 2026 split moved *headless*
surfaces off Max, interactive Claude Code stays on it).

## How It Works

**Think Iron Man:** Jarvis is nothing without Tony Stark. Tony Stark is still Tony Stark. But together? They make Iron Man. This SDLC is your suit - you build it over time, improve it for your needs, and it makes you both better.

**The dream:** Mold an ever-evolving SDLC to your needs. Replace my components with native Claude Code features as they ship — and one day, delete this repo entirely because Claude Code has them all built in. That's the goal.

```
WIZARD FILE (CLAUDE_CODE_SDLC_WIZARD.md)
  - Setup guide, used once
  - Lives on GitHub, fetched when needed
        |
        | generates
        v
GENERATED FILES (in your repo)
  - .claude/hooks/*.sh
  - .claude/skills/*/SKILL.md
  - .claude/settings.json
  - CLAUDE.md, SDLC.md, TESTING.md, ARCHITECTURE.md

        (that's everything you get — the arrow below leaves your repo)

        |
        | the harness itself is validated by
        v
CI/CD PIPELINE (this repo, NOT yours)
  - E2E: simulate SDLC task -> score 0-10
  - Before/after: main vs PR harness
  - Statistical: 5x trials, 95% CI
  - Model-aware: SDP adjusts for external conditions
```

**The bottom box runs here, not in your project.** `tests/e2e/` is not part of the
published package, so `npm pack` ships none of it. That scoring pipeline is how *this*
repo proves a change to the harness is an improvement before releasing it — it is not
something you run, configure, or need an API key for. What lands in your repo is the
middle box: hooks, skills, settings and docs.

## Self-Evolving System

| Cadence | Source | Action |
|---------|--------|--------|
| Weekly | Claude Code releases | PR with analysis + E2E test |
| Weekly | Community (Reddit, HN) | Issue digest |
| Monthly | Deep research, papers | Trend report |

Every update: regression tested -> AI reviewed -> human approved.

## E2E Scoring

Like evaluating scientific method adherence - we measure **process compliance**:

| Criterion | Points | Type |
|-----------|--------|------|
| TodoWrite/TaskCreate | 1 | Deterministic |
| Confidence stated | 1 | Deterministic |
| Plan mode | 2 | AI-judge |
| TDD RED | 2 | Deterministic |
| TDD GREEN | 2 | AI-judge |
| Self-review | 1 | AI-judge |
| Clean code | 1 | AI-judge |

40% deterministic + 60% AI-judged. 5 trials handle variance.

## Model-Adjusted Scoring (SDP)

| Metric | Meaning |
|--------|---------|
| **Raw** | Actual score (Layer 2: SDLC compliance) |
| **SDP** | Adjusted for model conditions |
| **Robustness** | How well SDLC holds up vs model changes |

- **Robustness < 1.0** = SDLC is resilient (good!)
- **Robustness > 1.0** = SDLC is sensitive (investigate)

## Tests Are The Building Blocks

Tests aren't just validation - they're the foundation everything else builds on.

- **Tests >= App Code** - Critique tests as hard (or harder) than implementation
- **Tests prove correctness** - Without them, you're just hoping
- **Tests enable fearless change** - Refactor confidently

## Official Plugin Integration

| Plugin | Purpose | Scope |
|--------|---------|-------|
| `claude-md-management` | **Required** - CLAUDE.md maintenance | CLAUDE.md only |
| `claude-code-setup` | Recommends automations | Recommendations |
| `code-review` | Optional preflight input to cross-model review; PR review | Local + PRs |

## Prove It's Better

Don't reinvent the wheel. Use native/built-in features UNLESS you prove your custom version is better. If you can't prove it, delete yours.

1. Test the native solution — measure quality, speed, reliability
2. Test your custom solution — same scenario, same metrics
3. Compare side-by-side
4. Native >= custom? **Use native. Delete yours.**
5. Custom > native? **Keep yours. Document WHY.** Re-evaluate when native improves.

This applies to everything: native commands vs custom skills, framework utilities vs hand-rolled code, library functions vs custom implementations.

## How This Compares

This isn't the only Claude Code SDLC tool. Here's an honest comparison:

| Aspect | SDLC Harness | everything-claude-code | claude-sdlc |
|--------|------------|----------------------|-------------|
| **Focus** | SDLC enforcement + measurement | Agent performance optimization | Plugin marketplace |
| **Hooks** | 3 (SDLC, TDD, instructions) | 12+ (dev blocker, prettier, etc.) | Webhook watcher |
| **Skills** | 4 (/sdlc, /setup, /update, /feedback) | 80+ domain-specific | 13 slash commands |
| **Evaluation** | 95% CI, CUSUM, SDP, Tier 1/2 | Configuration testing | skilltest framework |
| **CI Shepherd** | Local CI fix loop | No | No |
| **Auto-updates** | Weekly CC + community scan | No | No |
| **Install** | `npx -y agentic-sdlc-wizard@latest init` | npm install | npm install |
| **Philosophy** | Lightweight, prove-it-or-delete | Scale and optimization | Documentation-first |

**Our unique strengths:** Statistical rigor (CUSUM + 95% CI), SDP scoring (model quality vs SDLC compliance), CI shepherd loop, Prove-It A/B pipeline, comprehensive automated test suite, dogfooding enforcement.

**Where others are stronger:** everything-claude-code has broader language/framework coverage. claude-sdlc has webhook-driven automation. Both have npm distribution.

**The spirit:** Open source — we learn from each other. See [COMPETITIVE_AUDIT.md](COMPETITIVE_AUDIT.md) for details.

## Documentation

| Document | What It Covers |
|----------|---------------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design, 5-layer diagram, data flows, file structure |
| [CI_CD.md](CI_CD.md) | All workflows, E2E scoring, tier system, SDP, integrity checks |
| [SDLC.md](SDLC.md) | Version tracking, enforcement rules, SDLC configuration |
| [TESTING.md](TESTING.md) | Testing philosophy, test diamond, TDD approach |
| [CHANGELOG.md](CHANGELOG.md) | Version history, what changed and when |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute, evaluation methodology |

## XDLC Ecosystem (Sibling Projects)

This wizard is one of three published siblings. Same enforcement philosophy, different agent / domain:

| Package | Agent / Domain | What It Does |
|---------|----------------|--------------|
| [`agentic-sdlc-wizard`](https://www.npmjs.com/package/agentic-sdlc-wizard) ([repo](https://github.com/BaseInfinity/claude-sdlc-harness)) | Claude Code / SDLC | This repo. Plan → TDD → cross-model review for code, with hooks + skills + CI scoring |
| [`codex-sdlc-wizard`](https://www.npmjs.com/package/codex-sdlc-wizard) ([repo](https://github.com/BaseInfinity/codex-sdlc-wizard)) | OpenAI Codex / SDLC | Same SDLC enforcement, ported to Codex CLI (writes `.codex/` + `AGENTS.md`) |
| [`opencode-sdlc-wizard`](https://www.npmjs.com/package/opencode-sdlc-wizard) ([repo](https://github.com/BaseInfinity/opencode-sdlc-wizard)) | OpenCode / privacy-first | Same SDLC enforcement against ANY backend OpenCode supports — local Ollama, Azure OpenAI, Together, Groq, OpenRouter. Writes `.opencode/` + `AGENTS.md`. |
| [`claude-gdlc-wizard`](https://www.npmjs.com/package/claude-gdlc-wizard) ([repo](https://github.com/BaseInfinity/claude-gdlc-wizard)) | Claude Code / GDLC | Game Development Life Cycle — persona-driven playtest cycles, triangulated findings, ratchet-only-tightens |

All four are part of the broader [XDLC ecosystem](https://github.com/BaseInfinity/xdlc) — generalized lifecycle enforcement across agents and domains.

## Community

<div align="center">

[![Discord](https://img.shields.io/badge/Discord-Automation%20Station-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.com/invite/fGPEF7GHrF)

**[Automation Station](https://discord.com/invite/fGPEF7GHrF)** — a community Discord packed with software engineers bringing 40+ years of combined experience across every area of the stack.

_Frontend · Backend · Infra · Embedded · Data · QA · DevOps_

Share patterns, ask questions, compare notes on AI agents, automation, and SDLC tooling.

</div>

## Contributing

PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for evaluation methodology and testing.

## Feedback

Three ways to report bugs, request features, or ask questions:

- **In-session:** run `/feedback` inside any Claude Code session using this wizard — auto-fills context and redacts secrets before filing
- **Issue templates:** [bug report](https://github.com/BaseInfinity/claude-sdlc-harness/issues/new?template=bug_report.md), [feature request](https://github.com/BaseInfinity/claude-sdlc-harness/issues/new?template=feature_request.md), [question](https://github.com/BaseInfinity/claude-sdlc-harness/issues/new?template=question.md)
- **Discussions:** open-ended conversations at [github.com/BaseInfinity/claude-sdlc-harness/discussions](https://github.com/BaseInfinity/claude-sdlc-harness/discussions)
