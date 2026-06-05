# task-7-r5-b1 Scoped Attachment Gate Proof

Date: 2026-06-05

Acceptance for this builder item is the scoped task gate only:

```sh
bash backend/scripts/reap_stale_backends.sh
bash .agentloop/state/tasks/task-7-r5/verify.sh
```

The repo-root `bash verify.sh` aggregator was not used. It is explicitly out of
scope for this builder item because it runs unrelated task gates before
`task-7-r5`.

## Static Gate Validation

The gate parsed successfully:

```sh
bash -n .agentloop/state/tasks/task-7-r5/verify.sh
```

Static grep checks confirmed the gate is self-contained and attachment-scoped:

- Runs `cargo test --test attachments`.
- Requires all 5 Rust attachment tests:
  `attachment_upload_then_download_round_trips_exact_bytes`,
  `attachment_upload_rejects_oversize_payload_with_413`,
  `attachment_requires_bearer_token`,
  `attachment_download_unknown_id_is_404`, and
  `attachments_table_stores_no_plaintext_columns`.
- Boots one local backend on a free port via `pick_port`, polls `/health` with a
  bounded loop, and uses `trap cleanup EXIT`.
- Exports `CHATAPP_LIVE_BACKEND_URL`.
- Runs only the Swift attachment filters `FileCryptoTests`,
  `AttachmentDescriptorTests`, `HTTPAttachmentServiceTests`,
  `DMCoordinatorTests`, and `LiveAttachmentE2ETests`.
- Enforces exact Swift class counts of 6, 4, 4, 10, and 2 with 0 failures.
- Requires the two live attachment methods to pass and not skip:
  `testLiveAttachmentDMAndGroupRoundTripStoresOnlyCiphertext` and
  `testAlreadySubscribedRecipientReceivesLiveAttachmentsAndWritesByteIdenticalDownloads`.
- Names `LiveGroupE2ETests` and `LiveOfflineDeliveryE2ETests` only in the
  excluded-suite absence assertion.
- Retains ciphertext, byte-size, sentinel, schema, and
  `zk_relay_audit.sh` proofs.
- Ends with `echo "task-7 verify: PASS"`.

Self-containment grep:

```sh
rg -n "(^|[^[:alnum:]_./-])(bash|sh)?[[:space:]]*(\./)?verify\.sh|\.agentloop/verify\.sh|state/tasks/.*/verify\.sh" \
  .agentloop/state/tasks/task-7-r5/verify.sh
```

Result: no matches. The scoped gate does not call the repo-root `verify.sh`,
`.agentloop/verify.sh`, or any other task gate.

## Determinism

After reaping stale backends, the scoped gate was run three consecutive times:

```sh
bash backend/scripts/reap_stale_backends.sh
bash .agentloop/state/tasks/task-7-r5/verify.sh
bash .agentloop/state/tasks/task-7-r5/verify.sh
bash .agentloop/state/tasks/task-7-r5/verify.sh
```

All three runs exited 0 and ended with `task-7 verify: PASS`.

Durable summary: `.agentloop/state/tasks/task-7-r5/gate_repeatability.log`

```text
run 1: exit 0
run 1: final line: task-7 verify: PASS
run 1: PASS

run 2: exit 0
run 2: final line: task-7 verify: PASS
run 2: PASS

run 3: exit 0
run 3: final line: task-7 verify: PASS
run 3: PASS

result: 3/3 PASS
```

The final full run was saved to
`.agentloop/state/tasks/task-7-r5/scoped_gate_run.log`; its final line is:

```text
task-7 verify: PASS
```

A post-run stale-backend reap reported `reaped 0 stale test-chat-backend process(es)`.

## Test Inventory From Saved Final Run

Rust attachment tests in `scoped_gate_run.log` all passed:

- `attachments_table_stores_no_plaintext_columns ... ok`
- `attachment_requires_bearer_token ... ok`
- `attachment_download_unknown_id_is_404 ... ok`
- `attachment_upload_then_download_round_trips_exact_bytes ... ok`
- `attachment_upload_rejects_oversize_payload_with_413 ... ok`

Swift attachment-scoped classes in `scoped_gate_run.log` passed with exact counts:

- `AttachmentDescriptorTests`: executed 4 tests, 0 failures.
- `DMCoordinatorTests`: executed 10 tests, 0 failures.
- `FileCryptoTests`: executed 6 tests, 0 failures.
- `HTTPAttachmentServiceTests`: executed 4 tests, 0 failures.
- `LiveAttachmentE2ETests`: executed 2 tests, 0 failures.
- Selected Swift run total: executed 26 tests, 0 failures.

The two live attachment methods passed against the gate-booted backend:

- `testAlreadySubscribedRecipientReceivesLiveAttachmentsAndWritesByteIdenticalDownloads`
- `testLiveAttachmentDMAndGroupRoundTripStoresOnlyCiphertext`

Neither method was skipped.

## Scoped Exclusion

The saved final run contains no `LiveGroupE2ETests` or
`LiveOfflineDeliveryE2ETests` output:

```sh
rg -n "LiveGroupE2ETests|LiveOfflineDeliveryE2ETests" \
  .agentloop/state/tasks/task-7-r5/scoped_gate_run.log
```

Result: no matches.

## Ciphertext And Schema Proofs

The saved final run completed these attachment privacy checks:

- Stored `attachments.ciphertext` did not equal original plaintext.
- Captured upload wire body did not equal original plaintext.
- Stored blob matched the captured upload wire body.
- Stored blob length equaled original bytes plus 28 bytes of AES-GCM overhead.
- `attachments.byte_size` matched the stored ciphertext length.
- Sentinel plaintext was absent from raw SQLite strings, stored blob, captured
  upload wire body, and authenticated download.
- Live DM and group downloads written to disk were byte-identical to the live
  original file.
- The `attachments` schema stayed exactly `id`, `uploader_id`, `ciphertext`,
  `byte_size`, `created_at`.
- `backend/scripts/zk_relay_audit.sh` printed
  `ZERO-KNOWLEDGE SCHEMA AUDIT: PASS`.
