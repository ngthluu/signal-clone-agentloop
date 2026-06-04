# Zero-Knowledge Relay Compliance Audit

## 1. Claim / Summary

The Rust backend follows the Signal relay model for direct messages and attachments: it forwards opaque ciphertext and persists only routing metadata. For a sent DM, server-side storage is limited to `sender_id`, `recipient_id`, `message id`, `created_at`, and the encrypted `ciphertext` blob. For an uploaded attachment, server-side storage is limited to `id`, `uploader_id`, `byte_size`, `created_at`, and the encrypted `ciphertext` blob. The backend never receives or stores readable message plaintext, attachment content, or any private key.

The current schema enforces that property for direct messages, attachment blobs, and key publication. `messages` has no plaintext/body/content column; its only message-bearing column is `ciphertext` (`backend/migrations/0003_create_messages.sql:8-14`). `attachments` has no attachment-content column; its only attachment-bearing column is `ciphertext` (`backend/migrations/0005_create_attachments.sql:1-7`). `device_keys` stores only a public X25519 prekey and an Ed25519 signature (`backend/migrations/0003_create_messages.sql:1-6`). Current group tables also use ciphertext or wrapped-key blobs for encrypted group material (`backend/migrations/0004_create_groups.sql:17-33`).

## 2. Trust Boundary & Threat Model

Trusted boundary: the macOS client device. The device owns the Ed25519 identity signing key and the X25519 static private key. Those private keys are stored through the app's Keychain wrapper (`mac-app/Sources/ChatApp/Identity/KeychainStore.swift:27-87`), loaded or created by `IdentityManager` (`mac-app/Sources/ChatApp/Identity/IdentityManager.swift:11-28`) and `X25519KeyManager` (`mac-app/Sources/ChatApp/Messaging/X25519KeyManager.swift:13-33`).

Untrusted boundary: the Rust backend, its SQLite database, its logs/stdout/stderr, and its disk. An adversary with complete backend DB, log, and disk access can learn metadata: who talked to whom, when, message ids, message counts, and ciphertext sizes. That adversary cannot learn message text, attachment content, group content, or private keys from the server because those values are not present server-side.

## 3. Per-Table Data Classification

No listed column is plaintext. No listed column is a private key. All 10 application tables in the current backend schema are classified below, including the attachment storage surface covered by the task-4 sentinel and schema audit.

