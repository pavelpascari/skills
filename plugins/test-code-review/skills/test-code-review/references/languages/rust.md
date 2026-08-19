# Rust — test review patterns

- Files: `#[cfg(test)] mod tests` inline, `tests/*.rs` for integration.
- Watch for: `#[ignore]` added without justification; `assert!(result.is_ok())` replacing an assertion on the actual value; `assert!(matches!(x, Pattern))` loosened to a wildcard arm.
- **`#[should_panic]` without `expected = "..."` passes on any panic at all** — including an `unwrap()` in the test's own setup, or a panic from a completely unrelated bug. It is the single easiest way to have a green test that proves nothing.
- `let _ = fallible();` discards a `Result` and silences the `must_use` warning. In an implementation diff that is a deliberate-looking silent failure — check whether a test forces that path.
- `unwrap()` / `expect()` in the code under test *are* the error paths. A test that only exercises the happy path leaves them entirely unproven, and they abort the process rather than returning.
- Prefer tests returning `Result<(), E>` and using `?` over `unwrap()` — a failure then reports the error rather than a bare panic line.
