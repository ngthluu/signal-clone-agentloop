# task-9-b5 Acceptance Evidence

Captured on 2026-06-05 09:20 +07 against commit `7ec1e6d` in worktree
`task-9-b5-b3`.

This item is judged only by deterministic targeted commands for task-9-b5. The
repo-root global `bash verify.sh` aggregator and any `Live*E2ETests` are not the
gate for this item.

## Deterministic Command Evidence

### `cd mac-app && swift build`

Exit status: 0.

```text
Building for debugging...
[0/6] Write sources
[1/6] Write ChatApp-entitlement.plist
[2/6] Write swift-version--58304C5D6DBC2206.txt
[4/49] Compiling ChatApp KeychainStore.swift
[7/49] Compiling ChatApp ConversationListModel.swift
[8/49] Compiling ChatApp ConversationListStore.swift
[19/53] Compiling ChatApp DMCoordinator.swift
[31/53] Compiling ChatApp AppRootView.swift
[45/53] Compiling ChatApp ChatAppApp.swift
[47/53] Compiling ChatApp ConversationListView.swift
[48/53] Compiling ChatApp ConversationView.swift
[49/53] Compiling ChatApp ConversationsView.swift
[51/53] Linking ChatApp
[52/53] Applying ChatApp
Build complete! (6.60s)
```

### `cd mac-app && swift build --build-tests`

Exit status: 0.

```text
[0/1] Planning build
Building for debugging...
[18/50] Compiling ChatAppTests ComposerWiringTests.swift
[19/50] Compiling ChatAppTests ConversationListModelTests.swift
[20/50] Compiling ChatAppTests ConversationListStoreTests.swift
[21/50] Compiling ChatAppTests ConversationsViewWiringTests.swift
[47/50] Compiling ChatAppTests LiveGroupE2ETests.swift
[49/52] Compiling ChatAppPackageTests runner.swift
[50/52] Emitting module ChatAppPackageTests
[51/52] Linking ChatAppPackageTests
Build complete! (10.08s)
```

### `bash .agentloop/state/tasks/task-9-b5/verify.sh`

Exit status: 0. This is the b1-strengthened task-local gate. It builds, asserts
the production wiring, self-checks that it does not invoke the global aggregator
or any `Live*E2ETests`, and runs the three targeted offline suites with expected
counts.

```text
Build complete! (0.13s)
Build complete! (0.08s)
Test Suite 'ConversationsViewWiringTests' passed at 2026-06-05 09:20:40.099.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.109 (0.109) seconds
Test Suite 'ConversationListModelTests' passed at 2026-06-05 09:20:40.614.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'ConversationListStoreTests' passed at 2026-06-05 09:20:41.265.
	 Executed 7 tests, with 0 failures (0 unexpected) in 0.147 (0.147) seconds
task-9-b5 wiring verify: PASS
```

### `cd mac-app && swift test --filter ConversationsViewWiringTests`

Exit status: 0.

```text
Test Suite 'ConversationsViewWiringTests' started at 2026-06-05 09:20:45.500.
Test Case '-[ChatAppTests.ConversationsViewWiringTests testLiveRecordBumpsSidebarList]' passed (0.020 seconds).
Test Case '-[ChatAppTests.ConversationsViewWiringTests testSelectingConversationLoadsFullDecryptedHistory]' passed (0.030 seconds).
Test Case '-[ChatAppTests.ConversationsViewWiringTests testSidebarOrdersConversationsMostRecentFirst]' passed (0.012 seconds).
Test Case '-[ChatAppTests.ConversationsViewWiringTests testTaskPublishesOwnPrekey]' passed (0.022 seconds).
Test Suite 'ConversationsViewWiringTests' passed at 2026-06-05 09:20:45.585.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.084 (0.085) seconds
```

### `cd mac-app && swift test --filter ConversationListModelTests`

Exit status: 0.

