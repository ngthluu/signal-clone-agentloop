# Attachment Rendered Flow

This document is the reproducible review path for task-7-r3. It covers the same user-visible flow a reviewer exercises in the rendered macOS app: attach a file, send it to a recipient who already has the conversation open, see the attachment appear live, download it, and confirm the saved file opens intact.

## Rendered Surface Check

`ConversationView` exposes the DM flow:

- The paperclip button calls `pickAttachment()`.
- `pickAttachment()` presents an `NSOpenPanel`, reads the selected file, enforces the 10 MB limit, and calls `coordinator.sendAttachment(data:filename:mime:)`.
- Attachment messages render a bubble with the filename and `ByteCountFormatter` human file size.
- Each attachment bubble has a `Download` button.
- `Download` calls `coordinator.downloadAttachment(_:)`, presents an `NSSavePanel`, and writes the decrypted bytes to the chosen path.

`GroupView` exposes the same group flow:

- The paperclip button is enabled when a group is open and calls `pickAttachment()`.
- The attachment bubble renders filename, human file size, and `Download`.
- `Download` calls `coordinator.downloadAttachment(_:)`, presents `NSSavePanel`, and writes the decrypted bytes to disk.
- The message keeps the group sender label below the bubble, so live received attachments remain attributable by username in the rendered thread.

No lifecycle fix was needed for this item. The existing SwiftUI app target launches as a regular macOS app, and the file panels are created from the rendered views with `NSOpenPanel.runModal()` and `NSSavePanel.runModal()`.

## Human Walkthrough

1. Start the backend:

   ```sh
   cd backend
   cargo run -- --db-path /tmp/chatapp-rendered-flow.sqlite3 --port 3000
   ```

2. In a separate terminal, launch the macOS app:

   ```sh
   cd mac-app
   swift run ChatApp
   ```

3. Register or sign in as two users on two app instances or two local profiles, for example Alice and Bob.

4. For the DM path, have Bob open the DM with Alice before Alice sends. Alice selects the paperclip button, chooses a small text/PDF/image file, and sends it. Bob should see an attachment bubble appear live with the filename and file size. Bob selects `Download`, saves it, and opens the saved file. It must match Alice's original.

5. For the group path, create a group containing Alice and Bob. Have Bob open the group before Alice sends. Alice selects the paperclip button, chooses the same file or another common file, and sends it. Bob should see the group attachment appear live with filename, file size, and Alice's username as sender. Bob selects `Download`, saves it, and opens the saved file. It must match Alice's original.

The backend stores only encrypted attachment blobs. The filename, MIME type, size, and file key travel inside the encrypted message descriptor, so the server receives an opaque attachment blob and encrypted message ciphertext.

## Automated Demonstration

Run the helper from the repository root:

```sh
docs/run-attachments-rendered-flow-demo.sh
```

The helper:

- reaps stale backend processes with `backend/scripts/reap_stale_backends.sh`;
- chooses a free local port;
- boots the Rust backend with a temporary SQLite database;
- creates two real identities and authenticated sessions;
- publishes real signed X25519 prekeys;
- subscribes Bob to the DM live SSE stream before Alice sends;
- uploads an AES-GCM encrypted DM file blob, sends only an encrypted attachment descriptor, receives it over the live stream, downloads/decrypts it as Bob, and writes it to disk;
- creates a group containing Alice and Bob, subscribes Bob to the group live SSE stream before Alice sends, repeats the encrypted attachment send/download/write flow for the group;
- runs `cmp` for DM and group originals versus downloaded files;
- verifies the recovered text files contain the expected sentinel, proving they are openable text;
- terminates the backend on exit.

Expected final line:

```text
attachments rendered flow demo: PASS
```
