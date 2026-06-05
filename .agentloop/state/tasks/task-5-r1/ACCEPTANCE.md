# task-5-r1 Acceptance Evidence

Captured on 2026-06-05 against HEAD `7e0c8d8`.

This item is judged only by task-5-r1's deterministic targeted commands:
`.agentloop/state/tasks/task-5-r1/verify.sh` and the saved b1/b2 captures in
`scoped_gate_run.log` and `gate_repeatability.log`. The repo-root global
`bash verify.sh` aggregator and any `Live*E2ETests` beyond the single scoped
filter are not this item's gate.

## Deterministic Command Evidence

### `bash .agentloop/state/tasks/task-5-r1/verify.sh; echo EXIT=$?`

Exit status: 0. Fresh b1 capture from
`.agentloop/state/tasks/task-5-r1/scoped_gate_run.log`.

```text
Starting backend on 52876
swift test --filter testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages
Test Case '-[ChatAppTests.LiveGroupE2ETests testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages]' passed (0.198 seconds).
Test Suite 'LiveGroupE2ETests' passed at 2026-06-05 15:40:16.066.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.198 (0.199) seconds
task-5 verify: PASS
```

Three b2 repeat runs each used a fresh backend and exited 0
(`gate_repeatability.log:160-183`, `:345-368`, `:530-553`):

```text
Starting backend on 45698
task-5 verify: PASS
EXIT=0
Starting backend on 46679
task-5 verify: PASS
EXIT=0
Starting backend on 47665
task-5 verify: PASS
EXIT=0
```

### `cd backend && cargo test`

The task-local gate runs `cargo test`, then asserts every required group test by
name (`verify.sh:352-354`, `:121-143`). The fresh capture shows all 12
`tests/groups.rs` tests passed:

```text
Running tests/groups.rs (target/debug/deps/groups-dd51c3ddb97e60c4)

running 12 tests
test group_create_requires_bearer_token ... ok
test group_stream_requires_bearer_token ... ok
test group_tables_store_no_plaintext_columns ... ok
test group_list_returns_all_member_groups_in_rowid_order ... ok
test group_message_post_stores_exactly_the_ciphertext_blob ... ok
test group_message_history_returns_same_second_messages_in_send_order ... ok
test group_message_history_returns_only_ciphertext_for_members ... ok
test group_endpoints_reject_non_members_with_403 ... ok
test group_create_persists_name_membership_and_epoch_zero_keys ... ok
test group_add_member_broadcasts_epoch_event_to_members ... ok
test group_stream_with_member_returns_sse_headers ... ok
test group_add_member_bumps_epoch_and_blocks_prior_epoch_keys ... ok

test result: ok. 12 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.04s
```

Source: `.agentloop/state/tasks/task-5-r1/scoped_gate_run.log:56-72`.

### `cd mac-app && swift test --filter ChatAppTests.GroupCoordinatorTests`

```text
swift test --filter ChatAppTests.GroupCoordinatorTests
Test Suite 'GroupCoordinatorTests' passed at 2026-06-05 15:40:12.964.
	 Executed 20 tests, with 0 failures (0 unexpected) in 2.189 (2.191) seconds
```

Source: `.agentloop/state/tasks/task-5-r1/scoped_gate_run.log:134`,
`:182-183`.

### `cd mac-app && swift test --filter ChatAppTests.GroupCryptoTests`

```text
swift test --filter ChatAppTests.GroupCryptoTests
Test Suite 'GroupCryptoTests' passed at 2026-06-05 15:40:13.451.
	 Executed 9 tests, with 0 failures (0 unexpected) in 0.001 (0.002) seconds
```

Source: `.agentloop/state/tasks/task-5-r1/scoped_gate_run.log:192`,
`:217-218`.

### `cd mac-app && swift test --filter ChatAppTests.GroupEnvelopeTests`

```text
swift test --filter ChatAppTests.GroupEnvelopeTests
Test Suite 'GroupEnvelopeTests' passed at 2026-06-05 15:40:13.917.
	 Executed 7 tests, with 0 failures (0 unexpected) in 0.001 (0.002) seconds
```

