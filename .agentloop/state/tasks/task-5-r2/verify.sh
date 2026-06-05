#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
MAC_APP_DIR="${REPO_ROOT}/mac-app"
ARTIFACT_DIR="${SCRIPT_DIR}/artifacts"

SERVER_PID=""
SERVER_LOG=""
DB_PATH=""
LIVE_LOG=""
BACKEND_LOGS=()
SWIFT_LOGS=()
PORT=""
GROUP_ID_OUT=""
MEMBER_TOKEN_OUT=""
NON_MEMBER_TOKEN_OUT=""
SENTINEL_OUT=""
MESSAGE_ID_OUT=""
CIPHERTEXT_OUT=""

fail() {
  echo "task-5-r2 verify: FAIL"
  echo "reason: $*" >&2
  if [[ -n "${SERVER_LOG}" && -f "${SERVER_LOG}" ]]; then
    echo "----- backend server log -----" >&2
    tail -n 220 "${SERVER_LOG}" >&2 || true
    echo "----- end backend server log -----" >&2
  fi
  exit 1
}

cleanup_db() {
  local path="$1"
  [[ -z "${path}" ]] && return 0
  rm -f "${path}" "${path}-wal" "${path}-shm"
}

cleanup() {
  if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
    kill -TERM "${SERVER_PID}" >/dev/null 2>&1 || true
    wait "${SERVER_PID}" >/dev/null 2>&1 || true
    for _ in {1..30}; do
      kill -0 "${SERVER_PID}" >/dev/null 2>&1 || break
      sleep 0.1
    done
    if kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
      kill -KILL "${SERVER_PID}" >/dev/null 2>&1 || true
      wait "${SERVER_PID}" >/dev/null 2>&1 || true
    fi
  fi

  if [[ -n "${DB_PATH}" ]]; then
    pkill -TERM -f -- "--db-path ${DB_PATH}" >/dev/null 2>&1 || true
    for _ in {1..20}; do
      pgrep -f -- "--db-path ${DB_PATH}" >/dev/null 2>&1 || break
      sleep 0.1
    done
    pkill -KILL -f -- "--db-path ${DB_PATH}" >/dev/null 2>&1 || true
    cleanup_db "${DB_PATH}"
  fi
}
trap cleanup EXIT

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required"
}

require_file() {
  [[ -f "$1" ]] || fail "missing required file: $1"
}

require_non_empty_file() {
  [[ -s "$1" ]] || fail "missing or empty artifact: $1"
}

require_grep() {
  local pattern="$1"
  local file="$2"
  grep -Eq "${pattern}" "${file}" || fail "expected pattern not found in ${file}: ${pattern}"
}

reject_grep() {
  local pattern="$1"
  local file="$2"
  if grep -Eq "${pattern}" "${file}"; then
    fail "rejected pattern found in ${file}: ${pattern}"
  fi
}

sql_quote() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\'}"
}

self_guard() {
  local script_file="${BASH_SOURCE[0]}"
  local forbidden_agentloop
  local forbidden_root
  forbidden_agentloop=".agentloop/""verify.""sh"
  forbidden_root="${REPO_ROOT}/""verify.""sh"

  if grep -F "${forbidden_agentloop}" "${script_file}" >/dev/null 2>&1; then
    fail "task gate must not reference the agentloop aggregate gate"
  fi
  if grep -F "${forbidden_root}" "${script_file}" >/dev/null 2>&1; then
    fail "task gate must not reference the repo aggregate gate"
  fi

  while IFS= read -r line; do
    [[ "${line}" == *"--test groups"* && "${line}" == *"-- --exact"* ]] || fail "unscoped backend test command: ${line}"
  done < <(grep -nE 'cargo[[:space:]]+test([[:space:]]|$)' "${script_file}" || true)

  while IFS= read -r line; do
    [[ "${line}" == *"--filter"* ]] || fail "unscoped Swift test command: ${line}"
  done < <(grep -nE 'swift[[:space:]]+test([[:space:]]|$)' "${script_file}" || true)
}

