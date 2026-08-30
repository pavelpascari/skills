#!/bin/bash
# SessionStart hook: the hcampus-memory skill is only as useful as the MCP
# server behind it. When that server cannot start, nothing announces it — the
# memory_* tools simply are not there, and the failure surfaces mid-task as a
# missing tool rather than as "hcampus is not installed". One line at session
# start is much cheaper to read than that.
# Advisory: never blocks, always exits 0.
set -euo pipefail

# Drain stdin so the caller is never SIGPIPEd mid-write. Nothing in the
# SessionStart payload is needed here.
cat >/dev/null 2>&1 || true

# The command to probe is read from the plugin's own .mcp.json rather than
# hardcoded. A hardcoded "hcampus-mcp" would keep passing after that file
# changed, probing a command nobody launches — a check that reports health it
# never measured is worse than no check.
plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$plugin_root" ]; then
  plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

mcp_json="$plugin_root/.mcp.json"
if [ ! -r "$mcp_json" ]; then
  exit 0
fi

# Malformed JSON makes jq exit non-zero. A bare assignment failing there would
# abort under `set -e` with jq's own status — a hook that dies noisily because
# its own config is unreadable, which is the opposite of advisory.
server_command=$(jq -r '.mcpServers.hcampus.command // ""' "$mcp_json" 2>/dev/null) || exit 0
if [ -z "$server_command" ]; then
  exit 0
fi

if command -v "$server_command" >/dev/null 2>&1; then
  # Present. Say nothing — a hook that speaks on every healthy session start
  # teaches the reader to skip past it on the one session where it matters.
  exit 0
fi

{
  printf 'hcampus memory is not available: the MCP server command "%s" was not found on PATH.\n' "$server_command"
  printf 'The hcampus-memory skill has no tools to call until it is — memory_recall, memory_remember,\n'
  printf 'memory_explain and memory_forget will not resolve.\n'
  printf 'From the hcampus project: `uv sync --all-extras --dev`, then put its entry point on PATH.\n'
  printf 'If you launch the server another way (a wrapper, an absolute path, a container), ignore this.\n'
} | jq -Rs '{systemMessage: .}'
