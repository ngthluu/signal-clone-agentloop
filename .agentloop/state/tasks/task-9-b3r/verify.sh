#!/usr/bin/env bash
set -euo pipefail

# task-9-b3r verify: proves testHandleLiveRecordUpdatesLastActivityAtOnKnownPeer is
# committed in ConversationListStoreTests and that all 7 tests in that suite pass.
# Runs from REPO_ROOT (the global aggregator invokes per-task verify.sh with cd REPO_ROOT).

TEST_PATH="mac-app/Tests/ChatAppTests/ConversationListStoreTests.swift"
TARGET="testHandleLiveRecordUpdatesLastActivityAtOnKnownPeer"

fail() { echo "task-9-b3r verify: FAIL"; echo "reason: $*" >&2; exit 1; }

# 1. Committed presence: the test must exist in the committed tree (HEAD), not just the worktree.
git show "HEAD:${TEST_PATH}" 2>/dev/null | grep -q "func ${TARGET}" \
  || fail "${TARGET} not found in committed ${TEST_PATH}"

# 2. Compile + run only the ConversationListStoreTests suite; capture output.
echo "task-9-b3r verify: running swift test --filter ConversationListStoreTests"
if ! OUT="$(cd mac-app && swift test --filter ConversationListStoreTests 2>&1)"; then
  echo "${OUT}" >&2
  fail "swift test --filter ConversationListStoreTests exited non-zero"
fi

# 3. The target test must have run and passed by name.
echo "${OUT}" | grep -q "${TARGET}]' passed" \
  || { echo "${OUT}" >&2; fail "${TARGET} did not pass"; }

# 4. The whole 7-test suite must be green.
echo "${OUT}" | grep -q "Executed 7 tests, with 0 failures" \
  || { echo "${OUT}" >&2; fail "expected 'Executed 7 tests, with 0 failures'"; }

echo "task-9-b3r verify: PASS"
exit 0
