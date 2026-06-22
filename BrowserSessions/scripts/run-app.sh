#!/usr/bin/env bash
# Launch BrowserSessions with env vars that macOS `open` does not forward.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/BrowserSessions.app/Contents/MacOS/BrowserSessions"
if [[ ! -x "$APP" ]]; then
  echo "App bundle missing. Run: ./scripts/build-app-bundle.sh" >&2
  exit 1
fi
echo "Launching BrowserSessions (stub=${BROWSER_SESSIONS_STUB_COUNT:-0}, zeroState=${BROWSER_SESSIONS_FORCE_ZERO_STATE:-0})" >&2
exec "$APP"
