#!/usr/bin/env bash
set -euo pipefail

SERVER_PID=""
SERVER_LOG=""
DB_PATH=""
SENTINEL_OUT=""
ORIGINAL_FILE_OUT=""
DM_ATTACHMENT_ID_OUT=""
GROUP_ATTACHMENT_ID_OUT=""
BOB_TOKEN_OUT=""
UPLOAD_WIRE_FILE_OUT=""
LIVE_ORIGINAL_FILE_OUT=""
LIVE_DM_DOWNLOAD_OUT=""
LIVE_GROUP_DOWNLOAD_OUT=""
STORED_BLOB=""
DOWNLOADED_BLOB=""

fail() {
  echo "task-7 verify: FAIL"
  echo "reason: $*" >&2
  if [[ -n "${SERVER_LOG}" && -f "${SERVER_LOG}" ]]; then
    echo "server log tail:" >&2
    tail -n 220 "${SERVER_LOG}" >&2 || true
  fi
  exit 1
}

cleanup_file_and_sidecars() {
  local path="$1"
  [[ -z "${path}" ]] && return 0
  rm -f "${path}" "${path}-wal" "${path}-shm"
}

cleanup() {
  if [[ -n "${SERVER_PID}" ]]; then
    if kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
      kill "${SERVER_PID}" >/dev/null 2>&1 || true
      wait "${SERVER_PID}" >/dev/null 2>&1 || true
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

  if [[ -n "${DB_PATH}" ]]; then
    pkill -TERM -f -- "--db-path ${DB_PATH}" >/dev/null 2>&1 || true
    for _ in {1..30}; do
      if ! pgrep -f -- "--db-path ${DB_PATH}" >/dev/null 2>&1; then
        break
      fi
      sleep 0.1
    done
    pkill -KILL -f -- "--db-path ${DB_PATH}" >/dev/null 2>&1 || true
  fi

  local original_file=""
  local upload_wire_file=""
  local live_original_file=""
  local live_dm_download_file=""
  local live_group_download_file=""
  [[ -n "${ORIGINAL_FILE_OUT}" && -f "${ORIGINAL_FILE_OUT}" ]] && original_file="$(cat "${ORIGINAL_FILE_OUT}" 2>/dev/null || true)"
  [[ -n "${UPLOAD_WIRE_FILE_OUT}" && -f "${UPLOAD_WIRE_FILE_OUT}" ]] && upload_wire_file="$(cat "${UPLOAD_WIRE_FILE_OUT}" 2>/dev/null || true)"
  [[ -n "${LIVE_ORIGINAL_FILE_OUT}" && -f "${LIVE_ORIGINAL_FILE_OUT}" ]] && live_original_file="$(cat "${LIVE_ORIGINAL_FILE_OUT}" 2>/dev/null || true)"
  [[ -n "${LIVE_DM_DOWNLOAD_OUT}" && -f "${LIVE_DM_DOWNLOAD_OUT}" ]] && live_dm_download_file="$(cat "${LIVE_DM_DOWNLOAD_OUT}" 2>/dev/null || true)"
  [[ -n "${LIVE_GROUP_DOWNLOAD_OUT}" && -f "${LIVE_GROUP_DOWNLOAD_OUT}" ]] && live_group_download_file="$(cat "${LIVE_GROUP_DOWNLOAD_OUT}" 2>/dev/null || true)"
  [[ -n "${original_file}" ]] && rm -f "${original_file}"
  [[ -n "${original_file}" ]] && rmdir "$(dirname "${original_file}")" >/dev/null 2>&1 || true
  [[ -n "${upload_wire_file}" ]] && rm -f "${upload_wire_file}"
  [[ -n "${live_original_file}" ]] && rm -f "${live_original_file}"
  [[ -n "${live_original_file}" ]] && rmdir "$(dirname "${live_original_file}")" >/dev/null 2>&1 || true
  [[ -n "${live_dm_download_file}" ]] && rm -f "${live_dm_download_file}"
  [[ -n "${live_dm_download_file}" ]] && rmdir "$(dirname "${live_dm_download_file}")" >/dev/null 2>&1 || true
  [[ -n "${live_group_download_file}" ]] && rm -f "${live_group_download_file}"
  [[ -n "${live_group_download_file}" ]] && rmdir "$(dirname "${live_group_download_file}")" >/dev/null 2>&1 || true

  cleanup_file_and_sidecars "${DB_PATH}"
  rm -f "${SERVER_LOG}" \
    "${SENTINEL_OUT}" \
    "${ORIGINAL_FILE_OUT}" \
    "${DM_ATTACHMENT_ID_OUT}" \
    "${GROUP_ATTACHMENT_ID_OUT}" \
    "${BOB_TOKEN_OUT}" \
    "${UPLOAD_WIRE_FILE_OUT}" \
    "${LIVE_ORIGINAL_FILE_OUT}" \
    "${LIVE_DM_DOWNLOAD_OUT}" \
    "${LIVE_GROUP_DOWNLOAD_OUT}" \
    "${STORED_BLOB}" \
    "${DOWNLOADED_BLOB}"
  return 0
}

