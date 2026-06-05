# task-7-r7 Acceptance Evidence

This document maps the business acceptance clauses for task-7-r7 to the scoped gate evidence recorded in this task directory. The scoped gate evidence is `.agentloop/state/tasks/task-7-r7/scoped_gate_run.log`, the scope audit is `.agentloop/state/tasks/task-7-r7/gate_scope_audit.log`, and the live artifact paths are recorded in `.agentloop/state/tasks/task-7-r7/artifacts/latest.env`.

The latest scoped gate ended with:

```text
task-7-r7 verify: PASS
```

## Evidence Map

| Acceptance clause | Evidence |
| --- | --- |
| A user can attach a file to a direct message. | `scoped_gate_run.log` lines 142-160 run only `LiveDMAttachmentE2ETests`; lines 148-149 show `testSubscribedRecipientReceivesDownloadsAndDecryptsBinaryAttachment` passed, and line 160 records `task-7-r7 live DM round trip: PASS`. The UI and coordinator DM path is anchored in `ConversationView.swift:144` for file selection and `DMCoordinator.swift:141` for `sendAttachment(data:filename:mime:)`. |
| The recipient can download and decrypt the identical file. | `scoped_gate_run.log` lines 148-149 show the recipient live DM attachment test passed. `scripts/run_live_dm_roundtrip.sh:197` verifies `cmp -s "$ORIGINAL_FILE" "$DOWNLOADED_FILE"`, and `scripts/audit_live_dm_storage.sh:133` repeats the same byte comparison before auditing storage. |
| Downloaded bytes match the sender file exactly. | `artifacts/latest.env` lines 11-18 record `ORIGINAL_PATH_FILE`, `DOWNLOADED_PATH_FILE`, `ORIGINAL_FILE`, and `DOWNLOADED_FILE`. The live runner performs the exact byte comparison at `scripts/run_live_dm_roundtrip.sh:197`, and the audit runner repeats it at `scripts/audit_live_dm_storage.sh:133`. |
| Backend storage contains only encrypted attachment bytes plus routing metadata. | `backend/migrations/0005_create_attachments.sql:1` defines only `id`, `uploader_id`, `ciphertext`, `byte_size`, and `created_at`. `backend/src/routes/attachments.rs:43` inserts only those fields, binding the request body to `ciphertext` at line 49 and byte length at line 50. `scoped_gate_run.log` lines 165-179 show the live DB `attachments` schema with `ciphertext` as opaque ciphertext and `byte_size` as routing metadata. |
| Backend download returns encrypted bytes, not plaintext. | `backend/src/routes/attachments.rs:74` selects only `ciphertext` and line 85 returns it as `application/octet-stream`. The audit captures the authenticated GET body in the `GET_RESPONSE_FILE` live audit artifact recorded by `artifacts/latest.env` line 22; `scripts/audit_live_dm_storage.sh:224` requires it to equal `STORED_CIPHERTEXT_FILE`, line 228 requires it not to match the plaintext original, and line 232 scans it for both sentinels. |
| Stored attachment bytes equal the upload wire body and differ from plaintext. | The audit extracts the SQLite `attachments.ciphertext` blob to the `STORED_CIPHERTEXT_FILE` live audit artifact recorded by `artifacts/latest.env` line 21. It fails if stored ciphertext matches plaintext at `scripts/audit_live_dm_storage.sh:171`, requires stored ciphertext to match the captured upload wire body at line 175, and checks `attachments.byte_size` against the stored blob length at line 185. |
| Stored bytes include AES-GCM overhead for current file crypto. | `FileCrypto.swift:13` seals with AES-GCM and returns the combined nonce/ciphertext/tag at line 18. `scripts/audit_live_dm_storage.sh:186` requires stored length to be at least plaintext plus overhead and line 187 requires current FileCrypto overhead to be exactly 28 bytes. |
| Backend storage and logs do not contain the plaintext filename sentinel or file-content sentinel. | `artifacts/latest.env` lines 7-10 record distinct `FILENAME_SENTINEL`, `CONTENT_SENTINEL`, and their sentinel files. The audit scans the SQLite DB and sidecars, stored ciphertext, upload wire body, and live backend log at `scripts/audit_live_dm_storage.sh:59`; it scans the authenticated GET body and audit backend log at lines 232-233 and the schema audit log at line 245. `scoped_gate_run.log` line 320 records `task-7-r7 storage/log/authenticated download audit: PASS`. |
| Backend schema has no plaintext filename, MIME, descriptor, content, or secret columns. | `scoped_gate_run.log` lines 165-179 show the `attachments` table fields and classifications. Lines 319-320 record `ZERO-KNOWLEDGE SCHEMA AUDIT: PASS` and the storage/log/authenticated download audit pass. The audit writes the `SCHEMA_AUDIT_LOG` live audit artifact recorded by `artifacts/latest.env` line 24, invokes `backend/scripts/zk_relay_audit.sh "$DB_PATH"` at `scripts/audit_live_dm_storage.sh:236`, and requires the PASS text at line 241. |
| Targeted attachment crypto, service, and coordinator tests pass. | `scoped_gate_run.log` lines 14-22 show backend attachment tests passing, including plaintext-column and byte round-trip coverage. Lines 30-57 show `FileCryptoTests` passing, lines 58-80 show `AttachmentDescriptorTests` passing, lines 81-103 show `HTTPAttachmentServiceTests` passing, and lines 104-138 show `DMCoordinatorTests` passing. Line 139 records `task-7-r7 targeted tests: PASS`. |
| `verify.sh` runs only scoped attachment filters and exits 0. | `.agentloop/state/tasks/task-7-r7/verify.sh:32` parses task-local scripts, lines 36-39 run only the task-local scope check, targeted tests, live DM round trip, and storage audit scripts, and `scoped_gate_run.log` line 321 records `task-7-r7 verify: PASS`. |
| The scoped gate has no repo-root or `.agentloop/verify.sh` dependency. | `gate_scope_audit.log` lines 1-7 prove the repo-root gate delegates to the broad aggregate and is not this task gate, ending with `task-7-r7 scope audit: PASS`. `scripts/check_gate_scope.sh:87` checks for root or sibling gate calls, line 104 rejects unscoped Swift tests, and line 123 rejects forbidden live filters. |

