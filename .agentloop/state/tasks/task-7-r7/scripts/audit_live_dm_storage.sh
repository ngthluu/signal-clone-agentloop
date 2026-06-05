#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

LATEST_ENV="${TASK_DIR}/artifacts/latest.env"
require_nonempty_file "${LATEST_ENV}"
# shellcheck source=/dev/null
source "${LATEST_ENV}"

require_cmd bash
require_cmd cmp
require_cmd curl
require_cmd perl
require_cmd sqlite3
require_file "${BACKEND_DIR}/scripts/zk_relay_audit.sh"

require_env() {
  local name="${1:-}"
  [[ -n "${name}" ]] || fail "require_env needs a variable name"
  [[ -n "${!name:-}" ]] || fail "missing required artifact value: ${name}"
}

file_size() {
  local path="${1:-}"
  require_file "${path}"
  wc -c <"${path}" | tr -d '[:space:]'
}

sqlite_scalar() {
  local sql="${1:-}"
  [[ -n "${sql}" ]] || fail "sqlite_scalar needs SQL"
  sqlite3 -noheader -batch "${DB_PATH}" "${sql}"
}

sql_quote() {
  local value="${1:-}"
  printf "'%s'" "${value//\'/\'\'}"
}

require_output_contains() {
  local needle="${1:-}"
  local path="${2:-}"
  [[ -n "${needle}" ]] || fail "require_output_contains needs text"
  require_file "${path}"
  LC_ALL=C grep -F -q -- "${needle}" "${path}" || fail "missing expected output: ${needle}"
}

scan_absent_sentinels() {
  local path="${1:-}"
  local label="${2:-${path}}"
  require_file "${path}"
  require_absent_bytes "${FILENAME_SENTINEL_FILE}" "${path}" "${label} filename sentinel"
  require_absent_bytes "${CONTENT_SENTINEL_FILE}" "${path}" "${label} content sentinel"
}

scan_storage_and_logs() {
  local path
  for path in "${DB_PATH}" "${DB_PATH}-wal" "${DB_PATH}-shm" "${DB_PATH}-journal"; do
    if [[ -e "${path}" ]]; then
      scan_absent_sentinels "${path}" "${path}"
    fi
  done

  scan_absent_sentinels "${STORED_CIPHERTEXT_FILE}" "stored attachment ciphertext"
  scan_absent_sentinels "${UPLOAD_WIRE_FILE}" "captured upload wire body"
  scan_absent_sentinels "${SERVER_LOG}" "live backend log"
}

for name in \
  ARTIFACT_DIR \
  DB_PATH \
  SERVER_LOG \
  CONTENT_SENTINEL_FILE \
  FILENAME_SENTINEL_FILE \
  ORIGINAL_FILE \
  DOWNLOADED_FILE \
  UPLOAD_WIRE_FILE \
  ATTACHMENT_ID_FILE \
  BOB_TOKEN_FILE \
  ATTACHMENT_ID \
  BOB_TOKEN; do
  require_env "${name}"
done

require_nonempty_file "${CONTENT_SENTINEL_FILE}"
require_nonempty_file "${FILENAME_SENTINEL_FILE}"
require_nonempty_file "${ORIGINAL_FILE}"
require_nonempty_file "${DOWNLOADED_FILE}"
require_nonempty_file "${UPLOAD_WIRE_FILE}"
require_nonempty_file "${ATTACHMENT_ID_FILE}"
require_nonempty_file "${BOB_TOKEN_FILE}"
require_nonempty_file "${DB_PATH}"
require_file "${SERVER_LOG}"

[[ "$(tr -d '\r\n' <"${ATTACHMENT_ID_FILE}")" == "${ATTACHMENT_ID}" ]] || fail "attachment id artifact file does not match latest.env"
[[ "$(tr -d '\r\n' <"${BOB_TOKEN_FILE}")" == "${BOB_TOKEN}" ]] || fail "Bob token artifact file does not match latest.env"

if ! cmp -s "${ORIGINAL_FILE}" "${DOWNLOADED_FILE}"; then
  fail "downloaded attachment bytes differ from original"
fi

ARTIFACT_DIR="${ARTIFACT_DIR}"
mkdir -p "${ARTIFACT_DIR}"
STORED_CIPHERTEXT_FILE="${ARTIFACT_DIR}/stored-attachment-ciphertext.bin"
GET_RESPONSE_FILE="${ARTIFACT_DIR}/authenticated-download-ciphertext.bin"
AUDIT_SERVER_LOG="${ARTIFACT_DIR}/backend-authenticated-download.log"
SCHEMA_AUDIT_LOG="${ARTIFACT_DIR}/zk-relay-audit.log"

attachment_id_sql="$(sql_quote "${ATTACHMENT_ID}")"
row_count="$(sqlite_scalar "SELECT COUNT(*) FROM attachments WHERE id = ${attachment_id_sql};")"
[[ "${row_count}" == "1" ]] || fail "expected exactly one attachment row for live DM attachment, found ${row_count}"

