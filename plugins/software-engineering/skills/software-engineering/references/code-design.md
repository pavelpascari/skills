# Code design

## Boundary validation

**Rule:** Validate inputs at system boundaries (public/exported APIs, HTTP handlers, message consumers, anything reading from a DB or external service). Trust internal callers.

**Why:** Defensive checks everywhere are noise that lies about the real contract. They make code harder to read, hide where the actual boundary is, and slow execution paths that are already proven safe by their caller. Boundaries are the only place an unknown actor can hand you bad data.

**How to apply:** When writing a function, ask: is this called by code you wrote in this repo (trust it), or by something outside the trust zone (validate it)? Exported / public functions on the seams (HTTP, CLI, message queue, library entry-point) validate. Private helpers don't.

**Red flags:**
- Every internal function re-checks the same precondition.
- Validation duplicated in caller and callee, with no clear "this is the boundary".
- A trivial private helper guards against `nil` even though every caller has already non-nil-checked.

**Example:**
```go
// Public boundary: validates.
func (h *Handler) GetProfile(w http.ResponseWriter, r *http.Request) {
    id := r.URL.Query().Get("user_id")
    if id == "" {
        http.Error(w, "user_id required", http.StatusBadRequest)
        return
    }
    profile, err := h.service.GetProfile(r.Context(), id)
    // ...
}

// Internal: trusts its caller. id is guaranteed non-empty by the handler.
func (s *Service) GetProfile(ctx context.Context, id string) (*Profile, error) {
    return s.repo.Find(ctx, id)
}
```

---

## Semantic DRY

**Rule:** Extract a shared helper only when the underlying intent matches across the call sites. Surface similarity is not duplication.

**Why:** Premature abstraction couples things that happen to look alike but evolve independently. The shared helper grows knobs to satisfy diverging callers, ending up worse than the original duplication.

**How to apply:** Before extracting, ask: do these places represent the same concept? Will they change together? If two snippets read alike but parse different headers for different purposes, leave them inline. If three call sites genuinely encode one operation, extract.

**Red flags:**
- Extracted helper has a `mode` / `kind` / `type` parameter that picks between branches — sign that callers' intents differ.
- Renaming the helper to keep it accurate to all callers feels strained.
- Callers pass slightly different arguments by adding wrapper logic around the call.

**Example:**
```python
# OK — same concept, three call sites, extract:
def parse_auth_header(h: str) -> AuthToken: ...

# Not OK — looks similar but different intents:
def parse_header_with_mode(h: str, mode: str) -> Any: ...  # smell
```

---

## Internal coupling

**Rule:** Default to ports and adapters. Direct call is fine when the dependency is a single, well-scoped implementation with a clear API. Use an interface for multiple implementations or testing seams. **Inner modules must not depend on outer modules.**

**Why:** Dependency direction controls how code evolves. When inner (domain) code depends on outer (infra) code, changing infra breaks the domain. Reversing the direction — domain defines the port, infra implements it — lets the domain stay stable while the world around it changes.

**How to apply:** Identify which module is "inner" (core domain logic) and which is "outer" (HTTP, DB, queue). Inner code declares the interfaces it needs; outer code implements them. Avoid imports from inner → outer; require imports from outer → inner only.

**Red flags:**
- `domain/order.go` imports `infra/postgres`.
- An interface lives next to its single implementation with no second implementation in sight (and no testing reason).
- Mocks are needed for code that owns its own dependencies cleanly — a sign the seam is in the wrong place.

**Example:**
```go
// domain/order.go  — inner; declares what it needs.
type OrderRepository interface {
    Save(ctx context.Context, o *Order) error
}

// infra/postgres/order_repo.go — outer; implements the inner's port.
type PostgresOrderRepo struct { /* ... */ }
func (r *PostgresOrderRepo) Save(ctx context.Context, o *domain.Order) error { /* ... */ }
```

---

## API design

**Rule:** Design APIs as a minimal set of composable primitives. Extension points are demand-driven by real client use cases. Start small unless deep domain experience says otherwise. APIs must be coherent and self-explanatory.

