#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

BACKEND_PID=""
DB_PATH=""
SERVER_LOG=""
BACKEND_BUILD_LOG=""
BACKEND_TEST_LOG=""
SWIFT_LOGS=()
LIVE_LOG=""
SENTINEL_OUT=""
WIRE_OUT=""
MSGID_OUT=""
GROUP_ID_OUT=""
TOKEN_OUT=""
LATE_MEMBER_OUT=""
HISTORY_OUT=""

cleanup() {
  if [[ -n "${BACKEND_PID}" ]] && kill -0 "${BACKEND_PID}" 2>/dev/null; then
    kill -TERM "${BACKEND_PID}" 2>/dev/null || true
    wait "${BACKEND_PID}" 2>/dev/null || true
    if kill -0 "${BACKEND_PID}" 2>/dev/null; then
      kill -KILL "${BACKEND_PID}" 2>/dev/null || true
      wait "${BACKEND_PID}" 2>/dev/null || true
    fi
  fi

  rm -f \
    "${DB_PATH}" \
    "${SERVER_LOG}" \
    "${BACKEND_BUILD_LOG}" \
    "${BACKEND_TEST_LOG}" \
    "${LIVE_LOG}" \
    "${SENTINEL_OUT}" \
    "${WIRE_OUT}" \
    "${MSGID_OUT}" \
    "${GROUP_ID_OUT}" \
    "${TOKEN_OUT}" \
    "${LATE_MEMBER_OUT}" \
    "${HISTORY_OUT}"

  if [[ "${#SWIFT_LOGS[@]}" -gt 0 ]]; then
    rm -f "${SWIFT_LOGS[@]}"
  fi
}
trap cleanup EXIT

fail() {
  echo "task-5 verify: FAIL"
  if [[ -n "${SERVER_LOG}" && -f "${SERVER_LOG}" ]]; then
    echo "----- backend server log -----"
    cat "${SERVER_LOG}"
    echo "----- end backend server log -----"
  fi
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail
}

require_non_empty() {
  [[ -s "$1" ]] || fail
}

require_contains() {
  local file="$1"
  local pattern="$2"
  grep -Eq "${pattern}" "${file}" || fail
}

require_not_contains() {
  local file="$1"
  local pattern="$2"
  if grep -Eq "${pattern}" "${file}"; then
    fail
  fi
}

run_and_capture() {
  local output_file="$1"
  shift
  "$@" >"${output_file}" 2>&1 || {
    cat "${output_file}"
    fail
  }
  cat "${output_file}"
}

preflight() {
  command -v curl >/dev/null 2>&1 || fail
  command -v sqlite3 >/dev/null 2>&1 || fail
  require_file "${REPO_ROOT}/backend/Cargo.toml"
  require_file "${REPO_ROOT}/mac-app/Package.swift"
}

assert_backend_group_tests() {
  require_contains "${BACKEND_TEST_LOG}" "test result: ok\\..*0 failed"
  require_not_contains "${BACKEND_TEST_LOG}" "error\\["

  local tests=(
    group_create_persists_name_membership_and_epoch_zero_keys
    group_create_requires_bearer_token
    group_list_returns_all_member_groups_in_rowid_order
    group_endpoints_reject_non_members_with_403
    group_stream_requires_bearer_token
    group_stream_with_member_returns_sse_headers
    group_add_member_broadcasts_epoch_event_to_members
    group_message_post_stores_exactly_the_ciphertext_blob
    group_message_history_returns_only_ciphertext_for_members
    group_message_history_returns_same_second_messages_in_send_order
    group_add_member_bumps_epoch_and_blocks_prior_epoch_keys
    group_tables_store_no_plaintext_columns
  )

  local test_name
  for test_name in "${tests[@]}"; do
    require_contains "${BACKEND_TEST_LOG}" "test ${test_name} \\.\\.\\. ok"
  done
}

run_swift_suite() {
  local suite="$1"
  local expected_count="$2"
  local output_file
  output_file="$(mktemp)"
  SWIFT_LOGS+=("${output_file}")

  echo "swift test --filter ChatAppTests.${suite}"
  (
    cd "${REPO_ROOT}/mac-app"
    swift test --filter "ChatAppTests.${suite}"
  ) >"${output_file}" 2>&1 || {
    cat "${output_file}"
    fail
  }
  cat "${output_file}"

  require_contains "${output_file}" "Test Suite '${suite}' passed"
  require_contains "${output_file}" "Executed ${expected_count} tests, with 0 failures"
}

