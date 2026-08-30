#!/bin/bash
# PreToolUse hook on memory_remember: stop credential-shaped material from
# reaching durable memory.
#
# This is the only hook in this marketplace that blocks, and the exception is
# deliberate. Every other hook here warns because the cost of being wrong is one
# ignorable line. hcampus memory is append-only and provenance-preserving: a key
# written into it is evidence forever, readable from every earlier snapshot, and
# `memory_forget` is a logical forget that changes later snapshots without
# removing what was stored. There is no undo to fall back on, so the check has
# to happen before the write, not after.
#
# The trade is paid for by scope. Only high-confidence, structurally distinctive
# credential shapes deny — no generic `password = ...` rule, which is the
# pattern that generates false positives on ordinary prose. Everything else
# fails OPEN: malformed input, missing jq, an unreadable payload, a tool name
# that is not memory_remember — all exit 0 silently. A guard that blocks the
# tool because it could not parse its own input would be worse than no guard.
set -euo pipefail

input=$(cat)

# Malformed JSON (or no JSON at all, e.g. empty stdin) makes jq exit non-zero.
# A bare assignment failing there would abort the script under `set -e` with
# jq's own exit status. For a hook that can deny, a crash is not neutral —
# the caller sees a failed hook, not a passed one. `|| exit 0` keeps every
# parse failure on the fail-open path.
tool_name=$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null) || exit 0

# The matcher in hooks.json already narrows to memory_remember, but the exact
# tool name depends on how the MCP server was loaded — a plugin-provided server
# is namespaced (mcp__plugin_hcampus_hcampus__memory_remember), a
# project-level .mcp.json is not (mcp__hcampus__memory_remember). Matching the
# stable suffix here means this script is correct under both, and correct again
# if a future matcher is loosened.
case "$tool_name" in
  *memory_remember) : ;;
  *) exit 0 ;;
esac

# Scan the whole serialized tool_input rather than just `.text`. A secret pasted
# into `scope`, `targets`, or a field added later is the same secret; scanning
# one named field would quietly stop covering it the day the tool grows an
# argument.
payload=$(jq -c '.tool_input // {}' <<<"$input" 2>/dev/null) || exit 0
if [ -z "$payload" ] || [ "$payload" = "{}" ]; then
  exit 0
fi

detected=""

# scan <extended-regex> <label>
# Records the label, never the match. The reason string is echoed back into the
# transcript, so quoting the matched text would copy the secret into exactly the
# durable record this hook exists to keep it out of.
scan() {
  if grep -Eq -- "$1" <<<"$payload"; then
    detected="${detected}${detected:+, }$2"
  fi
}

scan '-----BEGIN [A-Z ]*PRIVATE KEY-----'                 'a PEM private key block'
scan 'AKIA[0-9A-Z]{16}'                                   'an AWS access key ID'
scan '\bsk-[A-Za-z0-9_-]{16,}'                            'an API secret key (sk- prefix)'
scan '\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}'           'a GitHub token'
scan '\bgithub_pat_[A-Za-z0-9_]{20,}'                     'a GitHub fine-grained token'
scan '\bxox[abprs]-[A-Za-z0-9-]{10,}'                     'a Slack token'
scan '\bAIza[0-9A-Za-z_-]{35}'                            'a Google API key'
scan '\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.'   'a JWT'
# A URL carrying inline credentials: scheme://user:password@host. The character
# classes exclude `/` so a path segment containing a colon can never be read as
# a credential pair.
scan '[a-zA-Z][a-zA-Z0-9+.-]*://[^:@/[:space:]"]+:[^@/[:space:]"]+@' 'a connection string with an inline password'

if [ -z "$detected" ]; then
  exit 0
fi

reason="This memory_remember call carries what looks like $detected.

hcampus memory is append-only: stored evidence stays readable from every later
snapshot, and memory_forget is a logical forget, not a deletion. A credential
written here cannot be taken back.

Rewrite the thought to describe the secret rather than contain it — which
credential it is, where it lives, what it is for — and call memory_remember
again. If this is a placeholder or an example rather than a live credential,
say so and the call can be re-issued deliberately."

jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