**Why:** A small primitives API lets users layer calls to reach sophisticated outcomes without you anticipating every variation. Pre-emptive flexibility (options bags, callback hooks) ages badly — most options never get used, and removing them is a breaking change.

**How to apply:** Ship the minimum that solves the use cases you can see today. When a new caller needs something the API doesn't expose, evaluate whether it's a real general need or a one-off — only then add. Exception: well-known problem spaces (auth, HTTP, retry policies) have canonical patterns; follow them.

**Red flags:**
- Parameters named `options`, `config`, `extra` with many optional fields.
- Hooks / callbacks with no tested call sites.
- Public method that takes a strategy / handler interface used in exactly one place.

**Example — options bag bloat:**
```typescript
// Anti-pattern: client constructor accumulates unrelated concerns over time.
new ApiClient({
  baseUrl: "...",
  timeout: 30000,
  retries: 3,
  retryBackoff: "exponential",
  retryJitter: true,
  cache: true,
  cacheTtl: 300,
  cacheStorage: "memory",
  authToken: "...",
  authHeader: "Authorization",
  userAgent: "...",
  proxy: "...",
  pool: { max: 100, keepAlive: true },
  metrics: metricsReporter,
  tracer,
  logger,
  errorHandler: (e) => { /* ... */ },
  middleware: [/* ... */],
});
// Twenty knobs. Most callers use 3-5 of them. The bag mixes unrelated
// concerns — transport, caching, auth, observability, error handling —
// and every new concern grows the constructor signature.

// Composable layers — one concern each. Callers wrap only what they need.
const transport = createTransport({ baseUrl, timeout, pool });
const cached    = withCache(transport, { ttl: 300 });
const traced    = withTracing(cached, tracer);
const client    = new ApiClient(traced, { auth: token });
```

**Example — lifecycle callbacks no one uses:**
```typescript
// Anti-pattern: pre-wired hooks "in case someone needs them later".
function processOrder(
  order: Order,
  hooks?: {
    beforeValidate?: (o: Order) => void;
    afterValidate?: (o: Order) => void;
    beforeSubmit?: (o: Order) => void;
    afterSubmit?: (o: Order) => void;
    onError?: (e: Error) => void;
  },
): Promise<void>;
// Six months later: zero call sites use any of these. They are now permanent
// obligations the maintainer cannot safely remove.

// Start without hooks. When a real caller needs to react to a specific
// moment, add THAT one callback — named after what it does — informed by
// the actual use case, not anticipation.
function processOrder(order: Order): Promise<void>;
```

---

## Code structure

**Rule:** Organize code as vertical slices outside (by domain), hexagonal inside (ports and adapters). Core domain is I/O-less; side effects only at outer layers. Prefer deep modules with minimal but strong APIs over many thin modules spread too thin.

**Why:** Vertical slices put files that change together next to each other. Hexagonal inside keeps the core testable without infrastructure. Deep modules hide complexity behind a small API; many thin modules force the reader to follow imports across many files to understand one concept.

**How to apply:** Top-level layout reflects business domains (`orders/`, `payments/`, `users/`). Inside each domain, a core layer (pure logic, no I/O) and adapter layers (HTTP, DB, queue). When in doubt about whether to split a module, ask: is its API surface still small and easy to describe?

**Red flags:**
- Top-level `controllers/`, `services/`, `repositories/` with domain concepts scattered across all three.
- Inner files that import HTTP clients, ORMs, or queues directly.
- A module whose public API has 12 exported functions, half of which exist only because callers needed implementation details.
- Hard-to-test code — usually a design signal, not a testing problem.

**Example:**
```
orders/
  core/                # I/O-less
    order.go           # entity, business rules
    pricing.go         # pure functions
  ports/
    order_repo.go      # interface
    payment_gateway.go # interface
  adapters/
    http_handler.go    # outer adapter
    postgres_repo.go   # outer adapter, implements ports/order_repo.go
```

**Notes by language:**
- **Go:** package boundaries align with module boundaries; the package is the unit of encapsulation.
- **Java/Kotlin:** use module / package-private visibility to keep adapter classes out of the core's public surface.
- **TypeScript:** use barrel files (`index.ts`) sparingly — they erode the encapsulation benefits of folder structure.
