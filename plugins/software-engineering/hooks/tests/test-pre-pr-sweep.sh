# Cases for hooks/pre-pr-sweep-check.sh
SCRIPT="$HOOKS_DIR/pre-pr-sweep-check.sh"

# --- commands that must NOT arm the tripwire ---
REPO="$(make_repo)"

assert_silent "sweep: non-Bash tool is ignored" \
  "$REPO" "$SCRIPT" '{"tool_name": "Read", "tool_input": {}}'

assert_silent "sweep: gh pr list is not a review request" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr list --author @me")"

assert_silent "sweep: gh pr view is not a review request" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr view 123 --json title")"

assert_silent "sweep: gh pr edit --title is not a review request" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr edit 5 --title 'fix(ATF-1): x'")"

# --- deliberate design change (blocking finding 1): the heredoc-body stripper
# was removed. A `cat <<EOF` body that merely mentions `gh pr create` now DOES
# arm the tripwire — the opposite of the old behavior this test name used to
# assert. This is accepted: for an advisory hook, one ignorable false-positive
# reminder is a far smaller cost than the stripper's failure mode (see the
# "gh pr create via a phantom heredoc delimiter" case below, and the comment
# in pre-pr-sweep-check.sh above the CONTINUATION-JOIN block).
assert_contains "sweep: gh pr create mentioned inside a heredoc body now arms the tripwire (deliberate, finding 1)" \
  "$REPO" "$SCRIPT" "$(bash_json "cat <<'EOF' > notes.md
run gh pr create when ready
EOF")" \
  "pre-pr-sweep has not run"

# --- commands that MUST arm it ---
assert_contains "sweep: gh pr create warns" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")" \
  "pre-pr-sweep has not run"

assert_contains "sweep: gh pr ready warns" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr ready 5")" \
  "pre-pr-sweep has not run"

assert_contains "sweep: gh pr edit --add-reviewer warns" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr edit 5 --add-reviewer chrizzlekicks")" \
  "pre-pr-sweep has not run"

# --- regression: line-continued --add-reviewer must still arm the tripwire (finding 6) ---
# grep is line-based and `.` cannot span newlines, so `gh pr edit 5 \` followed by
# `  --add-reviewer x` on the next line (an ordinary shell line-continuation) previously
# fell through the --add-reviewer pattern silently.
CONTINUATION_CMD=$'gh pr edit 5 \\\n  --add-reviewer chrizzlekicks'
assert_contains "sweep: line-continued --add-reviewer still warns" \
  "$REPO" "$SCRIPT" "$(bash_json "$CONTINUATION_CMD")" \
  "pre-pr-sweep has not run"

assert_contains "sweep: gh pr create after && on a later line warns" \
  "$REPO" "$SCRIPT" "$(bash_json "git push -u origin HEAD &&
gh pr create --fill")" \
  "pre-pr-sweep has not run"

assert_contains "sweep: gh pr create with a heredoc body still warns" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr create --body-file - <<'EOF'
some body
EOF")" \
  "pre-pr-sweep has not run"

# --- regression (blocking finding 1): the heredoc-stripper is gone, so a `<<`
# that appears inside ordinary quoted text — never a real heredoc opener — can
# no longer be misparsed as one. These two cases used to depend on the
# stripper's own "unterminated heredoc" safety net to fall back to the
# original command; now they trivially match the raw text like anything else,
# which is the whole point of the removal.
PHANTOM_HEREDOC_CMD=$'echo "a << b"\ngh pr create --fill'
assert_contains "sweep: text containing << does not swallow the real command" \
  "$REPO" "$SCRIPT" "$(bash_json "$PHANTOM_HEREDOC_CMD")" \
  "pre-pr-sweep has not run"

