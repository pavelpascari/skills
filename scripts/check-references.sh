#!/bin/bash
# Skills use progressive disclosure: a thin SKILL.md points at `references/...`
# files the agent loads only when it needs them. That keeps context small, and it
# means every pointer is a path resolved by a reader rather than by a compiler.
#
# A renamed or deleted reference file therefore fails silently — the skill still
# loads, the agent follows a pointer to nothing, and the guidance it was meant to
# reach is simply absent. This check resolves every referenced path.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
checked=0

# Every markdown file that ships inside a skill can carry pointers.
while IFS= read -r doc; do
  doc_dir="$(dirname "$doc")"

  # The skill root is the directory holding SKILL.md; `references/...` paths are
  # written relative to it, not to the file doing the pointing.
  skill_root="$doc_dir"
  while [ "$skill_root" != "$ROOT" ] && [ ! -r "$skill_root/SKILL.md" ]; do
    skill_root="$(dirname "$skill_root")"
  done
  [ -r "$skill_root/SKILL.md" ] || continue

  # Pointers appear as `references/foo.md`, or in brace form naming several
  # siblings at once: `references/languages/{go,rust,ruby}.md`. The brace form is
  # what the language pointers use, so it must be expanded rather than skipped —
  # an unexpanded brace pointer silently validates nothing, which is how the
  # first version of this check passed while a renamed language file was broken.
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    checked=$((checked + 1))
    if [ ! -r "$skill_root/$ref" ]; then
      printf 'BROKEN  %s\n          points at %s, which does not exist\n' \
        "${doc#"$ROOT"/}" "$ref"
      fail=1
    fi
  done < <(
    {
      # Plain pointers.
      grep -oE '`references/[A-Za-z0-9_/-]+\.md`' "$doc" 2>/dev/null | tr -d '`' || true
      # Brace pointers, expanded to one path per named sibling.
      grep -oE '`references/[A-Za-z0-9_/-]*\{[A-Za-z0-9_,-]+\}\.md`' "$doc" 2>/dev/null \
        | tr -d '`' \
        | while IFS= read -r brace; do
            prefix="${brace%%\{*}"
            names="${brace#*\{}"; names="${names%%\}*}"
            printf '%s\n' "$names" | tr ',' '\n' | while IFS= read -r n; do
              [ -n "$n" ] && printf '%s%s.md\n' "$prefix" "$n"
            done
          done || true
    } | sort -u
  )
done < <(find "$ROOT/plugins" -path '*/skills/*' -name '*.md' -type f | sort)

if [ "$fail" -ne 0 ]; then
  printf '\nEvery `references/...md` pointer must resolve from its skill root.\n'
  exit 1
fi

printf 'All %s reference pointers resolve.\n' "$checked"
