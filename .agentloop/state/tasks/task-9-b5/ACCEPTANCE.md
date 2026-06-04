# task-9-b5 Acceptance Evidence

Captured on 2026-06-04 23:09 +07 against commit `6f43eac` in worktree
`task-9-b5-b3`.

This item is judged only by deterministic targeted commands for task-9-b5. The
repo-root global `bash verify.sh` aggregator and any `Live*E2ETests` are not the
gate for this item.

## Deterministic Command Evidence

### `cd mac-app && swift build`

Exit status: 0.

```text
Building for debugging...
[0/6] Write ChatApp-entitlement.plist
[0/6] Write sources
[2/6] Write swift-version--58304C5D6DBC2206.txt
[4/49] Compiling ChatApp DMCoordinator.swift
[16/53] Compiling ChatApp AppRootView.swift
[21/53] Compiling ChatApp ConversationListModel.swift
[22/53] Compiling ChatApp ConversationListStore.swift
[47/53] Compiling ChatApp ConversationListView.swift
[48/53] Compiling ChatApp ConversationView.swift
[49/53] Compiling ChatApp ConversationsView.swift
[50/53] Compiling ChatApp GroupView.swift
[50/53] Write Objects.LinkFileList
[51/53] Linking ChatApp
[52/53] Applying ChatApp
Build complete! (7.21s)
```

### `cd mac-app && swift build --build-tests`

Exit status: 0.

```text
Building for debugging...
[5/46] Emitting module ChatAppTests
[32/50] Compiling ChatAppTests ConversationListModelTests.swift
[33/50] Compiling ChatAppTests ConversationListStoreTests.swift
[34/50] Compiling ChatAppTests ConversationsViewWiringTests.swift
[47/50] Compiling ChatAppTests LiveGroupE2ETests.swift
[49/52] Emitting module ChatAppPackageTests
[50/52] Compiling ChatAppPackageTests runner.swift
[50/52] Write Objects.LinkFileList
[51/52] Linking ChatAppPackageTests
Build complete! (8.94s)
```

### `bash .agentloop/state/tasks/task-9-b5/verify.sh`

Exit status: 0. This is the b1-strengthened task-local gate. It builds, asserts
the structural wiring, and runs the three targeted offline suites with expected
counts.

```text
Build complete! (0.12s)
Build complete! (0.08s)
Test Suite 'ConversationsViewWiringTests' passed at 2026-06-04 23:09:04.552.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.099 (0.099) seconds
Test Suite 'ConversationListModelTests' passed at 2026-06-04 23:09:05.024.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'ConversationListStoreTests' passed at 2026-06-04 23:09:05.645.
	 Executed 7 tests, with 0 failures (0 unexpected) in 0.149 (0.150) seconds
task-9-b5 wiring verify: PASS
```

### `cd mac-app && swift test --filter ConversationsViewWiringTests`

Exit status: 0.

```text
Test Suite 'ConversationsViewWiringTests' started at 2026-06-04 23:09:13.857.
Test Case '-[ChatAppTests.ConversationsViewWiringTests testLiveRecordBumpsSidebarList]' passed (0.019 seconds).
Test Case '-[ChatAppTests.ConversationsViewWiringTests testSelectingConversationLoadsFullDecryptedHistory]' passed (0.028 seconds).
Test Case '-[ChatAppTests.ConversationsViewWiringTests testSidebarOrdersConversationsMostRecentFirst]' passed (0.011 seconds).
Test Case '-[ChatAppTests.ConversationsViewWiringTests testTaskPublishesOwnPrekey]' passed (0.021 seconds).
Test Suite 'ConversationsViewWiringTests' passed at 2026-06-04 23:09:13.937.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.079 (0.080) seconds
```

### `cd mac-app && swift test --filter ConversationListModelTests`

Exit status: 0.

