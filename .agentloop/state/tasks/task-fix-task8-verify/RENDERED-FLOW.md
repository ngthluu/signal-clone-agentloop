# Offline Delivery Rendered Flow

The scoped live test exercises the offline-delivery user flow against a fresh backend:

1. The recipient is offline while the sender creates encrypted direct messages.
2. The backend queues those ciphertext messages for the offline recipient.
3. The recipient comes online and receives the queued messages in send order.
4. The app restarts and reloads conversation history in the same order.

The evidence run used the live offline E2E gate:

> `task-8 verify: building and testing Swift app with live offline E2E`

The target offline delivery test passed:

> `Test Case '-[ChatAppTests.LiveOfflineDeliveryE2ETests testOfflineRecipientReceivesQueuedMessagesInOrderAndRestartReloadsHistory]' passed (0.119 seconds).`

Inbox and history ordering checks passed, including same-second ordering:

> `test messages_inbox_delivers_same_second_messages_in_send_order ... ok`

> `test messages_history_returns_same_second_messages_in_send_order ... ok`

Ciphertext-only and schema sentinel checks passed:

> `test messages_table_stores_no_plaintext_columns ... ok`

> `test schema_dump_prints_schema_sample_row_and_rejects_private_material ... ok`

> `test zk_sentinel_roundtrip_stores_only_ciphertext_in_raw_db ... ok`

The curl ordered-delivery proof also ran before the final pass marker:

> `task-8 verify: curl ordered-delivery proof`

> `task-8 verify: PASS`

The run stayed scoped to `LiveOfflineDeliveryE2ETests`; `LiveGroupE2ETests` and 125-second timeout output are absent from `verify-task-8.log`.
