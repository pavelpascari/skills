---
name: pre-pr-sweep
description: >
  Use before asking anyone to review a branch — before `gh pr create`, `gh pr ready`,
  or adding a reviewer. Sweeps the whole-branch diff for uncontained failure paths,
  unguarded config, untested error branches, drifted comments, and undrained deferrals, then assembles
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

**Re-derivation's coverage is real but partial — say so plainly.** Passes 2, 3, 5 and 5b re-derive
four specific classes straight from the diff: failure modes, new config guards, in-diff duplication,
and comments that no longer match the code. That is genuine independence from the ledger for those
four classes, and an empty ledger does not weaken it. But a deferred finding outside them — a
misleading name, a leaky abstraction, an unvalidated string field, a perf concern —
has no re-deriving pass behind it. The ledger is its only carrier, and the ledger is a convenience, not a guarantee: if nothing
wrote it down, it is gone. Do not let the re-derivation rule above be read as "the sweep catches
everything regardless of the ledger" — it catches those four classes regardless of the ledger,
and nothing else.

**2. This runs identically on a 5-line PR and a 500-line PR.** Rigor that scales with how
important a change feels is why the small ones leak. There is no "this is too small to sweep".

## Passes

Passes 0, 1, 6, and 7 run here, in the main context. Passes 2–5b run as **context-blind sub-agents**
(see below). Passes 2, 3, 5 and 5b fan out in parallel; pass 4 runs after pass 2; pass 7 runs last,
because its risk list is derived from what 2–5b found.

