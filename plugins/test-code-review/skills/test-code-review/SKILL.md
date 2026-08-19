---
name: test-code-review
description: >
  Use when test files are written or modified, or user asks to "review tests" or "check test changes".
  Catches weakened assertions, missing coverage, and tests rewritten to match buggy behavior.
user-invocable: true
---

# Test Code Review

You are reviewing test code changes. Your job is to catch problems that green tests hide — weakened assertions, missing coverage, tests that pass for the wrong reason, and test changes that paper over bugs instead of catching them.

## Why this matters

One of the most dangerous patterns in software development is when tests fail against new code and the developer rewrites the tests to match, rather than questioning the implementation. The tests were right — they were catching a bug. But the signal was interpreted as "tests need updating" instead of "the code is wrong." This happens more frequently in agentic coding loops where an AI agent confidently rewrites tests with plausible explanations.

## How to review

### Step 1: Identify what changed

Determine what test files were modified and what implementation files changed alongside them. Use `git diff` (staged + unstaged) or `git diff HEAD~1` depending on context. Separate the changes into:

- **New test files** — tests written from scratch
- **Modified test files** — existing tests that were changed
- **Implementation files** — the production code that changed

Understanding the implementation change is essential context for evaluating whether test changes are correct.

### Step 2: Analyze modified tests (highest priority)

For each modified test, answer these questions:

**Are the assertion changes justified by the implementation change?**
- If a test previously asserted `expect(result).toBe(5)` and now asserts `expect(result).toBe(3)`, is that because the correct behavior genuinely changed, or because the implementation has a bug?
- Read the implementation diff to verify.

**Are assertions being weakened?**
Look for these red-flag patterns:
- Counts decreasing: `expected 2 rebases` → `expected 0 rebases`
- Specific assertions becoming general: `expect(x).toBe(5)` → `expect(x).toBeTruthy()`
- Error expectations removed: a test that expected an error no longer does
- Assertions deleted entirely without replacement
- `toEqual` becoming `toContain` or `toMatch` (less precise matching)
- Expected exceptions/panics removed

When you see weakened assertions, flag them explicitly. Explain what the test was checking before, what it checks now, and ask whether the old behavior was actually wrong.

**Are test comments being rewritten to rationalize new behavior?**
If a comment changes from describing one behavior to describing a different (weaker) behavior, that's a signal the test was rewritten to match buggy code. The comment rewrite makes it look intentional when it might not be.

**Is the test still testing what it claims to test?**
Sometimes a test's name says "test cascade propagation" but after modification it no longer tests cascading — it just checks that nothing happens. The name becomes misleading.

### Step 3: Analyze new tests

For new tests added alongside a bug fix:

**Does the test actually reproduce the bug?**
- Would this test have failed before the fix? If you can determine this from the diff, state it.
- A test that passes both before and after the fix isn't testing the fix.

**Does the test cover the right boundary?**
- Bug fixes often need tests at the exact boundary where the bug occurred, not just a happy-path test nearby.

For new tests added alongside a feature:

**Are edge cases covered?**
- Empty inputs, nil/null values, boundary conditions
- Error paths, not just success paths
- Concurrent access if applicable

**Are the assertions specific enough?**
- Tests that only check "no error returned" without verifying the actual result are weak.
- Tests should assert on observable behavior, not implementation details.

### Step 4: Check for missing tests

Look at the implementation diff and ask:
- Are there code paths with no test coverage?
- Are there error handling branches that aren't tested?
- If the implementation has a fast path and a slow path, are both tested?
- If there's a conditional (if/else, switch), does each branch have a test?

### Step 4b: Failure-path coverage

Step 4 asks which branches lack coverage. This step is narrower and catches what percentage-based
coverage cannot: **for every error-handling construct in the implementation diff — `catch` /
`rescue` / `except`, error returns, fallback defaults, retries — is there a test that *forces* that
failure?**

A path can be 100% covered and never once exercised as a failure. Coverage counts lines executed,
not failures triggered.

If you were given a list of enumerated failure modes (the caller may pass one), check coverage
against that list rather than hunting the diff blind.

**Assertion strength.** An assertion that would still pass under a plausible regression is not
coverage:

