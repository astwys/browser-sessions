# Manual AE Checklist — Browser Sessions v1

Use this checklist for behavior that cannot be fully verified by unit tests: macOS menu bar visibility, live popover updates, confirmation focus, and accessibility spot checks.

## Setup

```bash
cd BrowserSessions
./scripts/build-app-bundle.sh
pkill -x BrowserSessions || true
```

Use `./scripts/run-app.sh` rather than `open` so environment variables are passed through.

## AE1 — Count includes known + process detections

1. Start at least one `agent-browser` session or a Playwright/Puppeteer browser.
2. Run `./scripts/run-app.sh`.
3. Confirm the menu bar count matches rows shown in the popover.

Expected: count equals total rows across all sections.

## AE2 — Three-tier popover

1. Open the menu bar popover.
2. Verify sections exist:
   - agent-browser sessions
   - Playwright and Puppeteer browsers
   - Unconfirmed browsers

Expected: each row shows the browser's app icon and a "launcher · age" subtitle. Hovering a closable row highlights it and shows a ⊗ button left of the chevron; it also shows while the row is expanded. Unconfirmed rows show `view only`, a dimmed icon and no ⊗.

## AE3 / AE10 — Zero-state and hide behavior

```bash
pkill -x BrowserSessions || true
./scripts/run-app.sh
```

Expected: when nothing is detected, no numeric `0` is shown. The menu bar item may be hidden.

Fallback check:

```bash
pkill -x BrowserSessions || true
BROWSER_SESSIONS_FORCE_ZERO_STATE=1 ./scripts/run-app.sh
```

Expected: item remains visible and popover shows “No automation browsers detected”.

## AE4 — Unknown age is acceptable

Inspect Playwright/Puppeteer rows.

Expected: URL/last-change metadata may be unknown in v1. No stale/abandoned label is shown.

## AE5 — Close known agent-browser session

1. Start an `agent-browser` session.
2. Open popover and click `Close` on the known row.
3. Confirm the inline dialog.

Expected: the confirmation stays inside the popover, close runs, a status message appears, and the list refreshes.

## AE6 — Close HIGH process row

1. Create a high-confidence Playwright/Puppeteer browser row.
2. Click `Close`.
3. Confirm.

Expected: copy says SIGTERM goes to this browser after the app checks the PID still belongs to it. The owning Node/test process must remain alive.

## AE7 — LOW rows are inspect-only

Create or observe a LOW row such as Chrome with `--remote-debugging-port=9222` only.

Expected: LOW row is visible, shows `view only`, and has no ⊗ button.

## AE8 — Cancel confirmation

1. Hover a closable row and click its ⊗ button.
2. Click `Cancel` in the inline confirmation.

Expected: only the confirmation panel closes; the popover remains open and no close action runs.

## AE9 — Accessibility spot check

Use VoiceOver or Accessibility Inspector on representative rows.

Expected: row labels name the section (agent-browser session, Playwright or Puppeteer browser, unconfirmed browser), the PID when present, and "can be closed" or "view only". Closable rows offer a "Close" action in the VoiceOver Actions menu (VO-Command-Space), since the ⊗ button is hidden until hover.

## AE11 — Degraded CLI state

Temporarily launch with a PATH that cannot find `agent-browser` while a process row is detectable.

Expected: popover shows a degraded capability banner and still lists process detections.

## AE12 — Last row disappears while popover open

Close or stop the last detected browser while the popover is open.

Expected: within one poll/refresh, count drops to zero and empty state appears without crashing.

## AE13 — Signal classification sanity

Verify examples against expected UI:

- Playwright `--remote-debugging-pipe` → Playwright and Puppeteer section, closable
- Puppeteer cache + `--enable-automation` → Playwright and Puppeteer section, closable
- `--remote-debugging-port=9222` only → Unconfirmed section, view only
- `chrome_crashpad_handler` → not listed
- Renderer/GPU/utility helpers of a listed browser → not listed (one row per browser)
- `chrome-devtools-mcp` Node server → not listed; the Chrome it drives → one HIGH row

## Completion note

Before calling v1 complete, report which AE sections were manually verified and any observed macOS version-specific behavior.