Source: `.agentloop/state/tasks/task-5-r1/scoped_gate_run.log:227`,
`:248-249`.

### `cd mac-app && swift test --filter ChatAppTests.HTTPGroupServiceTests`

```text
swift test --filter ChatAppTests.HTTPGroupServiceTests
Test Suite 'HTTPGroupServiceTests' passed at 2026-06-05 15:40:14.390.
	 Executed 7 tests, with 0 failures (0 unexpected) in 0.008 (0.008) seconds
```

Source: `.agentloop/state/tasks/task-5-r1/scoped_gate_run.log:258`,
`:279-280`.

### Scoped Live Filter

The live leg is exactly one filtered Swift invocation against the fresh backend:

```text
Starting backend on 52876
swift test --filter testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages
Test Suite 'LiveGroupE2ETests' started at 2026-06-05 15:40:15.868.
Test Case '-[ChatAppTests.LiveGroupE2ETests testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages]' passed (0.198 seconds).
	 Executed 1 test, with 0 failures (0 unexpected) in 0.198 (0.199) seconds
task-5 verify: PASS
```

Source: `.agentloop/state/tasks/task-5-r1/scoped_gate_run.log:289-310`.

## Clause to Command Map

| # | Acceptance criterion | Deterministic command | Current file:line proof |
| --- | --- | --- | --- |
| 1 | All 12 Rust backend group tests pass. | `bash .agentloop/state/tasks/task-5-r1/verify.sh` runs `cd backend && cargo test`; the capture above shows all 12 `group_*` tests `... ok`. | `verify.sh:352-354` runs and checks cargo output; `verify.sh:125-138` names all 12 tests; `verify.sh:141-143` requires `test ${test_name} ... ok`; capture at `scoped_gate_run.log:56-72`. |
| 2 | The 12 required Rust tests are exactly `group_create_persists_name_membership_and_epoch_zero_keys`, `group_create_requires_bearer_token`, `group_list_returns_all_member_groups_in_rowid_order`, `group_endpoints_reject_non_members_with_403`, `group_stream_requires_bearer_token`, `group_stream_with_member_returns_sse_headers`, `group_add_member_broadcasts_epoch_event_to_members`, `group_message_post_stores_exactly_the_ciphertext_blob`, `group_message_history_returns_only_ciphertext_for_members`, `group_message_history_returns_same_second_messages_in_send_order`, `group_add_member_bumps_epoch_and_blocks_prior_epoch_keys`, and `group_tables_store_no_plaintext_columns`. | Same task-local gate. | Test-name array at `verify.sh:125-138`; corresponding pass lines at `scoped_gate_run.log:59-70`. |
| 3 | `GroupCoordinatorTests` passes with 20 tests. | `cd mac-app && swift test --filter ChatAppTests.GroupCoordinatorTests`. | Gate invocation and count assertion at `verify.sh:146-165`, `:356`; capture at `scoped_gate_run.log:134`, `:182-183`; repeat run 3 at `gate_repeatability.log:423-424`. |
| 4 | `GroupCryptoTests` passes with 9 tests. | `cd mac-app && swift test --filter ChatAppTests.GroupCryptoTests`. | Gate invocation and count assertion at `verify.sh:146-165`, `:357`; capture at `scoped_gate_run.log:192`, `:217-218`; repeat run 3 at `gate_repeatability.log:458-459`. |
| 5 | `GroupEnvelopeTests` passes with 7 tests. | `cd mac-app && swift test --filter ChatAppTests.GroupEnvelopeTests`. | Gate invocation and count assertion at `verify.sh:146-165`, `:358`; capture at `scoped_gate_run.log:227`, `:248-249`; repeat run 3 at `gate_repeatability.log:489-490`. |
| 6 | `HTTPGroupServiceTests` passes with 7 tests. | `cd mac-app && swift test --filter ChatAppTests.HTTPGroupServiceTests`. | Gate invocation and count assertion at `verify.sh:146-165`, `:359`; capture at `scoped_gate_run.log:258`, `:279-280`; repeat run 3 at `gate_repeatability.log:520-521`. |
| 7 | The live E2E gate runs only `swift test --filter testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages`. | `bash .agentloop/state/tasks/task-5-r1/verify.sh`. | The single live command is emitted and run at `verify.sh:201-205`; the gate requires `Executed 1 test` and `with 0 failures` at `verify.sh:211-212`; capture at `scoped_gate_run.log:290`, `:298-301`; the scoped test is defined at `LiveGroupE2ETests.swift:233`. |
| 8 | `testLiveCoordinatorCreatesGroupAndPeerReceivesDecryptedMessage` is excluded. | Same task-local gate. | The excluded test exists at `LiveGroupE2ETests.swift:16` and times out at the wait on `:46`; the task gate fails if that name appears in live output at `verify.sh:214`. The self-guard also rejects any `swift test --filter` that names it at `verify.sh:101-119`. |
| 9 | The two other coordinator live tests are also excluded: `testLiveGroupAllThreeMembersSendAndReceiveThroughCoordinators` and `testLiveGroupExistingMembersKeepReceivingAfterAddWhileNewMemberExcluded`. | Same task-local gate. | The tests exist at `LiveGroupE2ETests.swift:66` and `:133`; the task gate fails if either appears in live output at `verify.sh:215-216`; the self-guard rejects filtered invocations for these names at `verify.sh:115-118`. |
| 10 | `verify.sh` starts a fresh backend and exits 0 with `task-5 verify: PASS`. | `bash .agentloop/state/tasks/task-5-r1/verify.sh; echo EXIT=$?`. | Stale backend reap at `verify.sh:346`; fresh temp DB/logs at `verify.sh:333-344`; backend starts on the task port at `verify.sh:167-189`, `:361`; pass and exit at `verify.sh:367-368`. Captures show ports `52876`, `45698`, `46679`, `47665` and `EXIT=0` at `scoped_gate_run.log:289-310` and `gate_repeatability.log:160-183`, `:345-368`, `:530-553`. |
| 11 | A user can create a named group chat and invite users by username. | Scoped live filter plus backend group tests. | Live test creates Alice/Bob/Carol/Dave and calls `groupService.createGroup(token:name:members:)` with `"Live Group ..."` at `LiveGroupE2ETests.swift:249-267`; backend create payload has `name` and member `username` fields at `backend/src/routes/groups.rs:60-70`; backend resolves usernames at `backend/src/routes/groups.rs:187-200`, inserts group name at `:217-224`, and persists membership at `:231-259`. |
| 12 | Member key distribution is proven. | Scoped live filter plus unit suites. | Live test generates epoch-0 key and wraps it for Alice/Bob/Carol at `LiveGroupE2ETests.swift:254-262`; unwraps Bob/Carol epoch-0 keys at `:313-326`; fetches and unwraps keys via `unwrappedKey` at `:527-536`. Backend persists wrapped keys at `backend/src/routes/groups.rs:246-254` and returns per-member keys at `:496-530`. |
| 13 | Current group members can exchange/decrypt messages. | Scoped live filter and `GroupCoordinatorTests` 20/20. | Live test encrypts the sentinel, sends ciphertext, fetches Bob history, checks streamed ciphertext, and decrypts for Bob/Carol at `LiveGroupE2ETests.swift:275-336`; the coordinator unit suite includes live/decrypt/rekey flows and passes 20 tests in the capture. Backend accepts only member sends at `backend/src/routes/groups.rs:548-560`. |
| 14 | Sentinel plaintext is absent from the wire, fetched history, and DB. | Task-local gate after the scoped live filter. | Live test asserts the encoded wire body does not contain the sentinel at `LiveGroupE2ETests.swift:275-279` and writes proof artifacts at `:404-411`, `:661-675`. The gate requires artifacts, compares wire ciphertext to DB ciphertext, fetches history, checks sentinel absence in wire/history/DB row, and scans `strings` at `verify.sh:229-275`. |
| 15 | Late-member exclusion from prior epoch messages is proven. | Task-local gate after the scoped live filter. | Live test adds Dave at epoch 1, proves Dave has no epoch-0 key, and asserts Dave's keys cannot decrypt the epoch-0 sentinel at `LiveGroupE2ETests.swift:338-389`; the gate checks DB state for zero Dave epoch-0 keys and `joined_epoch == 1` at `verify.sh:278-305`. Backend stores the late member with the requested joined epoch and inserts only epoch-1 keys at `backend/src/routes/groups.rs:438-470`. |
| 16 | Backend stores only encrypted group message blobs and membership metadata, with no plaintext group-message storage. | `bash .agentloop/state/tasks/task-5-r1/verify.sh`; source/schema inspection. | `SendGroupMessageRequest` contains `epoch` and `ciphertext` only at `backend/src/routes/groups.rs:137-141`; inserts write `ciphertext` into `group_messages` at `:564-572`; history selects/returns `ciphertext` at `:668-715`. Schema stores `groups`, `group_members`, `group_keys.wrapped_key`, and `group_messages.ciphertext` only at `backend/migrations/0004_create_groups.sql:1-33`; the gate rejects plaintext-like columns and requires one `ciphertext` plus one `wrapped_key` column at `verify.sh:308-327`. |
| 17 | The repo-root `bash verify.sh` and any other `Live*E2ETests` are not this item's gate. | This task-local evidence bundle; no global aggregator command is used for acceptance. | The task gate self-guards against `.agentloop/verify.sh`, unrelated `verify.sh` invocations, and excluded coordinator live filters at `verify.sh:101-119`; the live command is the single service-level filter at `verify.sh:201-205`. |

