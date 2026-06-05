#!/usr/bin/env bash
set -euo pipefail

SERVER_PID=""
DB_PATH=""
SERVER_LOG=""
SENTINEL_OUT=""
WIRE_OUT=""
MSGID_OUT=""
TOKEN_OUT=""

fail() {
  echo "task-3 verify: FAIL"
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
  [[ -n "${TOKEN_OUT}" ]] && rm -f "${TOKEN_OUT}"
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

echo "task-3 verify: building and testing backend"
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
  "keys_publish_requires_valid_identity_signature"
  "keys_fetch_returns_published_prekey_for_username"
  "messages_post_requires_bearer_token"
  "messages_post_stores_exactly_the_ciphertext_blob"
  "messages_history_returns_only_ciphertext_and_is_scoped_to_the_pair"
  "messages_table_stores_no_plaintext_columns"
)

for test_name in "${required_rust_tests[@]}"; do
  if ! grep -Eq "test ${test_name} \\.\\.\\. ok" <<<"${cargo_output}"; then
    fail "backend acceptance test did not execute and pass: ${test_name}"
  fi
done

DB_PATH="$(mktemp -t task-3-dm-db.XXXXXX)"
SERVER_LOG="$(mktemp -t task-3-server-log.XXXXXX)"
SENTINEL_OUT="$(mktemp -t task-3-sentinel.XXXXXX)"
WIRE_OUT="$(mktemp -t task-3-wire.XXXXXX)"
MSGID_OUT="$(mktemp -t task-3-message-id.XXXXXX)"
TOKEN_OUT="$(mktemp -t task-3-token.XXXXXX)"
PORT="${TASK_3_PORT:-$((43000 + ($$ % 10000)))}"
BASE_URL="http://127.0.0.1:${PORT}"

echo "task-3 verify: starting backend on ${BASE_URL}"
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

echo "task-3 verify: backend health check returned 200"
export CHATAPP_LIVE_BACKEND_URL="${BASE_URL}"
export CHATAPP_DM_SENTINEL_OUT="${SENTINEL_OUT}"
export CHATAPP_DM_WIRE_OUT="${WIRE_OUT}"
export CHATAPP_DM_MSGID_OUT="${MSGID_OUT}"
export CHATAPP_DM_TOKEN_OUT="${TOKEN_OUT}"

echo "task-3 verify: building and testing Swift app with live DM E2E"
swift_output="$(
  cd "${MAC_APP_DIR}"
  swift build 2>&1
  swift test --filter ChatAppTests.MessageCryptoTests --filter ChatAppTests.MessageEnvelopeTests --filter ChatAppTests.HTTPMessageServiceTests --filter ChatAppTests.DMCoordinatorTests --filter ChatAppTests.LiveDME2ETests --filter ChatAppTests.LiveRegistrationE2ETests --filter ChatAppTests.LiveAuthE2ETests 2>&1
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

required_swift_tests=(
  "testLiveEncryptedDirectMessageRoundTripStoresOnlyCiphertext"
  "testEncryptDecryptRoundTripsToExactPlaintext"
  "testTamperedEnvelopeThrows"
  "testThirdPartyCannotDecrypt"
  "testSamePlaintextEncryptsToDifferentEnvelopes"
  "testEnvelopeBytesDoNotContainPlaintext"
  "testPrekeySignatureVerifiesAndRejectsTampering"
  "testSendMessageRequestEncodesExactCiphertextKeys"
  "testEncodedPayloadsContainNoPlaintextBodyOrTextFields"
  "testSendPostsCiphertextOnlyWithBearerToken"
  "testPublishPrekeyPutsSignedPrekeyWithBearerToken"
  "testHistoryDecodesMessageRecords"
  "testParseSSEEventDecodesDataLineAndIgnoresOtherLines"
  "testLiveMessagesYieldsSSERecordsAndCompletes"
  "testStartConversationRejectsPeerWithInvalidPrekeySignature"
  "testStartConversationShowsUserNotFoundForMissingPeer"
  "testSendEncryptsCiphertextAndRecipientCanDecryptIt"
  "testLoadHistoryDecryptsInboundRecordIntoDisplayMessages"
  "testSubscribeLiveDecryptsInboundRecordAndDedupesExistingMessages"
  "testLiveRegistrationPersistsAccountAndDuplicateShowsTakenError"
  "testLivePasswordFreeAuthRoundTripAndRejectsCorruptedSignature"
)

for test_name in "${required_swift_tests[@]}"; do
  if grep -q "${test_name}.*failed" <<<"${swift_output}"; then
    fail "acceptance-critical Swift test failed: ${test_name}"
  fi

  if ! grep -q "${test_name}.*passed" <<<"${swift_output}"; then
    fail "acceptance-critical Swift test did not execute and pass: ${test_name}"
  fi