sql_quote() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\'}"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    fail "${cmd} is required"
  fi
}

require_rust_test_ok() {
  local output="$1"
  local test_name="$2"
  if ! grep -Eq "test ${test_name} \\.\\.\\. ok" <<<"${output}"; then
    fail "backend attachment test did not execute and pass: ${test_name}"
  fi
}

require_swift_test_ok() {
  local output="$1"
  local test_name="$2"
  if grep -q "${test_name}.*failed" <<<"${output}"; then
    fail "acceptance-critical Swift test failed: ${test_name}"
  fi
  if grep -q "${test_name}.*skipped" <<<"${output}"; then
    fail "acceptance-critical Swift test skipped: ${test_name}"
  fi
  if ! grep -q "${test_name}.*passed" <<<"${output}"; then
    fail "acceptance-critical Swift test did not execute and pass: ${test_name}"
  fi
}

require_swift_class_count() {
  local output="$1"
  local class_name="$2"
  local expected_count="$3"
  local class_summary
  class_summary="$(grep -A2 -E "Test Suite '${class_name}' passed|Test Suite '${class_name}' started" <<<"${output}" || true)"
  if ! grep -Eq "Executed ${expected_count} tests, with 0 failures" <<<"${class_summary}"; then
    fail "${class_name} did not execute exactly ${expected_count} tests with 0 failures"
  fi
}

port_is_free() {
  local port="$1"
  if (echo >"/dev/tcp/127.0.0.1/${port}") >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

pick_port() {
  if [[ -n "${TASK_7_R6_PORT:-}" ]]; then
    port_is_free "${TASK_7_R6_PORT}" || fail "requested TASK_7_R6_PORT is already in use: ${TASK_7_R6_PORT}"
    printf '%s\n' "${TASK_7_R6_PORT}"
    return 0
  fi

  local start=$((47000 + ($$ % 10000)))
  local candidate
  for offset in {0..199}; do
    candidate=$((start + offset))
    if ((candidate > 60999)); then
      candidate=$((47000 + (candidate - 61000)))
    fi
    if port_is_free "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  fail "could not find a free port for task-7-r6 backend"
}

trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
MAC_APP_DIR="${REPO_ROOT}/mac-app"

[[ -f "${BACKEND_DIR}/Cargo.toml" ]] || fail "backend Cargo.toml not found at ${BACKEND_DIR}"
[[ -f "${MAC_APP_DIR}/Package.swift" ]] || fail "mac-app Package.swift not found at ${MAC_APP_DIR}"

for cmd in cargo swift curl sqlite3 strings cmp wc pgrep; do
  require_cmd "${cmd}"
done

echo "task-7 verify: reaping stale backend processes"
bash "${BACKEND_DIR}/scripts/reap_stale_backends.sh"

echo "task-7 verify: building backend and running scoped Rust attachment tests"
set +e
cargo_output="$(
  cd "${BACKEND_DIR}" &&
    cargo build 2>&1 &&
    cargo test --test attachments 2>&1
)"
cargo_status=$?
set -e

printf '%s\n' "${cargo_output}"
if [[ "${cargo_status}" -ne 0 ]]; then
  fail "backend cargo build or attachment test failed"
fi
if grep -q "error\\[" <<<"${cargo_output}"; then
  fail "backend cargo output contained a Rust compiler error"
fi
if ! grep -Eq "test result: ok\\..*0 failed" <<<"${cargo_output}"; then
  fail "backend attachment test output did not report 0 failed"
fi