```text
Test Suite 'ConversationListModelTests' started at 2026-06-05 09:20:48.965.
Test Case '-[ChatAppTests.ConversationListModelTests testConversationListContainsAndEmptyUpsertRoundTrip]' passed (0.000 seconds).
Test Case '-[ChatAppTests.ConversationListModelTests testPeerIdReturnsOtherPartyForInboundAndOutboundRecords]' passed (0.000 seconds).
Test Case '-[ChatAppTests.ConversationListModelTests testSortedOrdersMostRecentFirstAndTiesByUsername]' passed (0.000 seconds).
Test Case '-[ChatAppTests.ConversationListModelTests testUpsertInsertsBumpsToNewerActivityAndNeverRegresses]' passed (0.000 seconds).
Test Suite 'ConversationListModelTests' passed at 2026-06-05 09:20:48.966.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
```

### `cd mac-app && swift test --filter ConversationListStoreTests`

Exit status: 0.

```text
Test Suite 'ConversationListStoreTests' started at 2026-06-05 09:20:52.627.
Test Case '-[ChatAppTests.ConversationListStoreTests testHandleLiveRecordForKnownPeerBumpsAndDoesNotFetchAgain]' passed (0.018 seconds).
Test Case '-[ChatAppTests.ConversationListStoreTests testHandleLiveRecordForUnknownPeerRefreshesOnce]' passed (0.012 seconds).
Test Case '-[ChatAppTests.ConversationListStoreTests testHandleLiveRecordUpdatesLastActivityAtOnKnownPeer]' passed (0.011 seconds).
Test Case '-[ChatAppTests.ConversationListStoreTests testRefreshIncludesInboundOnlyPeerReturnedByBackend]' passed (0.011 seconds).
Test Case '-[ChatAppTests.ConversationListStoreTests testRefreshMapsRecordsAndSortsMostRecentFirst]' passed (0.010 seconds).
Test Case '-[ChatAppTests.ConversationListStoreTests testSelectedPeerUsernameRoundTrips]' passed (0.010 seconds).
Test Case '-[ChatAppTests.ConversationListStoreTests testSubscribeConsumesInjectedLiveStream]' passed (0.071 seconds).
Test Suite 'ConversationListStoreTests' passed at 2026-06-05 09:20:52.772.
	 Executed 7 tests, with 0 failures (0 unexpected) in 0.144 (0.145) seconds
```

## Clause to Command Map

| # | Acceptance criterion | Deterministic command | Current file:line proof |
| --- | --- | --- | --- |
| 1 | `cd mac-app && swift build` exits 0 and `swift build --build-tests` exits 0. | `cd mac-app && swift build`; `cd mac-app && swift build --build-tests` | Captures above both end in `Build complete!` with exit status 0. |
| 2 | `AppRootView` authenticated path renders `ConversationsView(listStore:dmCoordinator:)`, not `MainView`. | `bash .agentloop/state/tasks/task-9-b5/verify.sh` | `mac-app/Sources/ChatApp/App/AppRootView.swift:31` registered branch, `:32` authenticated branch, `:49` direct branch, `:50` `ConversationsView(`, `:51` `listStore: conversationListStore`, `:52` `dmCoordinator: dmCoordinator`; `verify.sh:65-73` asserts `ConversationsView`, `listStore`, `dmCoordinator`, and rejects `MainView(`/`RootView(`. |
| 3 | `ConversationsView` is a `NavigationSplitView` with `ConversationListView` sidebar bound to `selectedPeerUsername` and scrollable `ConversationView` detail. | `bash .agentloop/state/tasks/task-9-b5/verify.sh`; `cd mac-app && swift test --filter ConversationsViewWiringTests` | `ConversationsView.swift:8` `NavigationSplitView`, `:9` sidebar `ConversationListView(store: listStore)`, `:12-20` detail `ConversationView`; `ConversationListView.swift:9` `List(selection: $store.selectedPeerUsername)` and `:10` `ForEach(store.conversations)`; `ConversationView.swift:45` `ScrollView`, `:47` `ForEach(coordinator.messages)`; `verify.sh:76-90` asserts these structural clauses. |
| 4 | Targeted tests pass: `ConversationsViewWiringTests` 4/4, `ConversationListModelTests` 4/4, `ConversationListStoreTests` 7/7. | `cd mac-app && swift test --filter ConversationsViewWiringTests`; `cd mac-app && swift test --filter ConversationListModelTests`; `cd mac-app && swift test --filter ConversationListStoreTests`; also `bash .agentloop/state/tasks/task-9-b5/verify.sh` | Captures above show `Executed 4 tests, with 0 failures`, `Executed 4 tests, with 0 failures`, and `Executed 7 tests, with 0 failures`; `verify.sh:98-100` runs the same suites with expected counts; ordering tests live at `ConversationsViewWiringTests.swift:21-56`, `ConversationListModelTests.swift:5-78`, and `ConversationListStoreTests.swift:18-145`. |
| 5 | `RENDERED-FLOW.md` is committed with accurate file:line refs and manual reproduction steps. | `bash .agentloop/state/tasks/task-9-b5/verify.sh`; source line inspection | `.agentloop/state/tasks/task-9-b5/RENDERED-FLOW.md:7-16` production path refs, `:18-27` manual reproduction, `:29-38` deterministic commands, `:40-42` provenance. |
| 6 | The full repo-root `bash verify.sh` is not the gate for this item. | This task-local evidence file; `bash .agentloop/state/tasks/task-9-b5/verify.sh` | `verify.sh:10-20` self-guards against `Live*E2ETests` references and repo-root or `.agentloop` aggregator invocations; this document's out-of-scope block records the prior unrelated global failure. The gate is the six deterministic commands captured above. |
| 7 | Do not touch `AppRootView` / `AppRouter` / `Screen` enum. | `git status --short`; source line inspection only | This builder item edits only `.agentloop/state/tasks/task-9-b5/ACCEPTANCE.md`. `AppRootView.swift` was read for proof at `:31-52`; `AppRouter.swift` and `Screen.swift` are untouched. |

