# task-7-r6-b6 Ciphertext-Only Storage Proof

Fresh scoped run: `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log`

Command used:

```sh
bash backend/scripts/reap_stale_backends.sh
bash .agentloop/state/tasks/task-7-r6/verify.sh 2>&1 | tee .agentloop/state/tasks/task-7-r6/scoped_gate_run.log
```

The fresh gate exited 0 and printed `task-7 verify: PASS` at `scoped_gate_run.log:545`.

## Test Inventory

- Rust `backend/tests/attachments.rs`: 5 tests ran and passed. The log shows `running 5 tests` at `scoped_gate_run.log:156`, the five expected `... ok` lines at `scoped_gate_run.log:157-161`, and `5 passed; 0 failed` at `scoped_gate_run.log:163`.
- `AttachmentDescriptorTests`: 4 tests ran and passed. The suite starts at `scoped_gate_run.log:282`, all four methods pass at `scoped_gate_run.log:284`, `:286`, `:288`, and `:290`, and the count is `Executed 4 tests, with 0 failures` at `scoped_gate_run.log:292`.
- `DMCoordinatorTests`: 10 tests ran and passed. The suite starts at `scoped_gate_run.log:293`, all ten methods pass at `scoped_gate_run.log:295`, `:297`, `:299`, `:301`, `:303`, `:305`, `:307`, `:309`, `:311`, and `:313`, and the count is `Executed 10 tests, with 0 failures` at `scoped_gate_run.log:315`.
- `FileCryptoTests`: 6 tests ran and passed. The suite starts at `scoped_gate_run.log:316`, all six methods pass at `scoped_gate_run.log:318`, `:320`, `:322`, `:324`, `:326`, and `:328`, and the count is `Executed 6 tests, with 0 failures` at `scoped_gate_run.log:330`.
- `HTTPAttachmentServiceTests`: 4 tests ran and passed. The suite starts at `scoped_gate_run.log:331`, all four methods pass at `scoped_gate_run.log:333`, `:335`, `:337`, and `:339`, and the count is `Executed 4 tests, with 0 failures` at `scoped_gate_run.log:341`.
- Deterministic Swift total: 24 tests, 0 failures at `scoped_gate_run.log:343` and `scoped_gate_run.log:345`.
- `LiveAttachmentE2ETests`: 2 tests ran and passed against the gate-booted backend. The suite starts at `scoped_gate_run.log:354`; `testAlreadySubscribedRecipientReceivesLiveAttachmentsAndWritesByteIdenticalDownloads` passes at `scoped_gate_run.log:356`; `testLiveAttachmentDMAndGroupRoundTripStoresOnlyCiphertext` passes at `scoped_gate_run.log:358`; the count is `Executed 2 tests, with 0 failures` at `scoped_gate_run.log:360`.
- No acceptance test was skipped: the selected test output contains passing class summaries and 0 failures at `scoped_gate_run.log:292`, `:315`, `:330`, `:341`, and `:360`, with no skipped acceptance-critical method lines.

## Scoped Exclusion

- The deterministic run begins at `scoped_gate_run.log:278` and executes only `AttachmentDescriptorTests`, `DMCoordinatorTests`, `FileCryptoTests`, and `HTTPAttachmentServiceTests` in `scoped_gate_run.log:282-341`.
- The live run begins at `scoped_gate_run.log:350` and executes only `LiveAttachmentE2ETests` in `scoped_gate_run.log:354-360`.
- `LiveGroupE2ETests` and `LiveOfflineDeliveryE2ETests` are not executed: `rg -n "Test Suite '(LiveGroupE2ETests|LiveOfflineDeliveryE2ETests)'|Test Case '-\\[ChatAppTests\\.(LiveGroupE2ETests|LiveOfflineDeliveryE2ETests)" .agentloop/state/tasks/task-7-r6/scoped_gate_run.log` returns no matches.
- The gate enforces this scoped exclusion by checking both Swift test outputs for excluded suite names at `verify.sh:326-331` and `verify.sh:369-373`. The full log does include those filenames during `swift build --build-tests` compilation at `scoped_gate_run.log:266-267`; that is not test execution.

## Captured Attachment Values

- DM attachment id: `1eda35fa-eba9-4924-abca-d2f4fd37796e` at `scoped_gate_run.log:369`.
- Group attachment id: `1907043a-35de-4c41-ae37-dcbfc2651481` at `scoped_gate_run.log:370`.
- Byte counts: original plaintext file `91`, stored SQLite blob `119`, captured upload wire body `119`, `attachments.byte_size` `119`, AES-GCM overhead `28`, at `scoped_gate_run.log:380`.
- Numeric proof: `91 + 28 = 119`, so `stored == original + 28 == attachments.byte_size`, and `wire == stored`.
- Authenticated GET response bytes: `119` at `scoped_gate_run.log:382`, matching the stored and wire ciphertext length from `scoped_gate_run.log:380`.
- DM and group attachment rows both exist: `attachment rows for dm_and_group=2` at `scoped_gate_run.log:383`.

## Comparison Proofs

- DM on-disk download equals the live original: `cmp live_original live_dm_download PASS` at `scoped_gate_run.log:371`.
- Group on-disk download equals the live original: `cmp live_original live_group_download PASS` at `scoped_gate_run.log:372`.
- Stored SQLite blob is not plaintext: `cmp original stored_blob DIFFERENT` at `scoped_gate_run.log:374`.
- Captured upload wire body is not plaintext: `cmp original upload_wire DIFFERENT` at `scoped_gate_run.log:375`.
- Stored SQLite blob equals the captured upload wire body: `cmp stored_blob upload_wire PASS` at `scoped_gate_run.log:376`.

## Sentinel Absence

- Sentinel plaintext is absent from raw SQLite strings across DB, `-wal`, and `-shm`: `scoped_gate_run.log:377`.
- Sentinel plaintext is absent from the extracted stored blob: `scoped_gate_run.log:378`.
- Sentinel plaintext is absent from the captured upload wire body: `scoped_gate_run.log:379`.
- Sentinel plaintext is absent from the authenticated `GET /attachments/<id>` response: `scoped_gate_run.log:381`.

## Schema And Audit

- Exact attachment columns: `id,uploader_id,ciphertext,byte_size,created_at` at `scoped_gate_run.log:385`.
- The zero-knowledge audit's attachment table details confirm only these five columns at `scoped_gate_run.log:389-397`, with `ciphertext` classified as opaque ciphertext at `scoped_gate_run.log:401`.
- `ZERO-KNOWLEDGE SCHEMA AUDIT: PASS` is printed at `scoped_gate_run.log:543`.

## Determinism

`gate_repeatability.log` records three consecutive scoped gate runs after reaping stale backends:

- run 1: exit 0 and final line `task-7 verify: PASS` at `gate_repeatability.log:6`.
- run 2: exit 0 and final line `task-7 verify: PASS` at `gate_repeatability.log:9`.
- run 3: exit 0 and final line `task-7 verify: PASS` at `gate_repeatability.log:12`.
- summary: `3/3 runs exited 0 and printed task-7 verify: PASS` at `gate_repeatability.log:14`.

## Self-Containment

Self-containment grep:

```sh
rg -n "\.agentloop/verify\.sh|bash verify\.sh|[^/[:alnum:]_.-]verify\.sh|TASK_7_R5|task-7-r5" .agentloop/state/tasks/task-7-r6/verify.sh || true
```

This command returned no matches. The scoped gate's Swift test commands are the deterministic four-class filter at `verify.sh:299-305` and the live attachment-only command at `verify.sh:348`; it ends with `task-7 verify: PASS` at `verify.sh:511`.
