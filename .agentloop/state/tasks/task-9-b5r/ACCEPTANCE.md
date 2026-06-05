# task-9-b5r Acceptance Evidence

Verified from the repository root at HEAD `f66b789` with the task-local scoped
gate:

```sh
bash .agentloop/state/tasks/task-9-b5r/verify.sh
```

## Gate Result

- PASS line observed: `task-9-b5r scoped verify: PASS`.
- `swift build`: exited 0.
- `swift build --build-tests`: exited 0.
- This item's acceptance is pinned to the task-local scoped gate above.

## Targeted Test Evidence

The task-local gate ran only the accepted scoped test filters:

```sh
swift test --filter ConversationsViewWiringTests
swift test --filter ConversationListModelTests
swift test --filter ConversationListStoreTests
```

Observed filtered tallies:

- `ConversationsViewWiringTests`: `Selected tests`; `Executed 4 tests, with 0 failures`.
- `ConversationListModelTests`: `Selected tests`; `Executed 4 tests, with 0 failures`.
- `ConversationListStoreTests`: `Selected tests`; `Executed 7 tests, with 0 failures`.

The gate self-guards against bare `swift test`, `CHATAPP_LIVE_BACKEND_URL`,
repo-root aggregator invocation, and live end-to-end suite execution in the
filtered output.

## Production Wiring Evidence

`mac-app/Sources/ChatApp/App/AppRootView.swift:31` enters the registered path,
`mac-app/Sources/ChatApp/App/AppRootView.swift:32` enters the authenticated
path, and the direct-message branch renders `ConversationsView` at
`mac-app/Sources/ChatApp/App/AppRootView.swift:50`, passing `listStore:` at
`mac-app/Sources/ChatApp/App/AppRootView.swift:51` and `dmCoordinator:` at
`mac-app/Sources/ChatApp/App/AppRootView.swift:52`.

The rendered shell is `NavigationSplitView` at
`mac-app/Sources/ChatApp/Views/ConversationsView.swift:8`, with sidebar
`ConversationListView(store: listStore)` at
`mac-app/Sources/ChatApp/Views/ConversationsView.swift:9` and the detail
`ConversationView` path beginning at
`mac-app/Sources/ChatApp/Views/ConversationsView.swift:12`.

The complete production flow and manual reproduction proof are cross-referenced
in `.agentloop/state/tasks/task-9-b5r/RENDERED-FLOW.md`.

## Why Not The Repo-Root Aggregator

The repo-root `.agentloop/verify.sh` is a global aggregator, not this item's
acceptance gate. It collects per-task `verify.sh` scripts in sorted order at
`.agentloop/verify.sh:12-15`, runs each one at `.agentloop/verify.sh:17-21`,
and exits on the first per-task failure at `.agentloop/verify.sh:21-24`.

The rejection run died at sibling task `task-8` before reaching this item. That
is outside `task-9-b5r` ownership and outside this builder item's allowed edit
scope.

Sibling live-E2E blockers remain documented by these current line references:

- `.agentloop/state/tasks/task-8/verify.sh:210` exports
  `CHATAPP_LIVE_BACKEND_URL`; `.agentloop/state/tasks/task-8/verify.sh:218`
  invokes `swift test` for `LiveOfflineDeliveryE2ETests`.
- `.agentloop/state/tasks/task-9/verify.sh:151` exports
  `CHATAPP_LIVE_BACKEND_URL`; `.agentloop/state/tasks/task-9/verify.sh:161`
  invokes `swift test` for `LiveConversationsE2ETests` alongside sibling-owned
  filters.

Those sibling live-backend gates can trigger live E2E flakiness or timeouts
under the repo-root aggregator. This item's acceptance criteria explicitly
forbid replicating that pattern: `task-9-b5r` must use only targeted
`swift test --filter <name>` commands for `ConversationsViewWiringTests`,
`ConversationListModelTests`, and `ConversationListStoreTests`, and must not run
bare `swift test`.
