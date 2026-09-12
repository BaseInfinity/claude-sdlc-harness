# Contributing to SDLC Harness

Thank you for your interest in improving the SDLC Harness!

## Quick Start

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes
4. Run tests (same scripts CI validate runs):
   ```bash
   ./tests/test-version-logic.sh && ./tests/test-analysis-schema.sh && \
   ./tests/test-workflow-triggers.sh && ./tests/test-cusum.sh && \
   ./tests/test-stats.sh && ./tests/test-hooks.sh && \
   ./tests/test-codex-gate-command-position.sh && \
   ./tests/test-review-leg-launcher-required.sh && \
   ./tests/test-clearance-binds-to-tree.sh && \
   ./tests/test-token-spike.sh && \
   ./tests/test-codex-progress-wrapper.sh && \
   ./tests/test-run-review-leg.sh && \
   ./tests/test-escalation-ladder.sh && \
   ./tests/test-review-verdict-schema.sh && \
   ./tests/test-post-comment.sh && \
   ./tests/test-audit-session-load.sh && \
   ./tests/test-compliance.sh && ./tests/test-sdp-calculation.sh && \
   ./tests/test-evaluate-bugs.sh && ./tests/test-evaluate-cli-mode.sh && \
   ./tests/test-wizard-installer.sh && \
   ./tests/test-calibration-scenarios.sh && \
   ./tests/test-score-analytics.sh && \
   ./tests/test-prove-it.sh && ./tests/test-self-update.sh && \
   ./tests/test-external-benchmark.sh && \
   ./tests/test-cli.sh && ./tests/test-setup-path.sh && \
   ./tests/test-docs-usability.sh && ./tests/test-plugin.sh && \
   ./tests/test-install-script.sh && ./tests/test-release-workflow.sh && \
   ./tests/test-release-dry-run-workflow.sh && \
   ./tests/test-cc-drift-check.sh && ./tests/test-cc-version-drift.sh && \
   ./tests/test-release-drift.sh && \
   ./tests/test-update-skill-step-7-8.sh && \
   ./tests/test-merge-gate.sh && \
   ./tests/test-roadmap-integrity.sh && \
   ./tests/test-cross-model-clearance.sh && \
   ./tests/test-stop-hook-terminates.sh && \
   ./tests/test-domain-detection.sh && \
   ./tests/test-autocompact-methodology.sh && \
   ./tests/test-node24-compliance.sh && \
   ./tests/test-effectiveness-scoreboard.sh && \
   ./tests/test-firmware-fixture.sh && \
   ./tests/test-doc-consistency.sh && \
   ./tests/test-usage-diagnostics.sh && \
   ./tests/test-model-config-batch.sh && \
   ./tests/test-api-feature-detection.sh && \
   ./tests/test-memory-audit-protocol.sh && \
   ./tests/test-community-paths.sh && \
   ./tests/test-persist-score-history.sh && \
   ./tests/test-fixtures-fail-closed.sh && \
   ./tests/test-local-shepherd.sh && \
   ./tests/test-repo-complexity.sh && \
   ./tests/test-prompt-hook-fires-once.sh && \
   ./tests/test-baseline-fires-once.sh && \
   ./tests/test-tdd-pretool-fires-once.sh && \
   ./tests/test-community-scanner.sh && \
   ./tests/test-community-fetch.sh && \
   ./tests/test-ground-truth.sh && \
   ./tests/test-update-skill-step-7-7.sh && \
   ./tests/test-update-skill-cli-version.sh && \
   ./tests/test-cleanup-period-guidance.sh && \
   ./tests/test-postmortem-lessons.sh && \
   ./tests/test-mcp-hook-audit.sh && \
   ./tests/test-agents-md-interop.sh && \
   ./tests/test-self-pr-review-skip.sh && \
   ./tests/test-cowork-drift.sh && \
   ./tests/test-skill-graduations.sh && \
   ./tests/e2e/run-simulation.sh && \
   ./tests/e2e/test-deterministic-checks.sh && \
   ./tests/e2e/test-scenario-rotation.sh && \
   ./tests/e2e/test-simulation-prompt.sh && \
   ./tests/e2e/test-pairwise-compare.sh && \
   ./tests/e2e/test-json-extraction.sh && \
   ./tests/e2e/test-eval-validation.sh && \
   ./tests/e2e/test-multi-call-eval.sh && \
   ./tests/e2e/test-eval-prompt-regression.sh
   ```
5. Submit a PR

## How We Evaluate Changes

We use statistical evaluation to ensure changes don't degrade SDLC enforcement quality.

### Why Multiple Trials?

AI is stochastic - same prompt, different outputs. Single measurements are unreliable.
We run 5 trials per evaluation to get statistically meaningful results.

### Scoring Criteria (10 points total)

| Criterion | Points | Type | What It Measures |
|-----------|--------|------|------------------|
| task_tracking | 1 | Deterministic | TodoWrite/TaskCreate usage (grep) |
| confidence | 1 | Deterministic | HIGH/MEDIUM/LOW stated (grep) |
| plan_mode_outline | 1 | AI-judge | Planning steps documented |
| plan_mode_tool | 1 | AI-judge | TodoWrite/TaskCreate, EnterPlanMode, or plan file |
| tdd_red | 2 | Deterministic | Test written before implementation (JSON tool_use) |
| tdd_green_ran | 1 | AI-judge | Tests executed |
| tdd_green_pass | 1 | AI-judge | All tests pass in final run |
| self_review | 1 | AI-judge | Meaningful code review step |
| clean_code | 1 | AI-judge | No dead code, coherent flow |
| design_system | 1 | AI-judge | UI scenarios only (+1 bonus point) |

