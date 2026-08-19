# TypeScript / JavaScript

Language-specific notes. The principles live in the topic references; this file is only how they land in TypeScript.

## Testing
- If a fix involves async behaviour, use `await expect(...).rejects.toThrow(...)` — easy to get wrong, and a missing `await` makes the assertion vacuous.
- **Applying the mutation catalogue**: *replace the return value* — return `undefined`; *shift a boundary* — `<` → `<=`; *negate a condition* in a guard. Also worth the thought experiment: replace `toEqual` with `toMatchObject` and ask whether the extra fields would still have been caught.

## Errors
- JS errors are stringly-typed, so define a discriminated union (`type Result<T, E> = ...`) or use a library (neverthrow, fp-ts) to get an explicit error channel.

## Naming and comments
- JSDoc (`/** ... */`) drives editor hover hints — worth writing on exported types and functions.

## Code structure
- Without real package-level visibility, lean on directory boundaries plus lint rules (e.g. `eslint-plugin-boundaries`) to enforce import direction.

## Observability
- The OpenTelemetry SDK auto-instruments most HTTP / DB / cache libraries. Manual instrumentation belongs in application logic, not protocol plumbing.
