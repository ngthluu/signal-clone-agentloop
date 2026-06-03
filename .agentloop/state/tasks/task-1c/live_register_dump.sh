#!/usr/bin/env bash
set -euo pipefail

SERVER_PID=""
DB_PATH=""
SERVER_LOG=""
REGISTER_BODY=""
DUPLICATE_BODY=""
MALFORMED_BODY=""

fail() {
  echo "task-1c live-register-dump: FAIL"
  echo "reason: $*" >&2
  if [[ -n "${SERVER_LOG}" && -f "${SERVER_LOG}" ]]; then
    echo "server log:" >&2
    sed -n '1,160p' "${SERVER_LOG}" >&2 || true
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
  fi

  [[ -n "${DB_PATH}" ]] && rm -f "${DB_PATH}"
  [[ -n "${SERVER_LOG}" ]] && rm -f "${SERVER_LOG}"
  [[ -n "${REGISTER_BODY}" ]] && rm -f "${REGISTER_BODY}"
  [[ -n "${DUPLICATE_BODY}" ]] && rm -f "${DUPLICATE_BODY}"
  [[ -n "${MALFORMED_BODY}" ]] && rm -f "${MALFORMED_BODY}"
  return 0
}

trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
SCHEMA_DUMP="${BACKEND_DIR}/scripts/schema_dump.sh"

if [[ ! -f "${BACKEND_DIR}/Cargo.toml" ]]; then
  fail "backend Cargo.toml not found at ${BACKEND_DIR}"
fi

if [[ ! -x "${SCHEMA_DUMP}" ]]; then
  fail "schema dump script is not executable at ${SCHEMA_DUMP}"
fi

if ! command -v curl >/dev/null 2>&1; then
  fail "curl is required"
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  fail "sqlite3 CLI is required"
fi

DB_PATH="$(mktemp -t task-1c-users-db.XXXXXX)"
SERVER_LOG="$(mktemp -t task-1c-server-log.XXXXXX)"
PORT="${TASK_1C_PORT:-$((42000 + ($$ % 10000)))}"
BASE_URL="http://127.0.0.1:${PORT}"

echo "task-1c live-register-dump: starting backend on ${BASE_URL}"
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

echo "task-1c live-register-dump: backend health check returned 200"

post_json() {
  local body="$1"
  local output_file="$2"
  curl -sS --max-time 5 \
    -o "${output_file}" \
    -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -X POST \
    --data "${body}" \
    "${BASE_URL}/register"
}

REGISTER_BODY="$(mktemp -t task-1c-register-body.XXXXXX)"
DUPLICATE_BODY="$(mktemp -t task-1c-duplicate-body.XXXXXX)"
MALFORMED_BODY="$(mktemp -t task-1c-malformed-body.XXXXXX)"

status="$(post_json '{"username":"task_1c_live","identity_public_key":"cHVibGljLWtleS0xMjM0"}' "${REGISTER_BODY}")"
if [[ "${status}" != "201" ]]; then
  fail "expected initial registration status 201, got ${status}"
fi

user_id="$(sed -n 's/.*"user_id"[[:space:]]*:[[:space:]]*"\([^"]\{1,\}\)".*/\1/p' "${REGISTER_BODY}")"
if [[ -z "${user_id}" ]]; then
  fail "registration response did not contain a non-empty user_id"
fi

echo "task-1c live-register-dump: registration returned 201 with user_id ${user_id}"

status="$(post_json '{"username":"task_1c_live","identity_public_key":"cHVibGljLWtleS0xMjM0"}' "${DUPLICATE_BODY}")"
if [[ "${status}" != "409" ]]; then
  fail "expected duplicate registration status 409, got ${status}"
fi

echo "task-1c live-register-dump: duplicate username returned 409"

status="$(post_json '{"username":"no","identity_public_key":"not-base64"}' "${MALFORMED_BODY}")"
if [[ "${status}" != "400" ]]; then
  fail "expected malformed registration status 400, got ${status}"
fi

echo "task-1c live-register-dump: malformed input returned 400"

if kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
  kill "${SERVER_PID}" >/dev/null 2>&1 || true
  wait "${SERVER_PID}" >/dev/null 2>&1 || true
fi
SERVER_PID=""

rm -f "${REGISTER_BODY}" "${DUPLICATE_BODY}" "${MALFORMED_BODY}"
REGISTER_BODY=""
DUPLICATE_BODY=""
MALFORMED_BODY=""

echo "task-1c live-register-dump: running schema/row dump"
dump_output="$("${SCHEMA_DUMP}" "${DB_PATH}" 2>&1)" || {
  printf '%s\n' "${dump_output}"
  fail "schema_dump.sh failed"
}

printf '%s\n' "${dump_output}"

if ! grep -q '^PRAGMA table_info(users)$' <<<"${dump_output}"; then
  fail "schema dump did not include PRAGMA table_info(users)"
fi

actual_columns="$(sqlite3 -noheader -batch "${DB_PATH}" "SELECT name FROM pragma_table_info('users') ORDER BY cid;")"
expected_columns="id
username
identity_public_key
created_at"
if [[ "${actual_columns}" != "${expected_columns}" ]]; then
  fail "users table columns were not exactly id/username/identity_public_key/created_at"
fi

if ! grep -q '^sample stored user row$' <<<"${dump_output}"; then
  fail "schema dump did not include a sample stored user row"
fi

if ! grep -q '^confirmed no private/secret columns or private material in users schema or sample row$' <<<"${dump_output}"; then
  fail "schema dump did not confirm absence of private/secret material"
fi

echo "task-1c live-register-dump: PASS"
