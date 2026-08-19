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

for pass_name in "Pass 0" "Pass 1" "Pass 2" "Pass 3" "Pass 4" "Pass 5" "Pass 6"; do
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
