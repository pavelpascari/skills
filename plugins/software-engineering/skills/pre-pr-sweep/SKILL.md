---
name: pre-pr-sweep
description: >
  Use before asking anyone to review a branch — before `gh pr create`, `gh pr ready`,
  or adding a reviewer. Sweeps the whole-branch diff for uncontained failure paths,
  unguarded config, untested error branches, and undrained deferrals, then assembles
  the PR description. Runs its analytical passes as context-blind sub-agents.
user-invocable: true
---

# Pre-PR Sweep

The stage between "the tasks are done" and "a human is asked to look at this".

Task-scoped review answers *does this match the brief*, and correctly defers cross-cutting
concerns as out of scope. Branch-level review answers *is this consistent*. Neither one asks
*what happens when this fails, and is that tested* — so nothing does, and those findings arrive
from a reviewer instead.

This skill is that missing stage.

## Two rules that make it work

**1. Re-derive, never inherit.** Pass 2 enumerates failure modes from the diff every single time.
The deferral ledger is a convenience, not the input. An empty ledger means "nothing was handed
forward" — never "nothing to check". A sweep that only checks what an earlier stage chose to hand
it has rebuilt the exact gap it exists to close.

**2. This runs identically on a 5-line PR and a 500-line PR.** Rigor that scales with how
important a change feels is why the small ones leak. There is no "this is too small to sweep".

## Passes

Passes 0, 1, 6, and 7 run here, in the main context. Passes 2–5 run as **context-blind sub-agents**
(see below). Passes 2, 3, and 5 fan out in parallel; pass 4 runs after pass 2; pass 7 runs last,
because its risk list is derived from what 2–5 found.

### Pass 0 — Pin the diff

```bash
git fetch origin --quiet
BASE=$(git merge-base origin/main HEAD)   # or the repo's default branch
git diff "$BASE"...HEAD --stat
```

Confirm the diff is non-empty, and that `$BASE` is still an ancestor of `origin/main`.

If the base is stale, **abort the sweep** and say: rebase first. A diff padded with unrelated
files from an old merge base makes every downstream pass produce findings against code this PR
does not own — wasted effort that also trains you to ignore the output.

### Pass 1 — Drain the ledger

Read `docs/deferred-review-flags.md`. Entries look like this — the leading `- [ ]` is what the
tripwire hook greps for, so the format is a contract, not a suggestion:

```markdown
- [ ] 2026-08-19 `FirstAvailableSlotsQuery.kt:41` parseDueMember accepts >3 segments,
      silently dropping extras. Deferred by: task-scoped review (out of brief scope).
```

Every open entry (`- [ ]`) must be closed as exactly one of:

- `FIXED <sha>`
- `TICKETED <id>`
- `ACCEPTED <one-line rationale>`

Rewrite each entry in place, flipping `- [ ]` to `- [x]` and appending the disposition:

```markdown
- [x] 2026-08-19 `FirstAvailableSlotsQuery.kt:41` parseDueMember accepts >3 segments … — FIXED 2fd3eb955
```

No entry survives the sweep undecided — that is the whole mechanism. Dispositions feed the
`## Deferred` section of the PR body.

If the file does not exist, note "no ledger" and continue. It is not evidence of anything.

### Pass 2 — Failure-mode enumeration (sub-agent)

For every new or changed operation that can fail — external I/O, batched or pipelined operations,
callbacks running on a framework's event-loop thread, metrics value-suppliers, anything the code
calls best-effort — answer two questions:

1. **If this throws mid-operation, what is the blast radius?** Not "is it caught" — what actually
   breaks. One gauge supplier throwing fails the entire Prometheus scrape, not one metric. A throw
   mid-batch orphans already-queued commands into a later, unrelated batch.
2. **Is there a test that forces the throw?** If not, that is a finding regardless of the coverage
   percentage. Coverage counts lines executed, not failures exercised.

**Sub-lens — a documented best-effort claim must be enforced by a catch.** If a comment, docstring,
or design note calls a path "bookkeeping", "fire-and-forget", or "best-effort" and no handler
exists, the code lies about itself. Cross-reference: *code must never lie*, in the
`software-engineering` skill.

### Pass 3 — New config surface (sub-agent)

Every new numeric, duration, or size config field or constructor parameter needs a validation
guard plus two tests: rejection just outside the legal range, and acceptance at the smallest legal
value. The second is what catches a guard written `> 1` when it meant `> 0`.

Prioritise values the downstream system **silently accepts**: a timeout of `0` that makes an await
block forever instead of failing fast; a `MAXLEN ~ 0` that returns a real entry ID while leaving
the stream empty. These do not fail loudly, so only a guard catches them.

