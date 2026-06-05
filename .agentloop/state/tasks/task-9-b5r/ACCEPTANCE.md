# task-9-b5r Acceptance Evidence

Verified from repository root with the committed task-local gate:

```sh
bash .agentloop/state/tasks/task-9-b5r/verify.sh
```

## Gate Result

- Verified commit before this evidence artifact was authored: `5cbc334`.
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

## Production Wiring Evidence

`mac-app/Sources/ChatApp/App/AppRootView.swift:31` enters the registered path,
`mac-app/Sources/ChatApp/App/AppRootView.swift:32` enters the authenticated path,
and the direct branch renders `ConversationsView` at
`mac-app/Sources/ChatApp/App/AppRootView.swift:50`, passing
`listStore:` at `mac-app/Sources/ChatApp/App/AppRootView.swift:51` and
`dmCoordinator:` at `mac-app/Sources/ChatApp/App/AppRootView.swift:52`.

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

- every `swift test` invocation includes `--filter` on the same line;
- it contains no `Live[A-Za-z]*E2ETests` suite reference outside its self-guard;
- it does not invoke the repo-root `.agentloop/verify.sh` aggregator.

This acceptance is intentionally pinned to the task-local gate, not the
repo-root aggregator.
