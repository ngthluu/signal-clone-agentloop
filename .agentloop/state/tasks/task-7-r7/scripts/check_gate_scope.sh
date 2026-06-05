#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

LOG_PATH="${TASK_DIR}/gate_scope_audit.log"
: >"${LOG_PATH}"
exec > >(tee "${LOG_PATH}") 2>&1

trap 'fail "scope audit failed at line ${LINENO}"' ERR

require_cmd bash
require_cmd grep
require_cmd sed
require_file "${REPO_ROOT}/verify.sh"
require_file "${REPO_ROOT}/.agentloop/verify.sh"

task_scripts=(
  "${TASK_DIR}/scripts/common.sh"
  "${TASK_DIR}/scripts/run_targeted_tests.sh"
  "${TASK_DIR}/scripts/run_live_dm_roundtrip.sh"
  "${TASK_DIR}/scripts/audit_live_dm_storage.sh"
  "${TASK_DIR}/scripts/check_gate_scope.sh"
  "${TASK_DIR}/verify.sh"
)

for script in "${task_scripts[@]}"; do
  require_file "${script}"
  bash -n "${script}"
done

grep_absent() {
  local pattern="${1:-}"
  local label="${2:-forbidden scope pattern}"
  [[ -n "${pattern}" ]] || fail "grep_absent needs a pattern"

  local matches status
  set +e
  matches="$(LC_ALL=C grep -n -E -- "${pattern}" "${task_scripts[@]}")"
  status=$?
  set -e

  if [[ "${status}" -eq 0 ]]; then
    printf '%s\n' "${matches}" >&2
    fail "${label}"
  fi
  [[ "${status}" -eq 1 ]] || fail "grep failed while checking ${label}"
}

grep_present_file() {
  local pattern="${1:-}"
  local path="${2:-}"
  local label="${3:-required proof}"
  [[ -n "${pattern}" ]] || fail "grep_present_file needs a pattern"
  require_file "${path}"
  LC_ALL=C grep -n -E -- "${pattern}" "${path}" || fail "missing ${label}"
}

prove_root_gate_is_aggregate() {
  local root_gate="${REPO_ROOT}/verify.sh"
  local aggregate_gate="${REPO_ROOT}/.agentloop/verify.sh"
  local dot_agent=".agentloop"
  local gate_name="verify.sh"
  local swift_word="sw""ift"
  local test_word="te""st"

  echo "task-7-r7 scope: root gate proof"
  grep_present_file \
    "exec[[:space:]]+.*[$][{]SCRIPT_DIR[}]/${dot_agent}/${gate_name}" \
    "${root_gate}" \
    "repo-root gate delegation to agentloop aggregate"
  grep_present_file \
    "cargo[[:space:]]+${test_word}" \
    "${aggregate_gate}" \
    "aggregate backend test step"
  grep_present_file \
    "${swift_word}[[:space:]]+${test_word}([^[:alnum:]_-]|$)" \
    "${aggregate_gate}" \
    "aggregate Swift test step"
  echo "task-7-r7 scope: repo-root verify.sh delegates to .agentloop/verify.sh"
  echo "task-7-r7 scope: .agentloop/verify.sh is a broad aggregate runner, not this task gate"
}

check_no_root_or_sibling_gate_calls() {
  local gate_name="ver""ify.sh"
  local dot_agent=".agentloop"
  local state_path="${dot_agent}/state/tasks"
  local sibling_task="task-[^/[:space:]]+"

  grep_absent \
    "^[[:space:]]*(bash|sh|source|\\.|exec)[[:space:]]+([^#[:space:]]*/)?${gate_name}([[:space:]]|$)" \
    "repo-root aggregate gate call found"
  grep_absent \
    "^[[:space:]]*(bash|sh|source|\\.|exec)[[:space:]]+([^#[:space:]]*/)?${dot_agent}/${gate_name}([[:space:]]|$)" \
    "agentloop aggregate gate call found"
  grep_absent \
    "^[[:space:]]*(bash|sh|source|\\.|exec)[[:space:]]+([^#[:space:]]*/)?(${state_path}/)?${sibling_task}/${gate_name}([[:space:]]|$)" \
    "sibling task gate call found"
}

check_no_bare_swift_test() {
  local swift_word="sw""ift"
  local test_word="te""st"
  local matches filtered status

  set +e
  matches="$(LC_ALL=C grep -n -E -- "(^|[^[:alnum:]_./-])${swift_word}[[:space:]]+${test_word}([^[:alnum:]_-]|$)" "${task_scripts[@]}")"
  status=$?
  set -e
  [[ "${status}" -eq 0 || "${status}" -eq 1 ]] || fail "grep failed while checking scoped Swift commands"
  [[ "${status}" -eq 0 ]] || return 0

  filtered="$(printf '%s\n' "${matches}" | LC_ALL=C grep -v -- '--filter' || true)"
  if [[ -n "${filtered}" ]]; then
    printf '%s\n' "${filtered}" >&2
    fail "unscoped Swift test command found"
  fi
}

check_no_forbidden_live_filters() {
  local live_prefix="Live"
  local group_name="${live_prefix}Group"
  local offline_name="${live_prefix}OfflineDeliveryE2ETests"
  local broad_attachment="${live_prefix}AttachmentE2ETests"
  local matches filtered status

  set +e
  matches="$(LC_ALL=C grep -n -E -- "(${group_name})|(${offline_name})|(${broad_attachment})" "${task_scripts[@]}")"
  status=$?
  set -e
  [[ "${status}" -eq 0 || "${status}" -eq 1 ]] || fail "grep failed while checking forbidden live suites"
  [[ "${status}" -eq 0 ]] || return 0

  filtered="$(
    printf '%s\n' "${matches}" |
      LC_ALL=C grep -v -E '/run_targeted_tests[.]sh:[0-9]+:[[:space:]]*"Live(GroupE2ETests|OfflineDeliveryE2ETests|AttachmentE2ETests)"' |
      LC_ALL=C grep -v -E '/run_targeted_tests[.]sh:[0-9]+:[[:space:]]*for forbidden_suite in' || true
  )"
  if [[ -n "${filtered}" ]]; then
    printf '%s\n' "${filtered}" >&2
    fail "forbidden live suite reference found"
  fi
}

prove_root_gate_is_aggregate
check_no_root_or_sibling_gate_calls
check_no_bare_swift_test
check_no_forbidden_live_filters

echo "task-7-r7 scope audit: PASS"
