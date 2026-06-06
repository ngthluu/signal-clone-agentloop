# Test Chat App

Test Chat App is a local-first encrypted chat prototype with a Swift macOS client and a Rust Axum backend. The backend is a zero-knowledge relay over SQLite: it authenticates users, routes direct and group messages, stores encrypted attachments, and never receives plaintext message or file content.

## Repo Layout

| Path | Purpose |
| --- | --- |
| `backend/` | Rust Axum HTTP/SSE relay, SQLite migrations, backend tests, and maintenance scripts. |
| `mac-app/` | Swift Package Manager macOS app, app state, crypto, services, views, and tests. |
| `docs/` | Review notes and reproducible flows, including attachment rendering and zero-knowledge audits. |
| `verify.sh` | Root verification entrypoint; delegates to the AgentLoop verification script. |

## Architecture

```text
Swift macOS app
  |-- Keychain: identity private key, X25519 private key, session token
  |-- Application Support/ChatApp: account.json, sync-cursors.json
  |-- MessageCrypto / GroupCrypto / FileCrypto encrypt before upload
  v
HTTP + SSE at http://127.0.0.1:3000
  v
Rust Axum backend
  |-- auth, registration, keys, messages, groups, attachments, health routes
  |-- stores routing metadata, public keys, sessions, and opaque ciphertext
  v
SQLite database
```

The app runtime is fixed to `http://127.0.0.1:3000` for the production macOS client services. Live Swift tests can target another backend with `CHATAPP_LIVE_BACKEND_URL`.

The backend API surface includes `GET /health`, registration, auth challenge/verify/session, key publication and lookup, direct-message history/inbox/SSE, conversation summaries, group management/messages/SSE, and encrypted attachment upload/download routes.

## Data Flows

- Registration creates or loads a local identity key from Keychain, sends only the username and public identity key, and stores local account state under Application Support.
- Sign-in uses a backend challenge and a client-side identity signature; the session token is stored in Keychain.
- Direct messages use `MessageCrypto` on the sender device, then the backend stores and relays only ciphertext plus sender, recipient, id, and timestamp metadata.
- Groups use `GroupCrypto` to encrypt group messages and wrap group key material for members; the backend stores group membership metadata and ciphertext.
- Attachments use `FileCrypto` before upload. Filename, MIME type, file key, and size travel in encrypted message descriptors; the backend stores opaque encrypted bytes and routing metadata.
- Conversation updates use backend HTTP history endpoints plus SSE live streams.

## Prerequisites

- macOS 13 or newer for the SwiftUI app target.
- Swift 6 toolchain.
- Rust stable toolchain with Cargo.
- `bash`, `curl`, `sqlite3`, and standard Unix command-line tools for scripts and verification.

## Build And Test

Backend:

```bash
cd backend
cargo build
cargo test
```

macOS app:

```bash
cd mac-app
swift build
swift test
swift run ChatAppRunner
```

`ChatAppRunner` is the SwiftPM command-line runner. The Xcode scheme and app bundle remain named `ChatApp`.

To run the macOS client as a real app bundle from Xcode:

```bash
open mac-app/ChatApp.xcodeproj
```

Select the shared `ChatApp` scheme, select the `My Mac` destination, and press Run. The app window renders the normal registration, sign-in, or authenticated chat screen.

You can also build the Debug app bundle from the command line:

```bash
cd mac-app
xcodebuild -project ChatApp.xcodeproj -scheme ChatApp -configuration Debug -destination 'platform=macOS' build
```

For a Release app bundle suitable for local evaluation:

```bash
cd mac-app
rm -rf /tmp/chatapp-xcode-release
xcodebuild -project ChatApp.xcodeproj -scheme ChatApp -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/chatapp-xcode-release build
open /tmp/chatapp-xcode-release/Build/Products/Release/ChatApp.app
```

The repository gate intentionally skips live backend XCTest cases unless explicitly opted in:

```bash
cd mac-app
env -u CHATAPP_LIVE_BACKEND_URL swift test
```

Run the full root verification flow from the repository root:

```bash
./verify.sh
```

## Run Locally

