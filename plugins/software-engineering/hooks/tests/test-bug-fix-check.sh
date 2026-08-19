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
