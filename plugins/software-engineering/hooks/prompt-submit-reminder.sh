#!/bin/bash
# UserPromptSubmit hook: if the prompt looks like a coding task, inject a
# reminder about the software-engineering skill and a Definition-of-Done
# checklist to keep in mind while implementing.
set -euo pipefail

input=$(cat)

# Malformed JSON (or no JSON at all, e.g. empty stdin) makes jq exit non-zero.
# A bare assignment failing there would abort the script under `set -e` with
# jq's own exit status — exactly the "hooks never block" violation this
# script guards against everywhere else. `|| exit 0` keeps the failure from
# ever reaching `set -e`.
prompt=$(jq -r '.prompt // ""' <<<"$input" 2>/dev/null) || exit 0

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
- Docs / runbooks updated if behavior or contracts changed
- Anything noticed and ruled out of scope is recorded in docs/deferred-review-flags.md"

echo "$message" | jq -Rs '{systemMessage: .}'