```kotlin
// Weak: survives a 60x TTL cut. Duration.ofHours(12).toMinutes() is 720, and 720 > 0.
assertThat(ttl).isGreaterThan(0L)

// Strong: pins the actual value.
assertThat(ttl).isCloseTo(EXPECTED_TTL_SECONDS, within(5L))
```

The same shape recurs as `assertNotNull` where the value matters, `hasSizeGreaterThan(0)` where the
count matters, and "no exception thrown" where the result matters.

**Verify the test by breaking the code.** When you cannot tell whether an assertion is real, make
the obvious wrong change to the implementation, run the test, and confirm it fails. Then revert.

```
1. Change Duration.ofHours(ttlHours).toSeconds() to .toMinutes()
2. Run the test — it must fail
3. Revert
```

A test that still passes against deliberately broken code is not protecting anything, and the fact
it was green told you nothing. Report it as a finding.

**Boundary pairs for guards.** A new validation guard needs two tests, not one: rejection just
outside the legal range, and acceptance at the smallest legal value. Only the second catches a
guard written `> 1` when it meant `> 0`.

### Step 5: Check test setup correctness

- Do test fixtures/helpers create realistic scenarios, or do they accidentally create scenarios where the bug can't manifest?
- Are mocks/stubs matching the real interface? A mock that returns the "right" answer regardless of input can mask bugs.

## Output format

Structure your review as:

```
## Test Review: [brief summary]

### Weakened Assertions (if any)
For each weakened assertion:
- **File:line** — what changed, what it used to assert, why this is suspicious
- Recommendation: revert the assertion / keep with justification / rewrite differently

### Missing Coverage (if any)
- Code paths in the implementation diff that lack test coverage
- Specific test cases to add

### Failure-Path Coverage (if any)
Error-handling and failure-path gaps belong here, not under Missing Coverage, New Test Quality, or Weakened Assertions, even where those buckets' general wording could also apply. An untested `catch`/`rescue`/`except` block, error return, fallback default, or retry is always a Failure-Path Coverage finding — and so is any assertion on one of these paths that is too weak to prove the failure fired, whether that assertion was just written or was weakened by this diff. For each failure path that lacks a forcing test, or whose only test carries an assertion too weak to prove the failure was actually triggered:
- **File:line** — the failure path, what test (if any) touches it, and why the coverage is insufficient
- Recommendation: add a test that forces the failure and asserts on the actual outcome / strengthen the existing assertion so it fails when the failure-handling logic breaks

### New Test Quality (if any)
- Whether new tests would catch the bug they claim to test
- Assertion specificity issues

### Misleading Test Narrative (if any)
Findings from Step 2 about what a test *says* versus what it *does* — a comment rewritten to
describe weaker behavior, a test name that no longer matches its assertions, a docstring
rationalizing a behavior change. These are not assertion changes, so they do not belong under
Weakened Assertions; the assertion may be untouched while the prose around it now lies.
- **File:line** — what the name or comment claims, what the test actually exercises now
- Recommendation: restore the original behavior / rename the test to what it really checks

### Test Setup Fidelity (if any)
Findings from Step 5 about the scenario a test constructs — a fixture that accidentally makes the
bug unreproducible, a stub returning the right answer regardless of input, a mock whose signature
has drifted from the real collaborator. The assertions may be perfectly strong; the setup means
they never had a chance to fail.
- **File:line** — what the fixture or double does, and which real condition it fails to reproduce
- Recommendation: the specific setup change that would let the test fail when the code is wrong

### Verdict
One of:
- **Looks good** — tests are correct and comprehensive, with no unresolved findings above
- **Needs attention** — specific issues listed above should be addressed
- **Suspicious** — test changes may be papering over a bug; implementation should be re-examined
```

## When to apply fixes directly

If you find issues, fix them rather than just reporting:
- Revert weakened assertions to their original form (unless the implementation change genuinely warrants the change)
- Add missing test cases for uncovered code paths
- Strengthen vague assertions to be specific
- Fix misleading test names or comments

After applying fixes, run the tests. If they fail, that's valuable information — it means the tests are catching something the implementation gets wrong. Report this to the user rather than weakening the tests to make them pass.

## Language-specific patterns

### Go
- Test functions: `func Test*(t *testing.T)`
- Files: `*_test.go`
- Watch for: `t.Skip()` added without justification, `t.Fatal` → `t.Error` (stops failing the test immediately), error returns not checked

