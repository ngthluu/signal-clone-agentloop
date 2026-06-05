#!/usr/bin/env bash
set -euo pipefail

SERVER_PID=""
DB_PATH=""
SERVER_LOG=""
SENTINEL_OUT=""
WIRE_OUT=""
MSGID_OUT=""
GROUP_ID_OUT=""
TOKEN_OUT=""
LATE_MEMBER_OUT=""
CONTINUITY_MSGID_OUT=""

fail() {
  echo "task-5 verify: FAIL"
  echo "reason: $*" >&2
  if [[ -n "${SERVER_LOG}" && -f "${SERVER_LOG}" ]]; then
    echo "server log:" >&2
    sed -n '1,220p' "${SERVER_LOG}" >&2 || true
  fi
  exit 1
}

cleanup() {
  if [[ -n "${SERVER_PID}" ]]; then
    if kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
      kill "${SERVER_PID}" >/dev/null 2>&1 || true
      for _ in {1..20}; do
        if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
          break
        fi
        sleep 0.1
      done
      if kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
        kill -9 "${SERVER_PID}" >/dev/null 2>&1 || true
      fi
    fi
    wait "${SERVER_PID}" >/dev/null 2>&1 || true
  fi

  [[ -n "${DB_PATH}" ]] && rm -f "${DB_PATH}"
  [[ -n "${SERVER_LOG}" ]] && rm -f "${SERVER_LOG}"
  [[ -n "${SENTINEL_OUT}" ]] && rm -f "${SENTINEL_OUT}"
  [[ -n "${WIRE_OUT}" ]] && rm -f "${WIRE_OUT}"
  [[ -n "${MSGID_OUT}" ]] && rm -f "${MSGID_OUT}"
  [[ -n "${GROUP_ID_OUT}" ]] && rm -f "${GROUP_ID_OUT}"
  [[ -n "${TOKEN_OUT}" ]] && rm -f "${TOKEN_OUT}"
  [[ -n "${LATE_MEMBER_OUT}" ]] && rm -f "${LATE_MEMBER_OUT}"
  [[ -n "${CONTINUITY_MSGID_OUT}" ]] && rm -f "${CONTINUITY_MSGID_OUT}"
  return 0
}

trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
MAC_APP_DIR="${REPO_ROOT}/mac-app"

if [[ ! -f "${BACKEND_DIR}/Cargo.toml" ]]; then
  fail "backend Cargo.toml not found at ${BACKEND_DIR}"
fi

if [[ ! -f "${MAC_APP_DIR}/Package.swift" ]]; then
  fail "mac-app Package.swift not found at ${MAC_APP_DIR}"
fi

if ! command -v curl >/dev/null 2>&1; then
  fail "curl is required"
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  fail "sqlite3 CLI is required"
fi

echo "task-5 verify: reaping stale backend processes"
bash "${BACKEND_DIR}/scripts/reap_stale_backends.sh" || fail "failed to reap stale backend processes"

echo "task-5 verify: building and testing backend"
cargo_output="$(
  cd "${BACKEND_DIR}"
  cargo build 2>&1
  cargo test 2>&1
)" || {
  printf '%s\n' "${cargo_output}"
  fail "backend cargo build/test failed"
}

printf '%s\n' "${cargo_output}"

if grep -q "error\\[" <<<"${cargo_output}"; then
  fail "backend cargo output contained a Rust compiler error"
fi

if ! grep -Eq "test result: ok\\..*0 failed" <<<"${cargo_output}"; then
  fail "backend cargo output did not report passing test results with 0 failed"
fi

required_rust_tests=(
  "group_create_persists_name_membership_and_epoch_zero_keys"
  "group_create_requires_bearer_token"
  "group_endpoints_reject_non_members_with_403"
  "group_stream_requires_bearer_token"
  "group_stream_with_member_returns_sse_headers"
  "group_message_post_stores_exactly_the_ciphertext_blob"
  "group_message_history_returns_only_ciphertext_for_members"
  "group_add_member_bumps_epoch_and_blocks_prior_epoch_keys"
  "group_add_member_broadcasts_epoch_event_to_members"
  "group_tables_store_no_plaintext_columns"
)

for test_name in "${required_rust_tests[@]}"; do
  if ! grep -Eq "test ${test_name} \\.\\.\\. ok" <<<"${cargo_output}"; then
    fail "backend acceptance test did not execute and pass: ${test_name}"
  fi