required_rust_tests=(
  "attachment_upload_then_download_round_trips_exact_bytes"
  "attachment_upload_rejects_oversize_payload_with_413"
  "attachment_requires_bearer_token"
  "attachment_download_unknown_id_is_404"
  "attachments_table_stores_no_plaintext_columns"
)

for test_name in "${required_rust_tests[@]}"; do
  require_rust_test_ok "${cargo_output}" "${test_name}"
done

DB_PATH="$(mktemp -t task-7-r6-live-db.XXXXXX)"
SERVER_LOG="$(mktemp -t task-7-r6-server-log.XXXXXX)"
SENTINEL_OUT="$(mktemp -t task-7-r6-sentinel.XXXXXX)"
ORIGINAL_FILE_OUT="$(mktemp -t task-7-r6-original-path.XXXXXX)"
DM_ATTACHMENT_ID_OUT="$(mktemp -t task-7-r6-dm-attachment-id.XXXXXX)"
GROUP_ATTACHMENT_ID_OUT="$(mktemp -t task-7-r6-group-attachment-id.XXXXXX)"
BOB_TOKEN_OUT="$(mktemp -t task-7-r6-bob-token.XXXXXX)"
UPLOAD_WIRE_FILE_OUT="$(mktemp -t task-7-r6-upload-wire-path.XXXXXX)"
LIVE_ORIGINAL_FILE_OUT="$(mktemp -t task-7-r6-live-original-path.XXXXXX)"
LIVE_DM_DOWNLOAD_OUT="$(mktemp -t task-7-r6-live-dm-download-path.XXXXXX)"
LIVE_GROUP_DOWNLOAD_OUT="$(mktemp -t task-7-r6-live-group-download-path.XXXXXX)"
STORED_BLOB="$(mktemp -t task-7-r6-stored-blob.XXXXXX)"
DOWNLOADED_BLOB="$(mktemp -t task-7-r6-downloaded-blob.XXXXXX)"
PORT="$(pick_port)"
BASE_URL="http://127.0.0.1:${PORT}"

echo "task-7 verify: using unique DB path ${DB_PATH}"
echo "task-7 verify: starting backend on ${BASE_URL}"
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

echo "task-7 verify: backend health check returned 200"

echo "task-7 verify: building Swift app and test targets"
set +e
swift_build_output="$(
  cd "${MAC_APP_DIR}" &&
    swift build 2>&1 &&
    swift build --build-tests 2>&1
)"
swift_build_status=$?
set -e

printf '%s\n' "${swift_build_output}"
if [[ "${swift_build_status}" -ne 0 ]]; then
  fail "swift app or test-target build failed"
fi

unset CHATAPP_LIVE_BACKEND_URL
unset CHATAPP_ATTACHMENT_SENTINEL_OUT
unset CHATAPP_ATTACHMENT_ORIGINAL_FILE_OUT
unset CHATAPP_ATTACHMENT_DM_ID_OUT
unset CHATAPP_ATTACHMENT_GROUP_ID_OUT
unset CHATAPP_ATTACHMENT_BOB_TOKEN_OUT
unset CHATAPP_ATTACHMENT_UPLOAD_WIRE_FILE_OUT
unset CHATAPP_ATTACHMENT_LIVE_ORIGINAL_FILE_OUT
unset CHATAPP_ATTACHMENT_LIVE_DM_DOWNLOAD_OUT
unset CHATAPP_ATTACHMENT_LIVE_GROUP_DOWNLOAD_OUT

echo "task-7 verify: running deterministic attachment Swift test classes"
set +e
swift_deterministic_output="$(
  cd "${MAC_APP_DIR}" &&
    swift test \
      --skip-build \
      --filter FileCryptoTests \
      --filter AttachmentDescriptorTests \
      --filter HTTPAttachmentServiceTests \
      --filter DMCoordinatorTests \
      2>&1
)"
swift_deterministic_status=$?
set -e

printf '%s\n' "${swift_deterministic_output}"
if [[ "${swift_deterministic_status}" -ne 0 ]]; then
  fail "deterministic attachment Swift test run failed"
fi
if ! grep -Eq "Test Suite 'All tests' passed|Test run .* passed" <<<"${swift_deterministic_output}"; then
  fail "deterministic Swift test output did not report a passing test run"
fi
if ! grep -q "with 0 failures" <<<"${swift_deterministic_output}"; then
  fail "deterministic Swift test output did not report 0 failures"
fi

