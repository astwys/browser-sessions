#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/BrowserSessions.app"
TARGET="/Applications/BrowserSessions.app"
"$ROOT/scripts/build-app-bundle.sh"
rm -rf "$TARGET"
cp -R "$APP" "$TARGET"
echo "Installed $TARGET"
echo "Launch from Finder, Spotlight, or: open '$TARGET'"
