#!/usr/bin/env bash
# Installs dependencies and builds the server + dashboard from this repo.
set -euo pipefail
cd "$(dirname "$0")/.."

npm ci
npm run build
echo "FreeLLMAPI built."
