# Guard test (blocking finding 4): every `jq -r ... <<<"$var"` stdin read in
# every hook script must be immediately guarded with `|| exit 0`. jq exits
# non-zero on malformed/absent stdin; under this repo's `set -euo pipefail`
# convention, a bare assignment reading stdin through jq would abort the
# whole script with jq's own exit status — the exact "hooks never block"
# violation the comment next to every one of these reads exists to describe.
#
# That idiom is repeated across five call sites in three scripts today
# (hooks/prompt-submit-reminder.sh, hooks/pre-pr-sweep-check.sh,
# scripts/bug-fix-test-check.sh) with nothing pinning them together — a new
# hook cloned from one of these, or a new field added to an existing one,
# that omits `|| exit 0` would silently reintroduce the abort and nothing in
# the suite would notice. This scans every hook script for the pattern
# rather than hardcoding the five known call sites, so a script added later
# is covered automatically without anyone remembering to update this file.

# unguarded_jq_stdin_reads <file> -> one line per `jq -r ... <<< ...` stdin
# read in <file> that is not immediately followed on the same line by
# `|| exit 0`.
#
# Scoped to `-r` (field-extraction, the flag every read-idiom call site in
# this codebase uses) rather than any `jq ... <<<` at all: this repo also
# uses `jq -Rs '...' <<<"$message"` to format a hook's final systemMessage
# output — a wholly different operation (raw-string slurp of an already-
# trusted local variable, not a parse of untrusted stdin) that must not be
# flagged as an unguarded input read.
unguarded_jq_stdin_reads() {
  grep -nE 'jq[[:space:]]+-r[[:space:]].*<<<' "$1" 2>/dev/null \
    | grep -vE '\|\|[[:space:]]*exit[[:space:]]+0([[:space:]]|$)'
}

# Every top-level *.sh file directly under hooks/ or scripts/ is a hook
# script; hooks/tests/*.sh are the test suite itself, not hooks, and are
# deliberately excluded by the -maxdepth 1 scope on $HOOKS_DIR.
HOOK_SCRIPT_FILES="$(find "$HOOKS_DIR" -maxdepth 1 -name '*.sh' -print 2>/dev/null; find "$PLUGIN_ROOT/scripts" -maxdepth 1 -name '*.sh' -print 2>/dev/null)"

if [ -z "$HOOK_SCRIPT_FILES" ]; then
  fail "jq-stdin guard: at least one hook script exists to check" \
    "found no *.sh files under $HOOKS_DIR or $PLUGIN_ROOT/scripts"
else
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    bad="$(unguarded_jq_stdin_reads "$f")"
    if [ -n "$bad" ]; then
      fail "jq-stdin guard: $(basename "$f") guards every jq stdin read with || exit 0" \
        "unguarded read(s):
$bad"
    else
      pass "jq-stdin guard: $(basename "$f") guards every jq stdin read with || exit 0"
    fi
  done <<EOF
$HOOK_SCRIPT_FILES
EOF
fi

# --- meta-tests: prove the scanner itself actually detects an unguarded read,
# rather than passing vacuously because every real hook script happens to be
# correct today. Verified against the pre-fix state of this test (i.e.
# before this file existed) by temporarily deleting the ` || exit 0` from a
# real call site in hooks/prompt-submit-reminder.sh and re-running the
# suite: the scan below reproduces that same failure signal against a
# synthetic fixture instead, so the self-test doesn't depend on mutating a
# real script.
TMPDIR_JQGUARD="$(mktemp -d)"

UNGUARDED_FIXTURE="$TMPDIR_JQGUARD/unguarded.sh"
cat > "$UNGUARDED_FIXTURE" <<'EOF'
#!/bin/bash
set -euo pipefail
input=$(cat)
tool_name=$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null)
EOF
if [ -n "$(unguarded_jq_stdin_reads "$UNGUARDED_FIXTURE")" ]; then
  pass "jq-stdin guard: the scanner flags a jq stdin read missing || exit 0 (self-test)"
else
  fail "jq-stdin guard: the scanner flags a jq stdin read missing || exit 0 (self-test)" \
    "expected the scanner to flag the unguarded read in $UNGUARDED_FIXTURE"
fi

GUARDED_FIXTURE="$TMPDIR_JQGUARD/guarded.sh"
cat > "$GUARDED_FIXTURE" <<'EOF'
#!/bin/bash
set -euo pipefail
input=$(cat)
tool_name=$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null) || exit 0
EOF
if [ -z "$(unguarded_jq_stdin_reads "$GUARDED_FIXTURE")" ]; then
  pass "jq-stdin guard: the scanner does not flag a properly guarded jq stdin read (self-test)"
else
  fail "jq-stdin guard: the scanner does not flag a properly guarded jq stdin read (self-test)" \
    "expected no flags on $GUARDED_FIXTURE"
fi

rm -rf "$TMPDIR_JQGUARD"
