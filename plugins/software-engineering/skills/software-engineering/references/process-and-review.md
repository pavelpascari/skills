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
