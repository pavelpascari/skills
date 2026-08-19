# Drift guard (blocking finding 3): hooks/pre-pr-sweep-check.sh and
# scripts/bug-fix-test-check.sh each match a shell command against a
# "boundary class" of characters that can legitimately precede `gh`/`git`
# and still mark a genuine command position (see the `gh_boundary` /
# `git_boundary` comments in those two files for the full rationale), and
# each preprocesses its command text the same way before matching (joining
# backslash-continued lines — see the CONTINUATION-JOIN block in both
# files). Both idioms had already drifted once between the two scripts —
# one had `(` in its boundary class and the other did not, and separately,
# one joined line continuations before matching and the other didn't (that
# second drift is blocking finding 2: a `git \` + newline + `  commit -m
# "fix: x"` slipped past bug-fix-test-check.sh silently). This test extracts
# both the actual boundary-class argument AND the actual preprocessing code
# each script runs at runtime (not hardcoded expected strings) and fails if
# the two scripts disagree with each other on either one, so a future edit
# to one that is not mirrored in the other fails the suite immediately
# instead of drifting silently again.
#
# If the two classes (or the two preprocessing idioms) ever legitimately need
# to differ, this test cannot be satisfied by a quiet one-line edit: it
# forces whoever makes that change to also touch this test — either by
# asserting the new, still-matching pair of values, or by replacing the
# relevant comparison with two independent pinned assertions and a comment
# explaining why they no longer need to match.
SWEEP_SCRIPT="$HOOKS_DIR/pre-pr-sweep-check.sh"
BUGFIX_SCRIPT="$PLUGIN_ROOT/scripts/bug-fix-test-check.sh"

# extract_boundary <file> <varname> -> the single-quoted argument of that
# variable's own `<varname>=$(printf '%b' '...')` assignment.
#
# blocking finding 3: the previous version of this extractor was
# `grep -oE "printf '%b' '[^']*'" "$1" | head -1` — it took the FIRST
# `printf '%b'` literal anywhere in the file, with no anchor to the
# `gh_boundary=`/`git_boundary=` assignment at all. Inserting any earlier,
# unrelated `printf '%b'` call into either script (e.g. for some other
# feature) would make this test silently compare a decoy string instead of
# the real boundary class, and report green while the real classes had
# diverged. This version is anchored to the specific `<varname>=$(printf
# '%b' '...')` assignment via a fixed-string (non-regex) prefix match, so an
# unrelated earlier `printf '%b'` call cannot be mistaken for it.
extract_boundary() {
  local file="$1" var="$2" prefix line rest
  prefix="${var}=\$(printf '%b' '"
  line="$(grep -F -- "$prefix" "$file" 2>/dev/null | head -1)"
  [ -z "$line" ] && return 0
  rest="${line#*"$prefix"}"
  printf '%s' "${rest%\')}"
}

# extract_preprocessing <file> -> the exact code between the
# CONTINUATION-JOIN-BEGIN/END sentinel comments (exclusive), i.e. the
# backslash-continuation-joining awk program each script runs before
# matching. Anchored to explicit sentinel markers rather than any guess at
# where the code "probably" starts, for the same reason extract_boundary is
# anchored to the assignment: a decoy or reordering elsewhere in the file
# must not be able to fool the extraction.
extract_preprocessing() {
  sed -n '/# CONTINUATION-JOIN-BEGIN/,/# CONTINUATION-JOIN-END/p' "$1" 2>/dev/null | sed '1d;$d'
}

sweep_boundary="$(extract_boundary "$SWEEP_SCRIPT" "gh_boundary")"
bugfix_boundary="$(extract_boundary "$BUGFIX_SCRIPT" "git_boundary")"

if [ -z "$sweep_boundary" ]; then
  fail "boundary drift: pre-pr-sweep-check.sh's boundary class is extractable" \
    "no anchored gh_boundary=\$(printf '%b' '...') assignment found in $SWEEP_SCRIPT"
else
  pass "boundary drift: pre-pr-sweep-check.sh's boundary class is extractable"
fi

if [ -z "$bugfix_boundary" ]; then
  fail "boundary drift: bug-fix-test-check.sh's boundary class is extractable" \
    "no anchored git_boundary=\$(printf '%b' '...') assignment found in $BUGFIX_SCRIPT"
else
  pass "boundary drift: bug-fix-test-check.sh's boundary class is extractable"
fi

if [ -n "$sweep_boundary" ] && [ -n "$bugfix_boundary" ] && [ "$sweep_boundary" = "$bugfix_boundary" ]; then
  pass "boundary drift: pre-pr-sweep-check.sh and bug-fix-test-check.sh use the identical boundary class"
else
  fail "boundary drift: pre-pr-sweep-check.sh and bug-fix-test-check.sh use the identical boundary class" \
    "sweep='$sweep_boundary' bugfix='$bugfix_boundary'"
fi

# --- extended guard (blocking finding 3): pin the preprocessing idiom too,
# not just the boundary class. This is exactly the comparison that would
# have caught blocking finding 2 (bug-fix-test-check.sh matching raw
# $command with no continuation-join while pre-pr-sweep-check.sh joined
# first) before it shipped, instead of relying on a human noticing.
sweep_preprocessing="$(extract_preprocessing "$SWEEP_SCRIPT")"
bugfix_preprocessing="$(extract_preprocessing "$BUGFIX_SCRIPT")"

