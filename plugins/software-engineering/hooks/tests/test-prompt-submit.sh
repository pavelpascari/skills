# Cases for hooks/prompt-submit-reminder.sh
SCRIPT="$HOOKS_DIR/prompt-submit-reminder.sh"
REPO="$(make_repo)"

assert_silent "prompt-submit: empty prompt is ignored" \
  "$REPO" "$SCRIPT" "$(prompt_json "")"

assert_silent "prompt-submit: non-coding prompt is ignored" \
  "$REPO" "$SCRIPT" "$(prompt_json "what time is the standup")"

assert_contains "prompt-submit: coding prompt gets the DoD checklist" \
  "$REPO" "$SCRIPT" "$(prompt_json "implement the retry logic")" \
  "Definition-of-Done"

assert_contains "prompt-submit: 'fix' also triggers" \
  "$REPO" "$SCRIPT" "$(prompt_json "fix the flaky test")" \
  "software-engineering skill"

assert_contains "prompt-submit: the DoD reminder mentions the deferral ledger" \
  "$REPO" "$SCRIPT" "$(prompt_json "implement the retry logic")" \
  "deferred-review-flags.md"

# --- regression: malformed/absent JSON must not exit non-zero (mirrors
# pre-pr-sweep-check.sh's fix — see test-pre-pr-sweep.sh review finding 6) ---
# jq exits non-zero on a parse error; a bare `var=$(jq ...)` assignment left
# that failure to `set -e`, which would abort the script with jq's own exit
# status instead of the 0 every other path in this hook guarantees.
assert_silent "prompt-submit: malformed JSON on stdin exits silently" \
  "$REPO" "$SCRIPT" 'not json{{{'

assert_silent "prompt-submit: empty stdin exits silently" \
  "$REPO" "$SCRIPT" ''

rm -rf "$REPO"