port_is_free() {
  local candidate="$1"
  if (echo >"/dev/tcp/127.0.0.1/${candidate}") >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

pick_port() {
  if [[ -n "${TASK_5_R2_PORT:-}" ]]; then
    port_is_free "${TASK_5_R2_PORT}" || fail "requested TASK_5_R2_PORT is in use: ${TASK_5_R2_PORT}"
    printf '%s\n' "${TASK_5_R2_PORT}"
    return 0
  fi

  local start=$((46000 + ($$ % 10000)))
  local candidate
  for offset in {0..399}; do
    candidate=$((start + offset))
    if ((candidate > 60999)); then
      candidate=$((46000 + (candidate - 61000)))
    fi
    if port_is_free "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  fail "could not find a free port"
}

reap_stale_backends() {
  echo "task-5-r2 verify: reaping stale backends"
  require_file "${BACKEND_DIR}/scripts/reap_stale_backends.sh"
  bash "${BACKEND_DIR}/scripts/reap_stale_backends.sh"
}

run_backend_filter() {
  local filter="$1"
  local log_file="${ARTIFACT_DIR}/backend-${filter}.log"
  BACKEND_LOGS+=("${log_file}")

  echo "task-5-r2 verify: cargo test --test groups ${filter} -- --exact"
  (
    cd "${BACKEND_DIR}"
    cargo test --test groups "${filter}" -- --exact
  ) >"${log_file}" 2>&1 || {
    cat "${log_file}"
    fail "backend filter failed: ${filter}"
  }
  cat "${log_file}"

  require_grep "running 1 test" "${log_file}"
  require_grep "test ${filter} \\.\\.\\. ok" "${log_file}"
  require_grep "test result: ok\\..*1 passed; 0 failed; 0 ignored" "${log_file}"
}

run_swift_filter() {
  local filter="$1"
  local test_name="${filter##*/}"
  local log_file="${ARTIFACT_DIR}/swift-${test_name}.log"
  SWIFT_LOGS+=("${log_file}")

  echo "task-5-r2 verify: swift test --filter ${filter}"
  (
    cd "${MAC_APP_DIR}"
    swift test --filter "${filter}"
  ) >"${log_file}" 2>&1 || {
    cat "${log_file}"
    fail "Swift filter failed: ${filter}"
  }
  cat "${log_file}"

  require_grep "Executed 1 test, with 0 failures" "${log_file}"
  reject_grep "skipped" "${log_file}"
  reject_grep "${test_name}.*failed" "${log_file}"
}

start_live_backend() {
  DB_PATH="${ARTIFACT_DIR}/task-5-r2-live.sqlite3"
  SERVER_LOG="${ARTIFACT_DIR}/task-5-r2-backend.log"
  cleanup_db "${DB_PATH}"
  PORT="$(pick_port)"

  echo "task-5-r2 verify: building backend"
  (
    cd "${BACKEND_DIR}"
    cargo build
  ) >"${ARTIFACT_DIR}/backend-build.log" 2>&1 || {
    cat "${ARTIFACT_DIR}/backend-build.log"
    fail "backend build failed"
  }
  cat "${ARTIFACT_DIR}/backend-build.log"

  echo "task-5-r2 verify: starting live backend on ${PORT}"
  (
    cd "${BACKEND_DIR}"
    cargo run -- --db-path "${DB_PATH}" --port "${PORT}"
  ) >"${SERVER_LOG}" 2>&1 &
  SERVER_PID="$!"

  local deadline=$((SECONDS + 60))
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
      fail "backend exited during startup"
    fi
    if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  fail "backend did not become healthy"
}

run_live_filter() {
  GROUP_ID_OUT="${ARTIFACT_DIR}/group-id.txt"
  MEMBER_TOKEN_OUT="${ARTIFACT_DIR}/member-token.txt"
  NON_MEMBER_TOKEN_OUT="${ARTIFACT_DIR}/non-member-token.txt"
  SENTINEL_OUT="${ARTIFACT_DIR}/sentinel.txt"
  MESSAGE_ID_OUT="${ARTIFACT_DIR}/message-id.txt"
  CIPHERTEXT_OUT="${ARTIFACT_DIR}/ciphertext.txt"
  LIVE_LOG="${ARTIFACT_DIR}/swift-live-coordinator.log"
  rm -f "${GROUP_ID_OUT}" "${MEMBER_TOKEN_OUT}" "${NON_MEMBER_TOKEN_OUT}" "${SENTINEL_OUT}" "${MESSAGE_ID_OUT}" "${CIPHERTEXT_OUT}" "${LIVE_LOG}"

  export CHATAPP_LIVE_BACKEND_URL="http://127.0.0.1:${PORT}"
  export CHATAPP_GROUP_ID_OUT="${GROUP_ID_OUT}"
  export CHATAPP_GROUP_TOKEN_OUT="${MEMBER_TOKEN_OUT}"
  export CHATAPP_GROUP_NON_MEMBER_TOKEN_OUT="${NON_MEMBER_TOKEN_OUT}"
  export CHATAPP_GROUP_SENTINEL_OUT="${SENTINEL_OUT}"
  export CHATAPP_GROUP_MSGID_OUT="${MESSAGE_ID_OUT}"
  export CHATAPP_GROUP_CIPHERTEXT_OUT="${CIPHERTEXT_OUT}"

  echo "task-5-r2 verify: swift test --filter testLiveCoordinatorCreateWithTwoInviteesListsForMembersAndBlocksNonMember"
  (
    cd "${MAC_APP_DIR}"
    swift test --filter testLiveCoordinatorCreateWithTwoInviteesListsForMembersAndBlocksNonMember
  ) >"${LIVE_LOG}" 2>&1 || {
    cat "${LIVE_LOG}"
    fail "live Swift filter failed"
  }
  cat "${LIVE_LOG}"

  require_grep "Executed 1 test, with 0 failures" "${LIVE_LOG}"
  reject_grep "skipped" "${LIVE_LOG}"
  reject_grep "testLiveCoordinatorCreateWithTwoInviteesListsForMembersAndBlocksNonMember.*failed" "${LIVE_LOG}"
}

assert_live_artifacts_and_db() {
  require_non_empty_file "${GROUP_ID_OUT}"
  require_non_empty_file "${MEMBER_TOKEN_OUT}"
  require_non_empty_file "${NON_MEMBER_TOKEN_OUT}"
  require_non_empty_file "${SENTINEL_OUT}"
  require_non_empty_file "${MESSAGE_ID_OUT}"
  require_non_empty_file "${CIPHERTEXT_OUT}"
  require_file "${DB_PATH}"

  local group_id
  local member_token
  local non_member_token
  local sentinel
  local message_id
  local artifact_ciphertext
  group_id="$(cat "${GROUP_ID_OUT}")"
  member_token="$(cat "${MEMBER_TOKEN_OUT}")"
  non_member_token="$(cat "${NON_MEMBER_TOKEN_OUT}")"
  sentinel="$(cat "${SENTINEL_OUT}")"
  message_id="$(cat "${MESSAGE_ID_OUT}")"
  artifact_ciphertext="$(cat "${CIPHERTEXT_OUT}")"

  [[ "${member_token}" != "${non_member_token}" ]] || fail "member and non-member token artifacts match"
  [[ "${artifact_ciphertext}" != *"${sentinel}"* ]] || fail "ciphertext artifact contains plaintext sentinel"

  local groups_cols
  local members_cols
  local keys_cols
  local messages_cols
  groups_cols="$(sqlite3 "${DB_PATH}" "SELECT group_concat(name, ',') FROM pragma_table_info('groups') ORDER BY cid;")"
  members_cols="$(sqlite3 "${DB_PATH}" "SELECT group_concat(name, ',') FROM pragma_table_info('group_members') ORDER BY cid;")"
  keys_cols="$(sqlite3 "${DB_PATH}" "SELECT group_concat(name, ',') FROM pragma_table_info('group_keys') ORDER BY cid;")"
  messages_cols="$(sqlite3 "${DB_PATH}" "SELECT group_concat(name, ',') FROM pragma_table_info('group_messages') ORDER BY cid;")"
  [[ "${groups_cols}" == "id,name,creator_id,current_epoch,created_at" ]] || fail "unexpected groups columns: ${groups_cols}"
  [[ "${members_cols}" == "group_id,user_id,joined_epoch,added_at" ]] || fail "unexpected group_members columns: ${members_cols}"
  [[ "${keys_cols}" == "group_id,epoch,member_id,wrapped_key,created_at" ]] || fail "unexpected group_keys columns: ${keys_cols}"
  [[ "${messages_cols}" == "id,group_id,sender_id,epoch,ciphertext,created_at" ]] || fail "unexpected group_messages columns: ${messages_cols}"

  local quoted_group_id
  local quoted_message_id
  quoted_group_id="$(sql_quote "${group_id}")"
  quoted_message_id="$(sql_quote "${message_id}")"

  local group_count
  local member_count
  local key_count
  local message_count
  local stored_ciphertext
  group_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM groups WHERE id = ${quoted_group_id} AND current_epoch = 0;")"
  member_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM group_members WHERE group_id = ${quoted_group_id} AND joined_epoch = 0;")"
  key_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM group_keys WHERE group_id = ${quoted_group_id} AND epoch = 0 AND length(wrapped_key) > 0;")"
  message_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM group_messages WHERE id = ${quoted_message_id} AND group_id = ${quoted_group_id} AND epoch = 0;")"
  stored_ciphertext="$(sqlite3 "${DB_PATH}" "SELECT ciphertext FROM group_messages WHERE id = ${quoted_message_id} AND group_id = ${quoted_group_id};")"
  [[ "${group_count}" == "1" ]] || fail "live group row missing"
  [[ "${member_count}" == "3" ]] || fail "expected 3 epoch-0 members, got ${member_count}"
  [[ "${key_count}" == "3" ]] || fail "expected 3 epoch-0 wrapped keys, got ${key_count}"
  [[ "${message_count}" == "1" ]] || fail "live group message row missing"
  [[ "${stored_ciphertext}" == "${artifact_ciphertext}" ]] || fail "ciphertext artifact does not match DB row"
  [[ "${stored_ciphertext}" != *"${sentinel}"* ]] || fail "stored ciphertext contains plaintext sentinel"

  local forbidden_columns
  forbidden_columns="$(sqlite3 "${DB_PATH}" "SELECT name FROM pragma_table_info('groups') UNION ALL SELECT name FROM pragma_table_info('group_members') UNION ALL SELECT name FROM pragma_table_info('group_keys') UNION ALL SELECT name FROM pragma_table_info('group_messages');" | grep -E '(^|_)(plaintext|cleartext|private|secret|group_key|body|content|message)($|_)' || true)"
  [[ -z "${forbidden_columns}" ]] || fail "forbidden group column names found: ${forbidden_columns}"

  if strings "${DB_PATH}" | grep -F "${sentinel}" >/dev/null 2>&1; then
    fail "SQLite DB contains plaintext sentinel"
  fi

  local member_status
  local non_member_detail_status
  local non_member_keys_status
  member_status="$(curl -sS -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${member_token}" "http://127.0.0.1:${PORT}/groups/${group_id}")"
  non_member_detail_status="$(curl -sS -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${non_member_token}" "http://127.0.0.1:${PORT}/groups/${group_id}")"
  non_member_keys_status="$(curl -sS -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${non_member_token}" "http://127.0.0.1:${PORT}/groups/${group_id}/keys")"
  [[ "${member_status}" == "200" ]] || fail "member detail proof failed with ${member_status}"
  [[ "${non_member_detail_status}" == "403" ]] || fail "non-member detail proof failed with ${non_member_detail_status}"
  [[ "${non_member_keys_status}" == "403" ]] || fail "non-member keys proof failed with ${non_member_keys_status}"
}

