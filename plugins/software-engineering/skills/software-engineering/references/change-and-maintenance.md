# Change and maintenance

## Performance

**Rule:** Optimize for maintainability first. Gauge the actual need for performance from context. Instrument to learn when performance matters. Well-tested library upgrades are cheap; significant maintenance burden defers the optimization. Case-by-case.

**Why:** Premature optimization burns reading time forever to save execution time you may never need. The cost of clear code is paid once (writing it); the cost of obscure-but-fast code is paid every time someone reads it. Measure before optimizing. Instrument to know when measurement starts to matter.

**How to apply:**
- Write the clearest implementation first.
- Add metrics (RED/USE/Apdex/p99) that would tell you if performance becomes an issue.
- Watch the metrics. Optimize when they show a real problem.
- If the optimization is "use a well-tested library" — pay the cost, low risk.
- If the optimization is "rewrite this in a clever way" — only after measurement says it matters.

**Red flags:**
- "This might be slow at scale" without a defined scale.
- Optimization commits with no benchmark before/after.
- Obscure code with a comment "for performance".

---

## Legacy code

**Rule:** "Make the change easy, then make the easy change" (Kent Beck). Prefer refactor-first for non-trivial work. Use tactics to manage scope (strangler fig, seam introduction, boundary clarification). Before refactoring untested legacy, invest in ~80% coverage first to hedge against regressions; THEN refactor; THEN add the feature.

**Why:** Squeezing a feature into a tangled module makes the tangle worse and costs more on every subsequent change. Refactoring first costs upfront but compounds positively. Without tests, you can't refactor safely — coverage is what makes the refactor a non-event.

**Refactor signal: mental-model loss.** When you find yourself unable to remember where a piece of logic lives, or unable to predict how a change will ripple, in code you're actively modifying — that's a strong signal to refactor. Not because the code is "bad," but because it has outgrown what fits in a developer's head. Mental-model loss precedes the bugs that come from confidently editing code you no longer understand. ~10k LOC per maintainer is a practical ceiling for what one human can hold; above that, structure and firewalls have to do the remembering.

**How to apply:**
1. Identify the seams you need (where will the new feature interact with existing code?).
2. Cover those seams with tests until you're confident a refactor won't break them (~80%).
3. Refactor — introduce the interface, extract the class, untangle the responsibilities. No behavior change.
4. Add the feature against the clean shape.
5. Each step is its own PR or its own commit.

**Red flags:**
- Tangled module + new feature in one PR.
- "I'll add tests after the refactor" — the refactor is unsafe without them.
- Refactor PR that also changes behavior (mixed signal; un-revertable).

**Example flow:**
```
PR 1: tests covering current OrderService behavior (+0 behavior change)
PR 2: extract OrderRepository interface, no behavior change
PR 3: add new payment flow against the new shape
```

---

## Dependencies and supply chain

**Rule:** Stdlib first. For small, simple needs, build a shared internal component on top of stdlib. For non-trivial needs, use well-maintained community libraries. Have tooling for automated dependency upgrades. Follow framework-specific official extension patterns where the ecosystem provides them. Team/company convention is the deciding factor. Minimize 3rd-party surface to minimize supply-chain risk.

**Why:** Every dependency is a long-term liability: transitive risk, breaking changes, abandoned upstreams, supply-chain attacks (typosquats, malicious updates). Stdlib is forever; small internal helpers are yours to control; community libs that pass the bar (active maintenance, good test coverage, sane release cadence) earn their place.

**How to apply:**
- Before adding a dep, search stdlib. Then check if your team has an internal helper.
- If you must add: audit. Last commit recent? Tests? License compatible? Maintainer reputation? Transitive deps?
- Configure dependabot / renovate / equivalent. Stay current on patches.
- For frameworks with official extension points (Spring Boot starters, Django apps), prefer the official path.

**Red flags:**
- Adding a 10-line library to save writing 10 lines.
- Adopting a library that hasn't released in two years.
- A dependency tree where you can't name what most of the transitive deps do.