| Table | Column | Classification | Source |
| --- | --- | --- | --- |
| `users` | `id` | IDENTIFIER | `backend/migrations/0001_create_users.sql:1-6` |
| `users` | `username` | PUBLIC | `backend/migrations/0001_create_users.sql:1-6` |
| `users` | `identity_public_key` | PUBLIC | `backend/migrations/0001_create_users.sql:1-6` |
| `users` | `created_at` | TIMESTAMP | `backend/migrations/0001_create_users.sql:1-6` |
| `auth_challenges` | `id` | IDENTIFIER | `backend/migrations/0002_create_auth.sql:1-7` |
| `auth_challenges` | `user_id` | IDENTIFIER | `backend/migrations/0002_create_auth.sql:1-7` |
| `auth_challenges` | `nonce` | RANDOM-NONCE | `backend/migrations/0002_create_auth.sql:1-7` |
| `auth_challenges` | `created_at` | TIMESTAMP | `backend/migrations/0002_create_auth.sql:1-7` |
| `auth_challenges` | `expires_at` | TIMESTAMP | `backend/migrations/0002_create_auth.sql:1-7` |
| `sessions` | `token` | SESSION-TOKEN | `backend/migrations/0002_create_auth.sql:9-14` |
| `sessions` | `user_id` | IDENTIFIER | `backend/migrations/0002_create_auth.sql:9-14` |
| `sessions` | `created_at` | TIMESTAMP | `backend/migrations/0002_create_auth.sql:9-14` |
| `sessions` | `expires_at` | TIMESTAMP | `backend/migrations/0002_create_auth.sql:9-14` |
| `device_keys` | `user_id` | IDENTIFIER | `backend/migrations/0003_create_messages.sql:1-6` |
| `device_keys` | `x25519_public_key` | PUBLIC | `backend/migrations/0003_create_messages.sql:1-6` |
| `device_keys` | `key_signature` | PUBLIC | `backend/migrations/0003_create_messages.sql:1-6` |
| `device_keys` | `created_at` | TIMESTAMP | `backend/migrations/0003_create_messages.sql:1-6` |
| `messages` | `id` | ROUTING-METADATA | `backend/migrations/0003_create_messages.sql:8-14` |
| `messages` | `sender_id` | ROUTING-METADATA | `backend/migrations/0003_create_messages.sql:8-14` |
| `messages` | `recipient_id` | ROUTING-METADATA | `backend/migrations/0003_create_messages.sql:8-14` |
| `messages` | `ciphertext` | OPAQUE-CIPHERTEXT | `backend/migrations/0003_create_messages.sql:8-14` |
| `messages` | `created_at` | TIMESTAMP | `backend/migrations/0003_create_messages.sql:8-14` |
| `groups` | `id` | IDENTIFIER | `backend/migrations/0004_create_groups.sql:1-7` |
| `groups` | `name` | PUBLIC | `backend/migrations/0004_create_groups.sql:1-7` |
| `groups` | `creator_id` | ROUTING-METADATA | `backend/migrations/0004_create_groups.sql:1-7` |
| `groups` | `current_epoch` | ROUTING-METADATA | `backend/migrations/0004_create_groups.sql:1-7` |
| `groups` | `created_at` | TIMESTAMP | `backend/migrations/0004_create_groups.sql:1-7` |
| `group_members` | `group_id` | ROUTING-METADATA | `backend/migrations/0004_create_groups.sql:9-15` |
| `group_members` | `user_id` | ROUTING-METADATA | `backend/migrations/0004_create_groups.sql:9-15` |
| `group_members` | `joined_epoch` | ROUTING-METADATA | `backend/migrations/0004_create_groups.sql:9-15` |
| `group_members` | `added_at` | TIMESTAMP | `backend/migrations/0004_create_groups.sql:9-15` |
| `group_keys` | `group_id` | ROUTING-METADATA | `backend/migrations/0004_create_groups.sql:17-24` |
| `group_keys` | `epoch` | ROUTING-METADATA | `backend/migrations/0004_create_groups.sql:17-24` |
| `group_keys` | `member_id` | ROUTING-METADATA | `backend/migrations/0004_create_groups.sql:17-24` |
| `group_keys` | `wrapped_key` | OPAQUE-CIPHERTEXT | `backend/migrations/0004_create_groups.sql:17-24` |
| `group_keys` | `created_at` | TIMESTAMP | `backend/migrations/0004_create_groups.sql:17-24` |
| `group_messages` | `id` | ROUTING-METADATA | `backend/migrations/0004_create_groups.sql:26-33` |
| `group_messages` | `group_id` | ROUTING-METADATA | `backend/migrations/0004_create_groups.sql:26-33` |
| `group_messages` | `sender_id` | ROUTING-METADATA | `backend/migrations/0004_create_groups.sql:26-33` |
| `group_messages` | `epoch` | ROUTING-METADATA | `backend/migrations/0004_create_groups.sql:26-33` |
| `group_messages` | `ciphertext` | OPAQUE-CIPHERTEXT | `backend/migrations/0004_create_groups.sql:26-33` |
| `group_messages` | `created_at` | TIMESTAMP | `backend/migrations/0004_create_groups.sql:26-33` |
| `attachments` | `id` | IDENTIFIER | `backend/migrations/0005_create_attachments.sql:1-7` |
| `attachments` | `uploader_id` | ROUTING-METADATA | `backend/migrations/0005_create_attachments.sql:1-7` |
| `attachments` | `ciphertext` | OPAQUE-CIPHERTEXT | `backend/migrations/0005_create_attachments.sql:1-7` |
| `attachments` | `byte_size` | ROUTING-METADATA | `backend/migrations/0005_create_attachments.sql:1-7` |
| `attachments` | `created_at` | TIMESTAMP | `backend/migrations/0005_create_attachments.sql:1-7` |

