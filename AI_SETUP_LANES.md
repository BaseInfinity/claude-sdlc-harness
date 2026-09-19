# AI Setup Lanes

Two lanes. **Reliable** is the recommended default — field-proven, stable. **Bleeding edge** tracks the latest models. Pick your lane at install time:

```
npm install agentic-sdlc-wizard              # Reliable (@latest)
# npm install agentic-sdlc-wizard@frontier   # Bleeding edge (not yet published)
```

This is **guidance, not a hard rule**. Maintainer override is always allowed.

## Reliable — Opus 4.6[1m] + GPT-5.5 (Recommended default)

The maintainer's daily-driver pairing, field-proven with an SDLC harness. Optimized for reliability over capability. This is `@latest` on npm.

| Role | Model | Effort |
|------|-------|--------|
| **Builder** | Opus 4.6 (`claude-opus-4-6[1m]`) | `max` (4.6's sweet spot — no `xhigh` on this model) |
| **First brain / Reviewer** | GPT-5.5 via Codex CLI (repo-local `scripts/run-review-leg.sh`) | `xhigh` |
| **Escalation brain** | Fable 5.1 via `advisor()` | `high` — **only when builder + first brain can't reach 95% confidence** |

**The `[1m]` suffix is required.** Bare `claude-opus-4-6` pins a 200K context window. `claude-opus-4-6[1m]` gives 1M — confirmed by session header "Opus 4.6 (1M context)."

**Escalation valve:** Default flow is Opus builds → GPT-5.5 reviews → ship. Call `advisor()` (Fable) only when the first two cannot resolve a design question or reach 95% confidence together. Fable sees the full conversation transcript on every call (not cached between calls), so it is the most expensive shape — spend it on design decisions, not on grading finished work.

**Seat provenance:** v1.87.0's shipped docs named **GPT-5.6** as the reviewer. The maintainer runs **GPT-5.5** at work and finds it the most reliable pairing. The Reliable lane reflects the owner's live config, not what v1.87.0 shipped.

**Package:** `npm install agentic-sdlc-wizard` — this is `@latest`. The legacy `@opus-4.6` dist-tag still points at v1.87.0 (immutable, different reviewer defaults).

**When to use:** Complex multi-file work, agentic tasks, anything where reliability matters more than having the latest model. This is the default for the maintainer's own work.

---

## Setup A — Opus 5 + Sol + Fable (Bleeding edge)

**Experimental. Tracks the latest models — higher capability ceiling, less field data.** Install via `npm install agentic-sdlc-wizard@frontier` (dist-tag not yet published). Requires Claude Code v2.1.219+ for the `opus` alias to resolve to Opus 5.

| Role | Model | Effort |
|------|-------|--------|
| **Builder** | Opus 5 (`claude-opus-5`) | `high` |
| **First brain / Reviewer** | GPT-5.6 Sol via Codex CLI (repo-local `scripts/run-review-leg.sh`) | `high` |
| **Escalation brain** | Fable 5.1 via `advisor()` | `high` — only when builder + first brain can't reach 95% confidence |

Same three-tier escalation ladder as Reliable, different models. The valve is identical: Fable fires only on escalation, not on every review.

Sonnet 5 medium remains a fine default for less complex repos — see Setup B below. It's demoted from Setup A's primary slot here specifically because the maintainer's own workload is dominated by complex, agentic-heavy repos where Opus 5's extra capability is worth the cost; that's a workload-specific call, not a universal verdict that Sonnet 5 medium is inferior.

**Advisor failure has a fallback, not a shrug.** `advisor()` is a server-side tool and can fail. When it errors, spawn a Fable subagent as the fallback reviewer — the same rule the `/sdlc` skill carries ("if down, spawn Fable subagent at `high`"). The advisor check is never skipped; only its transport changes. **This fallback is unverified: it has never been observed firing.** Availability has moved twice in three weeks (disabled 2026-07-24, working 2026-08-16), so treat any availability sentence in this file as a dated observation rather than current state — and settle it by calling the tool.

**Requires:** Claude Code v2.1.219+ (Opus 5 alias resolution), Fable 5 access for advisor/subagent fallback.

## Setup B — Sonnet 5 Simple/One-Off (Legacy Flagship slot repurposed)

**For one-off tasks, scripts, and less complex repos — not the main workflow.** Where Setup A (bleeding edge) targets genuine autonomous agentic work, Setup B is for lower-stakes, lower-complexity work where Sonnet 5's speed and cost outweigh Opus 5's extra capability.

> **Setup B is unverified in this repo.** Every lane below rests on vendor material and general reasoning about cost and complexity, not on a measured run. The Reliable lane is what the maintainer dogfoods daily; Setup A (Bleeding edge) has cycle data from v1.88.0–v1.99.2. Neither Setup B nor C has been measured. Choose on scope and cost, not as a capability claim.

| Role | Model | Effort |
|------|-------|--------|
| **Advisor** | Fable 5 (via `advisorModel: "fable"`) — same dated-availability caveat as Setup A; fall back to a Fable subagent at `high` on failure | `high` (server-side); subagent fallback explicit `high` |
| **Driver** | Sonnet 5 (`claude-sonnet-5`) | `medium` default, escalate `high` → `xhigh` for tasks that turn out harder than expected |
| **Reviewer** | Codex (GPT-5.6 Sol) high | — |

Choose this lane deliberately for scope, not by default — a one-off script, a small doc fix, a low-blast-radius repo. If a Setup B task turns out to need real agentic depth, swap to Setup A rather than cranking Sonnet 5's effort past `xhigh`; that's a model swap, not an effort-tier problem.

**Effort escalation ladder:** Start at `medium` — CodeRabbit's testing found it captures most of Sonnet 5's upside at the lowest cost. Raise to `high` when medium struggles, `xhigh` for hard debugging, multi-file migrations, or long agent runs. `max` is rarely worth it — doubles cost for marginal gains per the same CodeRabbit testing.

**Opus 4.6/4.8 remain reachable as the field-proven stability/escalation backstop** for installer, release, or other high-blast-radius work regardless of which lane you're in — months of field data, Active through at least Feb 2027. Pin `claude-opus-4-8` explicitly rather than relying on the `opus` alias, which now resolves to Opus 5. **Opus 4.6 is the only Opus where `max` effort works without overthinking** — community reports confirm this is the sweet spot specific to 4.6 (no xhigh support on 4.6 — only low/medium/high/max); pin `claude-opus-4-6` explicitly when you want that specific consistency profile over Opus 5 or 4.8.

## Setup C — OpusPlan Hybrid (Saver)

| Role | Model | Effort |
|------|-------|--------|
| **Planner** | Opus 5 (via Plan Mode — Shift+Tab, follows the `opus` alias) | `xhigh` |
| **Advisor** | Fable 5 or Opus 5 (via `advisorModel`) | — |
| **Driver** | Sonnet 5 (auto execute mode) | `medium`, escalate `high` for hard runs |
| **Reviewer** | Codex (GPT-5.6 Sol) high | — |

Cost-efficient hybrid using CC's native `opusplan` alias. `opusplan` follows the `opus` alias for its planning phase — currently Opus 5 — and executes with Sonnet. Max-bundled — no API credit drain. Pin `model: "opusplan"` + `advisorModel: "fable"` in project settings. Sonnet 5 now uses 1M context natively (no `[1m]` suffix needed). GPT-5.6 Sol high is the cross-model reviewer.

**Note:** Opus 4.6 cannot advise Sonnet 5 (rejected in the advisor pairing table). Use Fable 5 or Opus 5 as advisor for this lane. Pin `claude-opus-4-8` explicitly (not the `opus` alias) if you specifically want Opus 4.8's field-proven planning behavior instead of Opus 5's.

## Setup D — Claude Lite

| Role | Model | Effort | Notes |
|------|-------|--------|-------|
| **Planner** | You (the user) | — | Task is pre-planned, no model reasoning needed |
| **Driver** | Sonnet 5 | `medium` | Max-bundled, ≈ Sonnet 4.6 at high quality |
| **Reviewer** | None | — | Blast radius too low for cross-model overhead |

The "just do the thing" lane. No TDD enforcement, no cross-model review, no planning phase. You already know what to do — you just need a fast, cheap pair of hands.

## When to Use Setup A (Bleeding edge)

For work where you want the latest models and accept less field data. Install via `@frontier` dist-tag (not yet published). Full discipline (TDD, cross-model review) still applies:

- Architecture or methodology changes
- Complex multi-file features or refactors
- Ambiguous debugging, root-cause investigation
- Installer behavior (`cli/`, `init`, `claude-setup-wizard`)
- CI / release automation
- Security-sensitive behavior
- Anything that could damage a consumer repo
- Any task where you'd otherwise reach for Setup B and find yourself needing more than one or two escalation rounds

## When to Use Setup B

Reach for Setup B for one-off tasks, scripts, and lower-stakes/lower-complexity repos where Sonnet 5's speed and cost outweigh Opus 5's extra capability:

- Feature implementation on well-understood, routine work
- Documentation and examples
- Test writing
- Normal CLI changes
- Mechanical refactors
- Small, low-blast-radius scripts or one-off tasks
- Anything where the task is clearly scoped and doesn't need Opus 5's deeper agentic reasoning

If a Setup B task turns out to need more depth than expected, swap to Setup A rather than cranking Sonnet 5's effort past `xhigh` — that's a model swap, not an effort-tier problem.

## When to Use Setup C

Setup C is sufficient for routine work where a Sonnet driver can ship with a strong reviewer and you want the Max-bundled cost profile of `opusplan`:

- Routine implementation
- Documentation
- Examples
- Tests
- Normal CLI changes (non-installer)
- Low-risk methodology edits
- Mechanical refactors

## When to Use Setup D

Setup D is for work where SDLC discipline overhead exceeds the value:

- Run a script with basic intelligence
- Deploy to staging (prod deploys need Setup A's or B's discipline — human gate + rollback plan; Setup A for anything complex/high-stakes, Setup B for simple ones)
- Config updates, env var changes
- File moves, renames, bulk operations
- Repo maintenance (dependency bumps, lockfile refreshes)
- Simple administrative tasks across repos like `~/afterhours`
- Anything where blast radius is low and you need speed, not depth

**Not Lite — escalate to A or B:** env vars that touch secrets or credentials, dependency bumps with security advisories, destructive bulk ops (rm -rf, drop table), migrations, prod-like shared staging, anything security-sensitive. If you're unsure, it's not Lite.

## What Setup D explicitly skips

- No TDD (no test-first for running a deploy script)
- No cross-model review (not worth the cost or time for grunt work)
- No planning phase (you are the planner)
- No effort escalation (Sonnet 5 medium is plenty)

**The discipline of knowing when NOT to use discipline.** Documenting this lane tells users "here's when to switch off the heavy methodology" rather than silently tempting them to skip it. If the task turns out to be harder than expected, escalate to Setup A or B.

## Final Review Policy

**Setups A, B, and C end at GPT-5.6 Sol high as the cross-model reviewer.** Claude can't grade its own homework — the reviewer always belongs to a different lab with different blind spots. See [CLAUDE_CODE_SDLC_WIZARD.md → "Cross-Model Review (Codex)"](CLAUDE_CODE_SDLC_WIZARD.md) for the handoff protocol.

**Setup D has no reviewer** — the blast radius doesn't justify it. If you're unsure whether a task is truly Lite, it probably isn't. Escalate.

If GPT-5.6 Sol isn't available on your OpenAI account, Codex auto-falls back to Terra — still keep `model_reasoning_effort="high"`. Lower reasoning misses subtle bugs that the reviewer is the last gate to catch.

**Escalation for unusually risky PRs:** `high` is the default as of 2026-08-01 — a maintainer decision made for cost and review-noise, **not** on measured capability. Be clear that neither `high` nor the `xhigh` it replaced rests on a controlled comparison in this repo; the previous "evidence-based" framing rested on a 2026-03-26 claim about GPT-5.4 with no measurement artifact behind it. No published data shows `max` or Pro mode catching meaningfully more real bugs than `xhigh` on ordinary PR review either. For a PR you'd genuinely lose sleep over (security-sensitive, high blast radius, touches the installer or a consumer-facing template), escalate the reviewer to `max` or Pro mode — a once-per-PR gate is exactly the kind of low-frequency, high-stakes call site where the extra cost is easiest to justify. Don't make it the default.

## Version Requirement

Opus 5 (Setup A's driver) requires **Claude Code v2.1.219+**. `advisorModel` in settings.json requires **v2.1.170+**. Check your version with `claude --version`. If below v2.1.219, update from inside a CC session:

```
! claude update
```

The `!` prefix runs shell commands inside your CC session — no need to exit and re-enter. After updating, restart the session to pick up the new alias resolution. **Also check for a stale `ANTHROPIC_DEFAULT_OPUS_MODEL` env var** (e.g. in `~/.zshrc`) — if set to an older Opus version, it silently overrides `/model opus` picker choices and prevents Opus 5 from resolving even after updating.

Fable 5 as advisor also requires Fable 5 access for your organization/plan.

## When the Advisor Is Unavailable

**Fable-as-advisor was server-side disabled on 2026-07-24 and was observed working again on 2026-08-16.** The 2026-07-24 block was a deliberate Anthropic rollout gate, documented at `code.claude.com/docs/en/advisor`: "Claude Code doesn't offer Fable 5 as the advisor... A remotely configured rollout controls when Fable 5 returns as an advisor option." On 2026-08-16 an `advisor()` call returned a full Fable 5 ruling, twice in one session.

**Both of those are dated observations, and neither is current state.** Availability moved twice in three weeks. Do not decide whether the advisor works by reading this file, and do not add a guard that greps it — **call the tool.** One failed call is the whole diagnostic.

**Exhausted Fable quota is not the same condition as a disabled advisor.** claude.ai `/settings/usage` shows `All models` and `Fable` as separate meters. **Observed 2026-08-16:** with the `Fable` meter reading 100% used and `/model fable` refused, an `advisor()` call still returned a Fable 5 ruling.

**What that does and does not establish.** It establishes that a capped `Fable` meter did not, on that occasion, block the advisor — so **try `advisor()` before concluding Fable is out of reach.** It does **not** establish which meter the call billed: no meter delta was measured before and after, and a plausible competing explanation — a quota window rolling over between the refusal and the call — was not ruled out. Nor is the separate-meter display itself evidence of separate pools; two meters can report against one limit. Treat "advisor survives a capped Fable meter" as one dated observation, not as a billing mechanism.

Either way it is not free. Advisor usage counts toward your plan's limits, it forwards the entire conversation on every call, and its read is not cached between calls. Spend it on design decisions, not on grading work already done.

**Step 1 — call `advisor()`. The call is the diagnostic.** Do not decide availability from this file, from the docs page, or from a Fable quota meter reading 100%. This rung moved to the front on 2026-08-16, when a capped `Fable` meter was observed not to block the advisor.

**A single error does not mean "Fable is down."** Anthropic documents several unrelated causes for an advisor failure: an unsupported provider, an invalid main-model/advisor pairing, an organization allowlist, feature-flag fetching, the advisor being disabled in the environment, and plain account access. Read the error before concluding anything, and do not record "server-side disabled" unless the error says so.

**Step 2 — on a real failure, go straight to the subagent.** Spawn a Fable subagent as the fallback reviewer, explicit `effort: "high"` (per this repo's own `/sdlc` skill: "if down, spawn Fable subagent at `high`"). No restart, no retry, no wait — a rollout gate is not transient, and a retry loop against one wastes a cycle. Batch your open questions into one consult at each point where you'd have called `advisor()`. Runs interactively on your Max subscription like any other agent. **Unverified:** this path has never been observed firing. During the 2026-07-24 outage the driver used it, but no receipt or transcript of a fallback-triggered leg was kept, so its behavior under a real failure is described, not measured.

**Step 3 — keep driving with your lane's model.** `/model opus` for Setup A, `/model sonnet` for Setup B. The subagent replaces the advisor's transport; the Codex high PR gate remains the separate final backstop, not a substitute for the advisor check.

**Step 4 (last resort, scripted/CI only):**

- `claude --model fable --effort high -p "$(cat <file>)"` — headless mode bills API credits, not your Max subscription.

Whichever path you use, the cross-model PR review gate still applies.

## Credit-Spend Warning

**Setup A (Opus 5 as driver) burns the 5-hour cap faster than Setup B** — Opus 5 driving implementation is the more expensive path (and more so if you escalate to `xhigh`); Sonnet 5 at `medium`/`high` (Setup B) generally uses less quota for comparable-scope work (the advantage narrows at `xhigh` — more turns per task plus tokenizer overhead). If you're hitting the cap mid-session on Setup A:

- Drop to Setup B (Sonnet 5) for the remainder of the day, or for the rest of a task that turns out simpler than expected
- Or drop to Setup D for grunt work that doesn't need deep reasoning
- Or use Sonnet directly for the final mechanical edits, then run the GPT-5.6 Sol reviewer over the whole diff at the end

**Setup D uses Sonnet** — same model as Setup B's driver, Max-bundled. One less model to manage if you're already reaching for Setup B for lighter work.

The reviewer (GPT-5.6 Sol high) is billed against your OpenAI account, separately. Watch both bills.

## Autocompact Thresholds

For recommended `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` values per context window and task shape, see [CLAUDE_CODE_SDLC_WIZARD.md → Autocompact Tuning](CLAUDE_CODE_SDLC_WIZARD.md#autocompact-tuning). Sonnet 5 (Setup B, D) has its own native ~967K-token proactive-compaction default at 1M context — don't carry over Opus-era 1M threshold guidance unexamined.

## How Billing Works — 1M Context, Max Plan, and the June 15 Split

A common question: **"does the `[1m]` model alias get billed differently? Does it pull from my Max plan or from API credits?"**

The short answer: **all five lanes are fully Max-bundled in interactive sessions** — Reliable (Opus 4.6[1m]), Setup A (Opus 5), Setup B (Sonnet 5, native 1M), Setup C (opusplan, Opus plan-mode + Sonnet execute), and Setup D (Sonnet). Here's the detail.

### 1M context is free on Max — no API premium

[Anthropic 2026-03-13](https://claude.com/blog/1m-context-ga): 1M context is GA at standard $5/$25 per million tokens for Opus 4.6 (also 4.7, 4.8). No long-context multiplier. **No beta header required**, requests over 200K tokens just work. Sonnet 5 always runs at 1M natively (see [`code.claude.com/docs/en/model-config#sonnet-5-context-window`](https://code.claude.com/docs/en/model-config#sonnet-5-context-window)) — no `[1m]` suffix, no separate billing tier.

For Claude Code on Max / Team / Enterprise plans, **1M context is included automatically** with no extra usage allocation for supported models. Whether you set `claude-opus-4-6` or `claude-opus-4-6[1m]` doesn't change *what* you're billed — both pull from the same per-token budget on your subscription. The `[1m]` suffix just makes the alias explicit so it sticks across alias-resolution changes; functionally Opus 4.6 in Claude Code today *is* the 1M-context model on a Max plan.

(Pro plan is the exception: Pro users need "Enable usage credits" turned on in their Claude account settings to use 1M context. Max / Team / Enterprise have it on by default.)

### The June 15, 2026 billing split

[Anthropic moved a slice of usage off the subscription](https://codersera.com/blog/anthropic-june-2026-billing-change-claude-code/) onto a separate metered credit pool that bills at full API rates:

| Surface | Billing as of June 15, 2026 |
|---|---|
| **Interactive Claude Code in terminal** (you typing into Claude Code right now) | **Stays on Max subscription** — unchanged |
| Claude.ai web / desktop / mobile chat | Stays on Max subscription |
| Claude Cowork | Stays on Max subscription |
| `claude -p` (headless / `--print`) | **Moves to separate credit pool**, billed at API rates |
| Claude Agent SDK | Moves to separate credit pool |
| Claude Code GitHub Actions | Moves to separate credit pool |
| Third-party apps via Agent SDK | Moves to separate credit pool |

Credit allocations: Pro $20/mo, Max 5x $100/mo, Max 20x $200/mo. **No rollover.**

### What this means for the lanes

- **Setup A — Opus 5 + Fable advisor (fallback subagent):** Opus 5 driver on Max, 1M context included at standard rates (see above). Fable 5 advisor observed working 2026-08-16 — Fable subagent fallback also Max-bundled. claude.ai `/settings/usage` shows `All models` and `Fable` as separate meters, and on 2026-08-16 the advisor answered with the `Fable` meter at 100%; **which meter that call billed was not measured**, so do not budget against it. Advisor is the priciest call shape regardless — full conversation every call, no cache between calls. GPT-5.6 Sol high reviewer, separate. Higher Max quota consumption than Setup B — though the gap narrowed when Setup A's driver default moved to `high`/`medium` on 2026-08-02.
- **Setup B — Sonnet 5 Simple/One-Off:** Sonnet 5's native 1M context — interactive session, Max-bundled, no `[1m]` suffix needed. Fable 5 advisor (fallback subagent) — also Max-bundled. GPT-5.6 Sol high reviewer on ChatGPT subscription. Generally lower Max quota consumption than Setup A at the `medium` default (savings shrink at higher effort).
- **Setup C — OpusPlan Hybrid:** **fully Max-bundled.** `opusplan` uses Opus (plan mode, now Opus 5) + Sonnet (execute mode), both at their native context windows — no credit drain.
  - **⚠️ Avoid `sonnet[1m]` as a manual pin outside Setup B/C:** if your provider or gateway doesn't resolve Sonnet 5 to its native 1M automatically, forcing a `[1m]`-suffixed pin on an older Sonnet can draw from your usage credits pool ($3/$15 per Mtok) instead of your Max subscription. The `/model` picker shows this explicitly — watch for "Draws from usage credits."
- **Reviewer (GPT-5.6 Sol high) in all three triads:** billed against your OpenAI account, completely separate from Anthropic.
- **CI loops that use `claude -p` post-June-15:** these now bill against the separate Anthropic credit pool, not your Max subscription. The wizard's CI shepherd loops (E2E scoring, weekly-update jobs) are local-only on the maintainer's machine and stay on Max; consumer-repo CI integrations may need to budget the new credit pool.

### Bottom line

If you're using Claude Code interactively (you, in your terminal, doing `/sdlc` work), **all three full-discipline lanes ride your existing Max subscription**, and 1M context (whether Sonnet 5's native window or an explicit `[1m]` alias) doesn't add extra charges on Max/Team/Enterprise. The June 15 split only affects programmatic / headless / CI use of Claude Code.

Watch the headless surface if you've automated `claude -p` calls in your project — those now bill differently as of June 15, 2026.

## Maintainer Override

**Override at any time.** A blanket setup choice doesn't replace judgment per change. If you're touching CI but the change is a one-line typo, Setup C is fine. If you're touching docs but the section is the wizard's safety-critical hook ordering, Setup A or B is the call.

The wizard does not enforce setup lane selection — it documents the recommended default per change shape. Whatever ships is your call.

## Model Selection — The Evidence

Moved here from `README.md` so that section stays short. **Read the honesty
note there first:** the Reliable lane is the actively dogfooded configuration; Setup A has cycle data from v1.88.0–v1.99.2.
The research below is third-party field data about model behavior in general.
It is the reasoning behind the lane assignments; it is not a measurement of
this harness running on any lane other than A.

### Why Opus 4.6 was the flagship, and why that changed

Two weeks of in-the-wild data after Opus 4.8's launch (2026-05-28) showed a clear pattern that first made Opus 4.6 the wizard's flagship over Anthropic's own "latest" model:

- **[Andon Labs Vending-Bench](https://andonlabs.com/blog/opus-4-8-vending-bench)** — 4.8 finished last vs 4.7 and GPT-5.5; documented "Max reasoning is not the best reasoning effort"; falls for scam suppliers 30× more frequently
- **[AI Weekly: 900K cache tokens per turn](https://aiweekly.co/alerts/claude-opus-48-thinking-burns-900k-tokens-per-turn)** — 40-60× jump vs 4.7 at HIGH effort. Burns Max 5-hour limits 2-3× faster
- **[Tech.yahoo review](https://tech.yahoo.com/ai/claude/articles/claude-opus-4-8-review-130106963.html)** — explicit: "Anthropic deliberately made Opus's new tokenizer less efficient"; "a single coding prompt drained our entire token quota"
- **Active GitHub regressions** — false-greens ([#63861](https://github.com/anthropics/claude-code/issues/63861)), 2-3× token burn ([#64961](https://github.com/anthropics/claude-code/issues/64961)), 46K tokens for simple coding turn ([#64153](https://github.com/anthropics/claude-code/issues/64153)), dropped constraints during execution ([#65932](https://github.com/anthropics/claude-code/issues/65932)), fabricated identifiers in parallel tool batches
- **[Paweł Huryn's 4.7 guide](https://www.productcompass.pm/p/claude-opus-4-7-guide)** — "most complaints about 4.7 feeling slow stem from people reflexively using max"
- **[BSWEN effort decision guide](https://docs.bswen.com/blog/2026-04-19-claude-code-effort-level-decision-guide/)** — "Max on Opus causes overthinking on routine stuff. xHigh is the sweet spot for autonomous work"
- **r/Claudeopus field reports** — one maintainer's literal A/B: "12 hours with 4.8 zero deliverables; plugged in 4.6, spec written + 133 tests green in one session." Top comment: "4.6 had the best overall balance at max"

That research still stands as the reason **Sonnet 5 (not Opus 4.6, not Opus 4.8) is Setup B's driver** — Sonnet 5 doesn't have Opus 4.8's overthinking problem, and generally uses less quota for comparable-scope work. **Note what kind of evidence that is:** third-party field reports about model behavior in general, not a measurement of this harness running on Setup B. The Reliable lane is the actively dogfooded configuration; Setup A has historical cycle data (v1.88.0–v1.99.2). Setup B remains unverified. The two statements are consistent — the research picks Sonnet 5 *over other Setup B candidates*; it says nothing about Setup B versus Setup A. Opus 4.6/4.8 remain reachable as an explicit escalation/stability pin (see the lane tables above) for anyone who's tuned a workflow to their specific behavior, but neither is a lane driver anymore.

**Why Opus 5 became the default (2026-07-24), on top of that history.** Opus 5 launched today at the same price as Opus 4.8, positioned by Anthropic as "close to Fable 5 intelligence at half the price," with documented self-verification improvements. Every capability claim behind this is Anthropic's own launch-day material — zero field data exists yet, the exact evidence class the wizard's own process treats with skepticism (see this document's trial-flagged framing). The wizard maintainer chose to adopt it as default anyway, judging the risk acceptable since Codex still gates every task and reverting is one settings change. Sonnet 5 remains the wizard's evidence-backed pick for lower-stakes work — Setup B, not deprecated.

4.6 remains Anthropic-supported until **≥ Feb 5, 2027** per the [official deprecation page](https://platform.claude.com/docs/en/about-claude/model-deprecations).

**Effort is model-aware, not blanket `max`.** Opus 5: `high` default for Setup A, `medium` for routine web/CRUD (changed 2026-08-02); `xhigh` is an escalation trigger for difficult/long-running work, not the default — effort tiers are static per session, but Opus 5 has documented adaptive reasoning *within* a fixed tier. Sonnet 5: `medium` default (CodeRabbit-tested), escalate `/effort high` → `xhigh` for hard tasks. Opus 4.8: `xhigh` (its own `max` overthinks). Opus 4.6: `max` (its one `xhigh`-less sweet spot). Set per-session with `/effort`, not a shell-rc or settings env var — persisting effort that way silently overrides a later `/effort` change after you switch models (see `SDLC.md`'s Lessons Learned for a real incident this caused). Also check for a stale `ANTHROPIC_DEFAULT_OPUS_MODEL` env var in your shell rc files — it silently overrides `/model opus` picker choices. OpenAI/Codex reviewer: `high` default (2026-08-01; cost and review-noise, not capability) — escalate to `xhigh` for unusually risky PRs, `max`/Pro above that (see the Final Review Policy above).

### Reading Setup A precisely

Clarified 2026-07-13, updated 2026-07-24 for the Opus 5 swap — these exact points kept getting re-confused; each rule states its why:

- **Effort starts at `high`, not `xhigh`** (changed 2026-08-02). Opus 5's own documented default is `high` for general use. Anthropic recommends "extra" (`xhigh`) specifically for difficult and long-running asynchronous work — treat that as an escalation trigger, not the standing default, and drop to `medium` for routine web/CRUD.
- **Model escalation swaps the driver, not the tier.** After 2 failed attempts, LOW confidence, or on high-stakes changes with Setup A already exhausted, a pinned Opus 4.8 (`claude-opus-4-8`) takes over as driver for a genuinely independent second pass — Opus-5-driver plus an Opus-5 advisor fallback would otherwise be a same-family self-check. Why a swap and not more effort: the lane's policy treats repeated failure as a sign the *approach* needs different eyes, not deeper reasoning on the same track.
- **Advisor failure has a fallback, not a shrug.** Fable 5 advises via `advisorModel: "fable"` — disabled by an Anthropic rollout on 2026-07-24, observed working again on 2026-08-16. Availability is a dated observation, so establish it by calling the tool. On a real failure, spawn a Fable subagent at `high` as the fallback reviewer immediately, exactly as the `/sdlc` skill prescribes. Why: the advisor's job is catching wrong approaches *before* they're built, so a transport failure changes how the advice is obtained — not whether the check happens.

## See Also

- [`CLAUDE_CODE_SDLC_WIZARD.md`](CLAUDE_CODE_SDLC_WIZARD.md) — Full wizard doc, including Stability tier opt-in for the wider model choice
- [`README.md` § Choosing Your Model](README.md#choosing-your-model) — Model selection philosophy
- [`AGENTS.md`](AGENTS.md) — Codex/reviewer guidelines used in all three full-discipline lanes
