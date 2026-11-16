# Antigravity SDLC Port Scope

**Verdict: port 3 hooks, 1 skill and 1 rules file. Skip the rest.** The minimal
port enforces the three things that matter: tests before code, a reviewed tree
before commit, and the SDLC baseline in every session. Everything else is
convenience or Claude-specific plumbing.

Platform facts come from `docs/agy-setup-guide.md`. Tags there apply here:
anything marked **[unknown]** must be probed before the guard that depends on it
is written.

## Target repo layout (`antigravity-sdlc-wizard`)

```
AGENTS.md                         # SDLC baseline, always loaded
.agents/
  hooks.json                      # 3 hook groups
  hooks/
    tdd-check.sh
    commit-gate.sh
    session-start.sh
  skills/sdlc/SKILL.md            # the one workflow skill
.agy-sdlc/
  review-policy.json              # {"schema_version":1,"cross_vendor_review":"required"}
install.sh                        # copies the above into a consumer repo
tests/                            # bash fixtures, one per hook
```

Bash, not Node: `claude-sdlc-wizard` hooks are bash and test cleanly with bash
fixtures. Windows support waits until someone asks.

## Hook map

Behavior below is read from each hook's header comment and from the hook
registration files (`claude-sdlc-wizard/hooks/hooks.json`,
`codex-sdlc-wizard/.codex/hooks.json`).