The reusable schema audit independently verifies this shape for all application tables in `backend/scripts/zk_relay_audit.sh`. It enumerates the schema at runtime, so future application tables are automatically covered by the forbidden-column scan even before any table-specific shape assertion is added.

## 4. DM Data Flow

1. The production client encrypts plaintext on device using `MessageCrypto`. The envelope is ECIES-style: X25519 key agreement, HKDF-SHA256 derivation, AES-GCM sealing, and a base64 envelope containing version, ephemeral public key, and sealed bytes (`mac-app/Sources/ChatApp/Messaging/MessageCrypto.swift:16-35`). Production ECIES correctness is proven outside the task-4 gate by task-3's ciphertext-preservation backend test and the client's own E2E suite; task-4 audits the backend's relay/storage boundary.
2. The client sends only `{recipient_username, ciphertext}`. The task-4 Rust sentinel test constructs that same two-field wire body with a known sentinel encrypted client-side before it reaches the backend (`backend/tests/zk_sentinel.rs:270-284`).
3. The backend authenticates the bearer session and derives `sender_id` from that session, not from the request body (`backend/src/routes/messages.rs:97-106`).
4. The backend resolves `recipient_username` to `recipient_id` (`backend/src/routes/messages.rs:112-116`).
5. The backend inserts only `id`, `sender_id`, `recipient_id`, `ciphertext`, and `created_at` into SQLite (`backend/src/routes/messages.rs:118-130`).
6. The backend relays the same opaque ciphertext record through SSE for the recipient (`backend/src/routes/messages.rs:132-143`, `backend/src/routes/messages.rs:211-233`).
7. History reads return the stored ciphertext and routing metadata, not plaintext (`backend/src/routes/messages.rs:256-320`).

The task-4 Rust sentinel test keeps the one-time pad in the test process, decodes the stored ciphertext, and recovers the exact sentinel as an anti-vacuity control (`backend/tests/zk_sentinel.rs:321-327`). That proves the opaque blob genuinely encodes the sentinel while the backend only observes and persists ciphertext.

## 5. Backend Visibility

The backend can see:

- Participant identifiers and usernames needed for routing.
- Message ids and timestamps.
- Message counts, timing, and ciphertext sizes.
- Attachment ids, uploader ids, timestamps, and ciphertext sizes.
- Public identity keys, public X25519 prekeys, and signatures.
- Session tokens while they are valid.

The backend cannot see:

- Direct-message text.
- Attachment content. `POST /attachments` stores the request body verbatim as `attachments.ciphertext`, with `uploader_id` derived from the authenticated session and `byte_size` derived from the body length (`backend/src/routes/attachments.rs:32-62`). `GET /attachments/:id` returns the stored ciphertext bytes as `application/octet-stream` (`backend/src/routes/attachments.rs:65-85`).
- Group message plaintext. Current group message storage uses `group_messages.ciphertext` plus group routing metadata (`backend/migrations/0004_create_groups.sql:26-33`; `backend/src/routes/groups.rs:492-550`).
- Ed25519 identity private keys or X25519 private keys.

This is the standard Signal-model trade-off: message content remains confidential from the relay, while routing metadata remains observable to the relay.

## 6. Private-Key Handling

The Ed25519-compatible identity object wraps a private signing key and exposes only its public key string and signing operation (`mac-app/Sources/ChatApp/Identity/CryptoIdentity.swift:4-17`). `IdentityManager` creates or loads that private key from the Keychain (`mac-app/Sources/ChatApp/Identity/IdentityManager.swift:11-28`). `X25519KeyManager` separately creates or loads the X25519 agreement private key from a Keychain account dedicated to X25519 (`mac-app/Sources/ChatApp/Messaging/X25519KeyManager.swift:4-33`).

Only public material crosses to the backend. Registration sends `identity_public_key`, and prekey publication sends `x25519_public_key` plus `key_signature`. The backend validates the signature over the public prekey (`backend/src/routes/keys.rs:50-83`) and stores only `user_id`, `x25519_public_key`, `key_signature`, and `created_at` (`backend/src/routes/keys.rs:85-99`). Fetching a prekey returns only `user_id`, `username`, `identity_public_key`, `x25519_public_key`, and `key_signature` (`backend/src/routes/keys.rs:107-135`).

