# Competitive Audit

> Last updated: 2026-03-25 (Item #10)
> Next review: Weekly (via `analyze-community.md` competitive watchlist in weekly community scan)

## Purpose

Honest assessment of where we stand in the Claude Code ecosystem. What we do well, what others do better, and what we should incorporate or share back. Open source spirit — we're allies, not enemies.

## Ecosystem Overview

| Project | Stars | Focus | Relationship |
|---------|-------|-------|-------------|
| [everything-claude-code](https://github.com/affaan-m/everything-claude-code) | 50K+ | Full agent framework (28 agents, 80+ skills) | Different niche — breadth vs our depth |
| [claude-sdlc](https://github.com/danielscholl/claude-sdlc) | — | Plugin marketplace (13 commands, 3 agents) | Closest competitor — similar philosophy |
| [claude-code-sdlc](https://github.com/Koroqe/claude-code-sdlc) | — | 12-agent documentation-first pipeline | Documentation overlap |
| [awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) | 31.9K | Curated resource directory | Community pulse |
| [aistupidlevel.info](https://aistupidlevel.info) | — | Model benchmarking (CUSUM, CI, drift) | Methodology ally — inspired our stats.sh |

## What We Do That Nobody Else Does

1. **Statistical E2E evaluation** — 95% confidence intervals with t-distribution, 5-trial Tier 2 testing. No other Claude Code tool measures itself this rigorously.
2. **SDP scoring** — Separates "the model had a bad day" (L1) from "our SDLC broke" (L2) using external benchmark cross-referencing. Formula: `SDP = Raw x (baseline_external / current_external)`.
3. **CI Shepherd** — Local shepherd loop watches CI, reads failure logs, fixes locally, and pushes — all within one session with full context. Max 2 fix attempts before escalating to user.
4. **Prove-It A/B pipeline** — Before keeping any custom feature, we prove it outperforms native alternatives with statistical evidence. If we can't prove it, we delete it.
5. **CUSUM drift detection** — Per-criterion tracking (not just overall). Catches "plan_mode is degrading while tdd_green is stable" — isolates which SDLC area is slipping.
6. **Dogfooding enforcement** — The wizard tests itself. Every PR to this repo runs the same SDLC evaluation we recommend for users. Comprehensive automated test suite validated by CI on every PR.
7. **Auto-update research** — Weekly Claude Code release checks + community scan, monthly deep research. Automated trend detection.

## What Others Do Better

| Feature | Who | What They Do | Our Status |
|---------|-----|-------------|-----------|
| Language coverage | everything-claude-code | 7+ languages, 10 ecosystems | Python/JS-centric (by design) |
| Skill library | everything-claude-code | 80+ domain-specific skills | 5 skills (by design — minimal) |
| Cross-platform hooks | everything-claude-code | Node.js (Windows/macOS/Linux) | Bash only (macOS/Linux) |
| Token/cost tracking | everything-claude-code | Per-session cost monitoring | Blocked — `claude-code-action` doesn't expose usage data |
| Webhook automation | claude-sdlc | GitHub issues auto-trigger SDLC | Manual PR creation |
| npm distribution | everything-claude-code, claude-sdlc | `npm install` or GitHub App | `npx agentic-sdlc-wizard init` (CLI shipped) |
| Pattern learning | everything-claude-code | Auto-extract patterns from sessions | Manual identification |

## What We Incorporated From This Audit

### aistupidlevel.info Integration
- **Before:** Cited methodology but never fetched their data
- **After:** Added as Source 3 in external benchmark cascade (DailyBench -> LiveBench -> aistupidlevel -> baseline)
- **API:** `https://aistupidlevel.info/api/dashboard/scores` — JSON with model scores, confidence intervals, trend data
- **Value:** Third independent data source for SDP scoring. Their confidence intervals validate our CI calculations.

### Competitive Watchlist
- **Before:** Weekly community scan checked general discussions
- **After:** `analyze-community.md` now includes named repos to check for new releases/patterns
- **Repos tracked:** everything-claude-code, claude-sdlc, claude-code-sdlc, awesome-claude-code, aistupidlevel

## What We Could Contribute Back

| Contribution | Target | Value |
|-------------|--------|-------|
| Per-criterion CUSUM | aistupidlevel.info | Granular drift detection (they track overall only) |
| SDP two-layer scoring | aistupidlevel.info | Separating model quality from task compliance |
| Self-healing CI pattern | Community | Auto-fix + re-trigger loop |
| Prove-It A/B methodology | Community | Statistical comparison framework for AI tools |
| `stats.sh` library | Community | Tested t-distribution 95% CI calculation in bash |

Status: Documented for future. Will open issues/PRs when timing is right.

## Tracked Gaps

### Token Usage Tracking (Blocked)
- **Problem:** If an update causes 3x more tokens, that's a real regression even if SDLC score holds
- **Blocker:** `claude-code-action@v1` doesn't expose usage data in execution output
- **When:** Weekly update workflow will detect when this becomes available
- **Plan:** Add tokens/run to score-history.jsonl, token regression detection to compare_ci

### Distribution (Shipped)
- CLI install shipped: `npx agentic-sdlc-wizard init`
- Remaining: docs polish, npm registry publishing

## Philosophical Position

We're not competing with everything-claude-code on breadth. We're a **minimal, focused SDLC baseline** that:
- Ships in a single wizard file + hooks
- Proves itself with statistical evidence
- Deletes custom code when native features catch up
- Gets better automatically through self-evolving research

The goal isn't to be the biggest — it's to be the most honest about whether it works.
