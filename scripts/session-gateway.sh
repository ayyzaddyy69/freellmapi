#!/usr/bin/env bash
# Start FreeLLMAPI inside a Claude cloud session and print how to reach it.
#
# Provider keys are NOT stored here. The session's network layer attaches the
# real key to each provider host, so the server is seeded with placeholders.
# Safe to run repeatedly: an already-running gateway is left alone.
#
#   scripts/session-gateway.sh           start (or confirm) the gateway
#   scripts/session-gateway.sh stop      stop it
#   scripts/session-gateway.sh restart   stop, then start
#
# GATEWAY_PLATFORMS overrides which providers are enabled (space separated).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA="${GATEWAY_DATA_DIR:-$HOME/.freellmapi-session}"
PORT="${GATEWAY_PORT:-3001}"
PLATFORMS="${GATEWAY_PLATFORMS:-groq nvidia openrouter google zhipu}"
URL="http://127.0.0.1:$PORT"
PID_FILE="$DATA/server.pid"
KEY_FILE="$DATA/unified-key"

is_up() { curl -fsS -m 3 "$URL/api/ping" >/dev/null 2>&1; }

stop() {
  if [ -f "$PID_FILE" ] && kill "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Stopped gateway (pid $(cat "$PID_FILE"))."
  else
    echo "Gateway was not running."
  fi
  rm -f "$PID_FILE"
}

case "${1:-start}" in
  stop) stop; exit 0 ;;
  restart) stop; sleep 1 ;;
  start) ;;
  *) echo "usage: $0 [start|stop|restart]" >&2; exit 2 ;;
esac

mkdir -p "$DATA"
chmod 700 "$DATA"

if ! is_up; then
  cd "$ROOT"
  if [ ! -d node_modules ]; then
    echo "Installing dependencies..."
    npm ci --no-audit --no-fund >"$DATA/install.log" 2>&1
  fi
  if [ ! -f server/dist/index.js ]; then
    echo "Building server..."
    npm run build -w server >"$DATA/build.log" 2>&1
  fi

  # Local-only admin account, so the first-run setup window is closed.
  [ -f "$DATA/admin-password" ] || (umask 077; node -e "process.stdout.write(require('crypto').randomBytes(18).toString('base64url'))" >"$DATA/admin-password")
  (umask 077; GATEWAY_PLATFORMS="$PLATFORMS" ADMIN_PW="$(cat "$DATA/admin-password")" node -e '
    // Google is reached through its OpenAI-compatible endpoint, because the
    // session can only attach its key as "Authorization: Bearer" and the
    // native Gemini API wants an x-goog-api-key header instead.
    const GEMINI_MODELS = [
      "gemini-3.8-flash", "gemini-3.7-flash", "gemini-3.6-flash", "gemini-3.5-flash",
      "gemini-3.5-flash-lite", "gemini-3.1-flash-lite", "gemini-3-flash-preview",
      "gemini-flash-latest", "gemini-flash-lite-latest",
      "gemma-4-31b-it", "gemma-4-26b-a4b-it",
    ];
    const names = process.env.GATEWAY_PLATFORMS.split(/\s+/).filter(Boolean);
    const keys = names.filter(n => n !== "google")
      .map(platform => ({ platform, key: "proxy-injected", label: "session" }));
    const customProviders = names.includes("google") ? [{
      baseUrl: "https://generativelanguage.googleapis.com/v1beta/openai",
      apiKey: "proxy-injected",
      label: "Gemini",
      models: GEMINI_MODELS.map(model => ({ model, displayName: model, supportsTools: true })),
    }] : [];
    const admin = { email: "session@localhost.local", password: process.env.ADMIN_PW };
    process.stdout.write(JSON.stringify({ admin, keys, customProviders }, null, 2));
  ' >"$DATA/config.json")

  echo "Starting gateway..."
  FREEAPI_DB_PATH="$DATA/freeapi.db" FREEAPI_CONFIG_PATH="$DATA/config.json" \
    HOST=127.0.0.1 PORT="$PORT" NODE_USE_ENV_PROXY=1 \
    nohup node server/dist/index.js >"$DATA/server.log" 2>&1 &
  echo $! >"$PID_FILE"

  for _ in $(seq 1 40); do is_up && break; sleep 0.5; done
  if ! is_up; then
    echo "Gateway failed to start. Last log lines:" >&2
    tail -n 20 "$DATA/server.log" >&2
    exit 1
  fi

  # Give the first catalog sync a moment so the model list below is current.
  for _ in $(seq 1 30); do
    grep -qE '\[catalog-sync\] (applied|fetch failed|up to date)' "$DATA/server.log" && break
    sleep 0.5
  done
fi

# The unified key belongs to this local server only; keep it in a private file.
(umask 077; cd "$ROOT/server" && DB="$DATA/freeapi.db" node -e '
  const Database = require("better-sqlite3");
  const db = new Database(process.env.DB, { readonly: true });
  const row = db.prepare("SELECT value FROM settings WHERE key = ?").get("unified_api_key");
  process.stdout.write(row.value);
' >"$KEY_FILE")

COUNTS="$(curl -fsS -m 15 -H "Authorization: Bearer $(cat "$KEY_FILE")" "$URL/v1/models" | node -e '
  let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
    const m = JSON.parse(s).data || [];
    console.log(m.filter(x => x.available).length + " of " + m.length + " models available");
  });' 2>/dev/null || echo "model list unavailable")"

cat <<EOF
FreeLLMAPI gateway is running.
  URL:        $URL  (OpenAI-compatible: /v1/models, /v1/chat/completions)
  Key file:   $KEY_FILE
  Providers:  $PLATFORMS
  Models:     $COUNTS
  Log:        $DATA/server.log

Example:
  curl -sS $URL/v1/chat/completions \\
    -H "Authorization: Bearer \$(cat $KEY_FILE)" -H "Content-Type: application/json" \\
    -d '{"model":"auto","messages":[{"role":"user","content":"Hello"}]}'
EOF
