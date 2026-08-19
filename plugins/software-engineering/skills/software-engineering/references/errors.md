# Errors

## Layered error handling

**Rule:** Internal layers propagate errors with context describing what they were attempting. The public API layer (HTTP handler, CLI entry, message consumer) decides how the error is presented to the outside world — status code, sanitized message, retry guidance, log severity.

**Why:** **Error handling is a first-class concern, not an exception path.** A USENIX study of catastrophic failures in distributed systems (Cassandra, HBase, HDFS, MapReduce, Redis) found that ~92% came from incorrect, ignored, or incomplete error handling — not from the happy-path logic. Treat error paths with the same rigor as the main path: name them, type them, test them, and decide explicitly what happens at the boundary.

The function that hits the database doesn't know whether the caller is a public HTTP endpoint, a background job, or a CLI tool. Each of those wants a different response: HTTP wants a status code and a sanitized body; a job wants a retry decision; a CLI wants a human-readable message. Pushing presentation decisions to the boundary keeps internal code single-purpose and lets one error type satisfy many callers.

**How to apply:**
- Internal code returns errors wrapped with context: `fmt.Errorf("loading order %s: %w", id, err)` (Go), `raise OrderLoadError(id) from err` (Python).
- Define error types with the categories the boundary needs to discriminate: `NotFound`, `Conflict`, `Validation`, `Internal`.
- The public-API layer is the one place where error → response/log mapping lives.
- Never `catch and continue` — that's the silent failure trap.
- Never `catch, log, return default` unless the default is genuinely the right behavior (and document why).

**Red flags:**
- HTTP handler code reaching deep into internal modules to translate errors.
- Internal functions returning typed responses (status codes, HTTP bodies) instead of typed errors.
- `try: ... except: pass` (Python) or `_ = err` (Go).
- A single `Internal Server Error` for every failure — the boundary isn't discriminating.

**Example:**
```go
// Internal layer: propagate with context.
func (r *PostgresOrderRepo) Find(ctx context.Context, id OrderID) (*Order, error) {
    row := r.db.QueryRowContext(ctx, "...", id)
    var o Order
    if err := row.Scan(&o.ID, &o.Total); err != nil {
        if errors.Is(err, sql.ErrNoRows) {
            return nil, ErrNotFound // typed
        }
        return nil, fmt.Errorf("scanning order %s: %w", id, err) // wrapped
    }
    return &o, nil
}

// Boundary: decide presentation.
func (h *Handler) GetOrder(w http.ResponseWriter, r *http.Request) {
    o, err := h.svc.GetOrder(r.Context(), OrderID(mux.Vars(r)["id"]))
    switch {
    case errors.Is(err, ErrNotFound):
        http.Error(w, "order not found", http.StatusNotFound)
        return
    case err != nil:
        log.Error("get_order_failed", "err", err)
        http.Error(w, "internal error", http.StatusInternalServerError)
        return
    }
    json.NewEncoder(w).Encode(o)
}
```

**Notes by language** — the principle is universal; apply it the way each language is idiomatic:
- **Go:** use `errors.Is` / `errors.As` for discrimination; wrap with `%w` in `fmt.Errorf`. A bare `return err` loses the operation context — wrap at each layer that knows something the caller doesn't.
- **Python:** raise typed exceptions; use `raise ... from err` to preserve cause chains. When suppression really is right, `contextlib.suppress(SpecificError)` says so out loud; `except: pass` says nothing and catches `KeyboardInterrupt` too.
- **TypeScript:** since JS errors are stringly-typed, define a discriminated union (`type Result<T, E> = ...`) or use a library (e.g., neverthrow, fp-ts) for explicit error channels.
- **Kotlin:** a sealed class or interface gives the boundary an exhaustive `when` over the failure cases the compiler can check. Be careful with `runCatching`: it catches `Throwable`, so inside a coroutine it swallows `CancellationException` and quietly breaks structured concurrency — rethrow it, or catch the specific exceptions you mean.
- **Java:** prefer a small typed exception hierarchy over `throws Exception`. Never leave a `catch` block empty; if the failure is genuinely ignorable, log it and say why in the same line.
- **Rust:** `thiserror` for library errors (typed, matchable by the caller) and `anyhow` at the binary's boundary. `?` propagates but carries no context of its own — add `.context("loading order")` at each layer, or the top-level error names a file descriptor instead of an operation.
- **Ruby:** give the library one base error class and derive from it, so a caller can `rescue MyLib::Error` and catch everything you raise and nothing you don't. Never `rescue Exception` — that catches `Interrupt` and `SignalException`, making the process unkillable by Ctrl-C.

---

## Failure containment — blast radius, not "is it caught"

**Rule:** For every operation that can fail, the question is not whether an exception is caught but
what breaks when it isn't. Name the blast radius, then decide whether that radius is acceptable.
A path documented as "best-effort" must have a handler that makes it so.

**Why:** "Is there a try/catch" is answerable by looking at one function. "What breaks" needs the
call site, the thread it runs on, and the framework's behaviour — which is why it gets skipped, and
why the failures it catches are the expensive ones. A metrics gauge with no handler does not lose
one metric; an uncaught exception from one value-supplier fails the whole scrape. A batch that
throws midway does not simply fail; already-queued commands sit unflushed in a connection buffer
and ride along on a later, unrelated batch.

A "best-effort" claim with no catch behind it is the same defect wearing a comment. Nobody decided
that a bookkeeping blip should return a 500 to a customer — it just was never considered, and the
docstring saying otherwise made it look considered.

This is not the "catch and continue" anti-pattern *Layered error handling* above forbids. That
phrase names a catch with no logging and no considered decision — the failure becomes invisible,
and execution proceeds as though nothing happened. A contained path is the opposite: the blast
radius was named, the catch is deliberate, the degraded outcome is logged, and the choice is
documented. It is exactly the "unless the default is genuinely the right behavior (and document
why)" exception that section already carves out — generalized past that phrasing's literal
*return default*: a best-effort background write that fails has no value to default at all, only a
log line and a stop, but the same test applies — was the catch deliberate, logged, and its
degraded outcome documented as the right one. This section is what earning that exception looks
like in practice, void operations included.

**How to apply:**
- For each new external call, batched operation, background callback, or metrics supplier, write
  down what breaks if it throws — the request, the scrape, the consumer group, the whole process.
- If the answer is bigger than the operation's own importance, contain it: catch, log with enough
  context to identify the dropped work, and degrade in one direction only.
- If a comment, docstring, or PR description calls a path best-effort, fire-and-forget, or
  bookkeeping, the catch is not optional — the claim is a contract.
- Log the containment. A silently swallowed failure and a contained one look identical in
  production unless the log line exists.
- Every containment gets a test that forces the failure. See `test-code-review` Step 4b.

**Red flags:**
- An exception path whose blast radius nobody has stated.
- Code called "best-effort" in prose with no handler in the body.
- `catch` blocks that log nothing, so the degraded mode is invisible.
- A failure path with 100% line coverage and no test that triggers it.

**Example:**
```kotlin
// Before: one failing Redis read fails the entire Prometheus scrape.
Gauge.builder(QUEUE_PENDING) { pendingCount() }.register(registry)

// After: contained, and NaN rather than 0.0 — zero is a plausible, reassuring
// reading that would hide the outage.
Gauge.builder(QUEUE_PENDING) { orUnknown { pendingCount() } }.register(registry)

private inline fun orUnknown(read: () -> Double): Double =
    runCatching(read).getOrDefault(Double.NaN)
```
