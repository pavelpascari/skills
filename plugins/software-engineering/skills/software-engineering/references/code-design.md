# Code design

## Boundary validation

**Rule:** Validate inputs at system boundaries (public/exported APIs, HTTP handlers, message consumers, anything reading from a DB or external service). Trust internal callers.

**Why:** Defensive checks everywhere are noise that lies about the real contract. They make code harder to read, hide where the actual boundary is, and slow execution paths that are already proven safe by their caller. Boundaries are the only place an unknown actor can hand you bad data.

**How to apply:** When writing a function, ask: is this called by code you wrote in this repo (trust it), or by something outside the trust zone (validate it)? Exported / public functions on the seams (HTTP, CLI, message queue, library entry-point) validate. Private helpers don't.

**Red flags:**
- Every internal function re-checks the same precondition.
- Validation duplicated in caller and callee, with no clear "this is the boundary".
- A trivial private helper guards against `nil` even though every caller has already non-nil-checked.

**Example — boundary validates input, internal trusts:**
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

**Example — null-object pattern for optional dependencies:**

The constructor is also a boundary. When a dependency is "optional" (metrics, logger, tracer, feature-flag client), the wrong fix is nil-checks at every call site:

```go
// Anti-pattern: nullable dependency forces defensive checks everywhere.
type Breaker struct {
    metrics *Metrics // may be nil in tests or some environments
}

func (b *Breaker) Allow() bool {
    if b.metrics != nil { // every call site repeats this
        b.metrics.DegradedDependencyTotal.WithLabelValues("breaker", "allow").Inc()
    }
    // ...
}
```

The right fix is to make the dependency unconditionally present via a null-object implementation. The constructor is the boundary that decides which implementation; every call site then trusts the dependency exists.

```go
type Metrics interface {
    IncDegraded(reason, outcome string)
}

type NoOpMetrics struct{}
func (NoOpMetrics) IncDegraded(_, _ string) {}

type Breaker struct {
    metrics Metrics // never nil — constructor guarantees it
}

func NewBreaker(m Metrics) *Breaker {
    if m == nil {
        panic("metrics is required; pass NoOpMetrics{} to disable explicitly")
    }
    return &Breaker{metrics: m}
}

func (b *Breaker) Allow() bool {
    b.metrics.IncDegraded("breaker", "allow") // unconditional; reads clean
    // ...
}
```

The panic at construction is the boundary doing its job: callers must make an explicit choice (real implementation or `NoOpMetrics{}`). There is no path to "I forgot to wire it" silently producing no metrics in production. The null-object has to be passed deliberately — the wiring stays honest, and call sites stay clean.

This pattern dovetails with **Code must never lie** (a nullable type lies about the contract), **Internal coupling — discover interfaces** (real + no-op are two real implementations, justifying the interface), and **Compose, don't inject** (`observability.md`).

---

## Semantic DRY

**Rule:** Extract a shared helper only when the underlying intent matches across the call sites. Surface similarity is not duplication.

**Why:** Premature abstraction couples things that happen to look alike but evolve independently. The shared helper grows knobs to satisfy diverging callers, ending up worse than the original duplication.

The other side of this is integrity: every line of code is a bug surface. Bjarne Stroustrup frames extra code as **ugly, large, slow** — ugly leaves places for bugs to hide, large ensures incomplete tests, slow encourages shortcuts and dirty tricks. The right amount of duplication serves the same goal as the right amount of abstraction: less code that must be correct, fewer places for bugs to hide.

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

**Rule:** Discover interfaces, don't design them. Start with concrete types. Introduce an interface only when a second implementation or a real testing seam exists, never preemptively. **Inner modules must not depend on outer modules.**

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

**Rule:** Organize code around three firewalls — packaging, layering, and domains. Use an explicit four-layer split with each layer owning its own type system:

- **API layer** — protocol transport (HTTP, gRPC, stdio). Decodes the stream into App models and encodes App models back to the stream. No data models of its own.
- **App layer** — external user-facing APIs. Data models carry the wire encoding (e.g. JSON tags) and the input constraints. Calls into Business.
- **Business layer** — the application's schema. Data models have no wire or storage encoding. Declares the storage contracts the domain needs.
- **Storage layer** — implements the Business storage contracts with persistence-specific encoding. Trusts the Business layer with what it is asked to store.

Data flows through these layers via transformations. Integrity is maintained because no layer's encoding leaks into another.

**Why:** Complexity is the long-term enemy. Each firewall localizes one kind of change so the rest of the system doesn't pay for it. When JSON changes, only the App layer changes; when the DB changes, only Storage changes; the Business schema stays stable. Packaging localizes individual problems into firewalled units the compiler reasons about. Domains group related layers so each group can be reasoned about and scaled independently.

**How to apply:**
- Each package has a clear, narrow purpose; it *provides* one thing rather than *containing* many disparate things.
- Each layer defines its own types for input and output; data is transformed between layers rather than shared.
- Imports are one-way streets. No cross-imports between packages; no inner-to-outer dependencies between layers.
- Polymorphism is opt-in: a polymorphic function uses the type system of the package that defined the interface. All other types stay package-local.
- **Reducing complexity is more powerful than hiding it.** Encapsulation hides complexity from one reader, but the complexity is still there for the next maintainer to face. When you can choose between hiding complexity behind a clean API and removing the complexity entirely, prefer removal. (Chris Hines, via Bill Kennedy.)
- "Don't make things easy to do, make things easy to understand." Optimize for the reader.

**Red flags:**
- Packages named `utils`, `helpers`, `common`, `shared` — names that describe contents, not purpose.
- App or API types leaking into Business or Storage (or vice versa).
- A single shared type definition used in all layers — usually one layer's encoding contaminating another.
- Cyclic imports — the firewall has cracked.

**Example (Go-shaped; the principle is language-agnostic):**
```
api/
  http/              # API layer — protocol transport
    handler.go       # decodes stream → App models; encodes App models → stream
app/
  orders/            # App layer — external user-facing API
    orders.go        # App models with JSON tags + input validation
business/
  orders/            # Business layer — the application schema
    orders.go        # Business models (no encoding leakage)
    storer.go        # Storage contract this domain needs
storage/
  ordersdb/          # Storage layer — implements the Business storage contract
    ordersdb.go      # Storage models with persistence-specific encoding
```

**Notes by language** — the principle is universal; apply it the way each language is idiomatic:
- **Go:** packages ARE the firewall — the compiler enforces them. The package is the unit of encapsulation.
- **Java/Kotlin:** module + package-private visibility approximates Go's package boundaries. Multi-module Gradle/Maven projects can mirror the four-layer structure.
- **TypeScript:** without real package-level visibility, lean on directory boundaries + lint rules (e.g. `eslint-plugin-boundaries`) to enforce import direction.

**Credit:** the three-firewalls / four-layer model is articulated by Bill Kennedy in *Domain-Driven, Data-Oriented Design* (ardanlabs/service wiki).