done

DB_PATH="$(mktemp -t task-5-group-db.XXXXXX)"
SERVER_LOG="$(mktemp -t task-5-server-log.XXXXXX)"
SENTINEL_OUT="$(mktemp -t task-5-sentinel.XXXXXX)"
WIRE_OUT="$(mktemp -t task-5-wire.XXXXXX)"
MSGID_OUT="$(mktemp -t task-5-message-id.XXXXXX)"
GROUP_ID_OUT="$(mktemp -t task-5-group-id.XXXXXX)"
TOKEN_OUT="$(mktemp -t task-5-token.XXXXXX)"
LATE_MEMBER_OUT="$(mktemp -t task-5-late-member.XXXXXX)"
CONTINUITY_MSGID_OUT="$(mktemp -t task-5-continuity-message-id.XXXXXX)"
PORT="${TASK_5_PORT:-$((45000 + ($$ % 10000)))}"
BASE_URL="http://127.0.0.1:${PORT}"

echo "task-5 verify: starting backend on ${BASE_URL}"
(
  cd "${BACKEND_DIR}"
  cargo run -- --db-path "${DB_PATH}" --port "${PORT}"
) >"${SERVER_LOG}" 2>&1 &
SERVER_PID="$!"

health_ok=0
for _ in {1..120}; do
  if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
    fail "backend process exited before health check passed"
  fi

  status="$(curl -sS --max-time 2 -o /dev/null -w '%{http_code}' "${BASE_URL}/health" 2>/dev/null || true)"
  if [[ "${status}" == "200" ]]; then
    health_ok=1
    break
  fi
  sleep 0.5
done

if [[ "${health_ok}" != "1" ]]; then
  fail "backend did not return 200 from /health within timeout"
fi

echo "task-5 verify: backend health check returned 200"
export CHATAPP_LIVE_BACKEND_URL="${BASE_URL}"
export CHATAPP_GROUP_SENTINEL_OUT="${SENTINEL_OUT}"
export CHATAPP_GROUP_WIRE_OUT="${WIRE_OUT}"
export CHATAPP_GROUP_MSGID_OUT="${MSGID_OUT}"
export CHATAPP_GROUP_ID_OUT="${GROUP_ID_OUT}"
export CHATAPP_GROUP_TOKEN_OUT="${TOKEN_OUT}"
export CHATAPP_GROUP_LATE_MEMBER_OUT="${LATE_MEMBER_OUT}"
export CHATAPP_GROUP_CONTINUITY_MSGID_OUT="${CONTINUITY_MSGID_OUT}"

required_swift_tests=(
  "testLiveGroupExistingMembersKeepReceivingAfterAddWhileNewMemberExcluded"
  "testLiveGroupAllThreeMembersSendAndReceiveThroughCoordinators"
  "testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages"
  "testNewGroupKeyIsThirtyTwoBytes"
  "testWrapAndUnwrapGroupKeyRoundTripsToExactBytes"
  "testThirdPartyCannotUnwrapGroupKey"
  "testEncryptDecryptGroupMessageRoundTripsToExactPlaintext"
  "testWrongGroupKeyFailsToDecryptGroupMessage"
  "testMessageEpochRecoversEmbeddedBigEndianEpoch"
  "testMessageEnvelopeDoesNotContainPlaintextBytes"
  "testSamePlaintextEncryptedTwiceProducesDifferentEnvelopes"
  "testInvalidGroupEnvelopeErrorsAreStable"
  "testCreateGroupRequestEncodesSnakeCaseKeys"
  "testSendGroupMessageRequestEncodesExactlyEpochAndCiphertext"
  "testEncodedPayloadsContainNoPlaintextBodyOrTextKeys"
  "testCreateGroupPostsMembersWithBearerTokenAndDecodesResponse"
  "testAddMemberPostsEpochKeysAndDecodesResponse"
  "testSendGroupMessagePostsCiphertextOnlyAndMapsStatuses"
  "testGetEndpointsDecodeGroupPayloads"
  "testParseGroupSSEEventDecodesDataLineAndIgnoresOtherLines"
  "testLiveGroupMessagesYieldsSSERecordsAndCompletes"
  "testCreateGroupWrapsEpochZeroKeyToEveryMember"
  "testCreateGroupRejectsMemberWithInvalidPrekeySignature"
  "testSendEncryptsUnderCurrentEpochKey"
  "testLateAddedMemberCannotDecryptPriorEpochMessage"
  "testOpenGroupDecryptsHistoryAndSkipsUndecryptable"
  "testSubscribeLiveDecryptsInboundGroupRecord"
  "testLiveEncryptedDirectMessageRoundTripStoresOnlyCiphertext"
  "testLiveRegistrationPersistsAccountAndDuplicateShowsTakenError"
  "testLivePasswordFreeAuthRoundTripAndRejectsCorruptedSignature"
  "testEncryptDecryptRoundTripsToExactPlaintext"
  "testSendPostsCiphertextOnlyWithBearerToken"
)

