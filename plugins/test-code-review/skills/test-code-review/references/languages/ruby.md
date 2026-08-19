# Ruby — test review patterns

- Files: `*_spec.rb` (RSpec), `*_test.rb` (Minitest).
- Watch for: `xit` / `xdescribe` / `skip` / `pending` added; `eq` weakened to `be_truthy`; `let!` changed to `let` (setup that used to run eagerly is now lazy and may never run).
- **`expect { }.not_to raise_error` as a test's only assertion** proves nothing about the result — and RSpec deliberately rejects the argument form (`not_to raise_error(SomeError)`) because it passes when a *different* error is raised.
- `allow(x).to receive(:y).and_return(z)` with no `with(...)` constraint answers `z` for every input, so a test can pass against an implementation that passes the wrong arguments entirely.
- In the implementation diff, `rescue nil` and a bare `rescue` (which catches `StandardError`) are the silent-failure sites. `rescue Exception` is worse — it catches `Interrupt` and `SignalException` too.
- `be_truthy` passes for `0` and `""`; `be true` is the strict check.
