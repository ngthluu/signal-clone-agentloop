# task-9-b5r Rendered Flow Proof

This proof traces the production post-sign-in direct-message path from app construction through the rendered SwiftUI navigation shell, sidebar ordering, scrollable decrypted history, and live sidebar bump behavior.

## Production Authenticated Direct Path

1. `mac-app/Sources/ChatApp/ChatAppApp.swift:16` creates the production `HTTPMessageService`. That same service is injected into `DMCoordinator` at `mac-app/Sources/ChatApp/ChatAppApp.swift:30`, with `service: messageService` at `mac-app/Sources/ChatApp/ChatAppApp.swift:35`.
2. `mac-app/Sources/ChatApp/ChatAppApp.swift:51` constructs `ConversationListStore`, and `mac-app/Sources/ChatApp/ChatAppApp.swift:52` passes the same `messageService` into it.
3. `mac-app/Sources/ChatApp/ChatAppApp.swift:63` renders `AppRootView`, passing the production `dmCoordinator` at `mac-app/Sources/ChatApp/ChatAppApp.swift:66` and `conversationListStore` at `mac-app/Sources/ChatApp/ChatAppApp.swift:68`.
4. `mac-app/Sources/ChatApp/App/AppRootView.swift:31` enters the registered branch, `mac-app/Sources/ChatApp/App/AppRootView.swift:32` enters the authenticated branch, and `mac-app/Sources/ChatApp/App/AppRootView.swift:49` enters the direct-chat branch.
5. The direct branch renders `ConversationsView` at `mac-app/Sources/ChatApp/App/AppRootView.swift:50`, passing `listStore: conversationListStore` at `mac-app/Sources/ChatApp/App/AppRootView.swift:51` and `dmCoordinator: dmCoordinator` at `mac-app/Sources/ChatApp/App/AppRootView.swift:52`.

## Navigation Shell

1. `mac-app/Sources/ChatApp/Views/ConversationsView.swift:8` defines the shell as `NavigationSplitView`.
2. The sidebar renders `ConversationListView(store: listStore)` at `mac-app/Sources/ChatApp/Views/ConversationsView.swift:9`.
3. The detail pane starts at `mac-app/Sources/ChatApp/Views/ConversationsView.swift:10`; `mac-app/Sources/ChatApp/Views/ConversationsView.swift:11` gates detail rendering on `listStore.selectedPeerUsername`, and `mac-app/Sources/ChatApp/Views/ConversationsView.swift:12` renders `ConversationView`.
4. The shell startup task begins at `mac-app/Sources/ChatApp/Views/ConversationsView.swift:33`, refreshes the sidebar at `mac-app/Sources/ChatApp/Views/ConversationsView.swift:34`, subscribes to live sidebar records at `mac-app/Sources/ChatApp/Views/ConversationsView.swift:35`, and publishes the user's DM prekey at `mac-app/Sources/ChatApp/Views/ConversationsView.swift:36`.
5. Selection changes are observed at `mac-app/Sources/ChatApp/Views/ConversationsView.swift:41`, routed through `openSelectedConversation` at `mac-app/Sources/ChatApp/Views/ConversationsView.swift:62`, and opened by `dmCoordinator.startConversation(withUsername:)` at `mac-app/Sources/ChatApp/Views/ConversationsView.swift:67`.

## Sidebar Ordering

1. `mac-app/Sources/ChatApp/Views/ConversationListView.swift:9` binds `List(selection:)` to `$store.selectedPeerUsername`.
2. `mac-app/Sources/ChatApp/Views/ConversationListView.swift:10` renders `ForEach(store.conversations)` for the sidebar rows.
3. `mac-app/Sources/ChatApp/Views/ConversationListView.swift:33` titles the sidebar `Messages`.
4. `mac-app/Sources/ChatApp/Messaging/ConversationListStore.swift:26` defines `refresh()`, and `mac-app/Sources/ChatApp/Messaging/ConversationListStore.swift:32` assigns `ConversationList.sorted(...)` to `conversations`.
5. `mac-app/Sources/ChatApp/Messaging/ConversationListModel.swift:90` defines the sort helper, and `mac-app/Sources/ChatApp/Messaging/ConversationListModel.swift:97` orders newer `lastActivityAt` values before older ones.

## Scrollable History Detail

1. `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:79` starts a selected DM conversation.
2. `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:109` calls `loadHistory()`, and `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:113` defines `loadHistory()`.
3. `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:121` fetches history records from the message service, and `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:122` converts decrypted records into published `messages`.
4. `mac-app/Sources/ChatApp/Views/ConversationView.swift:45` wraps the detail history in `ScrollView`.
5. `mac-app/Sources/ChatApp/Views/ConversationView.swift:47` renders `ForEach(coordinator.messages)`, so the selected conversation displays the decrypted scroll-back history loaded by `DMCoordinator`.

## Live Sidebar Bump

1. `mac-app/Sources/ChatApp/Messaging/ConversationListStore.swift:55` defines `subscribe()`.
2. `mac-app/Sources/ChatApp/Messaging/ConversationListStore.swift:63` consumes the live message stream, and `mac-app/Sources/ChatApp/Messaging/ConversationListStore.swift:67` sends each record to `handleLiveRecord`.
3. `mac-app/Sources/ChatApp/Messaging/ConversationListStore.swift:35` defines `handleLiveRecord(_:)`, and `mac-app/Sources/ChatApp/Messaging/ConversationListStore.swift:40` resolves the conversation peer id.
4. `mac-app/Sources/ChatApp/Messaging/ConversationListStore.swift:46` updates the sidebar list through `ConversationList.upsert(...)`.
5. `mac-app/Sources/ChatApp/Messaging/ConversationListModel.swift:101` defines `upsert`, and `mac-app/Sources/ChatApp/Messaging/ConversationListModel.swift:130` returns the re-sorted list.
6. Local sends follow the same bump model: `mac-app/Sources/ChatApp/Views/ConversationsView.swift:85` finds the selected summary, and `mac-app/Sources/ChatApp/Views/ConversationsView.swift:86` calls `listStore.noteLocalActivity(...)`.

## Manual Reproduction

1. From the repository root, build the mac app with `cd mac-app && swift build`, then run the app from Xcode or the built executable.
2. Register or sign in with a local account.
3. After authentication, use the chat type picker and select `Direct` if it is not already selected.
4. Confirm the first authenticated direct screen is the split navigation shell: the sidebar is titled `Messages`, and its conversation rows are ordered most-recent-first by activity.
5. Click a conversation in the `Messages` sidebar.
6. Confirm the detail pane opens that DM and loads the full decrypted message history.
7. Scroll the message history area backward to confirm older decrypted messages are available in the detail `ScrollView`.
8. Send a DM or receive a live DM for an existing conversation.
9. Confirm the `Messages` sidebar updates live and bumps that conversation according to the newest activity.

## Provenance

File-line references and manual reproduction steps verified against HEAD commit `dad7ac7` on 2026-06-05.