The task-1b identity gate names Keychain private-key persistence tests (`.agentloop/state/tasks/task-1b/verify.sh:8-11`). The task-3 live DM gate names the encrypted DM sentinel test and key publication checks (`.agentloop/state/tasks/task-3/verify.sh:142-145`, `.agentloop/state/tasks/task-3/verify.sh:168-202`, `.agentloop/state/tasks/task-3/verify.sh:277-284`).

## 7. Logging Posture

The backend performs no application-level body logging. A source audit for `println!`, `eprintln!`, `dbg!`, `tracing`, `log::`, `info!`, `debug!`, `warn!`, `error!`, `trace!`, `TraceLayer`, and `tracing_subscriber` across `backend/src` returns no matches. `lib.rs` builds the Axum router without a tracing or HTTP trace layer (`backend/src/lib.rs:8-21`), and `main.rs` starts the listener without installing a logging subscriber (`backend/src/main.rs:36-46`).

The task-4 verification leg captures backend stdout and stderr from the shipping `cargo run` binary, audits the migrated live database schema, and asserts that the sentinel and private-key markers are absent from captured server output (`.agentloop/state/tasks/task-4/verify.sh:258-311`).

Future logging invariant: backend logs must never include `ciphertext`, plaintext, attachment content, private keys, signatures, session tokens, or other key material. If logging is added later, it must remain metadata-only and the task-4 gate must continue to prove that no sentinel plaintext or private-key marker appears in server output.

## 8. Attachment Storage

Attachments follow the same relay rule as DMs: encrypt content before it reaches the server, send opaque bytes over the wire, store only ciphertext plus routing metadata server-side, and keep all private keys on device. The shipped attachment table is exactly `id`, `uploader_id`, `ciphertext`, `byte_size`, and `created_at` (`backend/migrations/0005_create_attachments.sql:1-7`). The upload route inserts those fields only, binds `uploader_id` from the authenticated session, stores the raw request body as the `ciphertext` BLOB, and records `byte_size` from `body.len()` (`backend/src/routes/attachments.rs:32-62`).

The attachment feature E2E is owned by task-7 and its live attachment gate. task-4 does not re-prove attachment product behavior; it proves the backend compliance boundary by sending encrypted sentinel attachment bytes through the real Rust route and then checking SQLite/raw bytes for plaintext absence.

## 9. Forward Compatibility

Current group-message routes already follow the same server storage pattern by accepting `epoch` plus `ciphertext`, deriving the sender from the authenticated session, and inserting `id`, `group_id`, `sender_id`, `epoch`, `ciphertext`, and `created_at` (`backend/src/routes/groups.rs:492-550`).

The schema audit is intentionally generic. It enumerates every application table and rejects plaintext-style or private-key column names before applying known shape assertions (`backend/scripts/zk_relay_audit.sh:89-136`). New tables are therefore covered automatically; a future `plaintext`, `content`, `private_key`, `secret_key`, or similar server-side column fails the audit. Sensitive table shapes are also pinned, including `attachments` as exactly `id,uploader_id,ciphertext,byte_size,created_at` (`backend/scripts/zk_relay_audit.sh:123-136`).

## 10. Verification / Reproduction

Run the schema audit against any file-backed backend SQLite database:

```bash
bash backend/scripts/zk_relay_audit.sh <db>
```

The audit prints `PRAGMA table_info` for every application table, classifies each column, rejects plaintext/private-key columns, pins the known sensitive table shapes including `attachments`, and ends with the zero-knowledge PASS line (`backend/scripts/zk_relay_audit.sh:97-150`).

Run the full task-4 sentinel, raw-bytes, schema, public-key, and log audit:

```bash
bash .agentloop/state/tasks/task-4/verify.sh
```

