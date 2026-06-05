# task-7-r7 Acceptance Evidence

This document maps the business acceptance clauses for task-7-r7 to the scoped gate evidence recorded in this task directory. The scoped gate evidence is `.agentloop/state/tasks/task-7-r7/scoped_gate_run.log`, with artifact locations recorded in `.agentloop/state/tasks/task-7-r7/artifacts/latest.env`.

The latest scoped gate ended with:

```text
task-7-r7 verify: PASS
```

## Evidence Map

| Acceptance clause | Evidence |
| --- | --- |
| A user can attach a file to a direct message. | `scoped_gate_run.log` lines 275-283 run only `LiveDMAttachmentE2ETests`, including `testSubscribedRecipientReceivesDownloadsAndDecryptsBinaryAttachment`, and the test passes. The UI and coordinator DM path is anchored in `ConversationView.swift:144` for file selection and `DMCoordinator.swift:141` for `sendAttachment(data:filename:mime:)`. |
| The recipient can download and decrypt the identical file. | `scoped_gate_run.log` lines 280-283 show the live DM attachment test passed. `scripts/run_live_dm_roundtrip.sh:165` verifies `cmp -s "$ORIGINAL_FILE" "$DOWNLOADED_FILE"`, and `scoped_gate_run.log` line 293 records `task-7-r7 live DM round trip: PASS`. |
| Downloaded bytes match the sender file exactly. | `artifacts/latest.env` records `ORIGINAL_FILE`, `DOWNLOADED_FILE`, `ORIGINAL_PATH_FILE`, and `DOWNLOADED_PATH_FILE`. The live runner performs the byte comparison at `scripts/run_live_dm_roundtrip.sh:165`, and the audit runner repeats it at `scripts/audit_live_dm_storage.sh:101`. |
| Backend storage contains only encrypted attachment bytes plus routing metadata. | `backend/migrations/0005_create_attachments.sql:1` defines only `id`, `uploader_id`, `ciphertext`, `byte_size`, and `created_at`. `backend/src/routes/attachments.rs:43` inserts only those fields, binding the request body to `ciphertext` at line 49 and byte length at line 50. `scoped_gate_run.log` lines 304-311 show the live DB `attachments` schema with `ciphertext` as opaque ciphertext and `byte_size` as routing metadata. |
| Backend download returns encrypted bytes, not plaintext. | `backend/src/routes/attachments.rs:74` selects only `ciphertext` and line 85 returns it as `application/octet-stream`. The audit captures the authenticated GET body in `authenticated-download-ciphertext.bin`; `scripts/audit_live_dm_storage.sh:184` requires it to equal `stored-attachment-ciphertext.bin`, line 188 requires it not to match the plaintext original, and line 192 scans it for both sentinels. |
| Stored attachment bytes equal the upload wire body and differ from plaintext. | The audit extracts the SQLite `attachments.ciphertext` blob to `stored-attachment-ciphertext.bin` at `scripts/audit_live_dm_storage.sh:122`. It fails if stored ciphertext matches plaintext at line 131, requires stored ciphertext to match the captured upload wire body at line 135, and checks `attachments.byte_size` against the stored blob length at line 145. |
| Stored bytes include AES-GCM overhead for current file crypto. | `FileCrypto.swift:13` seals with AES-GCM and returns the combined nonce/ciphertext/tag at line 18. `scripts/audit_live_dm_storage.sh:146` requires stored length to be at least plaintext plus overhead and line 147 requires current FileCrypto overhead to be exactly 28 bytes. |
| Backend storage and logs do not contain the plaintext filename sentinel or file-content sentinel. | `artifacts/latest.env` records distinct `FILENAME_SENTINEL`, `CONTENT_SENTINEL`, and their sentinel files. The audit scans the SQLite DB and sidecars, stored ciphertext, upload wire body, and live backend log at `scripts/audit_live_dm_storage.sh:59` and `:149`; it scans the authenticated GET body and audit backend log at lines 192-193. `scoped_gate_run.log` line 453 records `task-7-r7 storage/log/authenticated download audit: PASS`. |
| Backend schema has no plaintext filename, MIME, descriptor, content, or secret columns. | `scoped_gate_run.log` lines 304-311 show the `attachments` table fields and classifications. Lines 452-453 record `ZERO-KNOWLEDGE SCHEMA AUDIT: PASS` and the storage/log/authenticated download audit pass. The audit invokes `backend/scripts/zk_relay_audit.sh "$DB_PATH"` at `scripts/audit_live_dm_storage.sh:196` and requires the PASS text at line 201. |
| Targeted attachment crypto, service, and coordinator tests pass. | `scoped_gate_run.log` lines 157-159 show backend attachment round-trip and exact 10 MB acceptance tests passing. Lines 167-184 show `FileCryptoTests` passing, lines 194-206 show `AttachmentDescriptorTests` passing, lines 216-228 show `HTTPAttachmentServiceTests` passing, and lines 238-262 show `DMCoordinatorTests` passing. Line 272 records `task-7-r7 targeted tests: PASS`. |
| `verify.sh` runs only scoped attachment filters and exits 0. | `.agentloop/state/tasks/task-7-r7/verify.sh:30` parses task-local scripts, line 91 checks for root aggregator calls, line 92 checks for unscoped Swift tests, line 93 checks forbidden live filters, and lines 95-97 run only the task-local targeted, live DM, and audit scripts. `scoped_gate_run.log` line 454 records `task-7-r7 verify: PASS`. |
| The scoped gate has no repo-root or `.agentloop/verify.sh` dependency. | `.agentloop/state/tasks/task-7-r7/verify.sh:51` defines `check_no_root_aggregator_calls`, and lines 56-61 fail on root `verify.sh` or `.agentloop/verify.sh` calls before expensive work starts. |

## Artifact Index

`artifacts/latest.env` records the last live round-trip and audit inputs:

- `DB_PATH`: live SQLite database audited for the `attachments` row.
- `SERVER_LOG`: backend log from the live DM run.
- `ORIGINAL_FILE` and `DOWNLOADED_FILE`: sender plaintext sample and recipient decrypted download compared with `cmp -s`.
- `UPLOAD_WIRE_FILE`: captured encrypted request body uploaded to `/attachments`.
- `ATTACHMENT_ID` and `BOB_TOKEN`: routing/authentication values used for the authenticated download proof.
- `FILENAME_SENTINEL_FILE` and `CONTENT_SENTINEL_FILE`: distinct sentinels scanned out of storage, wire bodies, downloads, and logs.

The audit creates these files inside `ARTIFACT_DIR`:

- `stored-attachment-ciphertext.bin`: SQLite `attachments.ciphertext` extracted as binary.
- `authenticated-download-ciphertext.bin`: authenticated `GET /attachments/{id}` response body.
- `backend-authenticated-download.log`: log from the backend restarted for authenticated download proof.
- `zk-relay-audit.log`: schema audit output containing `ZERO-KNOWLEDGE SCHEMA AUDIT: PASS`.

## Scope Boundary

This evidence is for direct messages only. Group attachments are out of scope for task-7-r7 and are not claimed as task-7-r7 acceptance.
