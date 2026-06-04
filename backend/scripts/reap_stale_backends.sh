#!/usr/bin/env bash
set -euo pipefail

readonly BACKEND_NAME="test-chat-backend"
readonly TERM_WAIT_SECONDS="${REAP_STALE_BACKENDS_TERM_WAIT_SECONDS:-2}"

target_pids=()

while read -r pid ppid command; do
  [[ -n "${pid:-}" ]] || continue
  [[ "${ppid}" == "1" ]] || continue

  executable="${command%% *}"
  executable_name="${executable##*/}"
  [[ "${executable_name}" == "${BACKEND_NAME}" ]] || continue

  target_pids+=("${pid}")
done < <(ps -axo pid=,ppid=,command=)

if [[ "${#target_pids[@]}" -eq 0 ]]; then
  echo "reaped 0 stale ${BACKEND_NAME} process(es)"
  exit 0
fi

for pid in "${target_pids[@]}"; do
  kill -TERM "${pid}" 2>/dev/null || true
done

deadline=$((SECONDS + TERM_WAIT_SECONDS))
while [[ "${SECONDS}" -lt "${deadline}" ]]; do
  live_pids=()
  for pid in "${target_pids[@]}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      live_pids+=("${pid}")
    fi
  done

  [[ "${#live_pids[@]}" -gt 0 ]] || break
  sleep 0.1
done

for pid in "${target_pids[@]}"; do
  kill -0 "${pid}" 2>/dev/null || continue
  kill -KILL "${pid}" 2>/dev/null || true
done

reaped_count=0
for pid in "${target_pids[@]}"; do
  if ! kill -0 "${pid}" 2>/dev/null; then
    reaped_count=$((reaped_count + 1))
  fi
done

echo "reaped ${reaped_count} stale ${BACKEND_NAME} process(es)"
