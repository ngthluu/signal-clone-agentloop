# task-7-r5 Acceptance Evidence

Captured on 2026-06-05 from the task-local scoped gate log
`.agentloop/state/tasks/task-7-r5/scoped_gate_run.log`.

This item is judged by the scoped attachment gate:

```sh
bash .agentloop/state/tasks/task-7-r5/verify.sh
```

The repo-root `bash verify.sh` aggregator is NOT this item's gate. The root
aggregator runs every task gate alphabetically, reaches task-1d before
task-7-r5, and task-1d runs a bare full-suite `swift test` that launches
unrelated heavy live suites. This task's acceptance is therefore pinned to the
attachment-only scoped command above and the durable evidence below.

## Deterministic Command Evidence

### `bash .agentloop/state/tasks/task-7-r5/verify.sh`

Exit status: 0 in the saved scoped run. Final line:

```text
task-7 verify: PASS
```

The saved run proves:

- Rust `cargo test --test attachments`: 5 tests passed, 0 failed.
- Swift attachment classes: `AttachmentDescriptorTests` 4, `DMCoordinatorTests`
  10, `FileCryptoTests` 6, `HTTPAttachmentServiceTests` 4,
  `LiveAttachmentE2ETests` 2; all with 0 failures.
- The two live attachment tests passed against the gate-booted backend with
  `CHATAPP_LIVE_BACKEND_URL` exported by the gate.
- `LiveGroupE2ETests` and `LiveOfflineDeliveryE2ETests` were not invoked.
- Ciphertext, byte-size, sentinel, schema, and zero-knowledge audit proofs ran.

## Clause to Evidence Map

