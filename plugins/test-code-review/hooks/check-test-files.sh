#!/bin/bash
# PostToolUse hook: detect when test files are written or edited.
# If the file matches a test pattern, inject a system message prompting
# Claude to run the test-code-review skill.
set -euo pipefail

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // ""')
file_path=""

if [ "$tool_name" = "Write" ] || [ "$tool_name" = "Edit" ]; then
  file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')
else
  exit 0
fi

if [ -z "$file_path" ]; then
  exit 0
fi

# Match common test file patterns across languages
basename=$(basename "$file_path")
case "$basename" in
  *_test.go|*_test.py|test_*.py|*.test.ts|*.spec.ts|*.test.js|*.spec.js|*.test.tsx|*.spec.tsx|*.test.jsx|*.spec.jsx|*_test.rs|*Test.java|*Test.kt|*_spec.rb)
    echo "{\"systemMessage\": \"A test file was just modified: $file_path. Consider using the test-code-review skill to review the test changes for correctness — especially check for weakened assertions, missing coverage, and tests that may have been rewritten to match buggy behavior instead of catching it.\"}"
    ;;
  *)
    # Not a test file, no action
    exit 0
    ;;
esac