# The exact silent-bypass repro from blocking finding 1: `<<` inside a quoted
# string is read by a naive heredoc parser as an opener with delimiter STOP,
# and a later, unrelated bare `STOP` line is misread as the closing
# terminator — so the parse terminates "cleanly" (no "unterminated" signal)
# after swallowing every line in between, including the real
# `gh pr create --fill`. Reproduced against the pre-fix script: exit 0, zero
# output, total silence. Now that matching runs against the raw command text
# with no heredoc parsing at all, this can no longer happen.
PHANTOM_DELIM_CMD=$'echo "look: << STOP"\ngh pr create --fill\nSTOP'
assert_contains "sweep: gh pr create after a phantom heredoc delimiter still warns" \
  "$REPO" "$SCRIPT" "$(bash_json "$PHANTOM_DELIM_CMD")" \
  "pre-pr-sweep has not run"

# --- regression: SIGPIPE under set -o pipefail on large input (review finding 1) ---
# A large command matching on line 1 must not SIGPIPE a `grep -Eq` pipeline
# that exits early once it has its match.
LARGE_PADDING="$(head -c 100000 /dev/zero | tr '\0' 'x')"
LARGE_CMD="gh pr create --fill
# ${LARGE_PADDING}"
assert_contains "sweep: large command matching on line 1 does not SIGPIPE" \
  "$REPO" "$SCRIPT" "$(bash_json "$LARGE_CMD")" \
  "pre-pr-sweep has not run"

assert_contains "sweep: no marker reports 'never'" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")" \
  "swept: never"

# --- output-format contract: stdout must be JSON with a systemMessage key (finding 1) ---
# hooks.json wires this script's stdout straight into Claude Code's hook protocol, which
# expects `{"systemMessage": "..."}` — a plain-text or malformed stdout is silently dropped
# by the harness rather than shown to the agent. Nothing in the suite asserted this shape.
out="$(run_hook_in "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")")"
if printf '%s' "$out" | jq -e 'type == "object" and has("systemMessage")' >/dev/null 2>&1; then
  pass "sweep: stdout is JSON with a systemMessage key"
else
  fail "sweep: stdout is JSON with a systemMessage key" "got: $out"
fi

# With no ledger file at all, the message must still render — just without a list.
# Paired with assert_contains below (review finding 3): a script that crashed
# with empty stdout would also lack "open deferral" and pass the case below
# vacuously, so we also require proof the warning itself still renders.
assert_contains "sweep: absent ledger still warns" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")" \
  "pre-pr-sweep has not run"
out="$(run_hook_in "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")")"
case "$out" in
  *"open deferral"*) fail "sweep: absent ledger lists no deferrals" "got: $out" ;;
  *) pass "sweep: absent ledger lists no deferrals" ;;
esac
rm -rf "$REPO"

# --- marker states ---
REPO="$(make_repo)"
mkdir -p "$REPO/.git/software-engineering"
git -C "$REPO" rev-parse HEAD > "$REPO/.git/software-engineering/last-sweep"
assert_silent "sweep: marker matching HEAD is silent" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")"

# One more commit makes the marker stale.
printf 'more\n' > "$REPO/README.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "second"
assert_contains "sweep: stale marker warns" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")" \
  "pre-pr-sweep has not run"
assert_contains "sweep: stale marker counts commits since" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")" \
  "(1 commits since)"
rm -rf "$REPO"

# --- regression: a CRLF-saved marker must not permanently nag (review finding 4) ---
# `head -1` stops at \n but does not strip a preceding \r, so a marker saved
# with CRLF line endings compares "<sha>\r" against a bare "<sha>" and never
# matches, even when it names the current HEAD.
REPO="$(make_repo)"
mkdir -p "$REPO/.git/software-engineering"
printf '%s\r\n' "$(git -C "$REPO" rev-parse HEAD)" > "$REPO/.git/software-engineering/last-sweep"
assert_silent "sweep: CRLF marker matching HEAD is silent" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")"
rm -rf "$REPO"