```text
Test Suite 'ConversationListModelTests' started at 2026-06-04 23:09:13.665.
Test Case '-[ChatAppTests.ConversationListModelTests testConversationListContainsAndEmptyUpsertRoundTrip]' passed (0.000 seconds).
Test Case '-[ChatAppTests.ConversationListModelTests testPeerIdReturnsOtherPartyForInboundAndOutboundRecords]' passed (0.000 seconds).
Test Case '-[ChatAppTests.ConversationListModelTests testSortedOrdersMostRecentFirstAndTiesByUsername]' passed (0.000 seconds).
Test Case '-[ChatAppTests.ConversationListModelTests testUpsertInsertsBumpsToNewerActivityAndNeverRegresses]' passed (0.000 seconds).
Test Suite 'ConversationListModelTests' passed at 2026-06-04 23:09:13.666.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
```

### `cd mac-app && swift test --filter ConversationListStoreTests`

Exit status: 0.

```text
Test Suite 'ConversationListStoreTests' started at 2026-06-04 23:09:14.129.
Test Case '-[ChatAppTests.ConversationListStoreTests testHandleLiveRecordForKnownPeerBumpsAndDoesNotFetchAgain]' passed (0.017 seconds).
Test Case '-[ChatAppTests.ConversationListStoreTests testHandleLiveRecordForUnknownPeerRefreshesOnce]' passed (0.013 seconds).
Test Case '-[ChatAppTests.ConversationListStoreTests testHandleLiveRecordUpdatesLastActivityAtOnKnownPeer]' passed (0.011 seconds).
Test Case '-[ChatAppTests.ConversationListStoreTests testRefreshIncludesInboundOnlyPeerReturnedByBackend]' passed (0.011 seconds).
Test Case '-[ChatAppTests.ConversationListStoreTests testRefreshMapsRecordsAndSortsMostRecentFirst]' passed (0.011 seconds).
Test Case '-[ChatAppTests.ConversationListStoreTests testSelectedPeerUsernameRoundTrips]' passed (0.009 seconds).
Test Case '-[ChatAppTests.ConversationListStoreTests testSubscribeConsumesInjectedLiveStream]' passed (0.073 seconds).
Test Suite 'ConversationListStoreTests' passed at 2026-06-04 23:09:14.274.
	 Executed 7 tests, with 0 failures (0 unexpected) in 0.145 (0.145) seconds
```

## Clause to Evidence Map

