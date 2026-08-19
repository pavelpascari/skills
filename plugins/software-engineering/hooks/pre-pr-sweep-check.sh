#!/bin/bash
# PreToolUse(Bash) hook: a human is about to be asked to review this branch.
# Remind the agent to run the pre-pr-sweep skill first — unless a sweep already
# ran on this exact commit. Advisory: never blocks, always exits 0.
set -euo pipefail

input=$(cat)

tool_name=$(jq -r '.tool_name // ""' <<<"$input")
if [ "$tool_name" != "Bash" ]; then
  exit 0
fi

command=$(jq -r '.tool_input.command // ""' <<<"$input")
if [ -z "$command" ]; then
  exit 0
fi

# A heredoc body is data, not a command: `cat <<EOF` text that merely mentions
# `gh pr create` must not arm the tripwire. Drop every heredoc body first, while
# keeping the line that opens it (which may itself be a real `gh pr create`).
#
# The awk pass appends one final sentinel line reporting whether it hit EOF
# still inside an unterminated heredoc (e.g. `<<-EOF` closed by a tab-indented
# terminator we failed to recognize, or a `<<` inside quoted text that was
# never really a heredoc at all). For an advisory hook a false positive costs
# one ignorable reminder; a false negative silently defeats the whole
# mechanism — so when parsing is uncertain, discard the stripped result and
# match against the ORIGINAL, unstripped command instead.
#
# NOTE: this whole assignment reads all of $command via a single awk pass
# that never exits early (no early `exit`, no early-terminating consumer
# downstream) — safe against SIGPIPE regardless of input size.
awk_out=$(printf '%s\n' "$command" | awk '
  {
    line = $0
    if (skipping) {
      cmp = line
      if (dash) { sub(/^\t+/, "", cmp) }
      sub(/[ \t]+$/, "", cmp)
      if (cmp == delim) { skipping = 0 }
      next
    }
    print line
    # A here-string (`<<<`) is not a heredoc opener; strip it from the copy
    # we scan for openers so it cannot be mistaken for one.
    scan = line
    gsub(/<<</, "", scan)
    if (match(scan, /<<-?[ \t]*[\047"]?[A-Za-z_][A-Za-z0-9_]*[\047"]?/)) {
      d = substr(scan, RSTART, RLENGTH)
      dash = (d ~ /^<<-/)
      sub(/^<<-?[ \t]*/, "", d)
      gsub(/[\047"]/, "", d)
      delim = d
      skipping = 1
    }
  }
  END {
    if (skipping) { print "###SWEEP_HOOK_UNTERMINATED###" }
    else { print "###SWEEP_HOOK_OK###" }
  }
')
sentinel="${awk_out##*$'\n'}"
if [ "$sentinel" = "###SWEEP_HOOK_UNTERMINATED###" ]; then
  stripped="$command"
else
  stripped="${awk_out%$'\n'*}"
fi

# Exactly three invocations mean "a human is about to be asked to review".
# `gh pr list`, `gh pr view`, and `gh pr edit --title` must not match.
# Here-strings (`<<<`), not pipes, so a match on line one can never SIGPIPE
# a still-writing producer regardless of how large $stripped is.
if grep -Eq '(^|[[:space:];&|(])gh[[:space:]]+pr[[:space:]]+(create|ready)($|[[:space:]])' <<<"$stripped"; then
  :
elif grep -Eq '(^|[[:space:];&|(])gh[[:space:]]+pr[[:space:]]+edit([[:space:]].*)?--add-reviewer' <<<"$stripped"; then
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
  # A CRLF-saved marker leaves a trailing \r that head -1 does not strip
  # (it only stops at \n); trim it so a CRLF marker matching HEAD reads as
  # a match instead of a permanent, spurious nag.
  swept="${swept%$'\r'}"
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
  entry_lines=$(printf '%s\n' "$open_entries" \
    | sed -n '1,5p' \
    | sed -E 's/^[[:space:]]*-[[:space:]]*\[[[:space:]]\][[:space:]]*//' \
    | cut -c1-90 \
    | sed 's/^/    · /')
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
