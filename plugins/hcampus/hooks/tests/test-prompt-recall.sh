#!/bin/bash
# Tests for hooks/prompt-recall-nudge.sh — the recall nudge.
# Sourced by run-tests.sh.

SCRIPT="$HOOKS_DIR/prompt-recall-nudge.sh"
dir="$(scratch)"

# Explicit memory operations.
assert_contains "prompt-recall: fires on an explicit remember" \
  "$dir" "$SCRIPT" "$(prompt_json "remember that we deploy on Thursdays")" \
  "hcampus-memory skill"

assert_contains "prompt-recall: fires on forget" \
  "$dir" "$SCRIPT" "$(prompt_json "forget what I said about the staging database")" \
  "hcampus-memory skill"

# Implicit references to settled history — the case the current context may not
# contain at all, and the reason this hook is worth its noise.
assert_contains "prompt-recall: fires on a reference to a past decision" \
  "$dir" "$SCRIPT" "$(prompt_json "wire it up the way we decided last week")" \
  "hcampus-memory skill"

assert_contains "prompt-recall: fires on 'as discussed'" \
  "$dir" "$SCRIPT" "$(prompt_json "add the retry logic as discussed")" \
  "hcampus-memory skill"

assert_contains "prompt-recall: fires on a question about prior reasoning" \
  "$dir" "$SCRIPT" "$(prompt_json "why did we drop the Postgres backend?")" \
  "hcampus-memory skill"

# The untrusted-data warning must travel with every nudge. Recall returns
# caller-supplied text, and a nudge to read it without that caveat is an
# instruction to treat stored text as authoritative.
assert_contains "prompt-recall: always carries the untrusted-data warning" \
  "$dir" "$SCRIPT" "$(prompt_json "recall the deployment constraints")" \
  "untrusted data"

# The nudge is case-insensitive.
assert_contains "prompt-recall: matches regardless of case" \
  "$dir" "$SCRIPT" "$(prompt_json "REMEMBER: the API key rotates monthly")" \
  "hcampus-memory skill"

# Self-contained work must stay silent, or the nudge appears on every prompt
# and stops being read.
assert_silent "prompt-recall: silent on a self-contained request" \
  "$dir" "$SCRIPT" "$(prompt_json "format this JSON file and sort the keys")"

assert_silent "prompt-recall: silent on an ordinary coding task" \
  "$dir" "$SCRIPT" "$(prompt_json "add a nil check to the parser")"

assert_silent "prompt-recall: silent on an empty prompt" \
  "$dir" "$SCRIPT" "$(prompt_json "")"

assert_silent "prompt-recall: silent and exits 0 on malformed stdin" \
  "$dir" "$SCRIPT" "not json"

assert_silent "prompt-recall: silent and exits 0 on empty stdin" \
  "$dir" "$SCRIPT" ""
