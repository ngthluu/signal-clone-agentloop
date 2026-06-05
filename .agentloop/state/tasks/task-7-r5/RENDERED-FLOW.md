# task-7-r5 Rendered Flow Proof

This document traces the production macOS attachment GUI path for direct messages and groups. It is evidence for the scoped task-7-r5 attachment gate only; the root `bash verify.sh` aggregator is not this item's gate.

## Production DM Path

1. `mac-app/Sources/ChatApp/Views/ConversationView.swift:63` renders the DM composer controls. The paperclip button is defined at `mac-app/Sources/ChatApp/Views/ConversationView.swift:64`, calls `pickAttachment()` at `mac-app/Sources/ChatApp/Views/ConversationView.swift:65`, displays the paperclip symbol at `mac-app/Sources/ChatApp/Views/ConversationView.swift:67`, and is disabled until a peer is selected at `mac-app/Sources/ChatApp/Views/ConversationView.swift:70`.
2. `mac-app/Sources/ChatApp/Views/ConversationView.swift:144` starts `pickAttachment()`. It opens an `NSOpenPanel` at `mac-app/Sources/ChatApp/Views/ConversationView.swift:145`, allows one file and no directories at `mac-app/Sources/ChatApp/Views/ConversationView.swift:146` through `mac-app/Sources/ChatApp/Views/ConversationView.swift:148`, reads the chosen file bytes at `mac-app/Sources/ChatApp/Views/ConversationView.swift:154`, enforces the 10 MB limit at `mac-app/Sources/ChatApp/Views/ConversationView.swift:155`, and reports the limit error at `mac-app/Sources/ChatApp/Views/ConversationView.swift:156`.
3. The DM view keeps the selected filename at `mac-app/Sources/ChatApp/Views/ConversationView.swift:159`, sets the upload MIME to `application/octet-stream` at `mac-app/Sources/ChatApp/Views/ConversationView.swift:160`, and enters the production send path with `coordinator.sendAttachment(data:filename:mime:)` at `mac-app/Sources/ChatApp/Views/ConversationView.swift:165`.
4. `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:141` defines the DM attachment send path. It repeats the 10 MB guard at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:142`, requires an authenticated session at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:146`, requires an open DM at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:150`, and fetches a verified recipient prekey at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:154`.
5. The coordinator creates a fresh file key at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:159`, encrypts the file bytes at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:160`, uploads only the encrypted blob at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:161`, builds an `AttachmentDescriptor` at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:165`, encrypts the descriptor as the DM message ciphertext at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:172`, sends it at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:173`, and appends local attachment bubble state at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:175`.
6. Received DM records are decrypted in history at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:124` and from the live stream at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:268`. `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:327` converts plaintext into display state; when `AttachmentDescriptor.decode` succeeds at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:328`, it publishes `AttachmentInfo` at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:333`.
7. `mac-app/Sources/ChatApp/Views/ConversationView.swift:119` renders attachment messages as bubbles. The bubble shows the original filename at `mac-app/Sources/ChatApp/Views/ConversationView.swift:121`, shows size text at `mac-app/Sources/ChatApp/Views/ConversationView.swift:123`, formats that size through `ByteCountFormatter` at `mac-app/Sources/ChatApp/Views/ConversationView.swift:194` and `mac-app/Sources/ChatApp/Views/ConversationView.swift:195`, and renders the `Download` button at `mac-app/Sources/ChatApp/Views/ConversationView.swift:126`.
8. Pressing `Download` calls `saveAttachment(_:)` at `mac-app/Sources/ChatApp/Views/ConversationView.swift:127`. `saveAttachment` asks the coordinator for decrypted bytes at `mac-app/Sources/ChatApp/Views/ConversationView.swift:175`, opens an `NSSavePanel` at `mac-app/Sources/ChatApp/Views/ConversationView.swift:179`, defaults the save name to the original filename at `mac-app/Sources/ChatApp/Views/ConversationView.swift:180`, and writes the decrypted bytes to disk at `mac-app/Sources/ChatApp/Views/ConversationView.swift:185`.
9. `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:193` defines DM attachment download. It fetches the encrypted blob with `AttachmentService.download` at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:199`, decodes the descriptor file key at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:200`, and returns decrypted bytes from `FileCrypto` at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:208`.

## Production Group Path

