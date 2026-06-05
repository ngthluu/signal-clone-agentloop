# task-5-r1-b2 proof

## Repeatability

`gate_repeatability.log` was produced by running the real `.agentloop/state/tasks/task-5-r1/verify.sh`
three times back-to-back, appending each run tail and `EXIT=$?`.

Assertions checked from the log:

- `task-5 verify: PASS` appears 3 times.
- `EXIT=0` appears 3 times.
- No `AddrInUse`, `Address already in use`, `address already in use`, or bind failure text appears.

This exercises the real gate unchanged, including reap-before-boot, ephemeral backend port selection,
the single scoped live Swift filter, DB/wire ciphertext checks, late-member epoch checks, and schema
checks.

## Negative control

To prove the gate is non-vacuous, I made a temporary copy named
`.agentloop/state/tasks/task-5-r1/verify.negative-control.sh`, inverted exactly one live-scope
assertion, ran the copy, captured the failure, and deleted the copy.

The exercised real assertion is in `run_live_scoped_test`:

```bash
require_contains "${LIVE_LOG}" "Executed 1 test"
```

The temporary inverted diff was:

```diff
--- .agentloop/state/tasks/task-5-r1/verify.sh
+++ .agentloop/state/tasks/task-5-r1/verify.negative-control.sh
@@ -188,7 +188,7 @@
   }
   cat "${LIVE_LOG}"
 
-  require_contains "${LIVE_LOG}" "Executed 1 test"
+  require_contains "${LIVE_LOG}" "Executed 2 tests"
   require_contains "${LIVE_LOG}" "with 0 failures"
   require_not_contains "${LIVE_LOG}" "skipped"
   require_not_contains "${LIVE_LOG}" "testLiveCoordinatorCreatesGroupAndPeerReceivesDecryptedMessage"
```

The negative-control run used the temporary copy only. It executed the scoped live filter, the live
test reported `Executed 1 test, with 0 failures`, and then the inverted assertion failed because the
copy required `Executed 2 tests`.

Captured failure tail:

```text
Starting backend on 48494
swift test --filter testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages
Test Suite 'LiveGroupE2ETests' started at 2026-06-05 12:52:07.289.
Test Case '-[ChatAppTests.LiveGroupE2ETests testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages]' started.
Test Case '-[ChatAppTests.LiveGroupE2ETests testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages]' passed (0.221 seconds).
Test Suite 'LiveGroupE2ETests' passed at 2026-06-05 12:52:07.510.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.221 (0.221) seconds
Test Suite 'ChatAppPackageTests.xctest' passed at 2026-06-05 12:52:07.510.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.221 (0.221) seconds
Test Suite 'Selected tests' passed at 2026-06-05 12:52:07.510.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.221 (0.223) seconds
task-5 verify: FAIL
----- backend server log -----
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.06s
     Running `target/debug/test-chat-backend --db-path /var/folders/q9/1lgsjv4n37n0gcrdmg1rfjy00000gn/T/tmp.FMVxTX0ZK1 --port 48494`
----- end backend server log -----
```

Exit code: `1`.

The temporary inverted script was removed after the run. The real `verify.sh` was not modified.
