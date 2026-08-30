#!/bin/bash
# Tests for hooks/session-start-check.sh — the MCP availability probe.
# Sourced by run-tests.sh.

SCRIPT="$HOOKS_DIR/session-start-check.sh"
_saved_plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
dir="$(scratch)"

# A command that certainly exists on any machine that can run this suite.
present_root="$(make_plugin_root "sh")"
export CLAUDE_PLUGIN_ROOT="$present_root"
assert_silent "session-start: silent when the configured server command exists" \
  "$dir" "$SCRIPT" "$(session_start_json)"

# The probe must follow .mcp.json rather than a hardcoded name — a root naming
# a command that does not exist has to warn even though the real plugin's
# hcampus-mcp might be installed on this machine.
missing_root="$(make_plugin_root "hcampus-mcp-does-not-exist-xyz")"
export CLAUDE_PLUGIN_ROOT="$missing_root"
assert_contains "session-start: warns when the configured server command is missing" \
  "$dir" "$SCRIPT" "$(session_start_json)" "was not found on PATH"

# The warning names the command it actually probed, so a reader can tell which
# binary to install rather than guessing.
assert_contains "session-start: warning names the probed command" \
  "$dir" "$SCRIPT" "$(session_start_json)" "hcampus-mcp-does-not-exist-xyz"

# No .mcp.json means nothing to probe. Saying "not found" there would report a
# failure the hook never measured.
empty_root="$(scratch)"
export CLAUDE_PLUGIN_ROOT="$empty_root"
assert_silent "session-start: silent when .mcp.json is absent" \
  "$dir" "$SCRIPT" "$(session_start_json)"

# An .mcp.json that is not valid JSON must not abort the hook under `set -e`.
printf 'not json at all' > "$empty_root/.mcp.json"
assert_silent "session-start: silent and exits 0 on malformed .mcp.json" \
  "$dir" "$SCRIPT" "$(session_start_json)"

# Malformed stdin is the failure the whole suite exists to keep out of hooks.
export CLAUDE_PLUGIN_ROOT="$present_root"
assert_silent "session-start: silent and exits 0 on malformed stdin" \
  "$dir" "$SCRIPT" "not json"

if [ -n "$_saved_plugin_root" ]; then
  export CLAUDE_PLUGIN_ROOT="$_saved_plugin_root"
else
  unset CLAUDE_PLUGIN_ROOT
fi