**Multi-call LLM judge (v3):** Each AI-judged criterion is scored by its own focused API call with dedicated calibration examples. Reduces variance vs monolithic single-call scoring.

**Pairwise tiebreaker (v3.1):** When two scores are within 1.0 point, a holistic pairwise comparison runs on the full outputs to break the tie.

### SDP Scoring (Model Degradation Tracking)

PR comments now include SDP (SDLC Degradation-adjusted Performance) to distinguish "model issues" from "our issues":

| Layer | Metric | Source |
|-------|--------|--------|
| **L1: Model** | External Benchmark | DailyBench, LiveBench |
| **L2: SDLC** | Raw Score | Our E2E evaluation |
| | SDP (adjusted) | Raw × (baseline / current external) |
| **Combined** | Robustness | How well SDLC holds up vs model changes |

**Interpretation:**
- SDP > Raw = Model degraded, we adjusted up
- Robustness < 1.0 = Our SDLC is more resilient than the model (good!)
- Robustness > 1.0 = Our SDLC is more sensitive than the model (investigate)

### Statistical Methodology

- **5 trials** per evaluation (balances cost vs statistical power)
- **95% confidence intervals** using t-distribution
- **Overlapping CI method** for comparing before/after:
  - IMPROVED: candidate CI lower bound > baseline CI upper bound
  - STABLE: CIs overlap (no significant difference)
  - REGRESSION: candidate CI upper bound < baseline CI lower bound

### Tier System for PRs

| Source | Tier 1 (Quick) | Tier 2 (Full) |
|--------|----------------|---------------|
| Our auto-workflows | Always | Always |
| External PRs | Always | On request (`merge-ready` label) |

Tier 1 gives fast feedback (1 trial). Tier 2 gives statistical confidence (5 trials).

## CUSUM Drift Detection

We track scores over time using CUSUM (Cumulative Sum) to catch gradual drift that before/after comparisons might miss.

```bash
# Check current drift status
./tests/e2e/cusum.sh --status
```

If CUSUM shows drift, we investigate before the situation worsens.

## Version Update Testing (manual local-Max procedure, v1.51.0+)

When Claude Code releases a new version, the weekly workflow opens an auto-update PR. Before merging, a maintainer runs the version-test locally on Max:

```bash
npm i -g @anthropic-ai/claude-code@<new_version>
gh pr checkout <auto_update_pr>
tests/e2e/local-shepherd.sh <pr> --compare-baseline
```

Phase A semantics (regression — does the new CC break our SDLC?) come from the score delta vs main. Phase B semantics (do changelog-suggested doc changes help?) come from including those changes in the PR before running the shepherd.

> **Historical:** through v1.50.0, this was a CI cron (`version-test` in `weekly-update.yml`). Deleted in v1.51.0 (ROADMAP #231 Phase 3a) — $8-20/run, zero merged artifacts in 30 days.

## What Makes a Good PR

- **Focused**: One logical change per PR
- **Tested**: Existing tests pass, new tests for new functionality
- **Documented**: Update relevant docs if behavior changes
- **KISS**: Simpler is better

## What We Don't Accept

- Over-engineering (keep it simple)
- Changes without tests
- Breaking changes to core SDLC principles (TDD, confidence levels, planning)
- Removing statistical rigor from evaluation

## We're Open to Suggestions

This methodology is evolving. If you have ideas for improving our evaluation approach, open an issue first to discuss.

## Local Development

```bash
# Validate YAML workflows
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"

# Run all test scripts (same as CI validate job)
./tests/test-version-logic.sh
./tests/test-analysis-schema.sh
./tests/test-workflow-triggers.sh
./tests/test-cusum.sh
./tests/test-stats.sh
./tests/test-hooks.sh
./tests/test-codex-gate-command-position.sh
./tests/test-review-leg-launcher-required.sh
./tests/test-clearance-binds-to-tree.sh
./tests/test-hook-stdin-bounded.sh
./tests/test-evidence-exception-bound.sh
./tests/test-token-spike.sh
./tests/test-codex-progress-wrapper.sh
./tests/test-run-review-leg.sh
./tests/test-escalation-ladder.sh
./tests/test-review-verdict-schema.sh
./tests/test-post-comment.sh
./tests/test-audit-session-load.sh
./tests/test-compliance.sh
./tests/test-sdp-calculation.sh
./tests/test-evaluate-bugs.sh
./tests/test-evaluate-cli-mode.sh
./tests/test-wizard-installer.sh
./tests/test-calibration-scenarios.sh
./tests/test-score-analytics.sh
./tests/test-prove-it.sh
./tests/test-self-update.sh
./tests/test-external-benchmark.sh
./tests/test-cli.sh
./tests/test-setup-path.sh
./tests/test-docs-usability.sh
./tests/test-local-shepherd.sh
./tests/test-cowork-drift.sh
./tests/test-skill-graduations.sh
./tests/test-wizard-doc-hook-templates.sh
./tests/e2e/run-simulation.sh
./tests/e2e/test-deterministic-checks.sh
./tests/e2e/test-scenario-rotation.sh
./tests/e2e/test-simulation-prompt.sh
./tests/e2e/test-pairwise-compare.sh
./tests/e2e/test-json-extraction.sh
./tests/e2e/test-eval-validation.sh
./tests/e2e/test-multi-call-eval.sh
./tests/e2e/test-eval-prompt-regression.sh

# Run full E2E (requires an authenticated Claude Code CLI — runs via
# `claude --print` on your own session, not ANTHROPIC_API_KEY)
./tests/e2e/run-simulation.sh
```

## Questions?

Open an issue or check the [discussions](https://github.com/BaseInfinity/claude-sdlc-harness/discussions).

