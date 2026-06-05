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
require_file "${TASK_DIR}/scripts/check_gate_scope.sh"
require_file "${TASK_DIR}/scripts/run_targeted_tests.sh"
require_file "${TASK_DIR}/scripts/run_live_dm_roundtrip.sh"
require_file "${TASK_DIR}/scripts/audit_live_dm_storage.sh"

task_scripts=(
  "${TASK_DIR}/scripts/common.sh"
  "${TASK_DIR}/scripts/check_gate_scope.sh"
  "${TASK_DIR}/scripts/run_targeted_tests.sh"
  "${TASK_DIR}/scripts/run_live_dm_roundtrip.sh"
  "${TASK_DIR}/scripts/audit_live_dm_storage.sh"
  "${TASK_DIR}/verify.sh"
)

for script in "${task_scripts[@]}"; do
  bash -n "${script}"
done

bash "${TASK_DIR}/scripts/check_gate_scope.sh"
bash "${TASK_DIR}/scripts/run_targeted_tests.sh"
bash "${TASK_DIR}/scripts/run_live_dm_roundtrip.sh"
bash "${TASK_DIR}/scripts/audit_live_dm_storage.sh"

trap - ERR
echo "task-7-r7 verify: PASS"
