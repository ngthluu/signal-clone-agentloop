#!/usr/bin/env bash
set -euo pipefail

SERVER_PID=""
SERVER_LOG=""
DB2=""
SENTINEL_DB_FILE=""
SENTINEL_VALUE_FILE=""
SENTINEL_MSGID_FILE=""
SENTINEL_WIRE_FILE=""
SENTINEL_ATTACH_VALUE_FILE=""
SENTINEL_ATTACH_ID_FILE=""
SENTINEL_DB=""

fail() {
  echo "task-4 verify: FAIL"
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

  cleanup_file_and_sidecars "${SENTINEL_DB}"
  cleanup_file_and_sidecars "${DB2}"
  rm -f "${SERVER_LOG}" \
    "${SENTINEL_DB_FILE}" \
    "${SENTINEL_VALUE_FILE}" \
    "${SENTINEL_MSGID_FILE}" \
    "${SENTINEL_WIRE_FILE}" \
    "${SENTINEL_ATTACH_VALUE_FILE}" \
    "${SENTINEL_ATTACH_ID_FILE}"
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

require_test_ok() {
  local cargo_output="$1"
  local test_name="$2"
  if ! grep -Eq "test ${test_name} \\.\\.\\. ok" <<<"${cargo_output}"; then
    fail "backend acceptance test did not execute and pass: ${test_name}"
  fi
}

trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"

if [[ ! -f "${BACKEND_DIR}/Cargo.toml" ]]; then
  fail "backend Cargo.toml not found at ${BACKEND_DIR}"
fi

for required_cmd in curl sqlite3 strings; do
  if ! command -v "${required_cmd}" >/dev/null 2>&1; then
    fail "${required_cmd} is required"
  fi
done

SENTINEL_DB_FILE="$(mktemp -t task-4-sentinel-db.XXXXXX)"
SENTINEL_VALUE_FILE="$(mktemp -t task-4-sentinel-value.XXXXXX)"
SENTINEL_MSGID_FILE="$(mktemp -t task-4-sentinel-msgid.XXXXXX)"
SENTINEL_WIRE_FILE="$(mktemp -t task-4-sentinel-wire.XXXXXX)"
SENTINEL_ATTACH_VALUE_FILE="$(mktemp -t task-4-sentinel-attach-value.XXXXXX)"
SENTINEL_ATTACH_ID_FILE="$(mktemp -t task-4-sentinel-attach-id.XXXXXX)"
SERVER_LOG="$(mktemp -t task-4-server-log.XXXXXX)"
DB2="$(mktemp -t task-4-live-db.XXXXXX)"
PORT="${TASK_4_PORT:-$((44000 + ($$ % 10000)))}"
BASE_URL="http://127.0.0.1:${PORT}"

export ZK_SENTINEL_KEEP_DB=1
export ZK_SENTINEL_DB_OUT="${SENTINEL_DB_FILE}"
export ZK_SENTINEL_VALUE_OUT="${SENTINEL_VALUE_FILE}"
export ZK_SENTINEL_MSGID_OUT="${SENTINEL_MSGID_FILE}"
export ZK_SENTINEL_WIRE_OUT="${SENTINEL_WIRE_FILE}"
export ZK_SENTINEL_ATTACH_VALUE_OUT="${SENTINEL_ATTACH_VALUE_FILE}"
export ZK_SENTINEL_ATTACH_ID_OUT="${SENTINEL_ATTACH_ID_FILE}"

echo "task-4 verify: STEP A backend build and tests"
set +e
cargo_output="$(
  cd "${BACKEND_DIR}" &&
    cargo build 2>&1 &&
    cargo test 2>&1
)"
cargo_status=$?
set -e

printf '%s\n' "${cargo_output}"

if [[ "${cargo_status}" -ne 0 ]]; then
  fail "backend cargo build/test failed"
fi

if grep -q "error\\[" <<<"${cargo_output}"; then
  fail "backend cargo output contained a Rust compiler error"
fi

if ! grep -Eq "test result: ok\\..*0 failed" <<<"${cargo_output}"; then
  fail "backend cargo output did not report passing test results with 0 failed"
fi

required_rust_tests=(
  "zk_relay_audit_passes_for_ciphertext_only_schema"
  "zk_relay_audit_fails_when_plaintext_column_exists"
  "zk_relay_audit_fails_when_private_key_column_exists"
  "zk_relay_audit_fails_when_attachments_shape_drifts"
  "messages_post_stores_exactly_the_ciphertext_blob"
  "messages_table_stores_no_plaintext_columns"
  "zk_sentinel_roundtrip_stores_only_ciphertext_in_raw_db"
)

for test_name in "${required_rust_tests[@]}"; do
  require_test_ok "${cargo_output}" "${test_name}"
done

echo "task-4 verify: STEP B independent sentinel DB audit"
for artifact in \
  "${SENTINEL_DB_FILE}" \
  "${SENTINEL_VALUE_FILE}" \
  "${SENTINEL_MSGID_FILE}" \
  "${SENTINEL_WIRE_FILE}" \
  "${SENTINEL_ATTACH_VALUE_FILE}" \
  "${SENTINEL_ATTACH_ID_FILE}"; do
  if [[ ! -s "${artifact}" ]]; then
    fail "sentinel proof artifact was not written: ${artifact}"
  fi
done

SENTINEL_DB="$(cat "${SENTINEL_DB_FILE}")"
SENTINEL="$(cat "${SENTINEL_VALUE_FILE}")"
MSGID="$(cat "${SENTINEL_MSGID_FILE}")"
WIRE_JSON="$(cat "${SENTINEL_WIRE_FILE}")"
ATTACH_SENTINEL="$(cat "${SENTINEL_ATTACH_VALUE_FILE}")"
ATTACH_ID="$(cat "${SENTINEL_ATTACH_ID_FILE}")"

