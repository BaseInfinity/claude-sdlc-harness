# Reliable and Frontier AI Lane Research — Claude Side

**Research date:** 2026-10-18
**Status:** Recommendation and research snapshot; not an applied policy change
**Companion to:** `codex-sdlc-wizard/AI_LANE_RESEARCH_2026-10-18.md`

## Decision

Aligns with the Codex-side two-axis model. The same two independent decisions apply:

1. **Model lane:** Reliable or Frontier selects the model generation and field-confidence profile.
2. **Task rigor:** routine, standard, or critical selects how many brains and how much verification the task earns.

The Claude side converges on the same architecture with one difference: the home builder is an Anthropic model (Opus), so the always-on cross-model reviewer is an OpenAI model (Sol), and the conditional third brain is Fable (Anthropic's highest-capability model, different family tier than Opus).

## Reliable Lane

| Role | Model | Effort | Notes |
|---|---|---|---|
| **Builder** | Opus 4.6 (`claude-opus-4-6[1m]`) | `max` | Known-good, model-specific exception — not evidence that every model should run at max |
| **Cross-model reviewer** | GPT-5.6 Sol via `codex exec` | `xhigh` | Quality-first policy for this maintainer repo; consumer repos default to `high` |
| **Conditional third brain** | Fable 5.1 (`claude-fable-5-1`) via `advisor()` | `high` | Fires on disagreement, design questions, or <95% confidence |

### Field evidence

- Opus 4.6 has been the daily driver since Feb 2026. Active status confirmed from [Anthropic's deprecation page](https://platform.claude.com/docs/en/about-claude/model-deprecations) — retirement not sooner than February 5, 2027.
- GPT-5.5 retired from Codex CLI on 2026-10-14 (#715). Migration to GPT-5.6 Sol completed in `scripts/run-review-leg.sh` before the deadline; doc sweep completed 2026-10-18.
- Fable 5.1 (`claude-fable-5-1`) confirmed as a real, Active model ID — retirement not sooner than September 1, 2027. Previously carried as `claude-fable-5` (retirement not sooner than June 9, 2027); the explicit 5.1 pin has longer runway.

## Frontier Lane

| Role | Model | Effort | Notes |
|---|---|---|---|
| **Builder** | Opus 5.5 (`claude-opus-5-5`) | `high` | "Feels like 4.6 again" — community consensus; Anthropic's default is `medium`, `high` is quality-first |
| **Cross-model reviewer** | GPT-5.6 Sol via `codex exec` | `xhigh` | Same as Reliable; evaluate GPT-6.1 Sol as successor |
| **Conditional third brain** | Fable 5.1 (`claude-fable-5-1`) via `advisor()` | `high` | Same as Reliable |

### Why GPT-5.6 Sol and not GPT-6.1 Sol (yet)

GPT-6.1 Sol scores higher on every benchmark and costs half the tokens ($2/$10 vs $4/$20). On paper it strictly dominates. But:

- Launched September 29, 2026 — under 3 weeks of field data as of this writing.
- Codex CLI 0.159.1 makes it the default, but [ChatGPT-account auth may reject it](https://smartscope.blog/en/blog/codex-gpt-6-1-sol-not-supported-chatgpt-account-2026/) (reported Oct 3).
- The Codex-side research recommends evaluating 6.1 Sol before adopting it as the reviewer. This aligns: keep 5.6 Sol as the Reliable reviewer, trial 6.1 Sol in the Frontier lane.

When to move: after representative review slices show preserved quality. The `REVIEW_MODEL` env var in `scripts/run-review-leg.sh` makes per-run testing trivial — `REVIEW_MODEL=gpt-6.1-sol` on a single review leg, compare findings.

## Opus 5.5 Effort Findings

### What the research shows

| Effort | Tasks solved (100-task suite) | Token usage vs baseline | Source |
|---|---|---|---|
| medium | ~51 | 1× | [DEV Community effort test](https://dev.to/jaehyun_cho_0dff271e0d2e5/claude-opus-55-effort-levels-tested-low-to-max-4p97) |
| high | ~54 | ~1.8× | Same |
| xhigh | 56 | 2.6× | Same |
| max | 58 | 4.5× | Same |

- **medium → high:** +3 tasks, +80% tokens. Good tradeoff.
- **high → xhigh:** +2 tasks, +44% tokens. Marginal.
- **xhigh → max:** +2 tasks, +73% tokens. Poor ROI for routine work.

### Anthropic's own guidance

- Opus 5.5 defaults to `medium` — the only model where Claude Code doesn't default to `high`.
- "Opus 5.5 at medium matches or exceeds Opus 5 at high" — [Anthropic effort docs](https://platform.claude.com/docs/en/build-with-claude/effort).
- "Reserve xhigh and max for work whose added completion value pays for more output tokens and elapsed time."
- Max "may show diminishing returns and is prone to overthinking."

### Conclusion

Use **Opus 5.5 `high`** as the Frontier builder. `xhigh` for bounded reviewer or task-scoped escalation. `max` only after evidence that `xhigh` is insufficient. This matches the Codex-side conclusion.

## Opus 4.6 Effort Findings

- Opus 4.6 supports `max` as its deepest level — no `xhigh`.
- `max` on 4.6 does not overthink — it is the one Opus where `max` is the sweet spot, not the ceiling. Community reports confirm this is specific to 4.6.
- [Anthropic's April 23 postmortem](https://www.anthropic.com/engineering/april-23-postmortem) noted that even Opus 4.6 High sometimes consumed disproportionate latency and tokens. Max was not the problem model.

Conclusion: retain **Opus 4.6 `max`** as a model-specific exception. Aligns with the Codex-side finding.

## Fable 5.1 Findings

- Fable 5.1 scores 83.34/100 overall, ranked #3 out of 505 models ([benchlm.ai](https://benchlm.ai/md/models/claude-fable-5-1.md)).
- Coding: 77.6 (higher than GPT-6.1 Sol's 66.4 on shared benchmarks).
- Overall LLM Stats Score vs GPT-6.1 Sol: 53.5 vs 53.9 — nearly tied.
- Context: 1.0M tokens.
- The value in Brain 2 is not raw capability over Brain 1 — it is model-family diversity (Anthropic vs OpenAI) and the orchestrator role (resolves disagreements with specific assignments).

### Advisor availability

- `advisor()` forwards the full conversation transcript. Not cached between calls. The most expensive call shape.
- Server-side disabled 2026-07-24, observed working again 2026-08-16. Both are dated observations.
- A capped Fable meter (100% used) did not block `advisor()` on 2026-08-16 — try the call before concluding it's unavailable.
- Fallback: spawn a Fable 5.1 subagent at `high` on transport failure.

## GPT-6.1 Sol Findings (for future evaluation)

- Released September 29, 2026. Near-Astra intelligence at ~1/5 the cost.
- $2/$10 per MTok (vs GPT-5.6 Sol $4/$20 — 50% cheaper).
- Terminal-Bench 4.0: 12 points above GPT-6 Sol. DeepSWE: 75.2% at `high` — above Astra's best run.
- 13% slower than GPT-6 Sol; drops Chat Completions tool calling.
- Available in Codex CLI 0.159.1+ (`codex exec -m gpt-6.1-sol`).
- Supports low, medium, high, xhigh, max, and ultra.
- GPT-6 Astra has documented reliability issues in Codex ([GitHub](https://github.com/openai/codex/issues/42937), [OpenAI Community](https://community.openai.com/t/codex-work-gpt-6-astra-has-a-serious-model-downgrading-issue/1397173)). GPT-6.1 Sol was designed as the answer — same capability tier, better reliability, lower cost.

## Task-Rigor Overlay

Identical to the Codex-side design:

| Rigor | Examples | Required brains |
|---|---|---|
| **Routine** | Doc fixes, config edits, mechanical maintenance | Builder + targeted verification; reviewer optional |
| **Standard** | Features, bugs, tested refactors | Builder + cross-model reviewer |
| **Critical** | Wizard enforcement, installers, security/privacy, releases, auth, payments | Builder + reviewer + third brain when first two don't settle the risk |

## Cross-Ecosystem Alignment

| | Claude home | Codex home |
|---|---|---|
| **Reliable builder** | Opus 4.6 `max` | GPT-5.6 Sol `high` (xhigh in wizard repo) |
| **Reliable reviewer** | GPT-5.6 Sol `xhigh` | Opus 4.6 `max` |
| **Reliable third brain** | Fable 5.1 `high` | GPT-6 Astra `xhigh` |
| **Frontier builder** | Opus 5.5 `high` | GPT-6.1 Sol `high` |
| **Frontier reviewer** | GPT-5.6 Sol `xhigh` (evaluate 6.1) | Opus 5.5 `xhigh` |
| **Frontier third brain** | Fable 5.1 `high` | GPT-6 Astra `xhigh` |

The pattern holds: builder from your home family, reviewer from the other family, third brain is the highest-capability model available when escalation is justified.

## Operating Rule

Same as Codex side:

1. Builder produces implementation and verification evidence.
2. Cross-model reviewer performs a blind review.
3. Builder resolves actionable findings and reruns tests.
4. Third brain only on escalation triggers.

Escalation triggers: disagreement, security/auth/migration/release boundary, repeated same-class findings, tests can't establish the property, ambiguous and expensive to reverse, or user explicitly requests.

Three model passes do not establish "99% confidence." Confidence comes from independent review plus executable evidence.

## Deprecation Timeline (Primary Source)

From [Anthropic model deprecations](https://platform.claude.com/docs/en/about-claude/model-deprecations), fetched 2026-10-10:

| Model | Status | Retirement |
|---|---|---|
| `claude-opus-4-6` | Active | Not sooner than 2027-02-05 |
| `claude-opus-5-5` | Active | Not sooner than 2027-09-22 |
| `claude-fable-5-1` | Active | Not sooner than 2027-09-01 |
| `claude-fable-5` | Active | Not sooner than 2027-06-09 |
| `claude-opus-5` | Active | Not sooner than 2027-07-24 |

GPT-5.5 retired from Codex CLI on 2026-10-14. GPT-5.5 remains available on the OpenAI API but not through `codex exec`.

## Sources

### Anthropic

- [Model deprecations page](https://platform.claude.com/docs/en/about-claude/model-deprecations) — primary source for lifecycle status
- [Effort documentation](https://platform.claude.com/docs/en/build-with-claude/effort)
- [Opus 5.5 prompting guidance](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5)
- [Introducing Claude Opus 5.5](https://www.anthropic.com/claude-opus-5-5)

### Community and benchmarks

- [ClaudeFolio: "Opus 5.5 feels like Opus 4.6 again"](https://claudefolio.com/blog/were-so-back-opus-5-5-feels-like-opus-4-6-again)
- [Every: Vibe Check — Opus 5.5 pulling Codex converts back](https://every.to/vibe-check/vibe-check-opus-5-5-is-pulling-our-codex-converts-back-to-claude)
- [DEV Community: Opus 5.5 effort levels tested](https://dev.to/jaehyun_cho_0dff271e0d2e5/claude-opus-55-effort-levels-tested-low-to-max-4p97)
- [CodeRabbit: Opus 5.5 benchmarks](https://www.coderabbit.ai/blog/opus-5-5-model-review)
- [Artificial Analysis: GPT-5.6 Sol vs GPT-5.5](https://artificialanalysis.ai/models/comparisons/gpt-5-6-sol-high-vs-gpt-5-5)
- [Artificial Analysis: GPT-6.1 Sol replaces 6 Sol](https://artificialanalysis.ai/articles/gpt-6-1-sol-replaces-gpt-6-sol-after-just-7-days-with-near-astra-intelligence)
- [Fable 5.1 vs GPT-6.1 Sol](https://llm-stats.com/models/compare/claude-fable-5-1-vs-gpt-6.1-sol)
- [Cross-model LLM code review — arXiv](https://arxiv.org/pdf/2607.21656)

### OpenAI (GPT-side context)

- [GPT-5.5 retirement notice](https://letsdatascience.com/news/openai-retires-gpt-55-from-chatgpt-and-codex-1a6f69be)
- [GPT-6 Astra reliability issues — Codex GitHub](https://github.com/openai/codex/issues/42937)
- [GPT-6 Astra model downgrading — OpenAI Community](https://community.openai.com/t/codex-work-gpt-6-astra-has-a-serious-model-downgrading-issue/1397173)
- [GPT-6.1 Sol benchmarks — Vellum](https://www.vellum.ai/blog/gpt-6-1-sol-benchmarks-explained)

Community reports are anecdotal and sometimes reflect changing service conditions, client bugs, prompting differences, or different task shapes. They inform defaults but do not replace representative local evaluations.
