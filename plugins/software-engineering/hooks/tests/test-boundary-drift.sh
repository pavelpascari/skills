# Drift guard (blocking finding 3): hooks/pre-pr-sweep-check.sh and
# scripts/bug-fix-test-check.sh each match a shell command against a
# "boundary class" of characters that can legitimately precede `gh`/`git`
# and still mark a genuine command position (see the `gh_boundary` /
# `git_boundary` comments in those two files for the full rationale). The
# two copies of this idiom had already drifted once — one had `(` in the
# class, the other did not — and that drift silently broke the
# subshell-wrapped-commit case for bug-fix-test-check.sh. This test extracts
# the actual boundary-class argument each script computes at runtime (not a
# hardcoded expected string) and fails if the two scripts disagree with each
# other, so a future edit to one that is not mirrored in the other fails the
# suite immediately instead of drifting silently again.
#
# If the two classes ever legitimately need to differ (e.g. a character that
# only makes sense as a `git`-command boundary and not a `gh`-command one),
# this test cannot be satisfied by a quiet one-line edit: it forces whoever
# makes that change to also touch this test — either by asserting the new,
# still-matching pair of values, or by replacing this single comparison with
# two independent pinned assertions and a comment explaining why they no
# longer need to match. What it prevents is exactly the silent, unnoticed
# kind of divergence that caused finding 3.
SWEEP_SCRIPT="$HOOKS_DIR/pre-pr-sweep-check.sh"
BUGFIX_SCRIPT="$PLUGIN_ROOT/scripts/bug-fix-test-check.sh"

# Pulls the single-quoted argument out of a `printf '%b' '...'` boundary-class
# construction line, e.g. from:
#   gh_boundary=$(printf '%b' '[[:space:];&|(\042\047\0140]')
# this returns: [[:space:];&|(\042\047\0140]
extract_boundary() {
  grep -oE "printf '%b' '[^']*'" "$1" | head -1 | sed -E "s/^printf '%b' '//; s/'\$//"
}

sweep_boundary="$(extract_boundary "$SWEEP_SCRIPT")"
bugfix_boundary="$(extract_boundary "$BUGFIX_SCRIPT")"

if [ -z "$sweep_boundary" ]; then
  fail "boundary drift: pre-pr-sweep-check.sh's boundary class is extractable" \
    "no \"printf '%b' '...'\" boundary construction found in $SWEEP_SCRIPT"
else
  pass "boundary drift: pre-pr-sweep-check.sh's boundary class is extractable"
fi

if [ -z "$bugfix_boundary" ]; then
  fail "boundary drift: bug-fix-test-check.sh's boundary class is extractable" \
    "no \"printf '%b' '...'\" boundary construction found in $BUGFIX_SCRIPT"
else
  pass "boundary drift: bug-fix-test-check.sh's boundary class is extractable"
fi

if [ -n "$sweep_boundary" ] && [ -n "$bugfix_boundary" ] && [ "$sweep_boundary" = "$bugfix_boundary" ]; then
  pass "boundary drift: pre-pr-sweep-check.sh and bug-fix-test-check.sh use the identical boundary class"
else
  fail "boundary drift: pre-pr-sweep-check.sh and bug-fix-test-check.sh use the identical boundary class" \
    "sweep='$sweep_boundary' bugfix='$bugfix_boundary'"
fi
