# Kotlin / Java — test review patterns

- Files: `*Test.kt`, `*Test.java`, `*Spec.kt`; JUnit 5 `@Test`, `@ParameterizedTest`.
- Watch for: `@Disabled` / `@Ignore` added; `@Test(expected = ...)` removed; Mockito `eq(x)` widened to `any()` (the stub now answers every input); `verify(mock, times(1))` → `verify(mock)` → deleted.
- **AssertJ assertions that survive real regressions:** `isNotNull()` where the value matters, `isGreaterThan(0)` on a duration or size, and `assertThatCode { }.doesNotThrowAnyException()` as a test's *only* assertion. Prefer `isCloseTo(expected, within(tolerance))` when magnitude is the point — `Duration.ofHours(12).toMinutes()` is 720, which passes `isGreaterThan(0)` while being a 60× error.
- `runCatching { }` swallows everything, including `CancellationException` — inside a coroutine that silently breaks structured concurrency rather than propagating the cancel. A test that only checks the fallback value will not see it.
- `assertEquals(expected, actual)` on `Double` / `Float` without a delta argument is a flaky assertion waiting to happen.
