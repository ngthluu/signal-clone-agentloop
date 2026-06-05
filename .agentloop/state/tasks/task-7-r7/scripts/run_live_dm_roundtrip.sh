#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

require_cmd bash
require_cmd cmp
require_cmd swift
require_file "${MAC_APP_DIR}/Package.swift"
require_file "${MAC_APP_DIR}/Tests/ChatAppTests/LiveDMAttachmentE2ETests.swift"

ARTIFACT_ROOT="${TASK_DIR}/artifacts"
RUN_ID="live-dm-$(date +%Y%m%d-%H%M%S)-$$"
RUN_DIR="${ARTIFACT_ROOT}/${RUN_ID}"
mkdir -p "${RUN_DIR}"

DB_PATH="${RUN_DIR}/live-dm-attachments.sqlite"
SERVER_LOG="${RUN_DIR}/backend.log"
LIVE_TEST_LOG="${RUN_DIR}/swift-live-dm-attachment.log"
SWIFT_BUILD_TESTS_LOG="${RUN_DIR}/swift-build-tests.log"
CONTENT_SENTINEL_FILE="${RUN_DIR}/content-sentinel.txt"
FILENAME_SENTINEL_FILE="${RUN_DIR}/filename-sentinel.txt"
ORIGINAL_PATH_FILE="${RUN_DIR}/original-file-path.txt"
DOWNLOADED_PATH_FILE="${RUN_DIR}/downloaded-file-path.txt"
UPLOAD_WIRE_PATH_FILE="${RUN_DIR}/upload-wire-file-path.txt"
ATTACHMENT_ID_FILE="${RUN_DIR}/attachment-id.txt"
BOB_TOKEN_FILE="${RUN_DIR}/bob-token.txt"
LATEST_ENV="${ARTIFACT_ROOT}/latest.env"

BACKEND_STARTED=0
RUN_BACKEND_PID=""

cleanup() {
  local status=$?
  set +e
  if [[ "${BACKEND_STARTED}" -eq 1 ]]; then
    stop_backend "${RUN_BACKEND_PID}" "${DB_PATH}"
  fi
  return "${status}"
}
trap cleanup EXIT

read_text_file() {
  local path="${1:-}"
  require_nonempty_file "${path}"
  tr -d '\r\n' <"${path}"
}

require_output() {
  local needle="${1:-}"
  local path="${2:-}"
  [[ -n "${needle}" ]] || fail "require_output needs text"
  require_file "${path}"
  LC_ALL=C grep -F -q -- "${needle}" "${path}" || fail "missing expected output: ${needle}"
}

require_output_absent() {
  local needle="${1:-}"
  local path="${2:-}"
  [[ -n "${needle}" ]] || fail "require_output_absent needs text"
  require_file "${path}"
  if LC_ALL=C grep -F -q -- "${needle}" "${path}"; then
    fail "unexpected live DM attachment output: ${needle}"
  fi
}

require_no_live_failures_or_skips() {
  local path="${1:-}"
  require_file "${path}"
  local forbidden_patterns=(
    " FAILED"
    "FAILED "
    "failures:"
    " test result: FAILED"
    " failed "
    "Executed 0 tests"
    "XCTSkip"
    " skipped"
    "Skipped"
  )
  local pattern
  for pattern in "${forbidden_patterns[@]}"; do
    if LC_ALL=C grep -a -q -- "${pattern}" "${path}"; then
      fail "live DM attachment test failed or skipped: ${pattern}"
    fi
  done
}

shell_quote() {
  printf "%q" "${1:-}"
}

append_env_if_set() {
  local name="${1:-}"
  [[ -n "${name}" ]] || fail "append_env_if_set needs a variable name"
  if [[ -n "${!name:-}" ]]; then
    SWIFT_TOOL_ENV+=("${name}=${!name}")
  fi
}

if [[ -x "${BACKEND_DIR}/scripts/reap_stale_backends.sh" ]]; then
  bash "${BACKEND_DIR}/scripts/reap_stale_backends.sh"
fi

PORT="$(pick_free_port)"
echo "task-7-r7 live DM: starting backend on ${PORT}"
start_backend "${DB_PATH}" "${PORT}" "${SERVER_LOG}"
BACKEND_STARTED=1
RUN_BACKEND_PID="${BACKEND_PID}"
RUN_BACKEND_URL="${BACKEND_URL}"
unset BACKEND_PID BACKEND_URL

