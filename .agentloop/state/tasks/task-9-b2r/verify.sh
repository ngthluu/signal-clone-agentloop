#!/usr/bin/env bash
set -euo pipefail

# task-9-b2r verify: proves testConversationListContainsAndEmptyUpsertRoundTrip is
# committed in ConversationListModelTests and that all 4 tests in that suite pass.
# Runs from REPO_ROOT (the global aggregator invokes per-task verify.sh with cd REPO_ROOT).

TEST_PATH="mac-app/Tests/ChatAppTests/ConversationListModelTests.swift"
TARGET="testConversationListContainsAndEmptyUpsertRoundTrip"

fail() { echo "task-9-b2r verify: FAIL"; echo "reason: $*" >&2; exit 1; }

# 1. Committed presence: the test must exist in the committed tree (HEAD), not just the worktree.
git show "HEAD:${TEST_PATH}" 2>/dev/null | grep -q "func ${TARGET}" \
  || fail "${TARGET} not found in committed ${TEST_PATH}"

# 2. Compile + run only the ConversationListModelTests suite; capture output.
echo "task-9-b2r verify: running swift test --filter ConversationListModelTests"
if ! OUT="$(cd mac-app && swift test --filter ConversationListModelTests 2>&1)"; then
  echo "${OUT}" >&2
  fail "swift test --filter ConversationListModelTests exited non-zero"
fi

# 3. The target test must have run and passed by name.
echo "${OUT}" | grep -q "${TARGET}]' passed" \
  || { echo "${OUT}" >&2; fail "${TARGET} did not pass"; }

# 4. The whole 4-test suite must be green.
echo "${OUT}" | grep -q "Executed 4 tests, with 0 failures" \
  || { echo "${OUT}" >&2; fail "expected 'Executed 4 tests, with 0 failures'"; }

echo "task-9-b2r verify: PASS"
exit 0
