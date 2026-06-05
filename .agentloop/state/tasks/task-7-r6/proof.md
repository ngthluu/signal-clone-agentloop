# task-7-r6-b1 Proof

## Scoped Gate

- Gate: `.agentloop/state/tasks/task-7-r6/verify.sh`
- Syntax: `bash -n .agentloop/state/tasks/task-7-r6/verify.sh` exits 0.
- The gate is self-contained: grep for `.agentloop/verify.sh`, `bash verify.sh`, root `verify.sh`, `TASK_7_R5`, and `task-7-r5` returns no matches.
- The live Swift command is exactly scoped at `verify.sh:336`: `swift test --skip-build --filter LiveAttachmentE2ETests`.
- The deterministic Swift command is separate at `verify.sh:287-292`: `swift test --skip-build --filter FileCryptoTests --filter AttachmentDescriptorTests --filter HTTPAttachmentServiceTests --filter DMCoordinatorTests`.

## Test Inventory From Captured Green Run

Captured run: `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log`

- Rust attachments: five tests passed at `scoped_gate_run.log:9-15`.
  - `attachments_table_stores_no_plaintext_columns`
  - `attachment_requires_bearer_token`
  - `attachment_download_unknown_id_is_404`
  - `attachment_upload_then_download_round_trips_exact_bytes`
  - `attachment_upload_rejects_oversize_payload_with_413`
- Swift deterministic classes:
  - `AttachmentDescriptorTests`: 4 tests, 0 failures at `scoped_gate_run.log:39-40`.
  - `DMCoordinatorTests`: 10 tests, 0 failures at `scoped_gate_run.log:62-63`.
  - `FileCryptoTests`: 6 tests, 0 failures at `scoped_gate_run.log:77-78`.
  - `HTTPAttachmentServiceTests`: 4 tests, 0 failures at `scoped_gate_run.log:88-89`.
- Swift live class:
  - `testAlreadySubscribedRecipientReceivesLiveAttachmentsAndWritesByteIdenticalDownloads` passed at `scoped_gate_run.log:103-104`.
  - `testLiveAttachmentDMAndGroupRoundTripStoresOnlyCiphertext` passed at `scoped_gate_run.log:105-106`.
  - `LiveAttachmentE2ETests`: 2 tests, 0 failures at `scoped_gate_run.log:107-108`.

## Scoped Exclusion

- `rg -n "LiveGroupE2ETests|LiveOfflineDeliveryE2ETests" .agentloop/state/tasks/task-7-r6/scoped_gate_run.log` returns no matches.
- The gate names those suites only through the absence assertion list at `verify.sh:314-319` and `verify.sh:357-362`.

## Ciphertext-Only Proofs

The gate retains the r5 storage checks:

- All live artifact files must exist and be non-empty: `verify.sh:364-373`.
- DM and group on-disk downloads must be byte-identical to the live original file: `verify.sh:394-399`.
- The DM blob is extracted from SQLite with `writefile(blob, ciphertext)`: `verify.sh:404-407`.
- Stored blob must not equal the plaintext original, upload wire body must not equal plaintext, and stored blob must equal upload wire body: `verify.sh:409-417`.
- Sentinel plaintext is rejected in raw SQLite strings, stored blob, upload wire body, and authenticated download response: `verify.sh:419-446`.
- Stored ciphertext length must equal original bytes plus 28 bytes of AES-GCM overhead, and must equal `attachments.byte_size`: `verify.sh:429-437`.
- Both DM and group attachment rows must exist: `verify.sh:448-452`.
- Attachment columns must be exactly `id,uploader_id,ciphertext,byte_size,created_at`: `verify.sh:454-459`.
- Zero-knowledge schema audit must print `ZERO-KNOWLEDGE SCHEMA AUDIT: PASS`: `verify.sh:463-469`; captured at `scoped_gate_run.log:276`.
- Captured final verdict: `task-7 verify: PASS` at `scoped_gate_run.log:277`.

## Determinism

After `bash backend/scripts/reap_stale_backends.sh`, the scoped gate was run three consecutive times.

- `gate_repeatability.log` records:
  - run 1: exit 0, final `task-7 verify: PASS`
  - run 2: exit 0, final `task-7 verify: PASS`
  - run 3: exit 0, final `task-7 verify: PASS`
  - result: 3/3 PASS

The third full run is captured in `scoped_gate_run.log`.
