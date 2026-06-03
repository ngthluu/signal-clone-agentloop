#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
MAC_APP_DIR="$REPO_ROOT/mac-app"

REGISTRATION_TEST="testResolveReturnsRegistrationWhenNoAccountExists"
MAIN_TEST="testResolveReturnsMainWhenAccountExists"

fail() {
  echo "task-1a verify: FAIL"
  exit 1
}

echo "task-1a verify: building ChatApp"
cd "$MAC_APP_DIR"

if ! swift build; then
  echo "swift build failed"
  fail
fi

echo "task-1a verify: running routing tests"
if ! TEST_OUTPUT="$(swift test 2>&1)"; then
  printf '%s\n' "$TEST_OUTPUT"
  echo "swift test failed"
  fail
fi

printf '%s\n' "$TEST_OUTPUT"

if ! printf '%s\n' "$TEST_OUTPUT" | grep -Eq "Test Suite 'All tests' passed|Test run .* passed"; then
  echo "swift test output did not report a passing test run"
  fail
fi

if ! printf '%s\n' "$TEST_OUTPUT" | grep -q "with 0 failures"; then
  echo "swift test output did not report 0 failures"
  fail
fi

if ! printf '%s\n' "$TEST_OUTPUT" | grep -q "$REGISTRATION_TEST.*passed"; then
  echo "missing passing routing test: $REGISTRATION_TEST"
  fail
fi

if printf '%s\n' "$TEST_OUTPUT" | grep -q "$REGISTRATION_TEST.*failed"; then
  echo "routing test failed: $REGISTRATION_TEST"
  fail
fi

if ! printf '%s\n' "$TEST_OUTPUT" | grep -q "$MAIN_TEST.*passed"; then
  echo "missing passing routing test: $MAIN_TEST"
  fail
fi

if printf '%s\n' "$TEST_OUTPUT" | grep -q "$MAIN_TEST.*failed"; then
  echo "routing test failed: $MAIN_TEST"
  fail
fi

echo "task-1a verify: running non-fatal launch smoke check"
if "$SCRIPT_DIR/launch_smoke.sh"; then
  echo "task-1a verify: launch smoke completed"
else
  echo "task-1a verify: launch smoke failed or skipped; deterministic checks still decide verdict"
fi

echo "task-1a verify: PASS"
exit 0
