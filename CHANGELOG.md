# Changelog

All notable changes to the SDLC Wizard.

> **Note:** This changelog is for humans to read. Don't manually apply these changes - just run the wizard ("Check for SDLC wizard updates") and it handles everything automatically.

## [1.100.0] - 2026-09-12

### Changed
- **Reliable is now the recommended default.** Opus 4.6[1m] max + GPT-5.5 xhigh + Fable 5.1 high. Opus 5 moves to Bleeding edge (`@frontier` dist-tag).
- Two-lane install: `npm install agentic-sdlc-wizard` (Reliable, `@latest`). Bleeding edge (`@frontier`) not yet published.
- Simplified Setup A table to the three-tier ladder: Opus 5 high → GPT-5.6 Sol high → Fable 5.1 high.
- Both GPT-5.5 xhigh and Fable 5.1 high independently concurred on this strategy: revert default-flip commits on main, don't cherry-pick 143 commits from v1.87.0.

### Added
- Escalation ladder pin tests and canary scenario (#707, merged in v1.99.3 squash).

> **Registry note, 2026-08-26 — `opus-4.6` dist-tag (not a release).** The npm
> tag `opus-4.6` now points at **v1.87.0**, the last release published before
> Opus 5 entered this repo (Opus 5 became the Setup A default in v1.88.0).
> As of this note, `npm install agentic-sdlc-wizard@opus-4.6` resolves to that
> release; v1.87.0's published contents are immutable, while the tag itself is
> a mutable pointer — pin `@1.87.0` to guarantee the version.
> Its known-goodness is **recollection, not a recorded test** — the
> lifecycle canary that would upgrade that claim is tracked in
> [#689](https://github.com/BaseInfinity/claude-sdlc-harness/issues/689). No
> package contents changed; this entry documents registry state only.
> Observed at tagging time: `npm view agentic-sdlc-wizard dist-tags` →
> `{ latest: '1.99.2', 'opus-4.6': '1.87.0' }`.

## [1.99.2] - 2026-08-17

### Evidence now binds to what was reviewed, and the docs stopped claiming what nobody measured

> **There is no 1.99.0 or 1.99.1 release, and there never will be.** Both were
> planned milestone labels, and they failed in different ways, so they were resolved
> differently. `v1.99.1 — review-leg supervision` had shipped nothing, so it was simply
> renumbered to **v1.99.3** with its contents and order untouched. `v1.99.0 — PR-B:
> the gate` never described a release at all: three of its issues (#533, #581, #588)
> shipped inside v1.98.0 and three more (#540, #563, #636) ship here, so no version
> label on it can be true. It has been **retired rather than renumbered**, keeping
> #547, its one unshipped issue. No issue changed milestone.
>
> Version numbers here follow what shipped, not what was planned.

> **What of this reaches your install.** Per `npm pack --dry-run` — the shipped
> artifact, not the `files` field, which omits two paths npm adds on its own — the
> package contains `cli/`, `skills/`, `hooks/`, `.claude-plugin/`,
> `CLAUDE_CODE_SDLC_WIZARD.md`, `AI_SETUP_LANES.md`, `CHANGELOG.md`, plus `README.md`
> and `package.json`.
>
> Every other path named below is **repo-local and arrives in no install**: `scripts/`,
> `tests/`, `AGENTS.md`, `CODE_REVIEW_EXCEPTIONS.md`, `ROADMAP.md`, `SDLC.md`, and the
> generated `.reviews/` artifacts. They are described here because this documents the
> release, not only the shipped subset. Where a fix lands solely in a repo-local path
> it is called out at its entry. The asymmetry is **#594** and it is open.

Two gate holes in v1.98.0 let a merge cite a review of something other than what was
merged. Both are closed. Separately, an audit of the shipped documentation found
several claims that were asserted from a single uncontrolled observation, or that had
gone stale — including one whose "revisit if" trigger had already fired the day after
it was written.

### Added

- **A reviewer must now state the SHAPE and TARGET of its verdict** (#617), and the
  driver must route on the answer (#653). Previously the design pass was skipped
  whenever the builder judged a change small — and that judgement was the gate, with
  nothing recording that it had been made. SHAPE is now a required output, and
  `.reviews/merge-clearance-*.json` records it.

- **`scripts/post-comment.sh`** — a fixed-argv wrapper for posting PR and issue
  comments, plus allowlist entries for the read-only test suites. Permission patterns
  are prefix shapes and dangerous flags *trail*, so allowing `gh pr comment` at all
  would also authorize `--delete-last` — which erases the very clearance comments the
  merge gate reads as evidence. A wrapper can forbid a suffix; a glob cannot.

  **Repo-local, and NOT in the npm package.** `scripts/` is excluded from
  `package.json`'s `files`, so this arrives in no consumer install. It is listed here
  because this changelog documents the release, not only the shipped subset — the
  asymmetry is #594, it is open, and it is disclosed rather than implied.

### Fixed

- **A certification bound to a SHA did not bind to the merged content** (#540). The
  committed SHA is not guaranteed to be the reviewed SHA — a reviewed tree can be
  amended, rebased, or extended before it merges, and nothing checked. Certification
  now binds to **content**: a handoff must declare a
  `candidate_tree`, and the gate refuses the commit when the index tree does not match
  it. A handoff with no `candidate_tree` is refused outright rather than passed.

- **A moved merge base could merge content nobody reviewed** (#636). `base_tree` alone
  does not bind ancestry. The gate now binds with `base_sha`.

- **The merge gate blocked the one case where the review was cleanest** (#563): a
  round-1 review that found nothing was treated as insufficient evidence, while a
  round-2 review that found and fixed problems passed. Round 1 is now exempt when it
  is genuinely clean.

  **#563 and #636 both land in `scripts/merge-pr.sh`, which is repo-local and NOT in
  the npm package** (#594). Consumers do not receive this merge gate and are not
  affected by either fix. #540 above is different — its enforcement is in
  `hooks/codex-gate-check.sh`, which does ship.

- **Documentation that asserted more than the evidence supported** (#579, #544, #499).
  `AI_SETUP_LANES.md` said the advisor was disabled server-side; it works.
  `CODE_REVIEW_EXCEPTIONS.md` carried a workflow-permissions exception whose revisit
  trigger had already fired. `AGENTS.md` instructed reviewers to enforce a 20,000-byte
  ceiling on `SKILL.md` that was deleted in #489 and had never been measured — the
  file is 42,309 bytes. `README.md` gained the frontier-model banner.

- **`ROADMAP.md` could not resume a cold session** — three defects, then a fourth: the
  save point named an experiment that had been forfeited and will not be retried. The
  file now defers to a standing rule for "what is next" instead of restating a
  sequence, because a copied sequence goes stale (#580). It had, twice.

### Known limitations, stated rather than discovered later

- **This release was reviewed by one blind reviewer plus one context-rich
  corroborator, not two independent reviews.** `advisor()` forwards the driver's full
  transcript, so the second seat sees the first seat's findings. Tracked on **#657**.

- **The merge gate is identity-blind.** It verifies that two distinct reviewer
  *strings* returned a verdict bound to the head SHA. It cannot verify that the named
  reviewer ever ran. Three live instances are recorded on **#657**, the third of them
  produced by the driver in good faith while disclosing the weakness in prose the gate
  does not read.

- **Whether an exhausted quota meter blocks `advisor()` remains untested.** Exactly one
  observation survives — 2026-08-16, the advisor answering while the meters read full.
  It did not control for the weekly window rolling over. A second observation was
  recorded on 2026-08-17 and **retracted the same day**, once a usage panel showed the
  window had in fact rolled over before the call. `AI_SETUP_LANES.md` states this as
  availability-only and does not claim which pool is billed.

## [1.98.0] - 2026-08-15

### The review loop can now end, and a review leg can no longer silently fail to happen

Everything in v1.97.0 and earlier assumed a review round would terminate on judgement. Six
review rounds on one 30-line documentation change said otherwise. This release makes the
loop's exit condition explicit and makes the mechanics of launching a review leg something
the harness enforces rather than something a driver remembers.

### Added

- **A termination condition for the review loop** (#606). You are done when a fresh blind
  round returns zero unresolved findings against the *requested behaviours* — not merely
  "nothing new". After the budgeted passes, the loop continues only when the immediately
  preceding completed pass recorded an open P0/P1 showing a requested behaviour is currently
  wrong, or the first verification-evidence invalidation in this root task. A later
  evidence-only finding is filed, not spent on another pass.

- **A gate lane that refuses a hand-typed review leg** (#610), in the shipped
  `hooks/codex-gate-check.sh`. `codex exec` reads stdin to EOF and appends it to the prompt,
  so a leg handed an unclosed pipe blocks *before contacting the model* — indefinitely. Two
  legs were waited on for 51 and 28 minutes against processes that had never started.

  **The launcher this lane names is NOT in the npm package.** `scripts/` is not in
  `package.json`'s `files`, so consumers receive the refusal without the
  `scripts/run-review-leg.sh` it points them at. That is #594, it is open, and it is not
  fixed here. Verified with `npm pack --dry-run`: zero files under `scripts/`.

- **The review contract as one prose batch** (#558, #557, #573, #574, #564, #556): a severity
  scale, what actually blocks a merge, reviewers reconciling with each other verbatim rather
  than through the driver, and the post-review confidence percentages cut for carrying no
  signal.

- **Falsify-before-review is an executable step** (#596), not advice.

### Fixed — three defects in the commit gate

Two refused legitimate work; one failed open. Those are opposite failures and are not
described here as if they were the same one.

- **Refused work: the gate matched `git commit` in unquoted prose** (#588). It now fires on
  command position. A commit whose *message* mentions the phrase is still refused — that is
  #600, and it is open.
- **Refused work: the review gate made the review protocol uncommittable** (#533) — the rule
  and the mechanism enforcing it could not coexist.
- **Failed open: a JSON-escaped newline hid an invocation** (#581). A command split by an
  escaped newline walked past the gate entirely. The opposite failure to the two above, and
  the more dangerous one, because nothing surfaced it.

### Not in this release, stated because the shipped gate references it

`scripts/run-review-leg.sh` and the CI-status preflight it carries (#590, #613) are
repo-internal: they are why this project's own review legs no longer hang, and consumers do
not receive them. #594 tracks shipping the launcher.

### Changed

- The plugin update path is scoped by surface, and the command that reports success without
  moving a version is named as such (#572).


## [1.97.0] - 2026-08-10

### Removed — a hook that denied its own maintainer, twice

- **The Cowork `UserPromptSubmit` prompt classifier is deleted.** It blocked the maintainer's
  own instruction to codify a policy change, classifying a *description* of policy as an attempt
  to *evade* it. That was the second denial, not the first: on 2026-08-07 it refused "do the
  prose rename now, dont TDD something like this... just verify after" — a stated reason plus a
  stated alternative, a safeguard being **substituted**, not removed. A justified-exception
  carve-out shipped in response and a test pinned its text. The test passed. The hook denied the
  maintainer anyway.

  No prompt wording guarantees an LLM classification outcome, so it is unsatisfiable by
  narrowing, and it is unfalsifiable from inside — reporting the false positive requires a
  prompt it may block. Same class and same remedy as the `Stop` hook removed in v1.92.0.
  Blocking hooks fire on **acts** (`PreToolUse`), never on turn-level subject matter. (#561)

- **The honest cost, stated rather than hidden.** In Cowork, a prompt asking to skip planning or
  review, followed by edits to files that already exist, now hits **no gate at all** —
  `PreToolUse` fails open for edits, and the CLI's commit and merge gates cannot run there.
  That loss is preferable to a classifier that denied its maintainer twice, but it is real and
  it is written down in `cowork/README.md`, not buried. (#561)

### Changed — TDD RED is scoped to where a RED mutation is writable

- **An unqualified test-first mandate does not produce more testing. It produces fake testing.**
  This repo shipped **six guards that passed on every input, including the ones they existed to
  reject** — every one green in CI for its whole life. A seventh was found *inside this release*:
  the new guard protecting the hook deletion was itself *partially* dead — it caught a populated
  re-add and missed an empty one — found by a reviewer mutating the file rather than reading the
  assertion. When the driver must satisfy the rule
  and the only satisfying artifact for meaning-level prose is a grep that cannot fail, that is
  what gets written.

  The boundary is now mechanical: write the wrong version the test must catch **before** writing
  the test. If catching it requires understanding meaning, no assertion can. That gives a
  three-way call for every change — **EVAL it**, **plain-assert it**, or **DON'T TEST IT** and
  let cross-model review be the guard. Two loopholes were closed before shipping: the meaning
  exception applies only to prose judged by a reader (any observable input/output difference
  means RED *is* writable), and implement-first requires a gate that blocked the RED or evidence
  act itself — a gate refusing implementation because RED is missing is the gate working, not an
  entry ticket. (#561)

### Added — a guard that covers surfaces nobody knew existed

- **Hook-registration absence is now checked over the shipped file set, not a list of
  mechanisms.** Three enumerations of "where a hook can be registered" were each declared
  complete and each disproven within a review round, every miss found by reading Anthropic's
  documentation rather than ours — because each attempt quantified over *Anthropic's* set of
  registration mechanisms, which they own and extend.

  The check now quantifies over a set this repo owns: every tracked shipped file, rejecting any
  `hooks` declaration outside `cowork/hooks/hooks.json`, and **failing closed** on any format it
  has no parser for. Review then found that Anthropic also documents hooks in **agent frontmatter
  and command frontmatter** — a fifth and sixth surface no enumeration ever named — and the walk
  already covered both. It guards surfaces nobody involved knew existed. (#561)

- **"Fixed" now means observed.** Name the observable that would differ if a change were not
  fixed, then go look at it. Out-of-repo changes — global `settings.json`, env vars, shell rc,
  scheduler entries — get no gate at all: no diff, no PR, no reviewer. They need the verification
  command stated in the same message as the change. (#525)

- **The review pass budget is cumulative per root task, and planning requires a scope card**
  naming one issue, an estimated diff, and allowed paths. A budget that resets on re-freeze is
  not a budget. (#539, #538)

- **The wizard's own autocompact guidance was breaking compaction.** It recommended setting two
  knobs that multiply, so a 1M-token window compacted at a fraction of it. (#531)

- **`/sdlc` carries the standing setup itself.** Fable decides the approach, and a guard may not
  outgrow the change it guards — both were instructions the maintainer had been retyping every
  session. (#530)

- **The unmeasured 20,000-byte ceiling gate on `skills/sdlc/SKILL.md` is deleted**, not raised.
  It was never measured against anything, and every edit had begun by degrading something else to
  stay under it. (#489)

- **Install guidance recommends the native Claude Code installer** and warns off the
  `sudo npm install -g` footgun. (#476)

### Note on delivery

Merging delivered none of this. **Updating does.** The `UserPromptSubmit` classifier shipped in
every Cowork plugin version up to and including v1.96.0, so Cowork users remain on whatever
version is in their local cache **until it refreshes to v1.97.0** — the release is what moves it.
To verify the classifier is actually gone rather than assuming: `claude plugin details
sdlc-wizard-cowork` should report one hook, `PreToolUse`.

## [1.96.0] - 2026-08-09

### Fixed — the wizard doc shipped a second, diverged copy of the SDLC skill

- **A 639-line fence told you to hand-copy a skill the CLI already installs.**
  `CLAUDE_CODE_SDLC_WIZARD.md` carried a ````markdown block instructing readers to paste it
  into `.claude/skills/sdlc/SKILL.md` — the exact file `npx agentic-sdlc-wizard init` writes
  from `skills/sdlc/SKILL.md`. Two install paths, one destination, and they had diverged to
  56,284 bytes against the live skill's 19,356, moving in opposite directions inside single
  PRs. If you hand-copied that block, you installed a draft nobody maintains. The fence is
  deleted and the sections only reachable inside it are promoted to document level. (#513)

- **18 assertions were verifying the quotation instead of the document.** Across two suites,
  they grepped the wizard doc for strings that existed only inside that fence, so they passed by
  matching text no consumer ever installs. Guard and artifact pointed at different objects.
  (#513)

### Added — four guards so it cannot come back

Three of them ask whether a block reproduces the shipped skill's headings, its frontmatter at
real file size, or its body prose. The fourth ignores the content entirely and asks whether the
document tells a reader **where to install a file** — the one thing a hand-copy instruction
cannot obfuscate and still work.

The body-prose rule measures the raw document rather than fenced blocks, because a verbatim copy
indented four spaces carries no fence at all, and the same copy measured 105 or 131 reproduced
lines purely by the author's choice of three- or four-backtick wrapper.

These are lints, not a security boundary, and they say so: every artifact producible by plausible
accident fires loudly on several rules at once; multi-step deliberate evasion is review's job.
Reach limits are documented rather than papered over.

### Changed

- **Same-model self-review is no longer instructed — including in a hook that fired every turn.**
  `hooks/sdlc-prompt-check.sh` (a shipped hook) carried a per-prompt `/code-review` directive; it
  is deleted, along with the skill's checklist item and its "Self-Review Loop" section. What stays
  is the *measurement*: the `self_review` rubric row, same 1 point, minus its critical flag, so
  `tdd_red` is now the only must-pass criterion. A model reviewing its own output was never
  independent evidence — `/code-review` reported clean three times in one session while an
  independent model found real P1s each time. Cross-model review is untouched. (#509)
- **The Memory Audit Protocol now exists where it was advertised.** The skill pointed at the
  wizard doc, the wizard doc pointed back at the skill, and the protocol lived in neither. It is
  now written out in `CLAUDE_CODE_SDLC_WIZARD.md` — denylist table, promotion destinations,
  `promoted_to` tracking, the mandatory human gate — and the skill keeps a pointer that leads
  somewhere. Cross-model review mechanics moved the same direction. Net effect on the skill:
  19,993 → 19,137 bytes, so it is no longer one edit from its ceiling. (#509)
- **The review loop no longer hands the turn back every round.** The skill now states when it may
  stop, and only three answers count: **CONVERGED** (required verdicts in on the head SHA, zero
  unresolved findings), **DEADLOCK** (same finding unmoved after two rechecks), or **BOUND** (a
  gate that mechanically needs a human). While findings are landing, the loop is working — fix and
  launch the next round in the same turn. The load-bearing half is the anti-shopping invariant:
  every round must carry a delta, because "always continue" without it is just resubmitting until
  a tired YES. No fixed round cap. (#509)
- **README brought in sync with the above.** It no longer tells you to run cross-model review
  "after Claude's self-review passes" — the trigger is the change being high-stakes — and
  `/code-review` is described as optional preflight input to that review rather than a gate of its
  own. (#509)
- **Cowork's surface is now stated, not discovered.** Cowork users receive six files and never the
  wizard doc, so "full protocol: wizard doc" was a dead end for them. The skill now says it is
  complete on its own and those pointers are optional depth. `cowork/README.md` states plainly
  that Cowork is guidance, not enforcement — its prompt hooks are unproven as gates. (#509)
- **Dual cross-model certification is now merge authorization.** `scripts/merge-pr.sh` requires
  two distinct reviewers at >=95% confidence bound to the head commit, plus a CERTIFIED clearance
  artifact at round >= 2. That round count is a *structural proxy*, not proof — no local script can
  confirm a review dialogue was genuine, and the script says so rather than implying otherwise.
  Both clearances are also posted by the same token, so this is attested, not authenticated. Never
  cleared by any of it: red CI, net-removed tests, version bumps. Repo-local; it does not ship.
  (#511, #517)
- **CI `validate` lookup fixed — it could read a red or queued run as green.** The check took
  `head -1`, so a green run shadowed a red one of the same name, and its regex could not see the
  `"conclusion": null` a queued run carries. Found while building the above. (#517)
- **README corrected**: the E2E scoring pipeline runs in this repo, not in yours. (#507)
- **ROADMAP demoted to a view** over GitHub issues, which are the source of truth. (#518)

## [1.95.0] - 2026-08-07

**The repo is now `BaseInfinity/claude-sdlc-harness`.** The npm package stays
`agentic-sdlc-wizard`, and the plugin IDs, CLI bin and slash commands are unchanged —
those are what your install depends on, and renaming them would force every consumer to
reinstall for no functional gain. The old repo URL still redirects.

### Fixed — three defects that were shipping to every consumer

- **A hook could block forever on stdin.** `hooks/model-effort-check.sh` still drained
  stdin with a bare `cat > /dev/null` — the exact unbounded read v1.94.0 existed to
  remove, observed elsewhere alive at 10h19m against a 10-second timeout. It escaped
  because the test roster was hand-listed and this hook was never in it; the roster is
  now derived from `hooks/hooks.json` and fails if it drifts from the manifest.
- **We shipped the install footgun we warn about.** `instructions-loaded-check.sh` told
  every consumer, on every session start with an update available, to run a global npm
  install. The nudge is now channel-neutral and covers package-manager installs, which
  `claude update` cannot upgrade.
- **The docs promised a stall watchdog that has never existed.** No such variable is
  defined anywhere in this repo; the codex wrapper loops on `kill -0` and enforces no
  timeout at all. The claim is replaced with what the wrapper actually does.

### Fixed — the distribution boundary

`npm pack` ships no `scripts/` directory, yet five shipped references pointed consumers
at tools they never receive, including `skills/sdlc/SKILL.md` mandating
`scripts/merge-pr.sh`. Shipped guidance now names a real path (`gh pr merge --squash`)
and marks repo-local tooling as not installed.

### Fixed — gates that had no exception path

- **`scripts/merge-pr.sh --user-approved "<reason>"`** records a human decision on the PR
  before merging, and refuses to merge if that record cannot be posted. It cannot waive a
  red CI check or deleted tests.
- **The Cowork prompt gate now distinguishes a bypass from a justified exception.** It
  ended a turn outright for "don't TDD this one-time rename, verify after" — a stated
  reason with a stated alternative, so the safeguard was substituted rather than removed.
  It also now allows when ambiguous: this gate ends the turn with no retry, so a wrong
  denial costs the whole turn while a wrong allow costs nothing.

### Changed — Fable decides

Shipped guidance framed Fable as a rung to escalate to. The contract is stronger and is
now stated in order: **Fable decides → Opus implements → Fable reviews → Codex gates.**
Fable appears twice deliberately; Codex is last and singular, an adversarial gate rather
than a second opinion. Whether Fable should drive instead is explicitly recorded as
untested, not settled.

### Notes

`ROADMAP.md` had been telling cold sessions to start on work that did not exist, on a
branch that was empty. Corrected in place rather than deleted. It also claimed "Open PRs
— none" while one was open; it now links the tracker instead of restating it.

## [1.94.0] - 2026-08-05

### Fixed

- **Six shipped hooks could block forever on stdin** (plus the repo-local merge gate, which does not ship). Three — `codex-gate-check.sh`, `codex-review-stop-check.sh`, `tdd-pretool-check.sh` — read with a bare `$(cat)` and no guard at all. The other three had `[ ! -t 0 ]`, "is stdin not a terminal," which does not help: a unix socket is not a terminal, so the guard passes and the read waits for an EOF that never arrives. Five captured with `$(cat)`; `token-spike-check.sh` merely drained with `cat > /dev/null`, which blocks just the same. Observed live: `sdlc-prompt-check.sh` alive **10h19m against a 10-second hook timeout**, with stdin bound to a unix socket. The documented timeout did not reap it. If you installed the wizard, you have this. Nothing to do but update — the fix is in the hooks themselves.

- **Gates now fail closed when they cannot read their input.** A gate that cannot see the command it is judging cannot judge it safely, so `codex-gate-check.sh`, `tdd-pretool-check.sh` and the repo-local merge gate deny rather than allow. Advisory hooks (prompt check, stop check, precompact, token spike) degrade quietly instead — they must never block your prompt over a stdin hiccup.

- **`CLAUDE.md` misdescribed what this repo ships.** Its inventory listed `.claude/` and `tests/` but omitted `cli/`, `skills/`, `hooks/` and `.claude-plugin/` — every directory in `package.json`'s `files` list, i.e. exactly what consumers receive. A new guard reads `files` directly, so adding a shipped path now forces documenting it.

### Notes

The stdin fix took five iterations. Four were wrong, and **every one of them passed a green test**:

1. `read -d '' -t 5` stopped the hang and silently returned 0 bytes on a 45-byte payload — bash 3.2 discards partial input on timeout with `-d`.
2. A line accumulator turned the hang into a **silent gate bypass**: complete payload, stalled pipe, all three gates allowed. Found by cross-model review.
3. Failing closed on `rc > 128` was dead code — on bash 3.2 a timeout and a clean EOF **both return 1**. The `>128` convention is bash 4+.
4. `set -e` killed the merge gate before it could capture the read's exit code, so it exited 1: a script error wearing the costume of a policy decision.
5. Integer `$SECONDS` false-blocked benign payloads 4 times in 15. bash 3.2 has no sub-second clock, so the budget is now `limit + 1` — guaranteeing the configured timeout is a floor that is actually honoured.

The regression test for (5) was itself vacuous at first: an instant-EOF fixture scored **0/15 against deliberately reverted code**. It needed a 0.20s delay before EOF to reproduce the bug at all.

Four of those five were caught by an independent model or by deliberately breaking the fix to see whether the test noticed — none by a test passing.

## [1.93.0] - 2026-08-03

### Fixed

- **The merge gate never read a verdict.** `scripts/merge-pr.sh`'s cross-model clearance parser required reviewer, confidence and SHA — and merged on those alone. Two reviewers posting `verdict: "NO"` at confidence 97 and 99 merged a PR. Proven by a test that failed before the fix.

  It survived because the function already had 49 assertions covering confidence bounds, SHA binding, authorship and payload visibility. Every fixture omitted a verdict, so the suite tested the *shape* of the evidence and never the *answer inside it*.

  `verdict` is now required and anything but an exact `YES` fails closed. Payloads are pinned to exactly four keys with no backslash permitted, after two rounds of counting forbidden key text lost to unicode escaping — the check now states what is allowed rather than chasing what is banned. A sub-threshold `YES` prescribes the next action instead of dead-ending: v1.92.0 got YES/97 and YES/93, both reviewers agreeing it was safe, and the gate simply refused, so a human ran that merge by hand.

### Added

- **A working context ceiling: keep sessions under ~350K tokens** (~35% of a 1M window). Adopted as a practitioner heuristic to be validated by use, not derived from a study. It sits at the conservative end of reported practice — community numbers cluster at 80-200K for 200K-window models and 200-500K for 1M-window models. **No specific cliff has been benchmarked and this repo does not claim one.**

- **"Run the test — a completion claim is not a test result."** A test result is evidence; an assertion that something is fixed is not. The rule needs no statistics and is not conditioned on context size.

  Research cited only to establish the failure mode is common enough to warrant a rule: among runs that had *already failed*, agents still asserted success in 45% and 48% of two tau2-bench domains, 3% in a third, and 75.8% of AppWorld failures carrying an explicit status claim ([arXiv:2606.09863](https://arxiv.org/html/2606.09863)). LLM judges detect this poorly — AUROC ≤0.65 and ~0.54 — so a second model is not a validated detector.

  **Explicitly not claimed:** how much a completion claim should shift confidence (those percentages are conditioned on failure), that the effect worsens with context length, or that cross-model review catches it.

- Degradation below advertised context windows, with figures pinned by tests so a future edit cannot silently misquote them: [Chroma context rot](https://www.trychroma.com/research/context-rot), [NoLiMa](https://arxiv.org/abs/2502.05167), [RULER](https://arxiv.org/abs/2404.06654), [Lost in the Middle](https://cs.stanford.edu/~nfliu/papers/lost-in-the-middle.arxiv2023.pdf).

### Notes

Five cross-model review rounds found and fixed, in this section alone: four misquoted citations, a fabricated "dumb zone" attribution, a fabricated context threshold, three phrasings of one unsupported inference, and a caveat that misdescribed which measurement was missing. The consistency guard was rewritten twice after it both accepted a reversed counterfeit and rejected honest paraphrase; it now pins citation figures only and documents that limit rather than implying it can judge meaning.

## [1.92.0] - 2026-08-03

### Removed

- **The Cowork `Stop` hook is gone.** It fired 12 times in a single session and was wrong 11 of them: blocking turns that modified zero files, turns whose verification was already stated in the response, and five separate times quoting its own in-flight exemption before overriding it — once with a reason reading "This is in-flight work, not unverified work." It fired **zero** times during the v1.91.0 release work, which contained ten real defects.

  Three prior prompt rewrites each added exemption language the evaluator then ignored, so a fourth rewrite was not the fix. The governing constraint was already written in this repo's other Stop hook: *"Stop fires at the end of every turn, not just at true session end, and it must never prevent the user from getting their response."* A blocking Stop hook violates that by construction.

  **Cowork now has no completion enforcement.** `PreToolUse` (new-file heuristic) and `UserPromptSubmit` (explicit bypass denial) remain. `hooks/codex-review-stop-check.sh` covers the CLI only — different condition, non-blocking, and it cannot run in Cowork. `cowork/README.md`, the wizard doc, and E2E Test 5c are corrected to say so; previously they promised a hook that no longer exists.

- **~190 lines of tests asserting that hook's prompt TEXT.** They pinned which exemptions it named and what it must not demand. All passed continuously while the hook was wrong 11 times in 12 — a prompt containing the right words says nothing about whether the evaluator follows them. Replaced with assertions that the hook stays absent.

### Fixed

- `tests/test-stop-hook-terminates.sh` had lost its `[ "$FAIL" -eq 0 ] || exit 1` tail during the edit above, leaving a suite that printed failures and exited 0 — CI would have stayed green with a blocking hook reintroduced. Caught in review, restored, and watched fail before being accepted. A missing shipped `hooks.json` is a failure again rather than a silent skip.

- The same file carried a **vacuous control assertion**: it accepted "hook produced output" OR "hook was silent", which is every possible outcome, so nothing ever executed the script behind the allowlisted path. It now asserts the hook exits 0 on a normal stop, since exit 2 blocks the user's response. This sat directly beneath a comment condemning that exact defect class — the one this release deletes ~190 lines for committing.

- The guard that keeps the hook absent no longer enumerates load paths. It asserts one rule: the only `Stop` hook anywhere in the repo is the three exact command strings invoking `codex-review-stop-check.sh`. Scans `.json`, `.yaml`/`.yml`, and `.md` YAML frontmatter; skips only `.git`.

  **Accepted risk, logged so it is not re-litigated:** this guards *accident*, not an adversary. It cannot stop someone who deliberately re-adds a hook, because that person can also edit the guard. Six review rounds each found a new way to defeat it under an insider-adversary model; that model is unsatisfiable for a repo-local test, and further hardening is out of scope. A repo-file scan also cannot see a hook registered at install or runtime that no repo file expresses.

## [1.91.0] - 2026-08-02

### Fixed

- **The TDD hook had been silently dead for monorepo consumers since Claude Code 2.1.214.** `hooks/hooks.json` gated it on `Write(src/**)`. CC 2.1.214 changed single-segment `dir/**` conditions to match only `<cwd>/dir`; any-depth matching now requires `**/src/**`. Because `hooks/` ships via npm, every consumer with source under a **nested** `src/` directory — `packages/*/src/`, `apps/web/src/` — lost TDD enforcement with **no error and no warning**. (Repos whose source lives only in `lib/` or `app/` were never matched by `src/**` and lost nothing here.). The gate simply stopped firing. This repo never noticed because its own paths genuinely sit at the root.

  Fixed to `**/src/**`, with a regression test that builds a real monorepo-shaped tree and **executes glob semantics** against every `if:` pattern in the manifest rather than grepping for a string. RED confirmed before the fix (`src/** matched only ['src/widget.ts']`). That test would have caught 2.1.214 the week it landed.

### Changed

- **Driver effort default is now `high` for complex projects and `medium` for routine web/CRUD work**, with `xhigh` demoted to an escalation trigger rather than a standing default. Maintainer decision; consistent with Anthropic's Opus 5 prompting guidance to use lower effort liberally where quality holds. Guarded by a new positive-anchor assertion — there was previously no driver-effort guard at all.
- **`AGENTS.md` gained a `## Code Review Rules` section.** Codex loads this heading automatically for `codex review`; the existing review guidance was invisible to it without one. The rules encode defects found repeatedly in this repo: a test that greps is not a test of behavior; fixtures only prove a rule works on fixture-shaped documents; prefer positive anchors to denylists; a guard must not be able to damage what it protects.
- `AGENTS.md`'s blast-radius section previously listed only `.claude/` paths, which ship to nobody, and omitted `hooks/` and `skills/`, which ship to everyone. Rewritten against `package.json`'s `files` as the authority.
- Claude Code baseline marker moved v2.1.210 → v2.1.220.

### Note

The E2E judge model in `tests/e2e/` remains pinned to `claude-opus-4-7` deliberately. Changing it would invalidate every historical score and read as quality drift in CUSUM, so it needs its own migration with a provenance field rather than a quiet bump.

## [1.90.0] - 2026-07-30

### Fixed — things that were broken for consumers

- **Stop hook could block on work it was impossible to satisfy (#477, fourth defect).** The Cowork `Stop` hook denied a turn when a background task, review, or CI run was still in flight. An agent cannot make a background job finish sooner, so the only ways to satisfy the block were to wait forever or misstate the state — the same unsatisfiable-condition shape as the original #477 loop. Pending is not unverified, and the harness re-invokes the agent when the job completes, so ending the turn abandons nothing. Guarded by `tests/test-stop-hook-terminates.sh`.
- **The install instructions could not work (#455).** `CLAUDE_CODE_SDLC_WIZARD.md` told users to add the plugin from a `.../tree/main/cowork` web URL. That is not a supported marketplace source — only `owner/repo` shorthand, full git URLs, local paths, or a direct `marketplace.json` URL are. It now documents the repo-as-marketplace flow that `cowork/README.md` already described, so the two no longer contradict each other. Whether native Desktop sync then succeeds is still open in #455.
- **`cowork/README.md` documented a Stop contract that v1.89.0 deleted** — it still claimed the hook blocks on missing confidence, missing self-review, and tests not shown passing. All three were deliberately removed as false-block sources. Corrected to the single real blocking condition — and, after a reviewer caught the file still contradicting itself further down, the "the hooks enforce it" claim about the whole methodology was narrowed too. The hooks enforce a slice; the skills describe the rest.
- **`tests/e2e/codex-cowork-install.md` would have failed the plugin for behaving correctly.** Its hook expectations still encoded the pre-v1.89.0 Stop contract, told the tester to look for injected text that prompt hooks never emit, and installed via the broken URL above. Rewritten: gates rather than narrators, positive and negative cases per hook, a `stop_hook_active` loop-guard step, and the marketplace flow as the method that matters.

### Added

- **A documented review loop, not just a review protocol.** `CLAUDE_CODE_SDLC_WIZARD.md` gained the iterate/gate cycle with explicit termination rules: "done" means zero *unresolved* findings, a round cap ends in escalation and never in shipping, and both reviewers get the same severity scale so their verdicts are comparable. Take the lower verdict; do not average them.
- **A convergence test that uses severity, not count.** Finding count rises when a reviewer looks somewhere new, which is the opposite of a stopping signal. Judge by maximum severity per round, and only from a reviewer that has not already cleared the code — one reviewer's trend flattening means only that it has run out of defects it can see.
- **Style findings become lint rules, not review findings.** A cross-model round is slow and non-deterministic; a linter is free and total. If a style point is worth honouring, add the rule so nothing can violate it again.
- **The Prove-It Gate now covers PRACTICES, not just components.** It read "new skill/hook/workflow?"; a new process step slipped past it because it was none of those. Now "New skill/hook/workflow/PRACTICE?"
- **`TESTING.md` now states the Testing Diamond and the TDD contract.** Both existed elsewhere but not in this repo's own testing document, so compliance could not be checked. It also records honestly that the repo's current distribution is **not** reliably known — two census attempts disagreed and 39 of 64 suites went unclassified — so no ratio is quoted until ROADMAP #490 produces a reproducible one.

### Changed

- **TDD guidance is explicit that RED is per-assertion.** The common miss is watching red at the *suite* level: one assertion fails, the suite is red, you implement, it goes green, and an assertion that was green from birth is never noticed. Editing an existing test splits into two cases: if it guards a bug you are about to fix, RED is free; if it guards behaviour that is **already correct**, RED is unavailable — correct code does not fail — and the honest move is to say the assertion is unverified rather than imply otherwise. Prefer rewriting a suspect test over patching it either way.
- **`/goal` documentation corrected.** The evaluator is the configurable small-fast-model (Haiku by default on the Claude API), it judges the transcript only and cannot run tools, and `ANTHROPIC_DEFAULT_HAIKU_MODEL` is **not** scoped to `/goal` — it also moves conversation summarization onto that model.
- **Standing instructions stay in force.** Re-asking hands back a decision the human already made. When two of their instructions appear to conflict, apply the stricter bar and act rather than arbitrating upward.
- **`hooks/sdlc-prompt-check.sh`** heredoc delimiter renamed `SETUP` → `SETUP_REQUIRED`. Behaviour identical. The first content line began with the delimiter word, which made shellcheck report a false SC1122; renaming removes the ambiguity for human readers too.

### Repo-local, but worth stating plainly

- **`.claude/settings.json` gained 22 permission-allow rules**, including Chrome browser-automation tools (`computer`, `browser_batch`) and a set of test scripts. This came from a `/fewer-permission-prompts` pass and is a real broadening of what runs without a prompt **in this repository only** — it is not part of the npm package and affects no consumer. Flagged here because a permission change that reaches a release without appearing in its notes is the kind of thing nobody audits later.

### Note

A **shellcheck CI gate** was built for this release and then deliberately pulled from it. It is repo-local (`.github/workflows/`, absent from this package), and across four review rounds every finding concerned the gate or the tests guarding it rather than anything shipped — including a real bypass where a file named `-S error <path>` was read as command-line options and skipped. Both cross-model reviewers independently recommended removing it rather than holding consumer fixes behind another guard-design cycle. **An unverified gate is worse than no gate: its failure mode is a false green.** It lands separately once its tests hold. Tracked as ROADMAP #492.

### Note

The single-tier merge gate (#485) is **not** in this release. It is repo-local tooling that ships to nobody, and it is still in cross-model review — ten distinct bypasses of its clearance-visibility check were found and fixed across eight rounds. Holding these consumer-facing fixes behind it would have left a broken install instruction in place.

## [1.89.0] - 2026-07-27

### Fixed
- **Stop hook could block a turn forever** (#477). The Cowork prompt-type Stop hook had no
  repeat-suppression, so once it blocked it re-evaluated the same unchanged state and blocked
  again — observed 9 consecutive times in a consumer repo before the harness force-broke it.
  Three distinct defects, all of the same kind: the judge was ruling on things it cannot see.
  It now honours `stop_hook_active`, judges the current turn only, and blocks on exactly one
  condition — code changed with no verification attempted at all. It no longer blocks on test
  *outcomes* (a suite with known, explained failures is fine), scoped runs, infrastructure-blocked
  suites, or missing ceremony like a stated confidence level. It fails open when uncertain.
  **This matters because the wizard installs everywhere:** demanding a green suite made the hook
  unusable in any repo with long-standing failures.
- **Merge approval no longer means merge bypass** (#479). The single escape past the release/policy
  denylist also disabled the CI check, the test-deletion check, the SHA-freshness check and the
  clearance-artifact check — so acknowledging one finding disarmed four working ones. That flag is
  deleted. `--cross-model-cleared` now satisfies the denylist finding only; every other check is
  unconditional. Clearance is read from comments on the remote PR (two distinct reviewers, >=95%,
  bound to the head SHA) and is an audit trail, not an authentication boundary — stated plainly in
  the script rather than oversold.
- The denylist is now tiered. Paths that can alter the evidence a merge relies on (CI workflows,
  hooks, agent config, the merge script) always need a human. Policy prose is clearable on posted
  cross-model evidence. `CHANGELOG.md` is delisted — measured as dead weight.

### Added
- **Parallel blind dual review** (ROADMAP #469) in `CLAUDE_CODE_SDLC_WIZARD.md`. Run two reviewers
  in parallel and blind to each other, then merge findings. Chaining them anchors the second on the
  first's output. Includes a cost table scaled to blast radius and a single-model fallback.
- `tests/test-roadmap-integrity.sh`, `tests/test-cross-model-clearance.sh`,
  `tests/test-stop-hook-terminates.sh`.

## [1.88.0] - 2026-07-25

### Changed — Opus 5 becomes the recommended driver

- **Setup A is now Opus 5 + Fable advisor at `xhigh`** (was Sonnet 5). Anthropic's own recommendation for difficult and long-running work. Requires Claude Code **v2.1.219+** — below that, `opus` still resolves to 4.8. Flagged as a trial: strong on paper, unproven by field data at time of writing.
- **Setup B repurposed to Sonnet 5 at `medium`** for simple/one-off work — no longer the main-workflow driver.
- Setup C's opusplan table corrected to name Opus 5 as the planner, with a note on pinning 4.8 explicitly if you want its field-proven behavior.
- Propagated across README, SDLC.md, the wizard doc, both `sdlc/SKILL.md` copies, the setup and update skills, AGENTS.md, CI_CD.md, and `cli/lib/repo-complexity.js`.

### Fixed — autocompact guidance for Opus 5 (consumer-visible)

- **`skills/setup/SKILL.md` was writing `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: "30"` into consumer `.claude/settings.json`** for Setup A. That figure was derived for the retired `opus[1m]` extended-context opt-in and was never re-derived. **Setup A now writes no override at all.**
- Per the official env-vars docs, that variable only lowers the trigger where Claude Code compacts **proactively** — when `CLAUDE_CODE_AUTO_COMPACT_WINDOW` is set, in cloud sessions, on Sonnet 4.6/Opus 4.6 without extended context, and on Sonnet 5. A local Opus session is the docs' own counter-example. A 1M window establishes *capacity*, not proactive mode.
- Corrected in six wizard-doc locations plus the writer. Deliberately worded as a **documentation gap**, not a runtime claim — the docs are silent on Opus 5's local behavior, so the wizard says what is documented rather than asserting what the model does.
- **Setup B's `75` is unchanged and still correct** — Sonnet 5 *is* a documented proactive case. Note it is global to the settings file and applies to subagents; switching drivers does not switch it.

### Changed — escalation ladder: the human is the last rung

- Both `sdlc/SKILL.md` copies and the wizard doc previously said **"ASK USER"** for LOW confidence, FAILED-2x, and CONFUSED — skipping model escalation entirely. Now: **Fable → Codex `xhigh` → the human**, with the human reserved for priority, risk appetite, scope, spend, and irreversible or outward-facing calls.
- **Confidence is not authorization.** A high score never overrides an approval, external-effect, production, release/merge, or policy gate; merge protections are non-overridable. Production-deploy and approval gates remain human-gated by design.
- Ten more direct-to-human routes removed across the wizard doc and README, including the CI-failure flow diagram and the generated `CLAUDE.md` template.
- The shipped runtime hook (`hooks/sdlc-prompt-check.sh`) previously emitted the *old* ladder on every consumer session, contradicting the docs. Fixed, and now covered by a regression test.

### Added

- `SDLC.md` — a 2026-07-24 post-mortem: nine portable lessons on test design and process, including why a guard test can be vacuous in several distinct ways and why `bash "$t" </dev/null` matters when looping over test scripts.
- ROADMAP #468–#479, including the Claude 5 context-engineering realignment (#476), `/doctor` integration (#477), the merge-gate friction analysis (#478), and a `/sdlc` gap where the workflow verifies the solution but never re-checks the diagnosis (#479).

## [1.87.0] - 2026-07-14

### Added
- **🏆 First external contribution in this repo's history: [@thejesh23](https://github.com/thejesh23)** (#444, PR #445 — merged under his authorship). GitHub Copilot CLI ≥ 1.0.65 tightened `argument-hint` frontmatter validation to string-only and silently dropped all 7 wizard skills from its command menu. Bare brackets (`argument-hint: [task description]`) parse as a YAML flow sequence, not a string — the feedback skill's hint even parsed as an array wrapping a *mapping* — and Claude Code's lenient rendering had hidden it since the fields were introduced. His report pinned the exact breaking version with primary-source links and listed every affected file (it matched our own repo-wide sweep exactly); his fix updated the live skills and the `cowork/` copies together. Out of 300+ merged PRs, contributor #1. Maintainer's words, on the record: *"he deserves it and I am forever grateful."*
- **#444 regression test** (PR #447): `test_argument_hint_frontmatter_is_string` parses every live + cowork SKILL.md frontmatter with real YAML and fails on any non-string `argument-hint`; also guards the wizard doc's copy-source examples (the frontmatter reference-table cell was #445's one untouched straggler — consumers copy these blocks, so an unquoted example re-inherits the bug into generated repos). Hardened per Codex round-1 finding: the grep uses `argument-hint:[[:space:]]*\[` because an exactly-one-space pattern false-greened on zero/two-space variants (mutation-verified both directions). Anti-vacuity guards prevent the test from passing on zero files or unparsed frontmatter. Cross-vendor SKILL.md compatibility is now tracked as ROADMAP #448.

### Changed
- **GPT-5.6 Sol replaces GPT-5.5 as the cross-model reviewer** across all live guidance (#439, PR #441): `AI_SETUP_LANES.md`, `README.md`, `CLAUDE_CODE_SDLC_WIZARD.md`, both sdlc SKILL.md copies, `AGENTS.md`, repo `CLAUDE.md`. The unpinned auto-detect design is deliberately preserved (Codex CLI resolves your account's best model — proven live when it picked up Sol with zero config change); fallback chain documented as Sol → Terra. Reviewer effort stays `xhigh` per OpenAI's own migration guidance; Pro/`max` documented as escalation for unusually risky PRs. Historical citations (vending-bench, E2E audit, CHANGELOG) explicitly untouched and regression-guarded — rewriting them would falsify what actually ran.
- **Sonnet 5's documented default effort is now `medium`** (was `high`), and the "~5x less Max quota" claim is gone (#440, PR #443). Codex traced the 5x figure to commit `ab6fc9c` with zero supporting measurement anywhere; all 8 instances across 6 live-guidance files replaced with qualified language sourced to Anthropic's tokenizer note (Sonnet 5's newer tokenizer produces ~30% more tokens than Opus 4.6's for the same text; community cost reports suggest the advantage narrows at `high`/`xhigh`; no controlled measurement exists — check `/usage`). CodeRabbit — the source the wizard already cited — actually recommends `medium`. Escalation ladder is now `medium` → `high` → `xhigh`; fresh Fable and Codex opinions independently converged on this. `hooks/model-effort-check.sh` floor updated to match so the hook doesn't nag users following the wizard's own default (`medium` now silent; explicit `low` and the settings-only-`max` quirk still warn; worst-case warning output re-fitted under the 500-char cap after Codex caught the cap test had gone vacuous). 4 new mutation-verified doc-consistency tests plus a repo-wide guard banning the unqualified-multiplier phrasing class.
- **Setup A semantics made explicit** (PR #446, README "Reading Setup A precisely" + `AI_SETUP_LANES.md`): effort escalation happens *inside* the Sonnet 5 driver; model escalation *swaps the driver* to Opus 4.8 xhigh (2 failed attempts / LOW confidence / high-stakes); `advisor()` failure falls back to spawning a Fable subagent — never to skipping the check. The advisor-outage procedure's "continue with no advisor" path (which directly contradicted the new rule two sections above it — Codex round-1 catch) now routes to the subagent fallback: swap the transport, not the check. Section-scoped negative test assertions keep the skip-path from returning.

### Fixed
- ROADMAP #236 bloat-hunt follow-through (PR #440): hook/test cleanups, ROADMAP archive split.
- ROADMAP #434 sub-item statuses corrected against git history instead of re-asserted (PR #442).

### Why
Seven consumer-affecting commits had accumulated on main since v1.86.0 (July 5) with no npm release — discovered when the repo's first external bug report (#444) revealed that `npx agentic-sdlc-wizard@latest init` was still installing skills Copilot CLI silently drops even after the fix was merged and celebrated, with nothing in the process that would ever have prompted a release. Merge-to-main does not publish; only a `v*` tag does. Release-drift detection (own-package npm-vs-main watcher, in the style of `cc-version-drift.yml`) is tracked as ROADMAP #449 so this class of stranding is machine-caught, not memory-caught.

## [1.86.0] - 2026-07-05

### Fixed
- **#437: `codex-gate-check.sh` stale-certification loophole.** A CERTIFIED/REVIEWED `handoff.json` status was checked as a literal string with no freshness check — any number of commits made after certification would sail through the gate on the same stale status forever. Proven live during the v1.84.0 release: 2 real post-certification commits both passed the gate on a round-11 CERTIFIED handoff that was never re-issued. Fixed: certification now records `commit_sha` (HEAD at cert time) in `handoff.json`; the gate compares it to current HEAD and treats a mismatch — or a missing field, e.g. an old-format handoff.json predating this fix — as stale (exit 2, same as an uncertified commit). This allows exactly one commit after certification and blocks the next one until re-cert. `CODEX_GATE_SKIP=1` remains the logged-justification escape hatch. TDD: 2 new tests (`test_codex_gate_blocks_stale_certification_after_new_commit`, `test_codex_gate_blocks_missing_commit_sha_as_stale`) proven RED against the unmodified hook, GREEN after; 2 existing tests updated to real git-repo fixtures with a matching `commit_sha` (191/191 hook tests green, up from 189).
- **The protocol docs needed updating in 3 separate places, not 1 — Codex cross-model review caught 2 of them.** `CLAUDE_CODE_SDLC_WIZARD.md` documents the cross-model review protocol twice (a condensed summary section and a fuller tutorial section), each with its own prose instruction *and* its own ASCII flow diagram — 7 total "reached CERTIFIED, now what" decision points. Round 1 caught a missed prose instruction in the tutorial section; round 2's mutation testing proved my first regression test (a whole-file count comparison) had real slack and, while investigating that, surfaced a 3rd, entirely separate miss: the condensed section's own flow diagram, never touched by anything. All 7 decision points (3 prose instructions + 4 diagram exits across both sections) now write `"commit_sha"` on the same line. `skills/sdlc/SKILL.md` updated too. Replaced the count-based regression test with a per-line proximity check (`test_wizard_doc_certified_paths_all_mention_commit_sha` in `tests/test-doc-consistency.sh`) that can't be fooled by aggregate slack — proved it independently by mutating each of the 3 known-fragile spots one at a time and confirming each is individually caught (53/53 at baseline).
- **Latent bug in `tests/test-self-update.sh`'s multi-reviewer checks**, exposed (not caused) while trimming `skills/sdlc/SKILL.md` back under its 20K-char cap: 3 test functions used an unescaped `?` as a quantifier (`multi.?review`) inside plain `grep -qi`, which runs basic regex where a bare `?` is a literal character, not "0 or 1 of the preceding." The check had only ever passed via an incidental phrase collision elsewhere in the file ("parallel tasks... `sdlc-reviewer`" in an unrelated Context Management bullet, not actual multi-reviewer guidance) — trimming that unrelated bullet removed the accidental match and surfaced the real bug. Fixed by adding `-E` (extended regex) so `?` behaves as intended; verified it now matches the genuine `**Multi-reviewer:**` guidance directly (153/153 tests green).

### Why
Post-ship retrospective on v1.84.0 (2026-07-05) independently re-confirmed a gap already tracked as ROADMAP #437 (filed 2026-07-04 while shipping #436). Design settled with Fable's input in the same retrospective, implemented as a standalone TDD PR per that plan — kept separate from the doc-only v1.85.0 release since this one changes actual hook behavior on a security-relevant gate.

## [1.85.0] - 2026-07-05

### Fixed
- **Post-ship retrospective on v1.84.0** (independent Fable + Codex audits, both verified against primary sources before acting on them): `CLAUDE_CODE_SDLC_WIZARD.md`'s "Exception — known-large migrations" example still cited the wrong round count ("7 rounds... round 5") after the review ran to 11 rounds and round 8 turned out to be the more consequential find — corrected to the actual numbers.
- The `### Convergence` section had no record of this release's own sharpest lesson: cross-model review and CI are different verification layers. Round-11 CERTIFIED plus a full local sweep still missed 3 real bugs (a content regression, an npm-version JSON format change, a missing executable bit) that only surfaced once the PR was actually pushed and CI ran. Added a "CERTIFIED is not the finish line" callout so this isn't relearned per-release.
- `## CI Feedback Loop — Local Shepherd` (the portable wizard doc's version) was measurably weaker than `skills/sdlc/SKILL.md`'s own copy of the same section — missing "read CI logs even when green" (a green checkmark hides warnings/skipped steps/degraded scores — see v1.24.0), missing the cross-model CI-log-audit step, missing explicit "NEVER AUTO-MERGE" language (PR #145 evidence). Synced to match.
- `Release Review Focus` had no "Policy Migration Inventory" checklist item, despite the wizard doc itself documenting (in `SDLC.md`'s Lessons Learned) that exactly this gap is what turned v1.84.0's migration into an 11-round review instead of ~4-5. Added, with v1.84.0 as the cited evidence.
- `ROADMAP.md` #437 (the codex-gate handoff-staleness gap, filed 2026-07-04) settled its previously-open design question: `commit_sha`-in-`handoff.json` compared against current HEAD, not a branch/files-changed heuristic — simpler, and directly answers the "how do legitimate follow-up commits not false-positive" question the original entry raised. Implementation is a separate, standalone TDD PR (not bundled with this doc-only release).
- **Codex round 1 caught 2 more stale `1.84.0` version pointers this release's own version-bump checklist didn't cover:** `ROADMAP.md`'s "Built With SDLC Wizard" living-tracker row (this repo's own entry) and `cowork/README.md`'s "Version" section — neither matches the canonical checklist's two string patterns (`SDLC Wizard Version:` prefix or a `"version":` JSON key), since both read as plain prose. Fixed, and `SDLC.md`'s version-bump-checklist lesson updated with a broader canonical grep (`grep -rn "<previous-version>" . --include="*.md" --include="*.json"`, manually triage every hit) so the narrower two-pattern grep isn't the only check next release.

### Why
Same-session retrospective (2026-07-05) on the just-shipped v1.84.0: the user asked Fable and Codex, independently, "how well did this release follow its own `/sdlc` checklist, and what's missing from the doc itself." Both converged on real, independently-verified findings — this release fixes the doc-only subset; the hook-behavior fix (#437) and any sibling-repo (`claude-gdlc-wizard`, `claude-rdlc-wizard`, etc.) sync follow as separate, explicitly-scoped work per Fable's own recommendation to split rather than bundle.

## [1.84.0] - 2026-07-04

### Fixed
- **#436**: `codex-gate-check.sh` (cross-model review gate) and `tdd-pretool-check.sh` (TDD RED gate) printed the correct blocking warning text but always exited 0 — the exact condition Claude Code requires to actually deny a tool call is exit 2 + stderr, so neither hook ever blocked anything. Fixed both. `codex-gate-check.sh`'s commit-detection also went through 3 rounds of Codex cross-model review: an escaped-quote false negative (round 1), an over-broad fix that created a sibling-field false positive (round 2), and a field-scoped escape-aware fix that certified clean (round 3).
- **#436**: `tdd-pretool-check.sh`'s `src/` gate only matched paths containing `/src/` (nested/absolute) — relative paths like `src/app.js` silently bypassed the gate entirely. Now matches both forms.
- Distribution-parity gaps found via a new stronger test (`test_hooks_json_script_parity`, compares actual registered scripts per hook event, not just event-name presence): `codex-gate-check.sh` was never wired into the plugin's `hooks/hooks.json` (plugin users had zero cross-model gate); `goal-confidence-check.sh` was missing from the project's own `.claude/settings.json`; `token-spike-check.sh` was missing from the CLI template and from `cli/init.js`'s FILES array entirely (never actually copied to consumer repos by `npx ... init`).
- `SDLC.md`'s own Recommended Model/Effort table and `CLAUDE_CODE_SDLC_WIZARD.md`'s Autocompact Tuning table still recommended `claude-opus-4-6` + blanket `max` via shell-rc env var — the exact anti-pattern that bit a real user (see [1.80.0] entry below). Both updated to model-aware guidance; SDLC.md's table no longer contradicts its own Lessons Learned entry on the same page.
- **AI Setup Lanes v3 migration was incomplete** (Codex cross-model review caught this before release): the lane rewrite only updated the top lane tables in `AI_SETUP_LANES.md` — everything below (When-to-Use sections, Final Review Policy, Credit-Spend Warning, the entire Billing section) still described the old 3-lane structure with mismatched letters and stale model assignments (e.g. "Setups A and B use Opus 4.6 max" when the new Setup A is Sonnet 5). Fully reconciled to the 4-lane structure throughout. `README.md`'s "Choosing Your Model" section and `AGENTS.md`'s lane summary had the same staleness (README still told users to pin `claude-opus-4-6` + `CLAUDE_CODE_EFFORT_LEVEL=max` — the exact incident this release is about) and were rewritten to match. `skills/sdlc/SKILL.md` and `SDLC.md` said Sonnet 5's default effort is flat `xhigh`; corrected to match `AI_SETUP_LANES.md`'s tested position (`high` default, escalate to `xhigh` for hard tasks).
- **Round 2/3 of the same Codex cross-model review** found the migration was still incomplete beyond what round 1 sampled: `skills/sdlc/SKILL.md`'s own frontmatter still hardcoded `effort: max`, directly contradicting its own model-aware guidance 20 lines below — removed the field (driver effort now comes from the session/lane, not the skill). `CLAUDE_CODE_SDLC_WIZARD.md` had far more embedded "Opus 4.6 flagship / blanket max" doctrine than the two sections already fixed: the "Recommended Effort Level" section, its skill-frontmatter-field example table, the "1M vs 200K Context Window" opening paragraph, the "OpusPlan Tier" and "Latest tier — Opus 4.8" sections (both said "the wizard's flagship recommendation is Opus 4.6 max" and "wizard standard is max on all Claude models"), the Advisor Model "Recommended pairings" table (still used the old "Setup A — Premium / Setup B — Saver" labels), the "Reading Usage Signals" table (said Setup A's autocompact override is 30% — that's the old Opus-era number; Setup A is now Sonnet 5, whose tested default is 75%), and the "Confidence Check" table (still said `max (default)` / `Run /effort max now` for every confidence level). Rewritten to the model-aware framing; a round-3 Codex recheck caught one more instance (an unqualified "flagship Opus 4.6" in the Setup 9.5 opt-in paragraph, now labeled "legacy flagship" to match `AI_SETUP_LANES.md`'s own terminology for Setup B) — treat any remaining bare "flagship"/"blanket max" reference anywhere in this file as a bug, not an intentional carryover. Two existing tests (`test_skill_frontmatter` in `test-cli.sh`, `test_skills_have_effort` in `test-self-update.sh`, `test_wizard_confidence_effort_max`/`test_skill_confidence_effort_max` in `test-hooks.sh`) still asserted the old blanket-`max`/frontmatter-`effort` policy as correct — updated to assert the new intentional design instead of silently masking it.
- **Round 4 of the same review** found stale doctrine had spread well beyond the wizard doc into the actual setup/update flow users run: `skills/setup/SKILL.md`'s Step 9.5 menu never offered Sonnet 5 as a pinnable choice at all (only No pin / OpusPlan / "Flagship full" (Opus 4.6) / "Latest" (Opus 4.8, "effort: always max")) — rewritten to a 4-choice menu matching the current lanes (`[N]` no pin, `[s]` Sonnet 5 + Fable / Setup A, `[o]` OpusPlan Hybrid / Setup C now paired with an Opus 4.8 advisor, `[b]` Opus 4.6 Stability / Setup B). `skills/update/SKILL.md`'s Step 7.8 recommended `claude-opus-4-6` as the opusplan advisor (now `claude-opus-4-8`, matching the corrected wizard-doc guidance) and its Step 7.9 unconditionally pushed every user toward a persistent `CLAUDE_CODE_EFFORT_LEVEL=max` — rewritten to be driver-aware (only recommends the persistent `max` env pin for an Opus 4.6 driver; warns and recommends removal for a Sonnet 5 or Opus 4.8 driver, since that's the literal anti-pattern that caused this release's motivating incident). `CI_CD.md`, `tests/e2e/local-shepherd.sh`, `cli/lib/repo-complexity.js`, and `tests/test-repo-complexity.sh` had stale "wizard recommends Opus 4.6 max" comments/prose, corrected to Sonnet 5 / Setup A. `skills/setup/SKILL.md` and `skills/update/SKILL.md` both grew past their 20000-char audit threshold from these fixes — trimmed (condensed "Tell the user" prose in setup, trimmed 2 more of the oldest CHANGELOG-example bullets in update).
- **Round 5 of the same review** found the most consequential gap yet: `hooks/model-effort-check.sh` (a live SessionStart hook, not just documentation) still only accepted `xhigh` or `max` as silent and warned "SDLC requires xhigh or max" on any other value — meaning it would actively nudge a Sonnet-5-at-`high` session (the wizard's own new recommended default) to bump to `xhigh` unnecessarily. Fixed: `high` is now also a silent floor, since it's Sonnet 5's and Fable's tested default; warning text and comments updated to match. Five existing hook tests baked in the old high-triggers-warning assumption (`test_model_effort_check_stale_effort` used `effortLevel:"high"` as its "should warn" fixture; the below-floor loop test iterated `high medium low` expecting all three to warn; two more fixtures used `"high"` incidentally while testing unrelated nested-CWD/size-cap behavior) — all four repointed to `medium`/`low` fixtures, plus one new test (`test_model_effort_check_high_silent`) added to lock in the new behavior. Also fixed a genuine remaining mismatch Codex's grep caught in `CLAUDE_CODE_SDLC_WIZARD.md`'s Step 9.5 opt-in paragraph: it described a 4th "Opus 4.8 escalation + Fable advisor" Step 9.5 menu choice that doesn't actually exist in the round-4-rewritten `skills/setup/SKILL.md` (that skill's menu is now N/s/o/b only — Opus 4.8 is session-level escalation via `/model`, not a persistent Step 9.5 pin) — corrected to describe the actual 4 choices.
- **Round 6 of the same review** found the "Anti-Laziness Guidance for CLAUDE.md" section of `CLAUDE_CODE_SDLC_WIZARD.md` still told users to rely on `effort: max` "via SDLC skill frontmatter" — including a copy-paste CLAUDE.md snippet literally asserting "This project uses effort: max via SDLC skill frontmatter" — even though that frontmatter field was removed back in round 2, and this whole release's premise is that effort is model-aware, not blanket `max`. Rewrote the section's intro, snippet, and closing explanation to point at the actual current mechanism: per-session `/effort` matched to the active model (`AI_SETUP_LANES.md`), backstopped by `hooks/model-effort-check.sh`'s SessionStart nudge. Repo-wide grep confirmed no other `effort: max`/"SDLC skill frontmatter" references survive anywhere in the release diff.
- **Round 7 of the same review** found 3 more real inconsistencies missed by prior sweeps: `CLAUDE_CODE_SDLC_WIZARD.md`'s Cache Poisoning "Detection signal" note and `SDLC.md`'s Effort warning callout still said the hook loud-warns below `xhigh`/`max` — stale after round 5 made `high` a silent floor too, and directly contradicting SDLC.md's own Recommended Effort table 2 lines above it. Both corrected to reference the model's actual floor. Separately, `CLAUDE_CODE_SDLC_WIZARD.md`'s "1M vs 200K" opt-in rationale and `skills/update/SKILL.md`'s Step 7.5 migration prompt both claimed `opus[1m]` "guarantees Opus 4.6 max" — but that alias auto-resolves to whichever Opus Claude Code currently considers latest (now Opus 4.8, not 4.6), directly conflicting with Setup B's explicit `claude-opus-4-6` pin (which exists specifically to avoid that ambiguity). Both reworded to clarify the alias isn't guaranteed to mean 4.6 and to point users who want 4.6 specifically at the explicit pin. Also fixed 3 stale implementation details in the wizard doc's MCP-vs-bash hook audit table for `model-effort-check.sh` (wrong env var name, a nonexistent 3-tier silent/soft/loud description, stale line count) — left as a separate, out-of-scope note: the same table has similarly stale line counts for 4 other hooks that predate this release entirely.
- **Round 8** found the most impactful documentation bug in this whole review: `CLAUDE_CODE_SDLC_WIZARD.md`'s "Step 5: Create the TDD Hook" is a literal, mandatory-reading template — `skills/setup/SKILL.md` instructs Claude to read this file first because "it contains all templates... you CANNOT do this setup correctly without reading it first" — and that template was still the OLD advisory-only hook with no `exit 2`, even though the actual `hooks/tdd-pretool-check.sh` (fixed by #436, the headline fix of this very release) now blocks. Anyone running `/setup-wizard` manually (as opposed to `npx agentic-sdlc-wizard init`, which correctly copies the real file per `cli/init.js`) would have generated a broken, non-blocking TDD hook, missing #436's fix entirely. Fixed: added a minimal but real `exit 2` gate to the tutorial code block, with a note pointing at the actual shipped hook for the production-hardened (session-scoped) version. Also fixed the same false "does not block" claim in the MCP-vs-bash hook-audit table's `tdd-pretool-check.sh` row, and softened an "all 5 wizard hooks" framing that implied completeness when the project now registers 9.
- **Round 9** found the manual tutorial path was still worse than round 8's fix addressed: (a) that very fix had reintroduced the `#436`-round-1 relative-path bug into the tutorial's `src/` pattern (matched `*"/src/"* ` only, no `"src/"*` clause) — fixed, and now locked in by a dedicated regression check; (b) Step 4's light-hook auto-invoke line and Step 6's SDLC skill description omitted `release/publish/deploy` coverage present in the real shipped `hooks/sdlc-prompt-check.sh` and `skills/sdlc/SKILL.md` — added, matching the real files exactly; (c) the manual walkthrough only ever templates 2 of the wizard's 9 production hooks, with no path to the other 7 (`codex-gate-check.sh` among them — this release's own headline fix). Rather than hand-writing 7 more tutorials that would just recreate the same drift class, Step 5 now explicitly marks itself illustrative-only and points at `npx agentic-sdlc-wizard@latest init` for the complete, always-in-sync set; `skills/setup/SKILL.md`'s Step 10 gained a guardrail (fewer than 9 files in `.claude/hooks/` → tell the user to run the CLI install first, not hand-type the rest). New test `tests/test-wizard-doc-hook-templates.sh` mechanically checks every doc-templated hook against its real file for `exit 2` parity and specifically guards the relative-path regression — the shipped version of the post-mortem commitment already recorded in `SDLC.md`'s Lessons Learned; TDD-verified RED (failed against the pre-round-8 doc and against the round-9-buggy doc) before GREEN.
- **Round 10** found the new test itself wasn't wired up: `tests/test-workflow-triggers.sh`'s orphaned-script check failed because `test-wizard-doc-hook-templates.sh` was never added to `.github/workflows/ci.yml`, meaning it would pass locally but never actually run in CI. Added the missing step, which then surfaced a second, cascading gap the same check independently catches: `CONTRIBUTING.md`'s test-script list (used as the "how to run tests locally" reference) was now missing the same file relative to `ci.yml`. Added it there too. Full sweep re-run clean, including `test-workflow-triggers.sh` itself (169/169, up from 168 — the orphan check now has one more script to track).
- **Round 11: CERTIFIED** (11 rounds total). Codex verified round 10's CI-wiring fix and found nothing new. Actual CI on the opened PR then caught three things the local sweep and 11 rounds of review both missed: (1) `skills/update/SKILL.md`'s round-4 driver-aware rewrite of Step 7.9 had silently dropped a distinct, pre-existing warning — that CC ignores an `effortLevel: "max"` set only in `settings.json` (not the env var) since it's session-only and doesn't persist — while restructuring around Opus-4.6-vs-Sonnet-5/Opus-4.8 driver awareness; `tests/test-model-config-batch.sh`'s `test_update_effort_step_warns_settings_only_max` caught the regression. Fixed by merging both concerns back into the Opus 4.6 branch of Step 7.9. (2) `.github/workflows/release-dry-run.yml`'s path-assertion step asserted on `.files[]?.path` at the JSON top level, but a newer npm CLI (11.16.0) wraps `npm publish --dry-run --json` output under the package-name key — pre-existing drift unrelated to this branch's content (confirmed: not part of this PR's diff, and main's last green run predates the npm version bump), but blocking regardless. Fixed the jq path to `.[] | .files[]?.path`, which doesn't need to hardcode the package name. (3) `tests/test-wizard-doc-hook-templates.sh` (new in round 9) was committed without the executable bit — `bash tests/foo.sh` doesn't need it, but `ci.yml` invokes it as `./tests/foo.sh`, which does; CI failed with "Permission denied", exit 126. Fixed with `chmod +x`, plus a new `test_all_test_scripts_executable` check in `tests/test-workflow-triggers.sh` (170/170, up from 169) so any future test script missing the bit fails locally, not just in CI. All three verified locally before pushing; full sweep re-run clean.

### Added
- New `Stop` hook (`codex-review-stop-check.sh`) — non-blocking backstop for sessions that end with significant uncommitted changes and no REVIEWED/CERTIFIED cross-model review artifact, closing the gap where `codex-gate-check.sh` (which only fires on `git commit`) never gets a chance to trigger because a session simply never attempts a commit.
- **AI Setup Lanes v3**: `AI_SETUP_LANES.md` rewritten to a 4-lane structure (Sonnet 5 `high`→`xhigh` + Fable recommended, Opus 4.6 max for proven stability, opusplan, Lite) reflecting Sonnet 5's June 30 launch. `model-effort-check.sh` now recommends effort per model instead of a blanket `max`.
- **Cowork section** added to `CLAUDE_CODE_SDLC_WIZARD.md` — the `cowork/` plugin (prompt-based hooks for Claude Cowork, shipped in a prior release) had zero cross-reference from the main wizard doc until now.

### Why
Maintainer pain event (2026-07-04): "I hate having to remind 'don't forget to cross-model review with codex.'" Root-cause audit found the enforcement mechanisms this wizard exists to provide were mechanically non-functional — hooks that looked right but never blocked anything. Fixed via TDD with 188 hook tests (up from 185), all verified against actual exit codes, not just warning text. Separately, a real Sonnet 5 migration incident (blanket `CLAUDE_CODE_EFFORT_LEVEL=max` silently overriding `/effort xhigh` after a model switch) exposed that the wizard's own docs still recommended the exact env-var pattern that caused it — fixed at the source instead of just noting the gotcha.

## [1.83.0] - 2026-06-11

### Fixed
- **#403**: Hook lists multiple wizard-blessed models (claude-opus-4-6, opusplan, fable) instead of hardcoded single-model nudge
- **#391**: Setup Step 9.5 detects global `[1m]` model pin and warns about billing implications
- **#405**: Update Step 3 uses `min(npm, CHANGELOG)` as "latest installable" — prevents version race during publish window
- **#384**: Update Step 7.9 checks effort configuration regardless of version match

### Why
Model config batch — first trial of the confidence ramp pattern (Opus research → Fable batch review → 95% → TDD → Codex safety check). All 4 issues reached 95% confidence before implementation.

## [1.82.0] - 2026-06-11

### Added

- **"Reading Usage Signals" subsection** in Token Efficiency section. Maps community-observed session signals (subagent-heavy, >150K context, 8+ hour sessions) to SDLC actions per setup lane. Marked as community-observed, not official CC docs.

- **Advisor fallback procedure** in AI_SETUP_LANES.md. Escalation ladder: restart session → Fable driver fallback → `-p` last resort (with billing caveat). Documented after advisor was unavailable for a full session during API incident (2026-06-11).

- **Fable effort guidance** in Setup A description. Opus stays at `max`; Fable at `high` (exceeds prior models at `max`). Unset `CLAUDE_CODE_EFFORT_LEVEL` env var if switching driver to Fable temporarily.

- **Autocompact Thresholds cross-reference** in AI_SETUP_LANES.md. Numbers-free pointer to wizard doc to prevent dual-source drift.

### Fixed

- **Stale `/usage` row** in Monitor Costs table. Was "Session total: USD, API time, code changes" — now accurately describes plan usage limits and per-category breakdown (skill, subagent, plugin, MCP server). Added `/status` row (settings panel) to prevent future confusion.

- **`/usage` mention in SKILL.md** Context Management section. Folded into existing auto-compact bullet within 20K char budget.

### Why

- Token-burn spike (1.36M costly tokens vs ~86K median) in session 98d6c7b0 surfaced that the wizard's usage guidance was stale and didn't help diagnose the cause. The Monitor Costs table described `/usage` incorrectly, and no wizard prose mapped usage signals to SDLC actions. The advisor fallback procedure is a direct lesson from the same session where the Fable advisor was unavailable for the entire duration.

## [1.81.0] - 2026-06-10

### Changed

- **Native `advisorModel` support (CC v2.1.170+).** Setup A (Premium) now uses `advisorModel: "fable"` in project settings instead of manual `Agent(model: "fable")` subagent spawning. Fable 5 auto-consults at key decision points (architecture, complexity, blast-radius). Setup B (Saver) gains `advisorModel: "claude-opus-4-6"` — Opus advisor compensates for Sonnet driver's lighter reasoning.

- **Settings are project-level by default.** The setup skill writes `model` + `advisorModel` to `.claude/settings.json` (project-scoped, committed, shared with team). After writing, asks if user also wants `advisorModel` in global `~/.claude/settings.json`. Never nukes global settings without consent.

- **Update skill gains Step 7.8 (advisorModel migration).** Detects projects with a model pin but no `advisorModel` and suggests the right advisor pairing. Version-gated to CC v2.1.170+.

- **CLI init.js smart-merge handles `advisorModel`.** Same pattern as `model` — only set if missing, preserve on `--force`.

- **This repo dogfoods Setup A.** Project settings now include `model: "claude-opus-4-6"` + `advisorModel: "fable"`.

- **Documented `! claude update` tip** for users needing v2.1.170+ — the `!` prefix runs shell commands inside a CC session without exiting.

### Why

- The advisor tool (API beta `advisor-tool-2026-03-01`) graduated to native CC support as `advisorModel` in v2.1.170+. Native advisor is strictly better than manual subagent spawning: automatic consultation at key decision points, no headless billing risk, persists across sessions via settings.json, and integrates with CC's settings precedence (project > global).

- Project-level settings prevent the wizard from overwriting a multi-project user's global model config. Settings precedence: Managed > CLI flags > Local > Project > User (global). Writing project-level means each repo picks its own lane independently.

## [1.80.0] - 2026-06-09

### Changed

- **Flipped default recommended model: Opus 4.8 → Opus 4.6 max.** v1.79.0 added Opus 4.6 max as opt-in Stability tier; v1.80.0 graduates it to the wizard's recommended flagship default. Setup wizard's `[f] Flagship full` choice now writes `model: "claude-opus-4-6[1m]"` (was `"opus[1m]"` → 4.8). All wizard prose flipped accordingly: SDLC.md Recommended Model row, CLAUDE_CODE_SDLC_WIZARD.md effort warning + Strict Effort behavior section + mixed-mode reviewer references, skills/sdlc/SKILL.md model section + cross-model reviewer line, skills/setup/SKILL.md choice list, hooks/model-effort-check.sh RECOMMENDED_MODEL + warning text, cli/lib/repo-complexity.js tier comments, README.md "Choosing Your Model" section reframed as a 6-source argument for why 4.6 max beats 4.8 in production SDLC workflows.

- **Added `[l] Latest` tier as opt-in for Opus 4.8.** Replaces v1.79.0's `[s] Stability` choice (which is now the default — graduated, not removed). Latest tier ships SWE-Bench Pro / Terminal-Bench 2.1 / dynamic-workflows / parallel-subagent-swarm features 4.6 doesn't have. Documents the tradeoffs explicitly: 40-60× cache token jump at HIGH effort ([AI Weekly](https://aiweekly.co/alerts/claude-opus-48-thinking-burns-900k-tokens-per-turn)), `max` is worse than `xhigh` on 4.8 ([Andon Labs Vending-Bench](https://andonlabs.com/blog/opus-4-8-vending-bench)), active GitHub regressions still open. Recommended effort for 4.8 is `xhigh`, not `max`.

- **Setup wizard choice list updated** from `[N/m/f/s]` to `[N/m/f/l]`. The Stability tier graduates into Flagship; Latest replaces Stability as the new optional opposite-direction choice.

### Why

- Six independent sources converged in the 12 days since 4.8 launched (2026-05-28) on the same conclusion: **4.6 is the only Opus where `max` effort tolerates without overthinking, and 4.7/4.8's tokenizer + agentic improvements come with structural token-burn tradeoffs that hurt long-running SDLC workflows.** Sources: Andon Labs Vending-Bench arena (4.8 finished last; "Max reasoning is not the best reasoning effort"), AI Weekly (40-60× cache token jump at HIGH effort; up to 900K tokens per turn), [Tech.yahoo review](https://tech.yahoo.com/ai/claude/articles/claude-opus-4-8-review-130106963.html) ("Anthropic deliberately made Opus's new tokenizer less efficient"), [Paweł Huryn's 4.7 guide](https://www.productcompass.pm/p/claude-opus-4-7-guide) ("most complaints about 4.7 feeling slow stem from people reflexively using max"), [BSWEN effort decision guide](https://docs.bswen.com/blog/2026-04-19-claude-code-effort-level-decision-guide/) ("Max on Opus causes overthinking"), r/Claudeopus field reports including one maintainer's literal A/B ("12 hours with 4.8 zero deliverables; plugged in 4.6, spec written + 133 tests green in one session").

- Active GitHub regressions documented against 4.8 in Claude Code: false-greens ([#63861](https://github.com/anthropics/claude-code/issues/63861)), 2-3× token burn ([#64961](https://github.com/anthropics/claude-code/issues/64961)), 46K tokens for simple coding turn ([#64153](https://github.com/anthropics/claude-code/issues/64153)), dropped constraints during execution ([#65932](https://github.com/anthropics/claude-code/issues/65932)), fabricated identifiers in parallel batches.

- 4.6 is Anthropic-supported until ≥ Feb 5, 2027 per the [official deprecation page](https://platform.claude.com/docs/en/about-claude/model-deprecations) — 8 months minimum runway. The Feb-Apr 2026 quality bugs that triggered the original "is 4.6 nerfed" wave are fully fixed per Anthropic's [April 23 postmortem](https://www.anthropic.com/engineering/april-23-postmortem); the wizard's default picks up the post-fix model.

- Aligns the wizard with the [AI Setup Lanes](AI_SETUP_LANES.md) doc shipped in v1.79.0, which already named Opus 4.6 max as "Claude Premium" for both planner and driver in Setup A. The wizard's default flagship recommendation now matches.

### Notes

- **This is an explicit bet against the "newest = best" convention.** Anthropic recommends Opus 4.8 as their flagship; the wizard recommends Opus 4.6 max instead. Documented in README.md "Choosing Your Model" with the full six-source argument so users can evaluate the bet themselves and pick `[l] Latest` if they want Anthropic's official flagship.

- **No breaking changes to consumer-repo installs.** `settings.json` template still ships unpinned (auto-mode default unchanged). The flip is at the *setup wizard's recommendation step* — users running `setup-wizard` get the new `[f] Flagship full` choice writing 4.6 max instead of 4.8. Users who already opted into v1.78.0/v1.79.0 flagship and want to stay current can re-run setup or manually flip `claude-opus-4-8` → `claude-opus-4-6` in their `~/.claude/settings.json` env vars.

- **v1.79.0's Stability tier code stays in git history** but is now redundant — the Stability tier *was* "opt into Opus 4.6 max"; in v1.80.0 that's the default. No PR needed to remove the redundancy because the v1.80.0 prose subsumes it cleanly (Stability section content reframed as Latest tier opt-out instructions).

- **If 4.8 regressions materially improve** (Anthropic ships hotfixes for the token-burn issues, GitHub bug closures, second wave of positive field reports), the default can flip back via a single PR. The CHANGELOG entry above names the specific signals to watch.

## [1.79.0] - 2026-06-08

### Added

- **Opus 4.6 Stability tier** as a fourth setup-wizard model choice ([s] Stability, alongside [N] No pin / [m] Mixed-mode / [f] Flagship). Pins `model: "claude-opus-4-6[1m]"` with `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=30`. Pairs with `max` effort. Community signal converges on 4.6 being the only Opus version `max` tolerates without overthinking — Andon Labs Vending-Bench arena (4.8 finished last, "Max reasoning is not the best reasoning effort"), Paweł Huryn's 4.7 guide ("most complaints about 4.7 feeling slow stem from people reflexively using max"), BSWEN effort decision guide ("Max on Opus causes overthinking"), r/Claudeopus field reports (one maintainer: "12 hours with 4.8 zero deliverables; plugged in 4.6, spec written + 133 tests green in one session"; another commenter: "4.6 had the best overall balance at max"). New section "Stability tier — Opus 4.6 at max effort" in `CLAUDE_CODE_SDLC_WIZARD.md` documents when to pick it (production 4.7/4.8 regression escape — false-greens GH #63861, 2-3× token burn #64961, dropped constraints #65932, fabricated identifiers; context-heavy work where 4.6 scored 94.7% NYT Connections vs 4.7's 41%; original tokenizer avoids the 4.7+ 12-18% English token tax) and tradeoffs (misses 4.8's SWE-Bench Pro / Terminal-Bench / dynamic-workflows gains). Anthropic-supported until ≥ Feb 5, 2027 (8 months minimum runway per [Anthropic deprecation page](https://platform.claude.com/docs/en/about-claude/model-deprecations)). Wizard default remains flagship Opus 4.8 — Stability is opt-in, not a recommendation swap. Setup skill updated with `[s] Stability` choice + handler; settings.json snippet provided for both global (env-var sweep across all projects via `ANTHROPIC_DEFAULT_OPUS_MODEL=claude-opus-4-6`) and project-scoped pin patterns.

### Notes

- **4.6's Feb-Apr 2026 quality bugs are fully fixed per [Anthropic's April 23 postmortem](https://www.anthropic.com/engineering/april-23-postmortem).** The three bugs (effort default high→medium Mar 4-Apr 7; cache-clear-every-turn Mar 26-Apr 10; verbosity-limit prompt Apr 16-Apr 20) are resolved. The Stability tier picks up the post-fix model, not the regression window. Anthropic reset usage limits as compensation Apr 23.
- **Wizard default unchanged.** v1.78.0's flagship recommendation of Opus 4.8 stays. The Stability tier is an additive sibling for maintainers who've hit 4.7/4.8 regressions in production — surfaced as a choice in the setup wizard, not flipped as the default. If the community-validated A/B of 4.6 max vs 4.7/4.8 max materializes as a sustained pattern across maintainers, a future release may revisit the default.
- **Validation pending.** This release ships the tier so maintainers can opt in across their own repos and run the comparison. Real-world signal from extended use (token spend deltas, context-fidelity wins, false-green regressions caught) feeds back into a v1.80.0 calibration if warranted.

## [1.78.0] - 2026-06-02

### Changed

- **Bumped recommended model from Opus 4.7 → Opus 4.8** (closes #365). Opus 4.8 launched 2026-05-28; day 5 in-the-wild sentiment settled positive, proof-of-life via `claude --print --model claude-opus-4-8` confirmed reachability, and the `opus[1m]` alias auto-resolves to latest Opus on CC v2.1.154+ (no settings.json template change needed — alias does the work). Updated prose across `SDLC.md` (Recommended Model row + effort warning), `CLAUDE_CODE_SDLC_WIZARD.md` (~11 mentions in effort table + autocompact + mixed-mode tier + 1M-context section), `skills/sdlc/SKILL.md`, `skills/setup/SKILL.md` (mixed-mode + flagship tier suggestions), `skills/update/SKILL.md`, `hooks/model-effort-check.sh` (warning text), and `cli/lib/repo-complexity.js` (tier comments). Min CC bumped v2.1.111+ → v2.1.154+ (required to resolve `opus[1m]` to 4.8). Effort semantics preserved — strict effort behavior introduced in 4.7 carried forward to 4.8, so `max` remains the recommended default and `xhigh` the floor.

### Notes

- **Un-run gates 2+3 tracked as post-deploy follow-up obligations on #365.** Gate 2 (A/B coder quality vs 4.7 on real PRs) and Gate 3 (dogfood for 24h before bump) were both deferred. If real-world use surfaces the system-card-flagged regressions for 4.8 — prompt-injection +60% on Gray Swan, file-deletion tendency, or eval-awareness affecting wizard output — revert via a single PR that flips the 4.7↔4.8 prose. Settings.json template unchanged means revert is prose-only.

## [1.77.0] - 2026-05-24

### Added

- **`release-dry-run.yml` CI workflow** (A1, v1.75.1 post-mortem). Runs `npm publish --dry-run --tag dry-run --json` on every PR touching `release.yml`, `package.json`, or the shipped package surface (`cli/`, `hooks/`, `skills/`, `.claude-plugin/`, `CLAUDE_CODE_SDLC_WIZARD.md`, `CHANGELOG.md`). Catches MODULE_NOT_FOUND-class regressions, dropped shipped paths, Node/npm version drift — visible at PR-time instead of producing a half-published tag. Uses `permissions: contents: read` only (no `id-token: write` — npm CLI runs OIDC setup before the dry-run branch, so requesting that permission would attempt token mint on every PR). Rewrites `package.json` to `0.0.0-dry-run-<SHA>` in a temp checkout to avoid the "cannot publish over previously published versions" error. Path filter is `package.json.files`-aware and tested for drift. 25 quality tests in `tests/test-release-dry-run-workflow.sh`.
- **`cc-version-drift.yml` cadence workflow** (closes #350). The fix for the gap that let native `/goal` (CC v2.1.139) slip past for 32 versions / 5 weeks. Pure GH-API detector — no LLM, no API spend. Mon 09:30 UTC cron (staggered from `weekly-update.yml` 09:00 and `weekly-api-update.yml` 10:00) + `workflow_dispatch`. Parses new `<!-- Claude Code Baseline: vX.Y.Z -->` anchor in `SDLC.md` (single-purpose; NOT `<!-- SDLC Wizard Version -->` which is the wizard's own pkg version), compares to `npm view @anthropic-ai/claude-code version`, opens a tracking issue when patch gap > 5 (major/minor jumps alert regardless of threshold). Idempotent via label `cc-version-drift` + machine-readable marker in issue body. Edits existing open issue instead of comment-spamming. Re-opens a closed issue only if delta WIDENED (respects "won't fix for now"). 22 workflow tests + 18 unit tests on the extracted `scripts/cc-drift-check.sh` (bash 3 compatible, strict SemVer validation, refuses prereleases and regressions).
- **`/goal` SDLC-discipline gates in `/sdlc` skill** (PR-D). Two new load-bearing rules now that native `/goal` is universal across CC (v2.1.139+) and Codex CLI: **(1) Confidence gate — NEVER invoke `/goal` below HIGH 95%** (mirrors existing Confidence Check; below 95% the Haiku evaluator rubber-stamps "did the agent flail" as progress). **(2) DLC binding — the condition MUST name the active DLC** (`/sdlc`, `/gdlc`, `/ldlc`, etc.) so the evaluator anchors on "doing it right," not just "doing it." Example: `/goal "tests pass + clean tree following /sdlc, stop after 20 turns"`. `test_sdlc_skill_has_goal_wrapper` extended to grep both new keywords (9 quality elements total).
- **`<!-- Claude Code Baseline: v2.1.150 -->` anchor in `SDLC.md`** — single-purpose machine-parseable source of truth for `cc-version-drift.yml`. Maintainer updates this anchor + the human-readable `Claude Code Recommended` row when bumping CC support. Test asserts both stay in sync.

### Notes

- **Trusted Publishing flow held.** Third release shipped via OIDC since the v1.75.0 migration; no token to rotate, expire, or 2FA-gate.
- **Cross-model design reviews** at `.reviews/176-followup-prio-codex.md` (Codex gpt-5.5 xhigh). Caught: (a) naive `npm publish --dry-run` against already-published version fails today; (b) `id-token: write` on the dry-run workflow would attempt OIDC mint on every PR; (c) `weekly-update.yml` is the wrong host for #350 (cron is disabled + tests assert no `issues: write`); (d) "minor versions" is wrong terminology — `2.1.150 → 2.1.180` is a SemVer patch delta.
- **Self-test landed in PR-B:** the new `release-dry-run.yml` workflow ran ON the PR that introduced it (paths filter included `release-dry-run.yml` itself) and SUCCEEDED — first proof that the dry-run mechanism works end-to-end against the temp-version-rewrite + `--tag dry-run` flow.

## [1.76.0] - 2026-05-24

### Added

- **Native `/goal` wrapper in `/sdlc` skill** (closes #347). CC v2.1.139 shipped a native `/goal <condition>` command — set a completion condition, Haiku evaluator re-checks the transcript per turn until met. The /sdlc skill now carries a tight wrapper section with 5 load-bearing elements: pre-flight checklist (workspace trusted, hooks not disabled, CC ≥ v2.1.143 for the subagent-race fix), condition-as-SDLC-contract guidance (measurable end state + check + constraints + hard turn/time bound since there's no native cap), compose-with-hooks note (UserPromptSubmit/SessionStart/PreCompact fire normally per turn), `--resume` resets counters caveat, and the off-transcript anti-pattern callout (the evaluator cannot call tools, so `/goal "production is healthy"` is wrong — it can only judge what's in the conversation). New quality test `test_sdlc_skill_has_goal_wrapper` greps for each element by keyword. Per Prove-It Gate absorption principle: extends the existing /sdlc skill, no new skill/hook/template scaffolding.
- **CC v2.1.119 → v2.1.150 feature adoption** in `CLAUDE_CODE_SDLC_WIZARD.md` "Complementary native skills" table: `/code-review [effort] [--comment]` (v2.1.147+, renamed from `/simplify`, posts findings as inline GH PR comments), `/usage` per-category breakdown of limits usage (v2.1.149+ — skills, subagents, plugins, MCP-server costs), `/context all` per-skill per-model token estimates (v2.1.139+). Each row carries usage guidance with the same caveat discipline applied to `/insights` (#235a).
- **`Claude Code Recommended` baseline guidance** in `SDLC.md` — new row at `v2.1.150+` alongside the unchanged `Claude Code Minimum` floor at `v2.1.111+`. Splits "what we require" from "what unlocks the latest features" without breaking back-compat for consumers still on the minimum.

### Changed

- **ROADMAP cleanup with demand-signal-first entry gate** (PR #349). New top-of-ROADMAP gate: new entries require one of a maintainer pain event with repro, a second external user signal, a dated platform deadline, or a low-cost cleanup. Everything else goes to a Research Parking Lot with 30/60-day expiry — if the trigger hasn't fired by expiry, the item is deleted rather than carried forward. Excised 4 items now tracked in sibling repos (#9 OpenCode → `BaseInfinity/opencode-sdlc-wizard`, #82 Domain DLCs → Stefan's separate track, #91 Multi-Agent Adapter umbrella → per-adapter sibling repos, Back Burner Agent-agnostic SDLC). Killed 4 stale items with no demand signal (#85 Phase 2 — 1.7 months stale, killed by #231 zero-cron philosophy; #233 automation subitems — 1 month stale, Max-user footgun; Back Burner Chaos/Resilience Testing — 1.8 months, no concrete failure; Back Burner Subagent Model Compliance Audit — 3+ months, prototype already deleted in #236). Source: cross-model prioritization at `.reviews/roadmap-prio-codex.md`.
- **#347 corrected from "no native primitive" to "native `/goal` exists, build the wrapper"**. The original 2026-05-23 research (claude-code-guide subagent) was wrong — CC v2.1.139 had shipped `/goal` weeks earlier. Implementation scope shrunk from a 5-step plan + GOAL.md/HANDOFF.md templates down to a ~30-line wrapper in the existing `/sdlc` skill (now shipped — see Added). Meta-lesson captured: require explicit citation of an authoritative source (docs index, raw changelog grep) before accepting a "feature does not exist" claim — negative claims are easier to fake than positive ones.

### Added (ROADMAP only — implementation deferred)

- **#302 — User-level setup-wizard + repo-local lifecycle split** (PR #346). Cross-model design review (Codex gpt-5.5 xhigh) scored Claude's first-pass 5/10 NOT CERTIFIED and replaced it with a concrete channel contract: plugin = user-level/global, npm/npx = repo-local, no npm `postinstall` writing to `~/.claude/`. Implementation deferred per demand-signal-first gate.
- **#350 — CC feature-discovery cadence fix** (PR #350). Captures the process gap that let `/goal` slip past for ~5 weeks: #231 Phase 3d gutted the in-CI LLM-ranker to take `weekly-update.yml` to $0, and the maintainer-run replacement on Max never ran. Proposed fix: a thin GH-API-only check that opens a "CC version drift" issue when our `<!-- SDLC Wizard Version -->` baseline is >5 minor versions behind latest npm. No LLM, no API spend.

### Notes

- **Trusted Publishing flow is stable.** Second release shipped via OIDC since the v1.75.0 migration; no token to rotate, expire, mis-scope, or 2FA-gate.
- **Inventory of all 32 missed CC versions** (v2.1.119 → v2.1.150) lives at `.reviews/cc-feature-inventory-2026-05-24.md` (gitignored) with HIGH/MEDIUM/LOW relevance triage and the adoption sequence for follow-up PRs. After verifying against CC's hook docs, H2 (`$CLAUDE_EFFORT` env var) and H8 (Stop hook `background_tasks`) were demoted to non-applicable: `$CLAUDE_EFFORT` is only available in tool-use-context hooks (not our SessionStart-typed `model-effort-check.sh`), and `background_tasks` is only in Stop/SubagentStop input (not our PreCompact-typed `precompact-seam-check.sh`). The existing hook code is correct as-written.

## [1.75.1] - 2026-05-20

### Fixed

- **`release.yml` npm-upgrade step failed during v1.75.0 publish.** The `npm install -g npm@latest` step hit `npm error code MODULE_NOT_FOUND` / `Cannot find module 'promise-retry'` on the GitHub-hosted runner — a documented npm CLI bug where the in-place self-upgrade corrupts its own module tree mid-install. Bumped `actions/setup-node@v5` to `node-version: 24` (ships npm 11.x natively), dropped the unreliable `npm install -g` step entirely, and added an explicit `npm --version` fail-loud guard that aborts the publish if Node ever ships an npm older than 11.5.1. v1.75.0 is a tagged-but-unpublished version on GitHub; v1.75.1 supersedes it as the first version actually shipped via Trusted Publishing.

### Process post-mortem (for /sdlc Lessons Learned)

Two process gaps shipped this minor release:

1. **CI doesn't exercise `release.yml`.** `tests/test-release-workflow.sh` greps the workflow YAML but no test actually executes the npm-upgrade step on a runner. The MODULE_NOT_FOUND bug is invisible to unit tests. Future-proofing options: (a) add a `release-dry-run` job in CI that runs the publish steps with `--dry-run` against a throwaway scope, (b) accept that some failures are only visible at deploy time and document a fast rollback path. Tracked as a roadmap follow-up.
2. **`tag-then-publish` has a feedback gap.** v1.75.0 was tagged before the npm publish succeeded, leaving an inconsistent state where the git tag and the npm registry disagree (no GitHub Release page was ever created — that step was skipped after the publish failed). Mitigation already in place: tag verification (`git merge-base --is-ancestor` + `tag-vs-package.json` match), but neither catches "tag pushed, publish failed." Roadmap follow-up: gate the GitHub Release creation step on `npm publish` success (workflow already does this via step ordering), but also surface an explicit "PUBLISH FAILED — DO NOT TAG NEXT VERSION FROM THIS BASE" notice in the failed run.

Both items added to ROADMAP as v1.76.0+ candidates. Neither blocked v1.75.1 shipping.

### Test

- `tests/test-release-workflow.sh::test_upgrades_npm_for_trusted_publishing` rewritten to accept either strategy: (a) Node ≥24 + explicit `npm --version` guard, or (b) explicit `npm install -g npm@…` step before publish. The new strategy (a) is what 1.75.1 uses; the test still catches a future revert to either no-guard Node 24 (which could silently downgrade) or back to the unreliable in-place upgrade.

## [1.75.0] - 2026-05-20

### Changed

- **`release.yml` migrated to npm Trusted Publishing (OIDC).** Long-lived `NPM_TOKEN` retired in favor of per-publish OIDC auth via GitHub Actions (`id-token: write` was already set for SLSA provenance). The `NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}` env was removed, the `--provenance` flag was dropped (trusted publish auto-generates provenance), and a new step upgrades npm CLI to ≥ 11.5.1 (Node 22's bundled npm 10.9.x lacks Trusted Publishing support, which would silently fall back to token mode and re-introduce this failure class). Triggered by v1.74.0 publish failing with `404 Not Found - PUT` (revoked/expired token), then `EOTP` (token missing 2FA bypass). With Trusted Publishing there is no token to rotate, expire, mis-scope, or 2FA-gate — the workflow authenticates as itself against the registry via OIDC every time.

### Required one-time setup (after merging this PR, before tagging v1.75.0)

Maintainer must configure the publisher on the npm package page:

1. https://www.npmjs.com/package/agentic-sdlc-wizard → **Settings**
2. **Publishing access** → **GitHub Actions**
3. Repository owner: `BaseInfinity`, repository name: `claude-sdlc-wizard`, workflow filename: `release.yml`, environment: (leave blank)
4. **Save**

After that, `git tag v1.75.0 && git push origin v1.75.0` publishes via OIDC with zero token interaction.

### Removed

- `NPM_TOKEN` GitHub secret is no longer used. After verifying v1.75.0 ships cleanly, the maintainer can revoke the granular access token on npmjs.com and delete the GH secret — both are dead weight.

### Tests

- `tests/test-release-workflow.sh::test_uses_trusted_publishing_not_token` — fails if `NODE_AUTH_TOKEN:` reappears in `release.yml` env (i.e., a revert to token-based publishing). Replaces the prior `test_references_npm_token` which asserted NPM_TOKEN's presence (now backwards).
- `tests/test-release-workflow.sh::test_upgrades_npm_for_trusted_publishing` — fails if the `npm install -g npm@latest` (or pinned `>=11.5.1`) step is missing. Without the CLI upgrade, publishes silently fall back to token mode and reproduce the v1.74.0 EOTP failure.
- All 15 release-workflow tests green.

### Why this happened now (one-paragraph post-mortem)

The 2026-05-21 v1.74.0 release was the first wizard release after the `NPM_TOKEN` secret aged past npm's automation token TTL. The token had successfully shipped v1.69.0 → v1.73.0 over the prior 2 weeks, then silently expired between v1.73.0 (2026-05-06) and v1.74.0 (2026-05-20). Symptom 1: `404 Not Found - PUT registry.npmjs.org/agentic-sdlc-wizard` — npm returns 404 (not 401) when a token doesn't recognize itself as a package maintainer, which makes the failure look like a missing package. Symptom 2 after rotation: `EOTP — This operation requires a one-time password from your authenticator` — the new granular token was created without the "Bypass two-factor authentication (2FA)" checkbox set, which npm requires for CI tokens. Both symptoms are eliminated by Trusted Publishing: no token, no expiry, no 2FA mode mismatch, and short-lived OIDC credentials are minted fresh per publish so revocation is automatic. Pattern: every npm token in CI is a latent ticking bomb. This PR defuses it permanently.

## [1.74.0] - 2026-05-17

### Salvaged from closed v1.43.0-quick-wins branch (PR #340)

Long-running session built v1.43.0 quick-wins off `c1c6f31` (~May 12), unaware main had shipped through `v1.73.0`. PR #340 closed without merging; this release ships the items that are still genuinely missing on current main, with Codex+Claude joint triage (`.reviews/v143-salvage-triage.md`).

### Added

- **#338 SDLC-skill source-and-precedence preamble.** `skills/sdlc/SKILL.md` now opens with an explicit "Skill source & precedence" section: repo-local `.claude/skills/sdlc/SKILL.md` (symlinked to wizard's `skills/sdlc/SKILL.md`) wins over global `~/.claude/skills/sdlc/SKILL.md`, with a `head -5` verification one-liner. Resolves user-reported confusion when both copies exist with the same name. Regression test `test_sdlc_skill_has_precedence_preamble` in `tests/test-doc-consistency.sh`.
- **#235(a) `/insights` complementary-tool guidance.** Setup skill Step 12 closing checklist + `CLAUDE_CODE_SDLC_WIZARD.md` "Complementary native skills" table now both cite `/insights` (native CC v2.1.101+) with an explicit qualitative-only caveat: it surfaces `underlying_goal` / `outcome` / `friction_counts` / `user_satisfaction_counts` / `brief_summary` from local session history, but does NOT expose `cache_read_input_tokens` / cache-hit ratio / per-turn breakdown / model-version tracking — so it is **not a substitute** for token-spike detection (ROADMAP #220 / `hooks/token-spike-check.sh`) which reads raw session JSONL. Two regression tests guard the doc-presence + caveat.
- **#235(b) `/insights` allowlist.** Appended `/insights` to `tests/e2e/known-slash-commands.txt` so the community feature-discovery scanner (#207) stops flagging it as a "new" candidate on every weekly run. `tests/test-community-scanner.sh::test_filters_insights_as_known` asserts the scanner now filters `/insights` from candidate output.

### Fixed

- **Codex stdin-hang doc fix.** All multi-line `codex exec` invocations in `README.md`, `CLAUDE_CODE_SDLC_WIZARD.md`, `skills/sdlc/SKILL.md` (and the new `scripts/codex-review-with-progress.sh` wrapper) now append `< /dev/null`. Without the redirect, codex from a non-interactive parent (background, hooks, CI, Claude Code Bash tool) blocks on stdin reads even when the prompt is passed as an argument — the process sits at S/0% CPU indefinitely with a 0-byte `-o` output file (file only written on completion, so a hang gives zero visibility). Validated on `codex-cli 0.130.0` / macOS 14, 2026-05-15, after two 30+ minute silent hangs. Repro: `codex exec -s read-only 'Reply A.' &` hangs forever; `codex exec -s read-only 'Reply A.' < /dev/null` returns in 8s. Two new tests: `test_codex_exec_blocks_redirect_stdin` in `tests/test-doc-consistency.sh` (asserts every multi-line block in user-facing docs has the redirect) and `test_wrapper_redirects_child_stdin_to_dev_null` in `tests/test-codex-progress-wrapper.sh` (asserts the wrapper redirects child stdin so heartbeats actually fire instead of hanging).
- **`tests/test-hooks.sh` env-isolation.** `test_instructions_hook_cwd_walkup` now scopes both `HOME=$tmpdir` and `SDLC_WIZARD_CACHE_DIR=$tmpdir/cache`. Without isolation, the user's `~/.cache/sdlc-wizard/latest-version` (e.g. a stale `1.73.0`) poisoned the staleness check and triggered the "30 releases behind" loud nudge against a fresh-version fixture, breaking the test's negative grep. Hit live during the v1.43 session; happens any time the cached latest doesn't match the SDLC.md version under test.

### Test counts (all green)

- `tests/test-doc-consistency.sh` — 39/0 (4 new tests: setup-insights, wizard-insights, sdlc-preamble, codex-stdin)
- `tests/test-community-scanner.sh` — 15/0 (1 new: filters-insights-as-known)
- `tests/test-codex-progress-wrapper.sh` — 12/0 (1 new: wrapper-redirects-child-stdin)
- `tests/test-hooks.sh` — 156/0 (env-isolation fix)

### Dropped from v1.43 branch (not salvaged — already-shipped or no-longer-applicable)

- #226 weekly-update.yml Tier 2 wording fix — code deleted in #231 Phase 3d (v1.54.0)
- #227 weekly-update.yml `cusum --add` → `--add-json` — same refactor removed the CUSUM steps
- #219 setup-skill CC 2.1.117 model-pin note — already verified on main (CHANGELOG.md:331); doc nuance dropped per Codex's "weak MAYBE → DROP"
- #337 `--yolo` audit — verification-only, no code to ship
- #339 5-entry API triage — triage-only, no code to ship

### Process

Two-step Codex cross-model review: (1) initial triage of branch vs main (`.reviews/v143-salvage-triage.md`) returned CERTIFIED 7/10 with corrected target-line numbers for every salvaged item, (2) closed PR #340 cleanly with explanation comment, rebuilt against current main with Codex's targets.

## [1.73.0] - 2026-05-06

### Fix: PreCompact hook no longer false-positives on stale `.git/REBASE_HEAD`

`hooks/precompact-seam-check.sh` was treating any presence of `.git/REBASE_HEAD` as "rebase in progress" and blocking manual `/compact`. But `REBASE_HEAD` is just a rebase-related ref (the stopped/replayed commit) that git can leave behind after a clean rebase finishes — the authoritative "rebase in progress" signal is the `rebase-merge/` or `rebase-apply/` directory (which is what `git status` keys on too). Hit live in this repo 2026-05-05 — yesterday's clean rebase left `REBASE_HEAD` behind, the user's manual `/compact` was blocked, and clearing it required `rm .git/REBASE_HEAD` by hand.

The OR-chain at line 227 now drops the `REBASE_HEAD` predicate; only the `rebase-{merge,apply}/` dir checks remain. Two new tests cover the fix:

- `test_precompact_silent_on_stale_rebase_head_alone` — positive: `rc=0` + empty stderr when only `REBASE_HEAD` exists
- `test_precompact_blocks_on_rebase_head_with_rebase_merge_dir` — negative control: still blocks on real in-flight rebase (REBASE_HEAD + rebase-merge dir together)

156/156 hook tests green. Codex round 1 CERTIFIED 9/10 (one P2 comment-accuracy nit caught — fixed: `REBASE_HEAD` is the stopped/replayed commit, not the original branch tip, which is `ORIG_HEAD`).

PR #330.

### GC: -460 LOC of stale review/plan artifacts (#236 bloat hunt)

`.reviews/` is gitignored, but 14 handoff/preflight/round-N review files for now-merged PRs were committed before that gitignore line landed. They held no ongoing reference value. `plans/CATCHUP.md` captured the v2.1.15 → v2.1.81 catch-up (March 2026) — historical context lives in CHANGELOG (v1.8.0 entry); the plan doc was dead weight.

Deleted (15 files):

- `.reviews/baseline-fires-once-001/{round-1,round-2}-review.md`
- `.reviews/skill-cross-model-trim-001/{round-1,round-2,round-3}-review.md`
- `.reviews/tdd-pretool-fires-once-001/{round-1,round-2}-review.md`
- `.reviews/preflight-{allowed-tools-permissions,baseline-fires-once,model-pin-opt-in,precompact-seam,skill-cross-model-trim,staleness-nudge,tdd-pretool-fires-once}-001.md`
- `plans/CATCHUP.md`

Kept (still load-bearing):

- `.reviews/research-95/97/99/206/235.md` (cited from ROADMAP rows)
- `.reviews/experiment-tracking.md` (asserted by `tests/test-workflow-triggers.sh:2189`)
- `plans/AUTO_SELF_UPDATE.md` (still annotated with #231 phase notes)

Hooks 156/156, cli 88/88, workflow 176/176, docs 35/35 — all green post-deletion.

PR #331.

---

## [1.72.0] - 2026-05-05

### Closes #323: `init --force` no longer silently overwrites CUSTOMIZED files

User report 2026-05-05 — `npx agentic-sdlc-wizard check` flags 6 files as CUSTOMIZED then recommends `init --force`, which silently clobbers all 6. Reporter: "the wizard correctly **detected** 6 CUSTOMIZED files and then **recommended a command that would overwrite all 6**." Fully closed in two parts:

#### Part 1 — customization-aware recommendation in `check` (PR #325)

When `check` finds CUSTOMIZED files alongside an available update, the suggested command now warns and points at `init --dry-run` first instead of silently recommending `init --force`. Pure function `buildUpdateRecommendation(updateInfo, customizedCount)` exported from `cli/init.js`. Backward compat: zero-customized recommendation byte-for-byte unchanged.

#### Part 2 — new `init --preserve-customized` flag (PR #328)

Composes existing `--force` semantics — when both flags are set:

- **CUSTOMIZED** files (sha256 mismatch with template) → action `PRESERVE`, skipped during write, reported in summary footer
- **MATCH** files → `OVERWRITE` (refresh; effectively no-op since hashes already match)
- **MISSING** files → `CREATE` (new files added in latest version still get installed)

Without `--force`, the flag is a no-op (all existing files SKIP regardless). Updated `check` recommendation now suggests `init --force --preserve-customized` as the "upgrade safely" path when CUSTOMIZED files exist.

#### Sample output

```
PRESERVE  .claude/hooks/sdlc-prompt-check.sh
PRESERVE  .claude/skills/sdlc/SKILL.md
OVERWRITE .claude/hooks/tdd-pretool-check.sh
CREATE    .claude/skills/feedback/SKILL.md

PRESERVED 2 customized file(s) — review with `init --dry-run` to see what differs from the latest template.
```

#### Test coverage

10 new tests in `tests/test-cli.sh` across 3 PRs (78 → 88 green): customization-aware recommendation (2 from #325), null/undefined edge cases (2 from #326 P2 follow-up), preserve-customized core behavior (3 from #328 round 1), no-force-no-op + settings.json MERGE precedence + WIZARD_DOC parity (3 from #328 round-2).

#### Deferred

Option 3 from #323 (real `update` subcommand with backup directory + per-file diff prompt) — options 1 + 2 close the immediate footgun without a new subcommand and backup-storage convention.

#### Files

- `cli/init.js` — `buildUpdateRecommendation()` exported; `--preserve-customized` threaded through `init()` → `planOperations()`; `isCustomized()` hash helper; `PRESERVE` action skipped in `executeOperations()`; `printOps()` adds yellow `PRESERVE` color + summary footer
- `cli/bin/sdlc-wizard.js` — `--preserve-customized` flag + help text
- `tests/test-cli.sh` — 10 new tests across 3 PRs (78 → 88 green)
- `package.json`, `.claude-plugin/plugin.json` + `marketplace.json`, `SDLC.md`, `skills/update/SKILL.md`, `CLAUDE_CODE_SDLC_WIZARD.md`, `CHANGELOG.md` (1.71.0 → 1.72.0)

## [1.71.0] - 2026-05-05

### Token-bloat fix: SDLC skill Cross-Model Review section trimmed

`skills/sdlc/SKILL.md` Cross-Model Review section condensed from ~70 lines to ~20 lines. Saves ~427 tokens per SDLC skill auto-invoke (4995 → 4568 tokens). The skill auto-loads on virtually every productive `implement/fix/refactor` task, so this is real per-session cost.

### What stayed in SKILL.md

- Decision-making: when to run / skip / prerequisites / flagship-tier reviewer rule (#233)
- 4-step protocol summary (preflight → handoff → reviewer → dialogue loop)
- Required handoff JSON keys + `pr_number` self-heal opt-in note (#209)
- Convergence rule (2 rounds sweet spot, 3 max)
- Release-review verification-checklist additions
- Sandbox flag for Codex from CC

### What moved to canonical wizard doc only

Full JSON example, full codex command example, anti-patterns, multi-reviewer (Claude+Codex+human) workflow, non-code-domain variants. All these live in `CLAUDE_CODE_SDLC_WIZARD.md` → "Cross-Model Review Loop" (194 lines, full canonical protocol). The trimmed SKILL.md ends with an explicit pointer to that section.

### Audit method

ROADMAP #236 phase 3. `scripts/audit-session-load.sh` ranked SKILL.md files at the top of the size table:
- `skills/sdlc/SKILL.md`: 4995 tokens (sat right at 5K threshold)
- `skills/update/SKILL.md`: 4931 tokens
- `skills/setup/SKILL.md`: 4490 tokens

SDLC skill auto-invokes most often (every implement/fix/refactor task), so it earned the cut. Verified 8 test suites that grep for SKILL.md content (mocking table, TDD prove, Memory Audit Protocol heading, opus[1m], autocompact compound, Deployment Tasks, plus `tests/test-self-update.sh` which asserts cross-model-review-specific content: `### Release Review Focus` heading, `Version parity` focus area, `"mission"`/`"success"`/`"failure"` JSON-quoted schema keys, "verification checklist" pattern, "preflight" mention). Codex round 1 caught 3 missed assertions in `test-self-update.sh`; round 2 fixes restored those constraints in tighter prose without re-bloating.

### Files

- `skills/sdlc/SKILL.md` — Cross-Model Review section trimmed
- `CHANGELOG.md`, `SDLC.md`, `skills/update/SKILL.md` (Latest:), `package.json`, `.claude-plugin/plugin.json` + `marketplace.json`, `CLAUDE_CODE_SDLC_WIZARD.md` (1.70.0 → 1.71.0)

### Combined savings ROADMAP #236 phases 1-3

- v1.69.0: ~12K tokens/session (BASELINE block fires once)
- v1.70.0: ~0.5-1.5K tokens/session (TDD CHECK fires once)
- v1.71.0: ~573 tokens/session (SDLC skill leaner on auto-invoke)

Total on a 50-prompt + 20-Edit + 1 SDLC-skill-invoke session: **~14K tokens/session**.

## [1.70.0] - 2026-05-05

### Token-bloat fix: TDD CHECK nudge fires once per CC session

`hooks/tdd-pretool-check.sh` was emitting a ~50-token JSON nudge ("TDD CHECK: Are you writing IMPLEMENTATION before a FAILING TEST?") on every Write/Edit/MultiEdit touching `src/**`. After the SDLC skill auto-invokes (which already covers TDD RED/GREEN), the per-Edit nudge is duplicate context — typical SDLC session has 10-30 src Edits = ~0.5-1.5K wasted tokens.

Now gated on per-`session_id` sentinel under `$SDLC_WIZARD_CACHE_DIR/tdd-shown-<id>`, atomic-claimed via subshell `set -C` (noclobber). Same pattern as v1.69.0 BASELINE gate.

### Behavior

- **First src/ edit of a CC session** → TDD CHECK emits as before.
- **Subsequent src/ edits (same session_id)** → TDD CHECK suppressed.
- **New CC session (different session_id)** → TDD CHECK re-emits.
- **Non-src/ files** → no output (existing behavior, regardless of sentinel). Editing README first does NOT consume the sentinel slot — TDD CHECK still fires on first src/ edit afterward.
- **No session_id in stdin** (legacy CC, direct shell tests) → emits every src/ edit (back-compat preserved).
- **N parallel src/ edits with same session_id** → exactly 1 TDD CHECK emit (atomic claim).

### Files

- `hooks/tdd-pretool-check.sh` — atomic-claim sentinel + jq-decoupled session_id extraction.
- `tests/test-tdd-pretool-fires-once.sh` (new — 9 cases including 50-parallel concurrency, non-src/ doesn't consume sentinel, suppressed-fire-empty assertion).
- `.github/workflows/ci.yml`, `CONTRIBUTING.md` — wire new test into validate job + contributor checklist.
- `CHANGELOG.md`, `SDLC.md`, `skills/update/SKILL.md`, `package.json`, `.claude-plugin/plugin.json` + `marketplace.json`, `CLAUDE_CODE_SDLC_WIZARD.md` (1.69.0 → 1.70.0).

### Notes

ROADMAP #236 functional-bloat audit, phase 2. Phase 1 (v1.69.0) trimmed the BASELINE block (~12K tokens/session). Phase 2 trims the per-Edit nudge. Combined savings on a 50-prompt + 20-Edit session: ~13.5K tokens. Audit method continues — measure cost × frequency, judge value, don't blind-delete. Other always-on hooks (`model-effort-check`, `precompact-seam-check`, `token-spike-check`) remain silent at healthy state and are not bloat.

## [1.69.0] - 2026-05-04

### Token-bloat fix: BASELINE block fires once per CC session

Cuts ~12K tokens/session of duplicate context for users with >3 prompts. The `SDLC BASELINE` block in `hooks/sdlc-prompt-check.sh` (~250 tokens) was firing on every `UserPromptSubmit` — once Claude has the SDLC skill auto-invoked (covers TodoWrite/confidence/workflow phases), every subsequent re-emission is pure duplication. Now gated by a per-`session_id` sentinel under `$SDLC_WIZARD_CACHE_DIR/baseline-shown-<id>`, pruned at 7d.

### Behavior

- **First prompt of a CC session** → BASELINE emits as before (cold-start nudge survives).
- **Subsequent prompts (same session_id)** → BASELINE suppressed.
- **New CC session (different session_id)** → BASELINE re-emits.
- **No session_id in stdin** (legacy CC, direct shell tests) → BASELINE emits every fire (back-compat preserved).
- `SETUP NOT COMPLETE` warning + `EFFORT BUMP REQUIRED` nudge **continue to fire every prompt** — they're dynamic state warnings, not static reminders.

### Files

- `hooks/sdlc-prompt-check.sh` — extracts `session_id` from stdin JSON; gates the static BASELINE block via per-session sentinel; prunes >7d sentinels on emit.
- `tests/test-baseline-fires-once.sh` (new — 8 cases covering first-fire, suppression, different-session re-emit, no-session-id back-compat, SETUP-warning persistence, EFFORT-bump persistence, cross-cache-dir isolation, byte-shrink verification).
- `.github/workflows/ci.yml` — wires new test into `validate` job.
- `CHANGELOG.md`, `SDLC.md`, `skills/update/SKILL.md`, `package.json`, `.claude-plugin/plugin.json` + `marketplace.json`, `CLAUDE_CODE_SDLC_WIZARD.md` (1.68.0 → 1.69.0).

### Notes

Discovered during ROADMAP #236 functional-bloat audit. Identified `sdlc-prompt-check.sh` as the #1 amplifier (every-prompt × 22 lines × N prompts). Audit method: measure cost × frequency, judge value — not blind delete-and-see. Per-prompt BASELINE failed cost/value once skill is loaded; conditional warnings + effort-bump detector earned their keep and stayed untouched. Other hooks (`model-effort-check`, `precompact-seam-check`, `token-spike-check`) are silent at healthy state — not bloat.

## [1.68.0] - 2026-05-04

### Closed (paperwork-stale roadmap rows)

- **ROADMAP #97 — Anthropic Policy & Research alignment audit** ✅ DONE 2026-05-04 with NO-GO + one validating parallel verdict. Research write-up at `.reviews/research-97-anthropic-policy.md`. RSP, Transparency Hub, and Research page audited. RSP: not applicable (Anthropic's internal model-dev policy). Transparency: tangential (model-card disclosures, security-guidance overlap covered by #101). Research page: the April 2026 "Automated Alignment Researchers" paper is **conceptually parallel** to our cross-model review pattern — independent third-party validation that LLM-as-reviewer-of-LLM works. Our implementation predates the paper (PR #189 / ROADMAP #72 mission-first cross-model review) and already mitigates its noted weaknesses (reward hacking, limited generalization) via vendor-diverse adversarial framing + verification checklist. Constitution + Economic Futures skipped as clearly off-topic. **6/6 external audits NO-GO** (continues #76, #77, #95, #99, #235).

- **ROADMAP #243 — token-spike-check follow-up** ✅ CLOSED 2026-05-04. The 2-week verify-window opened by `hooks/token-spike-check.sh` (shipped v1.43.0, 2026-04-27) has elapsed: `wc -l .metrics/token-history.jsonl` shows 8 rows accumulated on maintainer machine, well above the 5-record rolling-baseline threshold. SessionStart skip-recent filter and transcript-dir resolution are working as designed. No code changes.

### Files

- `.reviews/research-97-anthropic-policy.md` (new — research write-up, force-added past `.reviews/` gitignore)
- `ROADMAP.md` (#97 marked DONE with verdict + AAR paper reference)
- `CHANGELOG.md`, `SDLC.md`, `skills/update/SKILL.md`, `package.json`, `.claude-plugin/plugin.json` + `marketplace.json`, `CLAUDE_CODE_SDLC_WIZARD.md` (1.67.0 → 1.68.0)

### Notes

Zero code changes. Same pattern as v1.65.0 + v1.66.0 + v1.67.0 paperwork closes. Open backlog after this release: `#302` (user-level setup skill, design-blocked) + ROADMAP top items #212 (multi-day, partial-API), #9 OpenCode (separate session per maintainer).

## [1.67.0] - 2026-05-04

### Closed (paperwork-stale roadmap rows)

- **ROADMAP #99 — AutoGPT integration audit** ✅ DONE 2026-05-04 with NO-GO verdict. Research write-up at `.reviews/research-99-autogpt.md`. Three blockers: (a) AutoGPT is now an agent platform/framework — same layer as Claude Code / Codex / OpenCode, not a target for SDLC enforcement; (b) no hook primitive — AutoGPT's "blocks" system is workflow composition, not pre-tool-call enforcement, so the wizard's TDD/seam/prompt hooks have no place to live; (c) audience mismatch — AutoGPT users build continuous-service agents, not interactive SWE workflows. If a real demand signal ever surfaces, the right layering is "AutoGPT agent invokes Claude Code as a sub-tool" — that inherits the wizard for free without an AutoGPT port. **5/5 external-product audits NO-GO** (continues #76 Promptfoo, #77 constrain-to-playbook, #235 Thoughtworks AI Evals, #95 Nous Research).

### Files

- `.reviews/research-99-autogpt.md` (new — research write-up, force-added past `.reviews/` gitignore)
- `ROADMAP.md` (#99 marked DONE with verdict reference)
- `CHANGELOG.md`, `SDLC.md`, `skills/update/SKILL.md`, `package.json`, `.claude-plugin/plugin.json` + `marketplace.json`, `CLAUDE_CODE_SDLC_WIZARD.md` (1.66.0 → 1.67.0)

### Notes

Zero code changes. Same pattern as v1.65.0 + v1.66.0 paperwork closes.

## [1.66.0] - 2026-05-04

### Closed (paperwork-stale roadmap rows)

- **ROADMAP #95 — Nous Research competitive audit** ✅ DONE 2026-05-04 with NO-GO verdict. Research write-up at `.reviews/research-95-nous.md`. Nous Research builds open-weights LLMs (Hermes), agent frameworks (Hermes Agent), RL environments (atropos), and distributed-training infra (Psyche) — different layer of the stack from SDLC enforcement. Hermes Agent is the same layer as Claude Code / Codex CLI / OpenCode (a *target* for the wizard, not a competitor); the OpenCode port (#9) is the right vehicle if anyone ever wants the wizard to run against a self-hosted Nous endpoint. Pattern continues with #76 (Promptfoo NO-GO), #77 (constrain-to-playbook NO-GO), #235 (Thoughtworks AI Evals NO-GO): external-product audits keep validating the wizard's niche.

- **`docs/codex-near-top` cross-reference** ✅ DONE 2026-05-04 in PR #309. Surfaced `codex-sdlc-wizard` sibling at the top of README.md (after the tagline, before Install) and `CLAUDE_CODE_SDLC_WIZARD.md` (after the "What This Is" intro), so users on OpenAI's Codex CLI find the alternative without scrolling 250+/500+ lines to the Ecosystem section. Two new doc-consistency tests (head -30 / head -50 grep) keep the callout from drifting out of the top fold. OpenCode sibling intentionally not mentioned yet (per maintainer — bootstrap shipping in a different session).

- **GitHub issue #308 (API features review)** ✅ CLOSED 2026-05-04. 4/4 entries audited (`gh issue view 308#issuecomment-4375055751`): zero wizard changes needed. Sonnet 1M-beta retirement (2026-04-30) only affects Sonnet 4.5 and Sonnet 4 — wizard's `sonnet[1m]` mixed-mode tier resolves to Sonnet 4.6 which keeps 1M GA per [API release notes](https://platform.claude.com/docs/en/release-notes/api.md). Rate Limits API + Memory for Managed Agents are different products. Haiku 3 retirement is irrelevant — `grep -ri "haiku.3\|claude-3-haiku"` returned zero hits across the wizard.

### Files

- `.reviews/research-95-nous.md` (new — research write-up, force-added past `.reviews/` gitignore matching #206 + #235 precedent)
- `ROADMAP.md` (#95 marked DONE with verdict reference)
- `README.md` + `CLAUDE_CODE_SDLC_WIZARD.md` (codex sibling callout near top, shipped in PR #309)
- `tests/test-doc-consistency.sh` (2 new top-of-doc grep tests for codex callout, shipped in PR #309)
- `CHANGELOG.md`, `SDLC.md`, `skills/update/SKILL.md`, `package.json`, `.claude-plugin/plugin.json` + `marketplace.json`, `CLAUDE_CODE_SDLC_WIZARD.md` (1.65.0 → 1.66.0)

### Notes

Zero code changes (research + cross-reference docs only). Backlog after this release: 1 open issue (#302 user-level setup skill — design-blocked) + ROADMAP top items #212 (multi-day), #9 OpenCode (separate session per maintainer).

## [1.65.0] - 2026-05-04

### Closed (paperwork-stale roadmap rows)

- **ROADMAP #210 — Node 24 compliance regression** ✅ DONE 2026-04-23 in PR #217 (commit `045c938`). Defensive `test_no_oven_sh_setup_bun` + committed negative-control fixture both shipped on the original PR; the row was just never paperwork-closed. Audit 2026-05-04 confirms zero workflows use `oven-sh/setup-bun`, all 15 Node 24 compliance tests green, full action surface is Node 24-compatible. Hard deadline 2026-06-02 (GitHub forces Node 24) is comfortably met.

- **ROADMAP #235 — Thoughtworks "AI Evals" methodology audit** ✅ DONE 2026-05-04 with NO-GO verdict. Research write-up at `.reviews/research-235-ai-evals.md`. The Thoughtworks Decoder article is methodology-only; every layer it describes (pre-deployment validation, post-deployment monitoring, quality gates, continuous oversight, performance consistency, output accuracy, error-mode catching, model-evolution tracking) already has a working analog in our pipeline (Tier 1/2 evaluator + score-history + CUSUM + token-spike + adversarial cross-model review + SDP scoring). Only candidate gap is bias/alignment evaluation, which is out of scope (the wizard is SDLC enforcement, not LLM ethics). Pattern continues with prior NO-GO research items #76 (Promptfoo) and #77 (constrain-to-playbook).

### Files

- `.reviews/research-235-ai-evals.md` (new — research write-up, force-added past `.reviews/` gitignore matching #206 precedent)
- `ROADMAP.md` (#210 + #235 marked DONE with verdict references)
- `CHANGELOG.md`, `SDLC.md`, `skills/update/SKILL.md`, `package.json`, `.claude-plugin/plugin.json` + `marketplace.json`, `CLAUDE_CODE_SDLC_WIZARD.md` (1.64.0 → 1.65.0)

### Notes

Zero code changes. Two paperwork-stale rows closed; no new behavior. Useful for cleaning the active queue heading into the OpenCode Phase B/C planning session.

## [1.64.0] - 2026-04-30

### Added (XDLC ecosystem cross-references)

- **README gets an "XDLC Ecosystem (Sibling Projects)" section.** The wizard ships as one of three published siblings — `agentic-sdlc-wizard` (this repo, Claude Code / SDLC), `codex-sdlc-wizard` (Codex CLI / SDLC), and `claude-gdlc-wizard` (Claude Code / Game Development Life Cycle). Until now, none of the three READMEs cross-referenced the others, so a user landing on one package on npm or GitHub couldn't discover the family. The new section is a 3-row table with package name + GitHub repo + one-line description, plus a pointer to the broader [XDLC ecosystem](https://github.com/BaseInfinity/xdlc) umbrella.

- **Wizard doc references the GDLC sibling.** `CLAUDE_CODE_SDLC_WIZARD.md` already mentioned the Codex sibling in the MCP-tool-hooks audit (portability criterion); now expanded to mention `claude-gdlc-wizard` alongside it. Cross-host portability is reframed as "cross-host / cross-domain portability" since GDLC is a different domain (games), not just a different agent.

- **ROADMAP "Built With SDLC Wizard" table adds the GDLC row.** Previously listed only this repo and `codex-sdlc-wizard`. Now lists all three siblings; status column shows current sibling versions (Codex v0.7.x, GDLC v0.2.x).

### Tests

- **3 new tests in `tests/test-doc-consistency.sh`** prevent drift:
  - `test_readme_references_all_siblings` — README must mention both sibling package names by literal string match (`codex-sdlc-wizard`, `claude-gdlc-wizard`)
  - `test_readme_has_ecosystem_section` — README must have a discoverable `## XDLC Ecosystem` / `## Family` / `## Siblings` heading (not just an inline mention)
  - `test_wizard_doc_mentions_gdlc_sibling` — Wizard doc must reference `claude-gdlc-wizard` wherever Codex sibling is mentioned (regression guard for sibling parity)

  TDD-verified: all three failed before the doc edits, all three pass after. 33/33 doc-consistency tests green.

### Files

- `README.md` (new "XDLC Ecosystem (Sibling Projects)" section)
- `CLAUDE_CODE_SDLC_WIZARD.md` (line 501 expanded — Codex + GDLC siblings, cross-host/cross-domain portability framing)
- `ROADMAP.md` ("Built With SDLC Wizard" table — added GDLC row, bumped this repo's status to v1.64.0)
- `tests/test-doc-consistency.sh` (+3 tests, 33 total)
- `CHANGELOG.md`, `SDLC.md`, `skills/update/SKILL.md`, `package.json`, `.claude-plugin/plugin.json` + `marketplace.json` (1.63.0 → 1.64.0)

### Follow-up

- Mirror issues filed in `BaseInfinity/codex-sdlc-wizard` and `BaseInfinity/claude-gdlc-wizard` so each sibling adds the same Ecosystem section pointing back here. Bidirectional cross-references means any of the 3 npm package pages surfaces the family.

## [1.63.0] - 2026-04-30

### Added (cache-cost observability closeout — closes ROADMAP #204)

- **Explicit cache-miss regression test in `tests/test-token-spike.sh`.** ROADMAP #204 had a Prove-It Gate: "require at least one quality test proves the hook/skill catches an actual cache-cost regression pattern." This release closes that gate. New `test_cache_miss_pattern_triggers_spike_warning` builds a 20-row baseline of cache-hit-heavy sessions (high cache_read, low cache_creation), appends one cache-miss session (cache_read collapses to 0, cache_creation spikes to 50000), and asserts the >2σ spike warning fires. Negative control `test_high_cache_read_no_warning` confirms the detector keys on cost-bearing fields (`costly_tokens = input + cache_creation + output`), not raw token count — a session with 10× cache reads but unchanged costly_tokens does NOT fire (hot cache is healthy, not expensive).

- **Wizard doc gains "Cache-Cost Surprises" subsection in Token Efficiency.** Quantifies the 10-20× silent blowup pattern, points at `hooks/token-spike-check.sh` as the detection mechanism, references the Anthropic 2026-04-23 post-mortem, and lists practices to avoid silent invalidation. NOT added to `skills/sdlc/SKILL.md` — that file is already at the 5000-token session-load threshold (audit-session-load.sh trim ceiling). The hook itself fires the warning automatically; the wizard doc has the action-focused guidance for when a user explicitly asks.

### Closed (absorbed)

- **#204 — Cache-cost guardrail hook.** Codex strategic-pass-2 review confirmed: the cache-miss pattern surfaces directly in `costly_tokens` (the metric `#220`'s `hooks/token-spike-check.sh` tracks). #204 is absorbed by #220 + the v1.63.0 regression test + docs. No new hook needed — the existing one already covers it.

### Files

- `tests/test-token-spike.sh` (+2 tests, 16 total)
- `CLAUDE_CODE_SDLC_WIZARD.md` (Cache-Cost Surprises subsection in Token Efficiency)
- `ROADMAP.md` (#204 marked absorbed v1.63.0)
- `CHANGELOG.md`, `SDLC.md`, `skills/update/SKILL.md`, `package.json`, `.claude-plugin/plugin.json` + `marketplace.json` (1.62.0 → 1.63.0)

## [1.62.0] - 2026-04-30

### Fixed

- **Backfilled 5 corrupted rows in `tests/e2e/score-history.jsonl`** — closes ROADMAP #211. UI-scenario rows (`add-ui-component`, `ui-styling-change`) had `score:11, max_score:10` because the design_system criterion adds an 11th point but the historical writer capped max at 10. Live scoring code was already correct (PR #216, v1.36.0); this PR backfills the historical data so trend analytics aren't poisoned. Found via Codex strategic-priority review: 5 rows on lines 22–25 + 30 fixed via single `sed -i 's/"score":11,"max_score":10/"score":11,"max_score":11/g'`. JSON validity preserved on all 5 rows (verified via per-line `jq empty`).

### Closed (paperwork — already shipped, table rows were stale)

Codex strategic-priority review (`.reviews/grouping-review.md`) audited the open ROADMAP table and found 6 rows still presented as open despite shipping in earlier releases:

- **#207** — Community feature-discovery scanner (scanner shipped v1.39.0, fetcher v1.56.0 PR #286)
- **#215** — Tier 2 dead persist step (fixed v1.36.0; Tier 2 jobs subsequently deleted entirely per #212 Option 1)
- **#217** — `model-effort-check.sh` loud warning below xhigh (shipped 2026-04-24; three-tier logic at `hooks/model-effort-check.sh:44`)
- **#78** — Firmware E2E fixture (shipped earlier)
- **#79** — Domain-Adaptive Testing Diamond (shipped earlier)
- **#80** — SDLC Effectiveness Scoreboard (shipped earlier)

All six table rows now properly tombstoned with the shipping release reference. Reduces roadmap noise so future "what's next?" reads are honest.

### Verified (config-side)

- **#219 — model-pin guidance against CC 2.1.117+ persistence change.** Verified locally on CC 2.1.118 (npm latest 2.1.123): both `cli/templates/settings.json` and `.claude/settings.json` have `has("model") == false`. The new persistence semantics (session-picked model now remembered across restarts) are orthogonal to #198's recommendation to omit the pin. `tests/test-cli.sh:1155` already asserts no default model pin so no new test needed. Optional manual UX check noted in roadmap row.

### Files

- `tests/e2e/score-history.jsonl` (5 rows backfilled, lines 22–25 + 30)
- `ROADMAP.md` (8 stale rows tombstoned)
- `CHANGELOG.md`, `SDLC.md`, `CLAUDE_CODE_SDLC_WIZARD.md`, `skills/update/SKILL.md`, `package.json`, `.claude-plugin/plugin.json` + `marketplace.json` (1.61.0 → 1.62.0)

## [1.61.0] - 2026-04-30

### Added

- **Calibration scenario suite — closes ROADMAP #96 Phase 3 PR 2.** New `tests/e2e/scenarios/calibration-careful-read.md` is the first scenario in a new `calibration-*` family designed specifically to reward self-review and punish rushed implementations. Builds on PR 1 (the lift-proof harness, v1.60.0).

  The scenario asks the agent to add a `parsePrice(input)` utility that handles five distinct formats (standard, cents-only, comma thousand-separator, surrounding whitespace, invalid). A self-reviewing agent reads all five requirements before coding; a rushed agent skims the first example and ships `parseFloat(s.replace('$', ''))` — which silently corrupts `'$1,000.00'` to `1` (a thousand-fold pricing bug). The score delta between these two agent profiles on this scenario is a load-bearing **calibration signal** for `lift-proof.sh`.

  Out of scope: actual end-to-end calibration verification (does a low-effort agent actually score lower on this scenario than an xhigh agent?). That's deferred to ROADMAP #212(i) Prove-It Gate paired runs. PR 2 ships the scenario; #212(i) runs the comparison.

### Tests

- New `tests/test-calibration-scenarios.sh` (6 tests): asserts a `calibration-*.md` exists, has the standard scenario format (`# Scenario:`, `## Task`, `## Fixture:`, calibration-signal docs), and lists ≥2 numbered requirements (the careful-read multi-path signal).
- Wired into `ci.yml` and `CONTRIBUTING.md` test list.

### Files

- `tests/e2e/scenarios/calibration-careful-read.md` (new) — the parsePrice scenario
- `tests/test-calibration-scenarios.sh` (new) — format validator
- `.github/workflows/ci.yml` — new test step
- `CONTRIBUTING.md` — test list parity
- `CHANGELOG.md`, `ROADMAP.md`, `SDLC.md`, `CLAUDE_CODE_SDLC_WIZARD.md`, `skills/update/SKILL.md`, `package.json`, `.claude-plugin/plugin.json` + `marketplace.json` (1.60.0 → 1.61.0)

### What's still TBD

The `calibration-*` family is intentionally extensible. Future scenarios could test other SDLC virtues — scope guard (don't fix things outside the task), TDD discipline (write tests before implementation), regression hygiene (don't break existing tests). Each new calibration scenario is a separate PR; PR 2 establishes the format.

## [1.60.0] - 2026-04-30

### Added

- **Wizard-installation lift-proof harness — closes ROADMAP #96 Phase 3 PR 1.** The benchmark series goes:
  - **Phase 1** (v1.57.0): de-coached the simulation prompt so the agent isn't told what's scored.
  - **Phase 2** (v1.58.0): added the ground-truth gate so the judge can't pass broken code.
  - **Phase 3 PR 1** (this): measures **the wizard's contribution itself** by running the same scenario against a **bare** fixture (no `.claude/`) and a **wizard-installed** fixture, then emitting the score delta. Positive delta = the wizard lifts organic SDLC behavior. That's the load-bearing claim of the entire harness.

  New script `tests/e2e/lift-proof.sh`:
  - Two legs in tmp dirs — bare (empty `.claude/`) and wizard-installed (`hooks/skills/settings.json` copied from `$REPO_ROOT/.claude/`).
  - Same parity flags as `local-shepherd.sh` (`--max-turns 55 --output-format json --add-dir tests/e2e`).
  - Both legs invoke `evaluate.sh` under `EVAL_USE_CLI=1` (#228) — honestly zero-API end-to-end.
  - Emits structured JSON artifact at `.benchmark/lift-proof-<timestamp>.json` with `bare_score`, `wizard_score`, `delta`, `lift`, plus provenance.
  - `--dry-run` mode for CI smoke + tests; `--scenario` flag (default `add-feature`); `--output` to override artifact path.

- **`tests/e2e/lib/wizard-installer.sh:install_wizard_into_fixture()`** — single source of truth for "the wizard installed into a project." Replaces the inline `cp -R` lines in `local-shepherd.sh:_build_strip_dir`. Accepts `<source_dir> <target_dir>`, copies `hooks/`, `skills/`, and `settings.json` into `<target_dir>/.claude/`. Errors loudly on missing source or target instead of silently no-op'ing.

### Tests

- New `tests/test-wizard-installer.sh` (17 tests): library exposes `install_wizard_into_fixture()`, runtime check that hooks+skills+settings land in target, error paths for missing source/target, `local-shepherd.sh` sources the lib (single source of truth), `lift-proof.sh` runs claude --print twice / calls evaluator / emits delta / inherits `EVAL_USE_CLI=1` / writes artifact.
- Wired into `ci.yml` and `CONTRIBUTING.md` test list.

### Files

- `tests/e2e/lib/wizard-installer.sh` (new) — reusable install helper
- `tests/e2e/lift-proof.sh` (new) — bare-vs-wizard orchestrator
- `tests/e2e/local-shepherd.sh` — `_build_strip_dir` now sources the lib instead of inlining `cp -R` (DRY)
- `tests/test-wizard-installer.sh` (new, 17 tests)
- `.github/workflows/ci.yml` (new test step)
- `CONTRIBUTING.md` (test list)
- Version bump 1.59.0 → 1.60.0

### What's still TBD for #96 Phase 3

- **PR 2** — calibration scenarios with subtle bugs to test self-review effectiveness (1-3 focused scenarios proving the harness catches real behavioral misses). Lands as a separate PR per Codex's overnight prioritization recommendation: keep fixture plumbing separate from scenario design.

## [1.59.0] - 2026-04-30

### Added

- **Evaluator runs on Max via `claude --print` — closes ROADMAP #228.** New `EVAL_USE_CLI=1` mode in `tests/e2e/evaluate.sh` swaps the per-criterion judge transport from `curl` → `api.anthropic.com` to `claude --print --output-format json` against the user's Max subscription. Same model (`claude-opus-4-7`), same prompts, same JSON parsing — only the auth/billing path differs. `local-shepherd.sh` sets it by default and drops the `ANTHROPIC_API_KEY` hard-fail, so the local-Max shepherd is now **honestly zero-API**: simulation, evaluator, and orchestration all on Max quota. CI keeps the curl path (default) for paths without an authed CLI.

  Why: the local-shepherd previously claimed "zero-API" but the evaluator still hit the paid API for per-criterion scoring (~$0.40/PR). Codex flagged this in the #212 review as the gap to close. With #228 done, the local-Max path is end-to-end on subscription quota.

  CLI invocation flags: `--print --output-format json --max-turns 1 --model claude-opus-4-7 --tools "" --setting-sources user --mcp-config '{"mcpServers":{}}' --strict-mcp-config`. Single-shot, model pinned to match curl path, no built-in tool use (`--tools ""`), no MCP tool exposure (Codex round 1 P1 #1 — `--tools ""` alone leaves user MCP servers like `mcp__playwright__*` reachable; the criterion prompt embeds untrusted simulation output, so prompt-injection could otherwise reach them), settings limited to user-level so this repo's hooks (sdlc-prompt-check, etc.) don't fire and pollute the criterion prompt with SDLC-baseline reminders. Runs from a clean `mktemp -d` cwd for the same reason. Retry-once preserved from the curl path.

  Score parity: same model, same prompts. Stochastic variance is the only expected delta (±1-2 pts per criterion). Statistical parity proof (Prove-It Gate, paired N=15 runs) is **deferred to ROADMAP #212(i)** — implementation here is engineering, not a parity claim.

### Tests

- New `tests/test-evaluate-cli-mode.sh` (15 tests): EVAL_USE_CLI branch present, calls `claude --print --output-format json --max-turns 1 --tools ""`, runs from clean cwd, retries on failure, extracts `.result` via jq selector tolerant of array+object shapes, gates ANTHROPIC_API_KEY check, API path intact, shepherd exports the env var, shepherd no longer hard-fails on missing key, MCP isolated via `--mcp-config '{}' --strict-mcp-config` on both calls (Codex round 1 P1 #1), `--model claude-opus-4-7` pinned on both calls (Codex round 1 P1 #2).
- `tests/test-local-shepherd.sh`: replaced obsolete `test_shepherd_aborts_on_missing_api_key` with `test_shepherd_runs_without_api_key` (positive contract — shepherd no longer cares about API key when CLI mode is on).
- Wired into `ci.yml` (new step "Run evaluator CLI-mode tests (#228)").

### Files

- `tests/e2e/evaluate.sh` (new `call_criterion_cli()` helper, branch in `call_criterion_api()`, conditional API-key check)
- `tests/e2e/local-shepherd.sh` (drop API-key requirement, export `EVAL_USE_CLI=1`, update stale provenance comments to reflect closed #228)
- `tests/test-evaluate-cli-mode.sh` (new, 15 tests)
- `tests/test-local-shepherd.sh` (replace obsolete API-key abort test with positive zero-API contract)
- `.github/workflows/ci.yml` (new test step)
- `CHANGELOG.md`, `package.json`, `SDLC.md`, `CLAUDE_CODE_SDLC_WIZARD.md`, `.claude-plugin/plugin.json` + `marketplace.json`, `skills/update/SKILL.md`, `.claude/skills/update/SKILL.md` (1.58.0 → 1.59.0)

## [1.58.0] - 2026-04-30

### Added

- **Ground-truth gate for the E2E benchmark — closes ROADMAP #96 Phase 2.** New `tests/e2e/ground-truth.sh` runs the fixture's own test suite (`npm test`) post-simulation and emits structured JSON: `{tests_run, tests_pass, tests_rc, tests_tail}`. `local-shepherd.sh` calls it after the evaluator, before the score-history append. If tests fail, the final score is **capped at 5/10** (configurable via `GROUND_TRUTH_FAIL_CAP`) — the judge can't tell if `npm test` actually passes; only running it can.

  Combined with Phase 1's de-coaching (v1.57.0), the benchmark now requires **both** judge approval **and** real test passage. Catches "agent followed protocol but produced broken code" false-positives — exactly the failure mode the v1.32.0 cross-model audit warned about.

  Score-history rows now record `original_judge_score`, `tests_run`, `tests_pass`, `ground_truth_gated` so trend analytics can distinguish judge noise from real regressions.

  Cross-platform timeout: uses `timeout` if available, falls back to `gtimeout` (coreutils on macOS), and finally a portable `perl` fallback for stock systems. Default `GROUND_TRUTH_TIMEOUT=120s`.

  Escape hatches:
  - `SDLC_SHEPHERD_SKIP_GROUND_TRUTH=1` — disables the gate entirely (raw judge scores)
  - `SDLC_SHEPHERD_FIXTURE_DIR=...` — override fixture location (default `tests/e2e/fixtures/test-repo`)
  - `SDLC_SHEPHERD_GROUND_TRUTH=...` — override script path (used by tests)

### Tests

- New `tests/test-ground-truth.sh` (11 tests): passing/failing/no-test/no-package/missing-dir/no-args/help/JSON-validity/timeout-enforcement.
- 4 new integration tests in `tests/test-local-shepherd.sh` (38 total): gate caps judge=9 to score=5, gate leaves passing judge alone, no-tests fixture skips gate, `SKIP_GROUND_TRUTH` env var fully disables gate.
- Wired into `ci.yml` and `CONTRIBUTING.md` test list.

### Files

- `tests/e2e/ground-truth.sh` (new, 105 lines)
- `tests/test-ground-truth.sh` (new, 11 tests)
- `tests/e2e/local-shepherd.sh` (gate logic + new score-history fields)
- `tests/test-local-shepherd.sh` (4 new integration tests)
- `.github/workflows/ci.yml` + `CONTRIBUTING.md` (test list)
- Version bump 1.57.0 → 1.58.0

### Phase 3 (future)

- Install wizard files into the local-shepherd test fixture so the simulation tests "wizard-installed agent" vs "wizard-less agent." That's the actual *"does the wizard work?"* test — pairs with calibration scenarios that include subtle bugs to test self-review effectiveness.

## [1.57.0] - 2026-04-30

### Fixed

- **De-coached the E2E benchmark prompt — closes ROADMAP #96 Phase 1.** The local-shepherd + model-comparison prompts used to tell the agent EXACTLY what was scored (`"You MUST use TodoWrite (scored by automated checks)"`, `"MUST state confidence as exactly 'Confidence: HIGH/MEDIUM/LOW' (scored by automated checks)"`, `"Write or edit test files BEFORE implementation files (TDD RED phase is scored)"`, `"MUST self-review by using Read on files you modified (scored by automated checks)"`). v1.32.0 cross-model audit (Codex GPT-5.4 xhigh) rated the benchmark **2/10 NOT CERTIFIED** specifically because of this answer-key leakage — and Codex's 2026-04-30 priority review independently flagged it as the single highest-leverage next action. ROADMAP #96 had been marked "DONE (but benchmark is broken)" — meaning the infra shipped, but the actual de-coaching never happened. This release does it.

  Replaced with neutral task framing: `"You are completing a coding task in a real working directory. Read the scenario file for the task spec. Complete it however you'd normally complete a coding task — using whatever practices your tooling, skills, or instructions teach you."` No mention of TodoWrite / confidence / TDD / self-review.

  The model-comparison workflow installs the wizard into the test fixture (`tests/test-model-comparison.sh` Test 23), so the wizard's SDLC skill is what should drive behavior — not the prompt. The local-shepherd fixture does NOT have the wizard, so under the new prompt local-shepherd measures whether agents practice SDLC organically (calibration baseline). Phase 3 (future) will install wizard into the local-shepherd fixture and prove that wizard installation lifts organically-low scores back up — the actual *"does the wizard work?"* test.

### Changed

- `tests/test-local-shepherd.sh::test_shepherd_prompt_has_required_signatures`: rewritten — asserts new neutral signatures present (`"You are completing a coding task"`, `"Working directory:"`, `"Scenario file:"`, `"Do NOT use EnterPlanMode"`) AND has a negative assertion that cheat-sheet phrases (`"scored by automated checks"`, `"MUST use TodoWrite"`, `"TDD RED phase is scored"`) do NOT resurrect.
- `tests/test-model-comparison.sh::test_prompt_quality` (Test 22): inverted — was requiring TDD + confidence in the prompt; now asserts cheat-sheet phrases are NOT in the prompt.

### Files

- `tests/e2e/local-shepherd.sh` (prompt rewritten)
- `.github/workflows/benchmark-model-comparison.yml` (prompt rewritten)
- `tests/test-local-shepherd.sh` (Test 22 updated)
- `tests/test-model-comparison.sh` (Test 22 inverted)
- Version bump 1.56.0 → 1.57.0

### Phase 2 + 3 (future)

- Phase 2: independent ground truth via `npm test` post-run. High score requires BOTH judge approval AND tests passing.
- Phase 3: install wizard files into the local-shepherd fixture; demonstrate wizard installation lifts organically-low scores. Calibration scenarios with subtle bugs to test self-review effectiveness.

## [1.56.0] - 2026-04-29

### Added

- **`tests/e2e/fetch-community.sh`** — closes ROADMAP **#207**. Pulls public threads from Reddit (r/ClaudeCode + r/ClaudeAI) and HN Algolia ("claude code" stories), emits combined transcript text to stdout. Pipe to `scan-community.sh` to surface candidate `/slash-command` mentions that the wizard doesn't already know.

  Usage:
  ```bash
  ./tests/e2e/fetch-community.sh --reddit ClaudeCode,ClaudeAI --hn | ./tests/e2e/scan-community.sh -
  ```

  Live mode hits Reddit's public JSON API + HN Algolia (no auth, no API spend on the Anthropic side). `--offline DIR` reads fixture JSON from `DIR/reddit-${sub}.json` + `DIR/hn-claudecode.json` for tests + offline-on-laptop runs. 11 quality tests in `tests/test-community-fetch.sh` (all mocked HTTP via fixtures, runs offline).

  Pairs with the existing `scan-community.sh` (which was the manual-input piece): the maintainer no longer has to copy-paste threads. Discord skipped (requires bot/OAuth) and GH Discussions deferred (GraphQL-only, low marginal value over Reddit+HN coverage).

### Security

- **P0 fix during Codex round 1**: `parse_or_die` originally interpolated the path into `python3 -c` source. A crafted subreddit name with single quote + Python could escape the string and execute. Rewritten to pass the path via `JSON_PATH` environment variable. New regression test (`test_offline_fixture_path_injection_blocked`) creates a fixture with an injection-payload subreddit name and asserts the sentinel file is NOT created.
- **P2 fix during Codex round 1**: `--reddit` and `--offline` previously silently exited 1 when called without a value. Both flags now validate `${2:-}` is non-empty before consuming + emit a clear flag-specific error. Two new tests cover the missing-value paths.

### Files

- `tests/e2e/fetch-community.sh` (new, ~180 lines after round-1 P0/P2 fixes)
- `tests/test-community-fetch.sh` (new, 14 tests — 11 happy/error-path + 3 round-1 P0/P2 regressions)
- `tests/fixtures/community-fetch/*.json` (new, 5 fixtures: reddit-claudecode, reddit-claudeai, hn-claudecode, reddit-empty, plus malformed.json for parse-error testing)
- `.github/workflows/ci.yml` (+1 step: `Run community fetcher tests`)
- `CONTRIBUTING.md` (test list updated)
- Version bump 1.55.0 → 1.56.0

## [1.55.0] - 2026-04-29

### Removed

- **Dead leftovers in `.github/workflows/weekly-update.yml`** — closes ROADMAP #231 Phase 4. After Phase 3d, the workflow still carried code that was wired to nothing:
  - `env.VERSION_SCENARIO` — flagged as a "no-op marker" since Phase 3a (version-test deleted)
  - `outputs.has_overlap` / `outputs.overlap_paths` job-level outputs — set by the placeholder analysis step but consumed by no downstream job (prove-it-test was already deleted in Phase 2)
  - `Generate placeholder analysis` step — wrote `/tmp/analysis.json` with `relevance: "UNKNOWN"` purely so the next step could parse it back out
  - `Parse analysis result` step — read the placeholder and wrote outputs that are now hardcoded
  - `Build PR body` step + the `case "$RELEVANCE"` switch — relevance is always `UNKNOWN` post-Phase-3d, so the case statement and templated title/label collapsed to a literal `[UNKNOWN]` / `relevance-UNKNOWN`

### Changed

- `.github/workflows/weekly-update.yml`: 289 → 161 lines (-44%). Steps consolidated: 10 → 5 operational (6 YAML steps including checkout). Detection + version compare + existing-PR check fold into one `detect` step. PR body inlined as a `body: |` block on the create-pull-request action (was a separate Build PR body step writing /tmp/pr_body.md). The disabled cron line stays as a documented comment, but cron-collision tests now use Python YAML parsing (Codex round 1 P1) so they only compare ACTIVE schedules.
- `tests/test-workflow-triggers.sh`: Test 17 updated to grep for the new pattern (`gh pr list --head` + `skip=true`) since the dedicated `existing-pr` step ID was consolidated. Test 54 simplified — the placeholder is gone, so the regression check is now just "no `claude-code-action@v1` directive resurrects." 3 new Phase 4 regression tests added (`test_weekly_update_no_dead_version_scenario_env`, `_no_has_overlap_output`, `_no_overlap_paths_output`).

### Phase 3 + Phase 4 cumulative

- weekly-update.yml has shrunk from ~1670 lines (pre-Phase 3) to 161 lines (-90%). Five jobs/workflows + one in-job ranker chain + Phase 4 dead-code removed. Zero `claude-code-action@v1` references. Cron burn $25-55/week → $0/week.
- ROADMAP #231 closes here. Detection-only workflow stays at ~150 lines as documented in the Phase 4 plan; folding into the session-start hook would lose the GitHub PR audit trail (which is the only place the maintainer sees a new release while away from a session).

### Files

- `.github/workflows/weekly-update.yml` (-128 lines net)
- `tests/test-workflow-triggers.sh` (+86 lines: 3 new regression tests, 2 tests updated)
- Version bump 1.54.0 → 1.55.0

## [1.54.0] - 2026-04-29

### Removed

- **In-CI Claude-ranker steps in `.github/workflows/weekly-update.yml`** (~150 lines: Build analysis prompt + Analyze release with Claude + Extract from output + parse). Closes ROADMAP #231 Phase 3d. Replaced with a 12-line placeholder step that writes a stub `/tmp/analysis.json` with `relevance: "UNKNOWN"` and a summary linking the maintainer to the manual command. The auto-update PR body now surfaces the on-Max invocation:

  ```bash
  gh release view <version> --repo anthropics/claude-code --json body --jq .body > /tmp/release_notes.md
  claude --print --allowedTools "Read,Bash" \
    "$(cat .github/prompts/analyze-release.md)\n\n## Release\n\nVersion: <ver>\n\nNotes:\n$(cat /tmp/release_notes.md)"
  ```

### Phase 3 cumulative (after this release)

- **weekly-update.yml is now zero-API-spend.** No `claude-code-action@v1` calls in the workflow at all. Cron burn down from $25-55/week (pre-Phase 1) to $0/week. Only ~$0.30/run for the GH API release detection itself.
- 5 jobs/workflows deleted: monthly-research workflow (Phase 1), prove-it-test job (Phase 2), version-test job (Phase 3a), community-e2e-test job (Phase 3b), scan-community job (Phase 3c). Plus the in-job analysis chain in check-updates (Phase 3d).
- Phase 4 next: shrink weekly-update.yml further (currently 285 lines after Phase 3d) or fold detection into the session-start hook.

### Changed

- `tests/test-workflow-triggers.sh`: 2 tests updated. Test 54 inverted to assert no `uses: anthropics/claude-code-action` directive remains (regression check). Test 109 stubbed (the deleted analysis step's `--bare` flag check is moot).

### Files

- `.github/workflows/weekly-update.yml` (-99 lines net: -150 deleted ranker chain, +51 placeholder + maintainer-instructions PR body)
- `tests/test-workflow-triggers.sh` (2 tests)
- Version bump 1.53.0 → 1.54.0

## [1.53.0] - 2026-04-29

### Removed

- **`scan-community` job in `.github/workflows/weekly-update.yml`** (252 lines including its surrounding header comment block) — closes ROADMAP #231 Phase 3c. The CI cron ran a Claude scan of Reddit/HN/blogs + friction-signal issues at $2-5/run. After Phase 3b deleted its consumer (community-e2e-test), it only created digest issues — value didn't justify the cost. Replacement: maintainer runs `claude --print --allowedTools "WebFetch,Read,Bash" "$(cat .github/prompts/analyze-community.md)"` on Max ($0 sim leg) when interested.

### Changed

- `.github/prompts/analyze-community.md`: header rewritten with usage block describing the manual `claude --print` invocation. The competitive watchlist is unchanged.
- `tests/test-workflow-triggers.sh`: 7 tests stubbed (Tests 57, 70b, 70c, 70d, 70f, 113, 164). Test 86 expanded to assert ALL three deleted jobs (version-test, community-e2e-test, scan-community) stay deleted; renamed `_has_two_jobs_post_phase_3b` → `_has_one_job_post_phase_3c`.
- `tests/test-prove-it.sh`: Test 18 (competitive watchlist) reframed — checks only that `analyze-community.md` retains the watchlist content, not that any CI workflow consumes it.
- `plans/AUTO_SELF_UPDATE.md`: workflow table updated.

### Files

- `.github/workflows/weekly-update.yml` (-252 lines)
- `.github/prompts/analyze-community.md` (+10 lines header)
- `tests/test-workflow-triggers.sh` (7 stubs, 1 test expanded + renamed)
- `tests/test-prove-it.sh` (1 test reframed)
- `plans/AUTO_SELF_UPDATE.md` (1 line updated)
- Version bump 1.52.0 → 1.53.0

### Phase 3 cumulative
After v1.53.0, weekly-update.yml has only `check-updates` (the cheap detection cron, ~$0.30/run). Phase 3d (split check-updates into detection + Claude-ranker) is the last remaining slice before Phase 4 (full deletion or ~50-line minimum).

## [1.52.0] - 2026-04-28

### Removed

- **`community-e2e-test` job in `.github/workflows/weekly-update.yml`** (231 lines) — closes ROADMAP #231 Phase 3b. The CI job ran "apply community findings → Phase A baseline → Phase B candidate → compare_ci" on every external community finding at $8-15/run. 30-day window: 1 merged artifact (community-patterns/2026-04-23). Replacement: maintainer reviews the digest issue from `scan-community`, manually applies findings, runs `tests/e2e/local-shepherd.sh <PR> --compare-baseline` locally on Max ($0 sim leg).

### Changed

- `tests/test-workflow-triggers.sh`: 3 community-e2e tests stubbed to "n/a per #231 Phase 3b" (Test 70, 70e, 88). Test 86 expanded to assert BOTH version-test AND community-e2e-test stay deleted (renamed to `test_weekly_update_has_two_jobs_post_phase_3b`, expected = ['check-updates', 'scan-community']).
- `plans/AUTO_SELF_UPDATE.md`: workflow table + E2E Testing line updated to reflect both deletions.

### Files

- `.github/workflows/weekly-update.yml` (-231 lines)
- `tests/test-workflow-triggers.sh` (3 stubs, 1 test expanded + renamed)
- `plans/AUTO_SELF_UPDATE.md` (2 lines updated)
- Version bump 1.51.0 → 1.52.0 across the usual files

## [1.51.0] - 2026-04-27

### Removed

- **`version-test` job in `.github/workflows/weekly-update.yml`** (319 lines) — closes ROADMAP #231 Phase 3a. The CI job ran two-phase E2E (Phase A regression + Phase B improvement) on every detected CC release with `path_to_claude_code_executable` to install + test specific versions. Cost: $8-20/run with zero merged artifacts in 30 days. Replacement: manual local-Max procedure using the v1.49.0+ shepherd (`npm i -g @anthropic-ai/claude-code@<version> && tests/e2e/local-shepherd.sh <PR> --compare-baseline`). Auto-update PRs no longer get auto-validated; the maintainer runs the shepherd before merging.

### Changed

- `tests/test-self-update.sh`: 3 version-test gate tests stubbed to "n/a per #231 Phase 3a" (preserves harness counters; remove after one release if no regressions). Added regression test verifying CI_CD.md documents the manual local replacement.
- `tests/test-workflow-triggers.sh`: 4 tests updated. Test 86 inverted to ensure version-test stays deleted (any future resurrection emits VERSION_TEST_RESURRECTED). Tests 87, 93, 95 stubbed.
- `CI_CD.md` "Two-Phase Version Testing" section rewritten with the manual local-shepherd procedure.
- `plans/AUTO_SELF_UPDATE.md` "Two-Phase Version Testing" section marked DELETED with the local replacement runbook.

### Files

- `.github/workflows/weekly-update.yml` (-319 lines)
- `tests/test-self-update.sh` (4 tests stubbed/updated)
- `tests/test-workflow-triggers.sh` (4 tests stubbed/inverted)
- `CI_CD.md` (1 section rewritten)
- `plans/AUTO_SELF_UPDATE.md` (1 section rewritten)
- Version bump 1.50.0 → 1.51.0 across the usual files

## [1.50.0] - 2026-04-27

### Added

- **`local-shepherd.sh --strip-paths` flag** — closes ROADMAP #231 Phase 2. When CC ships native equivalents to wizard custom features, the maintainer runs `local-shepherd.sh <PR> --compare-baseline --strip-paths '[paths]'` locally on Max to A/B compare wizard-with-features (baseline) vs wizard-without-stripped-features (candidate). Same-commit comparison (no main worktree). Both `BASELINE_DIR` and `CANDIDATE_DIR` are tmpdirs laid out as project roots; the candidate's fixture has the requested paths removed via `create_stripped_fixture` from `tests/e2e/lib/prove-it.sh` (single source of truth for the allowlist). Score-history rows tagged with `comparison_role: "baseline" | "candidate"` (same contract as plain `--compare-baseline`).
  - **Validation**: paths must be in `REMOVABLE_ALLOWLIST` from `tests/e2e/lib/prove-it.sh`. Non-allowlisted paths (e.g. `/etc/passwd`) are rejected — security against LLM-hallucinated arbitrary deletions.
  - **Constraint**: `--strip-paths` requires `--compare-baseline` (lone `--strip-paths` exits with a clear error). No silent fall-through to single-run mode.
  - 8 new quality tests (30/30 total in `test-local-shepherd.sh`).

### Removed

- **`prove-it-test` job in `.github/workflows/weekly-update.yml`** (251 lines) — replaced by the local `--strip-paths` flag. The CI job ran $6-12 per overlap detection with zero merged artifacts in 30 days. Local-Max replacement is $0 (sim leg on subscription) and gives the maintainer richer context to decide KEEP CUSTOM / SWITCH TO NATIVE.

### Changed

- `tests/test-prove-it.sh`: replaced workflow-existence tests (#11-#12) with local-shepherd integration tests; added a regression test that the `prove-it-test` job stays deleted. All 20 tests green.
- `CI_CD.md` and `plans/AUTO_SELF_UPDATE.md`: updated to document the local replacement workflow. Historical section preserves the deleted CI job's intent.

### Files

- `tests/e2e/local-shepherd.sh` (+105 lines, ~35 changed)
- `tests/test-local-shepherd.sh` (+~180 lines, +8 tests)
- `tests/test-prove-it.sh` (replaced 3 tests with 4 better-targeted ones)
- `.github/workflows/weekly-update.yml` (-251 lines)

## [1.49.0] - 2026-04-27

### Added

- **`local-shepherd.sh --compare-baseline` flag** — closes ROADMAP #230. When set, the shepherd runs the same scenario on `main` (via `git worktree add --detach`) AND the current branch, then posts a baseline-vs-candidate delta to the check-run + PR comment. Both score-history rows are tagged with `comparison_role: "baseline" | "candidate"` so trend analytics can distinguish comparison runs from regular shepherd runs. Single-run mode (no flag) is unchanged for backward compat — no `comparison_role` field on those rows.
  - **Atomic write** (Codex P1 round 1): both rows are appended together AFTER candidate sim+eval succeeds. A candidate failure leaves zero comparison rows in history (no orphan baseline). Verified by `test_compare_baseline_no_orphan_row_on_candidate_failure`.
  - **Tempdir hygiene** (Codex P1 round 1): `BASELINE_TMPRUN` is nested under `TMPRUN` so the existing `trap` cleans it up on every exit path. No leaks even on early failures (history mkdir, evaluator crash). Verified by `test_compare_baseline_no_baseline_tmprun_leak`.
  - 9 new quality tests (22/22 total in `test-local-shepherd.sh`). Codex round 2 CERTIFIED 9/10 (round 1 found 2 P1s, both fixed).
- **Unblocks ROADMAP #231 Phase 2** — weekly-update workflow migration (currently burning $25-55/week on API). With `--compare-baseline`, the maintainer can run the comparison locally on Max instead of paying for it in CI.

### Changed

- `local-shepherd.sh`: provenance fields (`HOST_OS`, `CLI_VERSION`, `AUTH_MODE`, `EXECUTION_PATH`) now computed ONCE before any sim runs. Previously duplicated between baseline and candidate paths; consolidated for both DRY and correctness.

### Files

- `tests/e2e/local-shepherd.sh` (+247 lines, ~50 changed)
- `tests/test-local-shepherd.sh` (+~280 lines, +9 tests)

## [1.48.0] - 2026-04-27

### Changed

- **SKILL.md trim — token bloat audit phase 2 follow-up.** PR #272's new `scripts/audit-session-load.sh` flagged 2 of 4 SKILL.md files as TRIM candidates (>=5000 tokens each — `skills/sdlc/SKILL.md` at 12,427t, `skills/update/SKILL.md` at 8,555t). Acting on the tool's findings closes the Prove-It loop: a tool that surfaces real bloat whose owner ignores it is just a louder lint warning. Both skills trimmed below threshold without losing operational content:
  - `skills/sdlc/SKILL.md`: 12,427 → 4,995 tokens (-60%, 49,709 → 19,983 chars). Compressed prose, removed ASCII-art decoration boxes (kept the **bold sentences** they contained), tightened cross-model review section while preserving every Codex command, sandbox note, dialogue-loop template, and convergence rule. TodoWrite checklist intact (all 30 items, with `activeForm` removed since the spinner falls back to `subject` when omitted).
  - `skills/update/SKILL.md`: 8,555 → 4,044 tokens (-53%, 34,220 → 16,179 chars). Step 1.5 CLI version detection's 30-line Node `cmp()` helper replaced with prose describing the algorithm (split on `-`, numeric major.minor.patch, prerelease ordering — `1.40.0-beta.1 < 1.40.0`). Step 3 changelog example shortened from 20-line frozen list to a placeholder pointing at the actual fetched CHANGELOG.
  - Test anchor preservation traced manually: every grep'd phrase across `tests/test-{doc-consistency,self-update,update-skill-step-7-7,update-skill-cli-version,memory-audit-protocol,docs-usability,cli,prove-it,hooks}.sh` verified to still match. 45 unit suites + 4 e2e quick-tests green.
- **New quality test** (`tests/test-audit-session-load.sh`): `test_wizard_own_skills_below_threshold` runs the audit on the wizard repo itself and fails if any SKILL.md flags TRIM. RED before the trim (both files flagged), GREEN after. Mutation-verifiable: bumping either file ~200 tokens flips the test red.
- Codex round 1 CERTIFIED 10/10. No findings — Codex did its own RED/GREEN proof (stashed only the trimmed skill files to keep the new test active), verified every checklist item with shell evidence, ran the full CONTRIBUTING.md test suite, and read both files end-to-end against `git show HEAD:...` for semantic completeness.

### Files

- `skills/sdlc/SKILL.md` (trimmed)
- `skills/update/SKILL.md` (trimmed)
- `tests/test-audit-session-load.sh` (+test_wizard_own_skills_below_threshold)

## [1.47.0] - 2026-04-27

### Added

- **Codex review progress wrapper** (closes #259). Consumer reported `codex exec` running opaquely during 1-5 minute xhigh reviews — no signal whether Codex is "still thinking" or "crashed silently". New `scripts/codex-review-with-progress.sh` backgrounds `codex exec` with the same default flags (`xhigh`, `danger-full-access`, `-o`) and emits a heartbeat to stderr every N seconds (`SDLC_CODEX_HEARTBEAT_INTERVAL`, default 10s):
  ```
  [codex 0m10s elapsed, 0 bytes written to .reviews/latest-review.md] still running...
  [codex 0m20s elapsed, 1342 bytes written to .reviews/latest-review.md] still running...
  [codex finished in 47s with rc=0]
  ```
  - **Signal-safe**: uses interruptible `sleep & wait` pattern (plain `sleep` blocks bash signal delivery for up to INTERVAL seconds). SIGTERM/INT/HUP propagates to the child codex within ~1s via TERM-then-KILL cleanup. No orphan codex processes after wrapper kill.
  - **Preflight binary check**: missing/typoed `codex` binary exits 127 with a clear error before backgrounding anything.
  - **No spurious heartbeats**: loop rechecks liveness after each sleep, so a fast-exiting codex doesn't print one final "still running..." after it has already finished.
  - 11 quality tests (`tests/test-codex-progress-wrapper.sh`) using a stub codex binary — no real OpenAI tokens burned. Codex round 3 CERTIFIED 10/10 (rounds 1-2 surfaced subprocess management bugs: missing trap cleanup, sleep blocking signal delivery, missing-binary not exiting 127 — all fixed with regression tests).
- `skills/sdlc/SKILL.md` Step 2 documents the wrapper as the recommended invocation for long reviews, alongside the bare `codex exec` form.

### Files

- `scripts/codex-review-with-progress.sh` (new, ~80 lines)
- `tests/test-codex-progress-wrapper.sh` (new, 11 tests)
- `.github/workflows/ci.yml` — wires the new test step
- `skills/sdlc/SKILL.md` — Step 2 documents the wrapper

## [1.46.1] - 2026-04-27

### Fixed

- **`npx check` surfaces dangling+enabled plugin state** (closes #266). Consumer disabled the wizard plugin via directory rename — CC's plugin loader still tried to resolve the missing path because `~/.claude/settings.json` `enabledPlugins["sdlc-wizard@sdlc-wizard-local"] = true` was untouched. Result: every UserPromptSubmit hook crashed silently for 3 days. The wizard can't fix CC's plugin loader, but `npx agentic-sdlc-wizard check` now cross-references `enabledPlugins` against DANGLING marketplace paths and surfaces a `CRASH RISK` block with the exact remediation: edit `~/.claude/settings.json` to flip the boolean to `false`, OR run `/plugin uninstall`. Strict-boolean check (only literal `true` triggers); scoped npm package keys parse correctly via `lastIndexOf('@')`. 3 new tests; Codex CERTIFIED 10/10 round 1.

### Files

- `cli/init.js` — `checkMarketplacePaths()` now reads `enabledPlugins`; result objects gain `crashRisk: bool` + `enabledPluginKey: string|null`; print loop surfaces actionable `CRASH RISK` block when both DANGLING + enabled hold
- `tests/test-cli.sh` — 3 new tests (positive crash-risk fires, negative without enabled, negative with disabled)

## [1.46.0] - 2026-04-27

### Added

- **PreCompact dry-run env vars** (closes #240). Consumer reported clobbering their real `.reviews/handoff.json` while smoke-testing the PreCompact hook — the only way to verify hook behavior was to `cp` real state aside, fabricate fakes, and restore. Two new env vars simulate state in-memory:
  - `SDLC_DRY_RUN_HANDOFF_STATUS=<value>` — overrides the handoff.json read entirely. Useful values: `PENDING_REVIEW`/`PENDING_RECHECK` (block), `CERTIFIED` (silent). Skips file I/O.
  - `SDLC_DRY_RUN_GIT_STATE=rebase|merge|cherry-pick` — simulates an in-flight git op. No real `.git/` needed.
  - **Safety**: unknown values (typos like `bogus`) fall back to real-state checks rather than silently bypassing safety. Codex round 1 caught this bypass risk; the fix uses a `DRY_RUN_GIT_HANDLED` flag so only known scenarios short-circuit the real check.
  - **No mutations**: dry-run paths are pure read-only simulation. Subsequent runs without env vars see clean state.
- 7 new test-hooks tests (positive simulations + override of real PENDING + typo fallback + no-mutation guarantee). Codex round 2 CERTIFIED 10/10.

### Files

- `hooks/precompact-seam-check.sh` — comment block + dry-run handoff `if/elif` branch + dry-run git `case` with `DRY_RUN_GIT_HANDLED` flag; real-state check gated on flag
- `tests/test-hooks.sh` — 7 new dry-run tests

## [1.45.0] - 2026-04-27

### Added

- **PreCompact path (c) — SHA-ancestry self-heal** (closes #257). Consumer reported PreCompact blocking `/compact` even when the cited Codex review WAS actually CERTIFIED — the user just forgot to bump `handoff.json status` from `PENDING_RECHECK` → `CERTIFIED`. Existing self-heals don't cover this solo-developer pattern: path (a) needs `pr_number`, path (b) needs `mtime > 14d`. New path (c) heals when: handoff is `PENDING_*` with no `pr_number`, every SHA cited in `fixes_applied[]` is reachable from HEAD (`git merge-base --is-ancestor`), AND `.reviews/latest-review.md` contains `CERTIFIED` without `NOT CERTIFIED`. Path (b) still runs if (c) abstains (no SHAs / no review file).
  - **Robust extraction**: awk extracts the `fixes_applied[]` block via bracket-depth + escape-aware string-literal tracking. `]` inside string literals (e.g. `"[x] FIXED..."` markdown checkboxes, `"...\"]"` escaped-quote-bracket) does NOT terminate the array prematurely.
  - **UUID resilience**: strips 8-4-4-4-12 hex UUIDs before SHA extraction so ticket IDs in fixes_applied entries (Linear, Jira, mission UUIDs) don't false-block the heal.
  - **Phantom SHA gate**: every cited SHA must pass `git merge-base --is-ancestor` against HEAD. Phantom SHAs (typos, references to other repos) correctly fail and block the heal.
  - 9 new test-hooks tests (positive heal, phantom blocks, NOT CERTIFIED blocks, missing review.md blocks, partial coverage blocks, fall-through to stale, markdown-checkbox bracket, UUID alongside real SHA, escaped-quote bracket). Codex round 3 CERTIFIED 10/10 (rounds 1-2 surfaced bracket-extraction edge cases — markdown `[x]`, escaped quotes — and UUID false-block; all fixed).

### Files

- `hooks/precompact-seam-check.sh` — new path (c) block with depth-counted + escape-aware awk extraction, sed UUID strip, ancestry check
- `tests/test-hooks.sh` — `_precompact_init_repo_with_commit` helper + 9 new path (c) tests

## [1.44.1] - 2026-04-27

### Fixed

- **Autocompact compound-misconfig detection** — closes #207. Consumer reported autocompact firing at 12% context on a fresh `opus[1m]` session because they set BOTH `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=30` AND `CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000` (a natural misreading of `CLAUDE_CODE_SDLC_WIZARD.md:1008`'s "or"-joined cell). The two compound: `30% × 400000 = 120000 tokens ≈ 12% of 1M`.
  - **Doc fix**: `CLAUDE_CODE_SDLC_WIZARD.md` 1M-vs-200K table now writes `**OR** ... (pick one)` and adds a `> ⚠ Do NOT set both` callout that explains the compound math and points at the runtime detection.
  - **Runtime detection**: `instructions-loaded-check.sh` (InstructionsLoaded hook) reads `.claude/settings.json` for both env vars, computes the effective trigger, and warns with the math when both are set — diagnosable from the warning alone.
  - **Shipped skill drift**: `skills/sdlc/SKILL.md` was still calling `opus[1m]` the "default" (stale post-#198) AND repeating the same ambiguous "30 or 400000" wording it ships to consumers. Both fixed: opus[1m] now framed as opt-in with #198 reference; autocompact tuning line says "pick ONE of: ... OR ... (do NOT set both)".
- 4 new test-hooks tests (warns / silent on PCT-only / silent on WINDOW-only / shows effective trigger), 3 new test-doc-consistency tests (wizard doc + sdlc skill regression guards), size-cap test fixture extended to include the new branch (cap raised 1500 → 1700 to accommodate). Codex round 2 CERTIFIED 9/10 (round 1 surfaced the size-cap, shipped-skill drift, and InstructionsLoaded vs SessionStart wording — all fixed).

### Files

- `hooks/instructions-loaded-check.sh` — new compound-misconfig detection block (single-line warning with full env var names + effective trigger math)
- `CLAUDE_CODE_SDLC_WIZARD.md` — line 1008 alternatives clarification + `> ⚠ Do NOT set both` callout
- `skills/sdlc/SKILL.md` — `opus[1m]` reframed `Default` → `Opt-in` (matches wizard doc post-#198); autocompact tuning line now warns against the compound config
- `tests/test-hooks.sh` — 4 new tests + size-cap fixture extended + cap raised
- `tests/test-doc-consistency.sh` — 3 new regression guards (wizard doc + sdlc skill)

## [1.44.0] - 2026-04-27

### Fixed

- **Install-path & cache hygiene** — closes #254 (P1+P2), #239, #238 filed by consumer codeguesser after upgrading 1.32.0 → 1.42.1.
  - **#254 Bug 1 (P1)**: `cli/init.js` FILES list now ships `hooks/_find-sdlc-root.sh`. The helper is sourced by all 5 wizard hooks and provides `find_sdlc_root` + `dedupe_plugin_or_project`, but `npx ... init --force` previously didn't copy it. Result on every consumer: stderr noise (`_find-sdlc-root.sh: No such file or directory`, `dedupe_plugin_or_project: command not found`) and the SDLC walk-up logic (#171), silent-exit-for-non-SDLC-dirs (#173), and plugin/project dedupe were all silently dead.
  - **#254 Bug 2 (P2)**: `init --force` now invalidates `~/.cache/sdlc-wizard/latest-version` (or `$SDLC_WIZARD_CACHE_DIR/latest-version` when overridden). Previously the cache held the pre-upgrade "latest" for up to 24h, producing reverse staleness nudges like `update available 1.42.1 → 1.41.1`. Console now prints a `BUST` line so the cache eviction is visible.
  - **#254 Bug 2 / #239 (semver-direction)**: `instructions-loaded-check.sh` introduces `semver_lt` for numeric major/minor/patch comparison. Nudge gate switched from `LATEST_VERSION != INSTALLED_VERSION` (which fired on equality AND reverse direction) to `semver_lt INSTALLED LATEST` — so the nudge only fires when an actual upgrade is available. Cache reads gain a sanity check: cached "latest" must be >= installed, otherwise force a refetch.
  - **#239 (npm failure surface)**: When `npm view` fails (e.g. EPERM from root-owned `~/.npm/_cacache/`) AND no usable cache exists, the hook now prints `npm view failed — version check unavailable (run 'npm view agentic-sdlc-wizard version' to debug)`. Previously the version-check block produced no output at all and the user had no signal that the staleness nudge was broken.
  - **#238 (dual-channel ack sentinel)**: The "CLI skills + Claude plugin both present" warning gains an opt-in silence mechanism. Once the user runs `mkdir -p $DUAL_CACHE_DIR && touch $DUAL_ACK_FILE` (the exact command is printed inside the nudge), the warning stops firing. Sentinel lives at `$SDLC_WIZARD_CACHE_DIR/dual-channel-acknowledged` (defaults to `~/.cache/sdlc-wizard/dual-channel-acknowledged`). Removes the every-session noise that was training users to ignore all hook output.
- 8 new tests across `tests/test-cli.sh` (75 total, +3 for #254) and `tests/test-hooks.sh` (134 total, +5 for the four bugs + Codex round-1 cache-dir-absent regression test). Codex CERTIFIED 10/10 round 2.

### Files

- `cli/init.js` — `FILES` list adds `_find-sdlc-root.sh`; new `invalidateVersionCache()` helper; `--force` path calls bust + logs `BUST` line
- `hooks/instructions-loaded-check.sh` — new `semver_lt()`; cache sanity check; npm-fail surface; semver-direction nudge gate; dual-channel ack sentinel
- `tests/test-cli.sh` — file-count test bumped 11→12; 3 new tests
- `tests/test-hooks.sh` — 5 new tests covering all 4 bugs + Codex cache-dir-absent regression

## [1.43.0] - 2026-04-27

### Added

- **Token-spike anomaly detection** (ROADMAP #220 closure). New SessionStart hook `hooks/token-spike-check.sh` walks the CC transcript dir (`~/.claude/projects/<sanitized-cwd>/*.jsonl`), sums per-session `usage.{input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens}` from every assistant message with a usage block, and idempotently appends one record per `session_id` to `.metrics/token-history.jsonl`. The hook then warns when the most recent completed session's `costly_tokens` (= `input + cache_creation + output`, excluding the cheap ~$1.50/M `cache_read` tier) exceeds the rolling baseline by more than 2σ. Anthropic's 2026-04-23 post-mortem documented a CC caching bug that "continuously dropped thinking blocks from subsequent requests" — invisible until the invoice arrived; this hook surfaces the same shape of regression the moment it occurs. The `--metric median` mode (default) uses MAD (median absolute deviation) instead of stdev for the spread term, so a single outlier session in the baseline doesn't mask the next genuine spike. Hook is gated on `.metrics/` existing in the project root (opt-in for consumers, on for the wizard repo which already maintains `.metrics/catches.jsonl`). 14 quality tests in `tests/test-token-spike.sh` cover burn calculation against summed transcript fields, idempotent ingest, positive/negative spike detection, the min-baseline floor (no false positives on <5-record windows), the median-vs-mean contrast (both `--metric` modes invoked, asserting median warns and mean does not on an outlier-inflated fixture), flat-baseline minimum-spread floor (1000→1100 suppressed, 1000→50000 still fires), privacy/type-coercion (a malicious transcript with `"USER_SECRET_INPUT"` strings in usage fields cannot leak content into history), concurrent-ingest atomic-lock serialization (parallel ingests produce 1 record per session), and hook gating + warning surface.

### Files

- New `hooks/token-spike-check.sh` (SessionStart, opt-in)
- New `tests/e2e/token-analytics.sh` (writer + checker engine; supports `--ingest`, `--check`, `--report`, `--metric median|mean`, `--window`, `--threshold-sigma`)
- New `tests/test-token-spike.sh` (14 quality tests)
- Hook registered in `hooks/hooks.json` and `.claude/settings.json` SessionStart event
- `SDLC.md` hooks table + file tree updated

## [1.42.2] - 2026-04-26

### Documented

- **`pr_number` opt-in for PreCompact self-heal** (ROADMAP #209 closure). The `precompact-seam-check.sh` hook self-heals on `PENDING_*` handoffs whose linked PR has merged: when handoff has `pr_number` and `gh pr view N --json state` returns `MERGED`, hook treats handoff as implicit CERTIFIED and unblocks `/compact` silently. The behavior shipped earlier alongside ROADMAP #229 (stale-expire fallback) but was undocumented in the handoff template schemas — meaning consumers had no way to discover the opt-in. Documented `pr_number` as an optional self-heal field in all 3 handoff schemas: `skills/sdlc/SKILL.md` (Step 1: Mission-First Handoff), `CLAUDE_CODE_SDLC_WIZARD.md` (Round 1: Initial Review + cross-model review section). New `test_handoff_template_documents_pr_number` in `tests/test-hooks.sh` (129 hook tests, 1 new) enforces template/doc parity going forward — a future schema edit that drops `pr_number` will fail this test. Hit live in this repo 2026-04-19 (PR #205) and 2026-04-26 (PR #253) — original handoffs lacked the field and fell through to the 14-day stale-expire fallback. Together with #229, #209 closes the "stuck PENDING handoff blocks /compact forever" footgun from both directions: PR-linked reviews self-heal on merge (instant), unlinked reviews auto-expire on mtime (14d default).

## [1.42.1] - 2026-04-26

### Fixed

- **Skip Claude PR review on wizard self-PRs** (CI hygiene). The `review` job in `pr-review.yml` calls `claude-code-action@v1` which requires `ANTHROPIC_API_KEY` with positive credit balance. The wizard maintainer keeps that key's balance dead as an "API canary" so unexpected API draws fail CI. Result: every wizard self-PR's `review` job was failing with "Credit balance is too low" — seven PRs (v1.39.0–v1.42.0) shipped to main with red CI, normalizing red and masking any real review failure. Fixed: workflow `if:` gate now skips the review job when `github.repository == 'BaseInfinity/claude-sdlc-wizard'`. Consumer projects using `pr-review.yml` are unaffected — the skip only fires on the wizard's own repo. The wizard uses Codex (`codex exec` xhigh) for cross-model review on its own PRs, so the Claude PR review is redundant on self-repo. Documented in `CI_CD.md` → "Self-PR Skip on the Wizard Repo". New `tests/test-self-pr-review-skip.sh` (6 tests) prevents regression.

## [1.42.0] - 2026-04-26

### Added

- **AGENTS.md interop detection in setup** (ROADMAP #205, phase a). Setup wizard now scans for `AGENTS.md` (cross-tool agent-instructions standard adopted by Cursor/Continue.dev/Aider, [CC issue #6235](https://github.com/anthropics/claude-code/issues/6235)) during Step 1 auto-scan. If found, new Step 4.5 surfaces a 3-way decision: dual-maintain (default), merge (manual in phase a), or skip. The choice is recorded as a one-line comment in the project's `SDLC.md` for the user's reference — `/update-wizard` does NOT yet parse this metadata (phase d). No wizard-side merge or symlink behavior in v1.42.0 — option B in the prompt is "record intent, copy by hand"; phase (b) will add the copy helper. Phase (d) drift-consistency test also deferred. New `tests/test-agents-md-interop.sh` (7 tests) asserts setup auto-scan, decision step structure, wizard doc reference + phase-scope honesty.

## [1.41.1] - 2026-04-26

### Added

- **MCP-tool hooks audit documented** (ROADMAP #218). CC 2.1.118 introduced `type: "mcp_tool"` for hooks. Audited all 5 wizard hooks (sdlc-prompt-check, instructions-loaded-check, tdd-pretool-check, model-effort-check, precompact-seam-check) against MCP-tool migration criteria: portability, gating semantics, cross-tool state. Conclusion: all 5 stay bash. Per-hook rationale documented in CLAUDE_CODE_SDLC_WIZARD.md → "Known CC Gotchas → MCP-tool hooks audit". New `tests/test-mcp-hook-audit.sh` (7 tests) ensures the audit doesn't get re-litigated by future maintainers; if a hook DOES migrate later, the test is the natural place to update with new rationale.

## [1.41.0] - 2026-04-26

### Added

- **Post-mortem 2026-04-23 lessons folded into wizard docs** (ROADMAP #221). [Anthropic's 2026-04-23 post-mortem](https://www.anthropic.com/engineering/april-23-postmortem) provides independent third-party evidence for three SDLC-relevant failure modes; this release captures all three:
  - **Don't rely on CC default effort** — the post-mortem confirmed CC has flipped reasoning_effort defaults across versions (high → medium → xhigh/high). Recommended Effort section now cites this as evidence and reinforces that `/effort max` should be set explicitly every session, never assumed from the default.
  - **Extended-thinking + caching + idle sessions can drop thinking blocks** — new "Known CC Gotchas" top-level section documents the failure mode (cached prompt prefix re-served after idle pruning silently drops thinking blocks downstream), with a workaround (start fresh session with `claude --continue` if quality degrades mid-session) and a detection signal pointer to ROADMAP #220.
  - **Brevity-cap audit + regression guard** — audited every `skills/*/SKILL.md` and `hooks/*.sh` for compounding brevity constraints (`≤N words`, `be concise`, `keep brief`). Audit clean; no system-prompt brevity caps in the wizard. New `tests/test-postmortem-lessons.sh` (7 tests) includes a regression guard that fails CI if a future PR introduces one.
- "Known CC Gotchas" is now a documented section pattern; future CC failure modes get folded here with workarounds.

## [1.40.1] - 2026-04-26

### Added

- **`cleanupPeriodDays: 30` pinned in template settings** (ROADMAP #225). CC 2.1.117 expanded `cleanupPeriodDays` to also cover `~/.claude/tasks/` — the directory where the Tasks system persists in-progress TodoWrite state. With aggressive defaults (some CC versions defaulted to 7 days), SDLC checklists for paused long-running features could be silently pruned. `cli/templates/settings.json` now ships `"cleanupPeriodDays": 30` as a top-level field. `CLAUDE_CODE_SDLC_WIZARD.md` documents the gotcha + override path. New `tests/test-cleanup-period-guidance.sh` (7 tests) asserts template default + wizard rationale don't regress.

## [1.40.0] - 2026-04-25

### Added

- **CLI version detection in /update-wizard** (ROADMAP #232). New Step 1.5 detects the locally installed `agentic-sdlc-wizard` CLI version (via `npm ls -g` for global installs and `~/.npm/_npx` cache inspection for npx users), compares to the npm registry latest at `registry.npmjs.org/agentic-sdlc-wizard/latest`, and surfaces a one-shot `npx -y agentic-sdlc-wizard@latest init --force` upgrade BEFORE running drift detection or per-file updates. Closes the gap where `/update-wizard` patched in-session project files but the user's stale npx cache kept running an old CLI on `init`/`check`/`complexity` invocations. Mirrors `claude update` UX (one-shot CLI + skill sync). Honors the `check-only` flag in report-only mode (no auto-upgrade). Graceful fallback when the CLI is undetectable (custom install, offline). New `tests/test-update-skill-cli-version.sh` (8 quality tests) covers step structure, both detection paths, the registry endpoint, the upgrade command, ordering before per-file plan, `check-only` precedence, fallback wording, and the changelog entry itself.

## [1.39.1] - 2026-04-25

### Fixed

- **Step 7.7 hoist** — `/update-wizard` now runs the dead-plugin cleanup even when the wizard version on disk matches npm latest. In v1.39.0 the cleanup was gated behind Step 3's "if versions match: stop" branch, so users already on the latest wizard with a stale `~/.claude/settings.json` plugin registration could never reach Step 7.7. Symptom: `UserPromptSubmit hook error: Plugin directory does not exist: ...sdlc-wizard@sdlc-wizard-local — run /plugin to reinstall` firing on every prompt despite running `/update-wizard`. Fix updates Step 3's match-branch to invoke Step 7.7 first, then stop. New `tests/test-update-skill-step-7-7.sh` (8 quality tests) asserts the ordering and prevents regression — covers Step 3-references-Step 7.7, ordering keywords, Step 7.7 documents version-independence, allowlist intact, jq pipeline intact, timestamped backup intact.

## [1.39.0] - 2026-04-24

### Added

- **Dead plugin registration cleanup in /update-wizard** (Step 7.7). When a wizard-installed plugin marketplace in `~/.claude/settings.json` points to a directory that no longer exists (rename, disable, or removal), every Claude Code session emits `UserPromptSubmit hook error: Failed to run: Plugin directory does not exist: ...` until cleaned up. New step detects entries in `extraKnownMarketplaces` matching `sdlc-wizard*` whose `source.path` is missing, plus the corresponding `enabledPlugins["sdlc-wizard@<marketplace>"]` flag, and offers cleanup with a backup. Scope-guarded to wizard installs only — never touches third-party plugin registrations. Lives in update-skill (not setup) because dead registrations only appear after install when something disables or removes the plugin directory; update is the natural drift-detection seam.

- **Community feature-discovery scanner** — ROADMAP #207. New `tests/e2e/scan-community.sh` script extracts `/[a-z][a-z0-9-]*` slash-command mentions from transcript text (Reddit, HN, Discord, CC GitHub Discussions exports) and emits any not in the `tests/e2e/known-slash-commands.txt` allowlist. Output is JSON with `scan_date`, `input_files`, and `candidates: [{slash, count, sample}]` for triage. Maintainer pulls transcripts manually (per ROADMAP #231 Phase 3 plan: "scan-community → port to tests/e2e/scan-community.sh; maintainer runs weekly on Max"); the scanner itself is offline + deterministic. Allowlist seeded with wizard skills (`/sdlc`, `/setup`, `/update`, `/feedback`, `/code-review`, `/less-permission-prompts`, `/claude-automation-recommender`, `/schedule`, `/ultrareview`), CC native commands as of 2.1.118 (`/help`, `/clear`, `/model`, `/effort`, `/usage`, `/cost`, `/stats`, `/compact`, `/resume`, `/init`, `/mcp`, `/plugin`, `/agents`, `/hooks`, `/permissions`, `/sandbox`, `/fast`, `/exit`, `/login`, `/logout`, `/doctor`, `/install`, `/uninstall`, `/settings`), plus common URL-path false positives (`/dev`, `/usr`, `/var`, `/tmp`, `/etc`, `/bin`, `/lib`, `/opt`, `/home`, `/root`, `/proc`, `/sys`, `/run`, `/mnt`, `/media`, `/srv`). Length-≥4 filter drops `/a`, `/ab` style noise. New `tests/test-community-scanner.sh` (14 tests) covers detection, allowlist filtering (CC native + wizard skills), dedup + count, empty-input edge case, JSON shape, stdin input, multi-file aggregation, sample-context inclusion, long-line sample window, case-insensitive extraction, and dash-leading filenames. Procedure documented in `CLAUDE_CODE_SDLC_WIZARD.md` → "Community Feature-Discovery Scanner". Complements aistupidlevel.info degradation signal and CC changelog diffs — three signals together cover official + community feature surface.

## [1.38.0] - 2026-04-24

### Added

- **Prompt-hook-fires-once instrumentation** — ROADMAP #224. `hooks/sdlc-prompt-check.sh` now records one tab-separated record (`<ts>\t<pid>\tsdlc-prompt-check`) per post-dedupe invocation when the opt-in env var `SDLC_HOOK_FIRE_LOG` is set. Maintainer can count lines per user prompt to verify CC 2.1.118's double-fire fix in real sessions; >1 line per prompt indicates regression. Unwritable paths fail silently. Procedure documented in `CLAUDE_CODE_SDLC_WIZARD.md` → "Verifying Prompt-Hook-Fires-Once". 6 regression tests in `tests/test-prompt-hook-fires-once.sh` cover the instrumentation contract (counter increments, opt-in semantics, log shape, output stability, error tolerance).

- **Mixed-mode tier (Sonnet 4.6 coder + Opus 4.7 reviewer)** — ROADMAP #233. New `cli/lib/repo-complexity.js` heuristic classifies repos as `simple` or `complex` from filesystem signals (LOC, test count, hook count, workflow count, plus stakes flag for `.env` / `secrets/` / `credentials/`). Setup skill Step 9.5 expanded from binary y/N into a 3-way prompt:
  - **`[N]`** No pin (default, recommended for most repos) — preserves Claude Code auto-mode
  - **`[m]`** Mixed-mode pin `model: "sonnet[1m]"` — suggested for `simple` tier; coder runs on Sonnet, cross-model reviewer always stays at flagship (Opus 4.7 / gpt-5.5 xhigh)
  - **`[f]`** Flagship pin `model: "opus[1m]"` + `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=30` — suggested for `complex` / stakes-flagged tier; current pre-#233 default
  Stakes flag (`.env` / `secrets/` / `credentials/`) forces `complex` regardless of size and detects at any depth (e.g. `config/.env`, `app/secrets/`); the coder is doing security-relevant work and the saving isn't worth the risk. Heuristic outputs are advisory — the user always picks the final tier. New `tests/test-repo-complexity.sh` (11 tests) with six fixture repos (`tests/fixtures/complexity/{simple,complex,stakes,nested-stakes,boundary-simple,boundary-complex}-repo`) covers tier classification, nested stakes detection, threshold-boundary cases (29 tests = simple, 30 = complex), JSON shape, missing-dir error path, and the `npx agentic-sdlc-wizard complexity` CLI subcommand. Cross-model review section in `skills/sdlc/SKILL.md` explicitly notes the reviewer **always** runs at flagship regardless of coder pin — weakening the review leg defeats the savings. Update skill Step 7.5 recognizes `sonnet[1m]` as a valid mixed-mode pin (no migration prompt). Wizard doc gets a new "Mixed-Mode Tier" subsection documenting the split, when to use each tier, the prove-it gate (pair-test on 3+ simple repos before recommending mixed-mode as default), and tradeoffs. **Reconciles with #198:** mixed-mode is opt-in per-project via Step 9.5; no-pin remains the default.

## [1.37.1] - 2026-04-24

### Fixed

- **Dual-channel hook 2× print** (token-bloat audit, ROADMAP item 8, PR #241). When both the project's `.claude/settings.json` AND a locally-installed wizard plugin (`~/.claude/plugins-local/` or `~/.claude/plugins/cache/`) registered the same hook, both fired per event — `SDLC BASELINE` block printed twice per `UserPromptSubmit`, ~300 tokens doubled per prompt. Fix: `dedupe_plugin_or_project()` helper in `hooks/_find-sdlc-root.sh`. Plugin invocation yields if project also registers the same hook by name (project always wins). Wired into all 5 hooks (sdlc-prompt-check, instructions-loaded-check, tdd-pretool-check, model-effort-check, precompact-seam-check). Consumer plugin-only installs still fire normally. Codex 2-round: 100/100 CERTIFIED. 9 new dedupe tests + 1 stale-fixture fix (test_instructions_hook_cwd_walkup now reads current version dynamically from package.json so it doesn't drift past the staleness-nudge threshold on each release).

## [1.37.0] - 2026-04-24

### Changed

- **`monthly-research.yml` workflow deleted** (ROADMAP #231 Phase 1, PR #235). 519 lines + 4 claude-code-action steps removed. Zero merged artifacts in 30d while burning $11-23/month in Anthropic API. Research now happens inline in a Claude Code session, not on a scheduled cron. All 17 `test_monthly_*` assertions in `tests/test-workflow-triggers.sh` stubbed with `n/a per #231 Phase 1` pattern (165/165 tests still green). Live docs (CI_CD.md, ARCHITECTURE.md, plans/AUTO_SELF_UPDATE.md) mark monthly-research REMOVED; historical audit tables intentionally preserved. Codex cross-model review: 3-round, 9/10 CERTIFIED.

- **`model-effort-check.sh` loud WARNING below xhigh** (ROADMAP #217, PR #236). Closed the coherence gap between the docs (`max` preferred, `xhigh` floor) and the hook behavior. Previously the hook treated any effort ≠ xhigh as "upgrade available" — including `max` (the preferred default), which was backwards. New behavior:
  - `effort=max` or `xhigh` → silent (at or above floor)
  - `effort=high/medium/low` or unset → LOUD WARNING block: `WARNING` marker, SDLC compliance mention, `/effort max` primary recommendation, `/effort xhigh` floor alternative, `opus[1m]` model reminder
  - Removed duplicate effort/model check from `instructions-loaded-check.sh` — single source of truth is now `model-effort-check.sh`. Regression test asserts the dupe doesn't come back.
  - 2 new TDD tests + 1 regression test. Updated `test_hooks_recommend_opus_1m_alias` for single-source-of-truth. 119/119 hook tests pass.
  - Codex cross-model review: 3-round, 10/10 CERTIFIED.

### Roadmap

- **#232 added**: `/update-wizard` should mimic `claude update` UX — detect stale npm CLI and offer to refresh before applying in-session file updates. User call-out 2026-04-24.

### Removed

- `.github/workflows/monthly-research.yml` (519 lines, 4 claude-code-action steps, 0 merged artifacts in 30d).

## [1.36.1] - 2026-04-23

### Changed

- **Repo renamed `agentic-ai-sdlc-wizard` → `claude-sdlc-wizard`.** Matches sibling pattern (`codex-sdlc-wizard`, future `opencode-sdlc-wizard`). GitHub auto-redirects old URLs for git + web. **npm package name unchanged** (`agentic-sdlc-wizard`) — brand-neutral, safer re: Anthropic trademark guidelines, and avoids disruptive npm rename.
- **Slug migration across docs/tests/configs.** All repo-internal references to the old slug updated: `README.md`, `CLAUDE_CODE_SDLC_WIZARD.md`, `CONTRIBUTING.md`, `ROADMAP.md`, `package.json` `repository.url`, raw GitHub URL fetches in `tests/test-self-update.sh`, CI workflow references. GitHub handles the redirect transparently but keeping internal references in sync prevents future drift.
- **`npm pkg fix` applied to `package.json`.** Normalizes `bin` path (drops leading `./`), `repository.url` form (`git+https://...`). Resolves `npm warn` messages surfaced during v1.36.0 publish.

### Process

- Codex cross-model review on the slug-migration + `npm pkg fix` PR.
- Release workflow `workflow_dispatch` fallback added in v1.36.0 via PR #221 proved its worth on v1.36.0 publish (tag-push trigger didn't fire; manual dispatch unblocked). Kept as permanent safety net.

## [1.36.0] - 2026-04-23

### Added

- **Regression test: every ci.yml `steps.X.outputs.Y` reference must resolve** (#214 / ROADMAP #215). Python+PyYAML test walks ci.yml, builds per-job map of step_id → emitted outputs (handles `NAME=val` and heredoc `NAME<<EOF`), and flags any dead gate. Caught #215's original bug and guards against re-introduction.
- **Regression test: no `oven-sh/setup-bun` in workflows** (#217 / ROADMAP #210). Defensive guard against Node 20 deprecation reintroduction. Committed negative control writes a tmp fixture with the banned pattern, asserts grep catches it, tears down — proves the regex is live-fire correct.
- **ROADMAP #218** — evaluate CC 2.1.118 `type: "mcp_tool"` hook capability (Prove-It gated).
- **ROADMAP #219** — re-verify #198 model-pin guidance against CC 2.1.117 restart-persistence behavior.
- **ROADMAP #220** — token-spike anomaly detection (from Anthropic 2026-04-23 post-mortem).
- **ROADMAP #221** — fold post-mortem lessons into wizard docs (explicit effort / extended-thinking+caching+idle gotcha / verbosity-cap audit).
- **ROADMAP #222** — prompt-compounding audit harness (A/B each of ~40 prompt-injection sites).
- **ROADMAP #223** — adopt GPT-5.5 in review-tier guidance after calibration (standard $5/$30 is Codex-usable ceiling; Pro $30/$180 is ChatGPT-only, reserve for release-blocker one-offs).

### Fixed

- **Tier 2 persist-scores dead gate** (#214 / ROADMAP #215). The Tier 2 "Persist scores to PR branch" step was gated on `steps.check-baseline.outputs.should_simulate`, but the Tier 2 `check-baseline` only emits `has_baseline`. The step had been silently dead, so `score-history.jsonl` never got appended from Tier 2 runs. One-word fix (`should_simulate` → `has_baseline`) plus the new cross-job output-parser regression test.
- **`score-history.jsonl` `max_score` correctness** (#216 / ROADMAP #211). Both Tier 1 and Tier 2 hardcoded `--argjson max_score 10`, causing UI scenarios (which score out of 11 via design_system bonus) to record `11/10` — nonsensical and breaking downstream analytics. Both sites now read `MAX_SCORE` from the eval result file; shell `case` statement guards non-numeric inputs; regression test grep-asserts no hardcoded literal remains.
- **CC 2.1.118 `/cost` → `/usage` doc rename** (#209). Claude Code 2.1.118 consolidated `/cost` and `/stats` into `/usage` with aliases preserved. Wizard docs and test-self-update now use `/usage` as canonical (alias note inline).

### Docs

- Roadmap entries for all additions above (#218-223), plus minor wording correction to #221(c) post-Codex review (attributes 3% drop to broader length-limit prompt change, not a single sentence).

### Process

- Codex cross-model review run on every PR in the v1.36.0 batch (3 code PRs: 10/10 + 10/10 + 8/10; 4 doc/roadmap PRs: 10/10 + 10/10 + 7/10→fixed + 9/10). Shepherd-loop discipline re-enforced after a process miss mid-cycle — logged as feedback memory `feedback_shepherd_loop_per_pr.md`.

## [1.35.0] - 2026-04-19

### Added

- **PreCompact seam gate** (#205 / ROADMAP #208). New `hooks/precompact-seam-check.sh` blocks manual `/compact` when `.reviews/handoff.json` status is `PENDING_REVIEW`/`PENDING_RECHECK` or a git rebase/merge/cherry-pick is in flight. Matcher is `manual` — auto-compact is deliberately NOT gated (blocking it could push past 100% context). Requires Claude Code v2.1.105+. 10 quality tests.
- **Self-healing PreCompact** (#206 / ROADMAP #209). Hook now treats a stale `PENDING_*` handoff as implicit `CERTIFIED` when optional `pr_number` field is present and `gh pr view <N>` reports `MERGED`. Fixes the "forgot to flip status to CERTIFIED after merge" consumer bug. Graceful fallback: if `pr_number` absent, `gh` missing, offline, or any error → existing block behavior. 4 new quality tests with mocked `gh` binary.
- **Dynamic effort auto-bump hook** (#202 / ROADMAP #195). `sdlc-prompt-check.sh` scans `UserPromptSubmit` payload for LOW-confidence / FAILED-repeatedly / CONFUSED phrases and logs a timestamped signal. At ≥2 recent signals in a 30-min window, emits a loud `!! EFFORT BUMP REQUIRED !!` block with the exact `/effort xhigh` command. 8 quality tests.
- **Loud staleness nudge** (#201 / ROADMAP #196). `instructions-loaded-check.sh` now caches npm-latest for 24h and prints a loud multi-line warning when the installed wizard is ≥3 minor versions behind. 1–2 minor keeps the existing mild one-liner.
- **Session-start CC auto-update nudge** (#192 / ROADMAP #85). Instructions-loaded hook queries for open auto-update PRs and nudges the user to review before compacting.
- **Hook token-cost caps** (#203). 4 new size-cap tests across every hook. Negative control injects echo bloat to prove the caps trip.
- **Permissions allowlist** (#204). Top read-only tools pre-approved in `.claude/settings.json` to cut permission prompts during automation.
- **Codex-audit-on-CI-logs shepherd step** (docs). SDLC skill now requires running `codex exec xhigh` against both Tier 1 and Tier 2 CI logs separately — catches silent failures, degraded metrics, and warnings-promoted-to-errors that the green checkmark hides. Dogfooded on PR #206: caught 4 P1s in pre-existing CI infra (tracked as ROADMAP #210, #211, #215 + regression of #93).

### Fixed

- **CI persist-to-PR-branch race** (#196 / ROADMAP #193). Tier 2 no longer aborts the whole run on a single low-score trial; records the trial instead.
- **Setup wizard `allowedTools` → `permissions.allow`** (#200 / ROADMAP #197). CC v2.1 renamed the field; setup template updated.
- **Setup wizard `opus[1m]` opt-in** (#199 / ROADMAP #198). Default no longer force-pins; respects explicit user choice.
- **SessionStart hook model-field absence** (#180 / commit 3b23860). Model isn't exposed in SessionStart payload; hook now detects effort-only.

### Docs

- Memory lessons promoted (#194): tier2 exit-code pattern + pipeline liveness.
- Community paths (#191 / ROADMAP #98): issue + PR templates + Discussions enabled.
- ROADMAP backlog filed this cycle: #210 (Node 24 false-green), #211 (Tier 1 "11/10" score), #212 (local-Max E2E), #213 (ship degradation env vars by default — blocked on #214), #214 (adaptive-thinking A/B Prove-It), #215 (Tier 2 persist dead code), #216 (repo rename).

## [1.34.0] - 2026-04-17

### Added
- Memory Audit Protocol for promoting private-memory lessons to shared docs (#189)
  - New `/sdlc` subsection under "After Session (Capture Learnings)" defines a three-bucket classifier (`promote` / `keep` / `manual-review`) with a rule-based privacy denylist (`type: user`/`reference` → keep, `project`/`feedback` → manual-review)
  - YAML frontmatter parser in `tests/test-memory-audit-protocol.sh` normalizes inline comments, quoted values, and whitespace so variants like `type: "user" # external` still route to keep
  - `SDLC.md` now has a `## Lessons Learned` section seeded with 7 verified technical gotchas (GH CLI stdout, `workflows` YAML scope, GITHUB_TOKEN workflow triggers, GHA `${{ }}` backtick substitution, macOS bash 3.x, stderr/stdout separation for JSON parsing, `continue-on-error` + `||` masking); each entry cites its originating PR or incident date and was re-verified with a runnable repro before promotion
  - 10-fixture corpus at `tests/fixtures/memory-audit-corpus/` (6 promote / 2 keep / 2 manual-review) with `test_expected` frontmatter seeds the future LLM-gated quality runner
  - 12-test protocol suite covers structure, rule-based denylist, YAML-variant hardening, corpus consistency (promote fixtures route to manual-review under rule-based), and corpus shape
  - Codex xhigh 3-round code review: 4/10 → 8/10 → 10/10 CERTIFIED. Caught two false lessons in private memory (`${3:-{}}` brace-default claim and `--argjson result` jq-conflict claim) that were retracted with dated strikethroughs — the protocol's first real use prevented its own false claims from shipping
  - CLI distributes skill updates + new SDLC.md section; CI wire-up in `.github/workflows/ci.yml` (validate job)
- API feature detection shepherd for Claude API release notes (#100, PRs #184, #186, #187)
  - LLM-free weekly detector at `.github/workflows/weekly-api-update.yml` polls `platform.claude.com/docs/en/release-notes/api.md`
  - `scripts/parse-api-changelog.py` parses ATX date headers with ordinal-date normalizer and bullet-summary capture (non-date sub-headers like `#### SDKs` no longer terminate bullet extraction); 200-char truncation with ellipsis; tab scrub
  - `scripts/persist-api-state.sh` writes last-seen date with branch-protection-safe non-blocking push; opens/updates a single `api-review-needed` tracking issue with enriched bullet summaries (not just dates)
  - `instructions-loaded-check.sh` nudges at session start when open issues exist; gated on local workflow presence so consumer forks see only their own detector's issues
  - 33 tests including 8 fixture-based parser tests (bullet capture, subheader boundary, tab scrub, truncation, ordinal dates) and 2 integration tests
  - Codex xhigh 5 rounds across 2 PRs: 9/10 CERTIFIED. Found-in-prod P0 hotfix in #187 — `gh api` writes JSON error bodies to stdout (not stderr), so the label-create `already_exists` check was broken after the first successful dispatch; pattern now captures both streams

### Fixed
- `gh api` error handling in `weekly-api-update.yml` now captures stdout+stderr together for `already_exists` detection on label creation (#187). Added as portable lesson in `SDLC.md` Lessons Learned

### Docs
- `/less-permission-prompts` Claude Code native skill surfaced in wizard and setup documentation (#183)
- README community section restyled with visual Discord badge for Automation Station

## [1.33.0] - 2026-04-17

### Added
- `opus[1m]` as the SDLC wizard default model (#182)
  - CLI template ships `"model": "opus[1m]"` + `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=30` (tuned for 1M — compacts at ~300K)
  - `cli/init.js` `mergeSettings` merges top-level `model` on fresh installs and when absent; respects user's explicit choice; `--force` overwrites
  - Wizard doc "1M vs 200K Context Window" section flipped to recommend `opus[1m]` as default; pricing framed as "verify current rates at docs.anthropic.com" (no stale tier-specific claims)
  - `/sdlc` skill: new "Recommended Model" section between auto-approval and Confidence Check
  - `/setup` skill Step 9.5: 1M default, 200K fallback (inverted from before)
  - SDLC.md baseline bumped to v2.1.111+ (Opus 4.7 minimum)
  - Session-start hooks now recommend `opus[1m]` alias (matches the `/model` command users run)
  - 9 new tests (5 CLI model merge, 4 doc consistency); 6 existing autocompact tests updated to expect `30`, fixtures bumped to `50` in tests 37/38 to preserve the no-overwrite proof
  - Codex xhigh 2-round review: 9/10 CERTIFIED
- Dual-channel install drift guardrails (#181)
  - `cli/init.js` detects plugin install paths (`~/.claude/plugins-local/sdlc-wizard-wrap/`, `~/.claude/plugins/cache/sdlc-wizard-local/`) and blocks init with a typed `err.pluginPaths` error; `--force` bypasses
  - `instructions-loaded-check.sh` non-blocking nudge when both CLI skills and Claude plugin are present in the same project
  - HOME isolation in test files (`mktemp -d` + `trap` cleanup) prevents dev-machine HOME from leaking into assertions
  - `path.isAbsolute(home)` guard in `detectPluginInstall` — empty/relative HOME no longer causes false-positive block
  - `run_init_split` test helper captures stdout/stderr separately with explicit exit code
  - 9 new CLI tests, 5 new hook tests; Codex xhigh 4-round review: 9/10 CERTIFIED
- Model/effort upgrade detection at session start (#179, #180)
  - SessionStart hook nudges when configured `effortLevel` is below `xhigh` (wording superseded by #217 on 2026-04-24: `max` preferred, `xhigh` floor)
  - Reads `.claude/settings.local.json` → `.claude/settings.json` → `$HOME/.claude/settings.json` precedence
  - Non-blocking (`exit 0`); asks Claude to compare recommended model against its own system prompt
  - `claude-opus-4-6` defaults bumped to `claude-opus-4-7` in `pr-review.yml`, `evaluate.sh`, `sdp-score.sh`, `pairwise-compare.sh`
  - Hook added to `SDLC.md` hooks table + CLI distributes `model-effort-check.sh`

### Fixed
- `cli/bin/sdlc-wizard.js` double-print: plugin-detect errors now suppress the outer `"Error:"` prefix since detection streams its own colored guidance block (#181)

## [1.32.0] - 2026-04-16

### Added
- Opus 4.7 support in benchmark workflow (#178)
  - `claude-opus-4-7` added to model choices, `effort` input (high/xhigh/max)
  - `--effort` passed via `claude_args`, effort recorded in artifacts + summaries
  - Hard-fail when xhigh used with non-4.7 models (inputs resolved before shell)
  - Artifact names include effort level to prevent collision
  - Default: opus-4-7 + xhigh (matches CC's new default)
  - 3 new tests (39 total model-comparison tests)
- `xhigh` effort level documented in wizard (#178)
  - New effort table: high → xhigh → max (xhigh was called "recommended for coding" here; superseded by #217 on 2026-04-24: `max` is preferred, `xhigh` is the floor)
  - Opus 4.7 changes: stricter effort adherence, budget_tokens deprecated, 64k+ max_tokens guidance
- Benchmark ceiling effect audit documented in wizard
  - Cross-model audit (Codex GPT-5.4, xhigh) rated benchmark 2/10 NOT CERTIFIED
  - 4 P0 findings: fake trials, answer key leaked, no independent verification, binary rubric
  - 3 concrete fixes documented (remove coaching, add correctness scoring, real trials)
  - External benchmark comparison (SWE-Bench, Aider methodology)
- Automation Station community Discord link in README

### Fixed
- Orphaned `skills/gdlc/` causing test-doc-consistency failures (deleted)

## [1.31.0] - 2026-04-14

### Added
- Ephemeral marketplace path detection in CLI `check` command (#174)
  - Scans `~/.claude/settings.json` `extraKnownMarketplaces` for directory sources on ephemeral paths (`/tmp/`, `/private/tmp/`, `/var/folders/`)
  - `EPHEMERAL` status (path exists but in ephemeral root) warns but doesn't fail check
  - `DANGLING` status (path doesn't exist) errors with non-zero exit code
  - Suggests moving to `~/.claude/plugins-local/<name>` for stable installs
  - JSON output (`--json`) includes new `marketplace` field
  - 10 new tests (51 total CLI tests)

### Fixed
- Hook false-positive "SETUP NOT COMPLETE" in non-SDLC directories (#173, PR #175)
  - Three-way detection: both files (normal), one file (warn partial setup), neither (silent exit)
  - Added `find_partial_sdlc_root` helper for partial-setup detection
  - 2 new hook tests (60 total hook tests)

## [1.30.0] - 2026-04-12

### Added
- CC degradation detection (#96, PR #166)
  - Score persistence: CI now git-commits `score-history.jsonl` to PR branch after E2E runs, feeding CUSUM drift detection with real data
  - Fork guard (`head.repo.full_name == github.repository`) prevents silent push failures on fork PRs
  - Injection-safe: `head.ref` passed via `env:` block, not inline `${{ }}`
  - Wizard effort section hardened: explains adaptive thinking root cause (Boris Cherny GH #42796), scopes "medium default" to Pro/Max plans, cites code.claude.com docs
  - `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` documented as opt-in hardening (not default)
  - Anti-laziness CLAUDE.md guidance section targeting specific mechanisms (adaptive thinking, effort levels, thinking budget)
  - 14 behavioral tests (`test-degradation-detection.sh`)
- Model A/B comparison workflow (#94, PRs #164, #165)
  - `workflow_dispatch` benchmark: Opus vs Sonnet on E2E scenarios with 95% CI
  - Matrix strategy over scenarios, parameterized model/trials/max_turns
  - Wizard installation verification before simulation (P0 fix)
  - jq-based artifact construction (safe against empty outputs)
  - 37 quality tests (`test-model-comparison.sh`)
- Firmware-embedded E2E fixture (#78, PR #163)
  - Python SD card overlay manager, 3 device configs (Raspberry Pi, STM32, ESP32)
  - SIL + config validation tests within fixture
  - Domain-adaptive testing proof: firmware indicators, Python overlay, multi-device differentiation
  - 12 quality tests (`test-firmware-fixture.sh`)

### Fixed
- P0 shell injection in model comparison workflow: `${{ inputs.model }}` directly in `run:` blocks. Fixed by passing all inputs through `env:` block (caught by Codex review)

## [1.29.0] - 2026-04-07

### Added
- Node 24 compliance across all GitHub Actions workflows (#93, PR #160)
  - 5 action version bumps: checkout@v5, setup-node@v5, upload-artifact@v6, create-pull-request@v8, sticky-pull-request-comment@v3
  - 2 third-party actions replaced with `gh` CLI: `int128/hide-comment-action` → GraphQL `minimizeComment`, `softprops/action-gh-release` → `gh release create`
  - 4 node-version bumps from 20 to 22
  - 13 new compliance regression tests (`test-node24-compliance.sh`)
  - Expression injection P0 in release.yml caught by CI reviewer and fixed
- Autocompact env var in settings.json (#88, PR #161)
  - CLI now ships `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75` in `settings.json` `env` field (200K default)
  - Smart merge preserves existing user env vars on upgrade; `--force` resets to defaults
  - Handles malformed env values (arrays, strings) gracefully with type validation
  - Setup wizard Step 9.5 references settings.json instead of shell profiles; 1M users guided to 30%
  - 9 new tests (41 total CLI tests)
- Effectiveness scoreboard (#80, PR #162)
  - `.metrics/catches.jsonl`: 52 historical bug catches extracted from repo history
  - `catch-analytics.sh`: DDE (Defect Detection Effectiveness) per layer, escape rates, severity breakdown
  - Results: cross-model-review (48%) and self-review (46%) nearly tied; self-review missed 28 bugs caught downstream; all 3 P0s caught by cross-model or CI review
  - 14 new quality tests (`test-effectiveness-scoreboard.sh`)
  - Log automation deferred until analytics proven useful (prove-it gate)

### Fixed
- Expression injection in `release.yml`: `${{ github.ref_name }}` directly in `run:` shell command allowed tag-based code injection. Fixed by passing through `TAG_NAME` env var (P0, caught by CI reviewer)
- `$TOTAL_` variable name collision in `catch-analytics.sh`: bash parsed as undefined variable `TOTAL_` instead of `$TOTAL` + underscore. Fixed with `${TOTAL}_` brace syntax (P0, caught by CI reviewer)

## [1.28.0] - 2026-04-06

### Added
- Autocompact benchmarking methodology — first rigorous framework for testing `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` thresholds (#92, PR #158)
  - `AUTOCOMPACT_BENCHMARK.md`: experimental design, canary fact mechanism, cost estimation, limitations
  - `tests/benchmarks/run-benchmark.sh`: parameterized harness with `--dry-run`, threshold validation, multi-turn session via `--resume`
  - `tests/benchmarks/analyze-results.sh`: statistical comparison tables using `stats.sh`
  - 3 task files (short/medium/long) with canary fact injection for context preservation measurement
  - `canary-facts.json`: 5 domain-independent facts for binary recall scoring with negation detection
  - `.github/workflows/benchmark-autocompact.yml`: `workflow_dispatch` with matrix strategy across thresholds
  - 26 quality tests proving methodology rigor, harness behavior, and research standards

### Changed
- README bio: reflects full-stack founding engineer background (not just SDET/QA)
- Wizard doc autocompact section references benchmarking methodology
- Workflow count updated (5→6) across README and CI

## [1.27.0] - 2026-04-05

### Added
- Domain-adaptive testing diamond — setup wizard auto-detects project domain (firmware/data-science/CLI/web) and generates domain-specific TESTING.md with appropriate testing layers (#79, PR #157)
  - Firmware/Embedded: HIL/SIL/Config Validation/Unit (no browser, no DB)
  - Data Science: Model Evaluation/Pipeline Integration/Data Validation/Unit
  - CLI Tool: CLI Integration/Behavior/Unit (no browser)
  - Web/API: unchanged default (E2E/Integration/Unit)
- Domain detection patterns in wizard doc scan tree and setup skill Step 1/2/6
- 3 new test fixtures: firmware-embedded, data-science, cli-tool (partially satisfies #78)
- 25 domain detection quality tests

### Fixed
- Setup skill cross-references: Step 4/5 now correctly reference wizard doc Steps 8/9 (caught by CI PR review)

## [1.26.0] - 2026-04-05

### Added
- Codex SDLC Adapter plan — certified (9/10) through 5-round cross-model review. `BaseInfinity/codex-sdlc-wizard` repo created with plan + README. Upstream sync architecture designed (weekly GH Action monitors sdlc-wizard releases). Hooks: PreToolUse `^Bash$` for git commit/push blocking (HARD — stronger than CC), AGENTS.md for TDD guidance (SOFT), UserPromptSubmit for SDLC baseline. ~70% CC parity (#91)
- Research: claw-code, OmO, OmX pattern analysis — 16 candidate patterns identified from 3 open-source AI agent projects (claw-code 168K stars, OmO 48K, OmX 16K). Key findings: GreenContract graduated test levels, $ralph bounded persistence loop, planning gate enforcement, planner/executor separation. All candidates require Prove It Gate before adoption. Codex certified 8/10 round 3 (#58)
- Automated CC Feature Discovery verified working — weekly-update.yml already implements this via analyze-release.md (#85)

### Changed
- Roadmap: #79 (Domain-Adaptive Testing) and #92 (Autocompact Benchmarking) queued for next release
- Research doc: `RESEARCH_58_CLAW_OMO_OMX.md` added as reference (candidates list, not commitments)
- Codex adapter plan: `CODEX_ADAPTER_PLAN.md` added with full specs (hooks, scripts, tests, install flow)

## [1.25.0] - 2026-04-04

### Added
- Claude Code plugin format — single source of truth: `skills/` and `hooks/` at repo root serve plugin + CLI. `.claude-plugin/plugin.json` manifest, `hooks/hooks.json` with `${CLAUDE_PLUGIN_ROOT}`, `.claude-plugin/marketplace.json` for self-hosted marketplace. Absorbs #66 + #87 (#89)
- 6 distribution channels — npm, plugin, curl install script, Homebrew tap, gh CLI extension, GitHub Releases (#90)
- `install.sh` curl-pipeable installer — download guard, strict mode, Node.js >= 18 check, `--global` flag, terminal-aware colors. 20 tests (structural + integration)
- `.github/workflows/release.yml` — tag-push automation with npm publish --provenance (SLSA), GitHub Release via softprops/action-gh-release@v2. 14 tests
- External repos: `BaseInfinity/homebrew-sdlc-wizard` (Homebrew tap), `BaseInfinity/gh-sdlc-wizard` (gh CLI extension)
- 25 plugin format tests, 34 distribution tests (20 install + 14 release workflow)

### Fixed
- CI shepherd: enforce reading CI logs on pass AND fail (not just failures). Pre-release CI audit across merged PRs added to release planning gate

### Changed
- CLI `init.js` reads skills/hooks from repo root (single source, no duplication)
- Dogfood `.claude/` uses symlinks to root skills/hooks
- README: added curl, Homebrew, gh extension, GitHub install methods
- CI_CD.md: added release.yml documentation + NPM_TOKEN secret

## [1.24.0] - 2026-04-04

### Added
- Hook `if` conditionals — CC v2.1.85+ `if` field on PreToolUse hook. TDD check only spawns for source files (repo: `.github/workflows/*`, template: `src/**`). Documented in wizard CC features section with matcher-vs-if comparison table (#68)
- Autocompact tuning guidance — `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` and `CLAUDE_CODE_AUTO_COMPACT_WINDOW` env vars with community-recommended thresholds (75% for 200K, 30% for 1M). 1M vs 200K context window comparison table. Setup wizard Step 9.5 for context window configuration (#88)
- 6 hook tests for `if` field (52 total hook tests)
- 5 autocompact/context tests (70 total self-update tests)

### Fixed
- E2E tdd_red detection — three bugs since inception: test-only scenarios scored 0 (missing elif branch), golden outputs were .txt not JSON, golden-scores.json encoded the bug it was meant to catch. Codex cross-model review caught regex false-positive + missing JSON pairing (#86)
- 29 deterministic + 9 regression tests for tdd_red fix

## [1.23.0] - 2026-04-01

### Added
- Update notification hook — `instructions-loaded-check.sh` checks npm for newer wizard version each session. Non-blocking, graceful on network failure. One-liner: "SDLC Wizard update available: X → Y (run /update-wizard)" (#64)
- Cross-model review standardization — mission-first handoff (mission/success/failure fields), preflight self-review doc, verification checklist, adversarial framing, domain template guidance, convergence reduced to 2-3 rounds. Audited 4 repos + 14 external repos + 7 papers (#72, #56)
- Release Planning Gate — section in SDLC skill. Before implementing release items: list all, plan each at 95% confidence, identify blocks, present plans as batch. Prove It Gate strengthened with absorption check (#73)
- 6 quality tests for update notification (fake npm in PATH, version comparison, failure modes)
- 12 quality tests for cross-model review, context position, release planning
- Testing Diamond boundary table — explicit E2E (UI/browser ~5%) vs Integration (API/no UI ~90%) vs Unit (pure logic ~5%) in SKILL.md and wizard doc (#65)
- Skill frontmatter docs — expanded to full table covering `paths:`, `context: fork`, `effort:`, `disable-model-invocation:`, `argument-hint:` (#69)
- `--bare` mode documentation in SKILL.md — complete wizard bypass warning for scripted headless calls (#70)
- 6 quality tests for #65/#69/#70
- "NEVER AUTO-MERGE" enforcement gate in CI Shepherd section — same weight as "ALL TESTS MUST PASS." Full shepherd sequence documented as mandatory (post-mortem from PR #145 incident)
- Post-Mortem pattern — when process fails, feed it back: Incident → Root Cause → New Rule → Test → Ship. "Every mistake becomes a rule"
- 4 quality tests for enforcement gate + post-mortem

### Fixed
- Dead-code pipe in `test_prove_it_absorption()` — `grep -qi | grep -qi` was a no-op (P1 from PR #145 CI review)

### Changed
- Moved "ALL TESTS MUST PASS" from 61% depth to 11% depth in SDLC skill (Lost in the Middle fix) (#57)
- Prove It Gate now requires absorption check — "can this be a section in an existing skill?" — before proposing new skills/components
- Wizard "E2E vs Manual Testing" section replaced with "E2E vs Integration — The Critical Boundary" (#65)
- Wizard "Skill Effort Frontmatter" section expanded to "Skill Frontmatter Fields" with full field reference (#69)

## [1.22.0] - 2026-04-01

### Added
- Plan Auto-Approval Gate — skip plan approval when confidence >= 95% AND task is single-file/trivial. Still announces approach, just doesn't wait. "When in doubt, wait for approval" (#53)
- Debugging Workflow section — systematic Reproduce → Isolate → Root Cause → Fix → Regression Test methodology. `git bisect` for regressions, environment-specific debugging guidance (#55)
- `/feedback` skill — privacy-first community contribution loop. Bug reports, feature requests, pattern sharing, SDLC improvements. Never scans without explicit consent. Creates GH issues on wizard repo (#37)
- BRANDING.md detection in setup wizard — scans for brand/, logos/, style-guide.md, brand-voice.md. Conditional generation only when branding assets found (#44)
- N-Reviewer CI Pipeline guidance — address each reviewer independently, resolve conflicts, max 3 iterations per reviewer (#32)
- Custom Subagents documentation — `.claude/agents/` pattern for sdlc-reviewer, ci-debug, test-writer agents. Skills vs agents comparison (#45)
- CLI distributes `/feedback` skill (9 template files, was 8)
- Improved CLI install restart messaging — `--continue` promoted as primary option for preserving conversation history
- 20 new tests across all 6 roadmap items

### Changed
- SDLC skill: added Auto-Approval, Debugging Workflow, Multiple Reviewers, Custom Subagents sections
- Setup skill: added branding asset detection (Step 1) and BRANDING.md generation (Step 8.5)
- Wizard doc: added Plan Auto-Approval, Debugging Workflow, N-Reviewer Pipeline, Custom Subagents, BRANDING.md template

## [1.21.0] - 2026-03-31

### Added
- Confidence-driven setup wizard — kills the fixed 18 questions. Scans repo, builds confidence per data point, only asks what it can't infer. Dynamic question count (0-2 for well-configured projects, 10+ for bare repos). 95% aggregate confidence threshold (#52)
- CI Shepherd opt-in question in setup wizard (#48 partial)
- Cross-model release review recommendation — releases/publishes as explicit trigger, Release Review Checklist with v1.20.0 evidence (#49)
- Prove It Gate enforcement in SDLC skill — prevents unvalidated additions with quality test requirements (#50)
- 6 confidence-driven setup tests, 10 prove-it-gate tests, 6 release review tests

### Removed
- ci-analyzer skill — violated Prove It philosophy (existence-only tests, no quality validation, overlap with `/claude-automation-recommender`) (#50)
- ci-self-heal.yml deprecated — local shepherd is the primary CI fix mechanism

### Changed
- Wizard doc: Q-numbered questions → data point descriptions with detection hints
- Setup skill: 12 steps (was 11) with new "Build Confidence Map" step
- CLI distributes 8 template files (was 9, removed ci-analyzer)

## [1.20.0] - 2026-03-31

### Added
- CC version-pinned update gate — E2E tests run actual new CC version, not bundled binary (#46)
- Tier 1 E2E flakiness fix — regression threshold 1.5→3.0, absorbs ±2-3 point LLM variance (#47)
- Flaky test prevention guidance with external reference in wizard, SKILL.md
- 2 release consistency tests (package.json ↔ CHANGELOG ↔ SDLC.md version parity)

## [1.19.0] - 2026-03-31

### Added
- CI Local Shepherd Model — two-tier CI fix model (shepherd primary, bot fallback), SHA-based suppression (#36)
- Gap Analysis vs `/claude-automation-recommender` — complementary tools positioning (#35)
- `/clear` vs `/compact` context management guidance (#38)
- Token efficiency auditing — `/cost`, `--max-budget-usd`, OpenTelemetry (#42)
- Blank repo support — verified clean install, 10 new E2E tests (#31)
- Feature documentation enforcement — ADR guidance, `claude-md-improver`, doc sync in SDLC (#43)
- Setup skill description trimmed to 199 chars (v2.1.86 caps at 250)

## [1.18.0] - 2026-03-30

### Added
- `/update-wizard` skill — guided update with changelog diff, per-file comparison, selective adoption
- `step-update-wizard` in wizard step registry
- CLI distributes `skills/update/SKILL.md` (now 8 managed files)
- `/update-wizard` reference in wizard "How to Update" section

## [1.17.0] - 2026-03-30

### Fixed
- Setup skill now force-reads entire wizard doc before proceeding (was just "Reference")
- README no longer tells users to manually invoke setup — hooks auto-invoke
- 3 new tests for setup auto-invoke behavior

### Changed
- Testing consolidation: `/testing` skill merged into `/sdlc` (#28)

## [1.16.0] - 2026-03-29

### Added
- Cross-model review dialogue protocol — structured FIXED/DISPUTED/ACCEPTED negotiation loop (#40)
- P0/P1/P2 severity rubric in PR review prompt (#34)
- Effort level recommendations in wizard
- 5 enforcement gap fixes in TodoWrite checklist (#39)

## [1.15.0] - 2026-03-25

### Added
- aistupidlevel.info as Source 3 in external benchmark cascade (DailyBench -> LiveBench -> aistupidlevel -> baseline)
- Competitive watchlist in `analyze-community.md` — weekly scan now checks 5 named repos for new releases/patterns
- `COMPETITIVE_AUDIT.md` — honest ecosystem comparison, unique strengths, tracked gaps, contribution ideas
- README "How This Compares" section with honest positioning table
- Token usage tracking gap documented (blocked until `claude-code-action` exposes usage data)
- 3 new tests in `test-external-benchmark.sh` for aistupidlevel integration
- 2 new tests in `test-prove-it.sh` for competitive watchlist and README positioning

### Changed
- Roadmap reordered: competitive audit (#10) marked DONE

## [1.14.0] - 2026-03-24

### Fixed
- CI re-trigger bug: `workflow_dispatch` caused `e2e-quick-check` to skip, blocking auto-merge (PR #75). Jobs now accept dispatch events with simulation steps gated behind PR-only checks
- SDLC.md version stuck at 1.9.0 (should be 1.14.0)
- CONTRIBUTING.md missing 11 test scripts, outdated scoring criteria, wrong repo URL in discussions link

### Added
- 3 tests in `test-workflow-triggers.sh`: verify required CI jobs accept `workflow_dispatch`
- 4 integration tests in `test-prove-it.sh`: prove `compare_ci` detects REGRESSION/STABLE/IMPROVED with synthetic scores
- 3 E2E tests in `test-self-update.sh`: verify live CHANGELOG and wizard URLs return valid content
- `should_simulate` gate in CI: dispatch runs produce green checks without burning API credits
- Documented `workflow_dispatch` behavior in `ci-self-heal.yml`

### Changed
- Roadmap reordered: competitive audit (#10) before distribution (#30)
- CONTRIBUTING.md scoring criteria updated to v3 multi-call judge + v3.1 pairwise tiebreaker
- CONTRIBUTING.md test list updated to all 21 CI validate scripts

## [1.13.0] - 2026-03-23

### Changed
- Rewrote "Staying Updated" section with explicit fetch URLs, CHANGELOG-first update flow, and 4-phase process
- Claude now shows users what changed (via CHANGELOG) before offering to apply updates
- Fixed "CHANGELOG is for Humans, Not Claude" — Claude reads CHANGELOG first to drive the update flow

### Added
- Optional "Wizard Update Notification" GitHub Action template — weekly check, creates issue when newer version exists ($0 cost, no API key)
- `step-update-notify` in wizard step registry (optional step for CI notification)
- 12 new tests in `tests/test-self-update.sh` (URL correctness, YAML validation, workflow template, step registry)

## [1.12.0] - 2026-03-23

### Fixed
- Apply step in `weekly-update.yml` and `monthly-research.yml` never propagated changes to test fixture (baseline == candidate, verdict always STABLE, comparison useless)
- Stale output file between baseline and candidate simulations in both auto-update workflows (same bug as ci.yml, fixed in #24)
- `sdp-score.sh` default model `claude-sonnet-4` corrected to `claude-opus-4-6` (matches evaluate.sh)
- README "All 6 workflows" corrected to "All 5 workflows" (stale since v1.9.0 consolidation)

### Added
- 6 new audit tests: apply step propagation (2), stale output cleanup (2), SDP model consistency (1), README accuracy (1)
- Native CC feature overlap analysis: all 5 custom features audited — KEEP CUSTOM (no overlap with CC v2.1.81)

### Audited (no changes needed)
- All 5 custom features (hooks + skills): value is in content (SDLC philosophy, TDD enforcement), not framework
- Noted for future: `continue-on-error` patterns, `/tmp` hardcodes, permission scoping

## [1.11.0] - 2026-03-23

### Fixed
- Stale output file between baseline and candidate simulations in Tier 2 (candidate eval could read baseline data on silent failure)
- Comment "3x evaluations" corrected to "5x evaluations" in ci.yml Tier 2 header
- `run-tier2-evaluation.sh` silent `score=0` fallback replaced with proper error handling (stderr separation, exit on failure)

### Added
- 13 test scripts wired into CI validate job (228 additional tests now run on every PR)
- Tests for Tier 2 comment accuracy and stale output cleanup
- Tests for `run-tier2-evaluation.sh` error handling (no stderr suppression, no silent fallback)

### Removed
- Legacy duplicate `tests/test-self-heal-simulation.sh` (690 lines, subset of e2e version)

## [1.10.0] - 2026-03-22

### Added
- "Prove It's Better" CI automation — when weekly-update detects a CC release that overlaps a custom wizard feature, CI auto-runs a side-by-side Tier 2 comparison and recommends KEEP CUSTOM / SWITCH TO NATIVE / TIE
- `tests/e2e/lib/prove-it.sh` — path validation allowlist + fixture stripping library
- `prove-it-test` job in `weekly-update.yml` — only runs when overlap detected ($0 extra on typical weeks)
- Custom feature inventory table in `analyze-release.md` — tells Claude what to check for overlap
- `has_overlap` / `overlap_paths` outputs wired from `check-updates` job
- 13 new tests in `tests/test-prove-it.sh` (allowlist validation, fixture stripping, settings.json updates, overlap signal parsing, workflow integration)
- Test fixture `tests/fixtures/releases/v99.0.0-overlap.json`

## [1.9.1] - 2026-03-22

### Verified
- `all-findings` self-heal (#27): PR #70 confirmed `workflow_run` triggers on review suggestions, `AUTOFIX_LEVEL=all-findings` passes filtering, Claude invoked in `review-findings` mode

### Added
- Real CI review format parsing test (h4 headers, `_None._` italic, line references)
- Roadmap ordering in AUTO_SELF_UPDATE.md

## [1.9.0] - 2026-03-21

### Changed
- Consolidated `daily-update.yml` + `weekly-community.yml` into single `weekly-update.yml`
  - 4 jobs: check-updates, version-test, scan-community, community-e2e-test
  - Single Monday 9 AM UTC schedule (was two separate cron entries)
  - Reduces workflow count from 6 to 5, auto-update workflows from 3 to 2
  - Cost: ~$2.50/week combined (unchanged)
- Updated all docs and 25+ tests to reference `weekly-update.yml`

### Added
- 5 new workflow consolidation tests: 4-job structure, dependency chains, permissions, single cron

## [1.8.1] - 2026-03-21

### Fixed
- `tdd_red` deterministic checker: now parses JSON execution output via jq (was always scoring 0/2 due to regex mismatch with claude-code-action JSON format)
- Score history push: checkout actual PR branch before push (was silently failing from detached HEAD)
- `instructions-loaded-check.sh`: explicit `exit 0` for defensive safety

### Changed
- Phase 5: Re-enabled all auto-update workflow schedules
  - `weekly-update.yml` (formerly `daily-update.yml` + `weekly-community.yml`): Mondays 9 AM UTC
  - `monthly-research.yml`: re-enabled (1st of month 11 AM UTC)
- Golden scores: `high-compliance.tdd_red` updated to 0 (text golden files lack JSON tool_use blocks; tdd_red correctness verified via dedicated JSON unit tests)

### Added
- 7 new tests: JSON-based tdd_red checks (5), empty/nonexistent file edge cases (2)
- 3 new workflow trigger tests: weekly schedule validation, all-schedules-active, score-history-checkout

## [1.8.0] - 2026-03-20

### Added
- Version catch-up: consolidated update from Claude Code v2.1.15 to v2.1.81 (66 minor versions)
- `InstructionsLoaded` hook (`instructions-loaded-check.sh`) — validates SDLC.md and TESTING.md exist at session start (v2.1.69+)
- `effort: high` frontmatter on `/sdlc` and `/testing` skills (v2.1.80+)
- "Prove It's Better" core philosophy — use native features unless custom is proven better via E2E comparison
- Vision statement in README — "Mold an ever-evolving SDLC... replace with native... one day delete this repo"
- Documentation section in README linking ARCHITECTURE.md, CI_CD.md, SDLC.md, TESTING.md, CHANGELOG.md, CONTRIBUTING.md
- Documented new built-in commands in wizard: `/memory`, `/simplify`, `/batch`, `/loop`, `/effort`
- Documented security hardening fixes (v2.1.49, v2.1.72, v2.1.74, v2.1.77, v2.1.78)
- Documented `${CLAUDE_SKILL_DIR}` variable, `agent_id`/`agent_type` hook metadata
- Documented `CLAUDE_CODE_SIMPLE` bypass risk, HTML comment behavior, 128k output tokens, `--bare` flag
- 7 new hook tests (18 total) for InstructionsLoaded hook
- `plans/CATCHUP.md` — documents the version catch-up process for future reference

### Changed
- Claude Code baseline bumped from v2.1.15+ to v2.1.81+
- Wizard version bumped from 1.7.0 to 1.8.0
- Prerequisites updated: minimum v2.1.69+ (was v2.1.16+)
- `.github/last-checked-version.txt` updated to v2.1.81
- Scheduled workflow triggers disabled (PR #66) to save API tokens — re-enable in Phase 5

### Audited (Category C: no swap needed)
- No custom `/claude-api` skill exists — nothing to swap with native built-in

## [1.7.0] - 2026-02-15

### Added
- CI Auto-Fix Loop (`ci-self-heal.yml`) — automated fix cycle for CI failures and PR review findings
- Multi-call LLM judge (v3) — per-criterion API calls with dedicated calibration examples
- Golden output regression — 3 saved outputs with verified expected score ranges catch prompt drift
- Per-criterion CUSUM — tracks individual criterion drift, not just total score
- Pairwise tiebreaker (v3.1) — holistic comparison with full swap when scores within 1.0
- Deterministic pre-checks — grep-based scoring for task_tracking, confidence, tdd_red (free, fast)
- 3 real-world scenarios: multi-file-api-endpoint, production-bug-investigation, technical-debt-cleanup
- Score analytics (`score-analytics.sh`) — history parsing, trends, per-criterion averages, reports
- Score history persistence — results committed back to repo after each E2E evaluation
- Historical context in PR comments — scenario average and weakest criterion
- Color-coded PR comments — emoji indicators for PASS/WARN/FAIL per criterion
- Binary sub-criteria scoring with workflow input validation (PR #32)
- Evaluate bug regression tests (`test-evaluate-bugs.sh`)
- Score analytics tests (`test-score-analytics.sh`)
- Self-heal simulation tests (25 tests) — retry counting, AUTOFIX_LEVEL filtering, findings parsing, branch safety
- Self-heal live fire test procedure — validated full workflow_run → Claude fix → commit cycle (PR #52)

### Fixed
- `workflow_run` trigger dead for ci-autofix — invalid `workflows: write` permission scope caused GitHub parser to silently fail; removed it + renamed to `ci-self-heal.yml`
- Tier 1 E2E flakiness — regression threshold widened from -0.5 to -1.5 (absorbs ±1 LLM noise)
- Silent zero scores from `2>&1` mixing stderr into stdout (PR #33)
- Token/cost metrics always N/A — removed dead extraction code (action doesn't expose usage data)
- Score history never persisting (ephemeral runner) — added git commit step
- `show_full_output` invalid action input — deleted
- `configureGitAuth` crash — added `git init` before simulation
- `error_max_turns` on hard scenarios — bumped from 45 to 55
- Autofix can't push workflow files — requires PAT with `workflow` scope or GitHub App (not YAML permissions)
- `git push` silent error swallowing in `weekly-community.yml` — removed `|| echo` fallback
- Missing `pull-requests: write` permission in `monthly-research.yml` — e2e-test job creates PRs but permission wasn't declared
- Workflow input validation audit — removed `prompt_file`, `direct_prompt`, `model` invalid inputs across all 3 auto-update workflows
- `outputs.response` doesn't exist — read from execution output file instead
- CI re-trigger 403 in self-heal loop — missing `actions: write` permission for `gh workflow run` dispatch

### Changed
- `monthly-research.yml` schedule enabled (1st of month, 11 AM UTC) — Item 23 Phase 3
- `weekly-community.yml` schedule enabled (Mondays 10 AM UTC) — Item 23 Phase 2
- `daily-update.yml` schedule re-enabled (9 AM UTC) — Item 23 Phase 1
- All auto-update workflows create PRs (removed "LOW → direct commit" path)
- Evaluation uses `claude-opus-4-6` model (was hardcoded to `claude-sonnet-4`)
- E2E scenarios expanded from 10 to 13

## [1.6.0] - 2026-02-06

### Added
- Full test coverage for stats library, hooks, and compliance checker (34 new tests)
- Extended SDP calculation and external benchmark tests (9 new tests)
- Future roadmap items 14-19 in AUTO_SELF_UPDATE.md

### Fixed
- Version format validation before npm install (security: prevents injection)
- Hardcoded `/home/runner/work/_temp/` paths replaced with `${RUNNER_TEMP:-/tmp}`
- Silent fallback to v0.0.0 on API failure (now fails loudly)
- Duplicate prompt sources in daily-update workflow (prompt_file + inline prompt)
- Hardcoded output path in pr-review workflow
- Weekly community workflow hardcoded output path

### Changed
- Documentation overhaul: TESTING.md, CI_CD.md, CONTRIBUTING.md, README.md updated
- SDLC.md version tracking updated from 1.0.0 to 1.6.0

### Files Added
- `tests/test-stats.sh` - Statistical functions tests (14 tests)
- `tests/test-hooks.sh` - Hook script tests (11 tests)
- `tests/test-compliance.sh` - Compliance checker tests (9 tests)

### Files Modified
- `.github/workflows/daily-update.yml` - Security + correctness fixes
- `.github/workflows/pr-review.yml` - Hardcoded path fix
- `.github/workflows/weekly-community.yml` - Hardcoded path fix
- `tests/test-sdp-calculation.sh` - Extended (5 new tests)
- `tests/test-external-benchmark.sh` - Extended (4 new tests)

## [1.5.0] - 2026-02-03

### Added
- SDP (SDLC Degradation-adjusted Performance) scoring to distinguish "model issues" from "wizard issues"
- External benchmark tracking (DailyBench, LiveBench) with 24-hour caching
- Robustness metric showing how well SDLC holds up vs model changes
- Two-layer scoring: L1 (Model Quality) + L2 (SDLC Compliance)

### How It Works
PR comments now show three metrics:
- **Raw Score**: Actual E2E measurement
- **SDP Score**: Adjusted for external model conditions
- **Robustness**: < 1.0 = resilient, > 1.0 = sensitive

When model benchmarks drop but your SDLC score holds steady, that's a sign your wizard setup is robust.

### Files Added
- `tests/e2e/lib/external-benchmark.sh` - Multi-source benchmark fetcher
- `tests/e2e/lib/sdp-score.sh` - SDP calculation logic
- `tests/e2e/external-baseline.json` - Baseline external benchmarks
- `tests/test-external-benchmark.sh` - Benchmark fetcher tests
- `tests/test-sdp-calculation.sh` - SDP calculation tests

### Files Modified
- `tests/e2e/evaluate.sh` - Outputs SDP alongside raw scores
- `.github/workflows/ci.yml` - PR comments include SDP metrics
- Documentation updated (README, CONTRIBUTING, CI_CD, AUTO_SELF_UPDATE)

## [1.4.0] - 2026-01-26

### Added
- Auto-update system for staying current with Claude Code releases
- Daily workflow: monitors official releases, creates PRs for relevant updates
- Weekly workflow: scans community discussions, creates digest issues
- Analysis prompts with wizard philosophy baked in
- Version tracking files for state management

### How It Works
GitHub Actions check for Claude Code updates daily (official releases) and weekly (community discussions). Claude analyzes relevance to the wizard, and HIGH/MEDIUM confidence updates create PRs for human review. Most community content is filtered as noise - that's expected.

### Files Added
- `.github/workflows/daily-update.yml`
- `.github/workflows/weekly-community.yml`
- `.github/prompts/analyze-release.md`
- `.github/prompts/analyze-community.md`
- `.github/last-checked-version.txt`
- `.github/last-community-scan.txt`

### Required Setup
Add `ANTHROPIC_API_KEY` to repository secrets for workflows to function.

## [1.3.0] - 2026-01-24

### Added
- Idempotent wizard - safe to run on any existing setup
- Setup tracking comments in SDLC.md (version, completed steps, preferences)
- Wizard step registry for tracking what's been done
- Backwards compatibility for old wizard users

### Changed
- "Staying Updated" section rewritten for idempotent approach
- Update flow now checks plugins and questions, not just files
- One unified flow for setup AND updates (no separate paths)

### How It Works
The wizard now tracks completed steps in SDLC.md metadata comments. Old users running "check for updates" will be walked through only the new steps they haven't done yet.

## [1.2.0] - 2026-01-24

### Added
- Official plugin integration (claude-md-management, code-review, claude-code-setup)
- Step 0.1-0.4: Plugin setup before auto-scan
- "Leverage Official Tools" principle in Philosophy section
- Post-mortem learnings table (what goes where)
- Testing skill "After Session" section for capturing learnings
- Clear update workflow in "Staying Updated" section

### Changed
- Step 0 restructured: plugins first, then SDLC setup, then auto-scan
- Stay Lightweight section now includes official plugin table
- Clarified plugin scope: claude-md-management = CLAUDE.md only

### Files Affected
- `.claude/skills/testing/SKILL.md` - Add "After Session" section
- `SDLC.md` - Consider adding version comment

## [1.1.0] - 2026-01-23

### Added
- Tasks system documentation (v2.1.16+)
- $ARGUMENTS skill parameter support (v2.1.19+)
- Ike the cat easter egg (8 pounds, Fancy Feast enthusiast)
- Iron Man analogy for human+AI partnership

### Changed
- Test review preference: user chooses oversight level
- Shared environment awareness (not everyone runs isolated)

## [1.0.0] - 2026-01-20

### Added
- Initial SDLC Wizard release
- TDD enforcement hooks
- SDLC and Testing skills
- Confidence levels (HIGH/MEDIUM/LOW)
- Planning mode integration
- Self-review workflow
- Testing Diamond philosophy
- Mini-retro after tasks