1. `mac-app/Sources/ChatApp/Views/GroupView.swift:153` renders the group composer controls. The paperclip button is defined at `mac-app/Sources/ChatApp/Views/GroupView.swift:154`, calls `pickAttachment()` at `mac-app/Sources/ChatApp/Views/GroupView.swift:155`, displays the paperclip symbol at `mac-app/Sources/ChatApp/Views/GroupView.swift:157`, and is disabled until a group is open at `mac-app/Sources/ChatApp/Views/GroupView.swift:160`.
2. `mac-app/Sources/ChatApp/Views/GroupView.swift:244` starts `pickAttachment()`. It opens an `NSOpenPanel` at `mac-app/Sources/ChatApp/Views/GroupView.swift:245`, allows one file and no directories at `mac-app/Sources/ChatApp/Views/GroupView.swift:246` through `mac-app/Sources/ChatApp/Views/GroupView.swift:248`, reads the chosen file bytes at `mac-app/Sources/ChatApp/Views/GroupView.swift:254`, enforces the 10 MB limit at `mac-app/Sources/ChatApp/Views/GroupView.swift:255`, and reports the limit error at `mac-app/Sources/ChatApp/Views/GroupView.swift:256`.
3. The group view keeps the selected filename at `mac-app/Sources/ChatApp/Views/GroupView.swift:259`, sets the upload MIME to `application/octet-stream` at `mac-app/Sources/ChatApp/Views/GroupView.swift:260`, and enters the production send path with `coordinator.sendAttachment(data:filename:mime:)` at `mac-app/Sources/ChatApp/Views/GroupView.swift:265`.
4. `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:297` defines the group attachment send path. It repeats the 10 MB guard at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:298`, requires an authenticated session at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:302`, requires an open group at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:306`, and prepares the current group epoch key at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:310`.
5. The group coordinator creates a fresh file key at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:316`, encrypts the file bytes at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:317`, uploads only the encrypted blob at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:318`, builds an `AttachmentDescriptor` at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:322`, encrypts that descriptor as a group message at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:329`, sends it at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:330`, and appends local group attachment bubble state at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:332`.
6. Group history resolves messages at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:442`, and live messages append through `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:455`. The resolver decrypts group ciphertext at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:474`, converts plaintext into display state at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:479`, detects an attachment descriptor at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:554`, and carries `AttachmentInfo` at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:561`.
7. `mac-app/Sources/ChatApp/Views/GroupView.swift:137` wraps each group bubble with sender metadata, renders the bubble at `mac-app/Sources/ChatApp/Views/GroupView.swift:138`, and retains the sender username label at `mac-app/Sources/ChatApp/Views/GroupView.swift:139`.
8. `mac-app/Sources/ChatApp/Views/GroupView.swift:220` renders attachment messages as bubbles. The bubble shows the original filename at `mac-app/Sources/ChatApp/Views/GroupView.swift:222`, shows size text at `mac-app/Sources/ChatApp/Views/GroupView.swift:224`, formats that size through `ByteCountFormatter` at `mac-app/Sources/ChatApp/Views/GroupView.swift:294` and `mac-app/Sources/ChatApp/Views/GroupView.swift:295`, and renders the `Download` button at `mac-app/Sources/ChatApp/Views/GroupView.swift:227`.
9. Pressing `Download` calls `saveAttachment(_:)` at `mac-app/Sources/ChatApp/Views/GroupView.swift:228`. `saveAttachment` asks the coordinator for decrypted bytes at `mac-app/Sources/ChatApp/Views/GroupView.swift:275`, opens an `NSSavePanel` at `mac-app/Sources/ChatApp/Views/GroupView.swift:279`, defaults the save name to the original filename at `mac-app/Sources/ChatApp/Views/GroupView.swift:280`, and writes the decrypted bytes to disk at `mac-app/Sources/ChatApp/Views/GroupView.swift:285`.
10. `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:354` defines group attachment download. It fetches the encrypted blob with `AttachmentService.download` at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:360`, decodes the descriptor file key at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:361`, and returns decrypted bytes from `FileCrypto` at `mac-app/Sources/ChatApp/Groups/GroupCoordinator.swift:369`.

## Supporting Graph