require_swift_class_count "${swift_deterministic_output}" "FileCryptoTests" "6"
require_swift_class_count "${swift_deterministic_output}" "AttachmentDescriptorTests" "4"
require_swift_class_count "${swift_deterministic_output}" "HTTPAttachmentServiceTests" "4"
require_swift_class_count "${swift_deterministic_output}" "DMCoordinatorTests" "10"

excluded_swift_suites=("LiveGroupE2ETests" "LiveOfflineDeliveryE2ETests")
for excluded_suite in "${excluded_swift_suites[@]}"; do
  if grep -q "${excluded_suite}" <<<"${swift_deterministic_output}"; then
    fail "excluded Swift suite appeared in deterministic scoped output: ${excluded_suite}"
  fi
done

export CHATAPP_LIVE_BACKEND_URL="${BASE_URL}"
export CHATAPP_ATTACHMENT_SENTINEL_OUT="${SENTINEL_OUT}"
export CHATAPP_ATTACHMENT_ORIGINAL_FILE_OUT="${ORIGINAL_FILE_OUT}"
export CHATAPP_ATTACHMENT_DM_ID_OUT="${DM_ATTACHMENT_ID_OUT}"
export CHATAPP_ATTACHMENT_GROUP_ID_OUT="${GROUP_ATTACHMENT_ID_OUT}"
export CHATAPP_ATTACHMENT_BOB_TOKEN_OUT="${BOB_TOKEN_OUT}"
export CHATAPP_ATTACHMENT_UPLOAD_WIRE_FILE_OUT="${UPLOAD_WIRE_FILE_OUT}"
export CHATAPP_ATTACHMENT_LIVE_ORIGINAL_FILE_OUT="${LIVE_ORIGINAL_FILE_OUT}"
export CHATAPP_ATTACHMENT_LIVE_DM_DOWNLOAD_OUT="${LIVE_DM_DOWNLOAD_OUT}"
export CHATAPP_ATTACHMENT_LIVE_GROUP_DOWNLOAD_OUT="${LIVE_GROUP_DOWNLOAD_OUT}"

echo "task-7 verify: running live attachment Swift test class"
set +e
swift_live_output="$(
  cd "${MAC_APP_DIR}" &&
    swift test --skip-build --filter LiveAttachmentE2ETests 2>&1
)"
swift_live_status=$?
set -e

printf '%s\n' "${swift_live_output}"
if [[ "${swift_live_status}" -ne 0 ]]; then
  fail "live attachment Swift test run failed"
fi
if ! grep -Eq "Test Suite 'All tests' passed|Test run .* passed" <<<"${swift_live_output}"; then
  fail "live Swift test output did not report a passing test run"
fi
if ! grep -q "with 0 failures" <<<"${swift_live_output}"; then
  fail "live Swift test output did not report 0 failures"
fi

require_swift_class_count "${swift_live_output}" "LiveAttachmentE2ETests" "2"

require_swift_test_ok "${swift_live_output}" "testLiveAttachmentDMAndGroupRoundTripStoresOnlyCiphertext"
require_swift_test_ok "${swift_live_output}" "testAlreadySubscribedRecipientReceivesLiveAttachmentsAndWritesByteIdenticalDownloads"

for excluded_suite in "${excluded_swift_suites[@]}"; do
  if grep -q "${excluded_suite}" <<<"${swift_live_output}"; then
    fail "excluded Swift suite appeared in live scoped output: ${excluded_suite}"
  fi
done

for artifact in "${SENTINEL_OUT}" "${ORIGINAL_FILE_OUT}" "${DM_ATTACHMENT_ID_OUT}" "${GROUP_ATTACHMENT_ID_OUT}" "${BOB_TOKEN_OUT}" "${UPLOAD_WIRE_FILE_OUT}"; do
  if [[ ! -s "${artifact}" ]]; then
    fail "live attachment proof artifact was not written: ${artifact}"
  fi
done
for artifact in "${LIVE_ORIGINAL_FILE_OUT}" "${LIVE_DM_DOWNLOAD_OUT}" "${LIVE_GROUP_DOWNLOAD_OUT}"; do
  if [[ ! -s "${artifact}" ]]; then
    fail "live on-disk download proof artifact was not written: ${artifact}"
  fi
done

