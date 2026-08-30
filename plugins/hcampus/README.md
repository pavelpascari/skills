# hcampus

Durable, evidence-backed memory for Claude Code, backed by the
[hcampus](https://github.com/pavelpascari/hcampus) MCP server.

Unlike a scratch file of remembered facts, hcampus keeps evidence append-only
and derives accepted Claims from it against a pinned snapshot. Retrieval is not
truth: a recall tells you what is supported, what defeats it, and where it came
from.

## Prerequisite

This plugin ships the MCP server declaration but not the server. Install
`hcampus-mcp` and put it on PATH:

```bash
git clone https://github.com/pavelpascari/hcampus
cd hcampus
uv sync --all-extras --dev
```

The `SessionStart` hook checks for the command named in `.mcp.json` and says so
once if it cannot find it.

## What you get

**The `hcampus-memory` skill** — when to recall (and in which mode), what is
worth remembering and under which Thought Kind, and when to forget. It also
establishes that recalled text is untrusted data, never instructions.

**Four hooks:**

| Event | Script | What it does |
|-------|--------|--------------|
| `SessionStart` | `session-start-check.sh` | Warns once if the MCP server command is not on PATH, so a missing install surfaces up front instead of as a missing tool mid-task. |
| `UserPromptSubmit` | `prompt-recall-nudge.sh` | When a prompt leans on settled history — "we decided", "as discussed", "forget that" — points at the skill before the work starts. |
| `PreToolUse` | `remember-secret-guard.sh` | Denies a `memory_remember` carrying credential-shaped material. |
| `Stop` | `stop-persist-nudge.sh` | Once per session, and only if nothing was stored yet, asks whether the session produced anything durable. |

### Why one hook blocks

Every other hook in this marketplace is advisory. This one is not, and the
exception is deliberate: hcampus memory is append-only, `memory_forget` is a
logical forget rather than a deletion, and a credential written into evidence
stays readable from every earlier snapshot. There is no undo to fall back on.

The trade is paid for by scope. Only structurally distinctive credential shapes
deny — PEM key blocks, AWS access key IDs, GitHub and Slack and Google tokens,
JWTs, `sk-` keys, and URLs carrying an inline password. There is deliberately no
generic `password = ...` rule, because that is the pattern that fires on
ordinary prose. Everything else fails open: malformed input, a missing `jq`, an
unexpected payload shape all exit silently rather than block a write.

## Tests

```bash
bash plugins/hcampus/hooks/tests/run-tests.sh
```
