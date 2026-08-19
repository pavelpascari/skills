# Rust

Language-specific notes. The principles live in the topic references; this file is only how they land in Rust.

## Testing
- Prefer a test returning `Result<(), E>` and using `?` over `unwrap()`, so a failure prints the error instead of a bare panic line.
- If you use `#[should_panic]`, **always give it `expected = "..."`**. The bare form passes on *any* panic, including one from the test's own setup — the cheapest way to have a green test that proves nothing.
- To verify an assertion binds: replace the returned value with `Default::default()`, or change `?` to `.unwrap_or_default()`. A test asserting `is_ok()` stays green; one asserting the value does not.

## Errors
- `thiserror` for library errors (typed, matchable by the caller); `anyhow` at the binary's boundary.
- `?` propagates but carries no context of its own — add `.context("loading order")` at each layer, or the top-level error names a file descriptor instead of an operation.

## Naming and comments
- `///` doc comments are compiled, and their examples are **run by `cargo test`**. A documented example cannot silently rot into a lie, which makes doc examples the cheapest place to put usage that must stay true.

## Code structure
- Modules plus `pub(crate)` / `pub(super)` give visibility the compiler actually enforces, so the firewall is real rather than conventional. Workspace crates are the coarser boundary when a module is not enough.

## Observability
- `tracing` is the ecosystem default — spans over log lines, with `tracing-opentelemetry` as the export bridge. Prefer `#[instrument]` on the operation over hand-rolled enter/exit, so an early `?` return cannot skip the exit.
