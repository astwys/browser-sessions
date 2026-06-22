#!/usr/bin/env bash
# Quick manual QA for U1 menu bar visibility.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Building app bundle"
./scripts/build-app-bundle.sh

pkill -x BrowserSessions 2>/dev/null || true

run_case() {
  local name="$1"
  shift
  echo
  echo "==> $name"
  echo "    Command: $*"
  "$@" &
  local pid=$!
  sleep 2
  if kill -0 "$pid" 2>/dev/null; then
    echo "    Process running (pid $pid). Check the right side of your menu bar."
  else
    echo "    ERROR: process exited immediately" >&2
    exit 1
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

run_case "Case A: hidden when empty (no icon expected)" \
  env BROWSER_SESSIONS_DEBUG=1 ./scripts/run-app.sh

run_case "Case B: badge count 3 (globe + 3)" \
  env BROWSER_SESSIONS_DEBUG=1 BROWSER_SESSIONS_STUB_COUNT=3 ./scripts/run-app.sh

run_case "Case C: neutral zero-state (globe, no number)" \
  env BROWSER_SESSIONS_DEBUG=1 BROWSER_SESSIONS_FORCE_ZERO_STATE=1 ./scripts/run-app.sh

echo
echo "Done. If Case B/C did not show a globe icon, check Control Center overflow (>>) in the menu bar."
