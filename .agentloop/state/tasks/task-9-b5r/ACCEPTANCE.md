# task-9-b5r Acceptance Evidence

Verified from the repository root with the committed task-local gate:

```sh
bash .agentloop/state/tasks/task-9-b5r/verify.sh
```

## Gate Result

- Verified commit: `aeeac6d`.
- Gate PASS line: `task-9-b5r scoped verify: PASS`.
- `swift build`: exited 0.
- `swift build --build-tests`: exited 0.

## Targeted Test Evidence

The gate ran only the accepted scoped filters, not a full `swift test`:

```sh
swift test --filter ConversationsViewWiringTests
swift test --filter ConversationListModelTests
swift test --filter ConversationListStoreTests
```

Observed tallies:

- `ConversationsViewWiringTests`: `Executed 4 tests, with 0 failures`.
- `ConversationListModelTests`: `Executed 4 tests, with 0 failures`.
- `ConversationListStoreTests`: `Executed 7 tests, with 0 failures`.

Each filtered run reported `Selected tests`, and the task-local gate rejects any
filtered output that executes a `Live*E2ETests` suite.

## Production Wiring Evidence

`mac-app/Sources/ChatApp/App/AppRootView.swift:31` enters the registered path,
`mac-app/Sources/ChatApp/App/AppRootView.swift:32` enters the authenticated path,
and the direct branch renders `ConversationsView` at
`mac-app/Sources/ChatApp/App/AppRootView.swift:50`, passing `listStore:` at
`mac-app/Sources/ChatApp/App/AppRootView.swift:51` and `dmCoordinator:` at
`mac-app/Sources/ChatApp/App/AppRootView.swift:52`.

The rendered shell is `NavigationSplitView` at
`mac-app/Sources/ChatApp/Views/ConversationsView.swift:8`, with the sidebar
`ConversationListView(store: listStore)` at
`mac-app/Sources/ChatApp/Views/ConversationsView.swift:9` and the detail
`ConversationView` path beginning at
`mac-app/Sources/ChatApp/Views/ConversationsView.swift:12`.

The complete production flow and manual reproduction proof are cross-referenced
in `.agentloop/state/tasks/task-9-b5r/RENDERED-FLOW.md`.

## Scope Confirmation

`.agentloop/state/tasks/task-9-b5r/verify.sh` is a scoped gate:

- every `swift test` invocation includes `--filter`;
- it self-guards against unfiltered `swift test` references;
- it never sets or requires `CHATAPP_LIVE_BACKEND_URL`;
- it rejects `Live*E2ETests` references and live-suite execution in filtered
  output;
- it does not invoke the repo-root `.agentloop/verify.sh` aggregator.

This item's acceptance is pinned to the task-local scoped gate per the task
acceptance criteria.

## Why Not The Repo-Root Aggregator

The repo-root `.agentloop/verify.sh` iterates every per-task `verify.sh` in
sorted order and exits on the first failure. The previous rejection was caused
by unrelated live end-to-end flakiness in a sibling task, historically
`task-1d`, before the aggregator reached this item's scoped gate.

The same global-gate failure mode still exists outside this item's ownership:

- `.agentloop/state/tasks/task-8/verify.sh:210` sets
  `CHATAPP_LIVE_BACKEND_URL`, and `.agentloop/state/tasks/task-8/verify.sh:218`
  runs bare `swift test`.
- `.agentloop/state/tasks/task-9/verify.sh:151` sets
  `CHATAPP_LIVE_BACKEND_URL`, and `.agentloop/state/tasks/task-9/verify.sh:161`
  runs bare `swift test`.
- `.agentloop/state/tasks/task-9/verify.sh:202` requires the live suite not to
  be skipped, so that sibling item cannot be scoped away by this task.

Those live-backend dominoes can trigger `LiveGroupE2ETests` flakiness or
timeouts under the repo-root aggregator. They are owned by their own task items.
This section is read-only documentation of that sibling-task context; no sibling
verify script, application source, global backlog file, or repo-root aggregator
is changed here.
