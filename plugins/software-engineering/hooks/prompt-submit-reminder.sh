#!/bin/bash
# UserPromptSubmit hook: if the prompt looks like a coding task, inject a
# reminder about the software-engineering skill and a Definition-of-Done
# checklist to keep in mind while implementing.
set -euo pipefail

input=$(cat)
prompt=$(echo "$input" | jq -r '.prompt // ""')

if [ -z "$prompt" ]; then
  exit 0
fi

# Coding-intent matcher. Case-insensitive.
if ! echo "$prompt" | grep -Eiq '\b(implement|fix(ing)?|refactor|review|add (a )?feature|write tests?|design (an? )?api|build (a )?service|debug)\b'; then
  exit 0
fi

message="Software engineering principles apply to this task. If not already loaded, invoke the software-engineering skill (see plugins/software-engineering).

Definition-of-Done — keep these in mind while implementing:
- Code compiles / type-checks
- All tests pass locally (new and existing)
- ≥80% test coverage on the changed code
- Manually exercised the actual feature path
- Adjacent features checked for regressions
- PR description tells the reviewer what, why, and how to verify
- Commits curated into a reviewable story
- Docs / runbooks updated if behavior or contracts changed"

echo "$message" | jq -Rs '{systemMessage: .}'
