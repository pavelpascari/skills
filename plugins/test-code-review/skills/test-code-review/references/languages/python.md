# Python — test review patterns

- Files: `test_*.py`, `*_test.py`.
- Watch for: `@pytest.mark.skip` added; `assertEqual` → `assertIn` (less precise); exception tests removed.
- `pytest.raises(ValueError)` without `match=` passes on *any* `ValueError`, including one raised by the setup before the code under test runs. `match=` is what proves the intended path failed.
- **`assert mock.some_method()` always passes.** A `Mock`/`MagicMock` returns a truthy `Mock` for any call or attribute, so bare-truthiness assertions on one are vacuous — and a typo'd attribute (`mock.reslut`) invents an attribute rather than raising. `assert x.called` has the same problem: `Mock` answers `.called_once` truthily too, and that is not a real API. Use `assert_called_once_with(...)`, or `spec=` / `autospec=True` so a typo raises.
- `assertAlmostEqual(a, b)` defaults to 7 decimal places — fine for floats, far too loose when the values are seconds or money.
- In the implementation diff, `except Exception: pass` and bare `except:` are the silent-failure sites. A test asserting only "no exception raised" cannot tell them from success.
