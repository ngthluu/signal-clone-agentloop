#!/usr/bin/env bash
set -euo pipefail

SERVER_PID=""
DB_PATH=""
SERVER_LOG=""

fail() {
  echo "task-1d verify: FAIL"
  echo "reason: $*" >&2
  if [[ -n "${SERVER_LOG}" && -f "${SERVER_LOG}" ]]; then
    echo "server log:" >&2
    sed -n '1,180p' "${SERVER_LOG}" >&2 || true
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
  return 0
}

trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
MAC_APP_DIR="${REPO_ROOT}/mac-app"
SCHEMA_DUMP="${BACKEND_DIR}/scripts/schema_dump.sh"

if [[ ! -f "${BACKEND_DIR}/Cargo.toml" ]]; then
  fail "backend Cargo.toml not found at ${BACKEND_DIR}"
fi

if [[ ! -f "${MAC_APP_DIR}/Package.swift" ]]; then
  fail "mac-app Package.swift not found at ${MAC_APP_DIR}"
fi

if [[ ! -f "${SCHEMA_DUMP}" ]]; then
  fail "schema dump script not found at ${SCHEMA_DUMP}"
fi

if ! command -v curl >/dev/null 2>&1; then
  fail "curl is required"
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  fail "sqlite3 CLI is required"
fi

DB_PATH="$(mktemp -t task-1d-users-db.XXXXXX)"
SERVER_LOG="$(mktemp -t task-1d-server-log.XXXXXX)"
PORT="${TASK_1D_PORT:-$((43000 + ($$ % 10000)))}"
BASE_URL="http://127.0.0.1:${PORT}"

echo "task-1d verify: starting backend on ${BASE_URL}"
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

echo "task-1d verify: backend health check returned 200"
export CHATAPP_LIVE_BACKEND_URL="${BASE_URL}"

echo "task-1d verify: building ChatApp"
(
  cd "${MAC_APP_DIR}"
  swift build
) || fail "swift build failed"

echo "task-1d verify: running Swift account-flow tests"
swift_output="$(
  cd "${MAC_APP_DIR}"
  swift test 2>&1
)" || {
  printf '%s\n' "${swift_output}"
  fail "swift test failed"
}

printf '%s\n' "${swift_output}"

if ! grep -Eq "Test Suite 'All tests' passed|Test run .* passed" <<<"${swift_output}"; then
  fail "swift test output did not report a passing test run"
fi

if ! grep -q "with 0 failures" <<<"${swift_output}"; then
  fail "swift test output did not report 0 failures"
fi

required_tests=(
  "testEncodesExactlyUsernameAndIdentityPublicKey"
  "testHTTPClientTransmitsExactlyTwoFieldRegisterPayload"
  "testHTTPClientMapsConflictToUsernameTaken"
  "testHTTPClientMapsBadRequestToInvalid"
  "testSaveRoundTripsCurrentAccountAndHasAccount"
  "testFreshStoreInSameDirectoryLoadsPersistedAccount"
  "testAccountFileContainsOnlyPublicAccountMaterial"
  "testSuccessfulRegistrationPersistsAccountAndMarksRegistered"
  "testUsernameTakenShowsClearErrorAndDoesNotPersistAccount"
  "testExistingAccountMarksCoordinatorRegisteredAtInit"
  "testLiveRegistrationPersistsAccountAndDuplicateShowsTakenError"
)

for test_name in "${required_tests[@]}"; do
  if grep -q "${test_name}.*failed" <<<"${swift_output}"; then
    fail "acceptance-critical Swift test failed: ${test_name}"
  fi

  if ! grep -q "${test_name}.*passed" <<<"${swift_output}"; then
    fail "acceptance-critical Swift test did not execute and pass: ${test_name}"
  fi
done

if grep -q "testLiveRegistrationPersistsAccountAndDuplicateShowsTakenError.*skipped" <<<"${swift_output}"; then
  fail "live E2E test skipped even though CHATAPP_LIVE_BACKEND_URL was set"
fi

echo "task-1d verify: running schema/row dump"
dump_output="$(bash "${SCHEMA_DUMP}" "${DB_PATH}" 2>&1)" || {
  printf '%s\n' "${dump_output}"
  fail "schema_dump.sh failed"
}

printf '%s\n' "${dump_output}"

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

echo "task-1d verify: PASS"
