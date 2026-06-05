#!/usr/bin/env bash
set -euo pipefail

SERVER_PID=""
DB_PATH=""
SERVER_LOG=""
TOKEN_OUT=""
ORDER_OUT=""
HISTORY_OUT=""

fail() {
  echo "task-9 verify: FAIL"
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
  [[ -n "${TOKEN_OUT}" ]] && rm -f "${TOKEN_OUT}"
  [[ -n "${ORDER_OUT}" ]] && rm -f "${ORDER_OUT}"
  [[ -n "${HISTORY_OUT}" ]] && rm -f "${HISTORY_OUT}"
  return 0
}

extract_peer_usernames() {
  local json="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.conversations[].peer_username' <<<"${json}"
  else
    sed -n 's/.*"conversations":\[\(.*\)\].*/\1/p' <<<"${json}" \
      | grep -o '"peer_username":"[^"]*"' \
      | sed 's/"peer_username":"//;s/"$//' || true
  fi
}

message_count() {
  local json="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.messages | length' <<<"${json}"
  else
    grep -o '"id":"[^"]*"' <<<"${json}" | wc -l | tr -d ' '
  fi
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

if ! command -v jq >/dev/null 2>&1 && ! command -v sed >/dev/null 2>&1; then
  fail "jq or sed is required for JSON proof parsing"
fi

echo "task-9 verify: building and testing backend"
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

if ! grep -Eq "test conversations_.* \\.\\.\\. ok" <<<"${cargo_output}"; then
  fail "backend conversations_* tests did not execute and pass"
fi

DB_PATH="$(mktemp -t task-9-conversations-db.XXXXXX)"
SERVER_LOG="$(mktemp -t task-9-server-log.XXXXXX)"
TOKEN_OUT="$(mktemp -t task-9-token.XXXXXX)"
ORDER_OUT="$(mktemp -t task-9-order.XXXXXX)"
HISTORY_OUT="$(mktemp -t task-9-history.XXXXXX)"
PORT="${TASK_9_PORT:-$((45000 + ($$ % 10000)))}"
BASE_URL="http://127.0.0.1:${PORT}"

echo "task-9 verify: starting backend on ${BASE_URL}"
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

echo "task-9 verify: backend health check returned 200"
export CHATAPP_LIVE_BACKEND_URL="${BASE_URL}"
export CHATAPP_CONV_TOKEN_OUT="${TOKEN_OUT}"
export CHATAPP_CONV_ORDER_OUT="${ORDER_OUT}"
export CHATAPP_CONV_HISTORY_OUT="${HISTORY_OUT}"
unset CHATAPP_DM_SENTINEL_OUT CHATAPP_DM_WIRE_OUT CHATAPP_DM_MSGID_OUT CHATAPP_DM_TOKEN_OUT

echo "task-9 verify: building and testing Swift app with live conversations E2E"
swift_output="$(
  cd "${MAC_APP_DIR}"
  swift build 2>&1
  swift test --filter LiveConversationsE2ETests --filter ConversationListModelTests --filter ConversationListStoreTests --filter HTTPConversationsServiceTests 2>&1
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
  "testSortedOrdersMostRecentFirstAndTiesByUsername"
  "testUpsertInsertsBumpsToNewerActivityAndNeverRegresses"
  "testPeerIdReturnsOtherPartyForInboundAndOutboundRecords"
  "testConversationsGetsBearerTokenAndDecodesResponse"
  "testConversationsMapsNon200ToEmptyArray"
  "testRefreshMapsRecordsAndSortsMostRecentFirst"
  "testHandleLiveRecordForKnownPeerBumpsAndDoesNotFetchAgain"
  "testHandleLiveRecordForUnknownPeerRefreshesOnce"
  "testSubscribeConsumesInjectedLiveStream"
  "testSelectedPeerUsernameRoundTrips"
  "testLiveConversationListOrderingAndHistory"
)

for test_name in "${required_swift_tests[@]}"; do
  if grep -q "${test_name}.*failed" <<<"${swift_output}"; then
    fail "task-9 Swift test failed: ${test_name}"
  fi

  if ! grep -q "${test_name}.*passed" <<<"${swift_output}"; then
    fail "task-9 Swift test did not execute and pass: ${test_name}"
  fi
done

if grep -q "testLiveConversationListOrderingAndHistory.*skipped" <<<"${swift_output}"; then
  fail "LiveConversationsE2ETests skipped even though CHATAPP_LIVE_BACKEND_URL was set"
fi

for artifact in "${TOKEN_OUT}" "${ORDER_OUT}" "${HISTORY_OUT}"; do
  if [[ ! -s "${artifact}" ]]; then
    fail "live conversations proof artifact was not written: ${artifact}"
  fi
done

TOKEN="$(cat "${TOKEN_OUT}")"
expected_order="$(cat "${ORDER_OUT}")"
if [[ -z "${TOKEN}" || -z "${expected_order}" ]]; then
  fail "live conversations proof artifacts must not be empty"
fi

echo "task-9 verify: proving /conversations ordering"
conversations_response="$(curl -sS --max-time 5 -H "Authorization: Bearer ${TOKEN}" "${BASE_URL}/conversations")" || {
  fail "GET /conversations request failed"
}

actual_order="$(extract_peer_usernames "${conversations_response}")"
actual_count="$(printf '%s\n' "${actual_order}" | sed '/^$/d' | wc -l | tr -d ' ')"
if [[ "${actual_count}" != "2" ]]; then
  fail "expected exactly two conversations, got ${actual_count}: ${conversations_response}"
fi

if [[ "${actual_order}" != "${expected_order}" ]]; then
  fail "conversation order did not match proof artifact; expected [${expected_order//$'\n'/,}], got [${actual_order//$'\n'/,}]"
fi

first_peer="$(sed -n '1p' "${ORDER_OUT}")"
second_peer="$(sed -n '2p' "${ORDER_OUT}")"
if [[ -z "${first_peer}" || -z "${second_peer}" ]]; then
  fail "conversation order proof did not include two peer usernames"
fi

echo "task-9 verify: proving per-conversation message history counts"
while IFS='=' read -r peer expected_count; do
  [[ -z "${peer}" ]] && continue
  history_response="$(curl -sS --max-time 5 -H "Authorization: Bearer ${TOKEN}" "${BASE_URL}/messages?with=${peer}")" || {
    fail "GET /messages history request failed for ${peer}"
  }
  actual_history_count="$(message_count "${history_response}")"
  if [[ "${actual_history_count}" != "${expected_count}" ]]; then
    fail "history count for ${peer} was ${actual_history_count}, expected ${expected_count}"
  fi
done < "${HISTORY_OUT}"

p1_count="$(grep -F "${first_peer}=" "${HISTORY_OUT}" | sed 's/.*=//')"
p2_count="$(grep -F "${second_peer}=" "${HISTORY_OUT}" | sed 's/.*=//')"
if [[ "${p1_count}" != "2" || "${p2_count}" != "1" ]]; then
  fail "expected most-recent peer history count 2 and second peer count 1, got ${first_peer}=${p1_count}, ${second_peer}=${p2_count}"
fi

echo "task-9 verify: PASS"