SENTINEL="$(cat "${SENTINEL_OUT}")"
ORIGINAL_FILE="$(cat "${ORIGINAL_FILE_OUT}")"
DM_ATTACHMENT_ID="$(cat "${DM_ATTACHMENT_ID_OUT}")"
GROUP_ATTACHMENT_ID="$(cat "${GROUP_ATTACHMENT_ID_OUT}")"
BOB_TOKEN="$(cat "${BOB_TOKEN_OUT}")"
UPLOAD_WIRE_FILE="$(cat "${UPLOAD_WIRE_FILE_OUT}")"
LIVE_ORIGINAL_FILE="$(cat "${LIVE_ORIGINAL_FILE_OUT}")"
LIVE_DM_DOWNLOAD_FILE="$(cat "${LIVE_DM_DOWNLOAD_OUT}")"
LIVE_GROUP_DOWNLOAD_FILE="$(cat "${LIVE_GROUP_DOWNLOAD_OUT}")"

echo "task-7 proof: dm_attachment_id=${DM_ATTACHMENT_ID}"
echo "task-7 proof: group_attachment_id=${GROUP_ATTACHMENT_ID}"

[[ -n "${SENTINEL}" ]] || fail "sentinel artifact must not be empty"
[[ -n "${DM_ATTACHMENT_ID}" ]] || fail "DM attachment id artifact must not be empty"
[[ -n "${GROUP_ATTACHMENT_ID}" ]] || fail "group attachment id artifact must not be empty"
[[ -n "${BOB_TOKEN}" ]] || fail "Bob token artifact must not be empty"
[[ -f "${ORIGINAL_FILE}" ]] || fail "original attachment proof file not found: ${ORIGINAL_FILE}"
[[ -f "${UPLOAD_WIRE_FILE}" ]] || fail "captured upload wire body not found: ${UPLOAD_WIRE_FILE}"
[[ -f "${LIVE_ORIGINAL_FILE}" ]] || fail "live original attachment proof file not found: ${LIVE_ORIGINAL_FILE}"
[[ -f "${LIVE_DM_DOWNLOAD_FILE}" ]] || fail "live DM downloaded file not found: ${LIVE_DM_DOWNLOAD_FILE}"
[[ -f "${LIVE_GROUP_DOWNLOAD_FILE}" ]] || fail "live group downloaded file not found: ${LIVE_GROUP_DOWNLOAD_FILE}"

if ! cmp -s "${LIVE_ORIGINAL_FILE}" "${LIVE_DM_DOWNLOAD_FILE}"; then
  fail "live DM downloaded file written to disk was not byte-identical to the original"
fi
echo "task-7 proof: cmp live_original live_dm_download PASS"
if ! cmp -s "${LIVE_ORIGINAL_FILE}" "${LIVE_GROUP_DOWNLOAD_FILE}"; then
  fail "live group downloaded file written to disk was not byte-identical to the original"
fi
echo "task-7 proof: cmp live_original live_group_download PASS"

echo "task-7 verify: extracting stored attachment blob and proving it is ciphertext"
quoted_blob_out="$(sql_quote "${STORED_BLOB}")"
quoted_dm_id="$(sql_quote "${DM_ATTACHMENT_ID}")"
writefile_result="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT writefile(${quoted_blob_out}, ciphertext) FROM attachments WHERE id=${quoted_dm_id};")" || {
  fail "could not extract stored attachment blob"
}
[[ -n "${writefile_result}" && -s "${STORED_BLOB}" ]] || fail "stored attachment blob was not written"

if cmp -s "${ORIGINAL_FILE}" "${STORED_BLOB}"; then
  fail "stored attachment blob equals original plaintext file"
fi
echo "task-7 proof: cmp original stored_blob DIFFERENT"
if cmp -s "${ORIGINAL_FILE}" "${UPLOAD_WIRE_FILE}"; then
  fail "captured upload wire body equals original plaintext file"
fi
echo "task-7 proof: cmp original upload_wire DIFFERENT"
if [[ "$(cmp -s "${STORED_BLOB}" "${UPLOAD_WIRE_FILE}"; echo $?)" != "0" ]]; then
  fail "stored attachment blob does not equal captured upload wire body"
fi
echo "task-7 proof: cmp stored_blob upload_wire PASS"

if strings "${DB_PATH}" "${DB_PATH}-wal" "${DB_PATH}-shm" 2>/dev/null | grep -F -- "${SENTINEL}" >/dev/null; then
  fail "sentinel plaintext appeared in raw SQLite strings"
