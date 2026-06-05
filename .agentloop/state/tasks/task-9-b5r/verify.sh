#!/usr/bin/env bash
set -euo pipefail

# task-9-b5r verify: proves the production authenticated app path is wired to
# ConversationsView and runs only the scoped Swift test filters for this item.
# Runs from REPO_ROOT.

fail() { echo "task-9-b5r scoped verify: FAIL"; echo "reason: $*" >&2; exit 1; }

SELF_PATH="${BASH_SOURCE[0]}"
RENDERED_FLOW=".agentloop/state/tasks/task-9-b5r/RENDERED-FLOW.md"

# scope-isolation self-guard: blocks live-suite regex references.
if grep -nE 'Live[A-Za-z]*E2ETests' "$SELF_PATH" | grep -v 'scope-isolation self-guard' >/tmp/task-9-b5r-live-suite-refs.txt; then # scope-isolation self-guard
  cat /tmp/task-9-b5r-live-suite-refs.txt >&2
  fail "task-local verifier must not reference live end-to-end suites"
fi

# scope-isolation self-guard: every test invocation must include --filter.
if grep -n 'swift test' "$SELF_PATH" | grep -v -- '--filter' | grep -v 'scope-isolation self-guard' >/tmp/task-9-b5r-bare-test-refs.txt; then # scope-isolation self-guard
  cat /tmp/task-9-b5r-bare-test-refs.txt >&2
  fail "task-local verifier must keep Swift tests scoped with filters"
fi

# scope-isolation self-guard: blocks repo/global aggregator invocations.
if grep -nE '\.agentloop/verify\.sh|exec[[:space:]].*verify\.sh' "$SELF_PATH" | grep -v 'scope-isolation self-guard' >/tmp/task-9-b5r-aggregator-refs.txt; then # scope-isolation self-guard
  cat /tmp/task-9-b5r-aggregator-refs.txt >&2
  fail "task-local verifier must not invoke an aggregator"
fi

# scope-isolation self-guard: blocks live-backend URL references.
LIVE_BACKEND_VAR='CHATAPP_LIVE_BACKEND_''URL'
if grep -n "$LIVE_BACKEND_VAR" "$SELF_PATH" | grep -v 'scope-isolation self-guard' >/tmp/task-9-b5r-live-backend-url-refs.txt; then # scope-isolation self-guard
  cat /tmp/task-9-b5r-live-backend-url-refs.txt >&2
  fail "task-local verifier must not set or require a live backend"
fi

require_file_contains() {
  local path="$1"
  local pattern="$2"
  local reason="$3"

  grep -Fq "$pattern" "$path" || fail "$reason"
}

require_file_not_contains() {
  local path="$1"
  local pattern="$2"
  local reason="$3"

  if grep -Fq "$pattern" "$path"; then
    fail "$reason"
  fi
}

run_swift_test_suite() {
  local suite="$1"
  local expected_count="$2"
  local output_path="/tmp/task-9-b5r-${suite}.txt"

  echo "task-9-b5r scoped verify: running swift test --filter ${suite}"
  if ! (cd mac-app && swift test --filter "$suite") 2>&1 | tee "$output_path"; then
    fail "swift test --filter ${suite} exited non-zero"
  fi

  grep -Fq "Executed ${expected_count} tests, with 0 failures" "$output_path" \
    || fail "${suite} must execute ${expected_count} tests with 0 failures"
  grep -Fq "Selected tests" "$output_path" \
    || fail "${suite} output must prove swift selected a scoped test filter"
  if grep -nE "Test Suite 'Live[A-Za-z]*E2ETests'" "$output_path" >/tmp/task-9-b5r-${suite}-live-execution.txt; then # scope-isolation self-guard
    cat /tmp/task-9-b5r-${suite}-live-execution.txt >&2
    fail "${suite} output must not execute live end-to-end suites"
  fi
}

CHAT_APP="mac-app/Sources/ChatApp/ChatAppApp.swift"
APP_ROOT="mac-app/Sources/ChatApp/App/AppRootView.swift"
CONVERSATIONS="mac-app/Sources/ChatApp/Views/ConversationsView.swift"
CONVERSATION_LIST="mac-app/Sources/ChatApp/Views/ConversationListView.swift"
CONVERSATION_VIEW="mac-app/Sources/ChatApp/Views/ConversationView.swift"

git show "HEAD:${RENDERED_FLOW}" >/dev/null 2>&1 \
  || fail "committed ${RENDERED_FLOW} is required"

echo "task-9-b5r scoped verify: running swift build"
(cd mac-app && swift build)

echo "task-9-b5r scoped verify: running swift build --build-tests"
(cd mac-app && swift build --build-tests)

require_file_contains "$CHAT_APP" "AppRootView(" \
  "ChatAppApp.swift must construct AppRootView("

require_file_contains "$APP_ROOT" "ConversationsView(" \
  "AppRootView.swift authenticated path must render ConversationsView("
require_file_contains "$APP_ROOT" "listStore:" \
  "AppRootView.swift ConversationsView construction must pass listStore:"
require_file_contains "$APP_ROOT" "dmCoordinator:" \
  "AppRootView.swift ConversationsView construction must pass dmCoordinator:"
require_file_not_contains "$APP_ROOT" "MainView(" \
  "AppRootView.swift must not construct MainView("
require_file_not_contains "$APP_ROOT" "RootView(" \
  "AppRootView.swift must not construct RootView("

require_file_contains "$CONVERSATIONS" "NavigationSplitView" \
  "ConversationsView.swift must use NavigationSplitView"
require_file_contains "$CONVERSATIONS" "ConversationListView(store:" \
  "ConversationsView.swift sidebar must render ConversationListView(store:"
perl -0777 -ne 'exit(/\.task\s*\{[^}]*listStore\.refresh\(\)[^}]*listStore\.subscribe\(\)[^}]*dmCoordinator\.publishOwnPrekey\(\)/s ? 0 : 1)' "$CONVERSATIONS" \
  || fail "ConversationsView.swift .task must refresh, subscribe, and publish the prekey"
require_file_contains "$CONVERSATIONS" "dmCoordinator.startConversation" \
  "ConversationsView.swift selection must call dmCoordinator.startConversation"

require_file_contains "$CONVERSATION_LIST" 'List(selection: $store.selectedPeerUsername)' \
  "ConversationListView.swift must bind List selection to store.selectedPeerUsername"

require_file_contains "$CONVERSATION_VIEW" "ScrollView" \
  "ConversationView.swift detail must be scrollable"
require_file_contains "$CONVERSATION_VIEW" "ForEach(coordinator.messages)" \
  "ConversationView.swift must render scroll-back history from coordinator.messages"

run_swift_test_suite "ConversationsViewWiringTests" 4
run_swift_test_suite "ConversationListModelTests" 4
run_swift_test_suite "ConversationListStoreTests" 7

echo "task-9-b5r scoped verify: PASS"
exit 0