## Artifact Index

`artifacts/latest.env` records the last live round-trip and audit input paths:

- `DB_PATH`: live SQLite database audited for the `attachments` row.
- `SERVER_LOG`: backend log from the live DM run.
- `ORIGINAL_FILE` and `DOWNLOADED_FILE`: sender plaintext sample and recipient decrypted download compared with `cmp -s`.
- `UPLOAD_WIRE_FILE`: captured encrypted request body uploaded to `/attachments`.
- `ATTACHMENT_ID` and `BOB_TOKEN`: routing/authentication values used for the authenticated download proof.
- `FILENAME_SENTINEL_FILE` and `CONTENT_SENTINEL_FILE`: distinct sentinels scanned out of storage, wire bodies, downloads, and logs.

The audit creates these live audit artifact paths inside `ARTIFACT_DIR` and records them back into `latest.env`:

- `stored-attachment-ciphertext.bin`: SQLite `attachments.ciphertext` extracted as binary.
- `authenticated-download-ciphertext.bin`: authenticated `GET /attachments/{id}` response body.
- `backend-authenticated-download.log`: log from the backend restarted for authenticated download proof.
- `zk-relay-audit.log`: schema audit output containing `ZERO-KNOWLEDGE SCHEMA AUDIT: PASS`.

## Scope Boundary

This evidence is for direct messages only. Group attachments are out of scope for task-7-r7 and are not claimed as task-7-r7 acceptance.
