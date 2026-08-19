#!/bin/bash
# Every plugin declares its version twice: in the marketplace entry and in its own
# plugin.json. At install time plugin.json wins (calculatePluginVersion precedence),
# so a marketplace entry that disagrees is not a cosmetic mismatch — it is a version
# users are shown but never receive.
#
# `claude plugin validate` reports this as a warning and still exits 0, so CI stayed
# green through two releases while the two files drifted apart. This check fails.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
MANIFEST="$ROOT/.release-please-manifest.json"

fail=0

note_failure() {
  printf 'MISMATCH  %s\n            %s\n' "$1" "$2"
  fail=1
}

if [ ! -r "$MARKETPLACE" ]; then
  printf 'cannot read %s\n' "$MARKETPLACE"
  exit 1
fi

# Compare, per plugin: the marketplace entry, the plugin's own plugin.json, and
# release-please's manifest — the record of what was actually tagged and released.
while IFS=$'\t' read -r name source entry_version; do
  [ -n "$name" ] || continue

  plugin_json="$ROOT/${source#./}/.claude-plugin/plugin.json"
  if [ ! -r "$plugin_json" ]; then
    note_failure "$name" "no plugin.json at ${plugin_json#"$ROOT"/}"
    continue
  fi

  plugin_version=$(jq -r '.version // ""' "$plugin_json")
  if [ -z "$plugin_version" ]; then
    note_failure "$name" "plugin.json declares no version"
    continue
  fi

  if [ "$entry_version" != "$plugin_version" ]; then
    note_failure "$name" \
      "marketplace.json says $entry_version, plugin.json says $plugin_version (plugin.json wins at install time)"
    continue
  fi

  # The manifest is release-please's record of the last tagged release. If either
  # file has drifted from it, a release bumped one and left the other behind.
  if [ -r "$MANIFEST" ]; then
    manifest_version=$(jq -r --arg p "${source#./}" '.[$p] // ""' "$MANIFEST")
    if [ -n "$manifest_version" ] && [ "$manifest_version" != "$plugin_version" ]; then
      note_failure "$name" \
        "both files say $plugin_version but the release manifest says $manifest_version"
      continue
    fi
  fi

  printf 'ok        %s %s\n' "$name" "$plugin_version"
done < <(jq -r '.plugins[] | [.name, .source, (.version // "")] | @tsv' "$MARKETPLACE")

if [ "$fail" -ne 0 ]; then
  printf '\nVersions must agree across marketplace.json, plugin.json, and the release manifest.\n'
  printf 'release-please keeps them in sync via the extra-files entries in release-please-config.json.\n'
  exit 1
fi

printf '\nAll plugin versions agree.\n'
