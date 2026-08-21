# Comments

Comments are the only part of a change that nothing verifies. Every other claim in a diff is checked
by a compiler, a linter, or a test; this one is checked by a reader noticing. That is why comments
rot silently, why the rot survives review, and why they need a discipline of their own.

**Treat comments as code.** They are written, reviewed, maintained, and deleted on the same terms.
The bar for keeping one is the bar for adding it today — a comment surviving because deleting it
felt presumptuous is noise with tenure.

**Optimise for the reader a year out**, not for yourself today. You have the whole change in your
head right now, which makes you the worst possible judge of what needs explaining. The reader who
matters arrives after the context is gone, and often after the code around the comment has moved.

## The four questions

Ask them when writing, and again when reviewing. They are the same questions; only the tense
changes.

**1. Will this still pay in a year?**
Not "is it true now" — will it still be worth its reading cost once the surrounding code has been
refactored twice by people who never met you.

**2. Is it prone to going out of sync?**
The one that most changes how you *write*, not just what you keep. Prefer formulations that cannot
rot:

```kotlin
// Rots: names the mechanism, dies when either half moves.
// We chunk by 200 here, then send each batch in the loop below.

// Durable: names an external constraint, survives any refactor of how we chunk.
// Upstream rate-limits above 200 items per call.
```

A comment about *why* usually outlives a comment about *how*, because reasons change more slowly
than mechanics. That is the real content of "why not what" — not a ban on describing behaviour.

**3. Is reading it the same as reading the code?**
Then it is noise, however it is phrased. A comment earns its place by operating at a **different
level of abstraction, in different words**. Restating the line in prose is redundant whether you
frame it as a what or a why.

This is why "never comment WHAT" is wrong as a rule: `Returns null when the account is soft-deleted`
is a *what*, and it is the most valuable line in the file — because a caller cannot see it without
reading the body. The test is redundancy and level, not the grammatical mood.

**4. Does this belong here at all?**
Some explanations have a better home: a doc link, an ADR, the commit message, the type system. A
comment is the right container only when nothing else holds it.

## Never re-document what someone else maintains

Explaining how a framework, library, or protocol works — inline, in your own words — is the
fastest-rotting comment there is. The upstream documentation has a maintainer and a release
schedule. Your paraphrase has neither, and it goes false on *their* timetable, not yours.

**Link, do not paraphrase.** And because links rot too, name the concept as well as linking it, so
the reader can still find it when the URL dies:

```kotlin
// Bad — a paraphrase of someone else's docs, false the moment they change it.
// Spring creates one instance of this bean and shares it across all threads, so
// any field you add here is shared mutable state across every request...

// Good — names the concept, links the source, states only what is local.
// Singleton scope (Spring bean scopes: https://docs.spring.io/…/beans-factory-scopes.html),
// so this must stay stateless — `lastResult` was a field here until INC-1142.
```

Keep the part that is *yours*: what this constraint means for this code, and what went wrong when it
was violated. That is the half no upstream doc will ever contain.

## The seven kinds

Comments are not one thing. Each kind has its own write rule and its own review test.

### 1. API contract — a docstring, KDoc, rustdoc, YARD block

**Write:** what a caller must know without reading the body — inputs, return, failure modes, units,
invariants, nullability. Phrase it so it stays true under reimplementation.
**Review:** does it state the contract, or restate the signature? `Returns the user's name` on
`fun userName(): String` is the latter.
**Fails as:** documentation-shaped noise, which is worse than none because it looks like the contract
has been specified.

### 2. Why / hidden constraint

**Write:** the reason that cannot be recovered from the code — a rate limit, an ordering requirement,
a workaround with its cause, a deliberate inefficiency. Name the external fact, not the local
mechanism.
**Review:** could a competent reader have inferred this? If yes, delete. If they could only infer it
by reading three other files, keep.
**Fails as:** an explanation of code that should have been renamed or extracted instead — the comment
is compensating for a name doing too little.

### 3. Landmine warning