# --- regression: general trailing-whitespace trim, not CR-only (review finding 5) ---
# The finding-4 fix stripped exactly one trailing \r. A marker saved with a
# trailing space, tab, or \r\r still never equalled a bare $head_sha and
# nagged permanently. The fix must trim ALL trailing whitespace.
REPO="$(make_repo)"
mkdir -p "$REPO/.git/software-engineering"
printf '%s \n' "$(git -C "$REPO" rev-parse HEAD)" > "$REPO/.git/software-engineering/last-sweep"
assert_silent "sweep: trailing-space marker matching HEAD is silent" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")"
rm -rf "$REPO"

REPO="$(make_repo)"
mkdir -p "$REPO/.git/software-engineering"
printf '%s\r\r\n' "$(git -C "$REPO" rev-parse HEAD)" > "$REPO/.git/software-engineering/last-sweep"
assert_silent "sweep: double-CR marker matching HEAD is silent" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")"
rm -rf "$REPO"

# --- ledger states ---
REPO="$(make_repo)"
mkdir -p "$REPO/docs"
cat > "$REPO/docs/deferred-review-flags.md" <<'LEDGER'
# Deferred review flags

- [ ] 2026-08-19 `FirstAvailableSlotsQuery.kt:41` parseDueMember accepts >3 segments
- [x] 2026-08-18 `RedisPipeline.kt:22` timeoutSeconds unguarded — FIXED dca5626
- [ ] 2026-08-19 `WorkerProperties.kt:18` pendingReclaimAfterMs has no guard
LEDGER

assert_contains "sweep: open deferrals are counted" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")" \
  "2 open deferral"
assert_contains "sweep: open deferrals are named, not just counted" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")" \
  "parseDueMember accepts >3 segments"
assert_contains "sweep: the second open deferral is named too" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")" \
  "pendingReclaimAfterMs has no guard"
rm -rf "$REPO"

# --- regression: a large ledger must not SIGPIPE (review finding 1) ---
# `head -5` exits as soon as it has its 5 lines; on a ledger whose open
# entries exceed the pipe buffer (64 KiB), that early exit SIGPIPEs the
# still-writing printf upstream, which under `pipefail` + `set -e` kills the
# whole script with empty stdout — silence from exactly the repo with the
# most deferrals to report. Entries are generated here, not committed as a
# fixture file.
REPO="$(make_repo)"
mkdir -p "$REPO/docs"
{
  i=1
  while [ "$i" -le 2000 ]; do
    printf -- '- [ ] 2026-08-19 `File%04d.kt:%d` deferred item number %04d with padding text to bulk up the line length\n' "$i" "$i" "$i"
    i=$((i + 1))
  done
} > "$REPO/docs/deferred-review-flags.md"
LEDGER_BYTES=$(wc -c < "$REPO/docs/deferred-review-flags.md" | tr -d ' ')
if [ "$LEDGER_BYTES" -le 65536 ]; then
  fail "sweep: large-ledger fixture exceeds the pipe buffer" "got only $LEDGER_BYTES bytes"
else
  pass "sweep: large-ledger fixture exceeds the pipe buffer"
fi
assert_contains "sweep: large ledger does not SIGPIPE" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")" \
  "pre-pr-sweep has not run"
rm -rf "$REPO"

# A ledger with only closed entries produces no deferral list.
REPO="$(make_repo)"
mkdir -p "$REPO/docs"
cat > "$REPO/docs/deferred-review-flags.md" <<'LEDGER'
- [x] 2026-08-18 all done — ACCEPTED not worth it
LEDGER
# Paired with assert_contains below (review finding 3) for the same reason
# as the absent-ledger case above.
assert_contains "sweep: closed-only ledger still warns" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")" \
  "pre-pr-sweep has not run"
out="$(run_hook_in "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")")"
case "$out" in
  *"open deferral"*) fail "sweep: closed-only ledger lists no deferrals" "got: $out" ;;
  *) pass "sweep: closed-only ledger lists no deferrals" ;;
esac
rm -rf "$REPO"