That gate is Swift-free. Step A builds and tests only the Rust backend with `cargo build` and `cargo test`, and requires the schema audit controls, message ciphertext-storage tests, and `zk_sentinel_roundtrip_stores_only_ciphertext_in_raw_db` to pass (`.agentloop/state/tasks/task-4/verify.sh:122-166`). The sentinel test boots the real `test_chat_backend::app` router in process, writes a file-backed SQLite DB, registers and signs in users, and exercises two known-sentinel surfaces:

- DM sentinel: the test sends a known sentinel as client-encrypted ciphertext, checks `messages` columns, proves stored ciphertext equals the wire value, checkpoints WAL before raw-byte reads, proves raw DB bytes contain the ciphertext but not the sentinel, verifies history/key responses expose no plaintext/private-key fields, and writes gate artifacts when `ZK_SENTINEL_*` variables are set (`backend/tests/zk_sentinel.rs:270-400`, `backend/tests/zk_sentinel.rs:490-498`).
- Attachment sentinel: the same test creates a distinct `ZK_ATTACH_SENTINEL_*`, encrypts it client-side, uploads the encrypted bytes through `POST /attachments`, checks the `attachments` shape, confirms stored BLOB and `byte_size`, decrypts the stored BLOB back to the sentinel as an anti-vacuity control, checkpoints WAL, proves raw DB bytes contain the ciphertext bytes but not the attachment sentinel, downloads the attachment ciphertext through `GET /attachments/:id`, and writes attachment artifacts for the shell gate (`backend/tests/zk_sentinel.rs:402-498`).

Step B independently re-reads those artifacts, scans the sentinel DB and sidecars with `strings`, confirms the `messages` row has only routing metadata plus the posted ciphertext, confirms the wire JSON keys are exactly `ciphertext,recipient_username`, checks that the attachment sentinel is absent from raw SQLite strings and the attachment metadata row, and runs `backend/scripts/zk_relay_audit.sh` against the populated sentinel DB (`.agentloop/state/tasks/task-4/verify.sh:168-256`). Step C boots the shipping backend binary with `cargo run -- --db-path "$DB2" --port "$PORT"`, waits for `/health`, runs the schema audit against that live migrated DB, and captures stdout/stderr to prove the logs contain neither the DM sentinel nor private-key markers (`.agentloop/state/tasks/task-4/verify.sh:258-311`).

Backing tests and artifacts:

- `backend/tests/zk_sentinel.rs`: Rust known-sentinel integration test and artifact producer for the raw-bytes proof.
- `backend/tests/zk_relay_audit.rs`: Rust positive control plus plaintext-column, private-key-column, and attachments-shape-drift negative controls for the schema audit (`backend/tests/zk_relay_audit.rs:21-172`).
- `backend/tests/messages.rs`: ciphertext-only DM storage and message schema tests (`backend/tests/messages.rs:410-435`, `backend/tests/messages.rs:740-758`).
- `backend/tests/attachments.rs`: ciphertext-only attachment storage and attachment schema tests (`backend/tests/attachments.rs:180-210`, `backend/tests/attachments.rs:267-314`).
- `backend/scripts/zk_relay_audit.sh`: reusable all-table schema audit.
- `.agentloop/state/tasks/task-4/verify.sh`: task-4 compliance gate leg.

The production ECIES cipher is proven separately by task-3, including `messages_post_stores_exactly_the_ciphertext_blob` (`backend/tests/messages.rs:410-440`). The attachment feature E2E is proven separately by task-7 and its live attachment gate. Those feature/cipher proofs are out of task-4 scope; task-4 proves that the backend stores and relays only opaque bytes plus routing metadata.

## 11. Root-Cause Note

task-4's verification leg is Swift-free, self-contained, and green when run in isolation with `bash .agentloop/state/tasks/task-4/verify.sh`. The overall `.agentloop/verify.sh` gate must still be green before task-4 can land, because it runs every task leg in sorted order. The rejection log's `LiveOfflineDeliveryE2ETests` failure belongs to task-8's offline-delivery leg and is an out-of-scope sibling failure for task-4.

## 12. Attestation / Acceptance Mapping

Date: 2026-06-04

Scope: current Rust backend SQLite schema, backend message/key routes, macOS client direct-message encryption/key storage, task-4 schema audit, and task-4 live sentinel verification leg.

