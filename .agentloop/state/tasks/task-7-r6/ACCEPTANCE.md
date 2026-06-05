# task-7-r6 Acceptance Evidence

Captured from the current task-local scoped gate log,
`.agentloop/state/tasks/task-7-r6/scoped_gate_run.log`, in worktree branch
`item/task-7-r6-b7` at commit `dad7ac7`.

## One-Command Acceptance

This builder item is accepted by this scoped gate:

```sh
bash .agentloop/state/tasks/task-7-r6/verify.sh
```

Expected verdict, captured in the fresh scoped log:

```text
.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:279:task-7 verify: PASS
```

The repo-root aggregator is not this item's gate. The scoped gate starts its own
backend, exports `CHATAPP_LIVE_BACKEND_URL` only for
`LiveAttachmentE2ETests`, proves ciphertext-only attachment storage, shuts the
backend down, asserts zero residue, and exits 0 with the literal
`task-7 verify: PASS`.

## Clause To Evidence Map

| # | Acceptance clause | Re-runnable command | Scoped log anchor |
| --- | --- | --- | --- |
| 1 | Rust attachment test `attachment_upload_then_download_round_trips_exact_bytes` passes. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:12` shows `test attachment_upload_then_download_round_trips_exact_bytes ... ok`; `:15` shows `5 passed; 0 failed`. |
| 2 | Rust attachment test `attachment_upload_rejects_oversize_payload_with_413` passes. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:13` shows `test attachment_upload_rejects_oversize_payload_with_413 ... ok`; `:15` shows `5 passed; 0 failed`. |
| 3 | Rust attachment test `attachment_requires_bearer_token` passes. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:10` shows `test attachment_requires_bearer_token ... ok`; `:15` shows `5 passed; 0 failed`. |
| 4 | Rust attachment test `attachment_download_unknown_id_is_404` passes. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:11` shows `test attachment_download_unknown_id_is_404 ... ok`; `:15` shows `5 passed; 0 failed`. |
| 5 | Rust attachment test `attachments_table_stores_no_plaintext_columns` passes. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:9` shows `test attachments_table_stores_no_plaintext_columns ... ok`; `:15` shows `5 passed; 0 failed`. |
| 6 | `FileCryptoTests` passes all 6 tests. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:65` starts `FileCryptoTests`; `:78` shows the suite passed; `:79` shows `Executed 6 tests, with 0 failures`. |
| 7 | `AttachmentDescriptorTests` passes all 4 tests. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:31` starts `AttachmentDescriptorTests`; `:40` shows the suite passed; `:41` shows `Executed 4 tests, with 0 failures`. |
| 8 | `HTTPAttachmentServiceTests` passes all 4 tests. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:80` starts `HTTPAttachmentServiceTests`; `:89` shows the suite passed; `:90` shows `Executed 4 tests, with 0 failures`. |
| 9 | `DMCoordinatorTests` passes all 10 tests. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:42` starts `DMCoordinatorTests`; `:63` shows the suite passed; `:64` shows `Executed 10 tests, with 0 failures`. |
| 10 | Live test `testLiveAttachmentDMAndGroupRoundTripStoresOnlyCiphertext` passes against a live backend. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:99` starts the live attachment run; `:106` starts this test; `:107` shows it passed; `:109` shows `Executed 2 tests, with 0 failures`. |
| 11 | Live test `testAlreadySubscribedRecipientReceivesLiveAttachmentsAndWritesByteIdenticalDownloads` passes against a live backend. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:99` starts the live attachment run; `:104` starts this test; `:105` shows it passed; `:109` shows `Executed 2 tests, with 0 failures`. |
| 12 | `LiveGroupE2ETests` and `LiveOfflineDeliveryE2ETests` are excluded from this scoped gate. | `bash .agentloop/state/tasks/task-7-r6/verify.sh`; audit with `rg -n "LiveGroupE2ETests|LiveOfflineDeliveryE2ETests" .agentloop/state/tasks/task-7-r6/scoped_gate_run.log || true` | The live run is `LiveAttachmentE2ETests` only at `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:99-109`; the deterministic run is the 24 attachment tests at `:27-94`; fresh `rg` over the scoped log returned no excluded-suite matches. |
| 13 | The gate starts a fresh backend. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:16` shows the unique DB path; `:17` shows backend startup on `http://127.0.0.1:54583`; `:18` shows `/health` returned 200. |
| 14 | The gate sets `CHATAPP_LIVE_BACKEND_URL` and runs exactly `swift test --skip-build --filter LiveAttachmentE2ETests` for live attachment coverage. | `bash .agentloop/state/tasks/task-7-r6/verify.sh`; inspect with `rg -n "CHATAPP_LIVE_BACKEND_URL|swift test --skip-build --filter LiveAttachmentE2ETests" .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:99` marks the live attachment Swift class run; `:103-109` shows only `LiveAttachmentE2ETests` executed, exactly 2 tests with 0 failures. |
| 15 | Backend storage is ciphertext-only and never plaintext file content. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:118` starts blob extraction/ciphertext proof; `:119` starts schema/audit proof; `:123-136` shows the `attachments` table has `id,uploader_id,ciphertext,byte_size,created_at` with ciphertext classified as opaque; `:277` shows `ZERO-KNOWLEDGE SCHEMA AUDIT: PASS`. The command also enforces byte-identical decrypted downloads, stored blob != plaintext, stored blob == upload wire body, `stored_bytes == original_bytes + 28 == attachments.byte_size`, sentinel absence, and DM/group row existence before it can reach `:279`. |
| 16 | The gate shuts the backend down and leaves no task-local residue. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:278` shows shutdown plus zero-residue assertion before the PASS line at `:279`. |
| 17 | The gate exits 0 with literal `task-7 verify: PASS`. | `bash .agentloop/state/tasks/task-7-r6/verify.sh` | `.agentloop/state/tasks/task-7-r6/scoped_gate_run.log:279` is `task-7 verify: PASS`. |

