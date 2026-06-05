# task-7-r6-b4 Ciphertext-Only Proof

Source artifacts:

- `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log`
- `.agentloop/state/tasks/task-7-r6/gate_repeatability.log`
- `.agentloop/state/tasks/task-7-r6/no_orphan_proof.log`

## Green Scoped Gate

Command:

```sh
bash .agentloop/state/tasks/task-7-r6/verify.sh
```

The full captured run is run 3 of the scoped attachment gate at `scoped_gate_run.log:3-4`. It starts by reaping stale backends at `scoped_gate_run.log:6-7`, uses a unique DB path at `scoped_gate_run.log:21`, starts the live backend at `scoped_gate_run.log:22`, gets HTTP 200 health at `scoped_gate_run.log:23`, shuts down and asserts zero residue at `scoped_gate_run.log:298`, and prints `task-7 verify: PASS` at `scoped_gate_run.log:299`.

## Test Inventory

Rust `backend/tests/attachments.rs` ran exactly 5 tests:

- `attachments_table_stores_no_plaintext_columns` passed at `scoped_gate_run.log:14`.
- `attachment_requires_bearer_token` passed at `scoped_gate_run.log:15`.
- `attachment_download_unknown_id_is_404` passed at `scoped_gate_run.log:16`.
- `attachment_upload_then_download_round_trips_exact_bytes` passed at `scoped_gate_run.log:17`.
- `attachment_upload_rejects_oversize_payload_with_413` passed at `scoped_gate_run.log:18`.
- The Rust count is `5 passed; 0 failed` at `scoped_gate_run.log:20`.

Deterministic Swift ran exactly the required 6 / 4 / 4 / 10 inventory:

- `FileCryptoTests`: 6 tests, 0 failures at `scoped_gate_run.log:70-84`: `testEncryptDecryptRoundTripReturnsExactBytesForBinaryPayload` at `scoped_gate_run.log:71-72`, `testEncryptDecryptRoundTripReturnsExactBytesForSmallPayload` at `scoped_gate_run.log:73-74`, `testEncryptedBlobDoesNotContainPlaintextBytes` at `scoped_gate_run.log:75-76`, `testNearTenMegabyteFileRoundTrips` at `scoped_gate_run.log:77-78`, `testTamperedBlobThrows` at `scoped_gate_run.log:79-80`, and `testWrongKeyFailsToDecrypt` at `scoped_gate_run.log:81-82`.
- `AttachmentDescriptorTests`: 4 tests, 0 failures at `scoped_gate_run.log:36-46`: `testDescriptorRoundTripsAndUsesSnakeCaseKeys` at `scoped_gate_run.log:37-38`, `testJSONWithoutAttachmentMarkerIsNotMisdetected` at `scoped_gate_run.log:39-40`, `testJSONWithWrongMarkerIsNotMisdetected` at `scoped_gate_run.log:41-42`, and `testPlainTextIsNotMisdetected` at `scoped_gate_run.log:43-44`.
- `HTTPAttachmentServiceTests`: 4 tests, 0 failures at `scoped_gate_run.log:85-95`: `testDownloadGetsAttachmentWithBearerTokenAndReturnsRawBytesOn200` at `scoped_gate_run.log:86-87`, `testDownloadReturnsNilFor404AndOtherErrors` at `scoped_gate_run.log:88-89`, `testUploadPostsOctetStreamBlobWithBearerTokenAndParsesAttachmentId` at `scoped_gate_run.log:90-91`, and `testUploadReturnsNilForNonSuccessStatusAndMalformedResponse` at `scoped_gate_run.log:92-93`.
- `DMCoordinatorTests`: 10 tests, 0 failures at `scoped_gate_run.log:47-69`: `testCancelLiveSubscriptionCancelsWithoutRemovingMessages` at `scoped_gate_run.log:48-49`, `testLoadHistoryDecryptsInboundRecordIntoDisplayMessages` at `scoped_gate_run.log:50-51`, `testLoadHistoryDetectsAttachmentDescriptorAndDownloadReturnsOriginalBytes` at `scoped_gate_run.log:52-53`, `testSendAttachmentUploadsEncryptedBlobAndSendsEncryptedDescriptor` at `scoped_gate_run.log:54-55`, `testSendEncryptsCiphertextAndRecipientCanDecryptIt` at `scoped_gate_run.log:56-57`, `testStartConversationRejectsPeerWithInvalidPrekeySignature` at `scoped_gate_run.log:58-59`, `testStartConversationShowsUserNotFoundForMissingPeer` at `scoped_gate_run.log:60-61`, `testSubscribeLiveCatchesUpOfflineHistoryInServerOrderAndDedupesSSE` at `scoped_gate_run.log:62-63`, `testSubscribeLiveDecryptsInboundRecordAndDedupesExistingMessages` at `scoped_gate_run.log:64-65`, and `testSubscribeLiveDeliversAttachmentDisplayDedupesAndDownloadsOriginalBytes` at `scoped_gate_run.log:66-67`.
- The deterministic selected-test total is 24 tests, 0 failures at `scoped_gate_run.log:97-99`.

Live Swift ran exactly 2 `LiveAttachmentE2ETests`:

- `testAlreadySubscribedRecipientReceivesLiveAttachmentsAndWritesByteIdenticalDownloads` passed at `scoped_gate_run.log:109-110`.
- `testLiveAttachmentDMAndGroupRoundTripStoresOnlyCiphertext` passed at `scoped_gate_run.log:111-112`.
- The live selected-test total is 2 tests, 0 failures at `scoped_gate_run.log:114-118`.

