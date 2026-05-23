#!/bin/bash
# Stop hook: when the agent appears to be wrapping up, print a Definition-of-Done
# checklist with hints about anything that looks unfinished. Non-blocking.
set -euo pipefail

# We don't need the hook input for this check, but consume stdin to be polite.
cat > /dev/null

# Only fire inside a git repo.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

dirty=""
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  dirty="yes"
fi

# Compose a checklist message. JSON-escape via jq -Rs.
checklist="Definition-of-Done check:
- Code compiles / type-checks
- All tests pass locally (new and existing)
- ≥80% test coverage on the changed code
- Manually exercised the actual feature path
- Adjacent features checked for regressions
- PR description tells the reviewer what, why, and how to verify
- Commits curated into a reviewable story
- Docs / runbooks updated if behavior or contracts changed"

if [ -n "$dirty" ]; then
  checklist="$checklist

Uncommitted changes detected — commit or explicitly note WIP before declaring done."
fi

# Emit as systemMessage.
echo "$checklist" | jq -Rs '{systemMessage: .}'
