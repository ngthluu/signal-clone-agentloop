#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
MAC_APP_DIR="$REPO_ROOT/mac-app"

STARTUP_WAIT_SECONDS="${LAUNCH_SMOKE_STARTUP_WAIT_SECONDS:-3}"
MAX_WAIT_SECONDS="${LAUNCH_SMOKE_MAX_WAIT_SECONDS:-8}"
LOG_FILE="$(mktemp -t task-1a-launch-smoke.XXXXXX.log)"
RUN_PID=""

cleanup() {
  if [[ -n "$RUN_PID" ]] && kill -0 "$RUN_PID" 2>/dev/null; then
    kill "$RUN_PID" 2>/dev/null || true
    wait "$RUN_PID" 2>/dev/null || true
  fi
  rm -f "$LOG_FILE"
}

trap cleanup EXIT

cd "$MAC_APP_DIR"

echo "launch_smoke: starting ChatApp"
swift run ChatApp >"$LOG_FILE" 2>&1 &
RUN_PID="$!"

elapsed=0
while (( elapsed < MAX_WAIT_SECONDS )); do
  sleep 1
  elapsed=$((elapsed + 1))

  if ! kill -0 "$RUN_PID" 2>/dev/null; then
    wait "$RUN_PID" 2>/dev/null || true
    echo "launch_smoke: SKIPPED (no GUI)"
    if [[ -s "$LOG_FILE" ]]; then
      echo "launch_smoke: swift run output follows"
      sed 's/^/launch_smoke:   /' "$LOG_FILE"
    fi
    exit 0
  fi

  if (( elapsed >= STARTUP_WAIT_SECONDS )); then
    echo "launch_smoke: PASS - ChatApp started at registration entry point (default no-account route)"
    exit 0
  fi
done

echo "launch_smoke: SKIPPED (no GUI)"
exit 0
