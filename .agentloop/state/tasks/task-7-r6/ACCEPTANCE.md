# task-7-r6 Acceptance Evidence

Refreshed on 2026-06-05T15:12:29Z in worktree branch
`item/task-7-r6-b3` at commit `cc6e3db`.

Primary evidence is the fresh scoped gate capture
`.agentloop/state/tasks/task-7-r6/scoped_gate_run.log`, captured at
2026-06-05T15:05:16Z from run 3 of the task-local gate at commit
`ede1a9e2da2aba6ea63a21c07568135af3fc7887`.

This item is judged by the task-local scoped gate:

```sh
bash .agentloop/state/tasks/task-7-r6/verify.sh
```

The repo-root `bash verify.sh` aggregator is not this item's gate. The scoped
gate starts its own backend, exports `CHATAPP_LIVE_BACKEND_URL` only for
`LiveAttachmentE2ETests`, proves ciphertext-only attachment storage, shuts the
backend down, asserts zero task-local residue, and exits 0 with the literal
verdict `task-7 verify: PASS`.

## Clause To Evidence Map

| # | Acceptance criterion | Deterministic command | Current evidence |
| --- | --- | --- | --- |
| 1 | Rust attachment test `attachment_upload_then_download_round_trips_exact_bytes` passes. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:17` shows `test attachment_upload_then_download_round_trips_exact_bytes ... ok`; `:20` shows `5 passed; 0 failed`. |
| 2 | Rust attachment test `attachment_upload_rejects_oversize_payload_with_413` passes. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:18` shows `test attachment_upload_rejects_oversize_payload_with_413 ... ok`; `:20` shows `5 passed; 0 failed`. |
| 3 | Rust attachment test `attachment_requires_bearer_token` passes. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:15` shows `test attachment_requires_bearer_token ... ok`; `:20` shows `5 passed; 0 failed`. |
| 4 | Rust attachment test `attachment_download_unknown_id_is_404` passes. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:16` shows `test attachment_download_unknown_id_is_404 ... ok`; `:20` shows `5 passed; 0 failed`. |
| 5 | Rust attachment test `attachments_table_stores_no_plaintext_columns` passes. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:14` shows `test attachments_table_stores_no_plaintext_columns ... ok`; `:20` shows `5 passed; 0 failed`. |
| 6 | `FileCryptoTests` passes all 6 tests. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:70` starts `FileCryptoTests`; `:83` shows the suite passed; `:84` shows `Executed 6 tests, with 0 failures`. |
| 7 | `AttachmentDescriptorTests` passes all 4 tests. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:36` starts `AttachmentDescriptorTests`; `:45` shows the suite passed; `:46` shows `Executed 4 tests, with 0 failures`. |
| 8 | `HTTPAttachmentServiceTests` passes all 4 tests. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:85` starts `HTTPAttachmentServiceTests`; `:94` shows the suite passed; `:95` shows `Executed 4 tests, with 0 failures`. |
| 9 | `DMCoordinatorTests` passes all 10 tests. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:47` starts `DMCoordinatorTests`; `:68` shows the suite passed; `:69` shows `Executed 10 tests, with 0 failures`. |
| 10 | Live test `testLiveAttachmentDMAndGroupRoundTripStoresOnlyCiphertext` passes against the gate-booted live backend. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:104` starts the live attachment class; `:111` starts this test; `:112` shows it passed; `:114` shows `Executed 2 tests, with 0 failures`. |
| 11 | Live test `testAlreadySubscribedRecipientReceivesLiveAttachmentsAndWritesByteIdenticalDownloads` passes against the gate-booted live backend. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:104` starts the live attachment class; `:109` starts this test; `:110` shows it passed; `:114` shows `Executed 2 tests, with 0 failures`. |
| 12 | The gate starts a fresh backend for the live attachment tests. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:21` shows a unique DB path; `:22` shows backend startup on `http://127.0.0.1:48536`; `:23` shows `/health` returned 200. |
| 13 | The gate sets `CHATAPP_LIVE_BACKEND_URL` and runs the live suite with scoped `LiveAttachmentE2ETests` selection. | `bash .agentloop/state/tasks/task-7-r6/verify.sh`; inspect with `rg -n "CHATAPP_LIVE_BACKEND_URL|swift test --skip-build --filter LiveAttachmentE2ETests" .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/verify.sh:333` exports `CHATAPP_LIVE_BACKEND_URL`; `:348` runs `swift test --skip-build --filter LiveAttachmentE2ETests`; `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:108-118` shows only `LiveAttachmentE2ETests`, exactly 2 tests, 0 failures. |
| 14 | `LiveGroupE2ETests` and `LiveOfflineDeliveryE2ETests` are excluded from this scoped gate. | `bash .agentloop/state/tasks/task-7-r6/verify.sh`; audit with `rg -n "LiveGroupE2ETests|LiveOfflineDeliveryE2ETests" .agentloop/state/tasks/task-7-r6/scoped_gate_run.log || true` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:32-99` shows the deterministic 24-test attachment run; `:104-118` shows the live run is `LiveAttachmentE2ETests` only. A fresh `rg` of the scoped log returns no `LiveGroupE2ETests` or `LiveOfflineDeliveryE2ETests` matches; `.agentloop/state/tasks/task-7-r6/verify.sh:326` names those suites only for exclusion assertions. |
| 15 | Backend storage is ciphertext-only and never plaintext file content. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:123-124` records DM and group attachment ids; `:125-126` shows decrypted downloads compare byte-identical to the original; `:128-130` proves stored blob differs from plaintext and equals the upload wire body; `:131-135` proves sentinel absence; `:134` proves `stored=119`, `wire=119`, `attachment_byte_size=119`, and `overhead=28`; `:137` proves DM and group rows exist; `:139-157` shows the `attachments` table columns are `id,uploader_id,ciphertext,byte_size,created_at` and classifies `ciphertext` as opaque. |
| 16 | The zero-knowledge schema audit passes. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:138` starts the schema/audit proof; `:140` starts `ZERO-KNOWLEDGE SCHEMA AUDIT`; `:297` reports `ZERO-KNOWLEDGE SCHEMA AUDIT: PASS`. |
| 17 | The gate shuts the backend down and leaves no task-local residue. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:298` shows shutdown plus zero-residue assertion; `.agentloop/state/tasks/task-7-r6/verify.sh:54-61` tears down by the unique `--db-path`; `:507-509` asserts no backend still matches that DB path before success. |
| 18 | The gate exits 0 with literal `task-7 verify: PASS`. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:299` is `task-7 verify: PASS`. |

## Out-of-Scope Global Aggregator

The scoped task-7-r6 gate above is this item's gate. The repo-global
`.agentloop/verify.sh` is a sibling-task aggregator: it finds every task
`verify.sh`, sorts them, runs them in order, and exits 1 on the first failing
sibling. That global result is outside this builder item, which must not edit
application source or sibling task gates.

Fresh attribution evidence is recorded in
`.agentloop/state/tasks/task-7-r6/aggregator_attribution.log`, generated at
2026-06-05T15:03:19Z:

```text
.agentloop/state/tasks/task-7-r6/aggregator_attribution.log:4-9
grep -nE 'find|sort|exit 1' .agentloop/verify.sh
15:done < <(find "$TASKS_DIR" -mindepth 2 -maxdepth 2 -name verify.sh -type f | sort)
23:    exit 1
```

At rejection time the global aggregator continued past this scoped attachment
gate and failed in sibling task-8. The rejection transcript captured in
`aggregator_attribution.log:43-61` shows both `LiveAttachmentE2ETests` methods
passed first, then task-8's bare unscoped Swift run drove the wider live suites:
`LiveGroupE2ETests.testLiveCoordinatorCreatesGroupAndPeerReceivesDecryptedMessage`
timed out after 125.285 seconds, followed by the registration-failure cascade and
`verify: FAIL (task-8)`.

The accurate current fact is that this rejection-time task-8 root cause has
already been narrowed in HEAD by merged commit `2672f49`.
`aggregator_attribution.log:12-31` shows commit
`2672f49e4cd6ef16a2e29821610e12475a9c1891` changed task-8 from bare
`swift test` to `swift test --filter LiveOfflineDeliveryE2ETests`;
`aggregator_attribution.log:33-41` proves the commit is merged and the current
task-8 script contains that filtered command.

Therefore task-7-r6-b3 is accepted or rejected by the scoped command
`bash .agentloop/state/tasks/task-7-r6/verify.sh` and the evidence rows above,
not by the repo-root aggregator.
