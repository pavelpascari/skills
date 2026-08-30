#!/bin/bash
# Shared fixtures and assertions for the hcampus hook tests.
# Sourced by run-tests.sh; not executable on its own.

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_ROOT="$(dirname "$HOOKS_DIR")"
PASS_COUNT=0
FAIL_COUNT=0

# Side channel for run_hook_in to report exit status / stderr back to its
# caller. A command-substitution capture (`out="$(run_hook_in ...)"`) only
# sees stdout, so status and stderr are written to these scratch files
# instead. Cleaned up when the sourcing shell (run-tests.sh) exits.
_HOOK_STATUS_FILE="$(mktemp)"
_HOOK_STDERR_FILE="$(mktemp)"
trap 'rm -f "$_HOOK_STATUS_FILE" "$_HOOK_STDERR_FILE"' EXIT

pass() {
  printf 'ok    %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  printf 'FAIL  %s\n        %s\n' "$1" "$2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# scratch -> prints the path of a fresh empty directory
scratch() {
  mktemp -d
}

# make_plugin_root <server-command> -> a directory usable as CLAUDE_PLUGIN_ROOT,
# containing a .mcp.json that names the given command. session-start-check.sh
# reads the command out of that file rather than hardcoding it, so this is how a
# test controls whether the probe finds something.
make_plugin_root() {
  local dir
  dir="$(mktemp -d)"
  jq -n --arg c "$1" '{mcpServers: {hcampus: {command: $c, args: []}}}' > "$dir/.mcp.json"
  printf '%s' "$dir"
}

# prompt_json <prompt> -> a UserPromptSubmit payload
prompt_json() {
  jq -nc --arg p "$1" '{prompt: $p}'
}

# remember_json <text> -> a PreToolUse payload for a plugin-namespaced
# memory_remember call
remember_json() {
  tool_json "mcp__plugin_hcampus_hcampus__memory_remember" "$1"
}

# tool_json <tool-name> <text> -> a PreToolUse payload for an arbitrary tool
tool_json() {
  jq -nc --arg n "$1" --arg t "$2" '{tool_name: $n, tool_input: {text: $t, kind: "observation"}}'
}

# stop_json <session-id> <transcript-path> <stop-hook-active> -> a Stop payload
stop_json() {
  jq -nc --arg s "$1" --arg t "$2" --argjson a "$3" \
    '{session_id: $s, transcript_path: $t, stop_hook_active: $a}'
}

# session_start_json -> a SessionStart payload
session_start_json() {
  jq -nc '{hook_event_name: "SessionStart", source: "startup"}'
}

# run_hook_in <dir> <script> <json> -> the hook's stdout
# A missing script must not read as "silent" — that would make every
# assert_silent case pass vacuously against a script nobody wrote yet.
# Also records the hook's exit status (in $_HOOK_STATUS_FILE) and stderr
# (in $_HOOK_STDERR_FILE): hooks run under their own `set -euo pipefail`,
# so an unguarded failing `grep`/`jq` inside a hook exits non-zero with
# empty stdout — indistinguishable from an intentional silent success
# unless the caller also checks the exit status.
run_hook_in() {
  local dir="$1" script="$2" json="$3"

  if [ ! -r "$script" ]; then
    printf '0' > "$_HOOK_STATUS_FILE"
    : > "$_HOOK_STDERR_FILE"
    printf 'HOOK SCRIPT MISSING: %s' "$script"
    return 0
  fi

  if [ ! -d "$dir" ]; then
    printf '1' > "$_HOOK_STATUS_FILE"
    printf 'FIXTURE DIRECTORY MISSING: %s' "$dir" > "$_HOOK_STDERR_FILE"
    return 0
  fi

  local out status
  out="$(cd "$dir" && printf '%s' "$json" | bash "$script" 2>"$_HOOK_STDERR_FILE")"
  status=$?
  printf '%s' "$status" > "$_HOOK_STATUS_FILE"
  printf '%s' "$out"
}

# assert_silent <name> <dir> <script> <json>
assert_silent() {
  local out status err
  out="$(run_hook_in "$2" "$3" "$4")"
  status="$(cat "$_HOOK_STATUS_FILE")"
  err="$(cat "$_HOOK_STDERR_FILE")"
  if [ "$status" != "0" ]; then
    fail "$1" "hook exited $status (expected 0); stdout: $out; stderr: $err"
  elif [ -z "$out" ]; then
    pass "$1"
  else
    fail "$1" "expected no output, got: $out"
  fi
}

# assert_contains <name> <dir> <script> <json> <needle>
assert_contains() {
  local out status err
  out="$(run_hook_in "$2" "$3" "$4")"
  status="$(cat "$_HOOK_STATUS_FILE")"
  err="$(cat "$_HOOK_STDERR_FILE")"
  if [ "$status" != "0" ]; then
    fail "$1" "hook exited $status (expected 0); stdout: $out; stderr: $err"
    return
  fi
  case "$out" in
    *"$5"*) pass "$1" ;;
    *) fail "$1" "expected output containing '$5', got: $out" ;;
  esac
}

# assert_denies <name> <dir> <script> <json> <reason-needle>
# A deny is expressed as JSON on stdout with exit 0, not as a non-zero exit —
# so a test that only checked the exit status would pass against a hook that
# denied nothing at all.
assert_denies() {
  local out status err decision reason
  out="$(run_hook_in "$2" "$3" "$4")"
  status="$(cat "$_HOOK_STATUS_FILE")"
  err="$(cat "$_HOOK_STDERR_FILE")"
  if [ "$status" != "0" ]; then
    fail "$1" "hook exited $status (expected 0); stdout: $out; stderr: $err"
    return
  fi
  decision="$(jq -r '.hookSpecificOutput.permissionDecision // ""' <<<"$out" 2>/dev/null || true)"
  if [ "$decision" != "deny" ]; then
    fail "$1" "expected permissionDecision=deny, got: $out"
    return
  fi
  reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"$out" 2>/dev/null || true)"
  case "$reason" in
    *"$5"*) pass "$1" ;;
    *) fail "$1" "expected deny reason containing '$5', got: $reason" ;;
  esac
}

# assert_output_lacks <name> <dir> <script> <json> <needle>
# For the case where the hook must speak WITHOUT quoting what it found.
assert_output_lacks() {
  local out status
  out="$(run_hook_in "$2" "$3" "$4")"
  status="$(cat "$_HOOK_STATUS_FILE")"
  if [ "$status" != "0" ]; then
    fail "$1" "hook exited $status (expected 0); stdout: $out"
    return
  fi
  if [ -z "$out" ]; then
    fail "$1" "expected output, got none"
    return
  fi
  case "$out" in
    *"$5"*) fail "$1" "output must not contain '$5', got: $out" ;;
    *) pass "$1" ;;
  esac
}
