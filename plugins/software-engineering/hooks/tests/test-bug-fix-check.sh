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

# INVERTED, deliberately. This case used to assert that a bare `git commit`
# falls back to `.git/COMMIT_EDITMSG` and warns from it. That fallback has been
# removed: this is a PreToolUse hook, so on an editor-authored commit the
# message has not been written yet and that file still holds the PREVIOUS
# commit's message. The old behaviour warned about the wrong commit — fix a bug
# with a test, then commit an unrelated refactor via the editor, and the stale
# "fix: ..." would trigger a warning on the refactor.
#
# The assertion is now the opposite: a populated COMMIT_EDITMSG must be ignored.
REPO="$(make_repo)"
printf 'fix: handle nil pointer\n' > "$REPO/.git/COMMIT_EDITMSG"
printf 'x\n' > "$REPO/handler.go"
git -C "$REPO" add handler.go
assert_silent "bug-fix: bare 'git commit' ignores a stale COMMIT_EDITMSG" \
  "$REPO" "$SCRIPT" "$(bash_json "git commit")"
rm -rf "$REPO"

# `git commit --amend` with no `-m`: must not abort on the `grep -oE` no-match.
# It is silent because no message flag is present, so the message is not
# determinable at PreToolUse time — NOT because a test file happens to be
# staged, and NOT because COMMIT_EDITMSG was consulted. Both are present here
# only to prove they make no difference to the outcome.
REPO="$(make_repo)"
printf 'fix: handle nil pointer\n' > "$REPO/.git/COMMIT_EDITMSG"
printf 'x\n' > "$REPO/handler.go"
printf 'x\n' > "$REPO/handler_test.go"
git -C "$REPO" add handler.go handler_test.go
assert_silent "bug-fix: 'git commit --amend' with no -m does not abort" \
  "$REPO" "$SCRIPT" "$(bash_json "git commit --amend")"
rm -rf "$REPO"

# `git commit -a` with no `-m`: must not abort, and must stay silent because
# no message flag is present. The COMMIT_EDITMSG content is irrelevant now and
# is left here only to show it is not read.
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

# --- regression: a backslash-continued `git commit` must still arm the
# tripwire (blocking finding 2) ---
# grep is line-based and `.` cannot span newlines, so `git \` followed by
# `  commit -m "fix: x"` on the next line (an ordinary shell line-continuation)
# previously fell through the `git commit` pattern silently: pre-pr-sweep-check.sh
# already joined backslash-continued lines before matching, but this script
# matched raw $command with no such join — the same bug class already fixed
# for --add-reviewer in the sibling script, just recurring here for `git commit`.
REPO="$(make_repo)"
printf 'x\n' > "$REPO/handler.go"
git -C "$REPO" add handler.go
CONTINUED_COMMIT_CMD=$'git \\\n  commit -m "fix: x"'
assert_contains "bug-fix: line-continued 'git commit' still warns" \
  "$REPO" "$SCRIPT" "$(bash_json "$CONTINUED_COMMIT_CMD")" \
  "no test changes"
rm -rf "$REPO"

# --- regression: git's attached short-option `-m` forms must still arm the
# tripwire (sweep-3 blocking finding 1) ---
# The extraction regex required whitespace between `-m` and its value
# (`-m[[:space:]]+(...)`), but git also accepts the attached form with no
# space: `-m"text"`, `-m'text'`, and bare `-mtext` all work and record that
# subject on an ordinary git invocation. Each previously extracted an empty
# message, skipped the fix heuristic, and exited silently — the hook's single
# purpose, bypassed by a perfectly normal commit.
REPO="$(make_repo)"
printf 'x\n' > "$REPO/handler.go"
git -C "$REPO" add handler.go
assert_contains "bug-fix: attached double-quoted -m ('-m\"...\"') still warns" \
  "$REPO" "$SCRIPT" "$(bash_json 'git commit -m"fix: nil pointer"')" \
  "no test changes"
