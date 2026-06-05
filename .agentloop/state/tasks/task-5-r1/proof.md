# task-5-r1-b2 proof

Generated from the b1-strengthened real gate at:

```text
.agentloop/state/tasks/task-5-r1/verify.sh
```

The real script was used unchanged for the green repeatability runs. Temporary negative-control
copies were deleted after their runs. Final real-script checksum after the controls:

```text
a402ae2a01657f5c3810d2f71a63c5bd91472a1ba369c1a42d51b33ed5637bcd  .agentloop/state/tasks/task-5-r1/verify.sh
```

## Repeatability

`gate_repeatability.log` was regenerated on 2026-06-05 by running:

```bash
bash .agentloop/state/tasks/task-5-r1/verify.sh
```

three times back-to-back, appending each run tail and `EXIT=<code>`.

Evidence cited from `gate_repeatability.log`:

```text
RUN 1: Starting backend on 45698 ... task-5 verify: PASS ... EXIT=0
RUN 2: Starting backend on 46679 ... task-5 verify: PASS ... EXIT=0
RUN 3: Starting backend on 47665 ... task-5 verify: PASS ... EXIT=0
```

The three backend ports are distinct, demonstrating fresh ephemeral backend startup for each run.
The log contains zero occurrences of `AddrInUse`, `Address already in use`, `address already in use`,
or bind-failure text.

## Negative Control 1: Inverted Live Count Assertion

Temporary copy:

```text
.agentloop/state/tasks/task-5-r1/verify.negative-control.sh
```

The copy changed exactly one substantive assertion in `run_live_scoped_test`:

```diff
-  require_contains "${LIVE_LOG}" "Executed 1 test"
+  require_contains "${LIVE_LOG}" "Executed 2 tests"
```

The temporary copy ran the same scoped live filter, the live test reported one executed test, and the
inverted assertion failed.

Captured failure tail:

```text
Starting backend on 49850
swift test --filter testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages
Test Suite 'LiveGroupE2ETests' started at 2026-06-05 19:10:15.994.
Test Case '-[ChatAppTests.LiveGroupE2ETests testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages]' started.
Test Case '-[ChatAppTests.LiveGroupE2ETests testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages]' passed (0.198 seconds).
Test Suite 'LiveGroupE2ETests' passed at 2026-06-05 19:10:16.192.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.198 (0.198) seconds
Test Suite 'ChatAppPackageTests.xctest' passed at 2026-06-05 19:10:16.192.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.198 (0.198) seconds
Test Suite 'Selected tests' passed at 2026-06-05 19:10:16.192.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.198 (0.199) seconds
task-5 verify: FAIL
----- backend server log -----
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.07s
     Running `target/debug/test-chat-backend --db-path /var/folders/q9/1lgsjv4n37n0gcrdmg1rfjy00000gn/T/tmp.QGF31ckEqh --port 49850`
----- end backend server log -----
```

Exit code: `1`.

The temporary script was deleted after the run.

## Negative Control 2: Self-Guard Aggregator Injection

Temporary copy:

```text
.agentloop/state/tasks/task-5-r1/verify.selfguard-control.sh
```

The copy injected an out-of-scope aggregator invocation immediately after the real `self_guard` call:

```diff
 preflight
 self_guard
+bash .agentloop/verify.sh
 
 DB_PATH="$(mktemp)"
```

The self-guard scanned the temporary copy, detected the `.agentloop/verify.sh` line, and failed
before the injected line could run.

Captured failure output:

```text
task-5 verify: FAIL
```

Exit code: `1`.

The temporary script was deleted after the run.

## Reversion

No temporary negative-control script remains under `.agentloop/state/tasks/task-5-r1/`. The real
`verify.sh` was not edited for either control; only copies were changed and removed.
