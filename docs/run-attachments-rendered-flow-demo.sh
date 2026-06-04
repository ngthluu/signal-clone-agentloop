#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/backend"
OUT_DIR="${1:-}"

if [[ -z "${OUT_DIR}" ]]; then
  OUT_DIR="$(mktemp -d -t chatapp-attachments-rendered-flow.XXXXXX)"
else
  mkdir -p "${OUT_DIR}"
fi

PORT="$(
  python3 - <<'PY'
import socket
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.bind(("127.0.0.1", 0))
    print(s.getsockname()[1])
PY
)"
BASE_URL="http://127.0.0.1:${PORT}"
DB_PATH="${OUT_DIR}/backend.sqlite3"
LOG_PATH="${OUT_DIR}/backend.log"
ARTIFACTS_PATH="${OUT_DIR}/demo-artifacts.env"
BACKEND_PID=""

cleanup() {
  if [[ -n "${BACKEND_PID}" ]] && kill -0 "${BACKEND_PID}" 2>/dev/null; then
    kill "${BACKEND_PID}" 2>/dev/null || true
    wait "${BACKEND_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

"${BACKEND_DIR}/scripts/reap_stale_backends.sh"

(
  cd "${BACKEND_DIR}"
  cargo run --quiet -- --db-path "${DB_PATH}" --port "${PORT}" >"${LOG_PATH}" 2>&1
) &
BACKEND_PID="$!"

for _ in {1..100}; do
  if curl -fsS --max-time 1 "${BASE_URL}/health" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "${BACKEND_PID}" 2>/dev/null; then
    echo "backend exited before becoming healthy; log follows" >&2
    cat "${LOG_PATH}" >&2 || true
    exit 1
  fi
  sleep 0.1
done

curl -fsS --max-time 2 "${BASE_URL}/health" >/dev/null

DEMO_BIN="${OUT_DIR}/attachments-live-flow-demo"
swiftc -parse-as-library "${ROOT_DIR}/docs/attachments_live_flow_demo.swift" -o "${DEMO_BIN}"
"${DEMO_BIN}" "${BASE_URL}" "${OUT_DIR}" | tee "${ARTIFACTS_PATH}"

# shellcheck disable=SC1090
source "${ARTIFACTS_PATH}"

cmp -s "${DM_ORIGINAL}" "${DM_DOWNLOADED}"
cmp -s "${GROUP_ORIGINAL}" "${GROUP_DOWNLOADED}"

grep -q "ATTACHMENT_RENDERED_FLOW_SENTINEL_" "${DM_DOWNLOADED}"
grep -q "ATTACHMENT_RENDERED_FLOW_SENTINEL_" "${GROUP_DOWNLOADED}"

echo "attachments rendered flow demo: PASS"
echo "artifacts: ${OUT_DIR}"
