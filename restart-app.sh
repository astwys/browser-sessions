#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
"$ROOT/BrowserSessions/scripts/install-app.sh"
pkill -x BrowserSessions || true
open /Applications/BrowserSessions.app
echo "Restarted /Applications/BrowserSessions.app"