## Behavioral Proof Details

The scoped service-level live test exercises the real HTTP backend with real
registration/auth/group services: `HTTPRegistrationClient`, `HTTPAuthClient`,
`HTTPMessageService`, and `HTTPGroupService` are created from
`CHATAPP_LIVE_BACKEND_URL` at `LiveGroupE2ETests.swift:233-245`. It creates a
named group with wrapped member keys, sends only encrypted group-message
ciphertext, reads history and SSE data back through the live service, decrypts
for current members, then adds a late member and proves that member can decrypt
epoch 1 but not epoch 0 (`LiveGroupE2ETests.swift:249-411`).

The task-local gate adds DB-level proof that the Swift test alone cannot show:
it compares the captured wire ciphertext to the SQLite `group_messages`
`ciphertext` row, fetches server history, rejects sentinel plaintext in wire,
history, row, and raw DB strings, verifies no late-member epoch-0 key exists,
checks `joined_epoch == 1`, and rejects plaintext-like schema columns
(`verify.sh:229-327`).

## Out-of-Scope Global Aggregator Rejection

The repo-root aggregator red is out of scope for task-5-r1-b3. The same run
shows task-5's own gate printed `task-5 verify: PASS` before the aggregator moved
on to task-8:

```text
task-5 verify: proving group wire, history, and DB contain ciphertext only
task-5 verify: proving late member lacks prior epoch key
task-5 verify: checking group message/key schemas
task-5 verify: PASS
verify: RUN (task-8)
```