if [[ -z "${SENTINEL_DB}" || -z "${SENTINEL}" || -z "${MSGID}" || -z "${WIRE_JSON}" || -z "${ATTACH_SENTINEL}" || -z "${ATTACH_ID}" ]]; then
  fail "sentinel proof artifacts must not be empty"
fi

if [[ ! -f "${SENTINEL_DB}" ]]; then
  fail "sentinel SQLite DB not found: ${SENTINEL_DB}"
fi

raw_strings="$(strings "${SENTINEL_DB}" "${SENTINEL_DB}-wal" "${SENTINEL_DB}-shm" 2>/dev/null || true)"
if grep -F -- "${SENTINEL}" <<<"${raw_strings}" >/dev/null; then
  fail "raw SQLite bytes contain plaintext sentinel"
fi

WIRE_CIPHERTEXT="$(json_extract_file "${SENTINEL_WIRE_FILE}" '$.ciphertext')"
WIRE_KEYS="$(json_keys_csv_file "${SENTINEL_WIRE_FILE}")"
WIRE_KEY_COUNT="$(json_key_count_file "${SENTINEL_WIRE_FILE}")"

if [[ -z "${WIRE_CIPHERTEXT}" ]]; then
  fail "wire JSON did not contain a ciphertext value"
fi

if [[ "${WIRE_KEYS}" != "ciphertext,recipient_username" || "${WIRE_KEY_COUNT}" != "2" ]]; then
  fail "wire JSON keys must be exactly ciphertext,recipient_username; got ${WIRE_KEYS:-<none>}"
fi

quoted_msgid="$(sql_quote "${MSGID}")"
message_row="$(sqlite3 -noheader -batch -separator $'\t' "${SENTINEL_DB}" \
  "SELECT id,sender_id,recipient_id,ciphertext,created_at FROM messages WHERE id=${quoted_msgid};")"

if [[ -z "${message_row}" ]]; then
  fail "sentinel message row was not found in messages table"
fi

if grep -F -- "${SENTINEL}" <<<"${message_row}" >/dev/null; then
  fail "messages row contains plaintext sentinel"
fi

stored_ciphertext="$(cut -f4 <<<"${message_row}")"
if [[ "${stored_ciphertext}" != "${WIRE_CIPHERTEXT}" ]]; then
  fail "messages.ciphertext does not equal the posted wire ciphertext"
fi
echo "task-4 verify: DM sentinel absent from raw SQLite bytes; messages.ciphertext matches wire ciphertext"

if grep -F -- "${ATTACH_SENTINEL}" <<<"${raw_strings}" >/dev/null; then
  fail "raw SQLite bytes contain plaintext attachment sentinel"
fi

quoted_attach_id="$(sql_quote "${ATTACH_ID}")"
attachment_row="$(sqlite3 -noheader -batch -separator $'\t' "${SENTINEL_DB}" \
  "SELECT id,uploader_id,byte_size,created_at FROM attachments WHERE id=${quoted_attach_id};")"

if [[ -z "${attachment_row}" ]]; then
  fail "sentinel attachment row was not found in attachments table"
fi

if grep -F -- "${ATTACH_SENTINEL}" <<<"${attachment_row}" >/dev/null; then
  fail "attachments metadata row contains plaintext attachment sentinel"
fi
echo "task-4 verify: attachment sentinel absent from raw SQLite bytes; attachment metadata row present without plaintext"

audit_output="$(bash "${BACKEND_DIR}/scripts/zk_relay_audit.sh" "${SENTINEL_DB}" 2>&1)" || {
  printf '%s\n' "${audit_output}"
  fail "zero-knowledge schema audit failed on sentinel DB"
}
printf '%s\n' "${audit_output}"

if ! grep -q "ZERO-KNOWLEDGE SCHEMA AUDIT: PASS" <<<"${audit_output}"; then
  fail "zero-knowledge schema audit did not print the PASS line for sentinel DB"
fi

echo "task-4 verify: STEP C live backend schema and log audit on ${BASE_URL}"
(
  cd "${BACKEND_DIR}"
  cargo run -- --db-path "${DB2}" --port "${PORT}"
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
live_audit_output="$(bash "${BACKEND_DIR}/scripts/zk_relay_audit.sh" "${DB2}" 2>&1)" || {
  printf '%s\n' "${live_audit_output}"
  fail "zero-knowledge schema audit failed on live backend DB"
}
printf '%s\n' "${live_audit_output}"

if ! grep -q "ZERO-KNOWLEDGE SCHEMA AUDIT: PASS" <<<"${live_audit_output}"; then
  fail "zero-knowledge schema audit did not print the PASS line for live backend DB"
fi

if grep -F -- "${SENTINEL}" "${SERVER_LOG}" >/dev/null 2>&1; then
  fail "server log contains plaintext sentinel"
fi

if grep -Eiq 'BEGIN .*PRIVATE KEY|x25519_private|identity_private|private_key' "${SERVER_LOG}" >/dev/null 2>&1; then
  fail "server log contains private-key markers"
fi

log_bytes="$(wc -c <"${SERVER_LOG}" | tr -d '[:space:]')"
echo "task-4 verify: server log bytes=${log_bytes}"
echo "task-4 verify: server log head"
head -n 20 "${SERVER_LOG}" || true

kill "${SERVER_PID}" >/dev/null 2>&1 || true
wait "${SERVER_PID}" >/dev/null 2>&1 || true
SERVER_PID=""

echo "task-4 verify: PASS"
