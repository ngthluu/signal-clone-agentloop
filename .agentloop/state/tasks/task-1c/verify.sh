#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "task-1c verify: FAIL"
  echo "reason: $*" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
BACKEND_DIR="$REPO_ROOT/backend"

if [[ ! -f "$BACKEND_DIR/Cargo.toml" ]]; then
  fail "backend Cargo.toml not found at $BACKEND_DIR"
fi

echo "task-1c verify: running cargo build"
(
  cd "$BACKEND_DIR"
  cargo build
) || fail "cargo build failed"

echo "task-1c verify: running cargo test"
test_output="$(
  cd "$BACKEND_DIR"
  cargo test 2>&1
)" || {
  printf '%s\n' "$test_output"
  fail "cargo test failed"
}

printf '%s\n' "$test_output"

if grep -q "test result: FAILED" <<<"$test_output"; then
  fail "cargo test reported a failed test result"
fi

if grep -q "error\\[" <<<"$test_output"; then
  fail "cargo test output contained a Rust compiler error"
fi

required_tests=(
  "register_stores_only_public_account_fields"
  "register_rejects_duplicate_username_without_second_row"
  "register_rejects_malformed_input"
  "migration_creates_users_table_with_only_public_account_columns"
  "schema_dump_prints_schema_sample_row_and_rejects_private_material"
)

for test_name in "${required_tests[@]}"; do
  if grep -Eq "^test ${test_name} \.\.\. FAILED$" <<<"$test_output"; then
    fail "acceptance-critical test failed: $test_name"
  fi

  if ! grep -Eq "^test ${test_name} \.\.\. ok$" <<<"$test_output"; then
    fail "acceptance-critical test did not execute and pass: $test_name"
  fi
done

if ! grep -Eq "test result: ok\. [0-9]+ passed; 0 failed;" <<<"$test_output"; then
  fail "cargo test output did not report 0 failures"
fi

echo "task-1c verify: PASS"