export CHATAPP_LIVE_BACKEND_URL="${RUN_BACKEND_URL}"
export CHATAPP_DM_ATTACHMENT_CONTENT_SENTINEL_OUT="${CONTENT_SENTINEL_FILE}"
export CHATAPP_DM_ATTACHMENT_FILENAME_SENTINEL_OUT="${FILENAME_SENTINEL_FILE}"
export CHATAPP_DM_ATTACHMENT_ORIGINAL_FILE_OUT="${ORIGINAL_PATH_FILE}"
export CHATAPP_DM_ATTACHMENT_DOWNLOADED_FILE_OUT="${DOWNLOADED_PATH_FILE}"
export CHATAPP_DM_ATTACHMENT_UPLOAD_WIRE_FILE_OUT="${UPLOAD_WIRE_PATH_FILE}"
export CHATAPP_DM_ATTACHMENT_ID_OUT="${ATTACHMENT_ID_FILE}"
export CHATAPP_DM_ATTACHMENT_BOB_TOKEN_OUT="${BOB_TOKEN_FILE}"

SWIFT_TOOL_ENV=(
  "PATH=${PATH}"
  "HOME=${HOME}"
  "TMPDIR=${TMPDIR:-/tmp}"
  "USER=${USER:-$(id -un)}"
)
append_env_if_set SHELL
append_env_if_set SDKROOT
append_env_if_set DEVELOPER_DIR
append_env_if_set TOOLCHAINS
append_env_if_set SWIFT_EXEC

LIVE_TEST_ENV=(
  "${SWIFT_TOOL_ENV[@]}"
  "CHATAPP_LIVE_BACKEND_URL=${CHATAPP_LIVE_BACKEND_URL}"
  "CHATAPP_DM_ATTACHMENT_CONTENT_SENTINEL_OUT=${CHATAPP_DM_ATTACHMENT_CONTENT_SENTINEL_OUT}"
  "CHATAPP_DM_ATTACHMENT_FILENAME_SENTINEL_OUT=${CHATAPP_DM_ATTACHMENT_FILENAME_SENTINEL_OUT}"
  "CHATAPP_DM_ATTACHMENT_ORIGINAL_FILE_OUT=${CHATAPP_DM_ATTACHMENT_ORIGINAL_FILE_OUT}"
  "CHATAPP_DM_ATTACHMENT_DOWNLOADED_FILE_OUT=${CHATAPP_DM_ATTACHMENT_DOWNLOADED_FILE_OUT}"
  "CHATAPP_DM_ATTACHMENT_UPLOAD_WIRE_FILE_OUT=${CHATAPP_DM_ATTACHMENT_UPLOAD_WIRE_FILE_OUT}"
  "CHATAPP_DM_ATTACHMENT_ID_OUT=${CHATAPP_DM_ATTACHMENT_ID_OUT}"
  "CHATAPP_DM_ATTACHMENT_BOB_TOKEN_OUT=${CHATAPP_DM_ATTACHMENT_BOB_TOKEN_OUT}"
)

echo "task-7-r7 live DM: running LiveDMAttachmentE2ETests"
echo "task-7-r7 live DM: ensuring Swift test bundle exists"
set +e
(
  cd "${MAC_APP_DIR}"
  env -i "${SWIFT_TOOL_ENV[@]}" swift build --build-tests
) >"${SWIFT_BUILD_TESTS_LOG}" 2>&1
build_status=$?
set -e
if [[ "${build_status}" -ne 0 ]]; then
  cat "${SWIFT_BUILD_TESTS_LOG}"
  fail "Swift test build failed with exit ${build_status}"
fi

set +e
(
  cd "${MAC_APP_DIR}"
  env -i "${LIVE_TEST_ENV[@]}" swift test --skip-build --filter LiveDMAttachmentE2ETests
) >"${LIVE_TEST_LOG}" 2>&1
test_status=$?
set -e
cat "${LIVE_TEST_LOG}"
[[ "${test_status}" -eq 0 ]] || fail "LiveDMAttachmentE2ETests failed with exit ${test_status}"

