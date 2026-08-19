# Go

Language-specific notes. The principles live in the topic references; this file is only how they land in Go.

## Testing
- Prefer table-driven tests when a bug has multiple boundary conditions — one row per condition.
- **Applying the mutation catalogue** (`testing.md`, *verify the test by breaking the code*): *negate a condition* — flip `!=` to `==` in the error check; *replace the return value* — return the zero value instead of the computed one. A test asserting only `err == nil` stays green through both. *Delete a statement* is especially cheap here: remove the `if err != nil { return }` and see whether anything notices.

## Errors
- Use `errors.Is` / `errors.As` for discrimination; wrap with `%w` in `fmt.Errorf`.
- A bare `return err` loses the operation context — wrap at each layer that knows something the caller doesn't.

## Naming and comments
- Exported identifiers get a doc comment starting with the identifier name (`// Order represents ...`). Some toolchain configs enforce it.

## Code structure
- Packages **are** the firewall — the compiler enforces them. The package is the unit of encapsulation.

## Observability
- OpenTelemetry has middleware for `net/http`, gRPC and `sql` — use it for wire-crossing operations rather than hand-rolling spans.