1. `mac-app/Sources/ChatApp/Messaging/AttachmentService.swift:3` defines the attachment service boundary. `HTTPAttachmentService.upload` starts at `mac-app/Sources/ChatApp/Messaging/AttachmentService.swift:21`, posts to `/attachments` at `mac-app/Sources/ChatApp/Messaging/AttachmentService.swift:23`, sets `Content-Type: application/octet-stream` at `mac-app/Sources/ChatApp/Messaging/AttachmentService.swift:25`, adds the bearer token at `mac-app/Sources/ChatApp/Messaging/AttachmentService.swift:26`, and sends the encrypted blob as the HTTP body at `mac-app/Sources/ChatApp/Messaging/AttachmentService.swift:27`.
2. `HTTPAttachmentService.download` starts at `mac-app/Sources/ChatApp/Messaging/AttachmentService.swift:43`, requests `/attachments/{attachmentId}` at `mac-app/Sources/ChatApp/Messaging/AttachmentService.swift:45` through `mac-app/Sources/ChatApp/Messaging/AttachmentService.swift:48`, adds the bearer token at `mac-app/Sources/ChatApp/Messaging/AttachmentService.swift:51`, and returns the response bytes at `mac-app/Sources/ChatApp/Messaging/AttachmentService.swift:57`.
3. `mac-app/Sources/ChatApp/Messaging/FileCrypto.swift:9` creates a 256-bit file key. `mac-app/Sources/ChatApp/Messaging/FileCrypto.swift:13` encrypts file bytes with AES-GCM and returns the combined sealed blob at `mac-app/Sources/ChatApp/Messaging/FileCrypto.swift:18`. `mac-app/Sources/ChatApp/Messaging/FileCrypto.swift:21` decrypts AES-GCM blobs back to plaintext bytes, opening the combined sealed box at `mac-app/Sources/ChatApp/Messaging/FileCrypto.swift:24`.
4. `mac-app/Sources/ChatApp/Messaging/AttachmentDescriptor.swift:3` defines the encrypted descriptor. It carries `attachmentId` at `mac-app/Sources/ChatApp/Messaging/AttachmentDescriptor.swift:6`, `fileKey` at `mac-app/Sources/ChatApp/Messaging/AttachmentDescriptor.swift:7`, `filename` at `mac-app/Sources/ChatApp/Messaging/AttachmentDescriptor.swift:8`, `mime` at `mac-app/Sources/ChatApp/Messaging/AttachmentDescriptor.swift:9`, and original plaintext `size` at `mac-app/Sources/ChatApp/Messaging/AttachmentDescriptor.swift:10`. `mac-app/Sources/ChatApp/Messaging/AttachmentDescriptor.swift:30` encodes the descriptor into JSON before message encryption, `mac-app/Sources/ChatApp/Messaging/AttachmentDescriptor.swift:34` decodes it after message decryption, and `mac-app/Sources/ChatApp/Messaging/AttachmentDescriptor.swift:63` through `mac-app/Sources/ChatApp/Messaging/AttachmentDescriptor.swift:68` convert it to bubble/download state.

## Manual Reproduction

1. From the repository root, stop stale local test backends:

   ```sh
   bash backend/scripts/reap_stale_backends.sh
   ```

2. Start a clean local backend:

   ```sh
   cd backend
   cargo run -- --db-path /tmp/chatapp-rendered-flow.sqlite3 --port 3000
   ```

3. In a second terminal, run the production app:

   ```sh
   cd mac-app
   swift run ChatApp
   ```

4. Register or sign in as two users. Open the app for both users after authentication so message keys are published.
5. DM flow: start a direct message with the second user, click the paperclip button, choose a file of 10 MB or less, send it, receive it on the other user, click `Download`, save it, and open the saved file. The saved file should match the original bytes and display the original contents.
6. Group flow: create or open a group containing both users, click the paperclip button, choose a file of 10 MB or less, send it, receive it in the group view with the sender username still shown under the bubble, click `Download`, save it, and open the saved file. The saved file should match the original bytes and display the original contents.

## Verification Commands

Run these scoped evidence commands from the repository root:

```sh
bash .agentloop/state/tasks/task-7-r5/verify.sh
docs/run-attachments-rendered-flow-demo.sh
```

The scoped gate is captured in `.agentloop/state/tasks/task-7-r5/scoped_gate_run.log` and must end with `task-7 verify: PASS`. The rendered-flow demo is captured in `.agentloop/state/tasks/task-7-r5/rendered_flow_demo_run.log`; that log records DM and group encrypted send, live receive, download, byte-identical `cmp`, sentinel-text openability, and ends with `attachments rendered flow demo: PASS`.

## Provenance

File-line references and manual reproduction steps were re-verified against commit `5cbc334` in the current task-7-r5-b4 worktree on 2026-06-05. Application source was inspected read-only; this builder item edits only task evidence artifacts.
