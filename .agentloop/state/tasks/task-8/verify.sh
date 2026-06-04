#!/usr/bin/env bash
set -euo pipefail

SERVER_PID=""
DB_PATH=""
SERVER_LOG=""
TMP_DIR=""

fail() {
  echo "task-8 verify: FAIL"
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
      kill -9 "${SERVER_PID}" >/dev/null 2>&1 || true
    fi
    wait "${SERVER_PID}" >/dev/null 2>&1 || true
  fi

  [[ -n "${DB_PATH}" ]] && rm -f "${DB_PATH}"
  [[ -n "${SERVER_LOG}" ]] && rm -f "${SERVER_LOG}"
  [[ -n "${TMP_DIR}" ]] && rm -rf "${TMP_DIR}"
  return 0
}

trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
MAC_APP_DIR="${REPO_ROOT}/mac-app"

for required in curl jq sqlite3 swift cargo; do
  if ! command -v "${required}" >/dev/null 2>&1; then
    fail "${required} is required"
  fi
done

echo "task-8 verify: building and testing backend"
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
  "messages_history_returns_same_second_messages_in_send_order"
  "group_message_history_returns_same_second_messages_in_send_order"
  "messages_inbox_delivers_same_second_messages_in_send_order"
  "messages_inbox_is_scoped_to_recipient_inbound_messages_only"
  "messages_inbox_since_cursor_returns_only_later_rows_and_advances"
  "messages_inbox_requires_bearer_token"
  "messages_inbox_empty_for_caller_with_no_inbound_messages"
  "conversations_requires_bearer_token"
  "conversations_lists_distinct_peers_ordered_by_recent_activity"
  "conversations_scope_excludes_unrelated_pairs_and_names_the_peer"
  "conversations_include_inbound_only_peer_started_while_viewer_was_offline"
  "group_list_returns_all_member_groups_in_rowid_order"
  "conversations_empty_for_user_with_no_messages"
)

for test_name in "${required_rust_tests[@]}"; do
  if ! grep -Eq "test ${test_name} \\.\\.\\. ok" <<<"${cargo_output}"; then
    fail "backend acceptance test did not execute and pass: ${test_name}"
  fi
done

TMP_DIR="$(mktemp -d -t task-8-proof.XXXXXX)"
DB_PATH="$(mktemp -t task-8-db.XXXXXX)"
SERVER_LOG="$(mktemp -t task-8-server-log.XXXXXX)"
PORT="${TASK_8_PORT:-$((44000 + ($$ % 10000)))}"
BASE_URL="http://127.0.0.1:${PORT}"

cat >"${TMP_DIR}/ed25519.swift" <<'SWIFT'
import CryptoKit
import Foundation

let args = CommandLine.arguments
func b64(_ data: Data) -> String { data.base64EncodedString() }
func data(_ value: String) -> Data { Data(base64Encoded: value)! }

switch args[1] {
case "identity":
    let key = Curve25519.Signing.PrivateKey()
    print("\(b64(key.rawRepresentation)) \(b64(key.publicKey.rawRepresentation))")
case "sign":
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: data(args[2]))
    print(b64(try key.signature(for: data(args[3]))))
default:
    fatalError("unknown mode")
}
SWIFT

swift_helper() {
  swift "${TMP_DIR}/ed25519.swift" "$@"
}

http_json() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local token="${4:-}"
  local output="${TMP_DIR}/response.json"
  local status

  if [[ -n "${token}" ]]; then
    status="$(curl -sS --max-time 8 -o "${output}" -w '%{http_code}' \
      -X "${method}" \
      -H "Authorization: Bearer ${token}" \
      -H "Content-Type: application/json" \
      --data "${body}" \
      "${BASE_URL}${path}")" || return 1
  elif [[ -n "${body}" ]]; then
    status="$(curl -sS --max-time 8 -o "${output}" -w '%{http_code}' \
      -X "${method}" \
      -H "Content-Type: application/json" \
      --data "${body}" \
      "${BASE_URL}${path}")" || return 1
  else
    status="$(curl -sS --max-time 8 -o "${output}" -w '%{http_code}' \
      -X "${method}" \
      "${BASE_URL}${path}")" || return 1
  fi

  printf '%s\n' "${status}"
}

