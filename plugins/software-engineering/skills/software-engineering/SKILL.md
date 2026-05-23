---
name: software-engineering
description: >
  Use during coding work: implementing features, fixing bugs, refactoring, reviewing
  code, designing APIs, writing tests, building services. Encodes 19 principles
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

## Code design

→ See `references/code-design.md` for details.

- **Boundary validation** — public APIs validate; internal callers are trusted.
- **Semantic DRY** — extract only when intent matches, not when shapes look alike.
- **Internal coupling** — default to ports and adapters; inner modules must not depend on outer modules.
- **API design** — minimal composable primitives; extension points are demand-driven.
- **Code structure** — vertical slices outside, hexagonal inside; IO-less core; deep modules with strong APIs.

## Naming and language

→ See `references/naming-and-language.md` for details.

- **Ubiquitous language** — domain layer speaks the agreed-upon business language; mapping layer bridges to legacy storage names.
- **Comments** — docstrings on public APIs; internal code only when WHY is non-obvious.

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

## Change and maintenance

→ See `references/change-and-maintenance.md` for details.

- **Performance** — maintainability first; instrument to learn when to optimize.
- **Legacy code** — make the change easy, then make the easy change; tests first, refactor, then feature.
- **Dependencies and supply chain** — stdlib first; automated upgrade tooling; minimize 3rd-party surface.

## Observability

→ See `references/observability.md` for details.

- **Context-driven instrumentation** — instrument what you would want at 3am during an incident.
- **Compose, don't inject** — prefer `TracedCachedClient` over injecting a tracer into the core API.
