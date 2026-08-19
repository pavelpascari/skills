# Structural and content contracts for this plugin's skills.
SKILLS_DIR="$PLUGIN_ROOT/skills"

# Every skill directory has a SKILL.md whose frontmatter name matches the directory.
for dir in "$SKILLS_DIR"/*/; do
  name="$(basename "$dir")"
  file="$dir/SKILL.md"
  if [ ! -r "$file" ]; then
    fail "skills: $name has a SKILL.md" "missing $file"
    continue
  fi
  pass "skills: $name has a SKILL.md"

  if grep -Eq "^name:[[:space:]]+$name[[:space:]]*$" "$file"; then
    pass "skills: $name frontmatter name matches its directory"
  else
    fail "skills: $name frontmatter name matches its directory" "no 'name: $name' line in $file"
  fi

  if grep -q '^description:' "$file"; then
    pass "skills: $name has a description"
  else
    fail "skills: $name has a description" "no description in $file"
  fi
done

SWEEP="$SKILLS_DIR/pre-pr-sweep/SKILL.md"

# The independence contract is the whole point of the design — pin it.
if grep -q 'MUST NOT read the ledger' "$SWEEP"; then
  pass "sweep skill: sub-agents are forbidden from reading the ledger"
else
  fail "sweep skill: sub-agents are forbidden from reading the ledger" \
    "the forbidden-inputs list no longer says 'MUST NOT read the ledger'"
fi

for pass_name in "Pass 0" "Pass 1" "Pass 2" "Pass 3" "Pass 4" "Pass 5" "Pass 6" "Pass 7"; do
  if grep -q "### $pass_name" "$SWEEP"; then
    pass "sweep skill: $pass_name is documented"
  else
    fail "sweep skill: $pass_name is documented" "no '### $pass_name' heading"
  fi
done

if grep -q 'runs identically on a 5-line PR' "$SWEEP"; then
  pass "sweep skill: size-independence is stated"
else
  fail "sweep skill: size-independence is stated" "the size-independence rule is missing"
fi

# The global "don't just check what was handed forward" constraint — the substance of
# rule 1, not just its heading, so trimming the explanation still fails this.
if grep -q 'never "nothing to check"' "$SWEEP"; then
  pass "sweep skill: an empty ledger does not mean nothing to check"
else
  fail "sweep skill: an empty ledger does not mean nothing to check" \
    "the 'never \"nothing to check\"' sentence is missing from the Two rules section"
fi

# Re-derive, never inherit: pass 2 must re-enumerate from the diff every time, not
# just whatever an earlier stage handed it.
if grep -q 'enumerates failure modes from the diff every single time' "$SWEEP"; then
  pass "sweep skill: pass 2 re-derives failure modes instead of inheriting them"
else
  fail "sweep skill: pass 2 re-derives failure modes instead of inheriting them" \
    "the 're-derive, never inherit' sentence is missing from the Two rules section"
fi

# The pass-4 carve-out is the one permitted exception to sub-agent independence —
# pin the reasoning, not just the bullet, so a later edit can't silently widen or
# drop the exception.
if grep -q 'work list of facts derived from the same diff' "$SWEEP"; then
  pass "sweep skill: the pass-4 findings carve-out is explained, not just asserted"
else
  fail "sweep skill: the pass-4 findings carve-out is explained, not just asserted" \
    "the 'work list of facts derived from the same diff' sentence is missing"
fi

# Reviewer hints may point toward risk, never away from it. If this rule is ever
# dropped, the hints become a laundering mechanism — pin it.
if grep -q 'toward risk, never away from it' "$SWEEP"; then
  pass "sweep skill: hints may not steer attention away from risk"
else
  fail "sweep skill: hints may not steer attention away from risk" \
    "the 'toward risk, never away from it' rule is missing"
fi

if grep -q 'may not be empty' "$SWEEP"; then
  pass "sweep skill: the risk list is required to be non-empty"
else
  fail "sweep skill: the risk list is required to be non-empty" \
    "the non-empty risk-list rule is missing"
fi

if grep -q '## How to review' "$SWEEP"; then
  pass "sweep skill: the How to review section is specified"
else
  fail "sweep skill: the How to review section is specified" "no '## How to review' in $SWEEP"
fi

# A repo's own PR template is a team convention and outranks our default shape.
if grep -q 'pull_request_template' "$SWEEP"; then
  pass "sweep skill: an existing PR template takes precedence"
else
  fail "sweep skill: an existing PR template takes precedence" \
    "the skill does not look for a repo PR template"
fi
