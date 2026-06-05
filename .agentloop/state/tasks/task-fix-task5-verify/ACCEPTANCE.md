# task-fix-task5-verify Acceptance Evidence

## Legacy task-5-r1 is not active

Static discovery no longer finds `task-5-r1/verify.sh`:

```text
$ find .agentloop/state/tasks -mindepth 2 -maxdepth 2 -name verify.sh -type f | sort | grep '/task-5-r1/'
(no output)
```

The current gate is still discoverable:

```text
$ find .agentloop/state/tasks -mindepth 2 -maxdepth 2 -name verify.sh -type f | sort | grep '/task-5-r2/verify.sh'
.agentloop/state/tasks/task-5-r2/verify.sh
```

The captured global log contains no `verify: RUN (task-5-r1)`. Its group-creation segment enters `task-5-r2` instead:

```text
verify: RUN (task-5-r2)
task-5-r2 verify: PASS
```

## Current task-5-r2 gate passes

Direct task-local evidence from `.agentloop/state/tasks/task-fix-task5-verify/verify-task-5-r2.log`:

```text
task-5-r2 verify: PASS
```

Global path evidence from `.agentloop/state/tasks/task-fix-task5-verify/verify-global.log`:

```text
verify: RUN (task-5-r2)
task-5-r2 verify: PASS
```

The global log contains no `verify: FAIL (task-5-r2)`.

## Scoped backend and Swift filters

Backend filters are scoped to exact `groups` tests:

```text
task-5-r2 verify: cargo test --test groups group_create_requires_creator_plus_two_invited_members -- --exact
task-5-r2 verify: cargo test --test groups group_created_by_signed_in_user_is_listed_for_invited_members_only -- --exact
task-5-r2 verify: cargo test --test groups group_endpoints_reject_non_members_with_403 -- --exact
task-5-r2 verify: cargo test --test groups group_records_store_only_metadata_public_material_and_wrapped_key_envelopes -- --exact
```

Swift filters are scoped one at a time:

```text
task-5-r2 verify: swift test --filter ChatAppTests.GroupCoordinatorTests/testCreateGroupRequiresAtLeastTwoInvitedMembers
task-5-r2 verify: swift test --filter ChatAppTests.GroupCoordinatorTests/testCreateGroupWrapsEpochZeroKeyToCreatorAndTwoInvitees
task-5-r2 verify: swift test --filter ChatAppTests.GroupCoordinatorTests/testInvitedMemberRefreshGroupsShowsCreatedGroupAndOpenDecryptsHistory
task-5-r2 verify: swift test --filter ChatAppTests.GroupEnvelopeTests/testCreateGroupRequestEncodesSnakeCaseKeys
task-5-r2 verify: swift test --filter ChatAppTests.HTTPGroupServiceTests/testCreateGroupPostsMembersWithBearerTokenAndDecodesResponse
task-5-r2 verify: swift test --filter testLiveCoordinatorCreateWithTwoInviteesListsForMembersAndBlocksNonMember
```

## Flaky retired live method excluded

The active `task-5-r2` evidence runs only:

```text
task-5-r2 verify: swift test --filter testLiveCoordinatorCreateWithTwoInviteesListsForMembersAndBlocksNonMember
```

`testLiveCoordinatorCreatesGroupAndPeerReceivesDecryptedMessage` is absent from `.agentloop/state/tasks/task-fix-task5-verify/verify-task-5-r2.log`.

## No task-local verify.sh created

```text
$ find .agentloop/state/tasks/task-fix-task5-verify -maxdepth 1 -name verify.sh -print
(no output)
```

## No application source or global backlog changes

`git diff --name-only` produced no output after the verification run. The only untracked worktree entry was the generated Swift build directory:

```text
?? mac-app/.build/
```

No files under `backend/src`, `backend/tests`, `mac-app/Sources`, `mac-app/Tests`, or `.agentloop/state/backlog*` were modified by this builder.

## Global gate final outcome

The global gate was run as:

```text
bash .agentloop/verify.sh
```

It exited `1` after passing `task-5-r2`, due to a later downstream legacy `task-5` failure:

```text
verify: RUN (task-5)
task-5 verify: FAIL
reason: backend acceptance test did not execute and pass: group_tables_store_no_plaintext_columns
```