Source: `.agentloop/logs/iter-25/item-task-8-b5.log:23642-23647` and
`:29281-29286` in this run's archived aggregator transcript.

Task-8 then runs a full `swift test` under `CHATAPP_LIVE_BACKEND_URL` from its
unscoped gate (`.agentloop/state/tasks/task-8/verify.sh:214-221`). That full
suite includes the coordinator-driven group live tests, and the terminal failure
is task-8:

```text
Test Case '-[ChatAppTests.LiveGroupE2ETests testLiveCoordinatorCreatesGroupAndPeerReceivesDecryptedMessage]' started.
/Users/ngthluu/choscor/test-chat-app/mac-app/Tests/ChatAppTests/LiveGroupE2ETests.swift:46: error: -[ChatAppTests.LiveGroupE2ETests testLiveCoordinatorCreatesGroupAndPeerReceivesDecryptedMessage] : failed - Timed out waiting for coordinator message 'hello'. Messages: []
Test Case '-[ChatAppTests.LiveGroupE2ETests testLiveCoordinatorCreatesGroupAndPeerReceivesDecryptedMessage]' failed (125.362 seconds).
Test Case '-[ChatAppTests.LiveGroupE2ETests testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages]' started.
/Users/ngthluu/choscor/test-chat-app/mac-app/Tests/ChatAppTests/LiveGroupE2ETests.swift:433: error: -[ChatAppTests.LiveGroupE2ETests testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages] : failed: caught error: "Registration failed for grp_a_9EB1877641BF400F9758: failure("Registration request failed.")"
Test Case '-[ChatAppTests.LiveGroupE2ETests testLiveGroupAllThreeMembersSendAndReceiveThroughCoordinators]' started.
/Users/ngthluu/choscor/test-chat-app/mac-app/Tests/ChatAppTests/LiveGroupE2ETests.swift:77: error: -[ChatAppTests.LiveGroupE2ETests testLiveGroupAllThreeMembersSendAndReceiveThroughCoordinators] : failed - Registration failed for coord3_a_D6B7CDAFE90E42DC87FE: failure("Registration request failed.")
Test Case '-[ChatAppTests.LiveGroupE2ETests testLiveGroupExistingMembersKeepReceivingAfterAddWhileNewMemberExcluded]' started.
/Users/ngthluu/choscor/test-chat-app/mac-app/Tests/ChatAppTests/LiveGroupE2ETests.swift:144: error: -[ChatAppTests.LiveGroupE2ETests testLiveGroupExistingMembersKeepReceivingAfterAddWhileNewMemberExcluded] : failed - Registration failed for cont_a_525744099AC84B6E90E1: failure("Registration request failed.")
Test Suite 'LiveOfflineDeliveryE2ETests' started at 2026-06-05 19:28:04.705.
/Users/ngthluu/choscor/test-chat-app/mac-app/Tests/ChatAppTests/LiveOfflineDeliveryE2ETests.swift:150: error: -[ChatAppTests.LiveOfflineDeliveryE2ETests testOfflineRecipientReceivesQueuedMessagesInOrderAndRestartReloadsHistory] : failed: caught error: "Registration failed for off_a_EA0375B65208467B80EA: failure("Registration request failed.")"
Test Suite 'LiveRegistrationE2ETests' started at 2026-06-05 19:29:04.860.
/Users/ngthluu/choscor/test-chat-app/mac-app/Tests/ChatAppTests/LiveRegistrationE2ETests.swift:30: error: -[ChatAppTests.LiveRegistrationE2ETests testLiveRegistrationPersistsAccountAndDuplicateShowsTakenError] : XCTAssertTrue failed
/Users/ngthluu/choscor/test-chat-app/mac-app/Tests/ChatAppTests/LiveRegistrationE2ETests.swift:31: error: -[ChatAppTests.LiveRegistrationE2ETests testLiveRegistrationPersistsAccountAndDuplicateShowsTakenError] : XCTAssertTrue failed
/Users/ngthluu/choscor/test-chat-app/mac-app/Tests/ChatAppTests/LiveRegistrationE2ETests.swift:32: error: -[ChatAppTests.LiveRegistrationE2ETests testLiveRegistrationPersistsAccountAndDuplicateShowsTakenError] : XCTUnwrap failed: expected non-nil value of type "LocalAccount"
Test Suite 'ChatAppPackageTests.xctest' failed at 2026-06-05 19:30:04.999.
	 Executed 185 tests, with 11 failures (5 unexpected) in 433.245 (433.263) seconds
task-8 verify: FAIL
verify: FAIL (task-8)
```

Source: `.agentloop/logs/gate.log:77402-77558` and
`.agentloop/state/last_gate.txt:4925-5081`. This is part of task-8's unscoped
`swift test`, not task-5-r1's scoped live filter.

The same scoped service-level test that fails inside task-8's exhausted
full-suite path passes on task-5-r1's fresh backend (`scoped_gate_run.log:289-310`
and `gate_repeatability.log:160-183`, `:345-368`, `:530-553`). Therefore the
aggregator red is owned by task-8's unscoped full-suite path. This builder item
cannot and must not gate on the repo-root `bash verify.sh`, `.agentloop/verify.sh`,
or any `Live*E2ETests` beyond
`testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages`.
