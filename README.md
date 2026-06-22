# Browser Sessions

macOS menu bar app to supervise automation browser sessions (`agent-browser`, Playwright, Puppeteer).

## Status

**U1 complete (scaffold):** SwiftPM menu bar shell with polling timer, hide/zero-state binding, and unit tests.

**U2 complete:** `agent-browser` CLI client with `CommandRunner`, JSON parsing, and graceful degradation.

Full Xcode is recommended for day-to-day UI work; this repo builds with Swift Package Manager + an app bundle wrapper (Command Line Tools sufficient for U1).

## Build & run

```bash
cd BrowserSessions
swift run BrowserSessionsTestRunner
./scripts/build-app-bundle.sh
./scripts/run-app.sh
```

Use `./scripts/run-app.sh` (not `open`) so env vars reach the app. With no env vars the icon stays hidden when count is zero — that is expected.

### Manual QA helpers (U1)

macOS `open` does **not** forward environment variables to the app. Use the run script or invoke the binary directly:

```bash
# Default — hidden when empty (no icon expected)
./scripts/run-app.sh

# Badge with stub count
BROWSER_SESSIONS_STUB_COUNT=3 ./scripts/run-app.sh

# Neutral zero-state (dim globe icon, stays visible when empty)
BROWSER_SESSIONS_FORCE_ZERO_STATE=1 ./scripts/run-app.sh
```

To quit a background instance: `pkill -x BrowserSessions`

### Tests

```bash
swift run BrowserSessionsTestRunner
BROWSER_SESSIONS_INTEGRATION=1 swift run BrowserSessionsTestRunner  # requires agent-browser on PATH
```

Run all three visibility cases in sequence:

```bash
./scripts/qa-menu-bar.sh
```

Add `BROWSER_SESSIONS_DEBUG=1` to any launch command to print menu bar state to the terminal.

## Docs

- Requirements: `docs/brainstorms/2026-06-21-automation-browser-menu-bar-requirements.md`
- Plan: `docs/plans/2026-06-21-001-feat-automation-browser-menu-bar-plan.md`

## Dependencies

- macOS 14+
- [`agent-browser`](https://github.com/vercel-labs/agent-browser) (from U2 onward)