| Source hook | Repo | What it does | agy event | Decision | Why |
|---|---|---|---|---|---|
| `codex-gate-check.sh` | claude | Blocks (exit 2) `git commit` unless the staged tree has a cross-model review artifact **or** a local test PASS for that tree (`hooks/codex-gate-check.sh:668-675`, #731); review is then required at merge by `scripts/merge-pr.sh` | `PreToolUse`, matcher `^run_command$` | **PORT** | The core gate. |
| `git-guard.cjs` → `review-gate.cjs` | codex | `PreToolUse ^Bash$`; `git-guard` calls `review-gate`, which binds the review to `git write-tree` (`review-gate.cjs:1134`) | same | **PORT** (merged with the row above) | Take the tree binding from here, the simplicity from the bash version. |
| `tdd-pretool-check.sh` | claude | Blocks (exit 2) source edits until the `sdlc` skill was invoked, and blocks writes to `src/**` unless a test file was touched earlier in the session | `PreToolUse`, matcher on write tools | **PORT** the test-first rule only | TDD is the other non-negotiable. The skill-invocation check depends on Claude's skill events. |
| `sdlc-prompt-check.sh` | claude (wired to `UserPromptSubmit` + `SessionStart`) | Prints the SDLC baseline once per session, on the first prompt (`hooks/sdlc-prompt-check.sh:85-126`). Silent on `SessionStart` (`hooks/sdlc-prompt-check.sh:23`) | `SessionStart` → `injectSteps` | **PORT** as new behavior | agy has no `UserPromptSubmit`, so the agy hook must print where the source stays silent. `AGENTS.md` repeats the text every turn. `codex-sdlc-wizard` ships a copy in `.codex/hooks/` but does not register it. |
| `session-start.cjs` | codex | `SessionStart` setup | `SessionStart` | Merge into the row above | One `SessionStart` hook. |
| `codex-review-stop-check.sh` | claude | Warns (non-blocking) at Stop when changes are unreviewed | `Stop` | DEFER | The commit gate already blocks. |
| `model-effort-check.sh` | claude | Nudges on effort level at session start | `SessionStart` (`modelName` is in the payload) | DEFER | The agy payload has the model, not the effort **[unknown]**. |
| `precompact-seam-check.sh` | claude | Compact guard | — | DROP | No compact event in agy. |
| `compact-guard.cjs` | codex | `PreCompact` / `PostCompact` | — | DROP | Same. |
| `instructions-loaded-check.sh` | claude | Version and setup checks at instruction load; no longer warns on missing `SDLC.md`/`TESTING.md` (#236(b)); never blocks | — | DROP | No equivalent event. |
| `token-spike-check.sh` | claude | Reads Claude transcripts for token-burn spikes | — | DROP | Claude-specific. |
| `handoff-check.sh` | claude | Advisory context-size reminder | — | DROP | Conduct/fleet layer. |
| `bash-guard.sh` | codex | Present in `.codex/hooks/`, not registered | — | DROP | Not live in the source repo. Use `permissions.deny`. |

### Blocking contract differs — rewrite, do not copy

Claude hooks block with **exit 2 + stderr**. agy hooks block by printing
`{"decision":"deny","reason":"..."}` on stdout for `PreToolUse` **[doc]**. Exit-code
semantics are undocumented **[unknown]**. The two `PreToolUse` hooks must:

1. Print the JSON decision on every path, including `allow`.
2. Be tested for the deny path by a fixture that checks stdout, not the exit code.
3. Fail closed on their own errors: a crash prints `deny`, not nothing. Timeout
   behavior is undocumented, so a hang may fail open **[unknown]**. Keep hooks
   fast and stdin-bounded (reuse `read_stdin_bounded` from `_find-sdlc-root.sh`).

The `SessionStart` hook takes no decision. It prints `{"injectSteps":[...]}` and
is tested for that output.

### First task: capture real payloads

`toolCall.args` keys per tool are **[unknown]**. Before any guard:

```json
{ "probe": { "PreToolUse": [ { "matcher": "", "hooks": [
  { "command": "cat >> \"$HOME/agy-hook-payloads.jsonl\"; echo '{\"decision\":\"allow\"}'" }
] } ] } }
```

Run one session that edits a file and runs `git status`. That file becomes the
fixtures for every hook test. Also record the exact names of the write tools;
the docs show `write_file`, `view_file`, `grep_search`, `run_command` and nothing
else.

## Review gate

Keep the `codex-sdlc-wizard` contract: a commit is allowed only when a review
artifact exists for the exact staged tree (`review-gate.cjs:1134` runs
`git write-tree` — "Cannot bind the exact staged tree"). Its
`.codex-sdlc/review-policy.json` sets `"cross_vendor_review": "required"`. In
`claude-sdlc-wizard` the rule is a working agreement (`CLAUDE.md`: Codex is the
cross-model check). `codex-gate-check.sh` also admits a commit on a local test
PASS for the tree, and `scripts/merge-pr.sh` requires the review at merge. Pick
one of those two points for the port; v0.1 gates at commit. Do not port
`review-gate.cjs` itself; it is over 3,000 lines. Port the contract.

- Bind the artifact to `git write-tree` of the index. A new edit changes the tree
  and voids the review.
- The reviewer runs out of process, headless, with model and effort pinned on the
  command line. A subagent cannot do this: subagent `model` only accepts
  `inherit|flash|pro` **[doc]**.
- The review runner, not the model, writes `<artifact dir>/<tree-sha>.json`:
  `{"tree": "<tree-sha>", "reviewer_model": "...", "reviewer_vendor": "...",
  "verdict": <the model's review-verdict.schema.json output>}`. The model only
  fills `verdict`; the runner adds the fields it knows.
- `commit-gate.sh` allows the commit only when that file exists for the staged
  tree, `verdict.verdict` is exactly `CERTIFIED`, and `reviewer_vendor` differs
  from the builder's. It denies otherwise.

**Conflict to resolve before building:** the requested setup is Hydrogen builds,
Argon reviews. Both are Google models. That fails `cross_vendor_review: required`.
Two KISS options:

- Keep the rule. The reviewer is Sol (via Codex) or Claude (via `claude -p`).
  Argon stays the in-session self-review, as Opus self-review is today.
- Relax the rule for this repo only, and say so in the policy file.

The A/B test in `docs/model-ab-test-plan.md` should decide this. If Argon high
matches Sol on recall, relaxing is defensible. If not, keep the rule.

## Skills

| Skill | Source | Decision | Notes |
|---|---|---|---|
| `sdlc` | claude `skills/sdlc`, codex `skill-sources/sdlc` | **PORT** | Diff the two copies first and start from whichever names fewer harness tools. Rewrite tool names (`Bash` → `run_command`; a todo tool is **[unknown]**). Drop advisor/Fable steps. Review step calls the headless reviewer. |
| `codex-sdlc-wizard` (installer skill) | codex `skills/` | DROP | `install.sh` replaces it. |
| `setup` / `setup-wizard` | both | DROP | No scan-and-ask wizard in v0.1. |
| `update` / `update-wizard` | both | DROP | Re-run `install.sh`. |
| `feedback` | both | DROP | |
| `conduct`, `fleet` | claude | DROP | Fleet layer, not SDLC. |

`codex-sdlc-wizard/agents/` is empty, so no subagent definitions need porting.

Skill frontmatter needs only `description` (required) and `name` **[doc]**. Keep
the `sdlc` description keyword-dense, since the description alone decides
autonomous loading.

## Rules

Put the SDLC baseline (plan first, state confidence, TDD, all tests pass before
commit) in root `AGENTS.md`. It is always loaded, needs no frontmatter, and is
also read by Codex, so one file serves both. Avoid `.agents/rules/*.md` for v0.1:
a bad `trigger` frontmatter drops the file silently.

## Out of scope for v0.1

Plugin packaging, marketplace, Windows hooks, auto-update workflow, E2E
simulation, score history, model/effort guard, Stop nudge.

## Definition of done

1. Payload probe captured, fixtures committed.
2. Each `PreToolUse` hook has a bash test for its allow and deny paths, asserted
   on stdout JSON. The `SessionStart` hook has a test asserting its
   `injectSteps` output.
3. On a scratch repo: an `agy` session that edits `src/` without a test is
   denied by the TDD guard, and `git commit` is denied until a review artifact exists for the
   staged tree.
4. `/hooks` lists exactly the 3 groups; `/skills` lists `sdlc`.
