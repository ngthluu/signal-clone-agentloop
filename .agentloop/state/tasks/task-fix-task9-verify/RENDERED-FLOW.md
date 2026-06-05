# task-9 Rendered Flow Evidence

The live conversation-list E2E exercises this user flow:

1. A user signs in against the fresh backend started by task-9.
2. The app requests `/conversations` with the live session token.
3. The conversation list renders distinct peers ordered by most-recent activity.
4. Selecting each peer loads that peer's `/messages?with=<peer>` history in send order.

The scoped log shows the live backend was available:

> `task-9 verify: starting backend on http://127.0.0.1:51372`

> `task-9 verify: backend health check returned 200`

The live Swift flow ran and passed instead of being skipped:

> `Test Case '-[ChatAppTests.LiveConversationsE2ETests testLiveConversationListOrderingAndHistory]' started.`

> `Test Case '-[ChatAppTests.LiveConversationsE2ETests testLiveConversationListOrderingAndHistory]' passed (2.526 seconds).`

The Swift test wrote the token, conversation-order, and history-count proof artifacts consumed by the shell gate. The script then validated them against the live backend:

> `task-9 verify: proving /conversations ordering`

> `task-9 verify: proving per-conversation message history counts`

The final PASS line confirms the proof artifacts were non-empty, `/conversations` returned exactly two peers matching the order artifact, and the per-peer history counts matched the expected first-peer count of 2 and second-peer count of 1:

> `task-9 verify: PASS`

The Swift run stayed scoped to the four required classes and completed quickly:

> `Test Suite 'Selected tests' passed at 2026-06-05 21:33:10.662.`

> `Executed 16 tests, with 0 failures (0 unexpected) in 2.676 (2.678) seconds`

The saved log contains no `LiveGroupE2ETests` occurrence and no `125` timeout text.
