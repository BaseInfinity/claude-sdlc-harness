---
name: sdlc
description: Full SDLC workflow for implementing features, fixing bugs, refactoring code, testing, releasing, publishing, and deploying. Use this skill when implementing, fixing, refactoring, testing, adding features, building new code, or releasing/publishing/deploying.
argument-hint: "[task description]"
---
# SDLC Skill - Full Development Workflow

## Skill source & precedence

Loaded from repo-local **`.claude/skills/sdlc/SKILL.md`**, which wins over global `~/.claude/skills/` — the project's authoritative contract. Global is for cross-repo tooling only. Unsure which is active? `head -5` both.

## Task
$ARGUMENTS

Operational checklist — **complete on its own**. Full protocol (optional depth, Claude Code installs only): `CLAUDE_CODE_SDLC_WIZARD.md`; if absent, do not hunt for it.

**If the user requests /sdlc, ALWAYS run the full workflow — even for mechanical tasks.** Never silently skip; if overkill, say so and ask.

## Full SDLC Checklist

Your FIRST action must be a task list covering every phase below — `TodoWrite`, or `TaskCreate` where that is what your harness exposes. Compact form (omit `activeForm` to use the subject as the spinner label):

```
TodoWrite([
  // PLANNING
  { content: "Find and read relevant documentation", status: "in_progress" },
  { content: "Assess doc health - flag issues (ask before cleaning)", status: "pending" },
  { content: "DRY scan: What patterns exist to reuse? New pattern = get approval", status: "pending" },
  { content: "Prove It Gate: adding new component? Research alternatives, prove quality with tests", status: "pending" },
  { content: "Blast radius: What depends on code I'm changing?", status: "pending" },
  { content: "Design system check (if UI change)", status: "pending" },
  { content: "Scope card BEFORE work: one issue, acceptance criteria, allowed paths, exclusions, risk tier, estimated diff", status: "pending" },
  { content: "Scrutinize test design - right things tested? Follow TESTING.md?", status: "pending" },
  { content: "Present approach + STATE CONFIDENCE LEVEL", status: "pending" },
  { content: "Signal ready - user exits plan mode", status: "pending" },
  // TRANSITION
  { content: "Doc sync: update or create feature doc — MUST be current before commit", status: "pending" },
  // IMPLEMENTATION
  { content: "TDD RED: failing test FIRST where a RED mutation is writable — watch EACH assertion fail; otherwise three-way call (see TDD proves)", status: "pending" },
  { content: "TDD GREEN: Implement, verify test passes", status: "pending" },
  { content: "Adding a guard? Name the requested behavior or field it binds to — if none, DO NOT ADD IT, file it (#617)", status: "pending" },
  { content: "Run lint/typecheck", status: "pending" },
  { content: "Run ALL tests", status: "pending" },
  { content: "Production build check", status: "pending" },
  // REVIEW
  { content: "DRY check: Is logic duplicated elsewhere?", status: "pending" },
  { content: "Visual consistency check (if UI change)", status: "pending" },
  { content: "Security review (if warranted)", status: "pending" },
  { content: "Cross-model review (high-stakes)", status: "pending" },
  { content: "Scope guard: only changes related to task? No legacy/fallback code left?", status: "pending" },
  // CI SHEPHERD
  { content: "Commit and push to remote", status: "pending" },
  { content: "Watch CI - fix failures, iterate until green (max 2x)", status: "pending" },
  { content: "Read CI review - implement valid suggestions, iterate until clean", status: "pending" },
  { content: "Meta-repo only: run local shepherd if PR needs E2E score (optional)", status: "pending" },
  { content: "Post-deploy verification (if deploy task)", status: "pending" },
  // FINAL
  { content: "Present summary: changes, tests, CI status", status: "pending" },
  { content: "Capture learnings (TESTING.md, CLAUDE.md, or feature docs)", status: "pending" },
  { content: "Close out plan files: mark complete or delete", status: "pending" }
])
```

## SDLC Quality Checklist (Scoring Rubric)

| Criterion | Points | Critical? | What Counts |
|-----------|--------|-----------|-------------|
| task_tracking | 1 | | Use TodoWrite or TaskCreate |
| confidence | 1 | | State HIGH/MEDIUM/LOW |
| tdd_red | 2 | **YES** | Write/edit test files BEFORE implementation files, where a RED mutation is writable (see TDD proves) |
| plan_mode_outline | 1 | | Outline steps before coding |
| plan_mode_tool | 1 | | Use TodoWrite/TaskCreate/EnterPlanMode |
| tdd_green_ran | 1 | | Run tests, show runner output |
| tdd_green_pass | 1 | | All tests pass in final run |
| self_review | 1 | | Read back files/diffs you modified |
| clean_code | 1 | | One coherent approach, no dead code |

**Total: 10 points** (11 for UI tasks, +1 for design_system check). Critical miss on `tdd_red` = process failure regardless of total score — when a RED mutation was writable. Out-of-scope under the three-way call is not a miss.

## Test Failure Recovery

