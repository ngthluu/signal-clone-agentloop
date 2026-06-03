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
  echo "task-4 verify: FAIL"
  echo "reason: $*" >&2
  if [[ -n "${SERVER_LOG}" && -f "${SERVER_LOG}" ]]; then
    echo "server log tail:" >&2
    tail -n 220 "${SERVER_LOG}" >&2 || true
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

sql_quote() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\'}"
}

json_extract_file() {
  local file="$1"
  local path="$2"
  local quoted_file
  quoted_file="$(sql_quote "${file}")"
  sqlite3 -noheader -batch ":memory:" "SELECT json_extract(CAST(readfile(${quoted_file}) AS TEXT), '${path}');" 2>/dev/null || true
}

json_keys_csv_file() {
  local file="$1"
  local quoted_file
  quoted_file="$(sql_quote "${file}")"
  sqlite3 -noheader -batch ":memory:" "SELECT group_concat(key, ',') FROM (SELECT key FROM json_each(CAST(readfile(${quoted_file}) AS TEXT)) ORDER BY key);" 2>/dev/null || true
}

json_key_count_file() {
  local file="$1"
  local quoted_file
  quoted_file="$(sql_quote "${file}")"
  sqlite3 -noheader -batch ":memory:" "SELECT count(*) FROM json_each(CAST(readfile(${quoted_file}) AS TEXT));" 2>/dev/null || true
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

for required_cmd in curl sqlite3 strings; do
  if ! command -v "${required_cmd}" >/dev/null 2>&1; then
    fail "${required_cmd} is required"
  fi
done

echo "task-4 verify: STEP A backend build and tests"
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
  "zk_relay_audit_passes_for_ciphertext_only_schema"
  "zk_relay_audit_fails_when_plaintext_column_exists"
  "messages_post_stores_exactly_the_ciphertext_blob"
  "messages_table_stores_no_plaintext_columns"
)

for test_name in "${required_rust_tests[@]}"; do
  if ! grep -Eq "test ${test_name} \\.\\.\\. ok" <<<"${cargo_output}"; then
    fail "backend acceptance test did not execute and pass: ${test_name}"
  fi
done

DB_PATH="$(mktemp -t task-4-dm-db.XXXXXX)"
SERVER_LOG="$(mktemp -t task-4-server-log.XXXXXX)"
SENTINEL_OUT="$(mktemp -t task-4-sentinel.XXXXXX)"
WIRE_OUT="$(mktemp -t task-4-wire.XXXXXX)"
MSGID_OUT="$(mktemp -t task-4-message-id.XXXXXX)"
TOKEN_OUT="$(mktemp -t task-4-token.XXXXXX)"
PORT="${TASK_4_PORT:-$((44000 + ($$ % 10000)))}"
BASE_URL="http://127.0.0.1:${PORT}"

echo "task-4 verify: STEP B starting backend on ${BASE_URL}"
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

echo "task-4 verify: backend health check returned 200"
export CHATAPP_LIVE_BACKEND_URL="${BASE_URL}"
export CHATAPP_DM_SENTINEL_OUT="${SENTINEL_OUT}"
export CHATAPP_DM_WIRE_OUT="${WIRE_OUT}"
export CHATAPP_DM_MSGID_OUT="${MSGID_OUT}"
export CHATAPP_DM_TOKEN_OUT="${TOKEN_OUT}"

echo "task-4 verify: STEP C live encrypted DM known-sentinel test"
swift_output="$(
  cd "${MAC_APP_DIR}"
  swift build 2>&1
  swift test 2>&1
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

if ! grep -q "testLiveEncryptedDirectMessageRoundTripStoresOnlyCiphertext.*passed" <<<"${swift_output}"; then
  fail "known-sentinel live DM test did not execute and pass"
fi

if grep -q "testLiveEncryptedDirectMessageRoundTripStoresOnlyCiphertext.*skipped" <<<"${swift_output}"; then
  fail "known-sentinel live DM test skipped even though CHATAPP_LIVE_BACKEND_URL was set"
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

for artifact in "${SENTINEL_OUT}" "${WIRE_OUT}" "${MSGID_OUT}" "${TOKEN_OUT}"; do
  if [[ ! -s "${artifact}" ]]; then
    fail "live DM proof artifact was not written: ${artifact}"
  fi
done

echo "task-4 verify: STEP D schema audit"
audit_output="$(bash "${BACKEND_DIR}/scripts/zk_relay_audit.sh" "${DB_PATH}" 2>&1)" || {
  printf '%s\n' "${audit_output}"
  fail "zero-knowledge schema audit failed"
}
printf '%s\n' "${audit_output}"

if ! grep -q "ZERO-KNOWLEDGE SCHEMA AUDIT: PASS" <<<"${audit_output}"; then
  fail "zero-knowledge schema audit did not print the PASS line"
fi

echo "task-4 verify: STEP E sentinel absent from storage, wire, and history"
SENTINEL="$(cat "${SENTINEL_OUT}")"
MSGID="$(cat "${MSGID_OUT}")"
TOKEN="$(cat "${TOKEN_OUT}")"
WIRE_JSON="$(cat "${WIRE_OUT}")"

if [[ -z "${SENTINEL}" || -z "${MSGID}" || -z "${TOKEN}" || -z "${WIRE_JSON}" ]]; then
  fail "live DM proof artifacts must not be empty"
fi

