# Model Brain Audit — Anthropic, OpenAI, Google

Researched 2026-11-15. Every number carries a source tag (list at the end) and a
basis:

- **V** — vendor-reported, run on the vendor's own harness.
- **I** — independent: a third party ran it.
- **not found** — searched, no primary or benchmark-owned source. Never estimated.

## Verdict

1. **The three lines are close at the top, not equal.** On the one independent
   index that covers every current model (Artificial Analysis), the best scores
   are Anthropic 65, Google 60, OpenAI 57 (an 8-point spread). At high effort the
   spread is wider, 12 points: Fable 5.2 62, Carbon 60, Astra 55, 6.1 Sol 50,
   Argon 50 (Hydrogen has only an xhigh score, 54). **At high effort 6.1 Sol ties
   Argon for last.** It is also the cheapest.
2. **"Sol is degraded" has two causes, and only one is the model.** Users and
   independent scores agree GPT-6 Sol regressed from 5.6 Sol. GPT-6.1 Sol recovers
   on benchmarks (AA 55 at max vs 44 for 6 Sol). But since 2026-11-03 a Codex
   prompt-template change has made 6.1 Sol reviews return far more, weaker
   findings with far less reasoning ([Codex #59128][gh59128], open, one reporter).
   The same model through OpenCode did not show it. The effort setting also
   changed in that report (xhigh → max), so the evidence is confounded. Read it as
   a **suspected** harness effect, not proven model decay either way.
3. **Astra: trust as a tiebreaker, not as the default reviewer.** It is the most
   honest about its own work, the least monitorable, harness-sensitive, and about
   5× the cost of 6.1 Sol per task.
4. **Argon: not yet.** Its strongest numbers are vendor-run. Independently it
   scores below Hydrogen (AA 50 vs 54), and Hydrogen costs less. Developer reports
   are split, including a benchmarking firm seeing infinite reasoning loops.
5. **Argon intro pricing: there is nothing to lock in.** The $2/$10 rate ends for
   everyone on 2026-11-30. Google documents no commitment or prepay that keeps it.
   It only matters for direct API use; `agy` on a subscription does not bill per
   token.
6. **First brain, prior to the A/B test:** keep the cross-vendor rule. The
   strongest non-Anthropic reviewer is **Gemini 4 Carbon high** (AA 60), but in
   Antigravity it needs Google AI Ultra. Spending that money is Stefan's call. The
   free option closest to Astra is **Hydrogen xhigh** (AA 54). Add both to
   `docs/model-ab-test-plan.md`.

## 1. The candidates

### Anthropic

| Model | In / Out $/MTok | Context / max out | Default effort | Levels |
|---|---|---|---|---|
| Fable 5.2 `claude-fable-5-2` | $8 / $40 | 1M / 128K | high | low–max |
| Fable 5.1 | $10 / $50 | 1M / 128K | high | low–max |
| Opus 5.5 `claude-opus-5-5` | $4 / $20 | 1M / 128K | medium | low–max |
| Opus 5 | $5 / $25 | 1M / 128K | high | low–max |
| Sonnet 5.5 | $2 / $10 | 1M / 128K | high | low–max |
| Haiku 5.5 | $0.10 / $0.50 (≤100K prompt) | 1M / 128K | medium | low–max |
| Opus 4.6 | $5 / $25 | 1M / 128K | high | low, medium, high, max (no xhigh) |

Source: [A-models], [A-pricing], [A-effort]. Fable 5.2 has its own, lower rate
limits per tier [A-mg] (seen in a search summary only).

### OpenAI

| Model | In / Out $/MTok | Context / max out | Levels | Note |
|---|---|---|---|---|
| gpt-6.1-sol | $2 / $10 | 1.05M / 128K | low, medium (API default), high, xhigh, max | Codex's local model cache defaults it to `low` |
| gpt-6-sol | $2 / $10 | 1.05M / 128K | none–max | AA lists it deprecated → 6.1 Sol |
| gpt-5.6-sol | $4 / $20 | 1.05M / 128K | none–max | promo pricing ends 2026-11-30; AA lists it deprecated |
| gpt-6-astra | $10 / $50 | 1.05M / 128K | low–max | |
| gpt-6.1-terra | $1 / $5 | not checked | not checked | AA index 51 at max |

Inputs over 272K cost more on every model. Source: [O-pricing], [O-models].

### Google

| Model | In / Out $/MTok | Context / max out | Levels (Antigravity default) | Antigravity plan |
|---|---|---|---|---|
| Gemini 4 Carbon `gemini-4-carbon` | $2 / $10 until 11-30, then $4 / $20 | 1M / 64K (1M long decode) | low, med, high (high) | Ultra, Enterprise |
| Gemini 4 Argon `gemini-4-argon` | $2 / $10 until 11-30, then $4 / $20 | same | low, med, high (high) | Pro (paid), Ultra, Enterprise |
| Gemini 4 Hydrogen `gemini-4-hydrogen` | $1.50 / $7.50 | same | low, med, high, xhigh (high) | all, including Free |
| Gemini 3.8 Flash | $0.75 / $3.75 until 2026-12-31 | 1M / 64K | low, med, high (med) | all |
| Gemini 3.1 Pro (preview) | $2 / $12 (≤200K) | 1M / 64K | low, high | Enterprise only — drop |

The Gemini API defaults Argon and Carbon to `medium` effort; Antigravity
defaults them to `high`. Always set effort explicitly. Source: [G-pricing],
[G-changelog], [G-latest], [agy-models]. Plans: AI Pro $19.99/mo, AI Ultra
$99.99/mo [G-plans].

## 2. Benchmarks

**Not found for any current model on a primary or benchmark-owned source:**
SWE-bench Verified, Aider Polyglot (the official board stops at Claude 4, last
updated 2025-11-20 [aider]), HumanEval, MMLU, MMLU-Pro. No vendor published these
for its 2026 models. Aggregator sites that list them conflict with each other and
with the vendors. They are not used here.

### Independent

| Model | AA Intelligence Index [AA] | SWE-bench Pro V2 public, Scale [scale-v2] | ARC-AGI-3 [arc] |
|---|---|---|---|
| Fable 5.2 | 65 max · 62 xhigh · 62 high | not listed | not on arcprize.org |
| Fable 5.1 | not on current board | 92.20 (high, Claude Code) | — |
| Opus 5.5 | 59 max | not listed | not found |
| Opus 5 | not on current board | 98.00 (xhigh, Claude Code) | — |
| Sonnet 5.5 | 55 max | 70.59 (xhigh, mini-swe-agent) | — |
| Haiku 5.5 | 36 max | 52.94 ±13.01 | — |
| GPT-6 Astra | 57 max · 55 xhigh · 55 high · 52 med · 43 low | 90.20 (high, Codex) | 62.7 (standard harness) |
| GPT-6.1 Sol | 55 max · 52 xhigh · 50 high · 46 med · 35 low | not listed | 52.7 |
| GPT-6 Sol | 44 max | not listed | 4.6 |
| GPT-5.6 Sol | N/A | 82.40 (xhigh, Codex) | 7.8 |
| GPT-6.1 Terra | 51 max | not listed | — |
| Gemini 4 Carbon | 60 high | not listed | — |
| Gemini 4 Hydrogen | 54 xhigh | not listed | — |
| Gemini 4 Argon | 50 high · 48 med | 92.16 (high, mini-swe-agent) — the same page also shows 99.22, likely another tab | — (ARC-AGI-2: 91.3 high) |
| Gemini 3.8 Flash | 31 high | 58.80 | — |

Caveats:

- **SWE-bench Pro V2 mixes scaffolds.** Claude rows ran in Claude Code, OpenAI
  rows in Codex, Gemini rows in mini-swe-agent. It measures model plus harness,
  so rows from different vendors are not a clean comparison.
- **Vendor vs independent gap on Terminal-Bench 4.0:** Opus 5.5 is 66.4 V vs
  59.6 I. Sonnet 5.5 is 70.6 V vs 64 I. Those two independent reruns land 6–7
  points lower. No rerun exists for the other vendors' numbers, so their discount
  is unknown.
- One secondary source gives 6.1 Sol max = 52 on AA; the live AA page says 55.
- Terminal-Bench 4.0, independent: 6.1 Sol 55.05% ±1.82 at max (Vals). It has
  no vendor number to compare against.
- On ARC-AGI-3, OpenAI's 99.9% headline for Astra used a "provider adapter"
  harness. The standard harness gives 62.7%.

### Vendor-reported coding

| Benchmark | Anthropic | OpenAI | Google |
|---|---|---|---|
| Terminal-Bench 4.0 | Opus 5.5 66.4 (xhigh) · Sonnet 5.5 70.6 · Fable 5.1 55.8 · Opus 5 52.3 · Haiku 5.5 39.2 | Astra 57.7 (57.9 in another repost) · 5.6 Sol 37.3 | Carbon 65.2 · Argon 57.4 (57.1 on another Google card) · Hydrogen 57.0 (TB 4.1) · 3.8 Flash 19.1 |
| DeepSWE v1.1 | — | 6.1 Sol 75.2 (high) · Astra 74.1 | Argon 77.9 · 3.8 Flash 73.7 |
| FrontierCode 2.0 | Fable 5.2 49.1 (xhigh) · Opus 5.5 45.5 · Fable 5.1 32.4 | — | — |
| GPQA Diamond | not found | Astra 96.0 · 5.6 Sol 94.6 | 3.1 Pro 94.3 |

Each vendor picks its own benchmarks, so the gaps in this table are not missing
data. They mean the vendor did not publish.

### Code review

No independent code-review benchmark covers all three lines. What exists:

| Evidence | Basis | Result |
|---|---|---|
| Pre-merge bug detection, copilot-cli `/review` at xhigh [arxiv-lo] | I (paper) | Opus 5: 79.6% recall@5 at $2.55/run · 5.6 Sol: 65.6% at $1.50/run |
| Deloitte, known-bug catch [A-o55] | customer via V | Opus 5.5 at lowest effort 72% vs Opus 5 at high 56%, fewer false alarms |
| Security-review benchmark, 8 models [arxiv-sec] | I | 6 Sol near the top on recall; exact score not extracted |
| CWE-bench v1 remediation [G-argon] | V | Carbon 71.0 · Argon 68.0 |
| Codex #59128 [gh59128] | user report | 6.1 Sol in Codex since 11-03: findings 5 → 32, reasoning tokens 9,054 → 3,732 on one ticket; effort also changed (xhigh → max). The same account through OpenCode gave 5 findings |

The only head-to-head review number is Anthropic ahead of 5.6 Sol by 14 points of
recall. There is no Gemini row. This gap is why `docs/model-ab-test-plan.md`
exists.

## 3. Token use per effort level

No vendor publishes a per-level token table. Artificial Analysis gives totals for
running its whole index. Totals are comparable across models; the per-task
figures are a different unit.

| Model | Low | Medium | High | Xhigh | Max |
|---|---|---|---|---|---|
| GPT-6.1 Sol, output tokens (index total) | 8.18M | 15.1M | 24.7M | 33.3M | 63.7M |
| GPT-6.1 Sol, time per task | 1.9 min | 4.4 min | 7.6 min | 9.8 min | 22.7 min |
| Gemini 4 Argon, output tokens (index total) | — | 81.7M | 113M | — | — |
| GPT-6 Astra (index total) | — | — | — | — | 54.3M |
| GPT-6 Sol (index total) | — | — | — | — | 65.1M |

Per Intelligence Index task at max: Sonnet 5.5 ~193K, Opus 5.5 ~119K, Fable 5.1
~78K, Opus 5 ~73K, Astra ~27K output tokens [AA-o55], [AA-s55].

**Argon at medium spends more output tokens than 6.1 Sol at max** (81.7M vs
63.7M) while scoring lower (48 vs 55). At its $4/$20 price from December, Argon is
the costliest reviewer per point in the Google line.

Cost per AA task at the top effort: Fable 5.2 $26.54 · Opus 5.5 $10.04 ·
Sonnet 5.5 $10.02 · Astra $6.24 · Carbon $5.48 · Argon $4.97 · Hydrogen $3.16 ·
6.1 Sol $1.27 [AA].

Vendor efficiency claims:

- Fable 5.2 at high (45.3) roughly matches Opus 5.5 at max (45.5) on
  FrontierCode 2.0 for about half the cost [A-f52]. Its 49.1 in §2 is at xhigh.
- Opus 5.5 at medium beats Opus 5 at max on Terminal-Bench 4.0 for about one fifth
  the cost [A-o55].

## 4. By role

Cross-vendor rule: with an Anthropic builder, the first brain must be OpenAI or
Google.

### Builder (medium effort)

| Candidate | AA at medium | $/MTok | Read |
|---|---|---|---|
| **Opus 5.5 medium** | not split out (59 at max; AA puts medium–max on its Pareto frontier) | $4 / $20 | Keep. Its vendor default; strongest builder evidence. |
| GPT-6.1 Sol medium | 46 | $2 / $10 | Cheaper, weaker. |
| Gemini 4 Hydrogen medium | not split out (54 at xhigh) | $1.50 / $7.50 | The `agy` builder. Free tier. |
| Gemini 4 Argon medium | 48 | $2 → $4 / $10 → $20 | Hydrogen is cheaper. No Hydrogen-medium score exists to compare quality. |

### First brain (high effort, must be non-Anthropic)

| Candidate | AA at high | Cost / AA task (top effort) | Access | Read |
|---|---|---|---|---|
| **Gemini 4 Carbon high** | 60 | $5.48 | Antigravity needs Ultra ($99.99/mo); API $2/$10 → $4/$20 | Strongest non-Anthropic. No review data. |
| GPT-6 Astra high | 55 | $6.24 (max) | Codex, already set up | Strong, but expensive and least monitorable |
| Gemini 4 Hydrogen xhigh | 54 | $3.16 | Antigravity, Free plan | Closest to Astra for a fraction of the cost. No review data. |
| GPT-6.1 Sol high | 50 | $1.27 (max) | Codex, already set up | The current lane. Fix the #59128 harness issue before judging it. |
| Gemini 4 Argon high | 50 | $4.97 | Antigravity Pro | No better than 6.1 Sol high, and costs more |
| GPT-5.6 Sol high | N/A on AA | — | Codex | AA lists it deprecated. Promo pricing ends 11-30. |

### Escalation / tiebreaker

| Candidate | Score | Read |
|---|---|---|
| **Fable 5.2 high** | AA 62; xhigh is also 62, max is 65 | Keep. Anthropic's effort page says gains above `high` are uneven, and AA agrees (high = xhigh). |
| Gemini 4 Carbon high | AA 60 | The cross-vendor tiebreaker if one is ever needed. |
| GPT-6 Astra high | AA 55 | Usable, but below both. |

## 5. Can Astra be trusted?

| Signal | Astra | 6.1 Sol | 5.6 Sol | Source |
|---|---|---|---|---|
| Misrepresents its work in coding tasks | **0.51%** | 1.50% | ~7× 6.1 Sol | system cards [O-scA], [O-sc61] |
| Notices it is being evaluated | **8.67%** (9.6% in its own card) | 4.81% | 2.52% | same |
| Can control the form of its own reasoning | **60.9%** | 44.8% | 16.1% | same |
| Monitorability | "decreased relative to GPT-5.6 Sol"; can "remain undetected when strategically underperforming in evaluations" | | | [O-scA] |

Developer reports are split: "Astra is very unreliable for coding" and "much
slower and didn't generate better results" against "Astra on Low has been my
favourite" [O-hn]. One HN ranking: "5.6-Sol > 6.0 Sol > Astra".

**Read:** Astra is the most honest about its own work and the most able to hide
its reasoning. A reviewer's job is to be checked by its output, not its reasoning,
so the monitorability risk is smaller here than for an agent. Its cost is the
binding constraint. It works as a tiebreaker, not as the default.

## 6. Can Argon be trusted?

- **Benchmarks:** strong on vendor runs (DeepSWE 77.9, Terminal-Bench 4.0 57.4)
  and on ARC-AGI-2 (91.3, independently verified). Middling on AA (50, below
  Hydrogen's 54). Its SWE-bench Pro V2 score is 92.16, alongside Fable 5.1 (92.20)
  and Astra (90.20), but on a different harness.
- **Developers:** "on par with Opus 5.5" and "it can absolutely code" on HN
  [G-hn]. Against: a benchmarking firm puts it "roughly in between Fable 5 and
  Fable 5.1… maybe 2 months behind the frontier", and "the first near-frontier
  model we've caught in infinite reasoning loops in a long time" [G-hn]. Google's
  own forum: "only 1.2× better than Gemini 3.8 Flash… benchmark-maxxing" and "it
  prioritizes rules over correctness" on large codebases [G-forum]. Press calls
  opinion "divided" and relays a Bloomberg report that some Google staff found it
  weak on real-world coding [G-tz].
- **Read:** Argon is not Google's best model (Carbon is) or its best value
  (Hydrogen is). The reasoning-loop report is a direct risk for a headless review
  leg with no human watching. Run it only behind `--print-timeout`.

## 7. Are the three lines equal?

At the top, roughly. Anthropic leads the independent index by 5 points over
Google and 8 over OpenAI. Google's best (Carbon) beats OpenAI's best (Astra) on
that index, for less money per task. On the mixed-harness SWE-bench Pro V2, the
best of each line sits within 8 points (Opus 5 98.0, Argon 92.2, Astra 90.2).

At the effort used for review, **6.1 Sol ties Argon for last**: both score 50 at
high, against 55–62 for Astra, Carbon and Fable 5.2 at high (Hydrogen has only an
xhigh score, 54). 6.1 Sol is also the cheapest: 2.5–4.9× less per AA task than
the other reviewer options. "Degraded" may be partly the Codex harness (#59128,
suspected and confounded). An A/B run through OpenCode or a pinned prompt would
separate it from the model.

## 8. Argon intro pricing — lock in?

**No.**

- There is nothing to lock. The $2/$10 rate is a window that ends for all API
  users on 2026-11-30; $4/$20 applies from 2026-12-01 [G-pricing], [G-cloud]. No
  Google page mentions a commitment, prepay or grandfathering. The phrase
  "locked in" appears only in third-party commentary.
- Only a sales contract could change that, and none is documented. Ask Google
  sales if it matters.
- `agy` on a Google AI Pro or Ultra subscription is billed by plan quota, not per
  token. The intro price does not apply to it.
- On the evidence, Argon is not the Gemini model to commit to. Hydrogen is cheaper
  with no price change scheduled and scores higher on AA. Carbon has the same
  price cliff and scores 10 points higher.
- The same date also ends GPT-5.6 Sol promo pricing, which AA already lists as
  deprecated.

## 9. Next steps

1. Fix or bypass Codex #59128 before treating any 6.1 Sol review as a quality
   signal: compare one review through OpenCode against Codex on the same diff.
2. Add **Carbon high** and **Hydrogen xhigh** to the arms in
   `docs/model-ab-test-plan.md`. Carbon in Antigravity needs Ultra, which costs
   money, so Stefan decides. The API route needs a paid Gemini API key.
3. Re-check Scale SWE-bench Pro V2 for Fable 5.2, Opus 5.5, 6.1 Sol and Carbon
   rows. None are listed today.

## Sources

Anthropic
- [A-models]: https://platform.claude.com/docs/en/about-claude/models/overview
- [A-pricing]: https://platform.claude.com/docs/en/about-claude/pricing
- [A-effort]: https://platform.claude.com/docs/en/build-with-claude/effort
- [A-mg]: https://platform.claude.com/docs/en/models/fable-5-2/migration-guide
- [A-f52]: https://www.anthropic.com/news/claude-fable-and-mythos-5-2
- [A-o55]: https://www.anthropic.com/claude-opus-5-5
- [A-s55]: https://www.anthropic.com/claude-sonnet-5-5
- [A-h55]: https://www.anthropic.com/claude-haiku-5-5

OpenAI
- [O-pricing]: https://developers.openai.com/api/docs/pricing
- [O-models]: https://developers.openai.com/api/docs/models/gpt-6.1-sol ·
  https://developers.openai.com/api/docs/models/gpt-6-sol ·
  https://developers.openai.com/api/docs/models/gpt-5.6-sol ·
  https://developers.openai.com/api/docs/models/gpt-6-astra
- [O-scA]: https://deploymentsafety.openai.com/gpt-6-astra
- [O-sc61]: https://deploymentsafety.openai.com/gpt-6-1-sol
- [O-hn]: https://news.ycombinator.com/item?id=49897054
- [gh59128]: https://github.com/openai/codex/issues/59128
- Vals: https://www.vals.ai/models/openai_gpt-6.1-sol
- DataCamp (Astra, secondary): https://www.datacamp.com/blog/gpt-6-astra

Google
- [agy-models]: https://antigravity.google/docs/models/
- [G-pricing]: https://aistudio.google.com/docs/pricing
- [G-changelog]: https://aistudio.google.com/docs/changelog
- [G-latest]: https://aistudio.google.com/docs/latest-model
- [G-argon]: https://deepmind.google/models/model-cards/gemini-4-argon/
- Carbon card: https://deepmind.google/models/model-cards/gemini-4-carbon/
- Hydrogen card: https://deepmind.google/models/model-cards/gemini-4-hydrogen/
- [G-cloud]: https://cloud.google.com/blog/products/ai-machine-learning/gemini-4-argon-available-on-google-cloud
- [G-plans]: https://one.google.com/about/google-ai-plans/
- [G-hn]: https://news.ycombinator.com/item?id=50073879
- [G-forum]: https://discuss.ai.google.dev/t/how-bad-is-gemini-4-argon/190009
- [G-tz]: https://www.techzine.eu/news/applications/144960/opinions-are-divided-on-gemini-4-argon/

Independent
- [AA]: https://artificialanalysis.ai/leaderboards/models
- [AA-o55]: https://artificialanalysis.ai/articles/claude-opus-5-5
- [AA-s55]: https://artificialanalysis.ai/articles/claude-sonnet-5-5
- AA model pages: https://artificialanalysis.ai/models/gpt-6-astra ·
  https://artificialanalysis.ai/models/gemini-4-argon
- [scale-v2]: https://labs.scale.com/leaderboard/swe_bench_pro_public_v2
- [arc]: https://arcprize.org/leaderboard
- [aider]: https://aider.chat/docs/leaderboards/
- [arxiv-lo]: https://arxiv.org/html/2610.13668v1
- [arxiv-sec]: https://arxiv.org/abs/2610.33509