done

if grep -q "testLiveEncryptedDirectMessageRoundTripStoresOnlyCiphertext.*skipped" <<<"${swift_output}"; then
  fail "LiveDME2ETests skipped even though CHATAPP_LIVE_BACKEND_URL was set"
fi

for artifact in "${SENTINEL_OUT}" "${WIRE_OUT}" "${MSGID_OUT}" "${TOKEN_OUT}"; do
  if [[ ! -s "${artifact}" ]]; then
    fail "live DM proof artifact was not written: ${artifact}"
  fi
done

SENTINEL="$(cat "${SENTINEL_OUT}")"
MSGID="$(cat "${MSGID_OUT}")"
TOKEN="$(cat "${TOKEN_OUT}")"
WIRE_JSON="$(cat "${WIRE_OUT}")"

if [[ -z "${SENTINEL}" || -z "${MSGID}" || -z "${TOKEN}" || -z "${WIRE_JSON}" ]]; then
  fail "live DM proof artifacts must not be empty"
fi

if grep -F -- "${SENTINEL}" "${WIRE_OUT}" >/dev/null 2>&1; then
  fail "sentinel plaintext appeared in captured wire payload"
fi

WIRE_CIPHERTEXT="$(sqlite3 -noheader -batch ":memory:" "SELECT json_extract(CAST(readfile('${WIRE_OUT}') AS TEXT), '$.ciphertext');" 2>/dev/null || true)"
if [[ -z "${WIRE_CIPHERTEXT}" ]]; then
  WIRE_CIPHERTEXT="$(sed -n 's/.*"ciphertext":"\([^"]*\)".*/\1/p' "${WIRE_OUT}")"
fi
if [[ -z "${WIRE_CIPHERTEXT}" ]]; then
  fail "could not extract ciphertext from captured wire payload"
fi

SENDER_USERNAME="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT u.username FROM messages m JOIN users u ON u.id = m.sender_id WHERE m.id = '${MSGID}';")"
if [[ -z "${SENDER_USERNAME}" ]]; then
  fail "could not resolve sender username for message ${MSGID}"
fi

echo "task-3 verify: proving wire, history, and DB contain ciphertext only"
history_response="$(curl -sS --max-time 5 -H "Authorization: Bearer ${TOKEN}" "${BASE_URL}/messages?with=${SENDER_USERNAME}")" || {
  fail "GET /messages history request failed"
}

if grep -F -- "${SENTINEL}" <<<"${history_response}" >/dev/null 2>&1; then
  fail "sentinel plaintext appeared in GET /messages response"
fi

db_row="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT id,sender_id,recipient_id,ciphertext,created_at FROM messages WHERE id = '${MSGID}';")"
if [[ -z "${db_row}" ]]; then
  fail "message row not found in DB for ${MSGID}"
fi

if grep -F -- "${SENTINEL}" <<<"${db_row}" >/dev/null 2>&1; then
  fail "sentinel plaintext appeared in messages DB row"
fi

if strings "${DB_PATH}" | grep -F -- "${SENTINEL}" >/dev/null 2>&1; then
  fail "sentinel plaintext appeared in raw DB strings"
fi

stored_ciphertext="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT ciphertext FROM messages WHERE id = '${MSGID}';")"
if [[ "${stored_ciphertext}" != "${WIRE_CIPHERTEXT}" ]]; then
  fail "stored ciphertext did not equal captured wire ciphertext"
fi

echo "task-3 verify: checking message/device key schemas"
message_columns="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT name FROM pragma_table_info('messages') ORDER BY cid;")"
expected_message_columns="id
sender_id
recipient_id
ciphertext
created_at"
if [[ "${message_columns}" != "${expected_message_columns}" ]]; then
  fail "messages table columns were not exactly routing metadata plus ciphertext"
fi

device_key_columns="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT name FROM pragma_table_info('device_keys') ORDER BY cid;")"
expected_device_key_columns="user_id
x25519_public_key
key_signature
created_at"
if [[ "${device_key_columns}" != "${expected_device_key_columns}" ]]; then
  fail "device_keys table columns were not exactly the signed prekey schema"
fi

bad_columns="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT name FROM pragma_table_info('messages') WHERE lower(name) IN ('plaintext','body','text','content','message','cleartext','private','secret') UNION ALL SELECT name FROM pragma_table_info('device_keys') WHERE lower(name) IN ('plaintext','body','text','content','message','cleartext','private','secret');")"
if [[ -n "${bad_columns}" ]]; then
  fail "plaintext-style column name found: ${bad_columns}"
fi

echo "task-3 verify: PASS"
