# task-7-r7 Rendered DM Attachment Flow

This traces the direct-message attachment product path only. Group attachments are out of scope for task-7-r7 and are not claimed as acceptance here.

## Sender UI

1. `ConversationView` exposes the paperclip file action at `mac-app/Sources/ChatApp/Views/ConversationView.swift:63`.
2. `pickAttachment()` opens an `NSOpenPanel`, allows a single file, and reads selected bytes at `ConversationView.swift:144`.
3. The UI enforces the 10 MB plaintext limit at `ConversationView.swift:155`.
4. The selected filename comes from `url.lastPathComponent` at `ConversationView.swift:159`, MIME is fixed to `application/octet-stream` at line 160, and the DM send call is `coordinator.sendAttachment(data:filename:mime:)` at line 165.

## Sender Encryption And Descriptor

1. `DMCoordinator.sendAttachment(data:filename:mime:)` starts at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:141` and repeats the 10 MB guard at line 142.
2. The coordinator loads the sender session and verified peer prekey at `DMCoordinator.swift:146` and `:154`.
3. It creates a fresh file key and encrypts the file locally at `DMCoordinator.swift:159` and `:160`.
4. `FileCrypto` uses AES-GCM in `mac-app/Sources/ChatApp/Messaging/FileCrypto.swift:13`, returning the combined nonce/ciphertext/tag bytes at line 18.
5. The encrypted blob is uploaded before descriptor delivery at `DMCoordinator.swift:161`.
6. `AttachmentDescriptor` carries the attachment id, file key, filename, MIME, and original size in local encrypted-message plaintext at `mac-app/Sources/ChatApp/Messaging/AttachmentDescriptor.swift:3`.
7. Its wire JSON uses `attachment_id` and `file_key` keys at `AttachmentDescriptor.swift:45`.
8. The descriptor JSON is encrypted as the DM message ciphertext at `DMCoordinator.swift:172`, then sent through the normal DM message service at line 173.

## Attachment Service And Backend Relay

1. `HTTPAttachmentService.upload` posts only `encryptedBlob` to `/attachments` at `mac-app/Sources/ChatApp/Messaging/AttachmentService.swift:21`.
2. The upload request uses `Content-Type: application/octet-stream` at `AttachmentService.swift:25`, bearer auth at line 26, and sets `request.httpBody = encryptedBlob` at line 27.
3. The backend upload route accepts opaque bytes at `backend/src/routes/attachments.rs:32`, authenticates with headers at line 33, rejects bodies over its attachment limit at line 37, and inserts only `id`, `uploader_id`, `ciphertext`, `byte_size`, and `created_at` at lines 43-51.
4. The backend schema for attachments is `backend/migrations/0005_create_attachments.sql:1`, with only `id`, `uploader_id`, `ciphertext`, `byte_size`, and `created_at`.
5. `HTTPAttachmentService.download` sends authenticated `GET /attachments/{id}` at `AttachmentService.swift:43`.
6. The backend download route authenticates at `backend/src/routes/attachments.rs:70`, selects only `ciphertext` at line 74, and returns it as `application/octet-stream` at line 85.

## Recipient Display And Save

1. Recipient DM plaintext is decoded by `DMCoordinator.displayMessage` at `mac-app/Sources/ChatApp/Messaging/DMCoordinator.swift:327`.
2. If the plaintext is an `AttachmentDescriptor`, the display message uses the descriptor filename and `AttachmentInfo` at `DMCoordinator.swift:328`.
3. `ConversationView.messageBubble` renders attachment filename, size, and Download button at `mac-app/Sources/ChatApp/Views/ConversationView.swift:117`.
4. The Download button calls `saveAttachment(_:)` at `ConversationView.swift:126`.
5. `saveAttachment(_:)` asks `DMCoordinator.downloadAttachment(_:)` for decrypted bytes at `ConversationView.swift:173`.
6. `DMCoordinator.downloadAttachment(_:)` downloads the encrypted blob and loads the descriptor file key at `DMCoordinator.swift:193`, then decrypts locally with `FileCrypto.decrypt` at line 208.
7. `FileCrypto.decrypt` opens the AES-GCM combined blob at `mac-app/Sources/ChatApp/Messaging/FileCrypto.swift:21`.
8. The save panel defaults to the descriptor filename at `ConversationView.swift:179`, and the decrypted bytes are written to disk at line 185.

## Acceptance Boundary

The backend never needs plaintext filename, MIME, file key, descriptor JSON, or file content for this DM path. Those values are either local UI state or inside the encrypted DM message descriptor. The backend stores and returns only opaque attachment bytes plus routing metadata.