| # | Acceptance criterion | Deterministic command | Current file:line / log proof |
| --- | --- | --- | --- |
| 1 | Rust attachment test `attachment_upload_then_download_round_trips_exact_bytes` passes. | `bash .agentloop/state/tasks/task-7-r5/verify.sh` runs `cargo test --test attachments`. | Test source: `backend/tests/attachments.rs:171`; gate command/assertions: `.agentloop/state/tasks/task-7-r5/verify.sh:181-212`; saved log: `.agentloop/state/tasks/task-7-r5/scoped_gate_run.log:12` shows `... ok`, and `:15` shows `5 passed; 0 failed`. |
| 2 | Rust attachment test `attachment_upload_rejects_oversize_payload_with_413` passes. | `bash .agentloop/state/tasks/task-7-r5/verify.sh` runs `cargo test --test attachments`. | Test source: `backend/tests/attachments.rs:214`; gate required-name assertion: `.agentloop/state/tasks/task-7-r5/verify.sh:202-212`; saved log: `.agentloop/state/tasks/task-7-r5/scoped_gate_run.log:13` shows `... ok`, and `:15` shows `5 passed; 0 failed`. |
| 3 | Rust attachment test `attachment_requires_bearer_token` passes. | `bash .agentloop/state/tasks/task-7-r5/verify.sh` runs `cargo test --test attachments`. | Test source: `backend/tests/attachments.rs:235`; gate required-name assertion: `.agentloop/state/tasks/task-7-r5/verify.sh:202-212`; saved log: `.agentloop/state/tasks/task-7-r5/scoped_gate_run.log:10` shows `... ok`, and `:15` shows `5 passed; 0 failed`. |
| 4 | Rust attachment test `attachment_download_unknown_id_is_404` passes. | `bash .agentloop/state/tasks/task-7-r5/verify.sh` runs `cargo test --test attachments`. | Test source: `backend/tests/attachments.rs:254`; gate required-name assertion: `.agentloop/state/tasks/task-7-r5/verify.sh:202-212`; saved log: `.agentloop/state/tasks/task-7-r5/scoped_gate_run.log:11` shows `... ok`, and `:15` shows `5 passed; 0 failed`. |
| 5 | Rust attachment test `attachments_table_stores_no_plaintext_columns` passes. | `bash .agentloop/state/tasks/task-7-r5/verify.sh` runs `cargo test --test attachments`. | Test source: `backend/tests/attachments.rs:268`; no-plaintext schema expectation: `backend/tests/attachments.rs:279-313`; gate required-name assertion: `.agentloop/state/tasks/task-7-r5/verify.sh:202-212`; saved log: `.agentloop/state/tasks/task-7-r5/scoped_gate_run.log:9` shows `... ok`, and `:15` shows `5 passed; 0 failed`. |
| 6 | `FileCryptoTests` passes all 6 tests. | `bash .agentloop/state/tasks/task-7-r5/verify.sh` runs `swift test --skip-build --filter FileCryptoTests ...`. | Test class: `mac-app/Tests/ChatAppTests/FileCryptoTests.swift:6`; test methods begin at `:7`, `:18`, `:29`, `:40`, `:50`, `:61`; gate filter/count assertion: `.agentloop/state/tasks/task-7-r5/verify.sh:282-313`; saved log: `.agentloop/state/tasks/task-7-r5/scoped_gate_run.log:64-78` shows all 6 passed and `Executed 6 tests, with 0 failures`. |
| 7 | `AttachmentDescriptorTests` passes all 4 tests. | `bash .agentloop/state/tasks/task-7-r5/verify.sh` runs `swift test --skip-build --filter AttachmentDescriptorTests ...`. | Test class: `mac-app/Tests/ChatAppTests/AttachmentDescriptorTests.swift:6`; test methods begin at `:7`, `:31`, `:35`, `:41`; gate filter/count assertion: `.agentloop/state/tasks/task-7-r5/verify.sh:282-313`; saved log: `.agentloop/state/tasks/task-7-r5/scoped_gate_run.log:30-40` shows all 4 passed and `Executed 4 tests, with 0 failures`. |
| 8 | `HTTPAttachmentServiceTests` passes all 4 tests. | `bash .agentloop/state/tasks/task-7-r5/verify.sh` runs `swift test --skip-build --filter HTTPAttachmentServiceTests ...`. | Test class: `mac-app/Tests/ChatAppTests/HTTPAttachmentServiceTests.swift:5`; test methods begin at `:11`, `:33`, `:49`, `:64`; gate filter/count assertion: `.agentloop/state/tasks/task-7-r5/verify.sh:282-313`; saved log: `.agentloop/state/tasks/task-7-r5/scoped_gate_run.log:79-89` shows all 4 passed and `Executed 4 tests, with 0 failures`. |
| 9 | `DMCoordinatorTests` passes all 10 tests. | `bash .agentloop/state/tasks/task-7-r5/verify.sh` runs `swift test --skip-build --filter DMCoordinatorTests ...`. | Test class: `mac-app/Tests/ChatAppTests/DMCoordinatorTests.swift:6`; attachment-specific DM tests at `:75`, `:134`, `:228`; gate filter/count assertion: `.agentloop/state/tasks/task-7-r5/verify.sh:282-313`; saved log: `.agentloop/state/tasks/task-7-r5/scoped_gate_run.log:41-63` shows all 10 passed and `Executed 10 tests, with 0 failures`. |
| 10 | Live attachment test `testLiveAttachmentDMAndGroupRoundTripStoresOnlyCiphertext` passes against a live backend. | `bash .agentloop/state/tasks/task-7-r5/verify.sh` boots a backend, exports `CHATAPP_LIVE_BACKEND_URL`, and runs `swift test --filter LiveAttachmentE2ETests`. | Live backend setup/env: `.agentloop/state/tasks/task-7-r5/verify.sh:214-265`; test source: `mac-app/Tests/ChatAppTests/LiveAttachmentE2ETests.swift:21`; live test pass/not-skipped assertion: `.agentloop/state/tasks/task-7-r5/verify.sh:313-316`; saved log: `.agentloop/state/tasks/task-7-r5/scoped_gate_run.log:93-94` shows the test passed, and `:96` shows `Executed 2 tests, with 0 failures`. |
| 11 | Live attachment test `testAlreadySubscribedRecipientReceivesLiveAttachmentsAndWritesByteIdenticalDownloads` passes against a live backend. | `bash .agentloop/state/tasks/task-7-r5/verify.sh` boots a backend, exports `CHATAPP_LIVE_BACKEND_URL`, and runs `swift test --filter LiveAttachmentE2ETests`. | Live backend setup/env: `.agentloop/state/tasks/task-7-r5/verify.sh:214-265`; test source: `mac-app/Tests/ChatAppTests/LiveAttachmentE2ETests.swift:126`; live test pass/not-skipped assertion: `.agentloop/state/tasks/task-7-r5/verify.sh:313-316`; saved log: `.agentloop/state/tasks/task-7-r5/scoped_gate_run.log:91-92` shows the test passed, and `:96` shows `Executed 2 tests, with 0 failures`. |
| 12 | The scoped gate explicitly excludes `LiveGroupE2ETests` and `LiveOfflineDeliveryE2ETests`. | `bash .agentloop/state/tasks/task-7-r5/verify.sh` runs only the five attachment-specific Swift class filters and fails if either excluded suite appears in Swift output. | Included filters only: `.agentloop/state/tasks/task-7-r5/verify.sh:282-293`; absence assertion: `.agentloop/state/tasks/task-7-r5/verify.sh:318-323`; saved log: `.agentloop/state/tasks/task-7-r5/scoped_gate_run.log:26-100` contains selected attachment output for 26 tests and no `LiveGroupE2ETests` or `LiveOfflineDeliveryE2ETests`. |
| 13 | `verify.sh` exits 0 with literal `task-7 verify: PASS`. | `bash .agentloop/state/tasks/task-7-r5/verify.sh`. | Gate verdict: `.agentloop/state/tasks/task-7-r5/verify.sh:433-434`; saved log final line: `.agentloop/state/tasks/task-7-r5/scoped_gate_run.log:265` is `task-7 verify: PASS`; prior proof records exit 0 at `.agentloop/state/tasks/task-7-r5/proof.md:14-18`. |
| 14 | Attachment storage remains ciphertext-only, byte-size checked, sentinel plaintext absent, schema fixed, and zero-knowledge audit passes. | `bash .agentloop/state/tasks/task-7-r5/verify.sh`. | Gate ciphertext/sentinel/byte-size/schema/audit checks: `.agentloop/state/tasks/task-7-r5/verify.sh:356-430`; saved log: `.agentloop/state/tasks/task-7-r5/scoped_gate_run.log:105-107` starts the proof/audit output, `:110-124` shows `attachments` columns classified, and `:264` shows `ZERO-KNOWLEDGE SCHEMA AUDIT: PASS`. |

