# task-9-b5r Rendered Flow Proof

This document traces the production post-sign-in direct-message GUI path and the customer reproduction steps for the rendered macOS app.

## Production Path

1. `mac-app/Sources/ChatApp/ChatAppApp.swift:16` creates the live `HTTPMessageService`. The same service is passed into `DMCoordinator` at `mac-app/Sources/ChatApp/ChatAppApp.swift:35` and into `ConversationListStore` at `mac-app/Sources/ChatApp/ChatAppApp.swift:52`.
2. `mac-app/Sources/ChatApp/ChatAppApp.swift:63` constructs `AppRootView`, passing the live `dmCoordinator` at `mac-app/Sources/ChatApp/ChatAppApp.swift:66` and the live `conversationListStore` at `mac-app/Sources/ChatApp/ChatAppApp.swift:68`.
3. `mac-app/Sources/ChatApp/App/AppRootView.swift:31` enters the registered branch, `mac-app/Sources/ChatApp/App/AppRootView.swift:32` enters the authenticated branch, and `mac-app/Sources/ChatApp/App/AppRootView.swift:49` selects the direct-chat branch. That branch renders `ConversationsView` at `mac-app/Sources/ChatApp/App/AppRootView.swift:50`, passing `conversationListStore` at `mac-app/Sources/ChatApp/App/AppRootView.swift:51` and `dmCoordinator` at `mac-app/Sources/ChatApp/App/AppRootView.swift:52`.
4. `mac-app/Sources/ChatApp/Views/ConversationsView.swift:8` defines the shell as a `NavigationSplitView`. Its sidebar renders `ConversationListView(store: listStore)` at `mac-app/Sources/ChatApp/Views/ConversationsView.swift:9`.
5. `mac-app/Sources/ChatApp/Views/ConversationListView.swift:9` binds the sidebar `List(selection:)` to `$store.selectedPeerUsername`, and `mac-app/Sources/ChatApp/Views/ConversationListView.swift:10` renders `ForEach(store.conversations)`. The sidebar title is `Messages` at `mac-app/Sources/ChatApp/Views/ConversationListView.swift:33`.
6. `mac-app/Sources/ChatApp/Messaging/ConversationListStore.swift:32` sorts conversations during refresh, using the most-recent-first ordering in `mac-app/Sources/ChatApp/Messaging/ConversationListModel.swift:97`.
7. `mac-app/Sources/ChatApp/Views/ConversationsView.swift:10` defines the detail pane. When a peer is selected, `mac-app/Sources/ChatApp/Views/ConversationsView.swift:12` renders `ConversationView(coordinator: dmCoordinator, ...)`.
8. `mac-app/Sources/ChatApp/Views/ConversationView.swift:45` makes the message history scrollable with `ScrollView`, and `mac-app/Sources/ChatApp/Views/ConversationView.swift:47` renders decrypted `dmCoordinator.messages` with `ForEach(coordinator.messages)`.
9. `mac-app/Sources/ChatApp/Views/ConversationsView.swift:33` runs the shell startup task: `listStore.refresh()` at `mac-app/Sources/ChatApp/Views/ConversationsView.swift:34`, `listStore.subscribe()` at `mac-app/Sources/ChatApp/Views/ConversationsView.swift:35`, and `dmCoordinator.publishOwnPrekey()` at `mac-app/Sources/ChatApp/Views/ConversationsView.swift:36`.
10. `mac-app/Sources/ChatApp/Views/ConversationsView.swift:41` observes `selectedPeerUsername`, and `mac-app/Sources/ChatApp/Views/ConversationsView.swift:67` opens the selected peer by calling `dmCoordinator.startConversation(withUsername:)`. `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:79` starts the conversation, `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:109` calls `loadHistory()`, and `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:122` publishes decrypted display messages into `messages`.
11. Live activity bumps the sidebar through `ConversationListStore.handleLiveRecord` at `mac-app/Sources/ChatApp/Messaging/ConversationListStore.swift:35`, which calls the upsert path at `mac-app/Sources/ChatApp/Messaging/ConversationListStore.swift:46` and re-sorts at `mac-app/Sources/ChatApp/Messaging/ConversationListModel.swift:130`.

## Manual Reproduction

1. Build and run the mac app from `mac-app`.
2. Register or sign in with a local account.
3. After authentication, select `Direct` if the chat type picker is not already on it.
4. Observe the sidebar labeled `Messages`; it lists conversations ordered by most recent activity first.
5. Click a conversation in the sidebar.
6. Confirm the detail pane opens that DM, loads the full decrypted message history, and the history area scrolls back through older messages.
7. Send a message or receive a live message for a conversation.
8. Confirm the sidebar updates live and bumps that conversation according to the newest activity.

## Verification Commands

Run these deterministic guards from the repository root:

```sh
bash .agentloop/state/tasks/task-9-b5r/verify.sh
(cd mac-app && swift test --filter ConversationsViewWiringTests)
(cd mac-app && swift test --filter ConversationListModelTests)
(cd mac-app && swift test --filter ConversationListStoreTests)
```

## Provenance

File-line references and manual reproduction steps verified against commit `ac10fec` on 2026-06-05.