register_and_sign_in() {
  local username="$1"
  local prefix="$2"
  local identity private_key public_key status challenge_id nonce signature token user_id

  identity="$(swift_helper identity)"
  private_key="${identity%% *}"
  public_key="${identity##* }"

  status="$(http_json POST /register "$(jq -cn --arg u "${username}" --arg p "${public_key}" '{username:$u, identity_public_key:$p}')")"
  [[ "${status}" == "201" ]] || fail "register ${username} returned ${status}: $(cat "${TMP_DIR}/response.json")"
  user_id="$(jq -r '.user_id' "${TMP_DIR}/response.json")"

  status="$(http_json POST /auth/challenge "$(jq -cn --arg u "${username}" '{username:$u}')")"
  [[ "${status}" == "201" ]] || fail "auth challenge ${username} returned ${status}: $(cat "${TMP_DIR}/response.json")"
  challenge_id="$(jq -r '.challenge_id' "${TMP_DIR}/response.json")"
  nonce="$(jq -r '.nonce' "${TMP_DIR}/response.json")"
  signature="$(swift_helper sign "${private_key}" "${nonce}")"

  status="$(http_json POST /auth/verify "$(jq -cn --arg c "${challenge_id}" --arg s "${signature}" '{challenge_id:$c, signature:$s}')")"
  [[ "${status}" == "200" ]] || fail "auth verify ${username} returned ${status}: $(cat "${TMP_DIR}/response.json")"
  token="$(jq -r '.token' "${TMP_DIR}/response.json")"

  printf -v "${prefix}_PRIVATE" '%s' "${private_key}"
  printf -v "${prefix}_PUBLIC" '%s' "${public_key}"
  printf -v "${prefix}_TOKEN" '%s' "${token}"
  printf -v "${prefix}_USER_ID" '%s' "${user_id}"
}

echo "task-8 verify: starting backend on ${BASE_URL}"
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

echo "task-8 verify: backend health check returned 200"
export CHATAPP_LIVE_BACKEND_URL="${BASE_URL}"
export CHATAPP_OFFLINE_MESSAGE_IDS_OUT="${TMP_DIR}/live-message-ids.txt"
export CHATAPP_OFFLINE_PLAINTEXTS_OUT="${TMP_DIR}/live-plaintexts.txt"

echo "task-8 verify: building and testing Swift app with live offline E2E"
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

if ! grep -q "testOfflineRecipientReceivesQueuedMessagesInOrderAndRestartReloadsHistory.*passed" <<<"${swift_output}"; then
  fail "LiveOfflineDeliveryE2ETests did not execute and pass"
fi

if grep -q "testOfflineRecipientReceivesQueuedMessagesInOrderAndRestartReloadsHistory.*skipped" <<<"${swift_output}"; then
  fail "LiveOfflineDeliveryE2ETests skipped even though CHATAPP_LIVE_BACKEND_URL was set"
fi

[[ -s "${CHATAPP_OFFLINE_MESSAGE_IDS_OUT}" ]] || fail "live offline message-id artifact was not written"
[[ -s "${CHATAPP_OFFLINE_PLAINTEXTS_OUT}" ]] || fail "live offline plaintext artifact was not written"

echo "task-8 verify: curl ordered-delivery proof"
suffix="$(date +%s)_$$"
register_and_sign_in "proof_alice_${suffix}" ALICE
register_and_sign_in "proof_bob_${suffix}" BOB

BOB_X25519_PUBLIC="$(openssl rand -base64 32)"
BOB_PREKEY_SIGNATURE="$(swift_helper sign "${BOB_PRIVATE}" "${BOB_X25519_PUBLIC}")"
status="$(http_json PUT /keys "$(jq -cn --arg x "${BOB_X25519_PUBLIC}" --arg s "${BOB_PREKEY_SIGNATURE}" '{x25519_public_key:$x, key_signature:$s}')" "${BOB_TOKEN}")"
[[ "${status}" == "200" || "${status}" == "201" ]] || fail "bob prekey publish returned ${status}: $(cat "${TMP_DIR}/response.json")"

status="$(http_json GET "/messages/inbox?since=0" "" "${BOB_TOKEN}")"
[[ "${status}" == "200" ]] || fail "starting inbox cursor returned ${status}: $(cat "${TMP_DIR}/response.json")"
start_cursor="$(jq -r '.next_cursor // 0' "${TMP_DIR}/response.json")"

expected_ids="${TMP_DIR}/expected-ids.txt"
inbox_ids="${TMP_DIR}/inbox-ids.txt"
history_ids="${TMP_DIR}/history-ids.txt"
same_second_history_ids="${TMP_DIR}/same-second-history-ids.txt"
shuffled_ids="${TMP_DIR}/shuffled-ids.txt"
: >"${expected_ids}"

for index in 1 2 3 4 5 6; do
  ciphertext="opaque-task-8-ciphertext-${suffix}-${index}"
  status="$(http_json POST /messages "$(jq -cn --arg u "proof_bob_${suffix}" --arg c "${ciphertext}" '{recipient_username:$u, ciphertext:$c}')" "${ALICE_TOKEN}")"
  [[ "${status}" == "201" || "${status}" == "200" ]] || fail "message send ${index} returned ${status}: $(cat "${TMP_DIR}/response.json")"
  jq -r '.message_id' "${TMP_DIR}/response.json" >>"${expected_ids}"
