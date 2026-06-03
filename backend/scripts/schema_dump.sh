#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <sqlite-db-path>" >&2
  echo "       or set DATABASE_PATH, DATABASE_URL, BACKEND_DB_PATH, or SQLITE_DB_PATH" >&2
}

db_input="${1:-${DATABASE_PATH:-${DATABASE_URL:-${BACKEND_DB_PATH:-${SQLITE_DB_PATH:-}}}}}"
if [[ -z "${db_input}" ]]; then
  usage
  exit 2
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "error: sqlite3 CLI is required" >&2
  exit 2
fi

db_path="${db_input}"
case "${db_path}" in
  sqlite://*) db_path="${db_path#sqlite://}" ;;
  sqlite:*) db_path="${db_path#sqlite:}" ;;
esac

if [[ "${db_path}" == ":memory:" ]]; then
  echo "error: schema_dump.sh requires a file-backed SQLite database" >&2
  exit 2
fi

if [[ ! -f "${db_path}" ]]; then
  echo "error: SQLite database not found: ${db_path}" >&2
  exit 2
fi

expected_columns="id
username
identity_public_key
created_at"

actual_columns="$(sqlite3 -noheader -batch "${db_path}" "SELECT name FROM pragma_table_info('users') ORDER BY cid;")"
if [[ "${actual_columns}" != "${expected_columns}" ]]; then
  echo "error: users table columns do not match the public-account schema" >&2
  echo "expected:" >&2
  printf '%s\n' "${expected_columns}" >&2
  echo "actual:" >&2
  printf '%s\n' "${actual_columns}" >&2
  exit 1
fi

row_count="$(sqlite3 -noheader -batch "${db_path}" "SELECT COUNT(*) FROM users;")"
if [[ "${row_count}" -lt 1 ]]; then
  echo "error: users table has no rows to inspect" >&2
  exit 1
fi

schema_dump="$(sqlite3 -header -column -batch "${db_path}" "PRAGMA table_info(users);")"
row_dump="$(sqlite3 -header -column -batch "${db_path}" "SELECT id, username, identity_public_key, created_at FROM users ORDER BY created_at, id LIMIT 1;")"
inspection_dump="${schema_dump}
${row_dump}"

if printf '%s\n' "${inspection_dump}" | grep -Eiq 'private|secret'; then
  echo "error: forbidden private/secret marker found in users schema or sample row" >&2
  printf '%s\n' "${inspection_dump}" >&2
  exit 1
fi

echo "PRAGMA table_info(users)"
printf '%s\n' "${schema_dump}"
echo
echo "sample stored user row"
printf '%s\n' "${row_dump}"
echo
echo "confirmed no private/secret columns or private material in users schema or sample row"