main() {
  require_file "${BACKEND_DIR}/Cargo.toml"
  require_file "${MAC_APP_DIR}/Package.swift"
  for cmd in cargo swift curl sqlite3 strings grep pkill pgrep; do
    require_cmd "${cmd}"
  done

  mkdir -p "${ARTIFACT_DIR}"
  self_guard
  reap_stale_backends

  run_backend_filter group_create_requires_creator_plus_two_invited_members
  run_backend_filter group_created_by_signed_in_user_is_listed_for_invited_members_only
  run_backend_filter group_endpoints_reject_non_members_with_403
  run_backend_filter group_records_store_only_metadata_public_material_and_wrapped_key_envelopes

  run_swift_filter ChatAppTests.GroupCoordinatorTests/testCreateGroupRequiresAtLeastTwoInvitedMembers
  run_swift_filter ChatAppTests.GroupCoordinatorTests/testCreateGroupWrapsEpochZeroKeyToCreatorAndTwoInvitees
  run_swift_filter ChatAppTests.GroupCoordinatorTests/testInvitedMemberRefreshGroupsShowsCreatedGroupAndOpenDecryptsHistory
  run_swift_filter ChatAppTests.GroupEnvelopeTests/testCreateGroupRequestEncodesSnakeCaseKeys
  run_swift_filter ChatAppTests.HTTPGroupServiceTests/testCreateGroupPostsMembersWithBearerTokenAndDecodesResponse

  start_live_backend
  run_live_filter
  assert_live_artifacts_and_db

  echo "task-5-r2 verify: PASS"
}

main "$@"
