#!/bin/bash
# Structural tests for the hcampus plugin.
# Sourced by run-tests.sh.
#
# Every test above this one runs a hook script directly, which proves the script
# works and proves nothing about whether Claude Code will ever call it. A
# command in hooks.json pointing at a path that does not exist fails silently at
# runtime: the hook simply never fires, and the suite stays green. These tests
# close that gap.

# --- hooks.json points at scripts that exist and parse ----------------------

if [ ! -r "$HOOKS_DIR/hooks.json" ]; then
  fail "wiring: hooks.json exists" "not readable at $HOOKS_DIR/hooks.json"
else
  if jq -e . "$HOOKS_DIR/hooks.json" >/dev/null 2>&1; then
    pass "wiring: hooks.json is valid JSON"
  else
    fail "wiring: hooks.json is valid JSON" "jq could not parse it"
  fi

  wired=0
  while IFS= read -r command; do
    [ -n "$command" ] || continue
    wired=$((wired + 1))

    # Commands are written as `bash ${CLAUDE_PLUGIN_ROOT}/hooks/foo.sh`.
    script="${command#bash }"
    script="${script//\$\{CLAUDE_PLUGIN_ROOT\}/$PLUGIN_ROOT}"

    if [ ! -r "$script" ]; then
      fail "wiring: $command" "script does not exist at ${script#"$PLUGIN_ROOT"/}"
      continue
    fi
    if ! bash -n "$script" 2>/dev/null; then
      fail "wiring: $command" "script is not valid bash"
      continue
    fi
    pass "wiring: ${script#"$PLUGIN_ROOT"/} exists and parses"
  done < <(jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command' "$HOOKS_DIR/hooks.json" 2>/dev/null)

  if [ "$wired" -eq 4 ]; then
    pass "wiring: all four hooks are registered"
  else
    fail "wiring: all four hooks are registered" "hooks.json wires $wired command(s), expected 4"
  fi

  # The events themselves. A hook registered under a misspelled event name is
  # accepted by the JSON and never fires.
  events="$(jq -r '.hooks | keys_unsorted | sort | join(",")' "$HOOKS_DIR/hooks.json" 2>/dev/null || true)"
  if [ "$events" = "PreToolUse,SessionStart,Stop,UserPromptSubmit" ]; then
    pass "wiring: hooks are registered under the intended events"
  else
    fail "wiring: hooks are registered under the intended events" "got: $events"
  fi

  # The guard is the only hook narrowed by a matcher, and the matcher is what
  # keeps it off every other tool call.
  matcher="$(jq -r '.hooks.PreToolUse[0].matcher // ""' "$HOOKS_DIR/hooks.json" 2>/dev/null || true)"
  case "$matcher" in
    *memory_remember*) pass "wiring: the PreToolUse matcher targets memory_remember" ;;
    *) fail "wiring: the PreToolUse matcher targets memory_remember" "got: '$matcher'" ;;
  esac
fi

# --- .mcp.json --------------------------------------------------------------
#
# session-start-check.sh reads the server command out of this file. If it stops
# being parseable the probe goes silent and reports health it never measured.

if [ ! -r "$PLUGIN_ROOT/.mcp.json" ]; then
  fail "wiring: .mcp.json exists" "not readable at $PLUGIN_ROOT/.mcp.json"
else
  server_command="$(jq -r '.mcpServers.hcampus.command // ""' "$PLUGIN_ROOT/.mcp.json" 2>/dev/null || true)"
  if [ -n "$server_command" ]; then
    pass "wiring: .mcp.json declares the hcampus server command"
  else
    fail "wiring: .mcp.json declares the hcampus server command" "no .mcpServers.hcampus.command"
  fi
fi

# --- the skill --------------------------------------------------------------

SKILL="$PLUGIN_ROOT/skills/hcampus-memory/SKILL.md"
if [ ! -r "$SKILL" ]; then
  fail "wiring: SKILL.md exists" "not readable at $SKILL"
else
  skill_name="$(sed -n 's/^name: //p' "$SKILL" | head -1)"
  if [ "$skill_name" = "hcampus-memory" ]; then
    pass "wiring: SKILL.md declares its name"
  else
    fail "wiring: SKILL.md declares its name" "got: '$skill_name'"
  fi

  # CONTRIBUTING.md caps a skill description at 250 characters. It is the text
  # the model reads when deciding whether to invoke, so an over-long one is
  # both a rule violation and a triggering problem.
  description="$(sed -n 's/^description: //p' "$SKILL" | head -1)"
  length="$(printf '%s' "$description" | wc -c | tr -d ' ')"
  if [ -n "$description" ] && [ "$length" -le 250 ]; then
    pass "wiring: SKILL.md description is present and within 250 characters ($length)"
  else
    fail "wiring: SKILL.md description is present and within 250 characters" "length: $length"
  fi
fi
