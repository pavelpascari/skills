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
- **Go:** use `errors.Is` / `errors.As` for discrimination; wrap with `%w` in `fmt.Errorf`.
- **Python:** raise typed exceptions; use `raise ... from err` to preserve cause chains.
- **TypeScript:** since JS errors are stringly-typed, define a discriminated union (`type Result<T, E> = ...`) or use a library (e.g., neverthrow, fp-ts) for explicit error channels.
