#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/.agentloop/state/tasks"
LAST_GATE="$REPO_ROOT/.agentloop/state/last_gate.txt"

mkdir -p "$(dirname "$LAST_GATE")"
exec > >(tee "$LAST_GATE") 2>&1

shopt -s nullglob
task_verify_scripts=("$TASKS_DIR"/*/verify.sh)
shopt -u nullglob

sorted_scripts=()
if [[ "${#task_verify_scripts[@]}" -gt 0 ]]; then
  while IFS= read -r verify_script; do
    sorted_scripts+=("$verify_script")
  done < <(printf '%s\n' "${task_verify_scripts[@]}" | sort)
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
