#!/bin/bash
# Tests for hooks/stop-persist-nudge.sh — the end-of-session persist nudge.
# Sourced by run-tests.sh.
#
# Stop fires at the end of every turn, so most of these tests are about the
# hook staying quiet. The nudge is worth one appearance per session and nothing
# more.

SCRIPT="$HOOKS_DIR/stop-persist-nudge.sh"
dir="$(scratch)"

# The hook records "already nudged" as a marker file under TMPDIR. Point that at
# a scratch directory so the suite neither reads nor leaves state in the real
# one — otherwise the first test would pass once and fail on every later run.
_saved_tmpdir="${TMPDIR:-}"
export TMPDIR="$(scratch)"

transcript_quiet="$dir/quiet.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}' > "$transcript_quiet"

transcript_stored="$dir/stored.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__hcampus__memory_remember"}]}}' > "$transcript_stored"

assert_contains "stop-nudge: fires once for a fresh session" \
  "$dir" "$SCRIPT" "$(stop_json "session-aaa" "$transcript_quiet" false)" \
  "durable"

# Second stop in the same session. Without this gate the nudge repeats at the
# end of every turn, which is the failure mode that gets hooks uninstalled.
assert_silent "stop-nudge: silent on a second stop in the same session" \
  "$dir" "$SCRIPT" "$(stop_json "session-aaa" "$transcript_quiet" false)"

# The marker is per session, not global — a new session gets its own nudge.
assert_contains "stop-nudge: fires again for a different session" \
  "$dir" "$SCRIPT" "$(stop_json "session-bbb" "$transcript_quiet" false)" \
  "durable"

# A session id with path separators in it must not escape the marker directory
# or collide with another session's marker.
assert_contains "stop-nudge: handles a session id containing path separators" \
  "$dir" "$SCRIPT" "$(stop_json "../../session-ccc" "$transcript_quiet" false)" \
  "durable"

# Re-entry: when a Stop hook's output makes the model continue, the next stop
# carries this flag. Speaking again there is how a Stop hook loops.
assert_silent "stop-nudge: silent when stop_hook_active is true" \
  "$dir" "$SCRIPT" "$(stop_json "session-ddd" "$transcript_quiet" true)"

# The behaviour this hook prompts has already happened — a reminder is noise.
assert_silent "stop-nudge: silent when the transcript already shows a memory_remember" \
  "$dir" "$SCRIPT" "$(stop_json "session-eee" "$transcript_stored" false)"

# An unreadable transcript is not evidence that nothing was stored, but it is
# also not a reason to crash. Nudge once and move on.
assert_contains "stop-nudge: still nudges when the transcript is unreadable" \
  "$dir" "$SCRIPT" "$(stop_json "session-fff" "$dir/no-such-file.jsonl" false)" \
  "durable"

assert_silent "stop-nudge: silent and exits 0 on malformed stdin" \
  "$dir" "$SCRIPT" "not json"

assert_silent "stop-nudge: silent and exits 0 on empty stdin" \
  "$dir" "$SCRIPT" ""

if [ -n "$_saved_tmpdir" ]; then
  export TMPDIR="$_saved_tmpdir"
else
  unset TMPDIR
fi
