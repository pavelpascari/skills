---
name: software-engineering
description: >
  Use during coding work: implementing features, fixing bugs, refactoring, reviewing
  code, designing APIs, writing tests, building services. Encodes 23 principles
  covering code design, testing, errors, review process, maintenance, and observability.
user-invocable: true
---

# Software Engineering Principles

A coherent set of principles to apply during software engineering work. The philosophy is integrated, not a checklist: the principles reinforce each other. Treat them as design discipline, not bureaucracy.

**Core philosophy:** Design for clarity, maintainability, and the reviewer's cognitive experience. Tests are a design tool. Make the change easy, then make the easy change. Compose, don't inject.

## How to use this skill

Skim the groups below to find the principle that matches what you're about to do. Drill into the relevant reference file for rule / why / how to apply / red flags / example.

## Non-negotiable rules

These apply always. If you find yourself about to violate one, stop and reconsider.

1. **TDD is imperative.** Write the failing test first, always. See `references/testing.md`.
2. **Bug fix = reproduce-then-fix.** Every bug fix begins with a failing test that demonstrates the bug. See `references/testing.md`.
3. **Never merge to main without a PR.** All changes go through review. See `references/process-and-review.md`.
4. **Definition of done is a chain, not a checkbox.** See `references/process-and-review.md`.
5. **A written deferral goes on the ledger.** When a review step's own output records a judgement —
   "out of scope", "not blocking", "worth flagging but inherited" — append it to
   `docs/deferred-review-flags.md` before moving on; the rule is checkable against that written
   judgement, not against what someone privately noticed. The ledger is a convenience, not the
   guarantee — the pre-review sweep's failure-mode pass re-derives from the diff every time,
   and that is what actually guarantees coverage. See `references/process-and-review.md`.

## Code design

→ See `references/code-design.md` for details.

- **Boundary validation** — public APIs validate; internal callers are trusted.
- **Semantic DRY** — extract only when intent matches, not when shapes look alike; every line is a bug surface.
- **Internal coupling** — discover interfaces, don't design them; inner modules must not depend on outer modules.
- **API design** — minimal composable primitives; extension points are demand-driven.
- **Code structure** — three firewalls (packaging, layering, domains); four layers (API / App / Business / Storage); each layer owns its types.

## Naming and language

→ See `references/naming-and-language.md` for details.

- **Ubiquitous language** — domain layer speaks the agreed-upon business language; mapping layer bridges to legacy storage names.
- **Code must never lie** — names, comments, tests, logs, and errors must accurately reflect what is actually happening.

## Comments

→ See `references/comments.md` for details.

- **Comments are code** — written, reviewed, maintained, and deleted on the same terms. If one does not add value, it is noise; remove it.
- **Optimise for the reader a year out** — four questions decide whether a comment earns its place: will it still pay in a year, is it prone to going out of sync, is reading it the same as reading the code, and does it belong here at all.
- **Write for durability** — prefer formulations that cannot rot. An external constraint outlives a description of the local mechanism.
- **Never re-document what someone else maintains** — link to the framework's docs and name the concept; keep only the local consequence.
- **Seven kinds, seven rules** — API contract, why/constraint, landmine, TODO, banner, commented-out code, framework explainer.
- **Three verdicts in review** — liability (it will rot and misdirect), noise (delete), keep.

## Testing

→ See `references/testing.md` for details.

- **TDD is imperative.**
- **Test pyramid + DI + stubs over mocks + testcontainers** for real integration.
- **Bug fix = reproduce-then-fix.**

## Errors

→ See `references/errors.md` for details.

- **Layered error handling** — propagate with context internally; the public API layer decides presentation.

## Process and review

→ See `references/process-and-review.md` for details.

- **Definition of done** — works + ≥80% coverage on changes + manually verified + no regressions + reviewer-optimized.
- **Scope discipline** — opportunistic cleanup OK if PR stays small; otherwise stacked PRs with discrete reviewable commits.
- **Commits and PRs** — always a PR; ~200-300 LOC target; each PR stands on its own; large changes → stacked PRs.
- **Decisions** — defer to team conventions first; surface tradeoffs explicitly.
- **Make it correct → clear → concise → fast** — four priorities, sequenced; do not reorder.
- **Prototype before production** — for non-trivial new ideas, validate with throwaway code before designing contracts.
- **Rules have costs** — every rule, convention, or lint check must pull its weight; audit them.
- **Pre-review sweep** — before asking a human to review, run the `pre-pr-sweep` skill: failure
  containment, config guards, failure-path tests, ledger drained, PR narrative written.

## Change and maintenance

→ See `references/change-and-maintenance.md` for details.

- **Performance** — maintainability first; instrument to learn when to optimize.
- **Legacy code** — make the change easy, then make the easy change; tests first, refactor, then feature.
- **Dependencies and supply chain** — stdlib first; automated upgrade tooling; minimize 3rd-party surface.

## Observability

→ See `references/observability.md` for details.

- **Context-driven instrumentation** — instrument what you would want at 3am during an incident.
- **Compose, don't inject** — prefer `TracedCachedClient` over injecting a tracer into the core API.
