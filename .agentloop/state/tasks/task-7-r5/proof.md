# task-7-r5 Scoped Attachment Gate Proof

Date: 2026-06-04

Command run for the saved green proof:

```sh
bash backend/scripts/reap_stale_backends.sh
set -o pipefail
bash .agentloop/state/tasks/task-7-r5/verify.sh 2>&1 | tee .agentloop/state/tasks/task-7-r5/scoped_gate_run.log
```

Result: exit 0. The saved log ends with:

```text
task-7 verify: PASS
```

Saved log: `.agentloop/state/tasks/task-7-r5/scoped_gate_run.log`

## Test Inventory

Rust attachment tests ran via `cargo test --test attachments` and passed all 5:

- `attachments_table_stores_no_plaintext_columns`
- `attachment_requires_bearer_token`
- `attachment_download_unknown_id_is_404`
- `attachment_upload_then_download_round_trips_exact_bytes`
- `attachment_upload_rejects_oversize_payload_with_413`

Swift attachment-scoped classes ran with exact counts and 0 failures:

- `FileCryptoTests`: 6 tests, 0 failures
- `AttachmentDescriptorTests`: 4 tests, 0 failures
- `HTTPAttachmentServiceTests`: 4 tests, 0 failures
- `DMCoordinatorTests`: 10 tests, 0 failures
- `LiveAttachmentE2ETests`: 2 tests, 0 failures

The 2 live attachment tests ran against `CHATAPP_LIVE_BACKEND_URL` and passed, not skipped:

- `testLiveAttachmentDMAndGroupRoundTripStoresOnlyCiphertext`
- `testAlreadySubscribedRecipientReceivesLiveAttachmentsAndWritesByteIdenticalDownloads`

## Scoped Exclusion

The gate runs only the five attachment-specific Swift classes using class-name filters. The saved green log contains no `LiveGroupE2ETests` or `LiveOfflineDeliveryE2ETests` run output, confirming the task-5/task-8 live suites were excluded from this attachment gate.

## Ciphertext Proofs

The gate completed the attachment zero-knowledge checks:

- DM and group live downloads written to disk were byte-identical to the live original file.
- Stored `attachments.ciphertext` did not equal the original plaintext.
- Captured upload wire body did not equal the original plaintext.
- Stored blob matched the captured upload wire body.
- Stored blob length equaled original bytes plus 28 bytes of AES-GCM overhead.
- `attachments.byte_size` matched the stored ciphertext length.
- Sentinel plaintext was absent from raw SQLite strings, stored blob, captured upload wire body, and authenticated download.
- `attachments` table columns remained exactly `id`, `uploader_id`, `ciphertext`, `byte_size`, `created_at`.
- `backend/scripts/zk_relay_audit.sh` printed `ZERO-KNOWLEDGE SCHEMA AUDIT: PASS`.

## Negative Control

Temporary gate-only edit: changed the expected `LiveAttachmentE2ETests` class count from `2` to `3`.

Observed result:

- Command: `bash .agentloop/state/tasks/task-7-r5/verify.sh > /tmp/task-7-r5-negative-control.log 2>&1`
- Exit code: 1
- Output included `task-7 verify: FAIL`
- Failure reason: `LiveAttachmentE2ETests did not execute exactly 3 tests with 0 failures`

The temporary edit was reverted, and the final saved green run returned to exit 0 with `task-7 verify: PASS`.

## Decoupling Note

This scoped gate proves attachment correctness without running `LiveGroupE2ETests` or `LiveOfflineDeliveryE2ETests`, the task-5/task-8 live suites that exhaust shared backend resources in the full root gate.
