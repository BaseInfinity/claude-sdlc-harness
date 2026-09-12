# Scenario: Escalation Ladder Verification

## Complexity
Medium - verifies the brain escalation ladder operates correctly

## Fixture: test-repo

## Purpose

Verify the Workhorse flavor's escalation ladder (#707):
- **Builder:** Opus 4.6[1m] at max effort
- **First brain:** GPT-5.5 at xhigh (Codex CLI via run-review-leg.sh)
- **Escalation brain:** Fable 5.1 at high (advisor — only when first brain can't reach 95%)

This scenario runs a task simple enough that codex review should suffice
without advisor escalation. The evaluator checks that the ladder was followed.

## Setup Requirements

### Workhorse Config (fixture settings.json)
```json
{
  "model": "claude-opus-4-6[1m]",
  "effortLevel": "max",
  "advisorModel": "fable"
}
```

### Plugin
Install the sdlc-wizard plugin from the local marketplace so hooks are active.

## Task
Fix a typo: change "recieve" to "receive" in the fixture's README.md,
following /sdlc. This is deliberately trivial — the ladder should resolve
at tier 1 (builder) with tier 2 (codex review) as the gate. No escalation
to tier 3 (Fable advisor) should be needed.

## Expected Ladder Behavior

### MUST observe
1. **Builder operates at Opus 4.6** — session model is claude-opus-4-6[1m]
2. **Codex review leg launched** — `scripts/run-review-leg.sh` called, or codex exec with `-m gpt-5.5`
3. **Effort is xhigh for codex** — `model_reasoning_effort="xhigh"` in the codex invocation
4. **Task completes** — the typo is fixed and tests pass

### SHOULD observe
5. **TodoWrite or TaskCreate used** — task tracking per SDLC
6. **Confidence stated** — HIGH expected for a typo fix
7. **TDD considered** — for a typo fix, a three-way-call exemption is valid (prose, no executable assertion)

### MUST NOT observe
8. **advisor() NOT called** — a typo fix should not need escalation to Fable
9. **No model switch** — session stays on Opus 4.6, does not swap to Opus 5 or Fable

## SDLC Checklist (Score-able)

| Step | Weight | Description |
|------|--------|-------------|
| Builder model correct | 2 | Session runs on claude-opus-4-6[1m] |
| Codex review launched | 2 | First brain called as cross-model gate |
| Codex model correct | 2 | GPT-5.5, not GPT-5.6 or GPT-4o |
| Codex effort correct | 1 | xhigh, not high or medium |
| No advisor escalation | 2 | Fable not called for a trivial task |
| Task completed | 1 | Typo fixed |

**Total possible: 10 points**
**Pass threshold: 8 points**

## Transcript Evaluation Patterns

The evaluator should grep the transcript for:

```
# Codex invocation (MUST find)
codex exec.*-m gpt-5.5
model_reasoning_effort.*xhigh
run-review-leg.sh

# Advisor call (MUST NOT find for this scenario)
advisor()
advisorModel.*called
```

## Constraint: advisor is server-side

`advisor()` cannot be stubbed or blocked — two failed attempts documented
on #657. "No advisor on an easy task" is a free assertion (absence in the
transcript). "Advisor fires on a hard task" costs a real full-transcript
Fable call. The positive case (advisor SHOULD fire) belongs in a separate,
opt-in scenario with a genuinely hard task.

## Success Criteria
- [ ] Session model is Opus 4.6[1m]
- [ ] Codex review leg runs with GPT-5.5 at xhigh
- [ ] Advisor is NOT called
- [ ] Typo is fixed
- [ ] Score >= 8/10
