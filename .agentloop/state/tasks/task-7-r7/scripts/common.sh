#!/usr/bin/env bash

set -euo pipefail

COMMON_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR="$(cd "${COMMON_SH_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${TASK_DIR}/../../../.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
MAC_APP_DIR="${REPO_ROOT}/mac-app"

fail() {
  echo "task-7-r7 verify: FAIL" >&2
  if [[ "$#" -gt 0 ]]; then
    printf '%s\n' "$*" >&2
  fi
  exit 1
}

require_cmd() {
  local name="${1:-}"
  [[ -n "${name}" ]] || fail "require_cmd needs a command name"
  command -v "${name}" >/dev/null 2>&1 || fail "missing required command: ${name}"
}

task_abs_path() {
  local path="${1:-}"
  [[ -n "${path}" ]] || fail "empty path"
  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s\n' "${REPO_ROOT}/${path}"
  fi
}

require_file() {
  local path
  path="$(task_abs_path "${1:-}")"
  [[ -f "${path}" ]] || fail "required file is missing: ${path}"
}

require_nonempty_file() {
  local path
  path="$(task_abs_path "${1:-}")"
  [[ -s "${path}" ]] || fail "required file is missing or empty: ${path}"
}

require_absent_bytes() {
  local needle_file haystack_file label
  needle_file="$(task_abs_path "${1:-}")"
  haystack_file="$(task_abs_path "${2:-}")"
  label="${3:-${haystack_file}}"
  require_nonempty_file "${needle_file}"
  require_file "${haystack_file}"
  require_cmd perl

  if NEEDLE_FILE="${needle_file}" HAYSTACK_FILE="${haystack_file}" perl -e '
    use strict;
    use warnings;
    local $/;
    open(my $needle_fh, "<:raw", $ENV{"NEEDLE_FILE"}) or die $!;
    my $needle = <$needle_fh>;
    open(my $haystack_fh, "<:raw", $ENV{"HAYSTACK_FILE"}) or die $!;
    my $haystack = <$haystack_fh>;
    exit(index($haystack, $needle) >= 0 ? 1 : 0);
  '; then
    return 0
  fi

  fail "forbidden bytes found in ${label}"
}

require_absent_text() {
  local text="${1:-}" path label
  path="$(task_abs_path "${2:-}")"
  label="${3:-${path}}"
  [[ -n "${text}" ]] || fail "require_absent_text needs non-empty text"
  require_file "${path}"

  if LC_ALL=C grep -a -F -q -- "${text}" "${path}"; then
    fail "forbidden text found in ${label}"
  fi
}

pick_free_port() {
  if command -v ruby >/dev/null 2>&1; then
    ruby -rsocket -e 'server = TCPServer.new("127.0.0.1", 0); puts server.addr[1]; server.close'
    return
  fi

  if command -v perl >/dev/null 2>&1; then
    perl -MIO::Socket::INET -e '$s = IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => 0, Proto => "tcp", Listen => 1) or die $!; print $s->sockport . "\n"; close($s)'
    return
  fi

  require_cmd lsof
  local port
  for _ in $(seq 1 100); do
    port=$((49152 + RANDOM % 12000))
    if ! lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
      printf '%s\n' "${port}"
      return
    fi
  done

  fail "could not find a free TCP port"
}

backend_pids_for_db() {
  local db_path="${1:-}"
  [[ -n "${db_path}" ]] || fail "backend_pids_for_db needs a DB path"

  ps axww -o pid= -o command= | while read -r pid command; do
    [[ -n "${pid:-}" ]] || continue
    [[ "${command}" == *"test-chat-backend"* || "${command}" == *"cargo run"* ]] || continue
    [[ "${command}" == *"--db-path ${db_path}"* || "${command}" == *"--db-path=${db_path}"* ]] || continue
    printf '%s\n' "${pid}"
  done
}

require_no_backend_for_db() {
  local db_path="${1:-}"
  [[ -n "${db_path}" ]] || fail "require_no_backend_for_db needs a DB path"

  local pids
  pids="$(backend_pids_for_db "${db_path}" || true)"
  [[ -z "${pids}" ]] || fail "backend process still running for ${db_path}: ${pids}"
}

wait_for_backend_health() {
  local port="${1:-}"
  local log_path="${2:-}"
  local pid="${3:-}"
  [[ -n "${port}" ]] || fail "wait_for_backend_health needs a port"
  require_cmd curl

  local url="http://127.0.0.1:${port}/health"
  local deadline=$((SECONDS + 60))
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    if [[ -n "${pid}" ]] && ! kill -0 "${pid}" 2>/dev/null; then
      [[ -n "${log_path}" && -f "${log_path}" ]] && tail -n 80 "${log_path}" >&2 || true
      fail "backend exited before health check passed"
    fi
    sleep 0.25
  done

  [[ -n "${log_path}" && -f "${log_path}" ]] && tail -n 80 "${log_path}" >&2 || true
  fail "backend did not become healthy at ${url}"
}

start_backend() {
  local db_path="${1:-}"
  local port="${2:-}"
  local log_path="${3:-}"
  [[ -n "${db_path}" ]] || fail "start_backend needs a DB path"
  [[ -n "${port}" ]] || fail "start_backend needs a port"
  [[ -n "${log_path}" ]] || fail "start_backend needs a log path"
  require_cmd cargo
  require_cmd curl
  require_file "${BACKEND_DIR}/Cargo.toml"
  mkdir -p "$(dirname "${db_path}")" "$(dirname "${log_path}")"
  require_no_backend_for_db "${db_path}"

  (
    cd "${BACKEND_DIR}"
    cargo run -- --db-path "${db_path}" --port "${port}"
  ) >"${log_path}" 2>&1 &

  BACKEND_PID=$!
  BACKEND_URL="http://127.0.0.1:${port}"
  export BACKEND_PID BACKEND_URL
  wait_for_backend_health "${port}" "${log_path}" "${BACKEND_PID}"
}

stop_backend() {
  local pid="${1:-${BACKEND_PID:-}}"
  local db_path="${2:-}"

  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    kill -TERM "${pid}" 2>/dev/null || true
  fi

  if [[ -n "${db_path}" ]]; then
    local db_pids
    db_pids="$(backend_pids_for_db "${db_path}" || true)"
    if [[ -n "${db_pids}" ]]; then
      while read -r db_pid; do
        [[ -n "${db_pid}" ]] || continue
        kill -TERM "${db_pid}" 2>/dev/null || true
      done <<<"${db_pids}"
    fi
  fi

  if [[ -n "${pid}" ]]; then
    wait "${pid}" 2>/dev/null || true
  fi

  local deadline=$((SECONDS + 10))
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    local still_running=""
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      still_running=1
    fi
    if [[ -n "${db_path}" && -n "$(backend_pids_for_db "${db_path}" || true)" ]]; then
      still_running=1
    fi
    [[ -n "${still_running}" ]] || break
    sleep 0.2
  done

  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    kill -KILL "${pid}" 2>/dev/null || true
    wait "${pid}" 2>/dev/null || true
  fi

  if [[ -n "${db_path}" ]]; then
    local remaining_pids
    remaining_pids="$(backend_pids_for_db "${db_path}" || true)"
    if [[ -n "${remaining_pids}" ]]; then
      while read -r db_pid; do
        [[ -n "${db_pid}" ]] || continue
        kill -KILL "${db_pid}" 2>/dev/null || true
      done <<<"${remaining_pids}"
    fi
  fi
}

cleanup_file_and_sidecars() {
  local path
  path="$(task_abs_path "${1:-}")"
  rm -f "${path}" "${path}-wal" "${path}-shm" "${path}-journal"
}
