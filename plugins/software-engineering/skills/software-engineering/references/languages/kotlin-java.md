# Kotlin / Java

Language-specific notes. The principles live in the topic references; this file is only how they land on the JVM.

## Testing
- JUnit 5's `assertThrows<T> { }` **returns** the exception — assert on its message, otherwise any `T` thrown from anywhere in the block satisfies the test.
- `@ParameterizedTest` with `@ValueSource` covers the boundary pair (largest rejected value, smallest accepted one) in one test.
- To verify an assertion binds: swap a `Duration` unit (`toSeconds()` → `toMinutes()`), or delete a `require`. `isGreaterThan(0)` and `isNotNull()` survive both; `isCloseTo(expected, within(...))` does not — `Duration.ofHours(12).toMinutes()` is 720, a 60× error that passes a sign check.

## Errors
- A sealed class or interface gives the boundary an exhaustive `when` over the failure cases, checked by the compiler.
- **`runCatching` catches `Throwable`.** Inside a coroutine that means it swallows `CancellationException` and quietly breaks structured concurrency, handing back a normal-looking fallback. Rethrow it, or catch the specific exceptions you mean.
- Java: prefer a small typed exception hierarchy over `throws Exception`. Never leave a `catch` block empty — if the failure really is ignorable, log it and say why on the same line.

## Naming and comments
- KDoc (`/** ... */`) with `@param` / `@return`; Dokka renders it. A `//` comment restating the next line is the one to delete.

## Code structure
- Module plus package-private visibility approximates Go's package boundaries. Multi-module Gradle/Maven projects can mirror the four-layer structure.

## Observability
- Spring Boot's auto-configuration covers most cross-cutting telemetry. Add custom instrumentation only for business KPIs.
