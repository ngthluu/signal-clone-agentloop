#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$WORKSPACE_ROOT/.agentloop/state/tasks"
LAST_GATE="$WORKSPACE_ROOT/.agentloop/state/last_gate.txt"

mkdir -p "$(dirname "$LAST_GATE")"
exec > >(tee "$LAST_GATE") 2>&1

ran_any=0

if [[ -d "$TASKS_DIR" ]]; then
  while IFS= read -r task_dir; do
    task_id="$(basename "$task_dir")"
    task_verify="$task_dir/verify.sh"

    if [[ ! -f "$task_verify" ]]; then
      continue
    fi

    ran_any=1
    echo "[$task_id] RUN"

    if /bin/bash "$task_verify"; then
      echo "[$task_id] PASS"
    else
      echo "[$task_id] FAIL"
      echo "verify: FAIL ($task_id)"
      exit 1
    fi
  done < <(find "$TASKS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
fi

if [[ "$ran_any" -eq 0 ]]; then
  echo "verify: no per-task verify scripts found"
fi

echo "verify: PASS"
exit 0