done

status="$(http_json GET "/messages/inbox?since=${start_cursor}" "" "${BOB_TOKEN}")"
[[ "${status}" == "200" ]] || fail "bob inbox returned ${status}: $(cat "${TMP_DIR}/response.json")"
jq -r '.messages[].id' "${TMP_DIR}/response.json" >"${inbox_ids}"

returned_count="$(jq '.messages | length' "${TMP_DIR}/response.json")"
[[ "${returned_count}" == "6" ]] || fail "expected 6 queued inbox messages, got ${returned_count}: $(cat "${TMP_DIR}/response.json")"

if ! diff -u "${expected_ids}" "${inbox_ids}" >/dev/null; then
  echo "expected ids:" >&2
  cat "${expected_ids}" >&2
  echo "inbox ids:" >&2
  cat "${inbox_ids}" >&2
  fail "inbox did not return offline messages in send order"
fi

status="$(http_json GET "/messages?with=proof_alice_${suffix}" "" "${BOB_TOKEN}")"
[[ "${status}" == "200" ]] || fail "bob history returned ${status}: $(cat "${TMP_DIR}/response.json")"
jq -r '.messages[].id' "${TMP_DIR}/response.json" >"${history_ids}"

history_count="$(jq '.messages | length' "${TMP_DIR}/response.json")"
[[ "${history_count}" == "6" ]] || fail "expected 6 queued history messages, got ${history_count}: $(cat "${TMP_DIR}/response.json")"

if ! diff -u "${expected_ids}" "${history_ids}" >/dev/null; then
  echo "expected ids:" >&2
  cat "${expected_ids}" >&2
  echo "history ids:" >&2
  cat "${history_ids}" >&2
  fail "history endpoint did not return offline messages in send order"
fi

awk '{ lines[NR] = $0 } END { for (i = NR; i >= 1; i--) print lines[i] }' "${expected_ids}" >"${shuffled_ids}"
if diff -u "${shuffled_ids}" "${inbox_ids}" >/dev/null; then
  fail "negative control unexpectedly passed against shuffled inbox expectation"
fi
if diff -u "${shuffled_ids}" "${history_ids}" >/dev/null; then
  fail "negative control unexpectedly passed against shuffled history expectation"
fi

while IFS= read -r message_id; do
  sqlite3 -batch "${DB_PATH}" \
    "UPDATE messages SET created_at = '2026-06-04T00:00:00Z' WHERE id = '${message_id}';"
done <"${expected_ids}"

status="$(http_json GET "/messages?with=proof_alice_${suffix}" "" "${BOB_TOKEN}")"
[[ "${status}" == "200" ]] || fail "same-second bob history returned ${status}: $(cat "${TMP_DIR}/response.json")"
jq -r '.messages[].id' "${TMP_DIR}/response.json" >"${same_second_history_ids}"
same_second_count="$(jq '.messages | length' "${TMP_DIR}/response.json")"
same_second_timestamp_count="$(jq '[.messages[].created_at] | unique | length' "${TMP_DIR}/response.json")"
[[ "${same_second_count}" == "6" ]] || fail "expected 6 forced same-second history messages, got ${same_second_count}: $(cat "${TMP_DIR}/response.json")"
[[ "${same_second_timestamp_count}" == "1" ]] || fail "forced same-second history batch did not share one timestamp: $(cat "${TMP_DIR}/response.json")"

if ! diff -u "${expected_ids}" "${same_second_history_ids}" >/dev/null; then
  echo "expected ids:" >&2
  cat "${expected_ids}" >&2
  echo "same-second history ids:" >&2
  cat "${same_second_history_ids}" >&2
  fail "history endpoint did not preserve send order for forced same-second messages"
fi
if diff -u "${shuffled_ids}" "${same_second_history_ids}" >/dev/null; then
  fail "negative control unexpectedly passed against forced same-second history"
fi

schema_columns="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT group_concat(name, ',') FROM pragma_table_info('messages') ORDER BY cid;")"
if [[ "${schema_columns}" != "id,sender_id,recipient_id,ciphertext,created_at" ]]; then
  fail "messages schema drifted: ${schema_columns}"
fi

device_key_columns="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT group_concat(name, ',') FROM pragma_table_info('device_keys') ORDER BY cid;")"
if [[ "${device_key_columns}" != "user_id,x25519_public_key,key_signature,created_at" ]]; then
  fail "device_keys schema drifted: ${device_key_columns}"
fi

group_message_columns="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT group_concat(name, ',') FROM pragma_table_info('group_messages') ORDER BY cid;")"
if [[ "${group_message_columns}" != "id,group_id,sender_id,epoch,ciphertext,created_at" ]]; then
  fail "group_messages schema drifted: ${group_message_columns}"
fi

echo "task-8 verify: PASS"
