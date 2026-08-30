#!/bin/bash
# Tests for hooks/remember-secret-guard.sh — the one blocking hook here.
# Sourced by run-tests.sh.
#
# Two properties matter equally. It must deny the credential shapes it claims
# to cover, and it must stay out of the way of everything else: a guard that
# denies ordinary prose gets disabled, after which it guards nothing.

SCRIPT="$HOOKS_DIR/remember-secret-guard.sh"
dir="$(scratch)"

# --- denies -----------------------------------------------------------------

assert_denies "remember-guard: denies an AWS access key ID" \
  "$dir" "$SCRIPT" "$(remember_json "prod creds are AKIAIOSFODNN7EXAMPLE for the uploader")" \
  "an AWS access key ID"

assert_denies "remember-guard: denies a PEM private key block" \
  "$dir" "$SCRIPT" "$(remember_json "deploy key: -----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA
-----END RSA PRIVATE KEY-----")" \
  "a PEM private key block"

assert_denies "remember-guard: denies a GitHub token" \
  "$dir" "$SCRIPT" "$(remember_json "CI uses ghp_0123456789abcdefghijABCDEFGHIJ0123")" \
  "a GitHub token"

assert_denies "remember-guard: denies a GitHub fine-grained token" \
  "$dir" "$SCRIPT" "$(remember_json "token github_pat_11ABCDEFG0abcdefghij_KLMNOP")" \
  "a GitHub fine-grained token"

assert_denies "remember-guard: denies an sk- API secret key" \
  "$dir" "$SCRIPT" "$(remember_json "the key is sk-abcdefghijklmnopqrstuvwxyz0123")" \
  "an API secret key"

assert_denies "remember-guard: denies a Slack token" \
  "$dir" "$SCRIPT" "$(remember_json "bot token xoxb-1234567890-abcdefghijklm")" \
  "a Slack token"

assert_denies "remember-guard: denies a Google API key" \
  "$dir" "$SCRIPT" "$(remember_json "maps key AIzaSyA0123456789abcdefghijklmnopqrstuvw")" \
  "a Google API key"

assert_denies "remember-guard: denies a JWT" \
  "$dir" "$SCRIPT" "$(remember_json "session eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.Sf1KxwRJ")" \
  "a JWT"

assert_denies "remember-guard: denies a connection string with an inline password" \
  "$dir" "$SCRIPT" "$(remember_json "connect with postgres://admin:hunter2pass@db.internal:5432/app")" \
  "an inline password"

# A secret can arrive in any argument, not only .text — the hook scans the whole
# serialized tool_input so a field added later is covered on the day it appears.
assert_denies "remember-guard: denies a secret outside the text field" \
  "$dir" "$SCRIPT" \
  "$(jq -nc '{tool_name: "mcp__hcampus__memory_remember", tool_input: {text: "routine note", scope: {project: "AKIAIOSFODNN7EXAMPLE"}}}')" \
  "an AWS access key ID"

# Naming the class is the point; quoting the match would copy the credential
# into the transcript this hook exists to keep it out of.
assert_output_lacks "remember-guard: never echoes the matched secret" \
  "$dir" "$SCRIPT" "$(remember_json "prod creds are AKIAIOSFODNN7EXAMPLE")" \
  "AKIAIOSFODNN7EXAMPLE"

# --- allows -----------------------------------------------------------------

assert_silent "remember-guard: allows an ordinary decision" \
  "$dir" "$SCRIPT" \
  "$(remember_json "Decided to keep SQLite as the physical projection; revisit if write volume grows.")"

# There is deliberately no generic `password = ...` rule — it is the pattern
# that fires on prose. These two cases pin that choice down so a future change
# that adds one has to argue with a failing test rather than slip in quietly.
assert_silent "remember-guard: allows prose describing where a secret lives" \
  "$dir" "$SCRIPT" \
  "$(remember_json "The deploy password is in 1Password under Infra, not in the repo.")"

assert_silent "remember-guard: allows prose mentioning tokens and API keys" \
  "$dir" "$SCRIPT" \
  "$(remember_json "We rotate the API key and the CI token every quarter.")"

assert_silent "remember-guard: allows an ordinary URL" \
  "$dir" "$SCRIPT" \
  "$(remember_json "Docs live at https://github.com/pavelpascari/skills and the mirror on :8080/api.")"

# --- stays out of the way ---------------------------------------------------

# Reads are none of this hook's business; only writes are irreversible.
assert_silent "remember-guard: silent for a non-remember tool" \
  "$dir" "$SCRIPT" \
  "$(tool_json "mcp__plugin_hcampus_hcampus__memory_recall" "AKIAIOSFODNN7EXAMPLE")"

# The undecorated name is what a project-level .mcp.json produces; the
# namespaced one is what a plugin-provided server produces. Both must guard.
assert_denies "remember-guard: matches the undecorated tool name too" \
  "$dir" "$SCRIPT" \
  "$(tool_json "mcp__hcampus__memory_remember" "AKIAIOSFODNN7EXAMPLE")" \
  "an AWS access key ID"

# --- fails open -------------------------------------------------------------
#
# A guard that denies because it could not parse its own input would block every
# write the moment anything upstream changed shape. Silence is the safe failure.

assert_silent "remember-guard: silent and exits 0 on malformed stdin" \
  "$dir" "$SCRIPT" "not json"

assert_silent "remember-guard: silent and exits 0 on empty stdin" \
  "$dir" "$SCRIPT" ""

assert_silent "remember-guard: silent when tool_input is absent" \
  "$dir" "$SCRIPT" "$(jq -nc '{tool_name: "mcp__hcampus__memory_remember"}')"
