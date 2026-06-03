#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
MAC_APP_DIR="$REPO_ROOT/mac-app"

IDENTITY_TESTS=(
  "testIdentityRoundTripsThroughKeychainWithStablePublicKey"
  "testPrivateKeyIsReachableViaKeychainAPI"
  "testDeletingKeychainItemMakesIdentityUnrecoverable"
  "testIdentityExposesNoRawPrivateBytes"
)

fail() {
  echo "task-1b verify: FAIL"
  exit 1
}

echo "task-1b verify: building ChatApp"
cd "$MAC_APP_DIR"

if ! swift build; then
  echo "swift build failed"
  fail
fi

echo "task-1b verify: running identity tests"
if ! TEST_OUTPUT="$(swift test 2>&1)"; then
  printf '%s\n' "$TEST_OUTPUT"
  echo "swift test failed"
  fail
fi

printf '%s\n' "$TEST_OUTPUT"

if ! grep -Eq "Test Suite 'All tests' passed|Test run .* passed" <<<"$TEST_OUTPUT"; then
  echo "swift test output did not report a passing test run"
  fail
fi

if ! grep -q "0 failures" <<<"$TEST_OUTPUT"; then
  echo "swift test output did not report 0 failures"
  fail
fi

for test_name in "${IDENTITY_TESTS[@]}"; do
  if ! grep -q "$test_name.*passed" <<<"$TEST_OUTPUT"; then
    echo "missing passing identity test: $test_name"
    fail
  fi

  if grep -q "$test_name.*failed" <<<"$TEST_OUTPUT"; then
    echo "identity test failed: $test_name"
    fail
  fi
done

echo "task-1b verify: PASS"
exit 0
