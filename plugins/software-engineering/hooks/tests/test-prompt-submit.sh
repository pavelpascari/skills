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

rm -rf "$REPO"
