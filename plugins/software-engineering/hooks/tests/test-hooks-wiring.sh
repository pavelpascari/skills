# Wiring contracts for hooks/hooks.json and the pre-pr-sweep marker path.
#
# hooks.json is the only thing connecting pre-pr-sweep-check.sh to reality: nothing else
# in this repo invokes it. A registration block deleted from hooks.json leaves the script
# perfectly correct and perfectly dead, and every assertion in test-pre-pr-sweep.sh (which
# invokes the script directly) still passes. These tests exercise hooks.json itself.
HOOKS_JSON="$HOOKS_DIR/hooks.json"

if jq empty "$HOOKS_JSON" >/dev/null 2>&1; then
  pass "hooks.json: parses as valid JSON"
else
  fail "hooks.json: parses as valid JSON" "jq failed to parse $HOOKS_JSON"
fi

bash_matcher_commands() {
  jq -r '.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]?.command' "$HOOKS_JSON" 2>/dev/null
}

if bash_matcher_commands | grep -q 'pre-pr-sweep-check\.sh'; then
  pass "hooks.json: pre-pr-sweep-check.sh is registered in the PreToolUse Bash matcher"
else
  fail "hooks.json: pre-pr-sweep-check.sh is registered in the PreToolUse Bash matcher" \
    "no PreToolUse/Bash hook command mentions pre-pr-sweep-check.sh in $HOOKS_JSON"
fi

if bash_matcher_commands | grep -q 'bug-fix-test-check\.sh'; then
  pass "hooks.json: bug-fix-test-check.sh is still registered in the PreToolUse Bash matcher"
else
  fail "hooks.json: bug-fix-test-check.sh is still registered in the PreToolUse Bash matcher" \
    "no PreToolUse/Bash hook command mentions bug-fix-test-check.sh in $HOOKS_JSON"
fi

# --- marker path: shared contract between the skill text and the hook script ---
# SKILL.md writes "$(git rev-parse --git-dir)/software-engineering/last-sweep" and the hook
# reads it back, with nothing pinning the two literal paths together — a rename on either
# side leaves the suite green and the tripwire permanently armed (the marker never matches
# HEAD, so every gh pr create/ready/--add-reviewer nags forever). Pin both halves of the
# literal path so changing one without the other fails one of these two assertions.
SWEEP_SKILL="$PLUGIN_ROOT/skills/pre-pr-sweep/SKILL.md"
SWEEP_HOOK="$HOOKS_DIR/pre-pr-sweep-check.sh"
MARKER_PATH_SUFFIX="software-engineering/last-sweep"

if grep -q "$MARKER_PATH_SUFFIX" "$SWEEP_HOOK"; then
  pass "marker path: the hook reads $MARKER_PATH_SUFFIX"
else
  fail "marker path: the hook reads $MARKER_PATH_SUFFIX" \
    "'$MARKER_PATH_SUFFIX' not found in $SWEEP_HOOK"
fi

if grep -q "$MARKER_PATH_SUFFIX" "$SWEEP_SKILL"; then
  pass "marker path: the skill writes $MARKER_PATH_SUFFIX"
else
  fail "marker path: the skill writes $MARKER_PATH_SUFFIX" \
    "'$MARKER_PATH_SUFFIX' not found in $SWEEP_SKILL"
fi
