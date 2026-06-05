# task-fix-task8-verify Acceptance Evidence

Evidence log: `.agentloop/state/tasks/task-fix-task8-verify/verify-task-8.log`

## Scoped Swift Gate

`task-8/verify.sh` is scoped to the offline delivery suite:

> `.agentloop/state/tasks/task-8/verify.sh:218:  swift test --filter LiveOfflineDeliveryE2ETests 2>&1`

The captured run shows only the selected offline suite executing:

> `Test Suite 'LiveOfflineDeliveryE2ETests' started at 2026-06-05 21:20:27.301.`

> `Test Suite 'Selected tests' passed at 2026-06-05 21:20:27.420.`

## Offline Test Passed And Was Not Skipped

The required test started and passed:

> `Test Case '-[ChatAppTests.LiveOfflineDeliveryE2ETests testOfflineRecipientReceivesQueuedMessagesInOrderAndRestartReloadsHistory]' started.`

> `Test Case '-[ChatAppTests.LiveOfflineDeliveryE2ETests testOfflineRecipientReceivesQueuedMessagesInOrderAndRestartReloadsHistory]' passed (0.119 seconds).`

The log has no `skipped` line for that test.

## No LiveGroup Cascade

`LiveGroupE2ETests` does not appear in `verify-task-8.log`, so the scoped run did not execute the live group suite.

The Swift XCTest execution completed in fractions of a second, not the previous roughly 433 second cascade:

> `Executed 1 test, with 0 failures (0 unexpected) in 0.119 (0.120) seconds`

No 125-second timeout line appears in the log.

## Swift Pass Criteria

The XCTest and Swift Testing pass markers are present:

> `Test Suite 'Selected tests' passed at 2026-06-05 21:20:27.420.`

> `Executed 1 test, with 0 failures (0 unexpected) in 0.119 (0.120) seconds`

> `Test run with 0 tests in 0 suites passed after 0.001 seconds.`

## Cargo, Schema, Curl, And Backend Checks Still Pass

The unchanged backend and schema checks completed successfully:

> `test messages_inbox_delivers_same_second_messages_in_send_order ... ok`

> `test messages_history_returns_same_second_messages_in_send_order ... ok`

> `test messages_table_stores_no_plaintext_columns ... ok`

> `test schema_dump_prints_schema_sample_row_and_rejects_private_material ... ok`

> `test zk_sentinel_roundtrip_stores_only_ciphertext_in_raw_db ... ok`

The fresh live backend started and answered health checks:

> `task-8 verify: starting backend on http://127.0.0.1:51656`

> `task-8 verify: backend health check returned 200`

The ordered-delivery curl proof ran before the final pass marker:

> `task-8 verify: curl ordered-delivery proof`

> `task-8 verify: PASS`

## No App Source Changes

This builder item produced evidence files only under `.agentloop/state/tasks/task-fix-task8-verify/`. It did not edit `mac-app/` or `backend/`.