if [ -z "$sweep_preprocessing" ]; then
  fail "boundary drift: pre-pr-sweep-check.sh's continuation-join preprocessing is extractable" \
    "no CONTINUATION-JOIN-BEGIN/END sentinel block found in $SWEEP_SCRIPT"
else
  pass "boundary drift: pre-pr-sweep-check.sh's continuation-join preprocessing is extractable"
fi

if [ -z "$bugfix_preprocessing" ]; then
  fail "boundary drift: bug-fix-test-check.sh's continuation-join preprocessing is extractable" \
    "no CONTINUATION-JOIN-BEGIN/END sentinel block found in $BUGFIX_SCRIPT"
else
  pass "boundary drift: bug-fix-test-check.sh's continuation-join preprocessing is extractable"
fi

if [ -n "$sweep_preprocessing" ] && [ -n "$bugfix_preprocessing" ] && [ "$sweep_preprocessing" = "$bugfix_preprocessing" ]; then
  pass "boundary drift: pre-pr-sweep-check.sh and bug-fix-test-check.sh use the identical continuation-join preprocessing"
else
  fail "boundary drift: pre-pr-sweep-check.sh and bug-fix-test-check.sh use the identical continuation-join preprocessing" \
    "sweep and bugfix preprocessing blocks differ"
fi

# --- meta-tests: prove the guard itself actually detects divergence, rather
# than passing vacuously because the two real scripts happen to agree today.
# These build synthetic fixture files and exercise extract_boundary /
# extract_preprocessing directly, asserting the comparison a human would make
# on their output comes out as a mismatch — without ever calling fail() on a
# constructed negative case (that would count as a real suite failure).

TMPDIR_DRIFT="$(mktemp -d)"

# 1) Anchoring regression (blocking finding 3's exact bug): a file with an
# earlier, unrelated `printf '%b'` call followed by the real anchored
# assignment. The pre-fix extractor (first `printf '%b'` literal anywhere)
# would have returned the decoy; the anchored extractor must return the real
# assignment's value.
DECOY_FILE="$TMPDIR_DRIFT/decoy.sh"
cat > "$DECOY_FILE" <<'EOF'
#!/bin/bash
some_unrelated_var=$(printf '%b' 'DECOY_VALUE_NOT_THE_BOUNDARY')
gh_boundary=$(printf '%b' '[[:space:];&|(\042\047\0140]')
EOF
decoy_extracted="$(extract_boundary "$DECOY_FILE" "gh_boundary")"
if [ "$decoy_extracted" = '[[:space:];&|(\042\047\0140]' ]; then
  pass "boundary drift: extract_boundary is anchored to the assignment, not fooled by an earlier decoy printf '%b'"
else
  fail "boundary drift: extract_boundary is anchored to the assignment, not fooled by an earlier decoy printf '%b'" \
    "expected the real gh_boundary value, got: '$decoy_extracted'"
fi

# 2) The guard fails when the classes genuinely differ.
DIFF_A="$TMPDIR_DRIFT/diff_a.sh"
DIFF_B="$TMPDIR_DRIFT/diff_b.sh"
printf "gh_boundary=\$(printf '%%b' '[[:space:];&|(]')\n" > "$DIFF_A"
printf "git_boundary=\$(printf '%%b' '[[:space:];&|]')\n" > "$DIFF_B"
val_a="$(extract_boundary "$DIFF_A" "gh_boundary")"
val_b="$(extract_boundary "$DIFF_B" "git_boundary")"
if [ -n "$val_a" ] && [ -n "$val_b" ] && [ "$val_a" != "$val_b" ]; then
  pass "boundary drift: the guard's comparison reports a mismatch when the two boundary classes genuinely differ"
else
  fail "boundary drift: the guard's comparison reports a mismatch when the two boundary classes genuinely differ" \
    "expected a='[[:space:];&|(]' b='[[:space:];&|]' to compare unequal; got a='$val_a' b='$val_b'"
fi

# 3) The guard fails when the preprocessing idiom genuinely differs.
PRE_A="$TMPDIR_DRIFT/pre_a.sh"
PRE_B="$TMPDIR_DRIFT/pre_b.sh"
cat > "$PRE_A" <<'EOF'
# CONTINUATION-JOIN-BEGIN
joined=$(printf '%s\n' "$command" | awk '{ print }')
# CONTINUATION-JOIN-END
EOF
cat > "$PRE_B" <<'EOF'
# CONTINUATION-JOIN-BEGIN
joined="$command"
# CONTINUATION-JOIN-END
EOF
pre_a="$(extract_preprocessing "$PRE_A")"
pre_b="$(extract_preprocessing "$PRE_B")"
if [ -n "$pre_a" ] && [ -n "$pre_b" ] && [ "$pre_a" != "$pre_b" ]; then
  pass "boundary drift: the guard's comparison reports a mismatch when the two preprocessing idioms genuinely differ"
else
  fail "boundary drift: the guard's comparison reports a mismatch when the two preprocessing idioms genuinely differ" \
    "expected pre_a and pre_b to compare unequal; got a='$pre_a' b='$pre_b'"
fi

rm -rf "$TMPDIR_DRIFT"
