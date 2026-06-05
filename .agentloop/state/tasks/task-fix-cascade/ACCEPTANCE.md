# task-fix-cascade acceptance evidence

Date: 2026-06-05
Worktree: `/Users/ngthluu/choscor/test-chat-app/.agentloop/worktrees/task-fix-cascade-b1`

## Change

Patched `.agentloop/state/tasks/task-3/verify.sh` only at the Swift test invocation inside `swift_output=$(...)`:

```bash
swift test --filter ChatAppTests.MessageCryptoTests --filter ChatAppTests.MessageEnvelopeTests --filter ChatAppTests.HTTPMessageServiceTests --filter ChatAppTests.DMCoordinatorTests --filter ChatAppTests.LiveDME2ETests --filter ChatAppTests.LiveRegistrationE2ETests --filter ChatAppTests.LiveAuthE2ETests 2>&1
```

`swift build 2>&1` and the downstream assertions remain unchanged.

## Isolated task-3 verifier

Command:

```bash
set -o pipefail
{ /usr/bin/time -p bash .agentloop/state/tasks/task-3/verify.sh; echo "exit=$?"; } 2>&1 | tee /tmp/task-fix-cascade-task3-warm.log
```

Key output:

```text
Test Suite 'Selected tests' passed at 2026-06-05 13:27:17.751.
         Executed 34 tests, with 0 failures (0 unexpected) in 0.696 (0.700) seconds
task-3 verify: PASS
real 4.36
user 1.67
sys 1.56
exit=0
```

## Required Swift test proof

Command:

```bash
required_tests=(
  testEncryptDecryptRoundTripsToExactPlaintext
  testTamperedEnvelopeThrows
  testThirdPartyCannotDecrypt
  testSamePlaintextEncryptsToDifferentEnvelopes
  testEnvelopeBytesDoNotContainPlaintext
  testPrekeySignatureVerifiesAndRejectsTampering
  testSendMessageRequestEncodesExactCiphertextKeys
  testEncodedPayloadsContainNoPlaintextBodyOrTextFields
  testSendPostsCiphertextOnlyWithBearerToken
  testPublishPrekeyPutsSignedPrekeyWithBearerToken
  testHistoryDecodesMessageRecords
  testParseSSEEventDecodesDataLineAndIgnoresOtherLines
  testLiveMessagesYieldsSSERecordsAndCompletes
  testStartConversationRejectsPeerWithInvalidPrekeySignature
  testStartConversationShowsUserNotFoundForMissingPeer
  testSendEncryptsCiphertextAndRecipientCanDecryptIt
  testLoadHistoryDecryptsInboundRecordIntoDisplayMessages
  testSubscribeLiveDecryptsInboundRecordAndDedupesExistingMessages
  testLiveEncryptedDirectMessageRoundTripStoresOnlyCiphertext
  testLiveRegistrationPersistsAccountAndDuplicateShowsTakenError
  testLivePasswordFreeAuthRoundTripAndRejectsCorruptedSignature
)
for t in "${required_tests[@]}"; do
  grep -q "${t}.*passed" /tmp/task-fix-cascade-task3-warm.log && printf 'PASS %s\n' "$t"
done
grep -q "LiveGroupE2ETests\|testLiveCoordinatorCreatesGroupAndPeerReceivesDecryptedMessage" /tmp/task-fix-cascade-task3-warm.log || echo 'EXCLUDED_MARKERS_ABSENT'
```

Output:

```text
PASS testEncryptDecryptRoundTripsToExactPlaintext
PASS testTamperedEnvelopeThrows
PASS testThirdPartyCannotDecrypt
PASS testSamePlaintextEncryptsToDifferentEnvelopes
PASS testEnvelopeBytesDoNotContainPlaintext
PASS testPrekeySignatureVerifiesAndRejectsTampering
PASS testSendMessageRequestEncodesExactCiphertextKeys
PASS testEncodedPayloadsContainNoPlaintextBodyOrTextFields
PASS testSendPostsCiphertextOnlyWithBearerToken
PASS testPublishPrekeyPutsSignedPrekeyWithBearerToken
PASS testHistoryDecodesMessageRecords
PASS testParseSSEEventDecodesDataLineAndIgnoresOtherLines
PASS testLiveMessagesYieldsSSERecordsAndCompletes
PASS testStartConversationRejectsPeerWithInvalidPrekeySignature
PASS testStartConversationShowsUserNotFoundForMissingPeer
PASS testSendEncryptsCiphertextAndRecipientCanDecryptIt
PASS testLoadHistoryDecryptsInboundRecordIntoDisplayMessages
PASS testSubscribeLiveDecryptsInboundRecordAndDedupesExistingMessages
PASS testLiveEncryptedDirectMessageRoundTripStoresOnlyCiphertext
PASS testLiveRegistrationPersistsAccountAndDuplicateShowsTakenError
PASS testLivePasswordFreeAuthRoundTripAndRejectsCorruptedSignature
EXCLUDED_MARKERS_ABSENT
```

## Global gate advances past task-3

Command:

```bash
bash .agentloop/verify.sh 2>&1 | awk '
  /verify: RUN \(task-3\)/ { seen_run=1; print; next }
  seen_run && /task-3 verify: PASS/ { seen_pass=1; print; next }
  seen_pass && /verify: RUN \(/ { print; fflush(); exit 0 }
  seen_run && (/task-3 verify: FAIL/ || /verify: FAIL \(task-3\)/) { print; fflush(); exit 2 }
' | tee /tmp/task-fix-cascade-global-excerpt.log
```

Output:

```text
verify: RUN (task-3)
task-3 verify: PASS
verify: RUN (task-4)
```
