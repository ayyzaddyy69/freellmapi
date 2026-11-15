#!/usr/bin/env bash
# Starts FreeLLMAPI in the background each time the Codespace starts.
# The database, encryption key and login live in $FREELLMAPI_HOME, which
# survives stop/start.
set -euo pipefail
cd "$(dirname "$0")/.."

HOME_DIR="${FREELLMAPI_HOME:-/workspaces/.freellmapi}"
SECRETS="$HOME_DIR/secrets.env"
mkdir -p "$HOME_DIR"

ready() { curl -sf -o /dev/null http://localhost:3001/api/auth/status; }
# Our instance always has an admin account, so "needsSetup":true means some
# other copy (usually `npm run dev`, which uses a separate empty database)
# holds port 3001. Stop it so the real one can start.
foreign_instance() { curl -sf http://localhost:3001/api/auth/status | grep -q '"needsSetup":true'; }
if foreign_instance; then
  echo "Another FreeLLMAPI copy (dev mode, empty database) is using port 3001; stopping it."
  pkill -f "tsx watch" || true
  pkill -f "bin/vite" || true
  sleep 3
fi

# Build if the install step did not finish (e.g. it was interrupted).
if [ ! -f server/dist/index.js ]; then
  bash .devcontainer/install-freellmapi.sh
fi

# First run: generate the encryption key and dashboard login once.
if [ ! -f "$SECRETS" ]; then
  umask 077
  {
    echo "ENCRYPTION_KEY=$(openssl rand -hex 32)"
    echo "ADMIN_EMAIL=admin@freellmapi.local"
    echo "ADMIN_PASSWORD=$(openssl rand -hex 10)"
  } > "$SECRETS"
fi

set -a
# shellcheck disable=SC1090
. "$SECRETS"
set +a

print_login() {
  echo ""
  echo "=============================================="
  echo " FreeLLMAPI is running on port 3001."
  echo " Email:    $ADMIN_EMAIL"
  echo " Password: $ADMIN_PASSWORD"
  echo " Open: Ports tab -> link next to 3001"
  echo "=============================================="
}

if ready; then
  echo "FreeLLMAPI is already running"
  print_login
  exit 0
fi

export NODE_ENV=production PORT=3001
export FREEAPI_DB_PATH="$HOME_DIR/freeapi.db"
export FREEAPI_CONFIG_JSON="{\"admin\":{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}}"

nohup node server/dist/index.js > "$HOME_DIR/server.log" 2>&1 &

for _ in $(seq 1 60); do
  if ready; then
    print_login
    exit 0
  fi
  sleep 1
done
echo "FreeLLMAPI did not start within 60s. Log: $HOME_DIR/server.log" >&2
tail -20 "$HOME_DIR/server.log" >&2 || true
exit 1