start_backend() {
  PORT="${TASK_5_R1_PORT:-$((45000 + ($$ % 10000)))}"
  export PORT

  echo "Starting backend on ${PORT}"
  (
    cd "${REPO_ROOT}/backend"
    cargo run -- --db-path "${DB_PATH}" --port "${PORT}"
  ) >"${SERVER_LOG}" 2>&1 &
  BACKEND_PID="$!"

  local deadline=$((SECONDS + 60))
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    if ! kill -0 "${BACKEND_PID}" 2>/dev/null; then
      fail
    fi
    if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
      return
    fi
    sleep 0.5
  done

  fail
}

run_live_scoped_test() {
  export CHATAPP_LIVE_BACKEND_URL="http://127.0.0.1:${PORT}"
  export CHATAPP_GROUP_SENTINEL_OUT="${SENTINEL_OUT}"
  export CHATAPP_GROUP_WIRE_OUT="${WIRE_OUT}"
  export CHATAPP_GROUP_MSGID_OUT="${MSGID_OUT}"
  export CHATAPP_GROUP_ID_OUT="${GROUP_ID_OUT}"
  export CHATAPP_GROUP_TOKEN_OUT="${TOKEN_OUT}"
  export CHATAPP_GROUP_LATE_MEMBER_OUT="${LATE_MEMBER_OUT}"

  echo "swift test --filter testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages"
  (
    cd "${REPO_ROOT}/mac-app"
    swift test --filter testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages
  ) >"${LIVE_LOG}" 2>&1 || {
    cat "${LIVE_LOG}"
    fail
  }
  cat "${LIVE_LOG}"

  require_contains "${LIVE_LOG}" "Executed 1 test"
  require_contains "${LIVE_LOG}" "with 0 failures"
  require_not_contains "${LIVE_LOG}" "skipped"
  require_not_contains "${LIVE_LOG}" "testLiveCoordinatorCreatesGroupAndPeerReceivesDecryptedMessage"
  require_not_contains "${LIVE_LOG}" "testLiveGroupAllThreeMembersSendAndReceiveThroughCoordinators"
  require_not_contains "${LIVE_LOG}" "testLiveGroupExistingMembersKeepReceivingAfterAddWhileNewMemberExcluded"
}

extract_wire_ciphertext() {
  local value
  value="$(sqlite3 ':memory:' "SELECT json_extract(readfile('${WIRE_OUT}'), '$.ciphertext');" 2>/dev/null || true)"
  if [[ -z "${value}" ]]; then
    value="$(sed -nE 's/.*"ciphertext"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "${WIRE_OUT}" | head -n 1)"
  fi
  [[ -n "${value}" ]] || fail
  printf '%s' "${value}"
}

assert_ciphertext_proofs() {
  require_non_empty "${SENTINEL_OUT}"
  require_non_empty "${WIRE_OUT}"
  require_non_empty "${MSGID_OUT}"
  require_non_empty "${GROUP_ID_OUT}"
  require_non_empty "${TOKEN_OUT}"
  require_non_empty "${LATE_MEMBER_OUT}"

  local sentinel
  local message_id
  local group_id
  local token
  sentinel="$(cat "${SENTINEL_OUT}")"
  message_id="$(cat "${MSGID_OUT}")"
  group_id="$(cat "${GROUP_ID_OUT}")"
  token="$(cat "${TOKEN_OUT}")"

  if grep -Fq "${sentinel}" "${WIRE_OUT}"; then
    fail
  fi

  local wire_ciphertext
  local stored_ciphertext
  wire_ciphertext="$(extract_wire_ciphertext)"
  stored_ciphertext="$(sqlite3 "${DB_PATH}" "SELECT ciphertext FROM group_messages WHERE id = '${message_id}' AND group_id = '${group_id}';")"
  [[ -n "${stored_ciphertext}" ]] || fail
  [[ "${stored_ciphertext}" == "${wire_ciphertext}" ]] || fail

  curl -fsS \
    -H "Authorization: Bearer ${token}" \
    "http://127.0.0.1:${PORT}/groups/${group_id}/messages" >"${HISTORY_OUT}" || fail
  require_non_empty "${HISTORY_OUT}"

  if grep -Fq "${sentinel}" "${HISTORY_OUT}"; then
    fail
  fi

  local db_row
  db_row="$(sqlite3 "${DB_PATH}" "SELECT id || '|' || group_id || '|' || sender_id || '|' || epoch || '|' || ciphertext || '|' || created_at FROM group_messages WHERE id = '${message_id}';")"
  [[ -n "${db_row}" ]] || fail
  if grep -Fq "${sentinel}" <<<"${db_row}"; then
    fail
  fi

  if strings "${DB_PATH}" | grep -Fq "${sentinel}"; then
    fail
  fi
}

