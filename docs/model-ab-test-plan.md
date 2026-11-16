# Cross-Model Reviewer A/B Test Plan

**Goal:** pick the default cross-model review leg. The maintainer reports Sol
reviews as degraded; `docs/model-brain-audit.md` §7 has the evidence. Part of it
may be a Codex harness effect (Codex #59128, one confounded report), not the
model. **Decision rule:** the winner has the highest mean recall
of known P0/P1 bugs across all runs, with a false-positive rate no worse than the
current Sol 5.6 high baseline. Cost and time break ties.

## Arms

| Arm | Harness | Slug | Effort | Pin source |
|---|---|---|---|---|
| A. Sol 5.6 high (baseline) | Codex | `gpt-5.6-sol` | high | local `~/.codex/models_cache.json` |
| B. Sol 6.1 medium | Codex | `gpt-6.1-sol` | medium | same |
| C. Astra low | Codex | `gpt-6-astra` | low | same |
| D. Hydrogen xhigh | agy | from `agy models` | xhigh | `--model` + `--effort`; Free plan |
| E. Argon high | agy | from `agy models` | high | same; needs Google AI Pro |
| F. Carbon high | agy | from `agy models` | high | same; needs Google AI Ultra ($99.99/mo) — run only if Stefan approves the plan |

- "Astra" is assumed to be `gpt-6-astra`, the only Astra slug in the local Codex
  model cache. Confirm before running.
- agy slugs are not verified. `agy` is not installed here. Run `agy models` and
  record the exact slug in the results file. An unknown slug exits 1, so a typo
  fails loudly instead of silently swapping models.
- All three Codex slugs list `low`, `medium` and `high` in
  `supported_reasoning_levels` in the local model cache. Their defaults differ
  (Sol `low`, Astra `medium`), so every run must pin effort explicitly.
- Codex arms run through `scripts/run-review-leg.sh`, which the gate requires and
  which guarantees closed stdin and an exit status. **Its effort is hard-coded:**
  `scripts/run-review-leg.sh:275-276` passes `-m "${REVIEW_MODEL:-gpt-5.6-sol}"`
  and `-c 'model_reasoning_effort="xhigh"'`, then appends extra args. The model
  pins via `REVIEW_MODEL`. Whether a second, appended effort `-c` override wins
  over the first is unverified. Before any
  run, add a `REVIEW_EFFORT` env var to the launcher (default `xhigh`, with a
  test), then:
  `REVIEW_MODEL=gpt-6.1-sol REVIEW_EFFORT=medium scripts/run-review-leg.sh OUT.md "$PROMPT" --sandbox read-only`
- Confirm the effort each run actually used from its Codex session log. A run
  whose logged effort differs from the arm is discarded.
- The launcher forces `--output-schema skills/sdlc/review-verdict.schema.json`
  (`scripts/run-review-leg.sh:231,278`). Every arm uses that one schema, so the
  output contract is shared.
- agy arms run headless with the permission trap closed, at their own arm's
  effort (`xhigh` for D, `high` for E and F):
  `agy -p "$PROMPT" --model "$SLUG" --effort "$EFFORT" --output-format json --json-schema skills/sdlc/review-verdict.schema.json --print-timeout 15m`
  with read tools in `permissions.allow`. The verdict is in `.structured_output`. Check stderr for a permission-denied
  notice. A headless denial still exits 0, and a reviewer that could not read the
  repo looks like a clean review.

D, E and F are same-vendor with a Gemini builder. Measure them anyway: the result
decides whether `cross_vendor_review: required` can relax for the Antigravity
port (see `docs/antigravity-sdlc-port-scope.md`).

## Diffs

Use replayed real diffs with known ground truth, not synthetic bugs alone.
Synthetic bugs measure whether a model finds planted bugs, which is not the job.

| Diff | What | Known findings | Why |
|---|---|---|---|
| d1 | `codex-thread.py` round 1 (the version before the `fix(conduct): codex-thread.py …` commits) | 3 P1 | Reused from the 2026-11-07 effort A/B. Those results live in session notes, not in this repo **[unverified here]** |
| d2 | the CONTRIBUTING over-listing change from the same A/B | 1 P1 | Same |
| d3 | `79d6ddc` — adds `codex-gate-check.sh` (#420/#428) | ≥3, see below | A gate that never blocks is the bug class this review exists to catch |
| d4 | a clean diff: a merged PR with zero review findings and no later fix to the same lines | 0 | Measures false positives. Not yet chosen. |

d3 replays `79d6ddc^..79d6ddc`. Known defects in it, each fixed later:

- P0: exits 0 on every path, including "REQUIRED", so it never blocks. Fixed by
  `ddc755f` (#436), whose message says so.
- P1: its tests asserted only on printed text, never on exit status. Same commit
  message.
- P1: stale-certification bypass. Fixed by `3d568c1` (#437).
- Quoted-command extraction bypass, fixed by `ddc755f`. Reported by the Sol
  review of this plan, not yet confirmed from the diff.

Confirm each against `79d6ddc` before the first run.

The exact base and head SHAs for d1 and d2 are not recorded in the earlier
notes. Recover them from the `fix(conduct): codex-thread.py …` history and the
CONTRIBUTING commits, and freeze them in `tests/ab/diffs.txt` before any run.
Ground truth for each diff is the set of bugs a later commit fixed. Write it down
before running any arm.

Each diff is materialized as a worktree at the head SHA, so the reviewer can read
the surrounding code, not only the patch.

## Prompt

One prompt, byte-identical across arms, stored in `tests/ab/prompt.md`. No hints
about the known bugs. Output is the shipped verdict schema: `verdict`
(`CERTIFIED` / `NOT_CERTIFIED`), `shape`, `confidence`, and `findings[]` with
`severity`, `target`, `disposition`, `claim`. The schema has no file or line
field, so the prompt asks for `file:line` at the start of each `claim`.

## Runs

- **n = 3 per arm per diff.** 6 arms × 4 diffs × 3 = 72 runs (60 without F). The 2026-11-07 A/B
  saw Sol xhigh go 3/3 then 1/3 on the same diff (session notes, not in this
  repo), so one run per cell is noise.
- Run arms **sequentially**, not in parallel, to avoid rate-limit skew.
- Fresh session per run. No `--continue`.

## Measures

| Metric | How |
|---|---|
| Recall | known P0/P1 found ÷ known P0/P1, per run, on d1–d3 only. d4 has no known bugs and no recall. A finding counts if it names the right file and the failure mode, whatever severity it assigns. |
| Severity calibration | count of known P1s rated P2 or lower |
| False positives | findings the scorer cannot reproduce, per run, on every diff. On d4 a reproduced finding is a real bug: d4 then stops being clean, joins d1–d3, and the clean slot is refilled |
| Extra real findings | findings outside ground truth that the scorer confirms by reproducing them |
| Variance | min and max recall across the 3 runs |
| Completion | did the run exit 0 with parseable JSON within 15 min |
| Cost | tokens in/out (Codex logs; agy `--output-format json` / `/usage`) |
| Wall time | seconds per run |

## Scoring

- Strip the arm name from each output and shuffle before scoring.
- Score against the written ground truth. Then probe every extra finding by
  reproducing it on the diff; an unreproduced claim is a false positive.
- Scorer is a model not under test (Opus 5.5 or Fable 5.2), then a human spot
  check of all P0/P1 calls and every disagreement.

## Output

`tests/ab/results-2026-11.md`: one table per diff with every run, then a summary
table of mean recall, recall range, FP per run, completion rate, mean tokens and
mean time per arm. The recommendation names one arm and the numbers that chose it.

## Known limits

- 4 diffs is small. A winner by less than one known bug of mean recall is a tie.
- All diffs come from this repo (bash, Python, Markdown). Results may not carry to
  TypeScript or Go codebases.
- agy has a documented headless failure mode (silent permission denial, exit 0).
  Any agy run with a denial notice on stderr is discarded and rerun, not scored.
