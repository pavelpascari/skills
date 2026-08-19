# Ruby

Language-specific notes. The principles live in the topic references; this file is only how they land in Ruby.

## Testing
- `expect { ... }.to raise_error(MyError, /specific message/)` — the bare `raise_error` matches every error class, and `not_to raise_error` is not an assertion about the result at all.
- **Applying the mutation catalogue**: *replace the return value* — return `nil`; *negate a condition* — swap `==` for `.present?`. `be_truthy` survives both, since only `nil` and `false` are falsy — `0` and `""` are truthy, so *replace a constant* with `0` is a good third probe.

## Errors
- Give the library one base error class and derive from it, so a caller can `rescue MyLib::Error` and catch everything you raise and nothing you don't.
- **Never `rescue Exception`** — that catches `Interrupt` and `SignalException`, making the process unkillable by Ctrl-C. A bare `rescue` catches `StandardError`, which is usually what you meant.

## Naming and comments
- YARD (`# @param`, `# @return`) is the convention. Since so much is duck-typed, the docstring is often the only statement of what a method actually accepts — load-bearing rather than decorative.

## Code structure
- There is no cross-file visibility the runtime enforces, so boundaries are conventional. Namespace modules plus `private_constant` express intent; an import-direction check in CI is what makes it a rule.

## Observability
- The OpenTelemetry SDK auto-instruments Rails, Sidekiq and the common HTTP clients. Background jobs are the usual gap — a job that fails silently is invisible unless the span records it.