From the repository root:

```bash
cd backend
cargo run -- --db-path ./backend.sqlite3 --port 3000
```

From another terminal, check that the backend is reachable:

```bash
curl -i http://127.0.0.1:3000/health
```

The environment-variable equivalent is:

```bash
cd backend
DATABASE_PATH=./backend.sqlite3 PORT=3000 cargo run
```

Start the backend on port 3000 first, then run the SwiftPM runner:

```bash
cd mac-app
swift run ChatAppRunner
```

Or open `mac-app/ChatApp.xcodeproj`, choose the `ChatApp` scheme and `My Mac`, then press Run. `ChatAppRunner` is only the SwiftPM runner command; the Xcode scheme and app bundle remain `ChatApp`. The app talks to the fixed runtime URL `http://127.0.0.1:3000`, so start the backend on port 3000 before testing registration, sign-in, or chat messaging against a live relay. The app window should still render its initial route without the backend.

For live Swift tests that need an explicit backend URL:

```bash
cd mac-app
CHATAPP_LIVE_BACKEND_URL=http://127.0.0.1:3000 swift test
```

For the attachment rendered-flow demo:

```bash
docs/run-attachments-rendered-flow-demo.sh
```

See also:

- `docs/zero-knowledge-relay.md`
- `docs/attachments-rendered-flow.md`
- `docs/run-attachments-rendered-flow-demo.sh`

## Configuration

| Name | Kind | Applies to | Default | Notes |
| --- | --- | --- | --- | --- |
| `DATABASE_PATH` | Environment variable | Backend | `backend.sqlite3` | SQLite file path relative to the backend process current working directory; parent directories are created. |
| `PORT` | Environment variable | Backend | `3000` | HTTP/SSE listen port. |
| `--db-path` | CLI flag | Backend | Overrides `DATABASE_PATH` | Example: `cargo run -- --db-path /tmp/chat.sqlite3`. |
| `--port` | CLI flag | Backend | Overrides `PORT` | Use `3000` for the current macOS app runtime. |
| `CHATAPP_LIVE_BACKEND_URL` | Environment variable | Swift tests | unset | When set, live E2E XCTest cases run against that backend; when unset, they skip. |
| none | Fixed runtime URL | macOS app | `http://127.0.0.1:3000` | Current HTTP services default to this URL. |

Optional artifact-output environment variables used by task gates are not required for normal local development.

## Security Model

The trusted boundary is the macOS client device. Private identity and X25519 keys live in Keychain; local account and sync cursor files live under the user's Application Support `ChatApp` directory. The backend is treated as an untrusted zero-knowledge relay: it can see routing metadata, public keys, sessions, timestamps, ids, and ciphertext sizes, but not direct-message plaintext, group-message plaintext, attachment contents, or private keys.

`MessageCrypto` uses X25519 key agreement, HKDF-SHA256, AES-GCM, and a base64 envelope containing the version, ephemeral public key, and sealed bytes. `GroupCrypto` uses per-epoch symmetric group keys, member-specific wrapped keys, and AES-GCM message envelopes. `FileCrypto` uploads AES-GCM encrypted bytes as opaque attachment blobs.

These components enforce the end-to-end encryption boundary before data reaches the Rust backend. The backend database schema intentionally stores ciphertext blobs and routing fields, not plaintext content columns. This protects content, not anonymity or metadata: the backend still sees account identifiers, usernames, message ids, group ids, membership, routing and timing metadata, public identity keys, public prekeys, signatures, valid bearer tokens, and ciphertext sizes. The detailed audit is in `docs/zero-knowledge-relay.md`.

## Troubleshooting

- Port 3000 already in use: remove stale orphaned backend processes, then restart the backend.

  ```sh
  bash backend/scripts/reap_stale_backends.sh
  ```

- App opens with an old account or cursor state: clear the local `ChatApp` files under the user's Application Support directory.
- App keeps using an old identity, X25519 key, or session: clear the related `com.testchatapp.identity` generic-password items from Keychain.
- Live Swift tests skip: set `CHATAPP_LIVE_BACKEND_URL` to a running backend URL.
