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

# --- regression: `git commit` with no `-m` must not abort (review finding 1) ---
# `grep -oE` finds no `-m ...` match on a no-`-m` commit and exits 1; under
# `pipefail` that failure is the pipeline's exit status even though `sed` and
# `head` downstream both succeed on the empty input. A bare
# `message=$(... | ... | ...)` assignment then aborts the whole script under
# `set -e` with that exit 1 — before ever reaching the `.git/COMMIT_EDITMSG`
# fallback a few lines below, which exists specifically to handle this case.
# This fires on ordinary `git commit`, `git commit --amend`, and
# `git commit -a` — not just malformed input.

# Bare `git commit`, no COMMIT_EDITMSG on disk at all: the message stays
# empty end to end (no `-m`, no fallback file), and the script must still
# reach `exit 0` rather than dying on the `grep -oE` no-match.
REPO="$(make_repo)"
rm -f "$REPO/.git/COMMIT_EDITMSG"
assert_silent "bug-fix: bare 'git commit' with no -m and no COMMIT_EDITMSG does not abort" \
  "$REPO" "$SCRIPT" "$(bash_json "git commit")"
rm -rf "$REPO"

# Bare `git commit`, no `-m`, but a real `.git/COMMIT_EDITMSG` left by an
# editor-driven commit describes a bug fix and no test file is staged. This
# proves the COMMIT_EDITMSG fallback doesn't just get reached — it drives the
# warning end to end.
REPO="$(make_repo)"
printf 'fix: handle nil pointer\n' > "$REPO/.git/COMMIT_EDITMSG"
printf 'x\n' > "$REPO/handler.go"
git -C "$REPO" add handler.go
assert_contains "bug-fix: bare 'git commit' falls back to COMMIT_EDITMSG and warns" \
  "$REPO" "$SCRIPT" "$(bash_json "git commit")" \
  "no test changes"
rm -rf "$REPO"

# `git commit --amend` with no `-m`: COMMIT_EDITMSG names a fix, but a test
# file is staged this time, so the fallback-driven check must stay silent —
# proving both that --amend doesn't abort and that the "tests present" path
# still works when the message came from the fallback.
REPO="$(make_repo)"
printf 'fix: handle nil pointer\n' > "$REPO/.git/COMMIT_EDITMSG"
printf 'x\n' > "$REPO/handler.go"
printf 'x\n' > "$REPO/handler_test.go"
git -C "$REPO" add handler.go handler_test.go
assert_silent "bug-fix: 'git commit --amend' with no -m does not abort" \
  "$REPO" "$SCRIPT" "$(bash_json "git commit --amend")"
rm -rf "$REPO"

# `git commit -a` with no `-m` and a non-fix fallback message: must not
# abort and must stay silent (message doesn't match the fix heuristic).
REPO="$(make_repo)"
printf 'chore: bump deps\n' > "$REPO/.git/COMMIT_EDITMSG"
printf 'x\n' > "$REPO/handler.go"
git -C "$REPO" add handler.go
assert_silent "bug-fix: 'git commit -a' with no -m does not abort" \
  "$REPO" "$SCRIPT" "$(bash_json "git commit -a")"
rm -rf "$REPO"

# --- regression: a subshell-wrapped commit must still arm the tripwire
# (blocking finding 3) ---
# The boundary class here was `[[:space:];&|]` — missing `(` entirely, unlike
# pre-pr-sweep-check.sh's `gh` class which already had it. A commit wrapped
# in a subshell, `(git commit -m "fix: ...")`, is exactly the shape that `(`
# exists to catch, and it silently fell through: no staged-test check ever
# ran on the one commit this hook exists to catch.
REPO="$(make_repo)"
printf 'x\n' > "$REPO/handler.go"
git -C "$REPO" add handler.go
assert_contains "bug-fix: subshell-wrapped fix commit without tests still warns" \
  "$REPO" "$SCRIPT" "$(bash_json '(git commit -m "fix: parser crash")')" \
  "no test changes"
rm -rf "$REPO"