**ALL TESTS MUST PASS. NO EXCEPTIONS.** Test code is app code. Failures are bugs — investigate them like a 15-year SDET, not by brushing aside.

Not acceptable: "those were already failing", "not related to my changes", "it's flaky" (flaky = bug we haven't found yet).

When tests fail:
1. Identify which test(s) failed
2. Diagnose WHY: your code broke it (regression — fix code), test is for deleted code (delete test), test has wrong assertions (fix test), "flaky" (investigate — race, shared state, env)
3. Fix appropriately, run specific test individually first, then run ALL tests
4. Still failing after 2 attempts? Escalate (see Confidence Check) — not straight to the user

## Confidence Check (REQUIRED)

State your confidence before presenting an approach:

| Level | Meaning | Action | Effort |
|-------|---------|--------|--------|
| HIGH (90%+) | Know exactly what to do | Present, proceed after approval | Model default |
| MEDIUM (60-89%) | Solid approach, some uncertainty | Present, highlight uncertainties | Model default |
| LOW (<60%) | Not sure | Escalate, don't ask ↓ | **escalate now** (per model, see above) |
| FAILED 2x | Something's wrong | Escalate, don't ask ↓ | **escalate now** |
| CONFUSED | Can't diagnose | Escalate, don't ask ↓ | **escalate now** |

**Effort bumping is NOT optional** — bump BEFORE the next attempt.

**Confidence ramp:** Opus research → Fable batch review → 95% list → /goal TDD → Codex.

**Uncertainty ≠ a human question.** Use the model/tool evidence available before interrupting a human — escalate to Fable (`advisor()`; if down, a Fable subagent at `high`), then Codex `high`; reserve the user for priority/risk/scope/spend or irreversible calls. **Confidence is not authorization**: a high score never overrides approval, external-effect, production, release/merge or policy gates; merge protections are non-overridable. **Standing instructions stay in force** (wizard doc).

## Plan Mode

Use plan mode for: multi-file changes, new features, LOW confidence, bug investigation. **Skip plan approval step** (auto-approval) when confidence HIGH (95%+) AND single-file/trivial AND no new patterns AND no architectural decisions — still announce approach, don't wait. When in doubt, wait.

## Long-Running Goals (`/goal`)

Native `/goal <condition>` (**v2.1.143+**). Haiku evaluator re-checks transcript per turn. **NEVER invoke below HIGH 95%** — below that it rubber-stamps flailing as progress. **Condition MUST name the DLC** (`/sdlc` etc.) so the evaluator anchors on "doing it right." **Pre-flight:** trusted workspace; `disableAllHooks`/`allowManagedHooksOnly` off. **Condition = contract:** end state + check + constraints + hard bound; e.g. `/goal "tests pass + clean tree following /sdlc, stop after 20 turns"`. Evaluator can't call tools; `--resume` resets counters.

## Recommended Model

**Recommended: Opus 4.6[1m] `max`** (Reliable default). **Opus 5 `high`** for bleeding-edge work, `medium` for routine web/CRUD; `xhigh` escalation only. **Sonnet 5 `medium`** for simple work. Pin `claude-opus-4-8` for a same-family escape. **Effort is model-aware, not blanket `max`** — set via `/effort` per session, never a shell-rc env var (overrides post-switch). `/model` persists; picker `s` does not.

**Autocompact: set neither override by default.** For a deliberately earlier boundary use `CLAUDE_CODE_AUTO_COMPACT_WINDOW` alone — a smaller window compacts sooner, and nothing in that range switches compaction off. On **current Opus** a percentage alone is inert unless the window is also set, and then the two multiply; on Sonnet 5 and on a 200K Opus 4.6 pin it is live, so size it against THAT window (#520). **Advisor (v2.1.170+):** `advisorModel: "fable"` works with all drivers above; set in `/claude-setup-wizard` Step 9.5.

## The Review Contract (give BOTH reviewers this, verbatim)

**Grade severity by impact if it shipped.** Not by how hard the fix is. Not by which round found it. Either one gets gamed to open or close a round.

| | |
|---|---|
| **P0** | Stop the world. Prod broken, data loss, secret leaked. Preempts the task. |
| **P1** | This PR does not merge. It doesn't work, or it broke something that did. |
| **P2** | Real, should fix, ships fine without it. |
| **P3** | Nit. |

**A finding blocks only if it is P0 or P1 and inside the scope card.** Fix a P2 or P3 here only if the diff is small and you already touched the file. Otherwise file it.

**Also answer: is this the right way to build it?** Should this code exist? Is it proportionate? Return **SOUND**, **CONCERN** (ship it, here's the debt), or **WRONG SHAPE** (stop, redesign). No severity level says "this should not exist", so nobody says it. *(#539: four rounds, seven real P1s, guard deleted at the end. WRONG SHAPE ends that at round 1.)*

**File anything outside the scope card as a GitHub issue. Never build it here.** This binds reviewers too: an out-of-card finding gets reported and filed, and does not block certification. *(#520: 20 rounds, 46 lines, nothing to compare growth against.)*

**Do not certify a doc that instructs commands unless the output is pasted.** The other leg can check this, which is the point. Reading catches judgement defects; only running catches wrong commands. *(#572: both legs certified a doc whose update command fails outright.)*

**Review against the issue's acceptance criteria, verbatim.** A stricter bar you invented in your own prompt is self-inflicted scope. *(#553: two rounds on a bar #530 never contained.)*

Ship good code, not perfect code. No glaring issues, right shape. Otherwise you never ship.

## Cross-Model Review (REQUIRED for High-Stakes)

**When to run:** high-stakes changes (auth, payments, data), releases/publishes, complex refactors. **Skip (log justification):** trivial, hotfixes, risk < review cost. **Reviewer:** `gpt-5.6-sol` `high` — adversarial diversity. **Cadence:** Fable during design, Codex once per frozen scope; don't stack both unless the decision needs two independent reviewers.

**Fable decides, Codex checks.** Fable rules on design, priority and sequencing *before* you commit to an approach — not a reviewer of work already done. A second repair to the same component in one cycle is a design question for Fable, not a third patch: review converges on a fix, never on the right design.

**No test costs more rounds than the change it guards.** When a guard accretes rounds past its own change, delete the guard and file the follow-up — the rounds are being spent on the needle, not the risk. #476 spent six on twenty doc lines: four bought real defects, two bought spellings of `sudo`, and the guard was deleted at round six anyway (#551).

PROTOCOL is universal across domains; only `review_instructions` and `verification_checklist` change.

**Handoff/preflight mechanics: wizard doc.** These two stay; improvising them cost real time (#364, #437).

1. **FALSIFY YOUR OWN WORK FIRST — the reviewer is not your test phase.** Before launching a leg, make a checklist with one row for (a) every factual, quantitative, or exact claim in the change and (b) every risk you name in the review prompt. Each row records `claim/risk | falsifier | route | evidence`. Route by the three-way call (see TDD proves): **EVAL**, **plain-assert**, or **JUDGMENT-ONLY**. For each detector add separate known-success and known-failure rows — the success it must not call failure, and the failure it must not call success. For EVAL/plain-assert rows run the falsifier and record the command and its output; where a RED mutation is writable, watch the wrong version fail first. For JUDGMENT-ONLY rows record why no executable observable exists and leave that judgement to cross-model review. Launch only when every row holds evidence or that explicit judgement-only disposition. **Why:** a risk worth naming in the prompt was worth testing before you sent it — asking the reviewer to check what you have not is using review as your test phase. PR #595 records four substantive finding rounds (5 → 4 → 1 → 0 P1s) whose findings were review-time checks of `-o` output, echoed prompt text, EOF pipes, readers versus writers, and a machine-dependent byte signature.
2. **Run reviewer through a launcher that owns the leg**, as a background task (`run_in_background: true` + `dangerouslyDisableSandbox: true`). The launcher runs `codex exec -c 'model_reasoning_effort="high"' -s danger-full-access "<prompt>" >> <output> 2>&1 < /dev/null` and exits with codex's own status. Redirect the transcript; do **not** also pass `-o <output>` — pointing both at one path makes codex truncate most of the redirected transcript and duplicate the final response. Always `high`, always background, always `< /dev/null` — and give the child that redirect inside the launcher, so it holds no matter what the caller inherited. **The prompt must demand a DIRECTION, not only a verdict:** "IF YOU DO NOT CERTIFY, name the SMALLEST change that would satisfy the certify condition." Treat that direction as a proposal under the dialogue loop — implement it, dispute it with evidence, or route it to the brain if it changes the design — not as a command, and do not patch findings individually until that choice is made. **Why:** `< /dev/null` prevents a stdin hang at 0% CPU; background avoids the Bash 10-min cap that kills foreground codex (bundles run 5–30 min). Foreground burned 70 min on a 7-min review (#364). On the direction: in PR #595 round 2 returned four P1s and prescribed deleting the waiter and sidecars; after that deletion round 3 returned one P1 whose prescribed fix was two sentences and no code.
3. **The launcher's exit status is the verdict. Do not build a second observer to reconstruct it.** 0 completed, non-zero failed — read the output for the failure and relaunch. Nothing by your deadline: inspect and relaunch, never keep waiting. **Before reusing an output path, cancel the owned background task and await its termination; if termination cannot be confirmed, relaunch to a unique per-attempt output file.** A relaunch truncates that path, and an old leg that is still alive keeps appending into it — two transcripts interleave and both legs report success (measured against codex 0.147.0). A leg started outside a launcher has no owner and no status, so its fate is unknown *immediately* — relaunch it through one rather than waiting on it. **Why:** by wall clock a hang is identical to a slow review, so it gets waited on — 51 and 28 minutes on 2026-08-13, the loop's "still working or done?" decision made twice against a process that never started (#590, #341). Two attempts to detect that from outside were falsified by running code: the output file cannot tell you (`-o` carries no completion marker; `tokens used` appears in the echoed prompt of a leg that *crashed*; an fd reported as a pipe may be at EOF and healthy; the hang's byte signature differs per machine — 39 on one, 143 on another), and pid/status sidecars cannot either (the child exits before a status is published, so a *successful* leg reads as dead; killing only the launcher leaves a status that never arrives; a stale status or a reused pid is indistinguishable from a live one). Never treat a quiet leg as progress — a gate that can hang invisibly is a gate that gets assumed passed.
4. **Dialogue loop:** per-finding response (`{"finding":"1","action":"FIXED|DISPUTED|ACCEPTED","summary":"..."}` in `.reviews/response.json`). Bump round, set `PENDING_RECHECK`, add `fixes_applied` (numbered, file:line), and write `"branch": "<git symbolic-ref --short HEAD>"` — the gate (#533) only lets an in-flight round commit on the branch it declares, so an undeclared round cannot save its work and lands the reviewer back on a mutable tree. **Every verdict — full review AND targeted recheck — must return `SHAPE` and a `TARGET` on every finding (#617).** `SHAPE: SOUND | CONCERN | WRONG_SHAPE` answers "should this code exist, in this form", independently of whether it is correct; no severity level says "this should not exist", so nobody says it. The version at *Also answer: is this the right way to build it* lives only in the INITIAL review — rounds 6-8 of PR #646 all happened inside this recheck loop, which says "don't hunt new surfaces" and never re-asks it.

**`TARGET` IS ASSIGNED BY LINE PROVENANCE, NOT BY WHICH RULE THE FINDING VIOLATES.** A finding is `VOLUNTEERED` when the defective line traces to no requested behavior of the issues under review — it would not exist if those issues, and nothing else, had been implemented — **even when the defect it causes violates an in-card invariant. A false refusal from a volunteered guard is a VOLUNTEERED finding, not an in-card one.** The anchor is **the issues under review, never the scope card**: cards written as artifact-wide invariants ("a guard is asserted but not proven", "a round >= 2 path gains a new requirement") reclassify every added line as `IN-CARD`, and the mechanism dies on arrival. **`VOLUNTEERED` admits exactly two dispositions — DELETE (verified) or FILE. Never REPAIR.** It cannot block certification and cannot authorize a repair pass.

**ROUTE THE VERDICT BY ITS SHAPE. A VERDICT IS NOT A WORK ORDER.** Requiring `SHAPE` only makes the reviewer answer; what the driver does next is where it pays, and the driver's default — patch every finding — is wrong for one of these rows.

| reviewer returns | driver does |
|---|---|
| `WRONG_SHAPE` | **Escalate to the design authority. Do not patch.** A patch answers a question nobody asked: the reviewer said the mechanism should not exist in this form, not that it has a bug. |
| `SOUND` + in-card P0/P1 | **Repair directly.** Mechanism right, one thing wrong — that is what the loop is for. |
| `CONCERN`, nothing blocking open | Ship, and file the debt in the reviewer's own words. Paraphrase and it becomes unactionable. **SHAPE is independent of correctness** — `CONCERN` arriving with an in-card P0/P1 repairs first under row 2, and the concern still files. |
| second repair to one component this cycle | **Stop and ask the design question**, whatever the SHAPE says. See *Offer "delete the guard"* below. |

*(#651 ran three of these four rows in one PR — it returned `WRONG_SHAPE` once and `SOUND` thereafter, never `CONCERN`, so row 3 rests on the definition at* Also answer: is this the right way to build it *and on no case of its own. Round 1 `WRONG_SHAPE` against `Bash(gh pr comment:*)`: allow rules are prefix shapes and the dangerous flags TRAIL, so it also authorized `--delete-last` — erasing the very clearance comments the merge gate reads. No narrower pattern exists, so escalation produced a fixed-argv wrapper; every patch would have been another pattern. Round 2 `SOUND` + P0: the wrapper inherited `GH_REPO`, mechanism right, one variable wrong — repaired. Round 3 would have been the second repair to that same file, so the design question got asked instead, and the answer was DECLARE the target with a pinned constant rather than SANITIZE the environment — a blacklist of ambient state fails open on the next variable the tool adds.)*

**The routing survives being wrong about the row.** Escalating a `SOUND` finding costs one round-trip. Patching a `WRONG_SHAPE` one costs every round it takes to discover no patch exists.

Contract: `skills/sdlc/review-verdict.schema.json`, fed to `codex exec --output-schema`. **Mechanical enforcement is repo-local** (`scripts/run-review-leg.sh` validates presence and enum membership and exits 65 on an incomplete leg) **and does not ship — GH #594 carries it.** Consumers inherit the contract, not yet the enforcer; that asymmetry is disclosed, not accidental. A validator may check presence, enum membership, and the cross-field rules the schema names — **never whether a tag is correct**, which is a reviewer's job and rebuilding it is how #598 reached 22 rounds. Recheck prompt: "TARGETED RECHECK. FIXED → verify certify condition. DISPUTED → ACCEPT if sound, REJECT with reasoning. ACCEPTED → verify applied. Report every defect at any severity; don't hunt new surfaces. A finding blocks only if it is P0/P1 AND against a REQUESTED behavior — and a finding showing a requested behavior is wrong IS P1, whatever label it arrived with." **NEVER unilaterally dismiss** — run the recheck; the reviewer may accept your dispute or counter with evidence you missed. **On CERTIFIED write `"commit_sha": "<git rev-parse HEAD>"` into `handoff.json`** — the gate hook (#437) treats a missing/mismatched SHA as stale, not just the status string. **A SHA alone is not enough: bind the clearance to CONTENT (#540).** The committed SHA is not guaranteed to be the SHA that was reviewed — the review runs, then the commit is made, so a certification naming only a SHA can certify a tree nobody looked at. **Also write `"candidate_tree": "<git write-tree>"`** and treat the clearance as stale the moment the index tree differs, even when the SHA still matches. A clearance that survives a content change is not a clearance. This field is **required, not advisory**: the shipped `hooks/codex-gate-check.sh` refuses a commit when a CERTIFIED handoff declares no `candidate_tree`, and again when the staged content is not what was certified. The hook runs *before* the shell, so an inline edit in the same command cannot satisfy it — write the handoff in its own step, then commit.

**Convergence — ONE REVIEW AND ONE VERIFY PER FROZEN SCOPE, COUNTED CUMULATIVELY PER ROOT TASK.** One review, one verify (verify reads only the diff since last verdict). **After those passes, continue ONLY when the immediately preceding COMPLETED pass recorded either (a) an open **IN-CARD** P0/P1 showing a requested behavior is currently wrong, or (b) the FIRST verification-evidence invalidation in this root task.** **A VOLUNTEERED finding authorizes nothing — it is not counted by (a), whatever its severity.** *(#617: rounds 6-8 of PR #646 each had genuine open P0/P1s, so this rule continued correctly by its own terms, against a guard that traced to neither issue under review. Without the IN-CARD qualifier a driver who adds code mid-review manufactures new in-scope P0/P1s and thereby manufactures unlimited authorised rounds, entirely within the letter of this rule.)* An evidence-only finding authorizes exactly one additional pass per root task; a later evidence-only finding is FILED. Otherwise STOP. Below-bar and out-of-scope findings are filed and authorize nothing. A fix to the deliverable creates a new SHA and must be verified; **a pass that found such a defect is not clean, whoever introduced it — including the loop itself.** The "first invalidation only" bound is load-bearing in both directions: without the exception, #598 stops at round 16 on a harness-only finding and round 17 never finds the real `./\git commit` fail-open; without the bound, round 21's seventh false-green route authorizes yet another pass and the rule never fires. Do not prompt a reviewer to "find the next route" or "defeat the new guard": asking for a fresh category biases review toward producing one, which holds the finding count above zero long after the deliverable has converged. A fix adding code or promises beyond the reviewed diff is NEW SCOPE — log continue/stop + cost in `handoff.json` `scope_decisions` BEFORE the pass; single driver records its own, next pass ratifies; human only on a cross-model split. **The count is cumulative and never resets when scope is re-frozen** — record `root_task` (the verbatim request) and `base_sha` once, then let `round` accumulate across every re-freeze; new scopes **append** to `scope_decisions`, never replace it. Re-freezing after each fix is how two-per-scope becomes unlimited (#520: 20 rounds). **Blame the line:** a blocker in code nobody asked for — cut it, don't repair it. **This is now a reviewer output, not a driver resolution** — see the TARGET contract below; the driver is the party with momentum and is the last one able to notice. Review committed SHAs, not a mutable tree. #520: 20 rounds, 46 lines. *(#588/PR #598 reached 22 review attempts under the old wording, which called itself accounting and left termination to the driver. Round 20 found the last shipped fail-open, `su\do`, introduced by round 19's own keyword-shield fix. Round 21 found no new plausibly-typed fail-open across 183 fresh probes and withheld certification for a seventh false-green harness route — the SECOND evidence-only finding in that root task, so under this rule it is filed and round 22 is forbidden. Round 22 produced no verdict.)*
**Loop autonomy — no per-round check-ins.** While a pass is owed, don't hand the turn back: fix, push, launch it in the SAME turn. Ending a turn with no pending work IS a stop decision; cite **CONVERGED** (verdicts in on head SHA, zero unresolved in-allowlist), **DEADLOCK** (finding unmoved after 2 rechecks, or non-waivable gate after 2 attempts), **BOUND** (context ceiling, or gate needing a human), or **SCOPE** (the stop condition fired: the last completed pass recorded no open in-scope P0/P1, and no first-invalidation exception remains — a recorded decision is required to continue anyway). Every pass carries a delta; resubmitting unchanged = reviewer-shopping.

**Multi-reviewer: let the reviewers reconcile with each other. You relay. You never merge their words.**

1. **Review blind.** No shared draft, no summary of the other. A reviewer who saw the first one confirms it instead of looking elsewhere, and you paid for two reviews to get one.
2. **Cross-feed verbatim.** Pass each the other's position as written. Paraphrase restates a position into something its author would not sign.
3. **Let them argue.** Concede what's right. Hold what's wrong with a file, a line, or command output — never an opinion.
4. **They hand back one position. You report it.** The user sees a settled answer, not two transcripts to referee.

You are the lowest-ranked reviewer of your own work: most context, least independence, and you wrote it. Merging their words is grading yourself through a paraphrase you control.

**On deadlock, route by where the position started.** A split that started as a design question belongs to the planner. One that started in a verdict, defect list, or recheck belongs to the reviewer, and the lower verdict applies. A split spanning both goes with the verdict. Only what survives that goes to the user, as one question. *(#561: the attacker opened with four P1s, the planner conceded all four and then found three surfaces the attacker missed. Neither produced that list alone.)*

**Non-code domains:** add `"audience"`/`"stakes"` keys.

**Full protocol** (rationale, full JSON example, anti-patterns like "find at least N", convergence diagrams): `CLAUDE_CODE_SDLC_WIZARD.md` → "Cross-Model Review Loop".

## Documentation Sync (REQUIRED — During Planning)

**Docs MUST be current before commit.** Stale docs = wrong implementations = wasted sessions.

Standard pattern: `*_DOCS.md` — living documents that grow with the feature (`AUTH_DOCS.md`, `PAYMENTS_DOCS.md`).

1. Read feature docs for the area being changed during planning
2. Code change contradicts or extends what the doc describes → MUST update the feature doc
3. No `*_DOCS.md` exists and feature touches 3+ files → create one
4. Project has `ROADMAP.md` → mark items done, add new items (ROADMAP feeds CHANGELOG)
5. **Change alters behaviour README describes → update README.** It ships and is the most-read doc; a deleted behaviour still advertised there is a lie to every consumer

`/claude-md-improver` audits CLAUDE.md structure periodically. Does NOT cover feature docs.

## CI Feedback Loop — Local Shepherd

**NEVER AUTO-MERGE. Do NOT run `gh pr merge --auto`.** Auto-merge fires before review feedback can be read. The shepherd loop IS the process.

Mandatory steps:
1. Push to remote
2. `gh pr checks --watch`
3. **Read CI logs even on pass** (`gh run view <RUN_ID> --log`) — green can hide warnings
4. **Cross-model audit the CI logs** — release/workflow/control-plane PRs only: silent failures, skipped tests, degraded metrics
5. CI fails → fix, push (max 2 attempts)
6. CI passes → `gh api .../pulls/PR/comments` for review feedback
7. Implement valid suggestions (bugs, perf, dedup). Skip opinions. **Termination is the cumulative rule above (#539), not a fixed count** — continue only while the last completed pass recorded an open in-card P0/P1 or the first evidence invalidation, counted per root task and never reset by re-freezing scope
8. **Clearance, once CI green.** Ask reviewers *"safe to merge?"* — NOT "can you break this" (unsatisfiable; #478). Each posts `**CROSS-MODEL-CLEARANCE**` + one fenced json `{"reviewer","verdict":"YES","confidence","sha"}`. **The verdict decides. Ignore the confidence number.** It does not separate certified-correct from certified-wrong, so never route a decision through it and don't spend output defending it. The field stays only because the merge gate still requires it (#574). *(#572: one leg certified at 100%, the other then found a P1 it had passed three times; the second certified at 96%, the first then found a P1 that only appeared by running the command. What discriminated was executing it.)*
9. Explicit `gh pr merge --squash` (repo wrapper if any) — never auto-merge. Needs 2 YES ≥95 on head SHA (the ≥95 is the gate's mechanical requirement until PR-B, not a review signal — see #574 above) AND: CI `validate` green, Codex `high` CERTIFIED via full dialogue; **fresh Fable subagent** (diff only) with **zero unresolved findings** in-allowlist after **≥1 dialogue round**. Merge-evidence paths (workflows, `hooks/`, `.claude/`, merge script) need a human — **unless** your repo has a merge gate mechanically checking CI, test deletions, clearance, and you run the *merged* copy, not this branch's edited one. No gate: human. Version bumps, reviewer deadlocks: always human. Tell the user after — never silent.

**Evidence:** PR #145 auto-merged, shipped a P1 bug. v1.92.0: two YES (97/93) dead-ended (#478).

## Scope, DRY, Patterns, Legacy

- **Scope guard** — only task-related changes. Notice something else → NOTE in summary, don't fix unless asked.
- **CLOSED ALLOWLIST** — the issue's requested behaviors are the whole job. No runtime behavior, enforcement, automation, computed output or new mechanisms unasked. Findings correct allowed work, never expand it. No issue? The restated task IS the allowlist. #520 asked for a doc line, got 2 parsers.
- **SCOPE CARD** — the artifact that makes the allowlist checkable, written BEFORE work starts (on the issue, or as the restated task): one issue, acceptance criteria, allowed paths, exclusions, risk tier, estimated diff. Nothing to compare growth against is why nothing fired during #520. It also **breaks the tie on a stale issue**: when the card's premise turns out false, say so on the issue and rescope in the open — never silently widen or narrow. The breaker trips on **a new subsystem, path or criterion; a diff past 2x the estimate; or two corrective rounds** — trip it and you stop and record, you do not keep going.
- **CLAIM RULE** — before printing a value computed from parsed input, state the domain it is promised correct over; out-of-domain → NO claim. Can't enumerate or fuzz it? Print the inputs, not the number. **Scope is measured in promises, not lines.**
- **EXISTENCE RULE** — a guard/fix does not exist until observed producing BOTH outcomes on live input. Every guard ships a negative fixture: RED proves it fires, never that it does not overfire.
- **PROCESS BUDGET prices the promise** — none, or watched it hold → ship; predicted → one fact-check pass; unobservable or High-Stakes → full gate.
- **DRY** — before coding: "what patterns exist to reuse?" After: "did I duplicate anything?"
- **New patterns** require human approval: search first, propose if no equivalent, get explicit approval.
- **DELETE legacy code** — backwards-compat shims, "just in case" fallbacks → gone. If it breaks, fix properly.

## Debugging Workflow (Systematic)

Reproduce → Isolate → Root Cause → Fix → Regression Test. No skipping. `git bisect` for regressions. 2 failed attempts → escalate (Confidence Check), not straight to the user.

## Fixed Means Observed

Before reporting a fix, name the observable that would differ if it were NOT fixed — then go look at it. Settings file edited → read the live process env, not the file. Hook changed → fire it. Threshold changed → measure it against the real files. If the only evidence is "I made the edit", the state is *submitted*, not fixed.

**Out-of-repo changes get no gate** (global `settings.json`, env vars, shell rc, scheduler entries): no diff, no PR, no reviewer ever sees them. Before editing, check `.reviews/` artifacts and memory for prior findings on the subject; state the verification command in the same message as the change; if a live process won't pick up the edit (env vars need a restart), say so instead of "fixed". **Evidence:** 2026-08-08 (#525) — a settings fix was reported fixed while the bug was still live; the answer was already in `.reviews/` from PR #468.

**An instruction is not a claim.** Never tell a reader to run a command you have not run. Labeling saves a claim, because the reader evaluates it. It cannot save an instruction, because the reader executes it. Delete it instead.

Run the exact string you ship, and fill in every placeholder at least once. **Check that the output shows the promised behavior, not just exit 0** — `✔ already at the latest version` proves the name resolves, not that the command updates. If you can't observe the behavior, narrow the instruction to what you did see. A command you genuinely cannot run may be described, never instructed. *(#572: 24 doc lines, five P1s, every one a claim wider than its evidence — including an update command that fails outright. That doc labeled its evidence honestly and still shipped broken.)*

## Release Planning (Task Ships a Release)

All ROADMAP items planned at 95%, dependencies identified, presented together (catches conflicts), pre-release CI audit across merged PRs — a green checkmark is insufficient. User approves, then implement in priority order.

## Deployment Tasks

Read `ARCHITECTURE.md` Environments table + Deployment Checklist. **Production requires HIGH (90%+); ANY doubt → ASK USER.** **Post-deploy verification:** health check, log scan, smoke tests, monitor 15 min (prod only). Issues → rollback first, then a new SDLC loop.

## Test Review (Harder Than Implementation)

Critique tests harder than app code: testing the right things? Proving correctness, or just pinning current behaviour? Follow TESTING.md.

**Testing Diamond:** E2E ~5% → Integration ~90% (best value — real DB/cache/services via API, no UI) → Unit ~5% (pure logic only). No UI/browser = integration, not E2E.

**Mocking:**

| What | Mock? | Why |
|------|-------|-----|
| Database | NEVER | Test DB or in-memory |
| Cache | NEVER | Isolated test instance |
| External APIs | YES | Real calls = flaky + expensive |
| Time/Date | YES | Determinism |

Mocks MUST come from real captured data — never guess shapes. Unit tests qualify ONLY for pure I→O (no DB, API, FS, cache).

**TDD proves:** RED (fails — bug or missing feature), GREEN (passes — fix works), Forever (regression protection). **TDD RED applies only where a RED mutation is writable** — write the wrong version the test must catch BEFORE writing the test. If catching the wrong version requires understanding meaning (a reversal, a negation, a contradicting sentence nearby), no assertion can do it: DO NOT write the test. That exception is for prose judged by a reader — for executable behavior, any observable input/output or side-effect difference means a RED mutation IS writable. Three-way call for every change: **EVAL it** (agent-facing guidance a real scenario can observe), **plain-assert it** (mechanical contract only — byte parity, a JSON key, a version, a heading; proves structure, never meaning), or **DON'T TEST IT** — two cases. (a) Prose whose correctness is a judgement call; cross-model review is the guard. (b) **HARNESS CONFIGURATION that declares no behavior of ours** — an output style, an editor or tool setting, a model/effort pin. A test here could only restate the file: the file is its own sole oracle, which is a tautology, and it pins a third party's config format so their next release reddens your suite. **The exemption ends the moment a second source of truth exists to reconcile against** — hook registrations vs the hooks on disk, `package.json` `files` vs what must ship (#594), CI step lists vs the suites in `tests/` — that reconciliation test stays. Verify sole-oracle config by USING it once and observing the effect — record the command and the observed effect — then move on. If a config value feeds OUR code, that code is what gets the test, not the value. *(Maintainer ruling 2026-08-15: tests for harness config are a waste of time. The first draft of this exemption said 'a value the harness reads and acts on itself', which describes `permissions.deny`, `hooks.json`, `files` and `ci.yml` equally well and would have exempted the reconciliation suite that caught a real gap in #617 an hour earlier. Sole oracle is the axis; who reads the file is not.)* **Implement-first** is allowed ONLY when a named gate blocked the required RED/evidence act itself — a gate refusing implementation because RED is missing is the gate working, not an entry ticket. Quote the refusal verbatim in the issue/PR, get a cross-model ruling that APPROVES that same act and scope BEFORE the edit, and name — before editing — the observable that would differ if the change were wrong, then go look at it after (#525). No quoted refusal or no approving ruling — no entry.

**List every observation the check promises, then break each one separately.** Mutate a copy of the live deliverable, not the base. The run fails unless every expected failure reports. Can't list them? Don't write the guard.

**Make the nearest wrong version fail, not just a deletion.** Deletion is the easiest mutation to survive, because a branch that pre-existing text already satisfies never notices it. *(Five dead checks in one session. #550's runner ran 30 of 65 suites and reported green.)*

**Grep prose for exact strings or structure only. Never for meaning, denial, or polarity.** Review the prose instead, or delete the marker (#493 req 6).

**The first time a reversed live instruction stays green, delete the guard. Do not patch it.** *(#539: three patches to one unfixable mechanism turned round 2 into round 4. Strikethrough won — `~~the count never resets~~` keeps the string byte-identical while teaching the opposite, suite green at 137/137.)*

**Offer "delete the guard" as an outcome in any guard recheck.** Reviewers only pick outcomes the prompt offers. Rounds 1–3 kept it off the menu; round 4 put it on and it was taken immediately. If you are repairing a guard for the second time this cycle, ask whether it should exist.

**Accepted residual:** no string check can catch a doc that lists the required fields and then contradicts them in prose. Cross-model review is the only guard for that.

## Prove It Gate (New Additions Only)

New skill/hook/workflow/PRACTICE? Default answer is NO. Prove it: (1) **Absorption check** — can this be a section in an existing skill? (2) Research equivalents (native CC, third-party, existing skill). (3) If one exists — why is yours better, with evidence. (4) If not — real gap or theoretical? (5) **Quality tests** must prove OUTPUT QUALITY (existence tests prove nothing) — scoped by the three-way call: prose whose correctness is a judgement call gets cross-model review, not a grep. (6) Less is more — every addition is burden.

If you can't name the evidence that would prove it works — a test or a cross-model review — you can't prove it works.

## After Session (Capture Learnings)

| Insight | Destination |
|---------|-------------|
| Testing patterns/gotchas | `TESTING.md` |
| Feature-specific quirks | `*_DOCS.md` (e.g., `AUTH_DOCS.md`) |
| Architecture decisions | `docs/decisions/` (ADR) or `ARCHITECTURE.md` |
| General project context | `CLAUDE.md` (or `/revise-claude-md`) |
| Plan files (work done) | Delete or mark complete (stale plans mislead) |

### Memory Audit Protocol

End of release: audit `~/.claude/projects/<proj>/memory/`, promote portable lessons to shared docs. **A process rule saved only to memory is a /sdlc gap** — memory changes one agent, docs change everyone. Denylist, destinations and the MANDATORY human gate: `CLAUDE_CODE_SDLC_WIZARD.md`.

## Post-Mortem: Process Failures Become Rules

```
Incident → Root Cause → New Rule → Evidence per the Three-Way Call → Ship
```

Don't fix only the symptom. Guard the rule per the three-way call (see TDD proves) — EVAL it, plain-assert it, or cross-model review for meaning-level prose. Sometimes the fix is DELETING a gate (#484, #561). Example: PR #145 auto-merged before CI review → "NEVER AUTO-MERGE" block + `test_never_auto_merge_gate`.

## Context Management & Subagents

- `/compact` between planning and implementation; `/clear` between unrelated tasks, after a PR, or after 2+ failed corrections
- **Work under ~350K tokens** (~35% of a 1M window). Compact well before autocompact (~95%). `/usage` = spend.
- **Run the test — a completion claim is not a test result.** At any context size, not past a threshold
- `--bare` (v2.1.81+) skips ALL hooks/skills/LSP/plugins. Headless only.
- Custom subagents (`.claude/agents/`) run autonomously. Skills guide; agents do. Use for parallel work or fresh context. **Two at once → reconcile them.**

## Design System Check (UI Changes Only)

Read `DESIGN_SYSTEM.md` if present: colors/fonts/spacing match tokens; flag new patterns. Skip backend/config code.

---
**Full reference:** `CLAUDE_CODE_SDLC_WIZARD.md` (protocol depth, deployment, memory). `TESTING.md` (diamond + mocking). `ARCHITECTURE.md` (environments, post-deploy).
