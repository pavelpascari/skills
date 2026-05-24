# Observability

## Context-driven instrumentation; compose, don't inject

**Rule:** Instrument what you would want at 3am during an incident on this code path. Don't add boilerplate telemetry that no one queries. Use shared chassis code for cross-cutting concerns (HTTP clients inject o11y headers; handler decorators add tracing). Wire-crossing requests get traces; metrics derive from spans. Custom metrics require explicit goals — what aspect is measured (directly or by proxy), and how is it encoded. **Prefer wrappers like `TracedCachedClient` or `TracedPaymentProcessor` over injecting a tracer into the core API.**

**Why:** Telemetry that no one queries is dead weight. The right question to ask is not "what could I log?" but "if this code path were currently misbehaving, what would I want to know?" — that shapes which fields, dimensions, and events earn their place. Composing observability via wrappers (decorators around a clean interface) keeps the core API focused on its job; injecting tracers into the core couples business logic to instrumentation libraries and makes the core harder to test and reuse.

**How to apply:**
- For wire-crossing operations (HTTP, gRPC, queue, DB), traces are default. The chassis injects span context and headers; you usually don't write it by hand.
- For custom metrics, write down the question: "What does this number tell me?" If you can't answer, don't add the metric.
- For wrappers: define the clean interface (e.g., `PaymentProcessor`). Implement business logic in one struct (`Stripe`). Wrap with observability in another (`TracedStripe`). Compose at construction time.
- Span attributes: include user/tenant/request identifiers, key inputs, outcome category. Avoid attributes that explode cardinality without purpose (free-text fields, raw payloads).

**Red flags:**
- A tracer or metrics client passed into the constructor of a domain object.
- Logs / metrics / spans added "just in case".
- Dashboards full of charts that no one opens.
- Wide-open free-text span attributes leaking PII or exploding cardinality.

**Example:**
```go
// Clean interface — no observability dependency.
type PaymentProcessor interface {
    Charge(ctx context.Context, amount Money, source SourceID) (ChargeID, error)
}

// Core implementation — no tracer.
type StripeProcessor struct { /* ... */ }
func (s *StripeProcessor) Charge(ctx context.Context, amount Money, source SourceID) (ChargeID, error) { /* ... */ }

// Observability wrapper — composes around the interface.
type TracedProcessor struct {
    inner  PaymentProcessor
    tracer trace.Tracer
}
func (t *TracedProcessor) Charge(ctx context.Context, amount Money, source SourceID) (ChargeID, error) {
    ctx, span := t.tracer.Start(ctx, "Charge",
        trace.WithAttributes(attribute.Stringer("amount", amount), attribute.String("source", string(source))))
    defer span.End()
    id, err := t.inner.Charge(ctx, amount, source)
    if err != nil {
        span.RecordError(err)
    }
    return id, err
}

// At wiring time:
proc := NewTracedProcessor(NewStripeProcessor(...), tracer)
```

**Notes by language** — the principle is universal; apply it the way each language is idiomatic:
- **Go:** OpenTelemetry has middleware for net/http, gRPC, sql — use it for wire-crossing operations.
- **Java/Spring:** Spring Boot's auto-configuration covers most cross-cutting telemetry; add custom only for business KPIs.
- **TypeScript/Node:** the OpenTelemetry SDK auto-instruments most HTTP / DB / cache libraries; manual instrumentation belongs in your application logic, not in protocol plumbing.

**See also:** the **null-object pattern** in `code-design.md` (under Boundary validation). When an observability dependency is "optional" (metrics, logger, tracer), the answer is not nil-checks at every call site — it's a no-op implementation that the constructor wires in deliberately. Same compose-don't-inject instinct, applied to absence rather than enrichment.
