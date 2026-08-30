#!/bin/bash
# Stop hook: a session that produced a decision, a correction, or a durable
# constraint and then ended without recording it has thrown that away — the next
# session starts from nothing and the user repeats themselves.
#
# Stop fires at the end of every turn, so the whole design problem here is not
# what to say but how rarely to say it. Three gates, in increasing cost order:
# the re-entry guard, the "memory was already written" check, and a once-per-
# session marker. A nudge that appears on every turn is a nudge nobody reads.
# Advisory: never blocks, always exits 0.
set -euo pipefail

input=$(cat)

# Empty stdin is not a stop event, and unlike malformed JSON it does not make
# jq fail — `jq '.x // false'` on no input at all succeeds with no output. The
# script would then sail past every gate on empty values and nudge under the
# fallback session key. Rejecting it here is the difference between "nudge once
# per session" and "nudge once, then never again for anyone".
if [ -z "$input" ]; then
  exit 0
fi

# Malformed JSON (or no JSON at all, e.g. empty stdin) makes jq exit non-zero.
# A bare assignment failing there would abort under `set -e` with jq's own exit
# status, which for a Stop hook means a failed hook at the end of every turn.
stop_hook_active=$(jq -r '.stop_hook_active // false' <<<"$input" 2>/dev/null) || exit 0

# Gate 1: re-entry. When a Stop hook's output causes the model to continue,
# the next stop arrives with this flag set. Speaking again there is how a Stop
# hook talks itself into a loop.
if [ "$stop_hook_active" = "true" ]; then
  exit 0
fi

transcript=$(jq -r '.transcript_path // ""' <<<"$input" 2>/dev/null) || exit 0
session_id=$(jq -r '.session_id // ""' <<<"$input" 2>/dev/null) || exit 0

# Gate 2: memory was already written. If the transcript shows a memory_remember
# anywhere in this session, the behaviour this hook exists to prompt has already
# happened and a reminder is pure noise.
if [ -n "$transcript" ] && [ -r "$transcript" ]; then
  if grep -q 'memory_remember' "$transcript" 2>/dev/null; then
    exit 0
  fi
fi

# Gate 3: once per session. Without this the nudge repeats at the end of every
# turn for the whole session, which is the failure mode that gets hooks
# uninstalled.
#
# The session id goes into a filename, so every character outside a safe set is
# folded to `_`. printf without a trailing newline keeps tr from translating the
# newline into the key as well. An empty id (a caller that does not send one)
# falls back to a fixed key: nudging once per machine is a far better failure
# than nudging on every single turn.
key=$(printf '%s' "${session_id:-nosession}" | LC_ALL=C tr -c 'A-Za-z0-9_-' '_') || exit 0
marker_dir="${TMPDIR:-/tmp}/hcampus-hooks"
mkdir -p "$marker_dir" 2>/dev/null || exit 0
marker="$marker_dir/stop-nudge-$key"

if [ -e "$marker" ]; then
  exit 0
fi
: > "$marker" 2>/dev/null || exit 0

{
  printf 'Before this session ends: did it produce anything durable enough to be worth recalling?\n\n'
  printf '  - a decision, with its rationale        -> kind=decision\n'
  printf '  - a correction to something stored      -> kind=correction\n'
  printf '  - a stable preference or constraint     -> kind=observation or user_statement\n'
  printf '  - work still outstanding                -> kind=plan\n'
  printf '  - a completed outcome worth reusing     -> kind=observation\n\n'
  printf 'Store the outcome, not the reasoning that reached it: short, and never credentials,\n'
  printf 'command output, or whole conversations.\n\n'
  printf 'If nothing durable came out of this session, storing nothing is the correct action.\n'
} | jq -Rs '{systemMessage: .}'
