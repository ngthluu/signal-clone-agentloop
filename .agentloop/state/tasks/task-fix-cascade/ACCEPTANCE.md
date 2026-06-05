# task-fix-cascade acceptance evidence

Captured on 2026-06-05 in worktree `task-fix-cascade-b2`.

The Swift test bundle was warmed once before the timed run because task-1d uses `swift test --skip-build`. The timed command below is the isolated acceptance run.

## 1. Full timed task-1d run

Command:

```bash
time bash .agentloop/state/tasks/task-1d/verify.sh; echo "exit=$?"
```

Output:

```text
task-1d verify: starting backend on http://127.0.0.1:52381
task-1d verify: backend health check returned 200
task-1d verify: building ChatApp
[0/1] Planning build
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.19s)
task-1d verify: running scoped Swift account-flow tests (no live group E2E)
[0/1] Planning build
Test Suite 'Selected tests' started at 2026-06-05 12:51:07.335.
Test Suite 'ChatAppPackageTests.xctest' started at 2026-06-05 12:51:07.336.
Test Suite 'AppRouterTests' started at 2026-06-05 12:51:07.336.
Test Case '-[ChatAppTests.AppRouterTests testResolveReturnsMainWhenAccountExists]' started.
Test Case '-[ChatAppTests.AppRouterTests testResolveReturnsMainWhenAccountExists]' passed (0.000 seconds).
Test Case '-[ChatAppTests.AppRouterTests testResolveReturnsRegistrationWhenNoAccountExists]' started.
Test Case '-[ChatAppTests.AppRouterTests testResolveReturnsRegistrationWhenNoAccountExists]' passed (0.000 seconds).
Test Suite 'AppRouterTests' passed at 2026-06-05 12:51:07.337.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
Test Suite 'LiveRegistrationE2ETests' started at 2026-06-05 12:51:07.337.
Test Case '-[ChatAppTests.LiveRegistrationE2ETests testLiveRegistrationPersistsAccountAndDuplicateShowsTakenError]' started.
Test Case '-[ChatAppTests.LiveRegistrationE2ETests testLiveRegistrationPersistsAccountAndDuplicateShowsTakenError]' passed (0.015 seconds).
Test Suite 'LiveRegistrationE2ETests' passed at 2026-06-05 12:51:07.352.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.015 (0.015) seconds
Test Suite 'LocalAccountStoreTests' started at 2026-06-05 12:51:07.352.
Test Case '-[ChatAppTests.LocalAccountStoreTests testAccountFileContainsOnlyPublicAccountMaterial]' started.
Test Case '-[ChatAppTests.LocalAccountStoreTests testAccountFileContainsOnlyPublicAccountMaterial]' passed (0.001 seconds).
Test Case '-[ChatAppTests.LocalAccountStoreTests testClearRemovesPersistedAccount]' started.
Test Case '-[ChatAppTests.LocalAccountStoreTests testClearRemovesPersistedAccount]' passed (0.000 seconds).
Test Case '-[ChatAppTests.LocalAccountStoreTests testFreshStoreInSameDirectoryLoadsPersistedAccount]' started.
Test Case '-[ChatAppTests.LocalAccountStoreTests testFreshStoreInSameDirectoryLoadsPersistedAccount]' passed (0.001 seconds).
Test Case '-[ChatAppTests.LocalAccountStoreTests testSaveRoundTripsCurrentAccountAndHasAccount]' started.
Test Case '-[ChatAppTests.LocalAccountStoreTests testSaveRoundTripsCurrentAccountAndHasAccount]' passed (0.001 seconds).
Test Suite 'LocalAccountStoreTests' passed at 2026-06-05 12:51:07.354.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds
Test Suite 'RegisterPayloadTests' started at 2026-06-05 12:51:07.354.
Test Case '-[ChatAppTests.RegisterPayloadTests testEncodesExactlyUsernameAndIdentityPublicKey]' started.
Test Case '-[ChatAppTests.RegisterPayloadTests testEncodesExactlyUsernameAndIdentityPublicKey]' passed (0.000 seconds).
Test Suite 'RegisterPayloadTests' passed at 2026-06-05 12:51:07.354.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'RegistrationCoordinatorTests' started at 2026-06-05 12:51:07.354.
Test Case '-[ChatAppTests.RegistrationCoordinatorTests testExistingAccountMarksCoordinatorRegisteredAtInit]' started.
Test Case '-[ChatAppTests.RegistrationCoordinatorTests testExistingAccountMarksCoordinatorRegisteredAtInit]' passed (0.001 seconds).
Test Case '-[ChatAppTests.RegistrationCoordinatorTests testSuccessfulRegistrationPersistsAccountAndMarksRegistered]' started.
Test Case '-[ChatAppTests.RegistrationCoordinatorTests testSuccessfulRegistrationPersistsAccountAndMarksRegistered]' passed (0.001 seconds).
Test Case '-[ChatAppTests.RegistrationCoordinatorTests testUsernameTakenShowsClearErrorAndDoesNotPersistAccount]' started.
Test Case '-[ChatAppTests.RegistrationCoordinatorTests testUsernameTakenShowsClearErrorAndDoesNotPersistAccount]' passed (0.000 seconds).
Test Suite 'RegistrationCoordinatorTests' passed at 2026-06-05 12:51:07.356.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds
Test Suite 'RegistrationServiceCaptureTests' started at 2026-06-05 12:51:07.356.
Test Case '-[ChatAppTests.RegistrationServiceCaptureTests testHTTPClientMapsBadRequestToInvalid]' started.
Test Case '-[ChatAppTests.RegistrationServiceCaptureTests testHTTPClientMapsBadRequestToInvalid]' passed (0.000 seconds).
Test Case '-[ChatAppTests.RegistrationServiceCaptureTests testHTTPClientMapsConflictToUsernameTaken]' started.
Test Case '-[ChatAppTests.RegistrationServiceCaptureTests testHTTPClientMapsConflictToUsernameTaken]' passed (0.000 seconds).
Test Case '-[ChatAppTests.RegistrationServiceCaptureTests testHTTPClientTransmitsExactlyTwoFieldRegisterPayload]' started.
Test Case '-[ChatAppTests.RegistrationServiceCaptureTests testHTTPClientTransmitsExactlyTwoFieldRegisterPayload]' passed (0.000 seconds).
Test Suite 'RegistrationServiceCaptureTests' passed at 2026-06-05 12:51:07.357.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'ChatAppPackageTests.xctest' passed at 2026-06-05 12:51:07.357.
	 Executed 14 tests, with 0 failures (0 unexpected) in 0.020 (0.021) seconds
Test Suite 'Selected tests' passed at 2026-06-05 12:51:07.357.
	 Executed 14 tests, with 0 failures (0 unexpected) in 0.020 (0.022) seconds
􀟈  Test run started.
􀄵  Testing Library Version: 1902
􀄵  Target Platform: arm64e-apple-macos14.0
􁁛  Test run with 0 tests in 0 suites passed after 0.001 seconds.
task-1d verify: running schema/row dump
PRAGMA table_info(users)
cid  name                 type  notnull  dflt_value  pk
---  -------------------  ----  -------  ----------  --
0    id                   TEXT  0                    1
1    username             TEXT  1                    0
2    identity_public_key  TEXT  1                    0
3    created_at           TEXT  1                    0

sample stored user row
id                                    username                   identity_public_key                           created_at
------------------------------------  -------------------------  --------------------------------------------  --------------------
e63afa62-12d5-455b-abaa-cbe5920f9f26  live_21B02C06496140FB8354  BzkaF/LJJIs1b5M8zDzFGFNr3aFO3Ct0WJ4eppI6lQI=  2026-06-05T05:51:07Z

confirmed no private/secret columns or private material in users schema or sample row
task-1d verify: PASS
.agentloop/state/tasks/task-1d/verify.sh: line 22: 59388 Terminated: 15          ( cd "${BACKEND_DIR}"; cargo run -- --db-path "${DB_PATH}" --port "${PORT}" ) > "${SERVER_LOG}" 2>&1
real 2.858
exit=0
```