(Pass 5b is numbered rather than appended as "pass 8" so that pass 7 stays last, where it belongs —
it consumes the analytical passes' output and cannot precede them.)

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

**Keep the ledger out of git.** Ensure it is gitignored before the first write to
`docs/deferred-review-flags.md` — whether this sweep is the one creating the file, or finds it
already present but untracked and unignored. It is a working document, not a reviewable artifact;
no PR should carry a diff of someone else's deferred findings.

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

### Pass 5b — Comment value (sub-agent)

Every comment in a changed hunk **and its enclosing function or block** gets one of three verdicts:

- **keep** — deleting it would lose information not recoverable from the code
- **noise** — recoverable from the code; delete it, or rename so it is
- **it lies** — the code moved and the comment did not

**Read comments the diff did not touch.** A comment goes stale precisely because the code changed
and the comment did not, so the drifted comment is usually *not* a changed line — it sits unchanged
beside changed code. A pass scoped to changed comment lines catches rewrites and misses every real
drift, which is the failure mode this pass exists for.

For a docstring on a public API, ask the stricter question: does it state the **contract** — inputs,
failure modes, invariants, units — or restate the signature?

**A drifted comment is a blocking finding. Noise is not.** Noise costs a reader seconds; a comment
that has drifted actively sends them where the code does not go, and is worse than no comment,
because a reader with no comment would have read the code. Report noise as a suggestion, so this
pass does not become a style-nit generator that reviewers learn to skip.

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

### Pass 7 — PR narrative and reviewer hints

The only pass that **produces content** rather than reporting findings: it assembles the PR body.
It runs **after** passes 2–5b, because its risk list is derived from their findings.

**Every PR answers three questions**, stacked or standalone:

1. **Why this change is valuable on its own.** Not what it changes — what it buys. A body that
   restates the diff gives the reviewer nothing the diff does not already say.
2. **What it depends on.** Parent PR or branch, and the ticket.
3. **What builds on it next.** Child PRs, planned follow-ups, and why this piece was worth
   separating. This one still applies when nothing is stacked behind it yet.

**Stack detection:**

```bash
git log origin/main..HEAD --oneline
gh pr list --author @me --state open --json number,title,headRefName,baseRefName
```

Siblings are the open PRs sharing this change's ticket prefix; the parent is whichever sibling
branch is the merge-base of this one.

**Cross-PR collision check.** For each sibling, compare changed files and top-level symbols against
this PR's. Surface every overlap in the body, so whoever merges second knows what they are
resolving before they hit it.

#### `## How to review`

A reviewer opens a diff sorted alphabetically, every hunk weighted equally, with no idea what the
author already checked. Fix that with four parts:

1. **Reading order.** Entry point → core change → tests, as a path list. Alphabetical is almost
   never the comprehension order.
2. **Where the risk is.** The specific hunks that deserve real scrutiny, and why each one is the
   risky one.
3. **What was verified, and how.** Commands run, environments hit, evidence produced — so the
   reviewer does not silently redo it. Paired with **what was not verified**, stated plainly.
4. **Questions for the reviewer.** The genuine tradeoffs decided unilaterally, in the form the
   *Decisions* principle already requires: "I picked X over Y because Z; happy to flip."

**Hints point toward risk, never away from it.** A description that tells a reviewer which files
are boring is a laundering mechanism, and worse than no hints at all. The test is the **effect**,
not the wording: any phrasing whose effect is to lower the reviewer's attention on a hunk is
forbidden, whatever words it uses. Three constraints:

- No wording that lowers attention on a hunk. "You can skip", "this part is mechanical", and "no
  need to look at" are examples of the pattern — **not an exhaustive list**. "Low signal",
  "boilerplate", or any other phrasing with the same effect is equally forbidden, however it is
  worded; satisfying the three quoted phrases proves nothing on its own.
- The risk list **may not be empty**. If no hunk in the change can be named as the risky one, that
  is a finding — not a clean bill of health.
- The risk list is **not authored freehand**. Derive it from passes 2–5b's findings, *including the
  ones dispositioned `ACCEPTED`*. An accepted deferral becomes an explicit review target instead of
  a quietly buried one.

#### The repo's PR template wins

Before composing anything, look for one:

```bash
ls .github/pull_request_template.md \
   .github/PULL_REQUEST_TEMPLATE.md \
   .github/PULL_REQUEST_TEMPLATE/*.md \
   docs/pull_request_template.md \
   .gitlab/merge_request_templates/*.md 2>/dev/null
```

If one exists it defines the structure, and this pass fills it in:

- **Never** delete, rename, or reorder the template's headings.
- Where a template heading already covers one of the obligations below, fill it **there** instead
  of adding a parallel heading. `## Description` gets the *why*; `## Testing` or `## Review Focus`
  gets the verification and risk content.
- Only obligations with no home in the template get appended, as new sections at the end.
- Leave no template section blank. If one genuinely does not apply, write `N/A — <reason>` rather
  than deleting it.

This is *Decisions* applied to the PR body: defer to team conventions first. A sweep that replaced
a team's template with its own structure would be a convention violation dressed up as
thoroughness.

#### Assembled body

The default shape when the repo has **no** template. With a template present, these are
**obligations to place**, not headings to emit.

| Section | Fed by |
|---|---|
| `## Why` / `## Stack` / `## What's next` | this pass |
| `## How to review` | this pass; risk list derived from passes 2–5b |
| `## Deferred` | pass 1 dispositions |
| `## Verification caveats` | pass 6 |

**Why this pass keeps its context**, when 2–5b are blinded: articulating intent *is* the task here,
so it needs the brief, the ticket, and the stack plan. The blind passes judge the code; this one
explains it. Neither gets to do the other's job — if that boundary blurs, the blinding stops being
worth anything.

## Context-blind sub-agents

Passes 2–5b each spawn a `general-purpose` sub-agent. A fresh context — not a fork.

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
not rationale, so this flow does not reintroduce that bias. No other **sub-agent** pass receives
another pass's output — this is the only permitted cross-pass flow among the blind passes. Pass 7
later reads all of 2–5b's findings by design, but it runs in the main context and was never blind
to begin with, so it sits outside this rule rather than violating it.

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
**An incomplete pass forces the verdict to `Not ready`.** Reporting "pass N did not complete" and
still returning `Ready for review` is the exact silent-empty failure this design exists to close —
a dead pass is a blocking finding in its own right, not a pass with nothing to say.

**Reconcile the ledger after, never before.** A blind agent will re-flag something already marked
`ACCEPTED`. That is correct behaviour. Handing it the ledger up front to prevent the duplicate
would bias the finding itself — prior acceptance is triage input, not review input. Report those as:

```
re-flagged, previously accepted 2026-08-14: <rationale>
```

which is also how an acceptance that has quietly gone stale becomes visible.

## Finishing

Determine the verdict first: **`Ready for review`** — every pass completed and produced no
blocking findings — or **`Not ready`** plus the blocking findings. Each finding carries
`file:line`, the failure scenario, and a proposed fix.

**Only a `Ready for review` verdict writes the marker.** A `Not ready` sweep must not write it —
writing it would silence the tripwire on a HEAD that has not actually passed, and `gh pr create`
would proceed without a word on the very commit the sweep just rejected. If the verdict is
`Not ready`, stop here; report the findings and skip the block below.

Record the sweep so the tripwire stays quiet until the next commit:

```bash
mkdir -p "$(git rev-parse --git-dir)/software-engineering"
git rev-parse HEAD > "$(git rev-parse --git-dir)/software-engineering/last-sweep"
```
