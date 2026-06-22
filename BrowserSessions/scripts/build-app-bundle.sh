#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release
BIN="$ROOT/.build/release/BrowserSessions"
APP="$ROOT/.build/BrowserSessions.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BrowserSessions"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/BrowserSessions"
echo "Built $APP"
echo "Run: ./scripts/run-app.sh"
echo "     BROWSER_SESSIONS_STUB_COUNT=3 ./scripts/run-app.sh"
echo "     BROWSER_SESSIONS_FORCE_ZERO_STATE=1 ./scripts/run-app.sh"