### Pass 4 — Failure-path test coverage (sub-agent, after pass 2)

Delegate to the `test-code-review` skill, passing the diff **and pass 2's failure list**, so
coverage is checked against enumerated failure modes rather than hunted blind.

If `test-code-review` is not installed, run the pass with this inline brief instead, and say so in
the report — the sweep degrades, it does not skip:

> For every error-handling construct in the implementation diff (catch/rescue/except, error
> returns, fallback defaults, retries), is there a test that *forces* that failure? Separately:
> is any assertion weak enough to survive a plausible regression?

### Pass 5 — Duplication within the diff (sub-agent)

Helper logic — hashing, key encoding, parsing — appearing in two or more files *within this diff*:
extract it, or record an explicit drift guard. Scoped to the diff, so this cannot escalate into a
codebase-wide refactor.

### Pass 6 — Hygiene

Mechanical, run here:

- PR title matches the repo's documented convention. Look in `CONTRIBUTING.md`, `.github/`, and any
  title-check workflow config.
- PR body has no unresolved `do not merge`, `before merging`, `verify X first`.
- `gh pr diff --name-only` lists only files this change owns.
- For a stacked PR: did the test workflow actually run? A workflow scoped
  `pull_request: branches: [main]` runs none of its matrix on a PR based on another branch, while
  the fast checks still go green — which makes an untested stack look tested. Verify with
  `gh run list --branch <branch>`, and record the answer under `## Verification caveats`.

## Context-blind sub-agents

Passes 2–5 each spawn a `general-purpose` sub-agent. A fresh context — not a fork.

The bias this avoids is specific: an agent that knows *why* the code was written this way will
accept the rationale. That is exactly how a real edge case gets cleared as "inherited from the
brief, not an implementer deviation". A reviewer who has never seen the brief cannot make that
move.

**Forbidden inputs.** Each sub-agent prompt is self-contained and deliberately impoverished:

- ✗ the task brief, plan, spec, or ticket text
- ✗ the PR description or the author's stated intent
- ✗ any prior review's conclusions — sub-agents **MUST NOT read the ledger**
- ✗ other passes' findings; the lenses stay independent — except pass 4, which receives pass 2's
  failure list by design (the one permitted cross-pass flow, explained below)
- ✓ the repo path, the diff command, and its own pass brief

**The one exception.** Pass 4 receives pass 2's failure list, and only pass 2's failure list — not
as rationale, but as a work list of facts derived from the same diff, because pass 4's job is
checking test coverage *against* enumerated failure modes rather than hunting blind. The bias the
blinding exists to prevent is the *author's* rationale, which lets a reviewer accept a
justification instead of judging the code in front of it; a sibling pass's enumerated findings are
not rationale, so this flow does not reintroduce that bias. No other pass receives another pass's
output — this is the only permitted cross-pass flow.

**Prompt template:**

> You are reviewing a diff in `<repo path>`. Get it with: `git diff <BASE>...HEAD`.
>
> <the pass brief, verbatim from above>
>
> Assume this code has an unhandled failure and find it. If you are uncertain whether something is
> a finding, report it.
>
> Every finding MUST carry: `file:line`, and a concrete failure scenario — specific inputs or state
> leading to a specific wrong outcome. A finding you cannot write a scenario for will be discarded,
> so do not pad. Do not ask about intent; judge the code in front of you.

**Noise control.** Discard findings without a concrete failure scenario, and report how many were
discarded. A pass that systematically over-flags should be visible, not invisible.

**A pass that returns nothing** is reported as "pass N did not complete" — never silently treated
as "no findings". A silent empty pass is the failure mode this skill exists to eliminate.

**Reconcile the ledger after, never before.** A blind agent will re-flag something already marked
`ACCEPTED`. That is correct behaviour. Handing it the ledger up front to prevent the duplicate
would bias the finding itself — prior acceptance is triage input, not review input. Report those as:

```
re-flagged, previously accepted 2026-08-14: <rationale>
```

which is also how an acceptance that has quietly gone stale becomes visible.

## Finishing

Record the sweep so the tripwire stays quiet until the next commit:

```bash
mkdir -p "$(git rev-parse --git-dir)/software-engineering"
git rev-parse HEAD > "$(git rev-parse --git-dir)/software-engineering/last-sweep"
```

Then report: **`Ready for review`**, or **`Not ready`** plus the blocking findings. Each finding
carries `file:line`, the failure scenario, and a proposed fix.
