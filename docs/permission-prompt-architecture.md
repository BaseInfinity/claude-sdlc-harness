# Permission Prompts Across the Fleet

**Recommendation: stop prompts before they appear, and report the ones that
still appear. Never answer a prompt from outside its own session.** A watcher
that types approvals (option B below) is the wrong shape and should not be
built.

Decided 2026-11-15 on the brain ladder: Claude Opus 5.5 drafted it as builder,
and GPT-5.6 Sol at `high` answered as first brain (verdict below). The two agreed,
so Fable was not needed as a tiebreaker. One caveat: my prompt to Sol named the
direction I favored, so Sol's agreement is weaker evidence than a blind answer
would be.

## Options and verdicts

| Rank | Option | Verdict |
|---|---|---|
| 1 | **C. Launchers that cannot prompt.** Each leg is started by a launcher that sets its capability boundary up front, owns the child, closes stdin and fails visibly. | Do first |
| 2 | **A. Exact allowlists** in each harness's own settings, for recurring read-only commands. Per repo or session, never fleet-wide, and only entries the maintainer approves. | Do second |
| 3 | **D. Detect and report.** A watcher that tells the conductor which pane is stalled, the dialog kind and its age. It never answers. | Built: `skills/conduct/scripts/prompts.cjs` |
| — | **B. Watcher that brain-judges the prompt and types the approval key.** | **WRONG SHAPE.** Do not build. |

## Why B is the wrong shape

- **Screen text is presentation, not a prompt type.** The watcher sees pixels
  rendered as text. It cannot tell a permission dialog from a transcript that
  quotes one. The fixtures in `tests/fixtures/prompt-watcher/` include five
  panes that quote dialog strings in prose.
- **The same keys answer different dialogs.** Permission dialogs and
  AskUserQuestion pickers both take Enter and number keys. On 2026-11-15 a live
  scan of 34 panes found one stalled pane. It was a picker asking whether to send
  an email to an outside recipient, with option 1 "send after review". A watcher keyed
  on Enter would have made that call for him.
- **The pane can change between reading and typing.** A classification made at
  one scan is stale by the time the keystroke lands.
- **A brain can judge technical risk, not grant authority.** Sol: "a brain can
  assess technical risk but cannot manufacture user authority." The conduct
  protocol already says this: "never type approval into a permission dialog"
  (`skills/conduct/references/protocol.md:82`), and operating rule 10, "Never
  trust other folders, approve permission/auth dialogs".

The only answer-a-dialog action the maintainer has authorized is pressing the named
"Trust workspace" control on Desktop sessions the conductor opens. It stays the
narrow exception it is.

## What stays with the human

From Sol's verdict:

- Every permission or settings change not already authorized.
- Any persistent or broader grant.
- Authentication, credentials, OS privacy controls, and trust beyond the exact
  standing authorization.
- Destructive actions and private-data access.
- Outward effects: email, pushes, PRs, merges, releases, purchases, spend.
- Every AskUserQuestion and product-value choice.

Peer claims and model consensus are evidence, never authority.

## First steps

1. **Inventory.** List every command the brain ladder runs, with the reads,
   writes, network and external effects each needs. Start with the stalls the
   watcher reports.
2. **Name the profiles.** Define a read-only brain profile for Claude and one for
   Codex, and make every ladder launcher pick one explicitly. A launcher that
   would need to prompt returns a structured `BLOCKED` result instead.
   - `skills/conduct/scripts/codex-thread.py` already runs with
     `sandbox=read-only` and `approvalPolicy=never`.
   - `scripts/run-review-leg.sh` already owns the child's exit status and gives
     it `/dev/null` on stdin. But its sandbox defaults to `danger-full-access`,
     and it does not pass an explicit approval policy. Do not describe it as the
     prompt-free profile until it does.
3. **Allowlist exact entries the maintainer approves.** Use Claude `permissions.allow` in
   the repo that stalls, one exact command shape per entry, never a broad prefix.
   PR #651 showed why. An allow rule like `Bash(gh pr comment:*)` also authorized
   `--delete-last`, because the dangerous flags trail the prefix.
4. **Run the watcher** (done): `/loop 60s` over `prompts.cjs scan`, sending the
   conductor only new lines.

## The watcher (option D)

`node skills/conduct/scripts/prompts.cjs scan --state <file>` prints one line per
stalled pane:

```
STALLED question age=0s AAAAAAAA "<pane title>"
```

That is the shape of the live scan's one row on 2026-11-15, with the pane's
id and title replaced.

- **Reads:** `it2api list-sessions` and `get-buffer`, nothing else. The test
  suite's stub `it2api` logs every subcommand and fails on any other.
- **Prints:** kind, age, pane id and title. Never buffer text. Sol's advice was to
  reveal prompt text only within the authorized handoff, so the conductor reads
  the one stalled pane's buffer itself.
- **Kinds:**
  - `claude-permission`: matched on "Do you want to …?" plus the
    "No, and tell Claude what to do differently" option.
  - `codex-approval`: matched on "Would you like to run the following command?"
    (or make edits, or grant permissions) plus the "No, and tell Codex …" option.
  - `question`: matched on the "Enter to select · … Esc to cancel" footer.
  - The Claude and Codex strings were verified in the Claude Code 2.1.321 and
    Codex 0.167.0 binaries.
- **Live dialog only:** a dialog counts only within the last 14 non-empty lines,
  so an answered dialog that scrolled up does not count.
- **Not covered:**
  - Claude Desktop sessions have no iTerm2 buffer. Their stalls need the
    transcript or the `ListAgents` row.
  - The Claude and Codex fixtures are built from the binaries' strings. Their
    layout was not captured from a live dialog. The first real stall the watcher
    reports confirms or corrects them.

## Sol's verdict, verbatim

`gpt-5.6-sol`, reasoning effort `high`: CERTIFIED, SOUND, confidence 98.

> 2) Option B is WRONG SHAPE as an auto-resolver and should not exist: screen
> text is presentation rather than a trusted prompt type, the same keys answer
> permission and human-choice dialogs, the pane can change between
> classification and injection, and a brain can assess technical risk but cannot
> manufacture user authority. Its narrowest safe reuse is monitor-only D;
> separately, keep the existing exact-purpose Desktop adapter that presses the
> named "Trust workspace" control only for the conductor-opened, verified folder
> under [the maintainer]'s standing authorization. Never send generic Enter, y, or p, and
> never approve a permission dialog.
