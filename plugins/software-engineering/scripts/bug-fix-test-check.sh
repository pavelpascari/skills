#!/bin/bash
# PreToolUse(Bash) hook: when the user is about to `git commit` a bug fix, warn
# if no test files are staged. Encodes the "reproduce-then-fix" principle.
# Non-blocking.
set -euo pipefail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // ""')

if [ "$tool_name" != "Bash" ]; then
  exit 0
fi

command=$(echo "$input" | jq -r '.tool_input.command // ""')

# Only interested in `git commit ...`. Match `git commit` as a word boundary so
# `git commit-tree` and other subcommands are excluded.
if ! echo "$command" | grep -Eq '(^|[[:space:];&|])git[[:space:]]+commit($|[[:space:]])'; then
  exit 0
fi

# Extract the commit message: prefer the -m argument; otherwise, fall back to .git/COMMIT_EDITMSG.
message=$(echo "$command" | grep -oE -- '-m[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]+)' | sed -E 's/^-m[[:space:]]+//; s/^["'"'"']//; s/["'"'"']$//' | head -1)
if [ -z "$message" ] && [ -r .git/COMMIT_EDITMSG ]; then
  message=$(head -1 .git/COMMIT_EDITMSG)
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