## Out-of-Scope Global Aggregator

The scoped task-7-r6 gate above is this item's gate. The repo-global
`.agentloop/verify.sh` is a sibling-task aggregator: it globs every task
`verify.sh` in sorted order and exits 1 on the first failing sibling gate. That
cross-task result is outside this builder item, which is not allowed to edit
other task gates.

Freshly captured grep evidence from this worktree:

```text
$ rg -n 'find "\$TASKS_DIR"|verify: FAIL|exit 1' .agentloop/verify.sh
15:done < <(find "$TASKS_DIR" -mindepth 2 -maxdepth 2 -name verify.sh -type f | sort)
22:    echo "verify: FAIL ($task_name)"
23:    exit 1

$ rg -n 'CHATAPP_LIVE_BACKEND_URL|swift test' .agentloop/state/tasks/task-8/verify.sh
210:export CHATAPP_LIVE_BACKEND_URL="${BASE_URL}"
218:  swift test 2>&1
227:  fail "swift test output did not report a passing test run"
231:  fail "swift test output did not report 0 failures"
```

Line-expanded context for those same snippets:

```text
$ nl -ba .agentloop/verify.sh | sed -n '12,24p'
    12	sorted_scripts=()
    13	while IFS= read -r verify_script; do
    14	  sorted_scripts+=("$verify_script")
    15	done < <(find "$TASKS_DIR" -mindepth 2 -maxdepth 2 -name verify.sh -type f | sort)
    16
    17	for verify_script in "${sorted_scripts[@]}"; do
    18	  task_name="$(basename "$(dirname "$verify_script")")"
    19	  echo "verify: RUN ($task_name)"
    20
    21	  if ! (cd "$REPO_ROOT" && bash "$verify_script"); then
    22	    echo "verify: FAIL ($task_name)"
    23	    exit 1
    24	  fi

$ nl -ba .agentloop/state/tasks/task-8/verify.sh | sed -n '214,219p'
   214	echo "task-8 verify: building and testing Swift app with live offline E2E"
   215	swift_output="$(
   216	  cd "${MAC_APP_DIR}"
   217	  swift build 2>&1
   218	  swift test 2>&1
   219	)" || {
```

The current out-of-scope failing node is task-8's unscoped live `swift test` at
`.agentloop/state/tasks/task-8/verify.sh:218`. That task-8 gate is owned by
`task-fix-cascade`, not by task-7-r6-b7, and is not editable here.
