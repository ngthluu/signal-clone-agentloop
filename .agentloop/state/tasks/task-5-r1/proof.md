# task-5-r1-b5 proof

Generated on 2026-06-05 from the real task gate at:

```text
.agentloop/state/tasks/task-5-r1/verify.sh
```

The real gate was not edited for these controls. Temporary copies were created, mutated, run, and
removed. Final real-script checksum after the controls:

```text
a402ae2a01657f5c3810d2f71a63c5bd91472a1ba369c1a42d51b33ed5637bcd  .agentloop/state/tasks/task-5-r1/verify.sh
```

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
Starting backend on 45570
swift test --filter testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages
[0/1] Planning build
Building for debugging...
[0/4] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.14s)
Test Suite 'Selected tests' started at 2026-06-05 22:13:32.920.
Test Suite 'ChatAppPackageTests.xctest' started at 2026-06-05 22:13:32.921.
Test Suite 'LiveGroupE2ETests' started at 2026-06-05 22:13:32.921.
Test Case '-[ChatAppTests.LiveGroupE2ETests testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages]' started.
Test Case '-[ChatAppTests.LiveGroupE2ETests testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages]' passed (0.212 seconds).
Test Suite 'LiveGroupE2ETests' passed at 2026-06-05 22:13:33.133.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.212 (0.212) seconds
Test Suite 'ChatAppPackageTests.xctest' passed at 2026-06-05 22:13:33.133.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.212 (0.213) seconds
Test Suite 'Selected tests' passed at 2026-06-05 22:13:33.133.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.212 (0.213) seconds
task-5 verify: FAIL
----- backend server log -----
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.07s
     Running `target/debug/test-chat-backend --db-path /var/folders/q9/1lgsjv4n37n0gcrdmg1rfjy00000gn/T/tmp.pqTZ02zNmf --port 45570`
----- end backend server log -----
EXIT=1
```

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
EXIT=1
```

## Final Real Gate PASS

After both temporary controls were removed, the unchanged real gate was run:

```bash
bash .agentloop/state/tasks/task-5-r1/verify.sh
```

Captured pass tail:

```text
Starting backend on 48407
swift test --filter testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages
[0/1] Planning build
Building for debugging...
[0/4] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.14s)
Test Suite 'Selected tests' started at 2026-06-05 22:14:04.120.
Test Suite 'ChatAppPackageTests.xctest' started at 2026-06-05 22:14:04.120.
Test Suite 'LiveGroupE2ETests' started at 2026-06-05 22:14:04.120.
Test Case '-[ChatAppTests.LiveGroupE2ETests testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages]' started.
Test Case '-[ChatAppTests.LiveGroupE2ETests testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages]' passed (0.209 seconds).
Test Suite 'LiveGroupE2ETests' passed at 2026-06-05 22:14:04.330.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.209 (0.209) seconds
Test Suite 'ChatAppPackageTests.xctest' passed at 2026-06-05 22:14:04.330.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.209 (0.209) seconds
Test Suite 'Selected tests' passed at 2026-06-05 22:14:04.330.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.209 (0.210) seconds
task-5 verify: PASS
EXIT=0
```

## Reversion

No temporary negative-control script remains under `.agentloop/state/tasks/task-5-r1/`. The real
`verify.sh` was not edited for either control; only copies were changed and removed.

Verification command:

```bash
git diff -- .agentloop/state/tasks/task-5-r1/verify.sh
```

Output was empty.
