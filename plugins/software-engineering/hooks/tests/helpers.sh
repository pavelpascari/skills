#!/bin/bash
# Shared fixtures and assertions for the software-engineering hook tests.
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

# make_repo -> prints the path of a fresh git repo with one commit
make_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "test"
  git -C "$dir" config commit.gpgsign false
  : > "$dir/README.md"
  git -C "$dir" add -A
  git -C "$dir" commit -qm "init"
  printf '%s' "$dir"
}

# bash_json <command> -> a PreToolUse(Bash) payload
bash_json() {
  jq -nc --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}'
}

# prompt_json <prompt> -> a UserPromptSubmit payload
prompt_json() {
  jq -nc --arg p "$1" '{prompt: $p}'
}

# run_hook_in <dir> <script> <json> -> the hook's stdout
# A missing script must not read as "silent" — that would make every
# assert_silent case pass vacuously against a script nobody wrote yet.
# Also records the hook's exit status (in $_HOOK_STATUS_FILE) and stderr
# (in $_HOOK_STDERR_FILE): hooks run under their own `set -euo pipefail`,
# so an unguarded failing `grep`/`git` inside a hook exits non-zero with
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
