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

assert_silent "sweep: gh pr create inside a heredoc body is data, not a command" \
  "$REPO" "$SCRIPT" "$(bash_json "cat <<'EOF' > notes.md
run gh pr create when ready
EOF")"

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

assert_contains "sweep: gh pr create after && on a later line warns" \
  "$REPO" "$SCRIPT" "$(bash_json "git push -u origin HEAD &&
gh pr create --fill")" \
  "pre-pr-sweep has not run"

assert_contains "sweep: gh pr create with a heredoc body still warns" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr create --body-file - <<'EOF'
some body
EOF")" \
  "pre-pr-sweep has not run"

# --- regression: awk heredoc-stripper edge cases (review finding 2) ---
# A `<<-EOF` closed by a tab-indented terminator (the entire point of `<<-`)
# must still terminate the heredoc, not swallow the real command that follows.
TAB_HEREDOC_CMD=$'cat <<-EOF\nmentions gh pr create in the body only\n\tEOF\ngh pr create --fill'
assert_contains "sweep: dash-heredoc with tab-indented terminator still warns" \
  "$REPO" "$SCRIPT" "$(bash_json "$TAB_HEREDOC_CMD")" \
  "pre-pr-sweep has not run"

# A closing delimiter with trailing whitespace must still terminate the
# heredoc rather than swallowing every line after it forever.
TRAILING_WS_HEREDOC_CMD=$'cat <<EOF\nmentions gh pr create in the body only\nEOF \ngh pr create --fill'
assert_contains "sweep: heredoc terminator with trailing whitespace still warns" \
  "$REPO" "$SCRIPT" "$(bash_json "$TRAILING_WS_HEREDOC_CMD")" \
  "pre-pr-sweep has not run"

# A `<<` used as a shift/append/comparison inside quoted text is not a real
# heredoc opener; it never finds a closing line matching its phantom
# delimiter, so parsing runs to EOF still "skipping". The safety-net must
# fall back to the ORIGINAL command rather than silently dropping the rest.
PHANTOM_HEREDOC_CMD=$'echo "a << b"\ngh pr create --fill'
assert_contains "sweep: text containing << does not swallow the real command" \
  "$REPO" "$SCRIPT" "$(bash_json "$PHANTOM_HEREDOC_CMD")" \
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
