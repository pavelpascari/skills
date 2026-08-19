# Python

Language-specific notes. The principles live in the topic references; this file is only how they land in Python.

## Testing
- `pytest.raises` with `match=` pins the error message and proves the intended path failed. Without it, a `ValueError` raised by your own fixture satisfies the test.
- `@pytest.mark.parametrize` is the table-driven equivalent when a bug has several boundaries — including the boundary pair (largest rejected value, smallest accepted one).
- **Applying the mutation catalogue**: *replace the return value* — return `None` instead of the result; *shift a boundary* — widen `>` to `>=`. A test asserting a `Mock` truthily, or `assertIsNotNone`, notices neither. Beware that with a bare `Mock`, *delete a statement* often survives too — the call it removed was never really asserted on.

## Errors
- Raise typed exceptions; use `raise ... from err` to preserve cause chains.
- When suppression really is right, `contextlib.suppress(SpecificError)` says so out loud. `except: pass` says nothing and catches `KeyboardInterrupt` too.

## Naming and comments
- Docstrings are part of the runtime (`__doc__`), so they double as machine-readable API descriptions.

## Code structure
- Nothing is truly private and a leading underscore is a request, not a rule. `__all__` plus import-linter — or a layered package structure with a lint rule on import direction — is what turns the convention into a check.

## Observability
- `opentelemetry-instrument` wraps the process with no code changes, covering wire-crossing calls. Reserve manual spans for business operations no library can name for you.