rm -rf "$REPO"

REPO="$(make_repo)"
printf 'x\n' > "$REPO/handler.go"
git -C "$REPO" add handler.go
assert_contains "bug-fix: attached single-quoted -m still warns" \
  "$REPO" "$SCRIPT" "$(bash_json "git commit -m'fix: nil pointer'")" \
  "no test changes"
rm -rf "$REPO"

REPO="$(make_repo)"
printf 'x\n' > "$REPO/handler.go"
git -C "$REPO" add handler.go
assert_contains "bug-fix: attached bare -m ('-mfix') still warns" \
  "$REPO" "$SCRIPT" "$(bash_json "git commit -mfix")" \
  "no test changes"
rm -rf "$REPO"

# An `-m` appearing inside the commit message text itself must not confuse
# the extraction into truncating early or splitting the message. The quoted
# alternatives only terminate on their own matching closing quote, so an
# embedded "-m" mid-message is just ordinary text, not a second flag boundary.
REPO="$(make_repo)"
printf 'x\n' > "$REPO/handler.go"
git -C "$REPO" add handler.go
assert_contains "bug-fix: -m embedded inside the quoted message text does not confuse extraction" \
  "$REPO" "$SCRIPT" "$(bash_json 'git commit -m "fix: document the -m flag behavior"')" \
  "no test changes"
rm -rf "$REPO"

# --- output-format contract: stdout must be JSON with a systemMessage key
# (sweep-3 blocking finding 2) ---
# hooks.json wires this script's stdout straight into Claude Code's hook
# protocol, which expects `{"systemMessage": "..."}` — a malformed key (e.g. a
# typo'd "systemMesage") is silently dropped by the harness rather than shown
# to the agent, and no existing assertion here would catch that: assert_contains
# only checks a substring appears somewhere in stdout, not that stdout is
# valid, correctly-keyed JSON. Mirrors the same assertion in
# test-pre-pr-sweep.sh and test-prompt-submit.sh.
REPO="$(make_repo)"
printf 'x\n' > "$REPO/handler.go"
git -C "$REPO" add handler.go
out="$(run_hook_in "$REPO" "$SCRIPT" "$(bash_json "git commit -m 'fix: handle nil pointer'")")"
if printf '%s' "$out" | jq -e 'type == "object" and has("systemMessage")' >/dev/null 2>&1; then
  pass "bug-fix: stdout is JSON with a systemMessage key"
else
  fail "bug-fix: stdout is JSON with a systemMessage key" "got: $out"
fi
rm -rf "$REPO"

# --- message forms knowable before git runs ---

# `--message=` is the long form of `-m` and just as determinable at PreToolUse time.
REPO="$(make_repo)"
printf 'x\n' > "$REPO/handler.go"
git -C "$REPO" add handler.go
assert_contains "bug-fix: --message= form is recognised" \
  "$REPO" "$SCRIPT" "$(bash_json "git commit --message='fix: nil pointer'")" \
  "no test changes"
rm -rf "$REPO"

# A stale .git/COMMIT_EDITMSG must NOT be read. This is a PreToolUse hook: on an
# editor-authored commit the message does not exist yet, and that file holds the
# PREVIOUS commit's message. Warning from it means warning about the wrong commit.
REPO="$(make_repo)"
printf 'x\n' > "$REPO/refactor.go"
git -C "$REPO" add refactor.go
printf 'fix: a bug fixed in some earlier commit\n' > "$REPO/.git/COMMIT_EDITMSG"
assert_silent "bug-fix: a stale COMMIT_EDITMSG does not trigger a warning" \
  "$REPO" "$SCRIPT" "$(bash_json "git commit")"
assert_silent "bug-fix: a stale COMMIT_EDITMSG does not trigger on --amend either" \
  "$REPO" "$SCRIPT" "$(bash_json "git commit --amend")"
rm -rf "$REPO"