**Write:** the coupling that is load-bearing and invisible. "These two calls must stay in this order;
`flush` reads state `close` clears."
**Review:** is the hazard specific and checkable? "Be careful here" warns nobody of anything.
**Fails as:** vague caution that survives forever because no one can tell whether it still applies.

### 4. TODO / FIXME

**Write:** an owner and a trigger condition, or do not write it. "TODO(pavel): drop once the v2
endpoint ships — tracked in ATF-1942."
**Review:** does it name who and when? An unowned TODO is a wish, and it will outlive the person who
wrote it.
**Fails as:** litter that accumulates until the whole class is ignored, taking the real ones with it.

### 5. Banner / section marker

**Write:** almost never. A `// ---- validation ----` divider inside a function is a signal that the
function wants splitting.
**Review:** treat it as a design smell rather than a comment problem — the fix is usually an extracted
function whose name says what the banner said.
**Fails as:** structure imposed by formatting rather than by code.

### 6. Commented-out code

**Write:** never. Version control has it, with the author, date, and message your commented block
lacks.
**Review:** delete on sight. "We might need it" is answered by `git log`.
**Fails as:** ambiguity — the next reader cannot tell whether it is a plan, a rollback, or an
accident.

### 7. Framework explainer

**Write:** do not. See *never re-document what someone else maintains* above — link, name the
concept, and keep only the local consequence.
**Review:** if the comment would be equally true in any other codebase using that framework, it
belongs in a link.
**Fails as:** a paraphrase that goes stale on someone else's release schedule, with no one watching.

## Judging a comment in review

Every comment gets exactly one of three verdicts, ranked by what it costs to leave in place:

- **liability** — it will rot and misdirect, or already has. The code moved and the comment did not.
- **noise** — cost with no benefit. Recoverable from the code; delete it, or rename so it is.
- **keep** — durable value a reader could not reconstruct.

The ranking is the point. Noise costs a reader seconds. **A comment that has drifted is a lie**, and
it actively sends the reader where the code does not go — worse than no comment, because a reader
with none would have read the code. This is *code must never lie*, with the comment as its subject.

**Where drift hides — and why "review the comments in the diff" misses it.** A comment goes stale
precisely *because* the code moved and the comment did not, so **the stale comment is usually not in
the diff.** It sits unchanged beside changed code. Reviewing only changed comment lines catches the
rewrites and misses every genuine drift.

So: read every comment in a changed hunk **and its enclosing function or block**, including comments
the diff never touched, and ask of each — does this still describe what the code now does?

**Red flags:**
- A comment describing a fallback, branch, or parameter the diff removed.
- A comment restating a signature, mistaken for documentation because it is formatted as a docstring.
- "As above", "see below", or a reference to a line number — all break silently on any edit.
- A comment that must be updated whenever a nearby constant changes. Derive it, or drop it.
- An explanation of how a framework behaves, written in this repo's own words.
- A reviewer approving a diff whose comments were never read as part of the review.

**Example:**
```kotlin
// Liability — the fallback it describes was deleted two commits ago. Worse than
// nothing: it sends the next reader looking for behaviour that is not there.
// Falls back to the cached value when the upstream call fails.
val rate = upstream.fetchRate()

// Noise — recoverable from the code. Delete, or rename `p` and `q` if that was
// the real problem.
// Multiply price by quantity.
val total = p * q

// Keep — an external constraint, phrased so no local refactor can falsify it.
// Upstream rate-limits above 200 items per call; chunking here rather than at the
// caller because the caller's page size is user-configurable.
items.chunked(200).forEach(upstream::send)
```

**In the sweep:** `pre-pr-sweep`'s Pass 5b applies these three verdicts to a whole-branch diff as a
context-blind pass. That pass reports a verdict; this file is how you reach one. Keep them
complementary — do not collapse the taxonomy into the pass, which has to stay small enough to run.

**Notes by language** — doc-comment conventions differ; load only the file for the language you are
working in: `references/languages/{go,typescript,python,kotlin-java,rust,ruby}.md`.
