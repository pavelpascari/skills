#!/bin/bash
# Entry point for the software-engineering hook tests.
# Usage: bash plugins/software-engineering/hooks/tests/run-tests.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$TESTS_DIR/helpers.sh"

for suite in "$TESTS_DIR"/test-*.sh; do
  [ -r "$suite" ] || continue
  printf '\n%s\n' "$(basename "$suite")"
  # shellcheck disable=SC1090
  . "$suite"
done

printf '\n%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
