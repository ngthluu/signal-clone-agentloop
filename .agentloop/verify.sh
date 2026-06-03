#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/.agentloop/state/tasks"

shopt -s nullglob
task_verify_scripts=("$TASKS_DIR"/*/verify.sh)
shopt -u nullglob

for verify_script in "${task_verify_scripts[@]}"; do
  task_name="$(basename "$(dirname "$verify_script")")"
  echo "verify: RUN ($task_name)"

  if ! (cd "$REPO_ROOT" && bash "$verify_script"); then
    echo "verify: FAIL ($task_name)"
    exit 1
  fi
done

echo "verify: PASS"
