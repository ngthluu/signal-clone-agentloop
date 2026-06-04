#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <sqlite-db-path>" >&2
  echo "       or set DATABASE_PATH, DATABASE_URL, BACKEND_DB_PATH, or SQLITE_DB_PATH" >&2
}

quote_sql_string() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\'}"
}

classify_column() {
  local table="$1"
  local column="$2"

  case "${table}.${column}" in
    messages.sender_id|messages.recipient_id)
      echo "routing-metadata"
      ;;
    messages.ciphertext|attachments.ciphertext)
      echo "opaque-ciphertext"
      ;;
    attachments.uploader_id|attachments.byte_size)
      echo "routing-metadata"
      ;;
    users.identity_public_key|device_keys.x25519_public_key)
      echo "public-key"
      ;;
    device_keys.key_signature)
      echo "signature"
      ;;
    sessions.token)
      echo "session-token"
      ;;
    auth_challenges.nonce)
      echo "random-nonce"
      ;;
    *.created_at|*.expires_at)
      echo "timestamp"
      ;;
    *)
      echo "identifier"
      ;;
  esac
}

assert_columns_exactly() {
  local table="$1"
  local expected_csv="$2"
  local actual_csv="$3"

  if [[ "${actual_csv}" != "${expected_csv}" ]]; then
    echo "error: ${table} table columns do not match the zero-knowledge schema" >&2
    echo "expected: ${expected_csv}" >&2
    echo "actual:   ${actual_csv}" >&2
    exit 1
  fi
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
  echo "error: zk_relay_audit.sh requires a file-backed SQLite database" >&2
  exit 2
fi

if [[ ! -f "${db_path}" ]]; then
  echo "error: SQLite database not found: ${db_path}" >&2
  exit 2
fi

tables="$(sqlite3 -noheader -batch "${db_path}" \
  "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != '_sqlx_migrations' ORDER BY name;")"

if [[ -z "${tables}" ]]; then
  echo "error: no application tables found in ${db_path}" >&2
  exit 1
fi

echo "ZERO-KNOWLEDGE SCHEMA AUDIT"
echo "database: ${db_path}"
echo

while IFS= read -r table; do
  [[ -z "${table}" ]] && continue

  quoted_table="$(quote_sql_string "${table}")"
  columns="$(sqlite3 -noheader -batch "${db_path}" "SELECT name FROM pragma_table_info(${quoted_table}) ORDER BY cid;")"
  lower_columns="$(printf '%s\n' "${columns}" | tr '[:upper:]' '[:lower:]')"
  actual_csv="$(printf '%s\n' "${lower_columns}" | paste -sd, -)"

  while IFS= read -r column; do
    [[ -z "${column}" ]] && continue

    if printf '%s\n' "${column}" | grep -Eiw '^(plaintext|body|text|content|message|cleartext|private|secret|password|passphrase|privkey|private_key|secret_key|seed|mnemonic)$' >/dev/null; then
      echo "error: forbidden column found: ${table}.${column}" >&2
      exit 1
    fi

    if printf '%s\n' "${column}" | grep -Ei 'private|secret|password|privkey|mnemonic' >/dev/null; then
      echo "error: forbidden column found: ${table}.${column}" >&2
      exit 1
    fi
  done <<< "${lower_columns}"

  case "${table}" in
    messages)
      assert_columns_exactly "${table}" "id,sender_id,recipient_id,ciphertext,created_at" "${actual_csv}"
      ;;
    device_keys)
      assert_columns_exactly "${table}" "user_id,x25519_public_key,key_signature,created_at" "${actual_csv}"
      ;;
    users)
      assert_columns_exactly "${table}" "id,username,identity_public_key,created_at" "${actual_csv}"
      ;;
  esac

  echo "table: ${table}"
  echo "PRAGMA table_info(${table})"
  sqlite3 -header -column -batch "${db_path}" "PRAGMA table_info(${quoted_table});"
  echo "classification:"
  while IFS= read -r column; do
    [[ -z "${column}" ]] && continue
    label="$(classify_column "${table}" "${column}")"
    printf '  - %s: %s\n' "${column}" "${label}"
  done <<< "${lower_columns}"
  echo
done <<< "${tables}"

echo "ZERO-KNOWLEDGE SCHEMA AUDIT: PASS — no plaintext or private-key columns in any table"
