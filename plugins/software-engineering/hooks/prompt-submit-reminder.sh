#!/bin/bash
# UserPromptSubmit hook: if the prompt looks like a coding task, inject a one-line
# reminder pointing at the software-engineering skill.
set -euo pipefail

input=$(cat)
prompt=$(echo "$input" | jq -r '.prompt // ""')

if [ -z "$prompt" ]; then
  exit 0
fi

# Coding-intent matcher. Case-insensitive.
if echo "$prompt" | grep -Eiq '(\b(implement|fix(ing)?|refactor|review|add (a )?feature|write tests?|design (an? )?api|build (a )?service|debug)\b)'; then
  echo '{"systemMessage": "Software engineering principles apply to this task. If not already loaded, invoke the software-engineering skill (see plugins/software-engineering)."}'
fi
