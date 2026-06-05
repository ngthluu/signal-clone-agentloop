#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/.agentloop/state/tasks"
BACKLOG_JSON="$REPO_ROOT/.agentloop/state/backlog.json"
LAST_GATE="$REPO_ROOT/.agentloop/state/last_gate.txt"

if [[ ! -f "$BACKLOG_JSON" && -f "$SCRIPT_DIR/../../../state/backlog.json" ]]; then
  BACKLOG_JSON="$(cd "$SCRIPT_DIR/../../.." && pwd)/state/backlog.json"
fi

mkdir -p "$(dirname "$LAST_GATE")"
exec > >(tee "$LAST_GATE") 2>&1

sorted_scripts=()
if [[ ! -f "$BACKLOG_JSON" ]]; then
  echo "verify: FAIL (backlog)"
  echo "reason: backlog not found: $REPO_ROOT/.agentloop/state/backlog.json"
  exit 1
fi

while IFS= read -r task_id; do
  verify_script="$TASKS_DIR/$task_id/verify.sh"
  if [[ -f "$verify_script" ]]; then
    sorted_scripts+=("$verify_script")
  fi
done < <(jq -r '.items[]?.id' "$BACKLOG_JSON")

if [[ "${AGENTLOOP_VERIFY_LIST_ONLY:-}" == "1" ]]; then
  for verify_script in "${sorted_scripts[@]}"; do
    printf '%s\n' "${verify_script#$REPO_ROOT/}"
  done
  exit 0
fi

for verify_script in "${sorted_scripts[@]}"; do
  task_name="$(basename "$(dirname "$verify_script")")"
  echo "verify: RUN ($task_name)"

  if ! (cd "$REPO_ROOT" && bash "$verify_script"); then
    echo "verify: FAIL ($task_name)"
    exit 1
  fi
done

if [[ "${#sorted_scripts[@]}" -eq 0 ]]; then
  echo "verify: no per-task verify scripts found"
fi

echo "verify: PASS"
exit 0