quoted_msgid="$(sql_quote "${MSGID}")"
SENDER="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT u.username FROM messages m JOIN users u ON u.id=m.sender_id WHERE m.id=${quoted_msgid};")"
if [[ -z "${SENDER}" ]]; then
  fail "could not resolve sender username for message ${MSGID}"
fi

db_row="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT id,sender_id,recipient_id,ciphertext,created_at FROM messages WHERE id=${quoted_msgid};")"
if [[ -z "${db_row}" ]]; then
  fail "message row not found in DB for ${MSGID}"
fi

if grep -F -- "${SENTINEL}" <<<"${db_row}" >/dev/null 2>&1; then
  fail "sentinel plaintext appeared in messages DB row"
fi

if strings "${DB_PATH}" | grep -F -- "${SENTINEL}" >/dev/null 2>&1; then
  fail "sentinel plaintext appeared in raw DB bytes"
fi

if grep -F -- "${SENTINEL}" "${WIRE_OUT}" >/dev/null 2>&1; then
  fail "sentinel plaintext appeared in captured wire payload"
fi

history_response="$(curl -sS --max-time 5 -H "Authorization: Bearer ${TOKEN}" "${BASE_URL}/messages?with=${SENDER}")" || {
  fail "GET /messages history request failed"
}

if grep -F -- "${SENTINEL}" <<<"${history_response}" >/dev/null 2>&1; then
  fail "sentinel plaintext appeared in GET /messages response"
fi

WIRE_CIPHERTEXT="$(json_extract_file "${WIRE_OUT}" '$.ciphertext')"
if [[ -z "${WIRE_CIPHERTEXT}" ]]; then
  WIRE_CIPHERTEXT="$(sed -n 's/.*"ciphertext":"\([^"]*\)".*/\1/p' "${WIRE_OUT}")"
fi
if [[ -z "${WIRE_CIPHERTEXT}" ]]; then
  fail "could not extract ciphertext from captured wire payload"
fi

stored_ciphertext="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT ciphertext FROM messages WHERE id=${quoted_msgid};")"
if [[ "${stored_ciphertext}" != "${WIRE_CIPHERTEXT}" ]]; then
  fail "stored ciphertext did not equal captured wire ciphertext"
fi

echo "task-4 verify: STEP F server log audit"
if grep -F -- "${SENTINEL}" "${SERVER_LOG}" >/dev/null 2>&1; then
  fail "sentinel plaintext appeared in captured server log"
fi

if grep -Eiq 'BEGIN .*PRIVATE KEY|x25519_private|identity_private|private_key' "${SERVER_LOG}"; then
  fail "private-key marker appeared in captured server log"
fi

log_bytes="$(wc -c <"${SERVER_LOG}" | tr -d '[:space:]')"
echo "task-4 verify: server log bytes=${log_bytes}"
echo "task-4 verify: server log head sample:"
sed -n '1,20p' "${SERVER_LOG}" || true

echo "task-4 verify: STEP G public-key-only and private-key audit"
wire_keys="$(json_keys_csv_file "${WIRE_OUT}")"
wire_key_count="$(json_key_count_file "${WIRE_OUT}")"
if [[ "${wire_keys}" != "ciphertext,recipient_username" || "${wire_key_count}" != "2" ]]; then
  fail "captured wire JSON keys were not exactly ciphertext,recipient_username; got keys=${wire_keys:-<none>} count=${wire_key_count:-<none>}"
fi

if grep -Eiq '"(plaintext|body|text|content|message|cleartext|private|secret|private_key|secret_key|x25519_private|identity_private)"[[:space:]]*:' "${WIRE_OUT}"; then
  fail "captured wire JSON included plaintext or key-material field"
fi

KEYS_JSON="$(mktemp -t task-4-keys-json.XXXXXX)"
keys_cleanup="${KEYS_JSON}"
key_response="$(curl -sS --max-time 5 "${BASE_URL}/keys/${SENDER}")" || {
  rm -f "${keys_cleanup}"
  fail "GET /keys/${SENDER} request failed"
}
printf '%s' "${key_response}" >"${KEYS_JSON}"

keys_keys="$(json_keys_csv_file "${KEYS_JSON}")"
keys_key_count="$(json_key_count_file "${KEYS_JSON}")"
if [[ "${keys_keys}" != "identity_public_key,key_signature,user_id,username,x25519_public_key" || "${keys_key_count}" != "5" ]]; then
  rm -f "${KEYS_JSON}"
  fail "GET /keys response keys were not exactly public fields; got keys=${keys_keys:-<none>} count=${keys_key_count:-<none>}"
fi

endpoint_x25519="$(json_extract_file "${KEYS_JSON}" '$.x25519_public_key')"
rm -f "${KEYS_JSON}"
if [[ -z "${endpoint_x25519}" ]]; then
  fail "could not extract x25519_public_key from GET /keys response"
fi

quoted_sender="$(sql_quote "${SENDER}")"
stored_x25519="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT x25519_public_key FROM device_keys WHERE user_id=(SELECT id FROM users WHERE username=${quoted_sender});")"
if [[ -z "${stored_x25519}" ]]; then
  fail "stored sender x25519 public prekey not found"
fi

if [[ "${stored_x25519}" != "${endpoint_x25519}" ]]; then
  fail "stored x25519 public prekey did not equal GET /keys public value"
fi

echo "task-4 verify: PASS"
