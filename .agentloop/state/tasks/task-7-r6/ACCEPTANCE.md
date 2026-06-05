# task-7-r6 Acceptance Evidence

Captured on 2026-06-05 15:05 +07 from the fresh task-local scoped gate log
`.agentloop/state/tasks/task-7-r6/scoped_gate_run.log`, against commit
`7e0c8d8` in worktree branch `item/task-7-r6-b2`.

This item is judged by exactly this scoped attachment gate:

```sh
bash .agentloop/state/tasks/task-7-r6/verify.sh
```

The repo-root `bash verify.sh` aggregator is NOT this item's gate. The root
aggregator delegates to `.agentloop/verify.sh`, which builds a sorted list with
`find "$TASKS_DIR" -mindepth 2 -maxdepth 2 -name verify.sh -type f | sort`
and exits on the first failing task gate (`.agentloop/verify.sh:12-24`).
That cross-task first-failure runner is useful for broad health, but it is not
the scoped acceptance proof for task-7-r6.

## Deterministic Command Evidence

### `bash .agentloop/state/tasks/task-7-r6/verify.sh`

Exit status: 0 in the saved scoped run. The final line is:

```text
task-7 verify: PASS
```

The saved run proves:

- Rust `cargo test --test attachments`: 5 tests passed, 0 failed.
- Swift deterministic attachment classes: `FileCryptoTests` 6,
  `AttachmentDescriptorTests` 4, `HTTPAttachmentServiceTests` 4,
  `DMCoordinatorTests` 10; all with 0 failures.
- Swift live attachment class: exactly `swift test --skip-build --filter
  LiveAttachmentE2ETests` against the gate-booted backend, 2 tests passed,
  0 failures.
- `LiveGroupE2ETests` and `LiveOfflineDeliveryE2ETests` were not invoked.
- Ciphertext-only, byte-size, sentinel, schema, and zero-knowledge audit proofs
  ran after the live round trip.

## Clause to Evidence Map

