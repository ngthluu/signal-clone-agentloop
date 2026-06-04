#!/usr/bin/env bash
set -euo pipefail

# task-9-b5 verify: proves the production authenticated app path is wired to
# ConversationsView and the Swift package still builds with tests.
# Runs from REPO_ROOT (the global aggregator invokes per-task verify.sh with cd REPO_ROOT).

fail() { echo "task-9-b5 wiring verify: FAIL"; echo "reason: $*" >&2; exit 1; }

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

CHAT_APP="mac-app/Sources/ChatApp/ChatAppApp.swift"
APP_ROOT="mac-app/Sources/ChatApp/App/AppRootView.swift"
CONVERSATIONS="mac-app/Sources/ChatApp/Views/ConversationsView.swift"
CONVERSATION_LIST="mac-app/Sources/ChatApp/Views/ConversationListView.swift"
CONVERSATION_VIEW="mac-app/Sources/ChatApp/Views/ConversationView.swift"

cd mac-app
swift build
swift build --build-tests
cd ..

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

if rg -n "OfflineSyncCoordinator|LocalMessageStore" mac-app/Sources >/tmp/task-9-b5-stale-source-refs.txt; then
  cat /tmp/task-9-b5-stale-source-refs.txt >&2
  fail "Sources must not reference OfflineSyncCoordinator or LocalMessageStore"
fi

echo "task-9-b5 wiring verify: PASS"
exit 0