This shows `exit=0`, `real 2.858` seconds (<60s), and `task-1d verify: PASS`.

## 2. Scope proof

Command and output:

```text
$ grep -E "LiveGroupE2ETests|testLiveCoordinatorCreatesGroupAndPeerReceivesDecryptedMessage" /tmp/task-fix-cascade-task1d-timed.log; echo exit=$?
exit=1

$ grep -E "Executed 14 tests, with 0 failures|with 0 failures" /tmp/task-fix-cascade-task1d-timed.log
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
	 Executed 1 test, with 0 failures (0 unexpected) in 0.015 (0.015) seconds
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds
	 Executed 1 test, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
	 Executed 14 tests, with 0 failures (0 unexpected) in 0.020 (0.021) seconds
	 Executed 14 tests, with 0 failures (0 unexpected) in 0.020 (0.022) seconds
```

The first grep had zero matches (`exit=1`) for both `LiveGroupE2ETests` and `testLiveCoordinatorCreatesGroupAndPeerReceivesDecryptedMessage`.

## 3. Global gate pass-through evidence

Command:

```bash
bash .agentloop/verify.sh
```

Relevant excerpt:

```text
verify: RUN (task-1d)
task-1d verify: starting backend on http://127.0.0.1:46478
task-1d verify: backend health check returned 200
task-1d verify: building ChatApp
[0/1] Planning build
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.12s)
task-1d verify: running scoped Swift account-flow tests (no live group E2E)
[0/1] Planning build
Test Suite 'Selected tests' started at 2026-06-05 12:52:02.469.
Test Suite 'ChatAppPackageTests.xctest' started at 2026-06-05 12:52:02.470.
Test Suite 'AppRouterTests' started at 2026-06-05 12:52:02.470.
Test Case '-[ChatAppTests.AppRouterTests testResolveReturnsMainWhenAccountExists]' started.
Test Case '-[ChatAppTests.AppRouterTests testResolveReturnsMainWhenAccountExists]' passed (0.000 seconds).
Test Case '-[ChatAppTests.AppRouterTests testResolveReturnsRegistrationWhenNoAccountExists]' started.
Test Case '-[ChatAppTests.AppRouterTests testResolveReturnsRegistrationWhenNoAccountExists]' passed (0.000 seconds).
Test Suite 'AppRouterTests' passed at 2026-06-05 12:52:02.471.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
Test Suite 'LiveRegistrationE2ETests' started at 2026-06-05 12:52:02.471.
Test Case '-[ChatAppTests.LiveRegistrationE2ETests testLiveRegistrationPersistsAccountAndDuplicateShowsTakenError]' started.
Test Case '-[ChatAppTests.LiveRegistrationE2ETests testLiveRegistrationPersistsAccountAndDuplicateShowsTakenError]' passed (0.014 seconds).
Test Suite 'LiveRegistrationE2ETests' passed at 2026-06-05 12:52:02.485.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.014 (0.014) seconds
Test Suite 'LocalAccountStoreTests' started at 2026-06-05 12:52:02.485.
Test Case '-[ChatAppTests.LocalAccountStoreTests testAccountFileContainsOnlyPublicAccountMaterial]' started.
Test Case '-[ChatAppTests.LocalAccountStoreTests testAccountFileContainsOnlyPublicAccountMaterial]' passed (0.000 seconds).
Test Case '-[ChatAppTests.LocalAccountStoreTests testClearRemovesPersistedAccount]' started.
Test Case '-[ChatAppTests.LocalAccountStoreTests testClearRemovesPersistedAccount]' passed (0.001 seconds).
Test Case '-[ChatAppTests.LocalAccountStoreTests testFreshStoreInSameDirectoryLoadsPersistedAccount]' started.
Test Case '-[ChatAppTests.LocalAccountStoreTests testFreshStoreInSameDirectoryLoadsPersistedAccount]' passed (0.000 seconds).
Test Case '-[ChatAppTests.LocalAccountStoreTests testSaveRoundTripsCurrentAccountAndHasAccount]' started.
Test Case '-[ChatAppTests.LocalAccountStoreTests testSaveRoundTripsCurrentAccountAndHasAccount]' passed (0.000 seconds).
Test Suite 'LocalAccountStoreTests' passed at 2026-06-05 12:52:02.487.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds
Test Suite 'RegisterPayloadTests' started at 2026-06-05 12:52:02.487.
Test Case '-[ChatAppTests.RegisterPayloadTests testEncodesExactlyUsernameAndIdentityPublicKey]' started.
Test Case '-[ChatAppTests.RegisterPayloadTests testEncodesExactlyUsernameAndIdentityPublicKey]' passed (0.000 seconds).
Test Suite 'RegisterPayloadTests' passed at 2026-06-05 12:52:02.487.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'RegistrationCoordinatorTests' started at 2026-06-05 12:52:02.487.
Test Case '-[ChatAppTests.RegistrationCoordinatorTests testExistingAccountMarksCoordinatorRegisteredAtInit]' started.
Test Case '-[ChatAppTests.RegistrationCoordinatorTests testExistingAccountMarksCoordinatorRegisteredAtInit]' passed (0.000 seconds).
Test Case '-[ChatAppTests.RegistrationCoordinatorTests testSuccessfulRegistrationPersistsAccountAndMarksRegistered]' started.
Test Case '-[ChatAppTests.RegistrationCoordinatorTests testSuccessfulRegistrationPersistsAccountAndMarksRegistered]' passed (0.001 seconds).
Test Case '-[ChatAppTests.RegistrationCoordinatorTests testUsernameTakenShowsClearErrorAndDoesNotPersistAccount]' started.
Test Case '-[ChatAppTests.RegistrationCoordinatorTests testUsernameTakenShowsClearErrorAndDoesNotPersistAccount]' passed (0.000 seconds).
Test Suite 'RegistrationCoordinatorTests' passed at 2026-06-05 12:52:02.489.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'RegistrationServiceCaptureTests' started at 2026-06-05 12:52:02.489.
Test Case '-[ChatAppTests.RegistrationServiceCaptureTests testHTTPClientMapsBadRequestToInvalid]' started.
Test Case '-[ChatAppTests.RegistrationServiceCaptureTests testHTTPClientMapsBadRequestToInvalid]' passed (0.000 seconds).
Test Case '-[ChatAppTests.RegistrationServiceCaptureTests testHTTPClientMapsConflictToUsernameTaken]' started.
Test Case '-[ChatAppTests.RegistrationServiceCaptureTests testHTTPClientMapsConflictToUsernameTaken]' passed (0.000 seconds).
Test Case '-[ChatAppTests.RegistrationServiceCaptureTests testHTTPClientTransmitsExactlyTwoFieldRegisterPayload]' started.
Test Case '-[ChatAppTests.RegistrationServiceCaptureTests testHTTPClientTransmitsExactlyTwoFieldRegisterPayload]' passed (0.000 seconds).
Test Suite 'RegistrationServiceCaptureTests' passed at 2026-06-05 12:52:02.490.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'ChatAppPackageTests.xctest' passed at 2026-06-05 12:52:02.490.
	 Executed 14 tests, with 0 failures (0 unexpected) in 0.019 (0.020) seconds
Test Suite 'Selected tests' passed at 2026-06-05 12:52:02.490.
	 Executed 14 tests, with 0 failures (0 unexpected) in 0.019 (0.020) seconds
􀟈  Test run started.
􀄵  Testing Library Version: 1902
􀄵  Target Platform: arm64e-apple-macos14.0
􁁛  Test run with 0 tests in 0 suites passed after 0.001 seconds.
task-1d verify: running schema/row dump
PRAGMA table_info(users)
cid  name                 type  notnull  dflt_value  pk
---  -------------------  ----  -------  ----------  --
0    id                   TEXT  0                    1
1    username             TEXT  1                    0
2    identity_public_key  TEXT  1                    0
3    created_at           TEXT  1                    0

sample stored user row
id                                    username                   identity_public_key                           created_at
------------------------------------  -------------------------  --------------------------------------------  --------------------
40a44e5b-1cda-4438-b00a-6f524c08ddcd  live_CF42BFE670824863AC71  EyDzZWgU3BcTLC6NqHp1RIzf/RMO9kmtTjHjhvMAjEA=  2026-06-05T05:52:02Z

confirmed no private/secret columns or private material in users schema or sample row
task-1d verify: PASS
/Users/ngthluu/choscor/test-chat-app/.agentloop/worktrees/task-fix-cascade-b2/.agentloop/state/tasks/task-1d/verify.sh: line 22: 63485 Terminated: 15          ( cd "${BACKEND_DIR}"; cargo run -- --db-path "${DB_PATH}" --port "${PORT}" ) > "${SERVER_LOG}" 2>&1
verify: RUN (task-3)
```

There is no `verify: FAIL (task-1d)` in the captured global gate log. The gate advanced from task-1d to task-3, so task-1d did not trigger the previous LiveGroupE2ETests cascade. The global gate run was stopped after it entered downstream task-3 live E2E work; downstream completion is explicitly out of scope for this builder item.

## Functional guarantees represented

- Live registration E2E and duplicate username rejection: `testLiveRegistrationPersistsAccountAndDuplicateShowsTakenError` passed.
- No private material on wire: `testEncodesExactlyUsernameAndIdentityPublicKey` and `testHTTPClientTransmitsExactlyTwoFieldRegisterPayload` passed.
- Duplicate username mapping: `testHTTPClientMapsConflictToUsernameTaken` and `testUsernameTakenShowsClearErrorAndDoesNotPersistAccount` passed.
- No private material in DB: schema dump shows only `id`, `username`, `identity_public_key`, `created_at`, includes a sample stored user row, and confirms no private/secret columns or private material.