require_output "LiveDMAttachmentE2ETests" "${LIVE_TEST_LOG}"
require_output "testSubscribedRecipientReceivesDownloadsAndDecryptsBinaryAttachment" "${LIVE_TEST_LOG}"
require_output "passed" "${LIVE_TEST_LOG}"
require_no_live_failures_or_skips "${LIVE_TEST_LOG}"

require_nonempty_file "${CONTENT_SENTINEL_FILE}"
require_nonempty_file "${FILENAME_SENTINEL_FILE}"
require_nonempty_file "${ORIGINAL_PATH_FILE}"
require_nonempty_file "${DOWNLOADED_PATH_FILE}"
require_nonempty_file "${UPLOAD_WIRE_PATH_FILE}"
require_nonempty_file "${ATTACHMENT_ID_FILE}"
require_nonempty_file "${BOB_TOKEN_FILE}"

CONTENT_SENTINEL="$(read_text_file "${CONTENT_SENTINEL_FILE}")"
FILENAME_SENTINEL="$(read_text_file "${FILENAME_SENTINEL_FILE}")"
ORIGINAL_FILE="$(read_text_file "${ORIGINAL_PATH_FILE}")"
DOWNLOADED_FILE="$(read_text_file "${DOWNLOADED_PATH_FILE}")"
UPLOAD_WIRE_FILE="$(read_text_file "${UPLOAD_WIRE_PATH_FILE}")"
ATTACHMENT_ID="$(read_text_file "${ATTACHMENT_ID_FILE}")"
BOB_TOKEN="$(read_text_file "${BOB_TOKEN_FILE}")"

require_nonempty_file "${ORIGINAL_FILE}"
require_nonempty_file "${DOWNLOADED_FILE}"
require_nonempty_file "${UPLOAD_WIRE_FILE}"

if ! cmp -s "${ORIGINAL_FILE}" "${DOWNLOADED_FILE}"; then
  fail "downloaded attachment bytes differ from original"
fi

if cmp -s "${ORIGINAL_FILE}" "${UPLOAD_WIRE_FILE}"; then
  fail "upload wire body unexpectedly matches plaintext original"
fi

cat >"${LATEST_ENV}" <<EOF
ARTIFACT_DIR=$(shell_quote "${RUN_DIR}")
DB_PATH=$(shell_quote "${DB_PATH}")
SERVER_LOG=$(shell_quote "${SERVER_LOG}")
LIVE_TEST_LOG=$(shell_quote "${LIVE_TEST_LOG}")
SWIFT_BUILD_TESTS_LOG=$(shell_quote "${SWIFT_BUILD_TESTS_LOG}")
BACKEND_PORT=$(shell_quote "${PORT}")
CONTENT_SENTINEL_FILE=$(shell_quote "${CONTENT_SENTINEL_FILE}")
FILENAME_SENTINEL_FILE=$(shell_quote "${FILENAME_SENTINEL_FILE}")
CONTENT_SENTINEL=$(shell_quote "${CONTENT_SENTINEL}")
FILENAME_SENTINEL=$(shell_quote "${FILENAME_SENTINEL}")
ORIGINAL_PATH_FILE=$(shell_quote "${ORIGINAL_PATH_FILE}")
DOWNLOADED_PATH_FILE=$(shell_quote "${DOWNLOADED_PATH_FILE}")
UPLOAD_WIRE_PATH_FILE=$(shell_quote "${UPLOAD_WIRE_PATH_FILE}")
ATTACHMENT_ID_FILE=$(shell_quote "${ATTACHMENT_ID_FILE}")
BOB_TOKEN_FILE=$(shell_quote "${BOB_TOKEN_FILE}")
ORIGINAL_FILE=$(shell_quote "${ORIGINAL_FILE}")
DOWNLOADED_FILE=$(shell_quote "${DOWNLOADED_FILE}")
UPLOAD_WIRE_FILE=$(shell_quote "${UPLOAD_WIRE_FILE}")
ATTACHMENT_ID=$(shell_quote "${ATTACHMENT_ID}")
BOB_TOKEN=$(shell_quote "${BOB_TOKEN}")
EOF
require_nonempty_file "${LATEST_ENV}"

stop_backend "${RUN_BACKEND_PID}" "${DB_PATH}"
BACKEND_STARTED=0
require_no_backend_for_db "${DB_PATH}"

echo "task-7-r7 live DM round trip: PASS"
