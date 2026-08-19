# TypeScript / JavaScript — test review patterns

- Files: `*.test.ts`, `*.spec.ts`, `*.test.js`, `*.spec.js`.
- Watch for: `.skip` added to test cases; `expect` calls removed; `.toEqual` → `.toMatchObject` (now allows extra fields).
- A missing `await` on `expect(...).rejects.toThrow(...)` makes the assertion vacuous — the promise settles after the test has already passed.