echo "task-5 verify: building and testing Swift app with live group E2E"
swift_output="$(
  cd "${MAC_APP_DIR}"
  swift build 2>&1
  for test_name in "${required_swift_tests[@]}"; do
    swift test --filter "${test_name}" 2>&1
  done
)" || {
  printf '%s\n' "${swift_output}"
  fail "swift build/test failed"
}

printf '%s\n' "${swift_output}"

if ! grep -Eq "Test Suite 'All tests' passed|Test run .* passed" <<<"${swift_output}"; then
  fail "swift test output did not report a passing test run"
fi

if ! grep -q "with 0 failures" <<<"${swift_output}"; then
  fail "swift test output did not report 0 failures"
fi

for test_name in "${required_swift_tests[@]}"; do
  if grep -q "${test_name}.*failed" <<<"${swift_output}"; then
    fail "acceptance-critical Swift test failed: ${test_name}"
  fi

  if grep -q "${test_name}.*skipped" <<<"${swift_output}"; then
    fail "acceptance-critical Swift test skipped: ${test_name}"
  fi

  if ! grep -q "${test_name}.*passed" <<<"${swift_output}"; then
    fail "acceptance-critical Swift test did not execute and pass: ${test_name}"
  fi
done

if grep -q "testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages.*skipped" <<<"${swift_output}"; then
  fail "LiveGroupE2ETests skipped even though CHATAPP_LIVE_BACKEND_URL was set"
fi

for artifact in "${SENTINEL_OUT}" "${WIRE_OUT}" "${MSGID_OUT}" "${GROUP_ID_OUT}" "${TOKEN_OUT}" "${LATE_MEMBER_OUT}"; do
  if [[ ! -s "${artifact}" ]]; then
    fail "live group proof artifact was not written: ${artifact}"
  fi
done

if [[ ! -s "${CONTINUITY_MSGID_OUT}" ]]; then
  fail "live group continuity proof artifact was not written: ${CONTINUITY_MSGID_OUT}"
fi

SENTINEL="$(cat "${SENTINEL_OUT}")"
MSGID="$(cat "${MSGID_OUT}")"
GROUP_ID="$(cat "${GROUP_ID_OUT}")"
TOKEN="$(cat "${TOKEN_OUT}")"
LATE_MEMBER="$(cat "${LATE_MEMBER_OUT}")"
WIRE_JSON="$(cat "${WIRE_OUT}")"
CONTINUITY_MSGID="$(cat "${CONTINUITY_MSGID_OUT}")"

if [[ -z "${SENTINEL}" || -z "${MSGID}" || -z "${GROUP_ID}" || -z "${TOKEN}" || -z "${LATE_MEMBER}" || -z "${WIRE_JSON}" || -z "${CONTINUITY_MSGID}" ]]; then
  fail "live group proof artifacts must not be empty"
fi

if grep -F -- "${SENTINEL}" "${WIRE_OUT}" >/dev/null 2>&1; then
  fail "sentinel plaintext appeared in captured group message wire payload"
fi