stored_hex="$(sqlite_scalar "SELECT hex(ciphertext) FROM attachments WHERE id = ${attachment_id_sql};")"
[[ -n "${stored_hex}" ]] || fail "attachment ciphertext blob is empty or missing"
if [[ "${#stored_hex}" -lt 2 || $(( ${#stored_hex} % 2 )) -ne 0 ]]; then
  fail "attachment ciphertext hex output is malformed"
fi

STORED_HEX="${stored_hex}" STORED_OUT="${STORED_CIPHERTEXT_FILE}" perl -e '
  use strict;
  use warnings;
  my $hex = $ENV{"STORED_HEX"};
  open(my $out, ">:raw", $ENV{"STORED_OUT"}) or die $!;
  print {$out} pack("H*", $hex);
'
require_nonempty_file "${STORED_CIPHERTEXT_FILE}"

if cmp -s "${STORED_CIPHERTEXT_FILE}" "${ORIGINAL_FILE}"; then
  fail "stored attachment ciphertext unexpectedly matches plaintext original"
fi

if ! cmp -s "${STORED_CIPHERTEXT_FILE}" "${UPLOAD_WIRE_FILE}"; then
  fail "stored attachment ciphertext differs from captured upload wire body"
fi

original_size="$(file_size "${ORIGINAL_FILE}")"
stored_size="$(file_size "${STORED_CIPHERTEXT_FILE}")"
upload_wire_size="$(file_size "${UPLOAD_WIRE_FILE}")"
db_byte_size="$(sqlite_scalar "SELECT byte_size FROM attachments WHERE id = ${attachment_id_sql};")"

[[ "${stored_size}" == "${upload_wire_size}" ]] || fail "stored ciphertext size differs from upload wire body size"
[[ "${db_byte_size}" == "${stored_size}" ]] || fail "attachments.byte_size ${db_byte_size} does not equal stored blob length ${stored_size}"
[[ "${stored_size}" -ge $((original_size + 28)) ]] || fail "stored blob is smaller than plaintext plus AES-GCM overhead"
[[ "${stored_size}" -eq $((original_size + 28)) ]] || fail "stored blob length ${stored_size} does not equal plaintext length ${original_size} plus current FileCrypto overhead 28"

scan_storage_and_logs

AUDIT_BACKEND_STARTED=0
AUDIT_BACKEND_PID=""
cleanup() {
  local status=$?
  set +e
  if [[ "${AUDIT_BACKEND_STARTED}" -eq 1 ]]; then
    stop_backend "${AUDIT_BACKEND_PID}" "${DB_PATH}"
  fi
  return "${status}"
}
trap cleanup EXIT

AUDIT_PORT="$(pick_free_port)"
echo "task-7-r7 storage audit: starting authenticated download backend on ${AUDIT_PORT}"
start_backend "${DB_PATH}" "${AUDIT_PORT}" "${AUDIT_SERVER_LOG}"
AUDIT_BACKEND_STARTED=1
AUDIT_BACKEND_PID="${BACKEND_PID}"
AUDIT_BACKEND_URL="${BACKEND_URL}"
unset BACKEND_PID BACKEND_URL

set +e
curl -fsS \
  -H "Authorization: Bearer ${BOB_TOKEN}" \
  "${AUDIT_BACKEND_URL}/attachments/${ATTACHMENT_ID}" \
  -o "${GET_RESPONSE_FILE}"
curl_status=$?
set -e
if [[ "${curl_status}" -ne 0 ]]; then
  [[ -f "${AUDIT_SERVER_LOG}" ]] && tail -n 80 "${AUDIT_SERVER_LOG}" >&2 || true
  fail "authenticated attachment download failed with exit ${curl_status}"
fi
require_nonempty_file "${GET_RESPONSE_FILE}"

if ! cmp -s "${GET_RESPONSE_FILE}" "${STORED_CIPHERTEXT_FILE}"; then
  fail "authenticated GET response differs from stored ciphertext"
fi

if cmp -s "${GET_RESPONSE_FILE}" "${ORIGINAL_FILE}"; then
  fail "authenticated GET response unexpectedly matches plaintext original"
fi

scan_absent_sentinels "${GET_RESPONSE_FILE}" "authenticated GET response"
scan_absent_sentinels "${AUDIT_SERVER_LOG}" "authenticated download backend log"

set +e
bash "${BACKEND_DIR}/scripts/zk_relay_audit.sh" "${DB_PATH}" >"${SCHEMA_AUDIT_LOG}" 2>&1
schema_status=$?
set -e
cat "${SCHEMA_AUDIT_LOG}"
[[ "${schema_status}" -eq 0 ]] || fail "zero-knowledge schema audit failed with exit ${schema_status}"
require_output_contains "ZERO-KNOWLEDGE SCHEMA AUDIT: PASS" "${SCHEMA_AUDIT_LOG}"

stop_backend "${AUDIT_BACKEND_PID}" "${DB_PATH}"
AUDIT_BACKEND_STARTED=0
require_no_backend_for_db "${DB_PATH}"

echo "task-7-r7 storage/log/authenticated download audit: PASS"