| Acceptance criterion | Deterministic command | File:line proof |
| --- | --- | --- |
| `swift build` exits 0 | `cd mac-app && swift build` | Build output above: `Build complete! (7.21s)` |
| `swift build --build-tests` exits 0 | `cd mac-app && swift build --build-tests` | Build output above: `Build complete! (8.94s)` |
| AppRootView authenticated path renders `ConversationsView(listStore:dmCoordinator:)`, not `MainView` | `bash .agentloop/state/tasks/task-9-b5/verify.sh` | `mac-app/Sources/ChatApp/App/AppRootView.swift:31` registered branch, `:32` authenticated branch, `:49` direct branch, `:50` `ConversationsView(`, `:51` `listStore: conversationListStore`, `:52` `dmCoordinator: dmCoordinator`; `verify.sh:52-61` asserts `ConversationsView`, `listStore`, `dmCoordinator`, and rejects `MainView(`/`RootView(` |
| `ConversationsView` is a `NavigationSplitView` | `bash .agentloop/state/tasks/task-9-b5/verify.sh` | `mac-app/Sources/ChatApp/Views/ConversationsView.swift:8`; asserted by `verify.sh:63-64` |
| Sidebar renders `ConversationListView` bound to `selectedPeerUsername` | `bash .agentloop/state/tasks/task-9-b5/verify.sh`; `swift test --filter ConversationsViewWiringTests` | `mac-app/Sources/ChatApp/Views/ConversationsView.swift:9`; `mac-app/Sources/ChatApp/Views/ConversationListView.swift:9`; asserted by `verify.sh:65-73`; covered by `mac-app/Tests/ChatAppTests/ConversationsViewWiringTests.swift:21-32` |
| Sidebar lists conversations most-recent-first and live records bump ordering | `swift test --filter ConversationsViewWiringTests`; `swift test --filter ConversationListModelTests`; `swift test --filter ConversationListStoreTests` | Sort call at `mac-app/Sources/ChatApp/Messaging/ConversationListStore.swift:32`; descending timestamp comparison at `mac-app/Sources/ChatApp/Messaging/ConversationListModel.swift:97`; live upsert at `mac-app/Sources/ChatApp/Messaging/ConversationListStore.swift:35-52`; tests at `ConversationsViewWiringTests.swift:21-56`, `ConversationListModelTests.swift:5-78`, `ConversationListStoreTests.swift:18-67` |
| Detail is a scrollable `ConversationView` rendering decrypted history | `bash .agentloop/state/tasks/task-9-b5/verify.sh`; `swift test --filter ConversationsViewWiringTests` | Detail creates `ConversationView` at `mac-app/Sources/ChatApp/Views/ConversationsView.swift:10-20`; history `ScrollView` at `mac-app/Sources/ChatApp/Views/ConversationView.swift:45`; `ForEach(coordinator.messages)` at `ConversationView.swift:47`; asserted by `verify.sh:75-78`; decrypted-history test at `mac-app/Tests/ChatAppTests/ConversationsViewWiringTests.swift:59-101` |
| Selection opens the selected peer's full decrypted history | `bash .agentloop/state/tasks/task-9-b5/verify.sh`; `swift test --filter ConversationsViewWiringTests` | Selection observer at `mac-app/Sources/ChatApp/Views/ConversationsView.swift:41-45`; `dmCoordinator.startConversation(withUsername:)` at `ConversationsView.swift:67`; test at `mac-app/Tests/ChatAppTests/ConversationsViewWiringTests.swift:59-101` |
| Shell startup publishes own prekey | `bash .agentloop/state/tasks/task-9-b5/verify.sh`; `swift test --filter ConversationsViewWiringTests` | `.task` at `mac-app/Sources/ChatApp/Views/ConversationsView.swift:33-37`; asserted by `verify.sh:67-68`; test at `mac-app/Tests/ChatAppTests/ConversationsViewWiringTests.swift:104-115` |
| Targeted suite `ConversationsViewWiringTests` passes 4/4 | `cd mac-app && swift test --filter ConversationsViewWiringTests` | Output above: `Executed 4 tests, with 0 failures`; also invoked by `verify.sh:85` |
| Targeted suite `ConversationListModelTests` passes 4/4 | `cd mac-app && swift test --filter ConversationListModelTests` | Output above: `Executed 4 tests, with 0 failures`; also invoked by `verify.sh:86` |
| Targeted suite `ConversationListStoreTests` passes 7/7 | `cd mac-app && swift test --filter ConversationListStoreTests` | Output above: `Executed 7 tests, with 0 failures`; also invoked by `verify.sh:87` |
| `RENDERED-FLOW.md` exists with accurate file:line refs and manual reproduction steps | `bash .agentloop/state/tasks/task-9-b5/verify.sh`; source line inspection | `.agentloop/state/tasks/task-9-b5/RENDERED-FLOW.md:7-16` production path refs; `:18-27` manual reproduction; `:40-42` provenance |
| Full repo-root `bash verify.sh` is not this item's gate | This document; task-local commands above | The task acceptance explicitly states the full `bash verify.sh` is not the gate because unrelated `LiveGroupE2ETests` flakiness is task-5 territory |

## Out-of-Scope Global Aggregator Rejection

The prior rejection came from the repo-root global aggregator, not from task-9-b5's
deterministic gate. The rejected run is out of scope for this builder item:

```text
task-1d FAILED: LiveGroupE2ETests
testLiveCoordinatorCreatesGroupAndPeerReceivesDecryptedMessage timed out
at LiveGroupE2ETests.swift:46 after 125s
subsequent live suites failed with "Registration request failed"
```

That failure is explicitly outside task-9-b5 acceptance. The parent acceptance
clause states that the full `bash verify.sh` is not this item's gate and is
blocked by unrelated `LiveGroupE2ETests` flakiness in task-5 territory.

Therefore task-9-b5-b3 must be judged on the deterministic targeted commands
recorded above: `swift build`, `swift build --build-tests`, the strengthened
task-local `.agentloop/state/tasks/task-9-b5/verify.sh`, and the three named
`swift test --filter` suites. It must never be judged by the repo-root global
aggregator or by any `Live*E2ETests`.
