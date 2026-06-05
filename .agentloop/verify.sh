#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAST_GATE="$REPO_ROOT/.agentloop/state/last_gate.txt"

mkdir -p "$(dirname "$LAST_GATE")"
exec > >(tee "$LAST_GATE") 2>&1

echo "verify: backend build"
(cd "$REPO_ROOT/backend" && cargo build)

echo "verify: backend tests"
(cd "$REPO_ROOT/backend" && cargo test)

echo "verify: mac app build"
(cd "$REPO_ROOT/mac-app" && swift build)

echo "verify: mac app tests"
(cd "$REPO_ROOT/mac-app" && env -u CHATAPP_LIVE_BACKEND_URL swift test)

echo "verify: PASS"
