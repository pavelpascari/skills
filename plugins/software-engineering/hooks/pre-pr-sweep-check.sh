#!/bin/bash
# PreToolUse(Bash) hook: a human is about to be asked to review this branch.
# Remind the agent to run the pre-pr-sweep skill first — unless a sweep already
# ran on this exact commit. Advisory: never blocks, always exits 0.
set -euo pipefail

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // ""')
if [ "$tool_name" != "Bash" ]; then
  exit 0
fi

command=$(echo "$input" | jq -r '.tool_input.command // ""')
if [ -z "$command" ]; then
  exit 0
fi

# A heredoc body is data, not a command: `cat <<EOF` text that merely mentions
# `gh pr create` must not arm the tripwire. Drop every heredoc body first, while
# keeping the line that opens it (which may itself be a real `gh pr create`).
stripped=$(printf '%s\n' "$command" | awk '
  {
    if (skipping) { if ($0 == delim) { skipping = 0 }; next }
    print
    if (match($0, /<<-?[ \t]*[\047"]?[A-Za-z_][A-Za-z0-9_]*[\047"]?/)) {
      d = substr($0, RSTART, RLENGTH)
      sub(/^<<-?[ \t]*/, "", d)
      gsub(/[\047"]/, "", d)
      delim = d
      skipping = 1
    }
  }
')

# Exactly three invocations mean "a human is about to be asked to review".
# `gh pr list`, `gh pr view`, and `gh pr edit --title` must not match.
if printf '%s\n' "$stripped" | grep -Eq '(^|[[:space:];&|(])gh[[:space:]]+pr[[:space:]]+(create|ready)($|[[:space:]])'; then
  :
elif printf '%s\n' "$stripped" | grep -Eq '(^|[[:space:];&|(])gh[[:space:]]+pr[[:space:]]+edit([[:space:]].*)?--add-reviewer'; then
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
  entry_lines=$(printf '%s\n' "$open_entries" \
    | head -5 \
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