fi
echo "task-7 proof: sentinel absent raw_sqlite_strings PASS"
if grep -F -- "${SENTINEL}" "${STORED_BLOB}" >/dev/null 2>&1; then
  fail "sentinel plaintext appeared in stored raw blob"
fi
echo "task-7 proof: sentinel absent stored_blob PASS"
if grep -F -- "${SENTINEL}" "${UPLOAD_WIRE_FILE}" >/dev/null 2>&1; then
  fail "sentinel plaintext appeared in captured upload wire body"
fi
echo "task-7 proof: sentinel absent upload_wire PASS"

original_bytes="$(wc -c <"${ORIGINAL_FILE}" | tr -d '[:space:]')"
stored_bytes="$(wc -c <"${STORED_BLOB}" | tr -d '[:space:]')"
db_byte_size="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT byte_size FROM attachments WHERE id=${quoted_dm_id};")"
upload_wire_bytes="$(wc -c <"${UPLOAD_WIRE_FILE}" | tr -d '[:space:]')"
if [[ "${stored_bytes}" -ne $((original_bytes + 28)) ]]; then
  fail "stored blob length ${stored_bytes} did not equal original length ${original_bytes} plus AES-GCM overhead"
fi
if [[ "${db_byte_size}" != "${stored_bytes}" ]]; then
  fail "attachments.byte_size ${db_byte_size} did not match stored ciphertext length ${stored_bytes}"
fi
if [[ "${upload_wire_bytes}" != "${stored_bytes}" ]]; then
  fail "captured upload wire body length ${upload_wire_bytes} did not match stored ciphertext length ${stored_bytes}"
fi
echo "task-7 proof: bytes original=${original_bytes} stored=${stored_bytes} wire=${upload_wire_bytes} attachment_byte_size=${db_byte_size} overhead=28"

curl -sS --max-time 5 -H "Authorization: Bearer ${BOB_TOKEN}" "${BASE_URL}/attachments/${DM_ATTACHMENT_ID}" -o "${DOWNLOADED_BLOB}" || {
  fail "authenticated attachment download failed"
}
if grep -F -- "${SENTINEL}" "${DOWNLOADED_BLOB}" >/dev/null 2>&1; then
  fail "sentinel plaintext appeared in downloaded ciphertext blob"
fi
downloaded_blob_bytes="$(wc -c <"${DOWNLOADED_BLOB}" | tr -d '[:space:]')"
echo "task-7 proof: sentinel absent authenticated_get_response PASS"
echo "task-7 proof: authenticated_get_response_bytes=${downloaded_blob_bytes}"

attachment_count="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT COUNT(*) FROM attachments WHERE id IN (${quoted_dm_id}, $(sql_quote "${GROUP_ATTACHMENT_ID}"));")"
if [[ "${attachment_count}" != "2" ]]; then
  fail "expected both DM and group attachment blobs in DB; found ${attachment_count}"
fi
echo "task-7 proof: attachment rows for dm_and_group=${attachment_count}"

echo "task-7 verify: checking attachments schema and zero-knowledge audit"
attachment_columns="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT name FROM pragma_table_info('attachments') ORDER BY cid;")"
expected_attachment_columns="id
uploader_id
ciphertext
byte_size
created_at"
if [[ "${attachment_columns}" != "${expected_attachment_columns}" ]]; then
  fail "attachments table columns drifted from ciphertext-only schema"
fi
echo "task-7 proof: attachments schema columns=$(tr '\n' ',' <<<"${attachment_columns}" | sed 's/,$//')"

audit_output="$(bash "${BACKEND_DIR}/scripts/zk_relay_audit.sh" "${DB_PATH}" 2>&1)" || {
  printf '%s\n' "${audit_output}"
  fail "zero-knowledge schema audit failed"
}
printf '%s\n' "${audit_output}"
if ! grep -q "ZERO-KNOWLEDGE SCHEMA AUDIT: PASS" <<<"${audit_output}"; then
  fail "zero-knowledge schema audit did not print PASS"
fi

echo "task-7 verify: shutting down backend and asserting zero residue"
cleanup
SERVER_PID=""
if pgrep -f -- "--db-path ${DB_PATH}" >/dev/null 2>&1; then
  fail "backend process still running for unique DB path after cleanup: ${DB_PATH}"
fi

echo "task-7 verify: PASS"
exit 0