# --- degenerate environments ---
NOTREPO="$(mktemp -d)"
assert_silent "sweep: outside a git repo, exit silently" \
  "$NOTREPO" "$SCRIPT" "$(bash_json "gh pr create --fill")"
rm -rf "$NOTREPO"

# --- regression: malformed/absent JSON must not exit non-zero (review finding 6) ---
# jq exits non-zero on a parse error; a bare `var=$(jq ...)` assignment left
# that failure to `set -e`, which aborted the script with jq's own exit
# status (5) instead of the 0 every other path in this hook guarantees.
REPO="$(make_repo)"
assert_silent "sweep: malformed JSON on stdin exits silently" \
  "$REPO" "$SCRIPT" 'not json{{{'

assert_silent "sweep: empty stdin exits silently" \
  "$REPO" "$SCRIPT" ''
rm -rf "$REPO"

# --- regression: an invalid UTF-8 byte in an open ledger entry must not
# abort the script (blocking finding 1) ---
# `cut -c1-90` is codepoint-aware under a UTF-8 locale; on BSD/macOS cut, a
# line containing an invalid UTF-8 byte (e.g. a path pasted with bad
# encoding) makes it exit 1 with "Illegal byte sequence". Under
# `set -euo pipefail` an unguarded pipeline here previously aborted the whole
# script — no JSON on stdout, non-zero exit — precisely when the ledger has
# an entry worth reporting. The fix must not just avoid crashing: it must
# still exit 0, still emit the sweep warning, and still name the offending
# entry (a `|| true` that silently produced an empty entry list would be a
# quieter version of the same bug), so this asserts all three explicitly
# rather than only checking exit status.
REPO="$(make_repo)"
mkdir -p "$REPO/docs"
printf -- '- [ ] 2026-08-19 `Bad\xffPath.kt:12` invalid UTF-8 byte in entry text\n' \
  > "$REPO/docs/deferred-review-flags.md"

out="$(run_hook_in "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")")"
status="$(cat "$_HOOK_STATUS_FILE")"
if [ "$status" = "0" ]; then
  pass "sweep: invalid-UTF-8 ledger entry still exits 0"
else
  fail "sweep: invalid-UTF-8 ledger entry still exits 0" \
    "exited $status; stdout: $out; stderr: $(cat "$_HOOK_STDERR_FILE")"
fi
case "$out" in
  *"pre-pr-sweep has not run"*) pass "sweep: invalid-UTF-8 ledger entry still emits the sweep warning" ;;
  *) fail "sweep: invalid-UTF-8 ledger entry still emits the sweep warning" "got: $out" ;;
esac
case "$out" in
  *"invalid UTF-8 byte in entry text"*) pass "sweep: invalid-UTF-8 ledger entry is still named" ;;
  *) fail "sweep: invalid-UTF-8 ledger entry is still named" "got: $out" ;;
esac
rm -rf "$REPO"

# --- regression: quoted/wrapped gh invocations must arm the tripwire
# (blocking finding 2) ---
# The boundary class `[[:space:];&|(]` excludes `"`, `'`, and a backtick, so
# a `gh pr create` wrapped in any quoting form never matched even though it
# unambiguously runs the command.
REPO="$(make_repo)"
assert_contains "sweep: eval-wrapped gh pr create warns" \
  "$REPO" "$SCRIPT" "$(bash_json 'eval "gh pr create --fill"')" \
  "pre-pr-sweep has not run"
rm -rf "$REPO"

REPO="$(make_repo)"
assert_contains "sweep: bash -c wrapped gh pr create warns" \
  "$REPO" "$SCRIPT" "$(bash_json 'bash -c "gh pr create --fill"')" \
  "pre-pr-sweep has not run"

assert_contains "sweep: ssh host wrapped gh pr create warns" \
  "$REPO" "$SCRIPT" "$(bash_json 'ssh host "gh pr create --fill"')" \
  "pre-pr-sweep has not run"
rm -rf "$REPO"
