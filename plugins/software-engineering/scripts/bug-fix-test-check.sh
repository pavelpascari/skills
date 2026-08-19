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
if ! echo "$command" | grep -Eq "(^|${git_boundary})git[[:space:]]+commit(\$|[[:space:]])"; then
  exit 0
fi

# Extract the commit message: prefer the -m argument; otherwise, fall back to .git/COMMIT_EDITMSG.
#
# `grep -oE` legitimately finds no match on any commit with no `-m` (`git
# commit`, `--amend`, `-a`, ...) and exits 1. Under `pipefail` that failure
# is the whole pipeline's exit status even though `sed`/`head` downstream
# both succeed on the resulting empty input, so a bare assignment here would
# abort the script under `set -e` — on ordinary commits, not just malformed
# input — before ever reaching the COMMIT_EDITMSG fallback below. `|| true`
# on the pipeline lets a "no match" resolve to an empty $message instead,
# matching the `staged=$(git diff --cached ... || true)` guard later in this
# script.
message=$(echo "$command" | grep -oE -- '-m[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]+)' | sed -E 's/^-m[[:space:]]+//; s/^["'"'"']//; s/["'"'"']$//' | head -1 || true)
if [ -z "$message" ] && [ -r .git/COMMIT_EDITMSG ]; then
  # Guarded for the same reason, even though a file already passed `-r` is
  # very unlikely to fail to read: keep every command that reads external
  # state on a legitimately-fallible path guarded the same way.
  message=$(head -1 .git/COMMIT_EDITMSG 2>/dev/null || true)
fi

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
