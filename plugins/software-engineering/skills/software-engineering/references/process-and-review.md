# Process and review

## Definition of done

**Rule:** Done means: code works, ≥80% test coverage on changed code, manually verified end-to-end, no regressions in adjacent features, optimized for the reviewer's cognitive experience, and the surrounding artifacts (tests, docs, handover rituals, conventions) are clean.

**Why:** "Tests green" is a property of the code; "done" is a property of the change as it lands in the world. A change is done when the next person — reviewer, on-call engineer, future you — has everything they need to operate it. Skipping pieces of done leaves debt that someone else pays.

**How to apply:** Before marking a task done, run the checklist below. If any item is unmet, finish it or explicitly call it out (with rationale) for the reviewer.

**Definition-of-done checklist:**
- [ ] Code compiles / type-checks.
- [ ] All tests pass locally (new and existing).
- [ ] ≥80% test coverage on the changed code (project's coverage tool).
- [ ] Manually exercised the actual feature path (endpoint hit, UI used, CLI run).
- [ ] Adjacent features checked for regressions.
- [ ] PR description tells the reviewer what changed, why, and how to verify.
- [ ] Commits are curated into a reviewable story.
- [ ] Docs / runbooks updated if behavior, ops, or contracts changed.
- [ ] No drive-by changes hiding in the diff.

**Red flags:**
- "Tests pass" being the only evidence offered.
- A PR with one giant commit "implement feature".
- A PR that touches files unrelated to the stated goal.

---

## Scope discipline

**Rule:** Opportunistic cleanup is OK if the PR stays small (~200-300 LOC). For larger changes, split into stacked PRs with discrete, reviewable commits. Every PR must stand on its own — independently mergeable and deployable. Optimize for the reviewer's cognitive experience.

**Why:** Big PRs are hard to review, hard to revert, and hide regressions. Stacked PRs let you ship in shippable steps: each PR is small enough to review carefully, and each can be deployed without waiting for the rest. The reviewer's time is the constraint — small, well-organized PRs are the highest-leverage thing you can do for the team.

**How to apply:**
- Estimate PR size before opening: lines changed, files touched, conceptual units.
- If it busts ~300 LOC, decompose into stacked PRs (each branch off the previous).
- Each PR has one stated purpose; commits inside the PR are reviewable steps toward that purpose.
- Drive-by fixes go in their own commit (or their own PR if they grow).

**Red flags:**
- PRs labeled "refactor + feature + bug fix + cleanup".
- PRs with reviewers asking "can you split this?".
- PRs that touch shared modules with changes unrelated to the stated goal.

---

## Commits and PRs

**Rule:** Never merge directly to main; always a PR. Curate WIP commits into a small number of meaningful, reviewable changesets. Each commit compiles and tests pass. Target ~200-300 LOC per PR; mechanical changes can be larger if well-tested. Each PR stands on its own.

**Why:** A clean commit history is the cheapest documentation you can produce. `git log` and `git blame` answer "what changed, when, and why" — only if the commits are coherent. WIP commits like `wip`, `fix typo`, `revert previous` waste the reviewer's time and pollute the history.

**How to apply:**
- Work locally with whatever WIP cadence you like; curate before pushing.
- Use `git rebase -i` to combine, reorder, and rewrite commits into a story.
- Each commit message: imperative present-tense subject ("add", "fix", "refactor"); body explains *why*, not *what*.
- Stacked PRs: each branch builds on the previous; each PR is rebased onto its parent before review.

**Red flags:**
- Commits named "fix", "WIP", "more", "asdf".
- Commit messages that restate the diff.
- A merge to main without a PR.

---

## Decisions

**Rule:** Defer to team conventions first; most "decisions" are already answered by guidelines. For genuine tradeoffs not covered by conventions, make a call AND surface it explicitly to the reviewer ("I assumed X; let me know if you'd want Y"). Explicit collaboration, not silent autonomy.

**Why:** A decision made silently inside a PR is invisible — the reviewer either approves it without realizing they did or pushes back after the fact. Surfacing the decision turns an ambiguity into a checkpoint: the reviewer can approve or redirect with full context, and the team accumulates explicit precedents instead of accidental ones.

**How to apply:**
- First, check conventions (style guide, ADRs, prior PRs in the area).
- For genuine tradeoffs, pick the option that best fits the spirit of existing conventions and call it out in the PR description: "I picked X over Y because Z; happy to flip."
- For irreversible decisions (DB schema, public API), prefer asking before deciding.

**Red flags:**
- PR description says "implements the feature" with no commentary on the tradeoffs.
- Tradeoffs only become visible during code review when the reviewer notices the choice.
- Conventions exist that would have answered the question, but weren't consulted.

---

## Make it correct, make it clear, make it concise, make it fast — in that order

**Rule:** Four priorities, sequenced. **Correct** first: the code must behave as required. **Clear** next: a reader must understand it. **Concise** next: only the code that earns its place stays. **Fast** last: optimize only the parts that need it, with measurement. Do not skip the order.

**Why:** Reordering corrupts the result. Optimizing for speed before correctness produces fast wrong code. Optimizing for conciseness before clarity produces clever code no one can maintain. Optimizing for clarity before correctness produces well-named bugs. The sequence keeps each concern from poisoning the one before it.

**How to apply:**
- First pass: get it working against tests. Don't pre-polish.
- Second pass: rename, restructure, split until the code reads on its own.
- Third pass: delete what isn't needed. Compress what is.
- Fourth pass (only if profiling shows a real problem): optimize the specific bottleneck.

**Red flags:**
- A PR that introduces both a feature and a clever performance trick — likely skipping the order.
- "Premature optimization" dressed up as elegance.
- Code that is clear and fast but has subtle correctness bugs.

**Credit:** "Make it correct, make it clear, make it concise, make it fast. In that order." — Wes Dyer.

---

## Prototype before production

**Rule:** For non-trivial new ideas, prototype in the concrete before designing contracts. Validate the approach with throwaway code, then decide on shape, interfaces, and boundaries.

**Why:** Design-up-front of a thing you don't fully understand produces over-fitted abstractions. The prototype exposes the real shape — what data flows where, where the contention lives, what the API actually needs to be — and the production design is informed by reality rather than guesses. The prototype is also the cheapest place to discover that the idea won't work at all.

**How to apply:**
- For a new feature with unknowns: spike first. Write the simplest end-to-end version that proves the idea, with whatever shortcuts get you there.
- Throw away (or keep, but be honest about quality) the prototype. The production version is fresh code informed by the lessons.
- Prototypes are NOT a license to skip TDD on the production version — they precede it.
- Time-box prototypes. A prototype that takes a month is a project; either cap it or plan it as one.

**Red flags:**
- A "prototype" that quietly turned into production code without the corresponding hardening.
- A "design" document for a feature where no one has yet built any of it.
- A new abstraction layer introduced before any concrete caller exists.

**Example workflow:**
```
1. Spike: scratch directory, throwaway code, prove the integration end-to-end (1-3 days).
2. Document what you learned (data shape, edge cases, performance characteristics).
3. Write the failing test for the production version.
4. Build the production version with TDD, informed by step 2.
```

**Credit:** Robert Griesemer's *Prototype your design!*, surfaced in Bill Kennedy's *Design Guidelines*.

---

## Rules have costs — every rule must pull its weight

**Rule:** Every rule, convention, lint check, or pattern you adopt has a cost — reading load, training load, exception-handling load. Before adopting a rule, identify what problem it solves; before keeping it, verify it still solves that problem.

**Why:** Rules accumulate. Teams adopt conventions for good reasons, then the reasons change, but the rules stay. The codebase ends up encoding history rather than current intent. Each rule reads like signal but functions as noise. Auditing rules — keeping the ones that still earn their weight, removing the ones that don't — is part of design discipline.

**How to apply:**
- When introducing a rule (style, lint, convention): write down the specific problem it solves and the cost of the alternative. If you can't, don't introduce it yet.
- When inheriting a rule: ask "what is this preventing?" If no one knows, the rule is a candidate for removal.
- "Be consistent" is not a sufficient reason. Consistency with a bad rule propagates the problem.
- Rules and conventions are themselves code — review and revise them with the same rigor.

**Red flags:**
- A linter rule with so many exceptions that the exceptions are the rule.
- "We always do it this way" without anyone able to articulate why.
- A style guide longer than the team's onboarding doc.
- A convention applied to code where it doesn't make sense, justified only by "consistency."

**Credit:** Michael Feathers ("An architecture isn't a set of pieces, it's a set of rules about what you can expect of them"), surfaced in Bill Kennedy's *Design Guidelines*.
