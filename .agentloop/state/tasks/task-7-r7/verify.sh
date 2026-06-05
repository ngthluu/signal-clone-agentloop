#!/usr/bin/env bash

set -euo pipefail

TASK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./scripts/common.sh
source "${TASK_DIR}/scripts/common.sh"

LOG_PATH="${TASK_DIR}/scoped_gate_run.log"
: >"${LOG_PATH}"
exec > >(tee "${LOG_PATH}") 2>&1

trap 'fail "verify orchestrator failed at line ${LINENO}"' ERR

require_cmd bash
require_cmd grep
require_file "${TASK_DIR}/scripts/common.sh"
require_file "${TASK_DIR}/scripts/run_targeted_tests.sh"
require_file "${TASK_DIR}/scripts/run_live_dm_roundtrip.sh"
require_file "${TASK_DIR}/scripts/audit_live_dm_storage.sh"

task_scripts=(
  "${TASK_DIR}/scripts/common.sh"
  "${TASK_DIR}/scripts/run_targeted_tests.sh"
  "${TASK_DIR}/scripts/run_live_dm_roundtrip.sh"
  "${TASK_DIR}/scripts/audit_live_dm_storage.sh"
  "${TASK_DIR}/verify.sh"
)

for script in "${task_scripts[@]}"; do
  bash -n "${script}"
done

check_absent_pattern() {
  local pattern="${1:-}"
  local label="${2:-forbidden pattern}"
  [[ -n "${pattern}" ]] || fail "check_absent_pattern needs a pattern"

  local matches
  set +e
  matches="$(LC_ALL=C grep -n -E -- "${pattern}" "${task_scripts[@]}")"
  local status=$?
  set -e
  if [[ "${status}" -eq 0 ]]; then
    printf '%s\n' "${matches}" >&2
    fail "${label}"
  fi
  [[ "${status}" -eq 1 ]] || fail "grep failed while checking ${label}"
}

check_no_root_aggregator_calls() {
  local agentloop_dir=".agentloop"
  local verify_name="verify.sh"
  local agentloop_verify="${agentloop_dir}/${verify_name}"

  check_absent_pattern \
    "^[[:space:]]*(bash|sh|source|\\.)[[:space:]]+([^#[:space:]]*/)?${verify_name}([[:space:]]|$)" \
    "repo-root verify.sh aggregator call found"
  check_absent_pattern \
    "^[[:space:]]*(bash|sh|source|\\.)[[:space:]]+([^#[:space:]]*/)?${agentloop_verify}([[:space:]]|$)" \
    "agentloop verify.sh aggregator call found"
}

check_no_bare_swift_test() {
  local matches filtered
  set +e
  matches="$(LC_ALL=C grep -n -E -- '(^|[^[:alnum:]_./-])swift[[:space:]]+test([^[:alnum:]_-]|$)' "${task_scripts[@]}")"
  local status=$?
  set -e
  [[ "${status}" -eq 0 || "${status}" -eq 1 ]] || fail "grep failed while checking Swift test scope"
  [[ "${status}" -eq 0 ]] || return 0

  filtered="$(printf '%s\n' "${matches}" | LC_ALL=C grep -v -- '--filter' || true)"
  if [[ -n "${filtered}" ]]; then
    printf '%s\n' "${filtered}" >&2
    fail "unscoped Swift test command found"
  fi
}

check_no_forbidden_live_filters() {
  local live="Live"
  local group="${live}Group"
  local offline="${live}OfflineDelivery"
  local attachment="${live}Attachment"
  local forbidden="${group}E2ETests|${offline}E2ETests|${group}|${attachment}E2ETests"
  check_absent_pattern \
    ".*--filter[[:space:]=]+.*(${forbidden})|.*(${forbidden}).*--filter[[:space:]=]+" \
    "forbidden group/offline/broad live suite filter found"
}

check_no_root_aggregator_calls
check_no_bare_swift_test
check_no_forbidden_live_filters

bash "${TASK_DIR}/scripts/run_targeted_tests.sh"
bash "${TASK_DIR}/scripts/run_live_dm_roundtrip.sh"
bash "${TASK_DIR}/scripts/audit_live_dm_storage.sh"

trap - ERR
echo "task-7-r7 verify: PASS"