## Scoped Gate Definition

The scoped gate is:

```sh
bash .agentloop/state/tasks/task-7-r5/verify.sh
```

That script reaps stale backends, chooses a free local port, boots one backend,
polls `/health`, exports `CHATAPP_LIVE_BACKEND_URL`, runs the 5 Rust attachment
tests and the 26 Swift attachment tests, asserts the two named live methods
passed and did not skip, asserts the heavy live suites are absent, runs
ciphertext/schema/zero-knowledge checks, and exits 0 only after printing
`task-7 verify: PASS`.

The repo-root `bash verify.sh` aggregator is NOT this item's gate. The global
aggregator is a cross-task runner, not the task-7-r5 scoped attachment proof. It
invokes unrelated approved/out-of-scope gates before it reaches task-7-r5, so a
global failure before task-7-r5 is not evidence about attachment behavior.

## Out-of-Scope Global Aggregator Rejection

The prior rejection came from the repo-root global aggregator, not from the
task-7-r5 scoped attachment gate. The rejected path was task-1d's full-suite
live run:

```text
verify: RUN (task-1d) ... FAIL
bare `swift test` -> LiveGroupE2ETests 125s timeout cascade
LiveOfflineDeliveryE2ETests / LiveRegistration later reported "Registration request failed"
```

That failure is unrelated to attachments. It comes from task-1d launching a
bare `swift test` against shared live backend resources, including
`LiveGroupE2ETests` and `LiveOfflineDeliveryE2ETests`. Task-1d is already
approved/out-of-scope for this builder item, and editing task-1d or other live
suites is explicitly forbidden here.

Therefore task-7-r5-b2 must be judged on the scoped attachment evidence above:
`bash .agentloop/state/tasks/task-7-r5/verify.sh`, the saved
`scoped_gate_run.log`, and the cited source/gate assertions. It must not be
judged by the repo-root `bash verify.sh` aggregator.