WIRE_CIPHERTEXT="$(sqlite3 -noheader -batch ":memory:" "SELECT json_extract(CAST(readfile('${WIRE_OUT}') AS TEXT), '$.ciphertext');" 2>/dev/null || true)"
if [[ -z "${WIRE_CIPHERTEXT}" ]]; then
  WIRE_CIPHERTEXT="$(sed -n 's/.*"ciphertext":"\([^"]*\)".*/\1/p' "${WIRE_OUT}")"
fi
if [[ -z "${WIRE_CIPHERTEXT}" ]]; then
  fail "could not extract ciphertext from captured group message wire payload"
fi

echo "task-5 verify: proving group wire, history, and DB contain ciphertext only"
history_response="$(curl -sS --max-time 5 -H "Authorization: Bearer ${TOKEN}" "${BASE_URL}/groups/${GROUP_ID}/messages")" || {
  fail "GET /groups/${GROUP_ID}/messages history request failed"
}

if grep -F -- "${SENTINEL}" <<<"${history_response}" >/dev/null 2>&1; then
  fail "sentinel plaintext appeared in GET /groups/:id/messages response"
fi

db_row="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT id,group_id,sender_id,epoch,ciphertext,created_at FROM group_messages WHERE id = '${MSGID}';")"
if [[ -z "${db_row}" ]]; then
  fail "group message row not found in DB for ${MSGID}"
fi

if grep -F -- "${SENTINEL}" <<<"${db_row}" >/dev/null 2>&1; then
  fail "sentinel plaintext appeared in group_messages DB row"
fi

if strings "${DB_PATH}" | grep -F -- "${SENTINEL}" >/dev/null 2>&1; then
  fail "sentinel plaintext appeared in raw DB strings"
fi

stored_ciphertext="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT ciphertext FROM group_messages WHERE id = '${MSGID}';")"
if [[ "${stored_ciphertext}" != "${WIRE_CIPHERTEXT}" ]]; then
  fail "stored group ciphertext did not equal captured wire ciphertext"
fi

echo "task-5 verify: proving post-add coordinator message is persisted and reachable"
continuity_group_id="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT group_id FROM group_messages WHERE id = '${CONTINUITY_MSGID}';")"
if [[ -z "${continuity_group_id}" ]]; then
  fail "continuity group message row not found in DB for ${CONTINUITY_MSGID}"
fi

continuity_token="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT s.token FROM sessions s JOIN group_members gm ON gm.user_id = s.user_id WHERE gm.group_id = '${continuity_group_id}' ORDER BY s.created_at LIMIT 1;")"
if [[ -z "${continuity_token}" ]]; then
  fail "no existing member bearer token found for continuity group ${continuity_group_id}"
fi

continuity_history_response="$(curl -sS --max-time 5 -H "Authorization: Bearer ${continuity_token}" "${BASE_URL}/groups/${continuity_group_id}/messages")" || {
  fail "GET /groups/${continuity_group_id}/messages continuity history request failed"
}

if ! grep -F -- "${CONTINUITY_MSGID}" <<<"${continuity_history_response}" >/dev/null 2>&1; then
  fail "continuity post-add message id ${CONTINUITY_MSGID} was not reachable in group history"
fi

echo "task-5 verify: proving late member lacks prior epoch key"
late_epoch0_count="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT COUNT(*) FROM group_keys gk JOIN users u ON u.id = gk.member_id WHERE gk.group_id = '${GROUP_ID}' AND gk.epoch = 0 AND u.username = '${LATE_MEMBER}';")"
if [[ "${late_epoch0_count}" != "0" ]]; then
  fail "late member had ${late_epoch0_count} epoch-0 group key rows"
fi

late_joined_epoch="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT gm.joined_epoch FROM group_members gm JOIN users u ON u.id = gm.user_id WHERE gm.group_id = '${GROUP_ID}' AND u.username = '${LATE_MEMBER}';")"
if [[ "${late_joined_epoch}" != "1" ]]; then
  fail "late member joined_epoch was ${late_joined_epoch}, expected 1"
fi

echo "task-5 verify: checking group message/key schemas"
bad_columns="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT name FROM pragma_table_info('group_messages') WHERE lower(name) IN ('plaintext','body','text','content','message','cleartext','private','secret') UNION ALL SELECT name FROM pragma_table_info('group_keys') WHERE lower(name) IN ('plaintext','body','text','content','message','cleartext','private','secret');")"
if [[ -n "${bad_columns}" ]]; then
  fail "plaintext-style column name found on group tables: ${bad_columns}"
fi

message_content_columns="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT name FROM pragma_table_info('group_messages') WHERE name = 'ciphertext';")"
if [[ "${message_content_columns}" != "ciphertext" ]]; then
  fail "group_messages did not expose ciphertext as its only message-content column"
fi

key_content_columns="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT name FROM pragma_table_info('group_keys') WHERE name = 'wrapped_key';")"
if [[ "${key_content_columns}" != "wrapped_key" ]]; then
  fail "group_keys did not expose wrapped_key as its only key-content column"
fi

echo "task-5 verify: PASS"
