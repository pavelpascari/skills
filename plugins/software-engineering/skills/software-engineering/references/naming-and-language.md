# Naming and language

## Ubiquitous language

**Rule:** The domain layer of your code speaks the agreed-upon business language. Storage may keep legacy names if a mapping layer bridges to the domain term. Rename storage too if the cost is cheap.

**Why:** When code, product, and customer all use different words for the same concept, every conversation translates back and forth. Translation costs compound: bugs hide in the mismatch, new joiners spend weeks decoding aliases, and architectural changes get blocked because no one is sure which term wins.

**How to apply:** Identify the canonical business term (talk to product, read recent design docs, listen to customer-facing copy). Use it in the domain layer (entities, services, value objects). If the database table is named legacy, define an entity mapping that translates at the persistence boundary. If your ORM tightly couples entity name to table name, push the translation into a mapping layer (DTOs, repositories).

**Red flags:**
- Mixed terminology in the same file or service: `Order`, `Purchase`, `Transaction`, `Cart` all referring to the same thing.
- Method names that translate (`purchaseToOrder`) scattered throughout the codebase rather than at one boundary.
- New code uses the legacy name because "everything else does".

**Example:**
```kotlin
// Storage layer keeps the legacy table name.
@Entity
@Table(name = "purchases")
class OrderEntity { /* ... */ }

// Domain layer speaks the agreed-upon language.
data class Order(val id: OrderId, val customer: CustomerId, val total: Money)

// Mapping at the boundary.
class OrderMapper {
    fun fromEntity(e: OrderEntity): Order = /* ... */
    fun toEntity(o: Order): OrderEntity = /* ... */
}
```

---

## Comments

**Rule:** Public/exported APIs get docstrings describing purpose. Internal code only gets comments when the WHY is non-obvious — hidden constraint, subtle invariant, workaround for a known bug, surprising behavior. Never comment WHAT.

**Why:** Names should carry the WHAT. A comment that restates the code is noise that future readers must verify against the implementation; when it drifts, it lies. A comment that explains WHY (intent, constraint, surprise) cannot be inferred from the code and earns its keep.

**How to apply:** Before writing a comment, ask: "Could a reader figure this out from the code itself?" If yes, rename instead. If the comment is "Adds two numbers" on `add(a, b)`, delete. If the comment is "Capped at 200 because the upstream API rate-limits beyond that", keep — that's a hidden constraint.

**Red flags:**
- Comments restating the code (`// increment i` above `i++`).
- Comments referencing tickets, PRs, or callers (`// fix for INC-1234`) — that context belongs in the commit message, not the source.
- Multi-paragraph block comments on internal helpers.
- Stale TODOs without dates or owners.

**Example:**
```python
# Bad — restates the code.
# Multiply quantity by price.
total = quantity * price

# OK — public API docstring.
def calculate_total(quantity: int, price: Decimal) -> Decimal:
    """Return the line-item total. Quantity and price must be non-negative."""
    return quantity * price

# OK — non-obvious WHY.
# Upstream API returns 429 over 200 items per call; chunk to stay under.
for chunk in chunked(items, 200):
    upstream.send(chunk)
```

**Notes by language** — the principle is universal; apply it the way each language is idiomatic:
- **Go:** exported identifiers should have a doc comment starting with the identifier name (`// Order represents ...`). The toolchain enforces this in some configs.
- **Python:** docstrings are part of the runtime (`__doc__`), so they double as machine-readable API descriptions.
- **TypeScript:** JSDoc (`/** ... */`) integrates with editor tooling for hover hints — worth writing on exported types/functions.

---

## Code must never lie

**Rule:** Code, names, comments, tests, log messages, and error strings must accurately reflect what is actually happening. A misleading name, a stale comment, a passing test that doesn't actually verify the behavior — all of these are lies the reader trusts, and the wrong fix follows.

**Why:** Software is read many more times than it is written. The reader's mental model is built from the signals the code provides — function names, type names, comments, test names, log fields, error messages. When any of those signals drifts from reality, the mental model is wrong, and confident edits compound the bug. The most insidious failures are those where the code looks like it's doing one thing but does another.

**How to apply:**
- **Names:** rename the moment behavior diverges. `validateOrder` that no longer validates is now misleading; it's `normalizeOrder` or it's broken.
- **Comments:** delete or update on every code change. A drifted comment is worse than no comment.
- **Tests:** a test named `test_handles_concurrent_writes` must actually exercise concurrency. If the implementation changed, fix the test, don't keep the name.
- **Errors:** error messages describe what actually went wrong with this run, not the original expectation.
- **Logs:** log fields match the values being logged. After `user` becomes `account`, the field name updates too.

**Red flags:**
- Function body has diverged from its name.
- Comment describing behavior the code no longer has.
- Test name overstates what the test verifies.
- Error message reused after the code path that produced it changed.
- `// TODO` markers from prior years, lying about ongoing work.

**Example:**
```python
# Bad — the name lies. The function no longer validates; it only normalizes.
def validate_email(addr: str) -> str:
    return addr.strip().lower()

# Good — name matches behavior.
def normalize_email(addr: str) -> str:
    return addr.strip().lower()

# Or, if validation is genuinely needed, restore it.
def validate_email(addr: str) -> str:
    addr = addr.strip().lower()
    if "@" not in addr:
        raise ValueError(f"invalid email: {addr!r}")
    return addr
```

**Credit:** "Code must never lie" — Nate Finch, surfaced in Bill Kennedy's *Design Guidelines* wiki.
