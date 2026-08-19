#!/bin/bash
# PreToolUse(Bash) hook: a human is about to be asked to review this branch.
# Remind the agent to run the pre-pr-sweep skill first — unless a sweep already
# ran on this exact commit. Advisory: never blocks, always exits 0.
set -euo pipefail

input=$(cat)

# Malformed JSON (or no JSON at all, e.g. empty stdin) makes jq exit non-zero.
# A bare assignment failing there would abort the script under `set -e` with
# jq's own exit status — exactly the "hooks never block" violation this
# script guards against everywhere else. `|| exit 0` keeps the failure from
# ever reaching `set -e`.
tool_name=$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null) || exit 0
if [ "$tool_name" != "Bash" ]; then
  exit 0
fi

command=$(jq -r '.tool_input.command // ""' <<<"$input" 2>/dev/null) || exit 0
if [ -z "$command" ]; then
  exit 0
fi

# Match against the ORIGINAL command text directly — there is deliberately no
# heredoc-body stripping here.
#
# A previous version tried to skip heredoc bodies so that `cat <<EOF` text
# merely mentioning `gh pr create` would not arm the tripwire. Its awk parser
# read a bare `<<` inside an ordinary quoted string — e.g. `echo "look: <<
# STOP"` — as a real heredoc opener. When a later line in the command happened
# to equal that phantom delimiter (e.g. a bare `STOP` line), the parser
# terminated "cleanly": the unterminated-heredoc safety net never fired, and
# every line in between — including a real `gh pr create --fill` — was
# silently swallowed before matching ever ran. That is a silent bypass of the
# whole hook, not a corner case, and it is the second independent way this
# stripper found to disarm itself.
#
# For an advisory hook, the cost of the false positive the stripper existed to
# prevent — one ignorable reminder when a heredoc body happens to mention
# `gh pr create` — is far smaller than the cost of its failure mode: total,
# undetectable silence on a real PR-creation command. Matching raw command
# text accepts that rare cosmetic false positive in exchange for closing off
# that whole class of silent bypass. See hooks/tests/test-pre-pr-sweep.sh for
# the case this now deliberately arms on.
#
# grep is line-based and `.` cannot span newlines, so a shell line-continuation —
# `gh pr edit 5 \` followed by `  --add-reviewer x` on the next line — would otherwise
# never match either pattern below even though it is one logical command. Join
# backslash-continued lines into a single line first (dropping the trailing `\`, keeping
# a space so tokens don't fuse) before matching. This reads all of $command via a single
# awk pass with no early exit, so it is safe against SIGPIPE regardless of input size.
#
# Kept identical, character for character, to the continuation-join block in
# scripts/bug-fix-test-check.sh — see hooks/tests/test-boundary-drift.sh, which fails the
# suite if the two preprocessing idioms drift apart (the same class of bug as finding 3
# there: two scripts detecting commands differently with nothing pinning them together).
# CONTINUATION-JOIN-BEGIN
joined=$(printf '%s\n' "$command" | awk '
  {
    line = (buf != "") ? buf $0 : $0
    if (line ~ /\\$/) {
      sub(/\\$/, " ", line)
      buf = line
    } else {
      print line
      buf = ""
    }
  }
  END { if (buf != "") print buf }
')
# CONTINUATION-JOIN-END

# Exactly three invocations mean "a human is about to be asked to review".
# `gh pr list`, `gh pr view`, and `gh pr edit --title` must not match.
# Here-strings (`<<<`), not pipes, so a match on line one can never SIGPIPE
# a still-writing producer regardless of how large $joined is.
#
# Boundary class: characters that can immediately precede `gh` and still mark
# a genuine command position, not just a substring inside a longer word.
# Originally just shell metacharacters (whitespace, `;`, `&`, `|`, `(` for
# `$(...)`/subshells) — which missed every quoted-wrapper form: `eval "gh pr
# create --fill"`, `bash -c "gh pr create --fill"`, `ssh host "gh pr create
# --fill"` all put a `"` immediately before `gh`, and none of `"`, `'`, or a
# backtick (legacy `` `cmd` `` command substitution) were in the class, so
# the tripwire silently never armed on any of them. `$(...)` needs no
# addition: its `(` is already covered. `{` is deliberately left out — bash
# requires whitespace right after `{` for it to open a command group
# (`{ gh ...; }`), so that case is already covered by [[:space:]], and a bare
# `{gh` has no shell meaning to catch.
#
# Built via `printf '%b'` with `\0NNN` octal escapes so the class itself
# never contains a literal quote/backtick that would fight with this file's
# own shell quoting. Kept identical, character for character, to the
# `git_boundary` class in scripts/bug-fix-test-check.sh — see
# hooks/tests/test-boundary-drift.sh, which fails the suite if the two drift
# apart again.
gh_boundary=$(printf '%b' '[[:space:];&|(\042\047\0140]')
if grep -Eq "(^|${gh_boundary})gh[[:space:]]+pr[[:space:]]+(create|ready)(\$|[[:space:]])" <<<"$joined"; then
  :
elif grep -Eq "(^|${gh_boundary})gh[[:space:]]+pr[[:space:]]+edit([[:space:]].*)?--add-reviewer" <<<"$joined"; then
  :
else
  exit 0
fi

# Everything below is best-effort: any surprise exits 0 rather than nagging wrongly.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi
git_dir=$(git rev-parse --git-dir 2>/dev/null || true)
head_sha=$(git rev-parse HEAD 2>/dev/null || true)
if [ -z "$git_dir" ] || [ -z "$head_sha" ]; then
  exit 0
fi

marker="$git_dir/software-engineering/last-sweep"
swept=""
if [ -r "$marker" ]; then
  swept=$(head -1 "$marker" 2>/dev/null || true)
  # head -1 stops at \n but strips nothing else: a marker saved with a
  # trailing space/tab, a CRLF (\r), or even \r\r would otherwise never
  # equal a bare $head_sha and would nag permanently. Trim ALL trailing
  # whitespace, not just a single \r.
  while :; do
    trimmed="${swept%[[:space:]]}"
    [ "$trimmed" = "$swept" ] && break
    swept="$trimmed"
  done
fi
if [ "$swept" = "$head_sha" ]; then
  exit 0
fi

head_short=$(git rev-parse --short HEAD 2>/dev/null || true)
swept_short="never"
since=""
if [ -n "$swept" ]; then
  swept_short="${swept:0:7}"
  if git cat-file -e "${swept}^{commit}" 2>/dev/null; then
    n=$(git rev-list --count "$swept..HEAD" 2>/dev/null || true)
    if [ -n "$n" ]; then
      since="  ($n commits since)"
    fi
  fi
fi

# Name the outstanding deferrals. A count alone earns banner-blindness; the
# specific items are what make this worth reading.
ledger="docs/deferred-review-flags.md"
open_entries=""
if [ -r "$ledger" ]; then
  open_entries=$(grep -E '^[[:space:]]*-[[:space:]]+\[[[:space:]]\]' "$ledger" 2>/dev/null || true)
fi

count=0
entry_lines=""
if [ -n "$open_entries" ]; then
  count=$(printf '%s\n' "$open_entries" | wc -l | tr -d ' ')
  # `sed -n '1,5p'`, not `head -5`: head exits as soon as it has its 5
  # lines, and on a large ledger that early exit SIGPIPEs the still-writing
  # printf upstream (fatal under `set -o pipefail`). sed reads to EOF
  # regardless of how much it prints, so no stage here can be SIGPIPEd.
  #
  # `cut -c` is codepoint-aware under a UTF-8 locale, and a ledger line
  # containing an invalid UTF-8 byte (e.g. a path pasted with bad encoding)
  # makes BSD/macOS cut exit 1 with "Illegal byte sequence". Under
  # `set -euo pipefail` that would abort the whole script with no JSON on
  # stdout at all — the "Advisory: never blocks" hook violating its own
  # contract, and doing so exactly when the ledger has entries worth
  # reporting. `LC_ALL=C` makes `cut` treat every byte as one character (the
  # single-byte C locale), so it can never reject a byte as "invalid" and the
  # entry text survives untouched; it only scopes to this one command, not
  # `sed` (a separate process) or anything else in the pipeline. `|| true` on
  # the assignment is a second, independent guard: if some future change
  # reintroduces a locale-sensitive failure here, the hook must still print
  # its warning (sans truncation) rather than abort silently — a guard that
  # instead produced an empty entry list would drop the deferral names,
  # which is a quieter version of the same bug.
  entry_lines=$(printf '%s\n' "$open_entries" \
    | sed -n '1,5p' \
    | sed -E 's/^[[:space:]]*-[[:space:]]*\[[[:space:]]\][[:space:]]*//' \
    | LC_ALL=C cut -c1-90 \
    | sed 's/^/    · /') || true
  if [ "$count" -gt 5 ]; then
    entry_lines=$(printf '%s\n    · … and %s more' "$entry_lines" "$((count - 5))")
  fi
fi

{
  printf '── pre-pr-sweep has not run on this commit ──\n'
  printf '  swept: %s   HEAD: %s%s\n' "$swept_short" "$head_short" "$since"
  if [ "$count" -gt 0 ]; then
    printf '  %s open deferral(s):\n' "$count"
    printf '%s\n' "$entry_lines"
  fi
  printf '  → run the pre-pr-sweep skill, or say "skip the sweep" to proceed\n'
} | jq -Rs '{systemMessage: .}'