Result: PASS when `bash .agentloop/state/tasks/task-4/verify.sh` completes successfully.

| Acceptance clause | Evidence |
| --- | --- |
| SQLite storage for a sent DM shows only ciphertext plus routing metadata. | `messages` schema has only `id`, `sender_id`, `recipient_id`, `ciphertext`, `created_at` (`backend/migrations/0003_create_messages.sql:8-14`); send handler inserts exactly those values (`backend/src/routes/messages.rs:120-130`); the sentinel test checks those columns and exact ciphertext preservation (`backend/tests/zk_sentinel.rs:289-319`); task-4 verify independently checks the populated DB row (`.agentloop/state/tasks/task-4/verify.sh:196-229`). |
| No readable message text appears server-side. | The sentinel is generated and encrypted in the Rust test before POSTing only `{recipient_username,ciphertext}` (`backend/tests/zk_sentinel.rs:270-284`); WAL is checkpointed before scanning DB and sidecar bytes (`backend/tests/zk_sentinel.rs:329-340`); task-4 verify asserts the sentinel is absent from raw SQLite strings and the selected DB row (`.agentloop/state/tasks/task-4/verify.sh:196-229`). |
| No attachment content appears server-side. | The sentinel test uploads encrypted `ZK_ATTACH_SENTINEL_*` bytes through the real attachment route, proves the stored BLOB decrypts back to the sentinel while raw DB bytes do not contain it, and confirms download returns only ciphertext (`backend/tests/zk_sentinel.rs:402-488`); the audit pins `attachments` as `id,uploader_id,ciphertext,byte_size,created_at` (`backend/scripts/zk_relay_audit.sh:123-126`); task-4 verify Step B independently greps the kept DB and sidecars for attachment sentinel absence and checks the attachment metadata row contains no plaintext (`.agentloop/state/tasks/task-4/verify.sh:231-246`). |
| No private keys appear server-side. | Private keys are created/loaded through Keychain managers (`mac-app/Sources/ChatApp/Identity/IdentityManager.swift:11-28`, `mac-app/Sources/ChatApp/Messaging/X25519KeyManager.swift:13-33`); server `device_keys` stores only public prekey and signature (`backend/migrations/0003_create_messages.sql:1-6`, `backend/src/routes/keys.rs:85-99`); the sentinel test checks public-only key responses and stored prekeys (`backend/tests/zk_sentinel.rs:371-400`); the audit has a private-key leak negative control (`backend/tests/zk_relay_audit.rs:118-143`). |
| Logs do not contain plaintext or private-key material. | Backend source has no body logging or trace layer (`backend/src/lib.rs:8-21`, `backend/src/main.rs:36-46`); task-4 verify captures stdout/stderr from the shipping backend binary and rejects sentinel/private-key markers (`.agentloop/state/tasks/task-4/verify.sh:258-311`). |
| Zero-knowledge property is verified by schema audit. | `backend/scripts/zk_relay_audit.sh` enumerates every table, classifies columns, rejects plaintext/private-key columns, and asserts known table shapes including `attachments` (`backend/scripts/zk_relay_audit.sh:89-150`); `backend/tests/zk_relay_audit.rs` covers pass, plaintext leak, private-key leak, and attachments-drift controls (`backend/tests/zk_relay_audit.rs:21-172`); task-4 verify runs the script against both the populated sentinel DB and a live shipping-binary DB (`.agentloop/state/tasks/task-4/verify.sh:248-256`, `.agentloop/state/tasks/task-4/verify.sh:283-292`). |
| Zero-knowledge property is verified by a known-sentinel raw-bytes test. | `backend/tests/zk_sentinel.rs` sends known client-encrypted DM and attachment sentinels, proves each stored blob decrypts back to its sentinel, checkpoints WAL, and scans DB plus sidecars for sentinel absence (`backend/tests/zk_sentinel.rs:270-340`, `backend/tests/zk_sentinel.rs:402-488`); task-4 verify re-runs the raw `strings` checks against the kept artifact DB (`.agentloop/state/tasks/task-4/verify.sh:168-246`). |
