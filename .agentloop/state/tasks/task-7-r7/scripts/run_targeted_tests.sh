#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

RUN_DIR="${TASK_DIR}/artifacts/targeted-tests"
mkdir -p "${RUN_DIR}"

require_cmd bash
require_cmd cargo
require_cmd swift
require_file "${BACKEND_DIR}/Cargo.toml"
require_file "${MAC_APP_DIR}/Package.swift"

BACKEND_LOG="${RUN_DIR}/backend-attachments.log"
SWIFT_BUILD_LOG="${RUN_DIR}/swift-build.log"
SWIFT_BUILD_TESTS_LOG="${RUN_DIR}/swift-build-tests.log"
SWIFT_FILTER_LOG="${RUN_DIR}/swift-targeted-filters.log"
COMBINED_LOG="${RUN_DIR}/combined.log"

: >"${COMBINED_LOG}"

append_log() {
  local log_path="${1:-}"
  require_file "${log_path}"
  cat "${log_path}"
  cat "${log_path}" >>"${COMBINED_LOG}"
}

run_and_capture() {
  local label="${1:-}"
  local log_path="${2:-}"
  shift 2
  [[ -n "${label}" ]] || fail "run_and_capture needs a label"
  [[ -n "${log_path}" ]] || fail "run_and_capture needs a log path"

  echo "task-7-r7 targeted: ${label}"
  printf 'task-7-r7 targeted command:'
  printf ' %q' "$@"
  printf '\n'
  set +e
  "$@" >"${log_path}" 2>&1
  local status=$?
  set -e
  append_log "${log_path}"
  [[ "${status}" -eq 0 ]] || fail "${label} failed with exit ${status}"
}

run_quiet_build() {
  local label="${1:-}"
  local log_path="${2:-}"
  shift 2
  [[ -n "${label}" ]] || fail "run_quiet_build needs a label"
  [[ -n "${log_path}" ]] || fail "run_quiet_build needs a log path"

  echo "task-7-r7 targeted: ${label}"
  printf 'task-7-r7 targeted command:'
  printf ' %q' "$@"
  printf '\n'
  set +e
  "$@" >"${log_path}" 2>&1
  local status=$?
  set -e
  if [[ "${status}" -ne 0 ]]; then
    append_log "${log_path}"
    fail "${label} failed with exit ${status}"
  fi
  echo "task-7-r7 targeted: ${label} complete"
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
    fail "unexpected output from unscoped suite or failure: ${needle}"
  fi
}

require_no_failure_output() {
  local path="${1:-}"
  require_file "${path}"
  local failure_patterns=(
    " FAILED"
    "FAILED "
    "failures:"
    " test result: FAILED"
    " failed "
    "Executed 0 tests"
  )
  local pattern
  for pattern in "${failure_patterns[@]}"; do
    if LC_ALL=C grep -a -q -- "${pattern}" "${path}"; then
      fail "failure output found in ${path}: ${pattern}"
    fi
  done
}

require_no_skipped_swift_tests() {
  local path="${1:-}"
  require_file "${path}"
  if LC_ALL=C grep -a -E -q "(^|[^[:alpha:]])([Ss]kipped|XCTSkip)" "${path}"; then
    fail "acceptance-critical Swift attachment test was skipped"
  fi
}

if [[ -x "${BACKEND_DIR}/scripts/reap_stale_backends.sh" ]]; then
  bash "${BACKEND_DIR}/scripts/reap_stale_backends.sh"
fi

run_and_capture \
  "backend attachment tests" \
  "${BACKEND_LOG}" \
  bash -c 'cd "$1" && cargo test --test attachments' bash "${BACKEND_DIR}"

required_backend_tests=(
  "attachment_upload_then_download_round_trips_exact_bytes"
  "attachment_upload_rejects_oversize_payload_with_413"
  "attachment_upload_accepts_exact_10mb_ciphertext_payload"
  "attachment_requires_bearer_token"
  "attachment_download_unknown_id_is_404"
  "attachments_table_stores_no_plaintext_columns"
)

for test_name in "${required_backend_tests[@]}"; do
  require_output "${test_name}" "${BACKEND_LOG}"
done
require_output "test result: ok" "${BACKEND_LOG}"
require_no_failure_output "${BACKEND_LOG}"

run_quiet_build \
  "Swift package build" \
  "${SWIFT_BUILD_LOG}" \
  bash -c 'cd "$1" && swift build' bash "${MAC_APP_DIR}"

run_quiet_build \
  "Swift test build" \
  "${SWIFT_BUILD_TESTS_LOG}" \
  bash -c 'cd "$1" && swift build --build-tests' bash "${MAC_APP_DIR}"

: >"${SWIFT_FILTER_LOG}"
swift_filters=(
  "FileCryptoTests"
  "AttachmentDescriptorTests"
  "HTTPAttachmentServiceTests"
  "DMCoordinatorTests"
)

for filter in "${swift_filters[@]}"; do
  filter_log="${RUN_DIR}/swift-${filter}.log"
  run_and_capture \
    "Swift ${filter}" \
    "${filter_log}" \
    bash -c 'cd "$1" && swift test --skip-build --filter "$2"' bash "${MAC_APP_DIR}" "${filter}"
  cat "${filter_log}" >>"${SWIFT_FILTER_LOG}"
  require_output "${filter}" "${filter_log}"
  require_output "Test Suite '${filter}'" "${filter_log}"
  require_no_failure_output "${filter_log}"
  require_no_skipped_swift_tests "${filter_log}"
done

require_output "Test Suite 'FileCryptoTests' passed" "${SWIFT_FILTER_LOG}"
require_output "Test Suite 'AttachmentDescriptorTests' passed" "${SWIFT_FILTER_LOG}"
require_output "Test Suite 'HTTPAttachmentServiceTests' passed" "${SWIFT_FILTER_LOG}"
require_output "Test Suite 'DMCoordinatorTests' passed" "${SWIFT_FILTER_LOG}"

for forbidden_suite in \
  "LiveGroupE2ETests" \
  "LiveOfflineDeliveryE2ETests" \
  "LiveAttachmentE2ETests"
do
  require_output_absent "${forbidden_suite}" "${COMBINED_LOG}"
done

echo "task-7-r7 targeted tests: PASS"
