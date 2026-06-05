# Rendered Flow Proof: Authenticated Conversation Workspace Shell

## Visible Authenticated Flow

1. Production construction starts in `mac-app/Sources/ChatApp/ChatAppApp.swift`.
   `ChatAppApp` creates one `HTTPMessageService`, injects it into both `DMCoordinator`
   and `ConversationListStore`, and passes those objects into `AppRootView`
   (`ChatAppApp.swift:15`, `ChatAppApp.swift:30`, `ChatAppApp.swift:51`,
   `ChatAppApp.swift:63`).

2. The registered and authenticated app path is owned by `AppRootView`.
   When `coordinator.isRegistered` and `authCoordinator.isAuthenticated` are true,
   the view shows the "Chat" shell, keeps the segmented picker on its default
   `"direct"` selection, and renders `ConversationsView(listStore:dmCoordinator:)`
   for the direct path (`AppRootView.swift:11`, `AppRootView.swift:30`,
   `AppRootView.swift:43`, `AppRootView.swift:49`). The `AppRootView` initializer
   and routing contracts are unchanged.

3. `ConversationsView` owns the authenticated conversation workspace layout. Its
   root is `NavigationSplitView`, with `ConversationListView` in the sidebar and
   the detail column switching between a placeholder and `ConversationView`
   (`ConversationsView.swift:7`, `ConversationsView.swift:8`,
   `ConversationsView.swift:9`, `ConversationsView.swift:10`).

4. Before a conversation is selected, the detail column shows the stable placeholder
   with the message icon and "Select a conversation" text. Once
   `ConversationListStore.selectedPeerUsername` is set, the detail area renders
   `ConversationView` wired to `DMCoordinator` for chat history, sending, and
   start-conversation actions (`ConversationsView.swift:11`,
   `ConversationsView.swift:12`, `ConversationsView.swift:21`,
   `ConversationsView.swift:26`, `ConversationsView.swift:41`).

5. `ConversationsView` also starts the direct workspace work: it refreshes the
   sidebar list, subscribes the conversation list to live updates, publishes the
   user's prekey, and opens a DM whenever the selected username changes
   (`ConversationsView.swift:33`, `ConversationsView.swift:34`,
   `ConversationsView.swift:35`, `ConversationsView.swift:36`,
   `ConversationsView.swift:41`, `ConversationsView.swift:62`).

## Sidebar States

The sidebar is implemented by `ConversationListView` and backed by
`ConversationListStore`.

- Loading: `ConversationListSidebarState.resolve` returns `.loading` when there
  are no rows and the initial refresh is still in flight or has not loaded yet.
  The sidebar renders `ProgressView` with "Loading conversations"
  (`ConversationListView.swift:3`, `ConversationListView.swift:17`,
  `ConversationListView.swift:58`, `ConversationListView.swift:60`,
  `ConversationListView.swift:61`).

- Empty: after refresh completes with no rows, the resolved state is `.empty`, and
  the sidebar shows "No conversations yet" while keeping the new-conversation
  controls available below the state area (`ConversationListView.swift:21`,
  `ConversationListView.swift:64`, `ConversationListView.swift:66`,
  `ConversationListView.swift:41`).

- Populated: any non-empty conversation array resolves to `.populated`, including
  while a background refresh is running. The sidebar renders the selectable
  `List`, preserving the store's ordering and binding selection directly to
  `store.selectedPeerUsername` (`ConversationListView.swift:13`,
  `ConversationListView.swift:69`, `ConversationListView.swift:70`,
  `ConversationListView.swift:71`, `ConversationListView.swift:80`).

`ConversationListStore` publishes the source state for those views:
`conversations`, `isLoading`, `hasLoaded`, and `selectedPeerUsername`
(`ConversationListStore.swift:5`, `ConversationListStore.swift:6`,
`ConversationListStore.swift:7`, `ConversationListStore.swift:8`). `refresh()`
sets loading before awaiting `service.conversations(token:)`, clears it in the
defer block, marks `hasLoaded`, and stores the sorted conversation list
(`ConversationListStore.swift:28`, `ConversationListStore.swift:36`,
`ConversationListStore.swift:37`, `ConversationListStore.swift:42`).

## Scoped Verification

Run from `mac-app` on 2026-06-05:

| Command | Result |
| --- | --- |
| `swift test --filter ConversationsViewWiringTests` | Exit 0. Executed 7 tests, 0 failures. Covered sidebar ordering, loading/empty/populated state selection, live list bumps, selected DM history loading, and prekey publishing. |
| `swift test --filter ConversationListStoreTests` | Exit 0. Executed 9 tests, 0 failures. Covered refresh sorting, loading/loaded flags, live bumps, unknown-peer refresh, selected username round trip, and injected live stream subscription. |
| `swift test --filter AppRouterTests` | Exit 0. Executed 2 tests, 0 failures. Confirmed account-existence routing remains registration/main only. |
| `swift test --filter RootViewTests` | Exit 0. Executed 2 tests, 0 failures. Confirmed `RootView.resolvedScreen` remains registration/main only. |
| `swift build` | Exit 0. Build complete for debugging. |
| `swift build --build-tests` | Exit 0. Test build complete for debugging. |

`git diff --name-only` was checked after creating this proof file and the task
result artifact; no global backlog files were edited.
