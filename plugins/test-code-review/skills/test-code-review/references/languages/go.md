# Go — test review patterns

- Test functions: `func Test*(t *testing.T)`. Files: `*_test.go`.
- Watch for: `t.Skip()` added without justification; `t.Fatal` → `t.Error` (the test no longer stops at the first failure, so later assertions run against broken state); error returns not checked.
