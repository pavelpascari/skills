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

**Notes by language:**
- **Go:** exported identifiers should have a doc comment starting with the identifier name (`// Order represents ...`). The toolchain enforces this in some configs.
- **Python:** docstrings are part of the runtime (`__doc__`), so they double as machine-readable API descriptions.
- **TypeScript:** JSDoc (`/** ... */`) integrates with editor tooling for hover hints — worth writing on exported types/functions.