assert_late_member_proofs() {
  local group_id
  local late_member
  local epoch_zero_keys
  local joined_epoch
  group_id="$(cat "${GROUP_ID_OUT}")"
  late_member="$(cat "${LATE_MEMBER_OUT}")"

  epoch_zero_keys="$(
    sqlite3 "${DB_PATH}" \
      "SELECT COUNT(*)
       FROM group_keys
       JOIN users ON users.id = group_keys.member_id
       WHERE group_keys.group_id = '${group_id}'
         AND group_keys.epoch = 0
         AND users.username = '${late_member}';"
  )"
  [[ "${epoch_zero_keys}" == "0" ]] || fail

  joined_epoch="$(
    sqlite3 "${DB_PATH}" \
      "SELECT group_members.joined_epoch
       FROM group_members
       JOIN users ON users.id = group_members.user_id
       WHERE group_members.group_id = '${group_id}'
         AND users.username = '${late_member}';"
  )"
  [[ "${joined_epoch}" == "1" ]] || fail
}

assert_schema_proofs() {
  local bad_columns
  bad_columns="$(
    sqlite3 "${DB_PATH}" \
      "SELECT name
       FROM pragma_table_info('group_messages')
       WHERE lower(name) IN ('plaintext','body','text','content','message','cleartext','private','secret')
       UNION ALL
       SELECT name
       FROM pragma_table_info('group_keys')
       WHERE lower(name) IN ('plaintext','body','text','content','message','cleartext','private','secret');"
  )"
  [[ -z "${bad_columns}" ]] || fail

  local message_ciphertext_count
  local key_wrapped_count
  message_ciphertext_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM pragma_table_info('group_messages') WHERE name = 'ciphertext';")"
  key_wrapped_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM pragma_table_info('group_keys') WHERE name = 'wrapped_key';")"
  [[ "${message_ciphertext_count}" == "1" ]] || fail
  [[ "${key_wrapped_count}" == "1" ]] || fail
}

preflight

DB_PATH="$(mktemp)"
SERVER_LOG="$(mktemp)"
BACKEND_BUILD_LOG="$(mktemp)"
BACKEND_TEST_LOG="$(mktemp)"
LIVE_LOG="$(mktemp)"
SENTINEL_OUT="$(mktemp)"
WIRE_OUT="$(mktemp)"
MSGID_OUT="$(mktemp)"
GROUP_ID_OUT="$(mktemp)"
TOKEN_OUT="$(mktemp)"
LATE_MEMBER_OUT="$(mktemp)"
HISTORY_OUT="$(mktemp)"

bash "${REPO_ROOT}/backend/scripts/reap_stale_backends.sh"

echo "cargo build"
run_and_capture "${BACKEND_BUILD_LOG}" bash -c "cd '${REPO_ROOT}/backend' && cargo build"
require_not_contains "${BACKEND_BUILD_LOG}" "error\\["

echo "cargo test"
run_and_capture "${BACKEND_TEST_LOG}" bash -c "cd '${REPO_ROOT}/backend' && cargo test"
assert_backend_group_tests

run_swift_suite GroupCoordinatorTests 20
run_swift_suite GroupCryptoTests 9
run_swift_suite GroupEnvelopeTests 7
run_swift_suite HTTPGroupServiceTests 7

start_backend
run_live_scoped_test
assert_ciphertext_proofs
assert_late_member_proofs
assert_schema_proofs

echo "task-5 verify: PASS"
exit 0
