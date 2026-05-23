# Testing

## TDD is imperative

**Rule:** Write a failing test that describes the behavior you intend, then write the minimum code to make it pass, then refactor. Always.

**Why:** Tests are a design tool, not just a verification tool. Writing the test first forces you to articulate the API and intent before implementation. The exercise reveals awkward signatures, missing abstractions, and ambiguous requirements — *before* you've committed to a shape. TDD also locks behavior in a form that survives refactors.

**How to apply:** For every new behavior — new function, new endpoint, new business rule — write the test first. Run it. Confirm it fails for the reason you expect (not because of a syntax error). Implement the minimum that makes it pass. Refactor with the test as a safety net. Commit small.

**Red flags:**
- "I'll add tests after I get it working" — you won't, or you'll write tests that match what the code does instead of what it should do.
- Tests that mirror the implementation's structure (one test per private helper) — a sign tests were written after.
- Tests that never failed for the right reason during development.

**Example:**
```typescript
// Red — write the test first.
test("rejects orders with zero quantity", () => {
  expect(() => createOrder({ quantity: 0 })).toThrow("quantity must be positive");
});

// Run it. Confirm it fails: "createOrder is not defined" or "did not throw".

// Green — minimum to pass.
function createOrder({ quantity }: { quantity: number }): Order {
  if (quantity <= 0) throw new Error("quantity must be positive");
  return { quantity };
}

// Refactor — the test stays green.
```

---

## Test pyramid, DI, stubs over mocks, testcontainers

**Rule:** Cover all layers of the pyramid. Design components to be testable in isolation through dependency injection. Prefer stubs over mocks where possible. For integration / component tests, use testcontainers to validate the system end-to-end: queries, data handling, serialization.

**Why:** A pure unit test proves the logic. An integration test proves the wiring. Both are needed. Stubs (simple test doubles that return canned values) are usually cleaner than mocks (verification frameworks that record calls) — they read like normal code and don't lie about the contract. Testcontainers run real infrastructure (real Postgres, real Redis) so your test exercises the real query / serialization path, not a fake one.

**How to apply:**
- Design every component to accept its dependencies as constructor / function arguments (DI). Hard-to-inject is hard-to-test, which is hard-to-change.
- Use unit tests with stubs for logic-heavy code that has clear inputs and outputs.
- Use integration tests with testcontainers for code that talks to infrastructure — verify the actual SQL runs, the actual JSON encodes, the actual queue delivers.
- Don't double-test: a unit test of the SQL string is not an integration test, and an integration test of the business rule is overkill.

**Red flags:**
- A test suite of 90% mock-based unit tests — likely missing whole classes of bugs that only show up at the seams.
- Tests that need to call package-private / internal methods to set up state — design smell.
- Tests that pass against a fake DB but break against the real one — usually means the fake is wrong, not the test.

**Example:**
```go
// Unit test with a stub.
type stubRepo struct{ saved *Order }
func (s *stubRepo) Save(_ context.Context, o *Order) error { s.saved = o; return nil }

func TestService_PlaceOrder_SavesWithCorrectTotal(t *testing.T) {
    repo := &stubRepo{}
    svc := NewService(repo)
    _ = svc.PlaceOrder(context.Background(), 3, money.USD(10))
    if repo.saved.Total != money.USD(30) {
        t.Fatalf("got %v, want %v", repo.saved.Total, money.USD(30))
    }
}

// Integration test with testcontainers.
func TestPostgresOrderRepo_SaveAndLoad(t *testing.T) {
    ctx := context.Background()
    pg := startPostgresContainer(t)
    defer pg.Terminate(ctx)
    repo := NewPostgresOrderRepo(pg.DB)
    // ... save, then load, then assert equality
}
```

---

## Bug fix = reproduce-then-fix

**Rule:** Every bug fix starts with a failing test that demonstrates the bug. Only then does the fix get written. The fix is confirmed by the test now passing. Non-negotiable.

**Why:** Two reasons. First, until you have a reproducing test, you don't actually know the bug is what you think it is. Second, the test prevents regression — the same bug can't quietly come back in six months. "Quick fixes" without reproducing tests are a leading cause of recurring incidents.

**How to apply:** When a bug is reported, locate the affected unit. Write a test that asserts the expected (correct) behavior. Run it. Confirm it fails *for the reason described in the bug*. Now fix the code. Run the test. Confirm it passes. Run the rest of the suite. Commit (often the test and the fix as one commit; sometimes the test as its own commit for clarity).

**Red flags:**
- Commit message says "fix:" but the diff contains no test changes.
- A test was added but it would pass against the old buggy code too.
- The reproducing test is the same as an existing happy-path test — likely missing the boundary the bug actually lives at.

**Example:**
```python
# Bug: negative quantities are accepted in update_order.

# Step 1: failing test.
def test_update_order_rejects_negative_quantity():
    o = create_order(quantity=5)
    with pytest.raises(ValueError, match="positive"):
        update_order(o, quantity=-1)

# Run it. Confirm: it does NOT raise — bug confirmed.

# Step 2: minimal fix.
def update_order(o, quantity):
    if quantity <= 0:
        raise ValueError("quantity must be positive")
    o.quantity = quantity
    return o

# Run the test. Confirm: it raises now.
# Run the full suite. Confirm: no regressions.
```

**Notes by language:**
- **Go:** prefer table-driven tests when the bug has multiple boundary conditions; one row per condition.
- **TypeScript / Jest:** if the fix involves async behavior, use `await expect(...).rejects.toThrow(...)` — easy to get wrong.
- **Python / pytest:** `pytest.raises` with `match=` pins the error message; useful for proving the right code path triggered.