### TypeScript/JavaScript
- Files: `*.test.ts`, `*.spec.ts`, `*.test.js`, `*.spec.js`
- Watch for: `.skip` added to test cases, `expect` calls removed, `.toEqual` → `.toMatchObject` (allows extra fields)

### Python
- Files: `test_*.py`, `*_test.py`
- Watch for: `@pytest.mark.skip` added, `assertEqual` → `assertIn` (less precise), exception tests removed
- `pytest.raises(ValueError)` without `match=` passes on *any* `ValueError`, including one raised by the setup before the code under test runs. Adding `match=` is what proves the intended path failed.
- **`assert mock.some_method()` always passes.** A `Mock`/`MagicMock` returns a truthy `Mock` for any call or attribute, so a bare-truthiness assertion on one is vacuous — and so is a typo'd attribute (`mock.reslut` invents an attribute rather than raising). `assert x.called` has the same problem: `Mock` also answers `.called_once` truthily, which is not a real API. Use `assert_called_once_with(...)`, or `spec=`/`autospec=True` so a typo raises.
- `assertAlmostEqual(a, b)` defaults to 7 decimal places — fine for floats, far too loose when the values are seconds or money.
- In the implementation diff, `except Exception: pass` and a bare `except:` are the silent-failure sites; a test asserting only "no exception raised" cannot tell them from success.

### Kotlin/Java
- Files: `*Test.kt`, `*Test.java`, `*Spec.kt`; JUnit 5 `@Test`, `@ParameterizedTest`
- Watch for: `@Disabled`/`@Ignore` added, `@Test(expected = ...)` removed, Mockito `eq(x)` widened to `any()` (the stub now answers every input), `verify(mock, times(1))` → `verify(mock)` → deleted
- **AssertJ assertions that survive real regressions:** `isNotNull()` where the value matters, `isGreaterThan(0)` on a duration or size, and `assertThatCode { }.doesNotThrowAnyException()` as a test's *only* assertion. Prefer `isCloseTo(expected, within(tolerance))` when magnitude is the point — `Duration.ofHours(12).toMinutes()` is 720, which passes `isGreaterThan(0)` while being a 60× error.
- `runCatching { }` swallows everything, including `CancellationException` — inside a coroutine that silently breaks structured concurrency rather than propagating the cancel. A test that only checks the fallback value will not see it.
- `assertEquals(expected, actual)` on `Double`/`Float` without a delta argument is a flaky assertion waiting to happen.

### Rust
- Files: `#[cfg(test)] mod tests` inline, `tests/*.rs` for integration
- Watch for: `#[ignore]` added without justification, `assert!(result.is_ok())` replacing an assertion on the actual value, `assert!(matches!(x, Pattern))` loosened to a wildcard arm
- **`#[should_panic]` without `expected = "..."` passes on any panic at all** — including an `unwrap()` in the test's own setup, or a panic from a completely unrelated bug. It is the single easiest way to have a green test that proves nothing.
- `let _ = fallible();` discards a `Result` and silences the `must_use` warning. In an implementation diff that is a deliberate-looking silent failure; check whether a test forces that path.
- `unwrap()`/`expect()` in the code under test *are* the error paths — a test that only exercises the happy path leaves them entirely unproven, and they abort the process rather than returning.
- Prefer tests returning `Result<(), E>` and using `?` over `unwrap()` — a failure then reports the error rather than a bare panic line.

### Ruby
- Files: `*_spec.rb` (RSpec), `*_test.rb` (Minitest)
- Watch for: `xit`/`xdescribe`/`skip`/`pending` added, `eq` weakened to `be_truthy`, `let!` changed to `let` (setup that used to run eagerly is now lazy and may never run)
- **`expect { }.not_to raise_error` as a test's only assertion** proves nothing about the result — and RSpec deliberately forbids the argument form (`not_to raise_error(SomeError)`) because it passes when a *different* error is raised.
- `allow(x).to receive(:y).and_return(z)` with no `with(...)` constraint answers `z` for every input, so a test can pass against an implementation that passes the wrong arguments entirely.
- In the implementation diff, `rescue nil` and a bare `rescue` (which catches `StandardError`) are the silent-failure sites. `rescue Exception` is worse — it catches `Interrupt` and `SignalException` too.
- `be_truthy` passes for `0` and `""`; `be true` is the strict check.