## Behavioral Proof Details

The sidebar list is most-recent-first because `ConversationListStore.refresh()`
assigns `ConversationList.sorted(...)` at
`mac-app/Sources/ChatApp/Messaging/ConversationListStore.swift:32`; the
comparator orders newer fixed-width timestamps first at
`mac-app/Sources/ChatApp/Messaging/ConversationListModel.swift:97`; live records
enter through `ConversationListStore.handleLiveRecord` at
`mac-app/Sources/ChatApp/Messaging/ConversationListStore.swift:35`, upsert at
`:46-52`, and re-sort at `ConversationListModel.swift:130`.

Selecting a peer loads full decrypted history because
`ConversationsView.swift:41-45` observes `selectedPeerUsername` and
`ConversationsView.swift:67` calls
`dmCoordinator.startConversation(withUsername:)`; `DMCoordinator.swift:79`
starts the conversation, `:109` calls `loadHistory()`, `:121` fetches history,
and `:122-130` publishes decrypted display messages into `messages`. The
scroll-back UI renders those messages through `ConversationView.swift:45-47`.

Shell startup publishes the local prekey because `ConversationsView.swift:33-37`
runs `listStore.refresh()`, `listStore.subscribe()`, and
`dmCoordinator.publishOwnPrekey()`; the targeted
`ConversationsViewWiringTests.swift:104-115` verifies that prekey publication.

## Out-of-Scope Global Aggregator Rejection

The prior rejection came from the repo-root global aggregator, not from
task-9-b5's deterministic gate. The rejected run is out of scope for this
builder item:

```text
task-1d boots a live backend and runs LiveGroupE2ETests.
testLiveCoordinatorCreatesGroupAndPeerReceivesDecryptedMessage timed out after
125s at LiveGroupE2ETests.swift:46.
The timeout cascaded into "Registration request failed" for later live suites.
```

Acceptance clause 6 declares that the repo-root global `bash verify.sh` is not
this item's gate. That failure belongs to the task-1d/task-5 live-backend path,
not to task-9-b5-b3. Therefore task-9-b5-b3 must be judged on the deterministic
targeted commands recorded above: `swift build`, `swift build --build-tests`,
the strengthened task-local `.agentloop/state/tasks/task-9-b5/verify.sh`, and
the three named `swift test --filter` suites. It must never be judged by the
repo-root global aggregator or by any `Live*E2ETests`.
