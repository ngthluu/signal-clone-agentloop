# task-5-r1 Rendered Group Flow

This note connects the rendered group-chat UI to the scoped verification gate and the lived coordinator capture. The application source and tests are unchanged for this builder item; this file only re-stamps and re-derives the evidence links.

## Rendered GUI Path

The production screen starts in `GroupView`. The user enters a group name, enters invitee usernames, and presses Create (`mac-app/Sources/ChatApp/Views/GroupView.swift:38`, `mac-app/Sources/ChatApp/Views/GroupView.swift:40`, `mac-app/Sources/ChatApp/Views/GroupView.swift:42`). In normal app wiring, that button calls the coordinator create path (`mac-app/Sources/ChatApp/Views/GroupView.swift:48`).

Once a group is open, the same view exposes invite and send controls. The invite field and Add button call `addMember(username:)` (`mac-app/Sources/ChatApp/Views/GroupView.swift:106`, `mac-app/Sources/ChatApp/Views/GroupView.swift:109`, `mac-app/Sources/ChatApp/Views/GroupView.swift:116`). The message composer's Send button submits the draft through `sendCurrentDraft`, which calls `GroupCoordinator.send(text:)` in normal app wiring (`mac-app/Sources/ChatApp/Views/GroupView.swift:176`, `mac-app/Sources/ChatApp/Views/GroupView.swift:202`, `mac-app/Sources/ChatApp/Views/GroupView.swift:212`).

Rendered messages come from `coordinator.messages`; the attribution line renders `message.senderName`, so the UI displays `"You"` or a resolved username instead of exposing only a raw sender UUID (`mac-app/Sources/ChatApp/Views/GroupView.swift:132`, `mac-app/Sources/ChatApp/Views/GroupView.swift:139`).

## Coordinator Path

`GroupCoordinator.createGroup(name:memberUsernames:)` is the GUI-facing create path (`mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:91`). It normalizes usernames including the local account, prepares a fresh epoch-0 group key, wraps that key for members, persists the group through the group service, stores local group state, refreshes the group list, and subscribes live so the creator receives near-real-time inbound group events (`mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:106`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:118`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:119`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:127`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:132`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:138`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:140`).

`GroupCoordinator.send(text:)` is the GUI-facing send path (`mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:254`). Before sending, it prepares the latest available epoch key; the plaintext draft is encrypted into a group ciphertext under `prepared.epoch`, and only that ciphertext is handed to the group service (`mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:267`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:273`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:274`). The local sender display row is appended as `"You"` (`mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:279`).

`subscribeLive(groupId:token:)` owns the live receive path (`mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:381`). It opens the service stream with an epoch-change hook, appends live records after decryption, and refreshes detail/keys/list when an epoch event arrives (`mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:388`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:391`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:401`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:419`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:420`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:421`).

The decrypt-and-render step is `resolve(record:)` (`mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:462`). It recovers the message epoch, self-heals by reloading detail and keys if the epoch key is missing, decrypts with the local epoch key, then builds the displayed message with sender attribution (`mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:463`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:467`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:468`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:469`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:473`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:474`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:479`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:482`).

`senderName(for:)` maps the local user to `"You"`, maps known member ids to usernames, and only falls back to the raw sender id if the roster cannot resolve it (`mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:572`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:573`, `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:576`). That result is the value rendered by `GroupView` (`mac-app/Sources/ChatApp/Views/GroupView.swift:139`).

## Backend Re-key Event

When a member is added, the backend writes the new member's joined epoch, updates the group's current epoch, stores wrapped keys for the new epoch, and broadcasts `GroupStreamEvent::Epoch` to live subscribers (`backend/src/routes/groups.rs:438`, `backend/src/routes/groups.rs:452`, `backend/src/routes/groups.rs:461`, `backend/src/routes/groups.rs:482`). That broadcast is the backend side of the coordinator self-heal path above: existing members see the epoch event, refresh detail and keys, and keep decrypting after a re-key while a late member remains excluded from prior epoch messages.

## Automated Capture Of The Rendered Path

The durable lived-flow artifact is `.agentloop/state/tasks/task-5-r1/rendered-coordinator-flow.log`. It runs the two coordinator-driven live tests on fresh isolated backends and deliberately excludes the 125-second `testLiveCoordinatorCreatesGroupAndPeerReceivesDecryptedMessage` case.

The first captured test, `testLiveGroupAllThreeMembersSendAndReceiveThroughCoordinators`, drives three real `GroupCoordinator` instances through create/open/send/receive over a real backend (`mac-app/Tests/ChatAppTests/LiveGroupE2ETests.swift:66`). The log records `Executed 1 test, with 0 failures` for that filter.

The second captured test, `testLiveGroupExistingMembersKeepReceivingAfterAddWhileNewMemberExcluded`, drives the add-member epoch bump, verifies existing members continue receiving, and verifies the new member is excluded from prior epoch messages (`mac-app/Tests/ChatAppTests/LiveGroupE2ETests.swift:133`). The log records `Executed 1 test, with 0 failures` for that filter.

The scoped gate remains narrower by acceptance design: it runs only `testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages` against a fresh backend (`mac-app/Tests/ChatAppTests/LiveGroupE2ETests.swift:233`). That service-level live test proves named group creation, wrapped key distribution, encrypted message round-trip, sentinel plaintext absence from wire/history/DB, and late-member exclusion from epoch-0 material while avoiding the excluded long-running coordinator test.

## Manual Reproduction

1. Start a fresh backend and register at least three users with published prekeys.
2. In the app, sign in as Alice and open the group chat screen.
3. Enter a group name and Bob's username in the Members field, then press Create.
4. Confirm the new group name and epoch are visible, and the roster shows Alice and Bob.
5. Sign in as Bob in another app session, open the group id, and confirm Bob sees the same group name and roster.
6. Have Alice send a message. Alice's rendered bubble should show `"You"`; Bob's rendered copy should show Alice's username.
7. From Alice's group screen, add Carol by username. The backend emits an epoch event, existing members refresh keys, and Alice/Bob continue sending and receiving under the newer epoch.
8. Confirm Carol can receive new epoch messages but cannot decrypt messages sent before she was added.

## Why The Scoped Gate Still Proves The Customer Flow

The rendered path above is the production GUI path: `GroupView` create/invite/send -> `GroupCoordinator.createGroup` -> `send` -> `subscribeLive` -> `resolve` -> `senderName(for:)`/`GroupView` attribution -> backend epoch broadcast on add. The b2 rendered coordinator capture proves that same path over a real backend for multi-member send/receive and add-member re-key continuity.

The task gate is intentionally scoped to one fast live service-level test because the acceptance criteria exclude the 125-second coordinator test. The scoped live leg still exercises the real HTTP group service and SQLite backend, then `verify.sh` inspects the wire, history, DB row, raw DB strings, late-member key rows, joined epoch, and schema to prove the backend stores encrypted group message blobs plus membership metadata only.

## Provenance

Line references in this rendered-flow note were re-derived with `sed -n "${line}p" <file>` and stamped against HEAD `ede1a9e` on 2026-06-05.