## Scoped Exclusion

The deterministic run begins at `scoped_gate_run.log:32` and executes only the deterministic attachment classes at `scoped_gate_run.log:36-95`. The live run begins at `scoped_gate_run.log:104` and executes only `LiveAttachmentE2ETests` at `scoped_gate_run.log:108-118`.

Fresh exclusion check:

```sh
rg -n "Test Suite '(LiveGroupE2ETests|LiveOfflineDeliveryE2ETests)'|Test Case '-\[ChatAppTests\.(LiveGroupE2ETests|LiveOfflineDeliveryE2ETests)" .agentloop/state/tasks/task-7-r6/scoped_gate_run.log
```

Result: no matches. The gate's live command is `swift test --skip-build --filter LiveAttachmentE2ETests` at `verify.sh:348`, and its absence checks for `LiveGroupE2ETests` / `LiveOfflineDeliveryE2ETests` are at `verify.sh:326-329` and `verify.sh:369-371`.

## Attachment IDs And Byte Counts

- DM attachment id: `33ca8213-52ec-44c2-84f1-b121ba4d6b2b` at `scoped_gate_run.log:123`.
- Group attachment id: `89574f85-e7c2-44cc-9ef9-af2865a2e092` at `scoped_gate_run.log:124`.
- DM and group attachment rows both exist: `attachment rows for dm_and_group=2` at `scoped_gate_run.log:137`.
- Byte counts: `original=91`, `stored=119`, `wire=119`, `attachment_byte_size=119`, `overhead=28` at `scoped_gate_run.log:134`.
- Numeric proof: `91 + 28 = 119`, so `stored == original + 28 == attachments.byte_size`, and `wire == stored`.
- Authenticated `GET /attachments/<id>` response size is `119` bytes at `scoped_gate_run.log:136`, matching the stored and wire ciphertext size at `scoped_gate_run.log:134`.

## Comparison Proofs

- DM decrypted download is byte-identical to the original: `cmp live_original live_dm_download PASS` at `scoped_gate_run.log:125`.
- Group decrypted download is byte-identical to the original: `cmp live_original live_group_download PASS` at `scoped_gate_run.log:126`.
- Stored SQLite blob is not plaintext: `cmp original stored_blob DIFFERENT` at `scoped_gate_run.log:128`.
- Captured upload wire body is not plaintext: `cmp original upload_wire DIFFERENT` at `scoped_gate_run.log:129`.
- Stored SQLite blob equals the captured upload wire body: `cmp stored_blob upload_wire PASS` at `scoped_gate_run.log:130`.

## Sentinel Absence

The plaintext sentinel is absent from every required storage and transport surface:

- Raw SQLite strings across the DB, `-wal`, and `-shm`: `sentinel absent raw_sqlite_strings PASS` at `scoped_gate_run.log:131`.
- Extracted stored blob: `sentinel absent stored_blob PASS` at `scoped_gate_run.log:132`.
- Captured upload wire body: `sentinel absent upload_wire PASS` at `scoped_gate_run.log:133`.
- Authenticated `GET /attachments/<id>` response: `sentinel absent authenticated_get_response PASS` at `scoped_gate_run.log:135`.

## Schema And Audit

- Exact `attachments` columns are `id,uploader_id,ciphertext,byte_size,created_at` at `scoped_gate_run.log:139`.
- `PRAGMA table_info(attachments)` confirms the five columns at `scoped_gate_run.log:143-151`.
- The audit classifies `ciphertext` as `opaque-ciphertext` and does not expose a plaintext column at `scoped_gate_run.log:152-157`.
- `ZERO-KNOWLEDGE SCHEMA AUDIT: PASS` is printed at `scoped_gate_run.log:297`.

## Determinism And Residue

`gate_repeatability.log` records three consecutive scoped gate runs:

- Run 1: command at `gate_repeatability.log:5`, exit 0 at `gate_repeatability.log:6`, final line `task-7 verify: PASS` at `gate_repeatability.log:7`.
- Run 2: command at `gate_repeatability.log:10`, exit 0 at `gate_repeatability.log:11`, final line `task-7 verify: PASS` at `gate_repeatability.log:12`.
- Run 3: command at `gate_repeatability.log:15`, exit 0 at `gate_repeatability.log:16`, final line `task-7 verify: PASS` at `gate_repeatability.log:17`.
- Summary: `3/3 PASS` at `gate_repeatability.log:20`.

`no_orphan_proof.log` records zero residue:

- Initial reaper found `reaped 0 stale test-chat-backend process(es)` at `no_orphan_proof.log:5-6`.
- Post-run `pgrep` output is `<empty>` for run 1 at `no_orphan_proof.log:8-14`, run 2 at `no_orphan_proof.log:16-22`, and run 3 at `no_orphan_proof.log:24-30`.

## Self-Containment

Fresh self-containment grep:

```sh
rg -n "\.agentloop/verify\.sh|bash verify\.sh|TASK_7_R5|task-7-r5" .agentloop/state/tasks/task-7-r6/verify.sh
```

Result: no matches. The scoped gate invokes `cargo test --test attachments` at `verify.sh:197`, the deterministic Swift filtered run at `verify.sh:299-305`, and the live attachment-only run at `verify.sh:348`; it ends with `task-7 verify: PASS` at `verify.sh:511`.
