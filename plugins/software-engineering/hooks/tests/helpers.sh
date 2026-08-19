#!/bin/bash
# Shared fixtures and assertions for the software-engineering hook tests.
# Sourced by run-tests.sh; not executable on its own.

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_ROOT="$(dirname "$HOOKS_DIR")"
PASS_COUNT=0
FAIL_COUNT=0

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
run_hook_in() {
  if [ ! -r "$2" ]; then
    printf 'HOOK SCRIPT MISSING: %s' "$2"
    return 0
  fi
  ( cd "$1" && printf '%s' "$3" | bash "$2" 2>/dev/null )
}

# assert_silent <name> <dir> <script> <json>
assert_silent() {
  local out
  out="$(run_hook_in "$2" "$3" "$4")"
  if [ -z "$out" ]; then
    pass "$1"
  else
    fail "$1" "expected no output, got: $out"
  fi
}

# assert_contains <name> <dir> <script> <json> <needle>
assert_contains() {
  local out
  out="$(run_hook_in "$2" "$3" "$4")"
  case "$out" in
    *"$5"*) pass "$1" ;;
    *) fail "$1" "expected output containing '$5', got: $out" ;;
  esac
}
