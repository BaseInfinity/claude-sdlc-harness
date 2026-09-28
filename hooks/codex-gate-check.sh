#!/bin/bash
# PreToolUse hook — blocks git commit without cross-model review artifact
# Fires on Bash tool; only acts when the command contains "git commit"
#
# #436 fix: exit 2 + stderr is what actually denies the tool call in Claude
# Code. The original version exited 0 on every path (including the two
# "CROSS-MODEL REVIEW REQUIRED" branches below), so it printed a warning but
# never blocked anything — the exact bug class this gate exists to prevent.
# Matches the proven blocking pattern in precompact-seam-check.sh.

set -e

HOOK_DIR="${BASH_SOURCE[0]%/*}"
[ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR="."
# shellcheck disable=SC1091
# Sourced only for read_stdin_bounded (#491 Class 2). The helper defines
# functions and has no top-level side effects, so this gate's behaviour is
# unchanged apart from no longer being able to block forever on stdin.
source "$HOOK_DIR/_find-sdlc-root.sh"

# Skip gate if explicitly overridden (emergency bypass with logged justification).
#
# #533: this is read from the HOOK's own process environment, which is not the
# shell that runs the blocked command — a PreToolUse hook fires first, so
# `CODEX_GATE_SKIP=1 git commit ...` is blocked identically to the unprefixed
# form. The variable stays (a settings env block can set it); what changed is
# that the messages below no longer instruct callers to take a route that
# cannot work from where they are reading it.
[ "${CODEX_GATE_SKIP:-}" = "1" ] && exit 0

# Named once so all four refusals say the same true thing.
BYPASS_NOTE="Emergency bypass: CODEX_GATE_SKIP=1, set in the hook's own environment (a settings env block) — this hook runs before your shell, so an inline prefix on the command cannot reach it."

TOOL_INPUT=$(read_stdin_bounded) || {
    # Fail CLOSED: unreadable stdin must not become an allow (#491 P0).
    echo "CROSS-MODEL REVIEW GATE: could not read hook input within ${SDLC_HOOK_STDIN_TIMEOUT:-5}s. Refusing to allow an unverified command. $BYPASS_NOTE" >&2
    exit 2
}

# Codex review findings (hook-enforcement-436):
# Round 1: extracting the "command" field's value via grep/sed with
# `[^"]*` broke when an earlier quote appeared in the command (e.g. `cd
# "$dir" && git commit ...`) — the class stops at the first literal `"`
# regardless of JSON escaping, truncating the capture before it ever
# reached "git commit" (false negative — review-less commit slipped
# through).
# Round 2: matching "git commit" against the WHOLE raw TOOL_INPUT (the
# round-1 fix) over-corrected — a non-commit command got blocked if any
# OTHER field (e.g. the Bash tool's own "description") happened to mention
# "git commit" in prose (false positive).
# Fix: extract just the "command" field's value with an escape-aware
# pattern — `([^"\\]|\\.)*` consumes an escaped quote (`\"`) as one unit
# instead of treating it as a terminator, so it can't stop early, and it
# still can't run past the field's true (unescaped) closing quote because
# neither alternative in the group can match a bare `"`. Scoped to just
# this field, so unrelated fields containing the phrase can't false-trigger.
# #236(b): under `set -e`, a grep with no match exits 1 and kills the whole
# script with an undefined exit code (a "command" field can be absent, e.g.
# an old-format payload) — `|| true` makes "no match" a clean, deliberate
# empty COMMAND_FIELD instead of a crash.
COMMAND_FIELD=$(printf '%s' "$TOOL_INPUT" \
    | grep -oE '"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' || true)

# Codex cross-model review finding (#236(b) round 1, 2026-07-06): a `-c`/`-C`
# value containing a space inside quotes is a real, valid git invocation
# (e.g. `git -c user.name="A B" commit`) but broke the structural match below
# — `\S+` stops at the embedded space, so the flag-value alternative never
# matches and the whole "git ... commit" pattern silently fails, letting the
# commit through unreviewed. Fix: strip COMMAND_FIELD down to just the raw
# value content (COMMAND_VALUE, still JSON-escaped), then collapse every
# quoted sub-span — both JSON-escaped `\"..\"` and plain `'..'` — to a single
# placeholder token before the structural match runs, so a quoted value can
# never look like more than one word to it.
#
# The double-quote masker is ESCAPE-AWARE but must NOT let the escape
# alternative swallow the closing quote. `\\.` would, and under POSIX
# longest-match `cd \"$dir\" && git commit -m \"message\"` then masks to
# `cd Q` — the invocation vanishes and the gate fails open. That was
# the reviewer's own suggested fix this round, and tests/test-hooks.sh caught it
# in the same commit that applied it. `\\[^"]` covers a backslash inside the
# span (a Windows path, an escaped char) while still stopping at the closer.
#
# STILL OPEN and PRE-EXISTING, tracked on #605: the two passes are independent,
# so a literal `"` inside one single-quoted argument and another inside a later
# one are paired as if they were a single double-quoted span. In
# `printf '%s\n' '"' && git commit -m 'fix "quoted" handling'` the mask
# swallows `&& git commit` and the gate allows a direct, unquoted invocation.
# Measured identical on origin/main, so this PR neither introduces nor fixes it.
# Closing it needs the two passes to scan jointly and honour whichever quote
# opens first — not another alternative bolted onto either regex.
COMMAND_VALUE=$(printf '%s' "$COMMAND_FIELD" \
    | sed -E 's/^"command"[[:space:]]*:[[:space:]]*"(.*)"$/\1/')

# #581: COMMAND_VALUE is still JSON-escaped, so a real newline in the command
# is the two characters `\` `n` and a tab is `\` `t`. Neither is whitespace to
# the checks below, and the `n` of `\n` supplies a word character immediately
# before "git" — so `\bgit` has no boundary left to match and any command whose
# INVOCATION WAS SPLIT BY one of those escapes walked past the gate. Not every
# multi-line command: an intact `git commit` sitting before some unrelated
# newline was always caught, on origin/main and here alike. Measured against
# shipped origin/main (57ec6cf): all four invocation-split shapes in the test
# escape, none are caught.
#
# A naive `s/\\[nrt]/ /g` is WRONG, and Sol caught it: it cannot tell a JSON
# control escape from an escaped literal backslash. In `echo x\ngit commit` the
# backslash escapes the letter n — there is no invocation there at all — but the
# naive pass rewrites it to a space and MANUFACTURES the word boundary that
# `\bgit` needs, denying a harmless command that shipped main allowed.
#
# So pair the backslashes first, exactly as JSON does, left to right:
#
#   run of 1  \n      -> control escape        -> becomes `;` (see below)
#   run of 2  \\n     -> literal backslash + n -> leave alone
#   run of 3  \\\n    -> literal backslash + newline, i.e. a shell line
#                        continuation          -> DELETED, see below
#   run of 4  \\\\n   -> two literal backslashes + n -> leave alone
#
# Pass 1 replaces each PAIR of backslashes with a sentinel, and sed's global
# substitution consumes pairs left to right, which is precisely JSON's own rule.
# After that, any backslash still standing is by definition the start of a
# control escape, so the later passes can act without ambiguity.
#
# The run-3 case is DELETED, not spaced, because that is what the shell does:
# bash removes a backslash-newline pair entirely, so `echo x\<newline>git commit`
# executes as `echo xgit commit` — one word, no invocation anywhere in it.
# Replacing it with a space instead would join `x` and `git` into two words and
# manufacture the boundary `\bgit` needs, denying a harmless command. Deleting
# keeps the real bypass detectable, because `git \<newline>  commit` still has
# its own surrounding spaces.
#
# For the same reason a run-3 before `t` is stripped of its escape rather than
# converted: bash treats an escaped tab as part of the word, not as a separator,
# so turning it into whitespace would invent a split the shell never makes.
#
# Each surviving control escape is then mapped to what bash actually does with
# that character, which is NOT uniformly "whitespace":
#
#   \n  -> `;`   a bare newline TERMINATES a command. Mapping it to a space
#                would fuse two commands into one: `git<newline>commit` is
#                `git` then a separate `commit`, never a `git commit`. With `;`
#                there is no `\s+` after `git` so it correctly does not match,
#                while `cd foo<newline>git commit` still does — `;` is itself a
#                word boundary.
#   \t  -> ` `   a bare tab IS a token separator, so whitespace is faithful.
#   \r  -> left alone. A carriage return is NOT a bash separator; it is ordinary
#                word content. `cd foo<CR>git commit` runs `cd` with the argument
#                `foogit` and never invokes git at all. Leaving `\r` intact keeps
#                the `r` as a word character, so `\bgit` cannot fire — which is
#                the truth. CRLF still blocks, via the `\n` half.
#
# Never decode to REAL newlines. Every consumer below greps line-by-line, so a
# real newline would split `git \` from `commit` across lines and leave both
# continuation forms permanently undetectable.
#
# Order is load-bearing: pairing precedes everything; the continuation and
# escaped-tab forms are handled BEFORE the general pass, so that pass cannot eat
# their trailing escape and strand a backslash mid-command.
#
# Normalizing here — once, upstream of both MASKED_COMMAND and the relocation
# check in the PENDING_RECHECK lane — is what closes it in both places.
#
# Known limits, stated rather than implied.
#
# This decodes the `\n`/`\r`/`\t` short forms the Bash tool actually emits, NOT
# the equivalent six-character unicode escapes (backslash-u-0-0-0-a and
# friends). An accident-catcher, not an adversary barrier.
#
# PARITY IS LOAD-BEARING, and #588 fixed it. The continuation and escaped-tab
# passes above match `(^|[^S])(SS)*S\n` rather than a bare `S\n`, so they fire
# only on an ODD decoded backslash run — which is what a line continuation
# actually is. An even run leaves the newline real, a command separator, so git
# genuinely runs.
#
# The earlier bare-`S\n` form treated EVERY run as a continuation. The old
# `\bgit` detector still blocked k = 1 (mod 4) — the real invocations — but for
# the wrong reason: the leftover literal backslash it produced is a non-word
# character, so it supplied the boundary `\b` needed. Requiring `git` in command
# position (below) removed that accident and exposed the fail-OPEN underneath.
#
# So the three FALSE DENIALS this comment used to record as declined — k = 3
# (mod 4): 7, 11, 15 — are gone, closed as a side effect of getting the parity
# right rather than by the second pairing pass #581 prototyped.
#
# The contract is now exactly parity, with no exceptions: BLOCK at k = 1 (mod 4),
# ALLOW everywhere else. Ground truth is DERIVED FROM A BASH ORACLE through
# k = 16 in tests/test-codex-gate-command-position.sh, and pinned in
# tests/test-hooks.sh.
#
# Unquoted PROSE that merely names the verb can match. That class predates this
# change and is tracked as #588. Its edge moves here, in both directions, and
# measured against origin/main it is:
#
#   single-line prose      blocked before, blocked now   — unchanged
#   newline-separated      allowed before, allowed now   — unchanged, because
#                          `\n` becomes `;` rather than a space, so the words
#                          are separated rather than fused
#   tab-separated          allowed before, BLOCKED now   — WIDENED
#
# So this is not the no-change it would be convenient to claim. Tab-separated
# prose is newly caught, because a tab genuinely IS a bash separator and the
# detector cannot see that the surrounding text is prose. Accepted as part of
# the already-accepted #588 class: it fails closed and costs a rephrase.
# HEREDOC BODIES: NOT masked, and that is a deliberate reversal.
#
# A previous cut of this PR masked heredoc bodies with an awk pass, to fix the
# false POSITIVE on `cat > script.sh <<'EOF' ... git commit ... EOF` — a shape
# #588's own defect description names. Sol's round-6 review measured that the
# pass introduced SIX fail-opens, each oracle-confirmed and each blocked before
# it landed:
#
#   # documentation: use <<EOF below      a comment mentioning the operator
#   echo '<<EOF'                          the operator inside quotes
#   cat <<< EOF                           the regex restarts inside `<<<`
#   (( x = 1 << EOF ))                    a left-shift in arithmetic
#   cat <<-EOF ... <tab>EOF               the tab is still `\t` at that stage
#   cat <<EOF / $(git commit) / EOF       an unquoted body is NOT inert: the
#                                         substitution runs while the
#                                         redirection is being constructed
#
# That last one also falsified a claim in the reverted comment, which had said
# the body never runs. The count read FIVE until Sol's round 7 observed that the
# sixth was described in prose but never counted — and that the row pinned as
# `(( x = 1 << 2 ))` did not demonstrate the defect at all, because the pass
# blocked that one too. `<< EOF` is the shape that actually escaped.
#
# Recognising a heredoc correctly means ignoring `<<` inside quotes, comments,
# arithmetic and escapes, excluding `<<<`, queueing multiple delimiters, and
# distinguishing quoted from expanding bodies. That is a partial shell parser,
# which is exactly what #533 ruled out — the same ruling this PR has refused to
# re-litigate everywhere else. So it is reverted rather than deepened, and the
# heredoc false positive goes back to being an accepted limit that fails CLOSED.
ESC_SENTINEL=$(printf '\001')
COMMAND_VALUE=$(printf '%s' "$COMMAND_VALUE" \
    | sed -E -e "s/\\\\\\\\/$ESC_SENTINEL/g" \
             -e "s/(^|[^$ESC_SENTINEL])(($ESC_SENTINEL$ESC_SENTINEL)*)$ESC_SENTINEL\\\\n/\\1\\2/g" \
             -e "s/(^|[^$ESC_SENTINEL])(($ESC_SENTINEL$ESC_SENTINEL)*)$ESC_SENTINEL\\\\t/\\1\\2${ESC_SENTINEL}t/g" \
             -e 's/\\n/;/g' \
             -e 's/\\t/ /g' \
             -e "s/$ESC_SENTINEL/\\\\/g")

MASKED_COMMAND=$(printf '%s' "$COMMAND_VALUE" \
    | sed -E -e 's/\\"([^"\\]|\\\\"|\\[^"])*\\"/Q/g' \
             -e "s/\\\\\\\\/$ESC_SENTINEL/g" \
             -e "s/\\\\'/E/g" \
             -e "s/'[^']*'/Q/g" \
             -e "s/$ESC_SENTINEL/\\\\\\\\/g")

# An ESCAPED separator is word content, not a command boundary: `echo \; git
# commit` is one command printing three words. Neutralising it to `E` here —
# rather than asking the anchor for "a separator not preceded by a backslash" —
# is what keeps PARITY right. A regex lookbehind cannot count backslashes, and
# `\\;` is an escaped BACKSLASH followed by a REAL separator, which is exactly
# the k = 1 (mod 4) case the backslash-run contract is built on. Getting this
# wrong re-opened k = 5, 9 and 13 as fail-opens, caught by those rows.
#
# Same sentinel technique as the normalisation above: pair off `\\` first, so
# only a backslash that genuinely escapes something is left to act on. Escaped
# whitespace is deliberately untouched — `FOO=a\ b` is still one word.
#
# An escape before an ORDINARY character is then REMOVED, because that is what
# bash does: `e\nv` is `env`, `git c\ommit` is `git commit`, `git --git-\dir`
# is `git --git-dir`. Enumerating an optional escape between every letter of
# every keyword instead is unwinnable — it was tried for `git` alone and
# produced both a fail-open (the escape can sit anywhere in the basename) and a
# false positive (`\\git` is a command named `\git`, not git) in consecutive
# rounds. Doing what the shell does closes the whole class in one rule.
# The class is deliberately narrow, and each exclusion is load-bearing:
#   - no SPACE: unescaping it would split the word, so an assignment prefix
#     would stop being a prefix (`FOO=a\ b git commit`).
#   - no `=`, `+` or `_`: unescaping any of them MANUFACTURES a GATE_ASSIGN
#     prefix the shell never sees. `FOO\=1 git commit` runs nothing — the word
#     is not NAME=VALUE, so it is looked up as a command.
# THE ESCAPED-KEYWORD SHIELD, built rather than hand-written.
#
# An escape ANYWHERE in a reserved word stops bash recognising it as one:
# `i\f`, `wh\ile` and `th\en` are all ordinary command names. Shielding only
# the leading position missed seven of eight spellings.
#
# And the shield needs BOTH boundaries. With only a right boundary it matched
# the `\do` inside `su\do`, which stopped that token normalising to the
# enumerated `sudo` wrapper — a fail-OPEN I introduced, caught by the reviewer
# running a PATH proxy for sudo. The left boundary is what keeps `su\do` a
# wrapper spelling rather than a shielded keyword.
GATE_KW_ALT=""
for _kw in if elif while until "then" "do" "else" coproc; do
    _i=0
    while [ "$_i" -lt "${#_kw}" ]; do
        _sp="${_kw:0:$_i}\\\\${_kw:$_i}"
        GATE_KW_ALT="${GATE_KW_ALT:+$GATE_KW_ALT|}$_sp"
        _i=$((_i + 1))
    done
done


MASKED_COMMAND=$(printf '%s' "$MASKED_COMMAND" \
    | sed -E -e "s/\\\\\\\\/$ESC_SENTINEL/g" \
             -e 's/\\[;&|(){}!]/E/g' \
             -e "s/(^|[[:space:];&|(){}!\`])(${GATE_KW_ALT})([^A-Za-z0-9_]|\$)/\\1K\\2\\3/g" \
             -e 's/\\([A-Za-z0-9./:,@%^~-])/\1/g' \
             -e "s/$ESC_SENTINEL/\\\\\\\\/g")

# #236(b): literal substring "git commit" misses git's own global-flag forms
# — `git -C <dir> commit` and `git -c k=v commit` are valid invocations that
# never contain that exact two-word substring, and previously sailed through
# unreviewed. Regex allows any number of -C/-c (with their required value),
# --long-flag, or single-letter-flag tokens between "git" and "commit".
# #588: `\bgit` matched the verb ANYWHERE, so a command that merely NAMED it was
# blocked — `echo the git commit gate` and `grep -rn git commit hooks/` both
# denied, neither invoking anything. (Quoted mentions were already fine: the
# masking pass above collapses them to Q. Only unquoted ones false-fired.)
#
# The fix is to require `git` in COMMAND POSITION. That is not the positive
# command parsing #533 ruled out — nothing here decides what the command DOES.
# It anchors the existing negative detector to the places bash can begin a
# command, which is decidable from the text.
#
# Anchors: start of string, or after `;` `&` `|` `(` `)` `{` `}` `!`, `$(`, a
# backtick, or a `then`/`do`/`else` keyword. The `\n` -> `;` normalization above
# is what keeps #581's line-split shapes caught — `;` is itself an anchor — so
# that is a load-bearing dependency, pinned by its own fixture row.
#
# TRANSPARENT PREFIXES. Anchoring alone would open a fail-OPEN hole: bash runs
# `env X=1 git commit`, `nice git commit` and `echo -m x | xargs git commit` for
# real, and after anchoring `git` in those is an argument. Measured with a bash
# oracle, all four escaped. So a closed, enumerated set of prefixes is treated
# as transparent — assignments (bash runs an assignment-prefixed command
# directly; this repo's own workflow uses the shape) plus the wrappers below.
# Whatever a wrapper takes before `git` is skipped wholesale — see the WRAPPER
# OPTION GRAMMAR note further down; this hook does not model per-wrapper flags.
#
# The set is CLOSED, and that is the accepted limit. A wrapper nobody enumerated
# — doas, setsid, caffeinate, unbuffer, flock — is a false NEGATIVE, recorded on
# #588. This hook says of itself that it is an accident-catcher, not an
# adversary barrier, and #588 concedes deliberate bypass is trivial; an
# open-ended enumeration cannot be won and is not attempted.
#
# `(\S*/)?git` keeps a path-prefixed invocation caught — `/usr/bin/git commit`
# was blocked by the old `\bgit` and must not regress. It does not re-open
# prose: `echo see docs/git commit-policy.md` has no anchor before `docs/git`.
#
# Every shape named here is pinned in tests/test-codex-gate-command-position.sh,
# whose expected column is GENERATED BY THE ORACLE rather than hand-written.
# `eval`, `exec` and `time` are in the transparent set for the same reason the
# wrappers are, and they were found the same way — by hunting fail-opens with
# the oracle BEFORE review, not by reasoning about the regex. Each one shipped
# blocked on origin/main and would have walked past the anchored detector:
#
#     eval git commit -m x     oracle INVOKES   base BLOCK   anchored ALLOW
#     exec git commit -m x     oracle INVOKES   base BLOCK   anchored ALLOW
#     time git commit -m x     oracle INVOKES   base BLOCK   anchored ALLOW
#
# `builtin git commit` is deliberately NOT in the set: the oracle reports it
# inert, because `builtin` only runs shell builtins and git is not one. Allowing
# it is the correct answer, and origin/main's false denial of it is fixed here.
#
# `\git commit` is handled upstream now, not by an optional backslash in this
# pattern: the normalisation pass REMOVES an escape before an ordinary
# character, exactly as bash does, so by the time this regex runs there is no
# backslash left. The optional-escape spelling that used to live here was
# deleted — it produced a fail-open (the escape can sit anywhere in the
# basename) and a false positive (`\\git` is a command named `\git`) in
# consecutive review rounds.
#
# STILL OPEN, and NOT introduced here — `eval 'git commit'`, `bash -c 'git
# commit'` and `sh -c "git commit"` are allowed on origin/main too, because the
# masking pass collapses the quoted payload to `Q` before any matching happens.
# Measured against origin/main, not assumed. Out of scope for #588 and filed
# separately rather than fixed silently in a PR about prose false-positives.
# Sol's round 1 found three more fail-open classes in the first cut of this
# anchor, all of which shipped BLOCKED on origin/main. Each is covered below and
# pinned by an oracle row:
#
#   if git commit -m x; then :; fi      reserved words other than then/do/else
#   </dev/null git commit -m x          a leading redirection is a valid prefix
#   env -u FOO git commit -m x          a wrapper option that takes an argument
#
# RESERVED WORDS. bash begins a command after `if`, `elif`, `while`, `until` and
# `coproc` exactly as it does after `then`, `do` and `else`.
#
# REDIRECTIONS. bash permits redirections before the command word, so
# `</dev/null git commit` and `2>/dev/null git commit` are ordinary invocations.
# They are transparent here, in any order with assignments — for the operators
# ENUMERATED in GATE_REDIR. That enumeration is the seventh narrowing instance
# in this file's history: it omitted `<<`, `<<-` and `<>`, and a SEPARATED
# operand escaped through the gap while an attached one matched by accident via
# a shorter operator. The set is closed, so an operator nobody enumerated is a
# false NEGATIVE, on the same footing as the closed wrapper set below.
#
# WRAPPER OPTION GRAMMAR. The first cut allowed only flags and bare numbers
# after a wrapper, so `env -u FOO`, `xargs -I X`, `sudo -u USER` and `timeout 5s`
# all broke the chain. Enumerating each wrapper's real option grammar is not
# winnable — the grammars differ per tool and per platform. So once one of the
# ENUMERATED wrappers appears in command position, the tokens between it and
# `git` are skipped wholesale, stopping at `;`, `&` or `|` so the skip cannot
# reach across into a separate command.
#
# That deliberately trades a narrow FALSE POSITIVE for closing a fail-open:
# `time echo git commit` is inert yet blocked here, because the text cannot say
# whether `echo` is a wrapper's option argument or a new command word. It fails
# CLOSED and the cost is a rephrase, which is the same bargain every other
# accepted limit on this hook takes — and the opposite direction from the one
# that actually matters for a review gate.
#
# SHELL WORDS ARE NOT `[^ ]*`. A backslash escape makes the next character
# ordinary word content, so `FOO=a\ b git commit`, `/path\ with\ spaces/git
# commit` and `env FOO=a\;b git commit` are all single words to bash and all
# invoke git. Modelling a word as "runs to the next space or separator" splits
# every one of them early and lets the invocation through. GATE_WORD is that
# model, and it is used at all SIX sites that consume a word:
#
#   1. assignment values          4. the path prefix on `git`
#   2. redirection operands       5. git's own global-option operands
#   3. the wholesale skip         6. the path prefix on a WRAPPER
#
# because a word atom that is right at five sites out of six is a fail-open at
# the sixth. Site 6 was missing from this list until Sol's round-6 review — the
# code had it, the prose did not, which is a claim-rule violation either way.
#
# WHAT GATE_WORD DOES NOT MODEL, stated plainly because the comment it replaced
# overclaimed: it models ESCAPES, not nested shell syntax. A separator inside
# `${...}`, `$(...)`, `$((...))` or backticks is not an outer command boundary,
# and this atom stops there anyway — `FOO=${UNSET:-a;b}x git commit` invokes git
# and is allowed here. Substitutions nest arbitrarily, so no regex closes that;
# it is the same constraint as the quoted-payload class on #599 and it is
# dispositioned the same way, as a pinned accepted limit. Nobody reaches those
# shapes by accident, and this hook's own header calls it an accident-catcher.
GATE_WORD='(\\.|[^[:space:];&|])'
# A separator only counts if it is REAL. `echo \; git commit` is one command
# printing three words — the `;` is escaped, so it is not a boundary. And a
# reserved word is only a command-position marker when the reserved word is
# ITSELF at a boundary: in `echo if git commit`, `if` is an argument to echo,
# not a keyword, so it must not open a command position. Both were false
# POSITIVES, which is the direction this detector is weakest in.
GATE_SEP='(^|[;&|(){}!]|\$\(|`)'
GATE_ANCHOR="(${GATE_SEP}|${GATE_SEP}[[:space:]]*(if|elif|while|until|then|do|else|coproc)[[:space:]])"
# A real assignment name, not "any run of non-space". `A-B=1` and `1A=1` are not
# assignments to bash — it runs them as commands — so treating them as prefixes
# was a false positive.
# `NAME+=` is a valid bash assignment form and prefixes a command exactly as
# `NAME=` does.
# An ARRAY-ELEMENT assignment is a command prefix too: `A[0]=x git commit` runs
# git. Narrowing this to scalar names (to kill the `A-B=1` / `1A=1` false
# positives) excluded them and opened a fail-open.
#
# THE SUBSCRIPT IS NOT AN IDENTIFIER. A bash indexed subscript is an ARITHMETIC
# EXPRESSION: it may nest brackets (`A[B[0]]=x`) and it may be empty (`A[]=x`
# evaluates to index 0). Both run git. A first cut bounded it to a nonempty,
# non-nested span and kept all four of those shapes fail-open — the THIRD time
# in this review that tightening a grammar against a false positive left a
# fail-open in the same expression.
#
# A second cut then bounded it to "anything but `=`" — and `=` is valid INSIDE a
# subscript too, because the expression is arithmetic: `A[B=1]=x`, `A[1==1]=x`,
# `A[B+=1]=x` and an associative key `A[x=y]=z` all run git. That was the FOURTH
# instance of the same pattern, and the two cuts were exact mirrors:
#
#   [^][]+   excluded empty and nested subscripts, admitted `=`
#   [^=]*    admitted empty and nested subscripts, excluded `=`
#
# A third cut bounded it by WHITESPACE, on the reasoning that an assignment
# prefix is a single shell word so its subscript could not contain unquoted
# whitespace. That reasoning is FALSE — bash's assignment lexer keeps whitespace
# inside an arithmetic subscript, and `A[1 + 2]=x git commit`, `A[1\ +\ 2]=x`
# and `declare -A A; A[foo\ bar]=x` all run git. That was the SIXTH instance.
#
# So the span is DELIBERATELY UNBOUNDED. Every attempt to characterise what a
# subscript may not contain has been wrong, in both directions, six times:
#
#   [^][]+          excluded empty and nested, admitted `=`
#   [^=]*           admitted empty and nested, excluded arithmetic `=`
#   [^[:space:]]*   excluded arithmetic whitespace
#
# and the reviewer's own proposed `(\[([^]]|\][^=])*\])?` was a fifth,
# admitting `=` while re-excluding nesting. The honest model is that a subscript
# is not enumerable by a regex: an INDEXED subscript is an arithmetic
# expression, and an ASSOCIATIVE one is an arbitrary string after expansion.
# Between them there is no character a regex can rely on excluding.
#
# THE COST, disclosed rather than discovered: an unbounded span OVERMATCHES.
# It does not validate bracket balance and cannot — POSIX ERE cannot without a
# bounded nesting limit or the scanner #533's ruling puts out of reach. So
# malformed text that merely looks like `NAME[...]=` is read as an assignment
# prefix and BLOCKED. `A[0]-B[1]=x git commit` is exactly that: oracle-inert,
# blocked, failing CLOSED, and pinned as a row rather than described.
#
# It is also greedy ACROSS A COMMAND BOUNDARY, which is a materially different
# cost and is pinned separately: in `A[0]=x; echo A[1]=y git commit` the span
# runs over the `;` and fuses two balanced fragments into one fictional
# assignment. Inert, blocked, fails CLOSED.
#
# The ONLY safety claim made here is the real NAME requirement, which is what
# keeps `A-B=1` and `1A=1` out. Three earlier versions of this comment claimed
# more than that and each claim was measured false.
GATE_ASSIGN="[A-Za-z_][A-Za-z_0-9]*(\\[.*\\])?\\+?=${GATE_WORD}*"
# The operand may be separated from the operator: `< /dev/null git commit` runs.
# `>|` is bash's clobber-override and belongs in the operator set.
GATE_REDIR="[0-9]*(<<<|<<-|<<|<>|>>|<&|>&|>\\||&>>|&>|<|>)[[:space:]]*${GATE_WORD}+"
# `builtin` is NOT a wrapper in its own right: it runs only shell BUILTINS, so
# `builtin git commit` and `builtin env git commit` are both inert and blocking
# them would be false positives. It is a prefix to exactly the builtin members
# of the set, and it stacks — `builtin builtin command git commit` invokes git.
GATE_BUILTIN="(\\\\?builtin[[:space:]]+(--[[:space:]]+)?)+\\\\?(command|eval|exec)"
GATE_EXTERNAL="(${GATE_WORD}*/)?\\\\?(env|command|eval|exec|time|nice|nohup|xargs|timeout|sudo|stdbuf)"
GATE_WRAPPER="(${GATE_BUILTIN}|\\\\?${GATE_EXTERNAL})"
# git's value-taking LONG options accept `--opt=v` and `--opt v` alike, and the
# separated form broke the chain: `git --git-dir .git commit` is an ordinary
# invocation. The separated alternative is listed first so it wins the match.
GATE_GIT_LONGVAL='--(git-dir|work-tree|namespace|exec-path|config-env|super-prefix)'
GATE_GIT="(${GATE_WORD}*/)?git(\\s+(${GATE_GIT_LONGVAL}\\s+${GATE_WORD}+|-C\\s+${GATE_WORD}+|-c\\s+${GATE_WORD}+|--${GATE_WORD}+|-[A-Za-z]))*\\s+commit\\b"
GATE_PREFIX="((${GATE_ASSIGN}|${GATE_REDIR})[[:space:]]+)*"
# The skip stops at a REAL separator only. `\;` is word content, not a boundary,
# and neither is the `&` or `|` inside a redirection operator — `env 2>&1 git
# commit`, `env &>/dev/null git commit` and `env >|/dev/null git commit` all
# invoke git. Those operators are admitted atomically; a BARE `&` or `|` still
# ends the skip, so `cmd & git commit` does not get swallowed (and is caught
# independently by the `&` anchor either way). GATE_WORD is interpolated here
# rather than re-inlined, so the six sites cannot drift apart.
GATE_SKIP="((${GATE_WORD}|[<>]\\||[<>]&|&>|[[:space:]])*[[:space:]])?"
# --- A REVIEW LEG MUST RUN THROUGH ITS LAUNCHER (#590 completion) -----------
#
# This lane sits ABOVE the git-commit detector because that detector exits 0
# on any command it does not recognise, and `codex exec` is one of them.
#
# `scripts/run-review-leg.sh` has prevented the codex stdin hang since #590
# closed, and its own header says a leg typed outside it "has no owner and no
# status". On 2026-08-14 two legs for PR #606 were typed by hand anyway, in a
# session that had read that header: one hung at 39 bytes with no
# `< /dev/null` (the exact signature #590 was closed on) and one exhausted its
# budget with no verdict. Written knowledge that is not applied is what this
# closes; the repo's answer to that has historically been to write it down
# again, and PR #606 is a seven-round demonstration of why that fails.
#
# The predicate is deliberately the smallest one that catches the accident:
# `codex` in command position followed by `exec`. There is no launcher escape
# hatch — see the note above the match itself for why one was never needed and
# why the one that existed was deleted.
#
# It reuses this gate's existing anchoring rather than adding a
# second notion of command position, so the two cannot drift — and it reads
# MASKED_COMMAND, so a quoted mention (`grep "codex exec" docs`) is already a Q
# by the time it gets here and cannot false-fire. That is the #588 defect class
# and it is not being repeated.
#
# NOT A SECURITY BOUNDARY, and the distinction is the one #479's ROADMAP note
# records about the merge gate: this sees commands issued through the Claude
# Code Bash tool. A leg launched from a terminal never meets it. It is an
# accident-catcher for the path where the accident actually happened.
# The subcommand is `exec` or its DECLARED alias `e` — `codex --help` lists
# "exec ... [aliases: e]", and `codex e --help` prints exec's help. Verified on
# the installed CLI; `ex` and `exe` do NOT resolve, so this is an alias list,
# not prefix inference, and enumerating the two is exact rather than a guess.
#
# The subcommand must be a COMPLETE token, and the boundary that proves it is a
# SHELL token boundary — whitespace, a metacharacter that actually ends a
# command, or end of line. Not "any non-word character", which is what round 4
# found: `$`, `.` and `=` all CONTINUE a token, so `SUFFIX=-server; codex
# exec$SUFFIX --help` runs `codex exec-server` and was refused. `exec-server` is
# a different subcommand and `-` was already excluded; `$`, `.` and `=` are the
# same case and are excluded the same way, by naming the boundary instead of
# negating a word class.
# `}` is NOT in the set. It only closes a group as a RESERVED WORD, which needs
# a preceding `;` or newline and its own whitespace — as a bare character it is
# an ordinary one, and `bash -c 'printf "[%s]" exec}foo'` prints one word. So
# `codex exec}foo --help` was refused. `)` stays: it is a real metacharacter.
GATE_CODEX_END="([[:space:]]|[;&|)<>]|\$)"
#
# NO OPTION MAY APPEAR BETWEEN `codex` AND THE SUBCOMMAND. That is a deliberate
# accepted limit, and it is the design this lane arrived at rather than the one
# it started with. Rounds 1-3 of cross-model review scored 3/10, 6/10, 4/10 —
# every round's findings were facts about codex's own option grammar, not about
# the accident being guarded:
#
#   round 2  an option's value is not the subcommand   `codex -C exec review`
#   round 3  compact short values                      `codex -mfoo exec`
#   round 3  `-h`/`-V` terminate and never dispatch    `codex -h exec`
#   round 3  `--image` is VARIADIC                     `codex -i a exec`
#   round 3  per-wrapper arity is not one letter class `xargs -E` vs `sudo -n`
#
# Each fix was correct and each opened new surface, because modelling a CLI's
# option grammar in a regex is building a parser — the thing #533 ruled out,
# arriving one round at a time. The score never converged.
#
# So the gap is closed instead of described. `codex` must be followed directly
# by the subcommand. This catches BOTH accidents that motivated the lane, and
# the reason is not luck: `codex exec --model X -c key=value "prompt"` is the
# shape the CLI is actually used in, with options AFTER the subcommand. An
# option BEFORE it is a shape no leg in this repo has ever been typed in.
#
# What it costs: `codex --model X exec` escapes, as does every wrapper carrying
# an option. Accepted and REPORTED rather than fixed — a missed leg is an
# accident this lane did not catch; a false refusal blocks the maintainer's own
# review. #601 is the precedent for a measured accepted limit.
GATE_CODEX="(${GATE_WORD}*/)?\\\\?codex[[:space:]]+(exec|e)${GATE_CODEX_END}"
# Wrappers, but NOT the greedy GATE_SKIP the git lane uses. GATE_SKIP consumes
# the wrapped command and restarts matching at its arguments, which turned
# `env echo codex exec`, `env grep codex exec README.md` and
# `env ls /tmp/codex exec` into refusals: the wrapper runs echo/grep/ls, and
# `codex exec` is their ARGUMENT, not a command.
#
# A wrapper may therefore carry NOTHING between itself and `codex`, for the
# same reason codex may carry no option before its subcommand: round 3 showed a
# shared letter class is wrong in both directions at once (`xargs -E` takes a
# value and was missed; `sudo -n` is boolean and caused a false refusal), and a
# per-wrapper arity table is the same parser by another name.
#
# `env codex exec` and `sudo codex exec` stay caught. `timeout 300 codex exec`
# and `nice -n 5 codex exec` no longer do — accepted with the rest.
GATE_CODEX_WRAP="(${GATE_WRAPPER}[[:space:]]+)*"
# THERE IS NO LAUNCHER ESCAPE HATCH, and removing it is what closed the last
# hole. This lane used to allow any command whose RAW text mentioned
# `run-review-leg.sh`, so that the launcher itself could not be refused. That
# check made `scripts/run-review-leg.sh out p && codex exec "q"` allowed — the
# lane satisfied by MENTIONING the launcher rather than using it.
#
# It was never needed. A launcher invocation is `scripts/run-review-leg.sh
# OUTPUT PROMPT [args]` and contains no `codex exec` token at all, so the
# predicate does not match it in the first place. Verified by neutralising the
# check and re-running: all three real launcher shapes stay ALLOWED, and the
# `&&` bypass becomes REFUSED. The whole hatch was dead weight that could only
# ever be wrong. The suite still pins the launcher shapes as allowed.
if printf '%s' "$MASKED_COMMAND" | grep -qE \
    "${GATE_ANCHOR}[[:space:]]*${GATE_PREFIX}${GATE_CODEX_WRAP}${GATE_CODEX}"; then
    echo "CROSS-MODEL REVIEW GATE: run the review leg through scripts/run-review-leg.sh, not 'codex exec' directly." >&2
    echo "  scripts/run-review-leg.sh OUTPUT_FILE PROMPT [EXTRA_CODEX_ARGS...]" >&2
    echo "The launcher gives the child /dev/null on stdin whatever the caller inherited, and its own exit status IS the leg's verdict — 0 completed, non-zero failed, nothing by your deadline means inspect and relaunch. A leg typed by hand has no owner and no status: its fate is unknown immediately, and by wall clock a hang is identical to a slow review. Measured 2026-08-14 on PR #606: one hand-typed leg hung at 39 bytes, a second returned no verdict. $BYPASS_NOTE" >&2
    exit 2
fi

if ! printf '%s' "$MASKED_COMMAND" | grep -qE \
    "${GATE_ANCHOR}[[:space:]]*${GATE_PREFIX}(${GATE_WRAPPER}[[:space:]]+${GATE_SKIP})*${GATE_GIT}"; then
    exit 0
fi

# #731: a green local test suite is commit authorization for development.
# run-local.sh writes "TREE_SHA PASS" on exit 0. Cross-model review is
# still required before merge (PR-level gate in scripts/merge-pr.sh).
LOCAL_RESULT="${SDLC_LOCAL_TEST_RESULT:-.local-test-result}"
LOCAL_TREE=$(git write-tree 2>/dev/null) || LOCAL_TREE=""
if [ -n "$LOCAL_TREE" ] && grep -q "^${LOCAL_TREE} PASS$" "$LOCAL_RESULT" 2>/dev/null; then
    exit 0
fi

REVIEW_FILE=".reviews/handoff.json"

if [ ! -f "$REVIEW_FILE" ]; then
    echo "CROSS-MODEL REVIEW REQUIRED: No .reviews/handoff.json found. Run Codex cross-model review before committing. $BYPASS_NOTE" >&2
    exit 2
fi

STATUS=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$REVIEW_FILE" \
    | head -1 \
    | sed 's/.*"status"[[:space:]]*:[[:space:]]*"//; s/"$//')

case "$STATUS" in
    CERTIFIED|REVIEWED)
        # #540: staleness keys on the CONTENT certified, never on a SHA.
        #
        # THE HOLE THIS REPLACES. The old key was `commit_sha == HEAD`.
        # PreToolUse runs BEFORE the commit, so at check time HEAD is still
        # the certified commit and the gate allows — then the commit lands
        # carrying whatever is in the index, reviewed or not. The resulting
        # commit was by construction never the one that was reviewed. That is
        # REVIEW UNIT being unenforceable by the mechanism meant to enforce
        # it. Found by Sol at file:line; Fable withdrew its own recommendation
        # to extend this gate once shown the counter-example.
        #
        # It also taxed every commit with a re-pin call — ~10 wasted tool
        # calls in one measured PR cycle — to protect nothing a content pin
        # does not.
        #
        # WHY TREE IDENTITY AND NOT patch-id. An earlier ruling chose
        # `git patch-id --stable`; both advisors amended it after measuring
        # two failures. Two diffs differing only in the indentation of an
        # added Python line produce the IDENTICAL patch-id — it ignores
        # whitespace by design, and whitespace is semantic in Python, YAML,
        # Makefiles and string literals. And at the merge boundary the thing
        # merged is the resulting TREE, not the diff, so a rebase onto moved
        # upstream keeps patch-id identical while producing content nobody
        # read. The goal was amended too, not just the primitive:
        # certification must not automatically survive a changed base.
        #
        # WHAT STAYS FREE. Message-only amend, squash and reorder with no
        # upstream movement all produce the same tree, so certification
        # survives them at zero cost. Only a change in content invalidates.
        CANDIDATE_TREE=$(grep -o '"candidate_tree"[[:space:]]*:[[:space:]]*"[^"]*"' "$REVIEW_FILE" \
            | head -1 \
            | sed 's/.*"candidate_tree"[[:space:]]*:[[:space:]]*"//; s/"$//')

        # Fail closed on an artifact that declares no content, including the
        # pre-#540 format that carried only commit_sha. Same posture #437 took
        # for a missing commit_sha and #533 for a missing branch: no
        # legacy-compat fallback, because a fallback here is the hole reopened
        # under an older key.
        if [ -z "$CANDIDATE_TREE" ]; then
            echo "CROSS-MODEL REVIEW REQUIRED: .reviews/handoff.json is $STATUS but declares no 'candidate_tree'. A certification names the content it was issued over — record it with: git write-tree. $BYPASS_NOTE" >&2
            exit 2
        fi

        # FROZEN INDEX, and this is what makes flag parsing unnecessary.
        #
        # `git commit -a` sweeps unstaged tracked changes into the commit, so
        # with a dirty tracked worktree the committed tree is not the index's
        # and no pre-commit check of the index can speak for it. The fix is
        # NOT to look for `-a` on the command line: modelling git's option
        # grammar in a regex is the #610 trap, where rounds 1-3 scored 3, 6,
        # 4 — falling, the non-convergence signature — doing exactly that,
        # and round 4 deleted all of it.
        #
        # Requiring a clean tracked worktree dissolves the case instead: with
        # nothing unstaged, `git commit` and `git commit -a` commit the same
        # tree, and the index speaks for both. Untracked files are NOT
        # examined — they are not in the index and `-a` does not add them.
        if ! git diff --quiet --ignore-submodules -- 2>/dev/null; then
            echo "CROSS-MODEL REVIEW REQUIRED: tracked files differ between the working tree and the index, so the tree that would be committed is not the one certified (git commit -a would sweep them in). Stage or revert them, then commit. $BYPASS_NOTE" >&2
            exit 2
        fi

        # The index IS the candidate: PreToolUse runs before the commit, so
        # `git write-tree` is exactly the tree the commit is about to carry.
        # It fails on an unmerged index, and that failure is left to fail
        # closed — a conflicted tree is not a reviewed tree.
        INDEX_TREE=$(git write-tree 2>/dev/null) || INDEX_TREE=""
        if [ -z "$INDEX_TREE" ] || [ "$INDEX_TREE" != "$CANDIDATE_TREE" ]; then
            echo "CROSS-MODEL REVIEW REQUIRED: the staged content is not what was certified (index tree ${INDEX_TREE:-unreadable}, certified candidate_tree $CANDIDATE_TREE). A certification authorizes the content it was issued over, not the next commit on the branch. Re-run cross-model review on the current content. $BYPASS_NOTE" >&2
            exit 2
        fi

        # base_tree is deliberately NOT checked here. At the commit boundary
        # "the base" is not observable without knowing the commit's kind — it
        # is HEAD for a normal commit and HEAD^ for an amend — and telling
        # those apart means reading `--amend` off the command line, which is
        # the option-grammar trap again.
        #
        # An earlier version of this comment justified the deferral by claiming
        # a rebase onto moved upstream always CHANGES the index tree, so the
        # check above already refuses it. Sol falsified that in round 1 of #628
        # with a running counter-example: when upstream independently produces
        # the candidate's final content, the rebase drops the now-redundant
        # branch change and the index tree is unchanged. `base_moved hook=0
        # candidate_same=yes base_changed=yes`. The claim is false and is not
        # repeated here.
        #
        # The deferral still holds, but for the narrower reason that survives:
        # PreToolUse cannot observe post-command state, so the hook was never
        # able to close this alone, and the base ref is only well-defined at
        # the merge boundary. That makes `scripts/merge-pr.sh` the sole
        # enforcement point for base_tree.
        #
        # An earlier version of this sentence said that boundary reads the base
        # from the PR's `baseRefOid`. It did, and that was the round-2 defect:
        # `baseRefOid` is the base commit ASSOCIATED WITH THE PR, a snapshot
        # that does not move when the branch does (measured — PR #615 carried
        # f8ba12b while main was at d0e1c7b). It now asks the server for the
        # branch tip directly and fails closed when it cannot.
        exit 0
        ;;
    PENDING_RECHECK)
        # #533: the in-flight review-dialogue lane.
        #
        # The protocol MANDATES this status for the whole duration of a
        # dialogue round, and this case used to fall to the refusal below —
        # so nothing could be committed during exactly the window in which
        # review work is produced, and every round was forced onto an
        # uncommitted working tree. That is the mutable-tree problem the
        # protocol's own "review committed increments" rule exists to
        # prevent, and it cost a real round: on #520 a reviewer read a tree
        # a concurrent harness mutated underneath it and filed a correct P1
        # against a defect that existed only in that mutation.
        #
        # The lane is keyed on a branch the round DECLARES, never on the hook
        # trying to prove the branch is not the remote's default. That proof
        # is unobtainable offline: default-branch-ness is server-side state,
        # and `refs/remotes/*/HEAD` is a cache with no freshness bound
        # (`git remote set-head -a` needs the network). Two review rounds were
        # spent failing to answer that strictly harder question. The round
        # already knows which branch it is about, so it writes it down, and
        # `branch` sits at exactly the trust level `status` and `commit_sha`
        # have always had. This gate is a guardrail against a cooperating but
        # fallible agent, not a sandbox.
        DECLARED_BRANCH=$(grep -o '"branch"[[:space:]]*:[[:space:]]*"[^"]*"' "$REVIEW_FILE" \
            | head -1 \
            | sed 's/.*"branch"[[:space:]]*:[[:space:]]*"//; s/"$//')
        CURRENT_BRANCH=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || CURRENT_BRANCH=""

        # Fail closed on a handoff that declares nothing — otherwise a stale
        # PENDING_RECHECK would be a forever-pass on every branch. Same
        # posture as #437's missing commit_sha: no legacy-compat fallback.
        if [ -z "$DECLARED_BRANCH" ]; then
            echo "CROSS-MODEL REVIEW REQUIRED: .reviews/handoff.json is PENDING_RECHECK but declares no 'branch'. An in-flight round must name the branch its work is on. $BYPASS_NOTE" >&2
            exit 2
        fi

        # Detached HEAD (or not a repo at all) leaves nothing to compare, so
        # the equality this lane rests on cannot be evaluated.
        if [ -z "$CURRENT_BRANCH" ]; then
            echo "CROSS-MODEL REVIEW REQUIRED: in-flight commits need a checked-out branch to match .reviews/handoff.json's declared branch '$DECLARED_BRANCH' — HEAD is detached or this is not a git repo. $BYPASS_NOTE" >&2
            exit 2
        fi

        if [ "$DECLARED_BRANCH" != "$CURRENT_BRANCH" ]; then
            echo "CROSS-MODEL REVIEW REQUIRED: .reviews/handoff.json's in-flight round declares branch '$DECLARED_BRANCH' but HEAD is on '$CURRENT_BRANCH'. This commit is not the round's work. $BYPASS_NOTE" >&2
            exit 2
        fi

        # ---- The two lines below are ACCIDENT-CATCHERS, NOT SOUNDNESS
        # ---- CLAIMS. Stated plainly because an undocumented denylist is how
        # ---- this cycle started, and because the honest framing is what
        # ---- keeps them from being mistaken for a boundary and either
        # ---- trusted or deleted.
        #
        # (1) A handoff that declares `main` would satisfy the equality above
        # and carry in-flight work onto a trunk. Refusing the two literal
        # names catches that accident. It does NOT establish that any other
        # name is safe — a repo whose default branch is `develop` is not
        # covered, and cannot be, per the offline argument above.
        case "$CURRENT_BRANCH" in
            main|master)
                echo "CROSS-MODEL REVIEW REQUIRED: in-flight commits are not allowed on '$CURRENT_BRANCH'. Work the round on a feature branch. $BYPASS_NOTE" >&2
                exit 2
                ;;
        esac

        # (2) This lane compares the handoff against HEAD in the HOOK's cwd,
        # so a command that relocates git elsewhere would be judged by a
        # branch it will not commit to. Refusing a plain relocation token
        # catches that accident. It is deliberately over-strict — the token
        # can appear inside a commit message and refuse a legitimate commit —
        # because the cost of a false match is a refusal, never an allow.
        #
        # Read on the RAW command value, never MASKED_COMMAND: masking exists
        # so DETECTION can ignore quoted prose, and it destroys exactly what
        # this needs to see.
        #
        # Reachability, stated because the alternative is a comment that
        # overpromises: this only ever sees commands DETECTION delivered. A
        # space-separated long flag (`git --work-tree /tmp commit`) fails the
        # structural match upstream and exits 0 before reaching any lane, so
        # this line never runs for it. That hole predates this lane and is
        # filed as #582; the `-C` and `--flag=value` forms do reach here.
        if printf '%s' "$COMMAND_VALUE" | grep -qE '(^|[[:space:]])(-C([[:space:]]|=)|--git-dir|--work-tree)'; then
            echo "CROSS-MODEL REVIEW REQUIRED: an in-flight commit may not carry a git relocation flag (-C / --git-dir / --work-tree) — this lane can only vouch for the branch checked out where the hook runs. $BYPASS_NOTE" >&2
            exit 2
        fi

        exit 0
        ;;
    *)
        echo "CROSS-MODEL REVIEW REQUIRED: .reviews/handoff.json status is '$STATUS' (need REVIEWED, CERTIFIED, or an in-flight PENDING_RECHECK round declaring its branch). Run Codex cross-model review before committing. $BYPASS_NOTE" >&2
        exit 2
        ;;
esac
