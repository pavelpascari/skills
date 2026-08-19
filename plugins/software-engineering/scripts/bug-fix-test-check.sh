#!/bin/bash
# PreToolUse(Bash) hook: when the user is about to `git commit` a bug fix, warn
# if no test files are staged. Encodes the "reproduce-then-fix" principle.
# Non-blocking.
set -euo pipefail

input=$(cat)

# Malformed JSON (or no JSON at all, e.g. empty stdin) makes jq exit non-zero.
# A bare assignment failing there would abort the script under `set -e` with
# jq's own exit status — exactly the "hooks never block" violation this
# script guards against everywhere else. `|| exit 0` keeps the failure from
# ever reaching `set -e`.
tool_name=$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null) || exit 0

if [ "$tool_name" != "Bash" ]; then
  exit 0
fi

command=$(jq -r '.tool_input.command // ""' <<<"$input" 2>/dev/null) || exit 0

# grep is line-based and `.` cannot span newlines, so a shell line-continuation —
# `git \` followed by `  commit -m "fix: x"` on the next line — would otherwise never
# match the pattern below even though it is one logical command. Join backslash-continued
# lines into a single line first (dropping the trailing `\`, keeping a space so tokens
# don't fuse) before matching. This reads all of $command via a single awk pass with no
# early exit, so it is safe against SIGPIPE regardless of input size.
#
# Kept identical, character for character, to the continuation-join block in
# hooks/pre-pr-sweep-check.sh — see hooks/tests/test-boundary-drift.sh, which fails the
# suite if the two preprocessing idioms drift apart. The two scripts had already drifted
# once on the boundary class below (this one was missing `(` entirely); this same class of
# bug (one script preprocesses differently than the other) is exactly what let a
# continued `git \` + `  commit -m "fix: x"` slip past this hook silently (blocking
# finding 2) — pre-pr-sweep-check.sh already joined continuations, this script did not.
# CONTINUATION-JOIN-BEGIN
joined=$(printf '%s\n' "$command" | awk '
  {
    line = (buf != "") ? buf $0 : $0
    if (line ~ /\\$/) {
      sub(/\\$/, " ", line)
      buf = line
    } else {
      print line
      buf = ""
    }
  }
  END { if (buf != "") print buf }
')
# CONTINUATION-JOIN-END

# Only interested in `git commit ...`. Match `git commit` as a word boundary so
# `git commit-tree` and other subcommands are excluded.
#
# Boundary class: kept identical, character for character, to the
# `gh_boundary` class in hooks/pre-pr-sweep-check.sh (see that file's comment
# for the full rationale — quoted wrappers like `eval "..."`/`bash -c
# "..."`/`` `...` `` need to match, and a subshell-wrapped commit like
# `(git commit -m "fix: ...")` needs its `(` in the class too). The two
# scripts had already drifted once (this one was missing `(` entirely) — see
# hooks/tests/test-boundary-drift.sh, which fails the suite if they drift
# apart again.
git_boundary=$(printf '%b' '[[:space:];&|(\042\047\0140]')
if ! echo "$joined" | grep -Eq "(^|${git_boundary})git[[:space:]]+commit(\$|[[:space:]])"; then
  exit 0
fi

# Extract the commit message from the command itself. Only flags that carry the
# message inline are usable here — see the note below on why there is no
# .git/COMMIT_EDITMSG fallback.
#
# Git accepts `-m` both with a space before its value (`-m "text"`) and
# attached directly to it (`-m"text"`, `-m'text'`, bare `-mtext`) — the
# spaced-only pattern this used to have (`-m[[:space:]]+(...)`) silently
# missed every attached form, extracting an empty message and skipping the
# fix heuristic on an entirely ordinary `git commit -m"fix: ..."`. The
# `(^|[[:space:]])` prefix anchors `-m` to a real flag boundary (start of
# line or preceded by whitespace) so the literal substring "-m" inside
# `--message` is never mistaken for this flag; `--message` is a different flag
# and is matched separately below. The three value alternatives — double-quoted, single-quoted, or
# bare — apply whether or not a space preceded them, and the quoted
# alternatives only terminate on their own matching closing quote, so an
# `-m` appearing inside the message text itself (already inside a quote) is
# just message content, not a second flag boundary.
#
# `grep -oE` legitimately finds no match on any commit with no `-m` (`git
# commit`, `--amend`, `-a`, ...) and exits 1. Under `pipefail` that failure
# is the whole pipeline's exit status even though `sed`/`head` downstream
# both succeed on the resulting empty input, so a bare assignment here would
# abort the script under `set -e` — on ordinary commits, not just malformed
# input — before reaching the `--message` match below or the empty-message
# exit. `|| true`
# on the pipeline lets a "no match" resolve to an empty $message instead,
# matching the `staged=$(git diff --cached ... || true)` guard later in this
# script.
message=$(echo "$joined" | grep -oE -- "(^|[[:space:]])-m([[:space:]]+(\"[^\"]*\"|'[^']*'|[^[:space:]]+)|\"[^\"]*\"|'[^']*'|[^[:space:]\"']+)" | sed -E 's/^[[:space:]]?-m[[:space:]]*//; s/^["'"'"']//; s/["'"'"']$//' | head -1 || true)
# `--message` is the same intent expressed as a long flag, and is just as
# knowable here as `-m`. Git's parse-options accepts BOTH `--message=text` and
# `--message text` — matching only the `=` form leaves the spaced form silently
# unmatched, which is the same silent-by-construction miss the attached `-m`
# forms had. The separator alternation `(=|[[:space:]]+)` covers both, and the
# value alternatives mirror the `-m` pattern above.
if [ -z "$message" ]; then
  message=$(echo "$joined" | grep -oE -- "(^|[[:space:]])--message(=|[[:space:]]+)(\"[^\"]*\"|'[^']*'|[^[:space:]]+)" | sed -E 's/^[[:space:]]?--message(=|[[:space:]]+)//; s/^["'"'"']//; s/["'"'"']$//' | head -1 || true)
fi

# There is deliberately NO fallback to .git/COMMIT_EDITMSG.
#
# This is a PreToolUse hook: it runs *before* git does. On a commit with no
# message flag (`git commit`, `git commit --amend`, `git commit -a`), the
# message does not exist yet — the editor that writes COMMIT_EDITMSG opens
# after this hook has already returned. What sits in that file at hook time is
# the *previous* commit's message.
#
# The fallback that used to be here therefore did not read "the message about
# to be written". It read the last one, and warned about it: commit a bug fix
# with a test, then commit an unrelated refactor via the editor, and this hook
# would warn on the refactor because the stale file still said "fix: ...".
# A warning derived from the wrong commit is worse than no warning, because it
# teaches the reader to dismiss the hook.
#
# So when the message is not determinable, this hook says nothing. Catching
# editor-authored commits needs a hook that runs after git, which is a
# different mechanism, not a fallback bolted onto this one.

if [ -z "$message" ]; then
  exit 0
fi

# Heuristic: does the message look like a bug fix?
if ! echo "$message" | grep -Eiq '\b(fix|bug|bugfix|hotfix|patch)\b'; then
  exit 0
fi

# Inspect staged file names for test-file patterns.
staged=$(git diff --cached --name-only 2>/dev/null || true)
if [ -z "$staged" ]; then
  exit 0
fi

if echo "$staged" | grep -Eq '(_test\.go$|\.test\.[jt]sx?$|\.spec\.[jt]sx?$|^test_.*\.py$|.*_test\.py$|.*Test\.java$|.*Test\.kt$|.*_spec\.rb$)'; then
  # Tests are present — looks good. Exit silently.
  exit 0
fi

# No tests in this commit. Emit a non-blocking warning.
jq -Rs '{systemMessage: ("Bug-fix commit detected with no test changes in the staged diff. By convention, every bug fix begins with a failing test that demonstrates the bug. If you have one in a separate commit, that is fine — otherwise consider adding a reproducing test to this commit. Commit message subject: " + .)}' <<< "$message"
