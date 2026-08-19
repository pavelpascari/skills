# Cases for scripts/bug-fix-test-check.sh
SCRIPT="$PLUGIN_ROOT/scripts/bug-fix-test-check.sh"

REPO="$(make_repo)"
assert_silent "bug-fix: non-Bash tool is ignored" \
  "$REPO" "$SCRIPT" '{"tool_name": "Read", "tool_input": {}}'

assert_silent "bug-fix: git commit-tree is not a commit" \
  "$REPO" "$SCRIPT" "$(bash_json "git commit-tree abc123")"

assert_silent "bug-fix: a feat commit is ignored" \
  "$REPO" "$SCRIPT" "$(bash_json "git commit -m 'feat: add endpoint'")"
rm -rf "$REPO"

# A fix commit with no staged test files warns.
REPO="$(make_repo)"
printf 'x\n' > "$REPO/handler.go"
git -C "$REPO" add handler.go
assert_contains "bug-fix: fix commit without tests warns" \
  "$REPO" "$SCRIPT" "$(bash_json "git commit -m 'fix: handle nil pointer'")" \
  "no test changes"
rm -rf "$REPO"

# A fix commit with a staged test file is silent.
REPO="$(make_repo)"
printf 'x\n' > "$REPO/handler.go"
printf 'x\n' > "$REPO/handler_test.go"
git -C "$REPO" add handler.go handler_test.go
assert_silent "bug-fix: fix commit with a staged test is silent" \
  "$REPO" "$SCRIPT" "$(bash_json "git commit -m 'fix: handle nil pointer'")"
rm -rf "$REPO"

# --- regression: malformed/absent JSON must not exit non-zero (mirrors
# pre-pr-sweep-check.sh's fix — see test-pre-pr-sweep.sh review finding 6) ---
# jq exits non-zero on a parse error; a bare `var=$(jq ...)` assignment left
# that failure to `set -e`, which would abort the script with jq's own exit
# status instead of the 0 every other path in this hook guarantees.
REPO="$(make_repo)"
assert_silent "bug-fix: malformed JSON on stdin exits silently" \
  "$REPO" "$SCRIPT" 'not json{{{'

assert_silent "bug-fix: empty stdin exits silently" \
  "$REPO" "$SCRIPT" ''
rm -rf "$REPO"
