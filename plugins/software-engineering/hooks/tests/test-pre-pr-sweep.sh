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

assert_contains "sweep: no marker reports 'never'" \
  "$REPO" "$SCRIPT" "$(bash_json "gh pr create --fill")" \
  "swept: never"

# With no ledger file at all, the message must still render — just without a list.
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

# A ledger with only closed entries produces no deferral list.
REPO="$(make_repo)"
mkdir -p "$REPO/docs"
cat > "$REPO/docs/deferred-review-flags.md" <<'LEDGER'
- [x] 2026-08-18 all done — ACCEPTED not worth it
LEDGER
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