| # | Acceptance criterion | Deterministic command | Current file:line / log proof |
| --- | --- | --- | --- |
| 1 | Rust attachment test `attachment_upload_then_download_round_trips_exact_bytes` passes. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` runs `cargo build` and `cargo test --test attachments`. | Test source: `backend/tests/attachments.rs:171`; gate command/assertions: `.agentloop/state/tasks/task-7-r6/verify.sh:181-212`; saved log: `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:12` shows `... ok`, and `:15` shows `5 passed; 0 failed`. |
| 2 | Rust attachment test `attachment_upload_rejects_oversize_payload_with_413` passes. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` runs `cargo build` and `cargo test --test attachments`. | Test source: `backend/tests/attachments.rs:214`; gate command/assertions: `.agentloop/state/tasks/task-7-r6/verify.sh:181-212`; saved log: `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:13` shows `... ok`, and `:15` shows `5 passed; 0 failed`. |
| 3 | Rust attachment test `attachment_requires_bearer_token` passes. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` runs `cargo build` and `cargo test --test attachments`. | Test source: `backend/tests/attachments.rs:235`; gate command/assertions: `.agentloop/state/tasks/task-7-r6/verify.sh:181-212`; saved log: `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:10` shows `... ok`, and `:15` shows `5 passed; 0 failed`. |
| 4 | Rust attachment test `attachment_download_unknown_id_is_404` passes. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` runs `cargo build` and `cargo test --test attachments`. | Test source: `backend/tests/attachments.rs:254`; gate command/assertions: `.agentloop/state/tasks/task-7-r6/verify.sh:181-212`; saved log: `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:11` shows `... ok`, and `:15` shows `5 passed; 0 failed`. |
| 5 | Rust attachment test `attachments_table_stores_no_plaintext_columns` passes. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` runs `cargo build` and `cargo test --test attachments`. | Test source: `backend/tests/attachments.rs:268`; no-plaintext column assertions: `backend/tests/attachments.rs:279-313`; gate command/assertions: `.agentloop/state/tasks/task-7-r6/verify.sh:181-212`; saved log: `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:9` shows `... ok`, and `:15` shows `5 passed; 0 failed`. |
| 6 | `FileCryptoTests` passes all 6 tests. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` unsets live env, then runs `swift test --skip-build --filter FileCryptoTests --filter AttachmentDescriptorTests --filter HTTPAttachmentServiceTests --filter DMCoordinatorTests`. | Test class/methods: `mac-app/Tests/ChatAppTests/FileCryptoTests.swift:6-61`; gate filters/count assertion: `.agentloop/state/tasks/task-7-r6/verify.sh:272-312`; saved log: `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:64-78` shows all 6 passed and `Executed 6 tests, with 0 failures`. |
| 7 | `AttachmentDescriptorTests` passes all 4 tests. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` unsets live env, then runs the deterministic 4-class Swift filter. | Test class/methods: `mac-app/Tests/ChatAppTests/AttachmentDescriptorTests.swift:6-41`; gate filters/count assertion: `.agentloop/state/tasks/task-7-r6/verify.sh:272-312`; saved log: `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:30-40` shows all 4 passed and `Executed 4 tests, with 0 failures`. |
| 8 | `HTTPAttachmentServiceTests` passes all 4 tests. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` unsets live env, then runs the deterministic 4-class Swift filter. | Test class/methods: `mac-app/Tests/ChatAppTests/HTTPAttachmentServiceTests.swift:5-64`; gate filters/count assertion: `.agentloop/state/tasks/task-7-r6/verify.sh:272-312`; saved log: `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:79-89` shows all 4 passed and `Executed 4 tests, with 0 failures`. |
| 9 | `DMCoordinatorTests` passes all 10 tests. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` unsets live env, then runs the deterministic 4-class Swift filter. | Test class/methods: `mac-app/Tests/ChatAppTests/DMCoordinatorTests.swift:6-317`; gate filters/count assertion: `.agentloop/state/tasks/task-7-r6/verify.sh:272-312`; saved log: `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:41-63` shows all 10 passed and `Executed 10 tests, with 0 failures`. |
| 10 | Live attachment test `testLiveAttachmentDMAndGroupRoundTripStoresOnlyCiphertext` passes against the gate-booted live backend. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` starts a fresh backend, exports `CHATAPP_LIVE_BACKEND_URL`, then runs exactly `swift test --skip-build --filter LiveAttachmentE2ETests`. | Backend/env setup: `.agentloop/state/tasks/task-7-r6/verify.sh:214-255` and `:321-330`; live command/assertions: `.agentloop/state/tasks/task-7-r6/verify.sh:332-355`; test source: `mac-app/Tests/ChatAppTests/LiveAttachmentE2ETests.swift:21`; saved log: `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:105-108` shows this test passed and the class executed 2 tests with 0 failures. |
| 11 | Live attachment test `testAlreadySubscribedRecipientReceivesLiveAttachmentsAndWritesByteIdenticalDownloads` passes against the gate-booted live backend. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` starts a fresh backend, exports `CHATAPP_LIVE_BACKEND_URL`, then runs exactly `swift test --skip-build --filter LiveAttachmentE2ETests`. | Backend/env setup: `.agentloop/state/tasks/task-7-r6/verify.sh:214-255` and `:321-330`; live command/assertions: `.agentloop/state/tasks/task-7-r6/verify.sh:332-355`; test source: `mac-app/Tests/ChatAppTests/LiveAttachmentE2ETests.swift:126`; saved log: `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:103-108` shows this test passed and the class executed 2 tests with 0 failures. |
| 12 | The scoped gate does not run `LiveGroupE2ETests` or `LiveOfflineDeliveryE2ETests`. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` includes only the deterministic attachment filters and then exactly `swift test --skip-build --filter LiveAttachmentE2ETests`, failing if either excluded suite appears. | Deterministic filters: `.agentloop/state/tasks/task-7-r6/verify.sh:283-293`; live filter: `.agentloop/state/tasks/task-7-r6/verify.sh:332-337`; absence assertions: `.agentloop/state/tasks/task-7-r6/verify.sh:314-319` and `:357-361`; saved log selected output: `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:26-116` contains only the 24 deterministic tests and 2 live attachment tests, with no `LiveGroupE2ETests` or `LiveOfflineDeliveryE2ETests`. |
| 13 | `verify.sh` starts a fresh backend, sets `CHATAPP_LIVE_BACKEND_URL`, runs `swift test --filter LiveAttachmentE2ETests`, shuts down, exits 0, and prints literal `task-7 verify: PASS`. | `bash .agentloop/state/tasks/task-7-r6/verify.sh`. | Cleanup trap/backend lifecycle: `.agentloop/state/tasks/task-7-r6/verify.sh:164` and `:230-255`; live env/command: `.agentloop/state/tasks/task-7-r6/verify.sh:321-337`; final verdict: `.agentloop/state/tasks/task-7-r6/verify.sh:471-472`; saved log: `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:16-17`, `:98-108`, and final line `:277` is `task-7 verify: PASS`. |
| 14 | Backend stores only encrypted attachment blobs: downloads are byte-identical after decrypt, stored blob differs from plaintext, stored blob equals captured upload wire body, byte size is `original + 28`, sentinel plaintext is absent from SQLite/blob/wire/download, DM and group rows exist, attachments columns are exactly `id,uploader_id,ciphertext,byte_size,created_at`, and `zk_relay_audit.sh` passes. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` runs the live tests and then performs DB/blob/wire/schema/audit assertions. | Gate proof assertions: `.agentloop/state/tasks/task-7-r6/verify.sh:363-469`; saved log: `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:117-118` starts the storage proof, `:122-136` shows the attachment table columns/classification, and `:276` prints `ZERO-KNOWLEDGE SCHEMA AUDIT: PASS`. |

## Scoped Gate Definition

The scoped gate is:

```sh
bash .agentloop/state/tasks/task-7-r6/verify.sh
```

That script reaps stale backends, chooses a free local port, boots one backend,
polls `/health`, builds Rust and Swift targets, runs the 5 Rust attachment
tests, runs the 24 deterministic Swift attachment tests before live env is set,
then exports `CHATAPP_LIVE_BACKEND_URL` only for exactly
`swift test --skip-build --filter LiveAttachmentE2ETests`. It asserts the two
named live methods passed and did not skip, asserts the heavy live suites are
absent from both Swift outputs, runs ciphertext/schema/zero-knowledge checks,
and exits 0 only after printing `task-7 verify: PASS`.

The repo-root `bash verify.sh` aggregator is a cross-task runner, not the
task-7-r6 scoped attachment proof. It discovers all task gates in sorted order
and stops on the first failure (`.agentloop/verify.sh:12-24`). A failure in any
earlier or unrelated task gate can prevent the aggregator from reaching
task-7-r6 at all, and that outcome is not evidence about attachment behavior.

## Out-of-Scope Global Aggregator

Current aggregator state was verified from the worktree scripts, not copied from
the older r5 narrative:

- `.agentloop/verify.sh:12-24` still sorts all per-task `verify.sh` scripts and
  exits on the first failing gate.
- `task-fix-cascade` has scoped the formerly broad live task gates for task-1d,
  task-3, and task-6: task-1d now runs filtered account-flow suites
  (`.agentloop/state/tasks/task-1d/verify.sh:107-121`), task-3 now runs filtered
  DM/live auth suites (`.agentloop/state/tasks/task-3/verify.sh:147-154`), and
  task-6 now runs filtered emoji DM suites
  (`.agentloop/state/tasks/task-6/verify.sh:147-154`).
- Two sibling live gates still run bare live `swift test` after setting
  `CHATAPP_LIVE_BACKEND_URL`: task-8
  (`.agentloop/state/tasks/task-8/verify.sh:210-219`) and task-9
  (`.agentloop/state/tasks/task-9/verify.sh:151-162`).
- Older non-live task-1a/task-1b gates also run bare `swift test`, but they do
  not set `CHATAPP_LIVE_BACKEND_URL`.

No global aggregator failure is asserted here because this builder item did not
re-run the root aggregator and is not allowed to modify sibling gates. The
decoupling point is structural and current: r6's gate is self-contained, never
invokes `bash verify.sh` or `.agentloop/verify.sh`, never launches
`LiveGroupE2ETests` or `LiveOfflineDeliveryE2ETests`, and produces the scoped
attachment evidence cited above.
